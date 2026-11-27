import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/molecules/message_input.dart';
import 'package:intergalactic/utils/autofill_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

/// DEBUG finding, 2026-09-08 (relayed through FEATURES): `onKey` asked only
/// `HardwareKeyboard.instance.isLogicalKeyPressed(...)` - "is this key down
/// right now", global and event-agnostic - instead of "is this EVENT a press
/// of this key". Two consequences, tested at two levels:
///
/// - [isComposerKeyPress] pins the extracted predicate directly: it must
///   reject the wrong key, key-up, and (unless opted in) repeat.
/// - The widget group below drives real key events through a pumped
///   [MessageInput], because the predicate being correct in isolation does
///   not prove `onKey`'s branches call it with the right key or event - a
///   call site can pin the wrong argument to a correct rule just as easily as
///   it can call the wrong rule. 'Tests Must Run Production Order' and the
///   project's own predicate-vs-call-site history are why both levels exist
///   here rather than only the cheaper one.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isComposerKeyPress', () {
    test('a KeyDownEvent for the key is a press', () {
      expect(
        isComposerKeyPress(
          const KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.tab,
            logicalKey: LogicalKeyboardKey.tab,
            timeStamp: Duration.zero,
          ),
          LogicalKeyboardKey.tab,
        ),
        isTrue,
      );
    });

    test('a KeyDownEvent for a DIFFERENT key is not a press', () {
      // This is the tab-hijack reproduction's root cause, pinned directly:
      // the event names a different key entirely, which no amount of "is tab
      // currently held" can excuse.
      expect(
        isComposerKeyPress(
          const KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.keyA,
            logicalKey: LogicalKeyboardKey.keyA,
            timeStamp: Duration.zero,
          ),
          LogicalKeyboardKey.tab,
        ),
        isFalse,
      );
    });

    test('a KeyUpEvent is never a press, key-matched or not', () {
      expect(
        isComposerKeyPress(
          const KeyUpEvent(
            physicalKey: PhysicalKeyboardKey.enter,
            logicalKey: LogicalKeyboardKey.enter,
            timeStamp: Duration.zero,
          ),
          LogicalKeyboardKey.enter,
        ),
        isFalse,
      );
    });

    test('a KeyRepeatEvent is rejected unless repeat is requested', () {
      const event = KeyRepeatEvent(
        physicalKey: PhysicalKeyboardKey.keyV,
        logicalKey: LogicalKeyboardKey.keyV,
        timeStamp: Duration.zero,
      );

      expect(isComposerKeyPress(event, LogicalKeyboardKey.keyV), isFalse);
      expect(
        isComposerKeyPress(event, LogicalKeyboardKey.keyV, repeat: true),
        isTrue,
      );
    });
  });

  group('MessageInput.onKey call sites', () {
    // Direct calls pin the branch decisions without relying on text-input
    // platform-channel effects. The held-Tab case also sends a real key-down
    // so the old global-key-state implementation is exercised.
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await globals.preferences.init();
    });

    // flutter_test defaults defaultTargetPlatform to android, which makes
    // onKey's own `BuildConfig.MOBILE || Layout.mobile` guard short-circuit
    // every case here to `ignored` before reaching any branch under test - a
    // false pass that would hide a real regression, not confirm one. [body]
    // must reset the override itself before returning: flutter_test's
    // end-of-test invariant check runs inside the test's own callback, before
    // either `tearDown` or `addTearDown` callbacks fire, so neither can
    // satisfy it.
    Future<void> withDesktopPlatform(Future<void> Function() body) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    Future<MessageInputState> pumpState(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: const [ThemeSettings()],
          ),
          home: Scaffold(
            body: MessageInput(client: _FakeClient(), draftCacheKey: null),
          ),
        ),
      );
      final state = tester.state<MessageInputState>(find.byType(MessageInput));
      state.textFocus.requestFocus();
      await tester.pump();
      return state;
    }

    // The reproduction as described: holding Tab, then pressing an unrelated
    // key. Against the old `isLogicalKeyPressed` check, the unrelated key's
    // own KeyDownEvent still matched the Tab branch - held state does not
    // distinguish which event this call of onKey is even for - and cycled
    // the autofill selection, swallowing the keystroke as `handled` before it
    // could reach the field. Populating autoFillResults is what makes the
    // Tab branch reachable at all; without it, both old and fixed code return
    // `ignored` regardless of this bug, so an empty list would prove nothing.
    testWidgets(
      'a keystroke for a different key does not take the Tab branch',
      (tester) => withDesktopPlatform(() async {
        final state = await pumpState(tester);
        state.autoFillResults = [AutofillSearchResult('alice', 'alice')];

        await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
        try {
          expect(
            HardwareKeyboard.instance.isLogicalKeyPressed(
              LogicalKeyboardKey.tab,
            ),
            isTrue,
          );
          final selectionBefore = state.autoFillSelection;
          final aResult = state.onKey(
            state.textFocus,
            const KeyDownEvent(
              physicalKey: PhysicalKeyboardKey.keyA,
              logicalKey: LogicalKeyboardKey.keyA,
              timeStamp: Duration.zero,
            ),
          );

          expect(
            aResult,
            KeyEventResult.ignored,
            reason:
                "a keydown for 'a' must not take the Tab branch just because "
                'Tab is still held',
          );
          expect(state.autoFillSelection, selectionBefore);
        } finally {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
        }
      }),
    );

    // Holding Ctrl+V and letting the OS auto-repeat is the ordinary way a
    // paste key repeats on a real keyboard. The old check re-entered the
    // paste branch on every repeat because it never looked at the event type.
    testWidgets(
      'an OS auto-repeat of Ctrl+V does not re-trigger paste',
      (tester) => withDesktopPlatform(() async {
        final state = await pumpState(tester);
        var pasteCalls = 0;
        state.readImageFromClipboardForTesting = () async {
          pasteCalls++;
        };

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        state.onKey(
          state.textFocus,
          const KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.keyV,
            logicalKey: LogicalKeyboardKey.keyV,
            timeStamp: Duration.zero,
          ),
        );
        expect(pasteCalls, 1);

        state.onKey(
          state.textFocus,
          const KeyRepeatEvent(
            physicalKey: PhysicalKeyboardKey.keyV,
            logicalKey: LogicalKeyboardKey.keyV,
            timeStamp: Duration.zero,
          ),
        );
        state.onKey(
          state.textFocus,
          const KeyRepeatEvent(
            physicalKey: PhysicalKeyboardKey.keyV,
            logicalKey: LogicalKeyboardKey.keyV,
            timeStamp: Duration.zero,
          ),
        );

        expect(
          pasteCalls,
          1,
          reason: 'a held Ctrl+V must paste once, not once per OS repeat tick',
        );

        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      }),
    );

    // Enter must not re-send on repeat: a real keyboard can auto-repeat Enter
    // exactly like any other key, and the old check could not tell a repeat
    // from a fresh press. The seam counts calls at the onKey branch itself,
    // rather than through sendMessage's own debounce and text-clearing side
    // effects, which would otherwise mask a true double-send.
    testWidgets(
      'a held Enter does not resend on repeat',
      (tester) => withDesktopPlatform(() async {
        final state = await pumpState(tester);
        var sends = 0;
        state.sendMessageForTesting = () => sends++;
        state.controller.text = 'hello';

        state.onKey(
          state.textFocus,
          const KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.enter,
            logicalKey: LogicalKeyboardKey.enter,
            timeStamp: Duration.zero,
          ),
        );
        expect(sends, 1);

        state.onKey(
          state.textFocus,
          const KeyRepeatEvent(
            physicalKey: PhysicalKeyboardKey.enter,
            logicalKey: LogicalKeyboardKey.enter,
            timeStamp: Duration.zero,
          ),
        );
        state.onKey(
          state.textFocus,
          const KeyRepeatEvent(
            physicalKey: PhysicalKeyboardKey.enter,
            logicalKey: LogicalKeyboardKey.enter,
            timeStamp: Duration.zero,
          ),
        );

        expect(
          sends,
          1,
          reason: 'held Enter must send once, not once per repeat',
        );
      }),
    );
  });
}

class _FakeClient implements Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
