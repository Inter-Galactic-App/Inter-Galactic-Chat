import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_feature_reactions.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/atoms/emoji_reaction.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_reactions.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Who reacted, fixed. Whether the chip is highlighted is therefore purely a
/// question of which client the widget thinks it is looking at.
const _reactorId = '@second:example.org';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.layoutOverride.set('mobile');
  });

  testWidgets('re-reads the current user when the timeline is replaced', (
    tester,
  ) async {
    // This widget already accepts a replacement timeline, and that comparison
    // is client-agnostic. `currentUserIdentifier` was resolved once in
    // initState, so after a cross-account replacement the chips stayed
    // highlighted for the *previous* user.
    final first = _FakeTimeline(selfId: '@first:example.org');
    final second = _FakeTimeline(selfId: _reactorId);

    Widget subject(Timeline timeline) => MaterialApp(
      home: Scaffold(
        body: TimelineEventViewReactions(index: 0, timeline: timeline),
      ),
    );

    await tester.pumpWidget(subject(first));
    await tester.pump();
    expect(
      tester.widget<EmojiReaction>(find.byType(EmojiReaction)).highlighted,
      isFalse,
      reason: 'the reaction is not from the first account',
    );

    await tester.pumpWidget(subject(second));
    await tester.pump();
    expect(
      tester.widget<EmojiReaction>(find.byType(EmojiReaction)).highlighted,
      isTrue,
      reason: 'kept the replaced timeline client\'s user id',
    );
  });

  testWidgets(
    'rendered content follows the index when only the index changes',
    (tester) async {
      // THE REGRESSION SURFACE OF BUG-298, WHICH WAS UNGUARDED. That refactor
      // replaced imperative GlobalKey-driven updates with didUpdateWidget
      // reacting to an index parameter, changing how EVERY timeline event view
      // refreshes — reactions, URL previews and message updates.
      //
      // Measured during the 2026-08-17 review: deleting the index comparison in
      // didUpdateWidget entirely left all 17 timeline tests GREEN. The suite
      // covered the timeline-replacement path and none of the index path, so a
      // view could go stale against its own event with nothing to catch it.
      //
      // The two events must differ in RENDERED output, not just identity — an
      // assertion on the event object would pass against a stale render.
      final timeline = _FakeTimeline(
        selfId: '@first:example.org',
        timelineEvents: const [
          _FakeReactionEvent(eventId: r'$first'),
          _FakeReactionEvent(
            eventId: r'$second',
            emoticon: _FakeEmoticon(shortcode: 'tada', key: '\u{1F389}'),
          ),
        ],
      );

      Widget subject(int index) => MaterialApp(
        home: Scaffold(
          body: TimelineEventViewReactions(index: index, timeline: timeline),
        ),
      );

      await tester.pumpWidget(subject(0));
      await tester.pump();
      expect(
        tester
            .widget<EmojiReaction>(find.byType(EmojiReaction))
            .emoji
            .shortcode,
        'thumbsup',
        reason: 'the view should render the event at index 0',
      );

      // Same timeline instance, same widget type, same position in the tree —
      // ONLY the index changes. This is exactly the update didUpdateWidget has
      // to react to, and the one nothing was asserting.
      await tester.pumpWidget(subject(1));
      await tester.pump();
      expect(
        tester
            .widget<EmojiReaction>(find.byType(EmojiReaction))
            .emoji
            .shortcode,
        'tada',
        reason:
            'the view kept rendering index 0 after being rebuilt at index 1 — '
            'didUpdateWidget is not reacting to the index change',
      );
    },
  );

  testWidgets('an index past the end of the timeline renders nothing', (
    tester,
  ) async {
    // The other half of setStateFromIndex, and the one a naive fix breaks:
    // clamping or ignoring an out-of-range index would render a neighbouring
    // event instead of nothing, which is a wrong message rather than a blank.
    final timeline = _FakeTimeline(selfId: '@first:example.org');

    Widget subject(int index) => MaterialApp(
      home: Scaffold(
        body: TimelineEventViewReactions(index: index, timeline: timeline),
      ),
    );

    await tester.pumpWidget(subject(0));
    await tester.pump();
    expect(find.byType(EmojiReaction), findsOneWidget);

    await tester.pumpWidget(subject(5));
    await tester.pump();
    expect(
      find.byType(EmojiReaction),
      findsNothing,
      reason: 'an out-of-range index must clear, not keep the previous event',
    );
  });
}

class _FakeEmoticon implements Emoticon {
  const _FakeEmoticon({this.shortcode = 'thumbsup', this.key = '\u{1F44D}'});

  @override
  ImageProvider? get image => null;

  @override
  String get slug => shortcode;

  @override
  final String shortcode;

  @override
  final String key;

  @override
  EmoticonUsage get usage => EmoticonUsage.emoji;

  @override
  bool get isSticker => false;

  @override
  bool get isEmoji => true;
}

class _FakeReactionEvent
    implements TimelineEvent, TimelineEventFeatureReactions {
  const _FakeReactionEvent({
    this.eventId = r'$reacted',
    this.emoticon = const _FakeEmoticon(),
  });

  @override
  final String eventId;

  final Emoticon emoticon;

  @override
  String get senderId => '@alice:example.org';

  @override
  DateTime get originServerTs => DateTime.utc(2026, 8, 17, 10);

  @override
  bool hasReactions(Timeline timeline) => true;

  @override
  Map<Emoticon, Set<String>> getReactions(Timeline timeline) => {
    emoticon: {_reactorId},
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTimeline extends Timeline {
  _FakeTimeline({required String selfId, List<TimelineEvent>? timelineEvents}) {
    room = _FakeRoom(client: _FakeClient(selfId));
    client = room.client;
    events = timelineEvents ?? [const _FakeReactionEvent()];
  }

  @override
  bool get canLoadFuture => false;

  @override
  bool get canLoadHistory => false;

  @override
  bool get isLoadingFuture => false;

  @override
  bool get isLoadingHistory => false;

  @override
  Stream<void> get onLoadingStatusChanged => const Stream<void>.empty();

  @override
  Future<void> close() async {}

  @override
  bool canDeleteEvent(TimelineEvent event) => false;

  @override
  void deleteEvent(TimelineEvent event) {}

  @override
  Future<TimelineEvent?> fetchEventByIdInternal(String eventId) async => null;

  @override
  bool isEventRedacted(TimelineEvent event) => false;

  @override
  Future<void> loadMoreFuture() async {}

  @override
  Future<void> loadMoreHistory() async {}

  @override
  void markAsRead(TimelineEvent event) {}
}

class _FakeRoom implements Room {
  _FakeRoom({required this.client});

  @override
  final Client client;

  @override
  String get identifier => '!room:example.org';

  @override
  Member getMemberOrFallback(String id) => _FakeMember(id);

  @override
  T? getComponent<T extends RoomComponent>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient implements Client {
  _FakeClient(String selfId) : self = _FakeProfile(selfId);

  @override
  final Profile self;

  @override
  String get identifier => 'client-${self.identifier}';

  @override
  T? getComponent<T extends Component>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfile implements Profile {
  const _FakeProfile(this.identifier);

  @override
  final String identifier;

  @override
  String get displayName => identifier;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMember implements Member {
  _FakeMember(this.identifier);

  @override
  final String identifier;

  @override
  String get displayName => identifier;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
