import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/molecules/message_input.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

/// These tests FAIL against current main ON PURPOSE. They are the target for
/// the `onKey` fix, written by DEBUG at the request of FEATURES, who own this
/// file for Composer Bracket Typing And Shortcuts. Do not merge them without
/// the fix - a red suite on main helps nobody.
///
/// THE DEFECT, found while investigating BUG-290 and confirmed independent of
/// it. `message_input.dart`'s `onKey(FocusNode node, KeyEvent event)` never
/// reads `event`. Every branch asks
/// `HardwareKeyboard.instance.isLogicalKeyPressed(...)` - "is this key down
/// RIGHT NOW" - instead of "is this event FOR this key", and nothing gates on
/// `KeyDownEvent`. So the handler fires on key-up and auto-repeat too, and
/// while any shortcut key is held, EVERY other key's event takes that
/// shortcut's branch.
///
/// THE SEMANTICS THESE PIN, agreed with FEATURES:
///   - the TRIGGERING key comes from `event.logicalKey`;
///   - MODIFIERS keep using `HardwareKeyboard` (Ctrl/Shift genuinely are a
///     "currently held" question, and that usage is correct today);
///   - paste and send honour `KeyDownEvent` only;
///   - Tab-cycling through autofill results may also honour `KeyRepeatEvent`.
///
/// WHY THIS FILE HAS TO OVERRIDE THE PLATFORM, and it is very likely the whole
/// reason `onKey` has no coverage today. Its first line is
/// `if (BuildConfig.MOBILE || Layout.mobile) return KeyEventResult.ignored;`.
/// `BuildConfig.MOBILE` resolves from `defaultTargetPlatform`, which in
/// `flutter_test` is `TargetPlatform.android` on EVERY host regardless of the
/// machine - so in a widget test this handler returns on its first line and
/// nothing below it is reachable. A test written without this override passes
/// against any defect in the entire function, because the function never runs.
/// `Layout.mobile` is pinned too, since it reads the same flag.
///
/// WHY EVERY CASE DRIVES THE ARROW-UP BRANCH rather than send or paste. The
/// defect is identical in all of them - it is one missing `event` read - but
/// the branches differ in how honestly they can be observed. `sendMessage()`
/// runs inside `sendDebouncer`, which collapses exactly the rapid repeats
/// these cases generate, so a send-path test would pass against the defect it
/// was written for and prove nothing. The arrow-up branch calls
/// `widget.editLastMessage` directly with no debounce and no state to set up,
/// so a second call means a second wrong routing and nothing else. Pinning the
/// clearest branch is deliberate: the fix is one change and it lands on all of
/// them at once.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
  });

  /// Runs [body] as a desktop composer would run it, and always undoes both
  /// pieces of global state afterwards.
  ///
  /// The platform override CANNOT be undone in `tearDown`: the test binding
  /// verifies that no foundation debug variable is still set at the end of the
  /// test BODY, before tearDown runs, and fails the test with "the value of a
  /// foundation debug variable was changed by the test" - which looks nothing
  /// like a platform problem and hides whatever the assertions actually said.
  /// A key left down is the other half: HardwareKeyboard state is global, so
  /// it would leak into the next case, which is the very staleness this defect
  /// is about.
  Future<void> runDesktop(
    WidgetTester tester,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await body();
    } finally {
      for (final key in HardwareKeyboard.instance.logicalKeysPressed.toList()) {
        await simulateKeyUpEvent(key);
      }
      debugDefaultTargetPlatformOverride = null;
    }
  }

  /// Pumps a composer with an EMPTY text field, which is what the arrow-up
  /// branch requires (`controller.text.isEmpty`), and returns a counter of how
  /// many times the composer decided "the user pressed arrow-up on an empty
  /// composer".
  Future<int Function()> pumpComposer(WidgetTester tester) async {
    var editLastMessageCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
        home: Scaffold(
          body: MessageInput(
            client: _FakeClient(),
            // Unkeyed: no draft is saved or restored, so nothing from another
            // case can put text in the composer and silently disqualify the
            // arrow-up branch.
            draftCacheKey: null,
            editLastMessage: () => editLastMessageCalls++,
          ),
        ),
      ),
    );
    await tester.pump();

    // The handler under test is the composer's own FocusNode callback, so it
    // only runs when that node has focus.
    final focusNode = tester
        .widget<EditableText>(find.byType(EditableText).first)
        .focusNode;
    focusNode.requestFocus();
    await tester.pump();

    return () => editLastMessageCalls;
  }

  testWidgets('a held shortcut key does not hijack another key press', (
    tester,
  ) async {
    await runDesktop(tester, () async {
      final calls = await pumpComposer(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      expect(
        calls(),
        1,
        reason:
            'ARMING: the arrow-up press itself must route here. If this is 0 the '
            'handler is not being reached at all and the assertion below would '
            'pass over a harness fault rather than over the fix.',
      );

      // Arrow-up is still held. This event is for a completely different key and
      // must not be attributed to the arrow-up shortcut.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);

      expect(
        calls(),
        1,
        reason:
            'THE DEFECT: with arrow-up held, `A` takes the arrow-up branch '
            'because the handler asks whether arrow-up is DOWN rather than '
            'whether this EVENT is arrow-up. Every composer keystroke is '
            'mis-routed for as long as any shortcut key is held.',
      );
    });
  });

  testWidgets('a held shortcut key does not hijack another key RELEASE', (
    tester,
  ) async {
    await runDesktop(tester, () async {
      final calls = await pumpComposer(tester);

      // `A` goes down first, so its release is a real event the handler sees
      // while arrow-up happens to be held.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      expect(calls(), 1, reason: 'ARMING: the arrow-up press, as above');

      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);

      expect(
        calls(),
        1,
        reason:
            'a key-up is not a shortcut press. The handler never filters to '
            'KeyDownEvent, so releases route too - which is half of why a lost '
            'key-up can leave the composer permanently mis-routed.',
      );
    });
  });

  testWidgets('auto-repeat does not re-trigger a shortcut', (tester) async {
    await runDesktop(tester, () async {
      final calls = await pumpComposer(tester);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      expect(calls(), 1, reason: 'ARMING: the initial press');

      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowUp);

      expect(
        calls(),
        1,
        reason:
            'holding arrow-up must edit the last message once, not once per '
            'repeat. Editing the last message is idempotent enough to look '
            'harmless here; the same repeat handling reaches the send and paste '
            'branches, where it is not.',
      );
    });
  });
}

class _FakeClient implements Client {
  @override
  final String identifier = '@me:test';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
