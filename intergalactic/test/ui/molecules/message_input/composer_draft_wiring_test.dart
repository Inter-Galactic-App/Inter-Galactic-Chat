import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_draft.dart';
import 'package:intergalactic/client/permissions.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/molecules/message_input.dart';
import 'package:intergalactic/ui/onboarding/tutorial_anchor.dart';
import 'package:intergalactic/ui/organisms/chat/chat.dart';
import 'package:intergalactic/ui/organisms/chat/chat_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

/// REVIEW finding, 2026-09-06: the draft feature can be turned OFF entirely and
/// the suite stays green.
///
/// Replacing the `draftCacheKey` argument in `chat_view.dart` with a literal
/// `null` disconnects saving and restoring completely, and all 25 tests in this
/// directory still pass - because every one of them drives
/// `ComposerDraftCache.save`/`read` directly and none pumps a `MessageInput`
/// with a key. The cache was well tested; its USE was not tested at all.
///
/// These cases assert on the surface that stops depending on the feature when
/// it is unwired: the composer's own text after a rebuild, and the key rule
/// that decides whether a composer participates at all.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    ComposerDraftCache.clearForTesting();
  });

  Future<void> pumpComposer(
    WidgetTester tester, {
    required String? draftCacheKey,
    Key? key,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
        home: Scaffold(
          body: MessageInput(
            key: key,
            client: _FakeClient(),
            draftCacheKey: draftCacheKey,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  final composerField = find.byType(EditableText).first;

  group('a keyed composer keeps its draft across a rebuild', () {
    // The round trip. Against `draftCacheKey: null` the text comes back empty,
    // which is the disconnection REVIEW demonstrated.
    testWidgets('typed text is restored into a fresh composer', (tester) async {
      await pumpComposer(tester, draftCacheKey: '@me:test:!room:test:room');
      await tester.enterText(composerField, 'half-written thought');
      await tester.pump();

      // Rebuild with a different widget key, so initState runs again on a new
      // State rather than the same one being reused.
      await pumpComposer(
        tester,
        draftCacheKey: '@me:test:!room:test:room',
        key: const ValueKey('rebuilt'),
      );

      expect(
        tester.widget<EditableText>(composerField).controller.text,
        'half-written thought',
        reason: 'a keyed composer must restore what was typed into it',
      );
    });

    testWidgets('typing is what puts the draft in the cache', (tester) async {
      await pumpComposer(tester, draftCacheKey: '@me:test:!room:test:room');
      await tester.enterText(composerField, 'saved by typing');
      await tester.pump();

      expect(
        ComposerDraftCache.read('@me:test:!room:test:room')?.text,
        'saved by typing',
      );
    });

    testWidgets('clearing the composer clears the stored draft', (
      tester,
    ) async {
      await pumpComposer(tester, draftCacheKey: '@me:test:!room:test:room');
      await tester.enterText(composerField, 'about to be sent');
      await tester.pump();
      await tester.enterText(composerField, '');
      await tester.pump();

      expect(ComposerDraftCache.read('@me:test:!room:test:room'), isNull);
    });

    // The other side of the same wire: no key means no participation, which is
    // what a reply, edit or inbound-share composer gets.
    testWidgets('an unkeyed composer restores nothing', (tester) async {
      ComposerDraftCache.save(
        '@me:test:!room:test:room',
        const TextEditingValue(text: 'someone else draft'),
      );

      await pumpComposer(tester, draftCacheKey: null);

      expect(tester.widget<EditableText>(composerField).controller.text, '');
    });

    testWidgets('an unkeyed composer saves nothing', (tester) async {
      await pumpComposer(tester, draftCacheKey: null);
      await tester.enterText(composerField, 'not to be retained');
      await tester.pump();

      expect(ComposerDraftCache.read('@me:test:!room:test:room'), isNull);
    });

    testWidgets('a draft does not leak between rooms', (tester) async {
      await pumpComposer(tester, draftCacheKey: '@me:test:!first:test:room');
      await tester.enterText(composerField, 'for the first room');
      await tester.pump();

      await pumpComposer(
        tester,
        draftCacheKey: '@me:test:!second:test:room',
        key: const ValueKey('second'),
      );

      expect(tester.widget<EditableText>(composerField).controller.text, '');
    });
  });

  // The key rule itself, which decides whether a composer is keyed at all. It
  // was an inline conditional in chat_view.dart and so unreachable from a test.
  group('composerDraftCacheKey', () {
    String? keyFor({
      String? threadId,
      bool isInteraction = false,
      bool hasInboundShareDraft = false,
    }) => composerDraftCacheKey(
      clientId: '@me:test',
      roomId: '!room:test',
      threadId: threadId,
      isInteraction: isInteraction,
      hasInboundShareDraft: hasInboundShareDraft,
    );

    test('an ordinary room composer is keyed by client, room and room', () {
      expect(keyFor(), '@me:test:!room:test:room');
    });

    test('a thread composer is keyed separately from its room', () {
      expect(
        keyFor(threadId: r'$thread:test'),
        r'@me:test:!room:test:$thread:test',
      );
      expect(keyFor(threadId: r'$thread:test'), isNot(keyFor()));
    });

    // Reply and edit borrow the composer for one-off text. Retaining it would
    // restore a quoted message into a later plain composer.
    test('a reply or edit composer is not keyed', () {
      expect(keyFor(isInteraction: true), isNull);
    });

    test('an inbound-share composer is not keyed', () {
      expect(keyFor(hasInboundShareDraft: true), isNull);
    });
  });

  // The integration point, which every case above leaves open. They hand
  // `MessageInput` a `draftCacheKey` themselves, so replacing the argument in
  // `chat_view.dart` with a literal `null` - the exact disconnection REVIEW
  // demonstrated - keeps all of them green. This is the only place the app
  // decides whether a room composer participates in drafts at all.
  //
  // `ChatView.input()` is CONSTRUCTED rather than pumped. The claim is about
  // which key the call site computes; pumping the whole composer would put a
  // real room, timeline, theme and overlay between the defect and the failure,
  // and none of that is what would break.
  group('chat_view wires the room composer to composerDraftCacheKey', () {
    late _FakeChatState state;

    tearDown(() => state.disposeControllers());

    String? keyFromChatView({
      String? threadId,
      EventInteractionType? interactionType,
      InboundShareDraft? inboundShareDraft,
    }) {
      final client = _FakeClient();
      final room = _FakeRoom(client: client);
      state = _FakeChatState(
        room: room,
        chat: Chat(
          room,
          threadId: threadId,
          inboundShareDraft: inboundShareDraft,
        ),
        interactionType: interactionType,
      );

      final anchor = ChatView(state).input() as TutorialAnchor;
      final composer = (anchor.child as ClipRRect).child! as MessageInput;
      return composer.draftCacheKey;
    }

    test('an ordinary room composer is keyed by client and room', () {
      expect(
        keyFromChatView(),
        '@me:test:!room:test:room',
        reason:
            'the room composer is not wired to composerDraftCacheKey, so '
            'drafts are neither saved nor restored anywhere in the app',
      );
    });

    test('a thread composer is keyed by its thread', () {
      expect(
        keyFromChatView(threadId: r'$thread:test'),
        r'@me:test:!room:test:$thread:test',
        reason: 'the thread id is not reaching composerDraftCacheKey',
      );
    });

    test('a reply or edit composer is unkeyed', () {
      expect(
        keyFromChatView(interactionType: EventInteractionType.reply),
        isNull,
      );
      expect(
        keyFromChatView(interactionType: EventInteractionType.edit),
        isNull,
      );
    });

    test('an inbound-share composer is unkeyed', () {
      expect(
        keyFromChatView(inboundShareDraft: _FakeInboundShareDraft()),
        isNull,
      );
    });
  });

  // The privacy half. A draft is plaintext taken out of an encrypted room, and
  // the cache holds it for seven days of process lifetime, so signing an
  // account out has to take its drafts with it. Keys are built through
  // [composerDraftCacheKey] rather than written out, because the removal is a
  // prefix match on that format: a key that stops leading with the client id
  // would make the removal silently clear nothing, and these would still pass
  // against a literal.
  group('ComposerDraftCache.clearForClient', () {
    String keyFor(String clientId, {String? threadId}) => composerDraftCacheKey(
      clientId: clientId,
      roomId: '!room:test',
      threadId: threadId,
      isInteraction: false,
      hasInboundShareDraft: false,
    )!;

    test('drops every draft belonging to the removed account', () {
      final room = keyFor('signedOut');
      final thread = keyFor('signedOut', threadId: r'$thread:test');
      ComposerDraftCache.save(room, const TextEditingValue(text: 'secret'));
      ComposerDraftCache.save(
        thread,
        const TextEditingValue(text: 'also secret'),
      );

      ComposerDraftCache.clearForClient('signedOut');

      expect(ComposerDraftCache.read(room), isNull);
      expect(ComposerDraftCache.read(thread), isNull);
    });

    test('leaves the accounts that are still signed in alone', () {
      final other = keyFor('stillHere');
      ComposerDraftCache.save(other, const TextEditingValue(text: 'keep me'));

      ComposerDraftCache.clearForClient('signedOut');

      expect(ComposerDraftCache.read(other)?.text, 'keep me');
    });

    // The separator is load-bearing: client ids are random strings, so one can
    // be a prefix of another.
    test('does not clear an account whose id merely starts the same', () {
      final longer = keyFor('signedOutToo');
      ComposerDraftCache.save(longer, const TextEditingValue(text: 'keep me'));

      ComposerDraftCache.clearForClient('signedOut');

      expect(ComposerDraftCache.read(longer)?.text, 'keep me');
    });
  });
}

class _FakeClient implements Client {
  @override
  final String identifier = '@me:test';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeRoom implements Room {
  _FakeRoom({required this.client});

  @override
  final Client client;

  @override
  final String identifier = '!room:test';

  @override
  bool get isE2EE => false;

  @override
  Permissions get permissions => _FakePermissions();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakePermissions extends Permissions {
  @override
  bool get canSendMessage => true;
}

/// Enough of [ChatState] for `ChatView.input()` to build its composer.
///
/// Only the members that call site actually reads are supplied; everything
/// else forwards to a null-returning [noSuchMethod], because every remaining
/// `MessageInput` argument is nullable and none of the torn-off callbacks are
/// invoked while the widget is merely being constructed.
class _FakeChatState implements ChatState {
  _FakeChatState({required this.room, required Chat chat, this.interactionType})
    : _chat = chat;

  final Chat _chat;

  @override
  final Room room;

  @override
  EventInteractionType? interactionType;

  @override
  Chat get widget => _chat;

  @override
  String? get threadId => _chat.threadId;

  @override
  bool get isThread => _chat.threadId != null;

  @override
  bool get isBubble => _chat.isBubble;

  @override
  Timeline? get timeline => null;

  @override
  TimelineEvent? interactingEvent;

  @override
  bool processing = false;

  @override
  List<PendingFileAttachment> attachments = List.empty(growable: true);

  @override
  StreamController<void> onFocusMessageInput = StreamController<void>();

  @override
  StreamController<String> setMessageInputText = StreamController<String>();

  void disposeControllers() {
    onFocusMessageInput.close();
    setMessageInputText.close();
  }

  // `State` is `Diagnosticable`, whose `toString` takes a named argument, so
  // `Object.toString` does not satisfy the interface.
  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      '_FakeChatState';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeInboundShareDraft implements InboundShareDraft {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
