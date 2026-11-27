import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/polls/poll_component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_poll.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

const String _question = 'Which orbit?';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.layoutOverride.set('mobile');
  });

  Widget subject({required Timeline timeline, required int index}) {
    return MaterialApp(
      // The layout renders through tiamat atoms, which read ThemeSettings off
      // the theme.
      theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
        body: TimelineEventViewPoll(index: index, timeline: timeline),
      ),
    );
  }

  testWidgets('an index past the end of the timeline renders nothing', (
    tester,
  ) async {
    // The owning entry bumps updateRevision on every room update, so
    // setStateFromIndex runs against an index that was accurate a frame ago.
    // A redaction shrinking the list between the two made the unguarded
    // `events[index]` throw RangeError inside didUpdateWidget.
    //
    // The assertion is deliberately "renders nothing", not "does not throw":
    // an early return that kept the previous render would attach this poll to
    // an event that is no longer in the timeline, which is a wrong message
    // rather than a blank one. Same rule as TimelineEventViewReactions.
    final timeline = _FakeTimeline(events: [const _FakePollEvent()]);

    await tester.pumpWidget(subject(timeline: timeline, index: 0));
    await tester.pump();
    expect(find.text(_question), findsOneWidget);

    await tester.pumpWidget(subject(timeline: timeline, index: 1));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      find.text(_question),
      findsNothing,
      reason: 'an out-of-range index must clear, not keep the previous event',
    );
  });
}

class _FakePollEvent implements TimelineEvent {
  const _FakePollEvent();

  @override
  String get eventId => r'$poll';

  @override
  String get senderId => '@alice:example.org';

  @override
  DateTime get originServerTs => DateTime.utc(2026, 9, 7, 10);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePollComponent implements PollComponent {
  @override
  bool isPollEvent(TimelineEvent event) => true;

  @override
  String getPollQuestion(TimelineEvent event) => _question;

  @override
  int getMaxSelections(TimelineEvent event) => 1;

  @override
  bool shouldShowResults(TimelineEvent event, Timeline timeline) => false;

  @override
  bool isFinished(TimelineEvent event, Timeline timeline) => false;

  @override
  List<PollAnswer> getAllowedPollAnswers(TimelineEvent event) => [
    PollAnswer('a', 'Low'),
    PollAnswer('b', 'High'),
  ];

  @override
  Map<String, Set<String>> getPollResponses(
    Timeline timeline,
    TimelineEvent event,
  ) {
    return {};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTimeline extends Timeline {
  _FakeTimeline({required List<TimelineEvent> events}) {
    room = _FakeRoom(client: _FakeClient());
    client = room.client;
    this.events = events;
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
  _FakeClient() : self = const _FakeProfile('@first:example.org');

  final PollComponent polls = _FakePollComponent();

  @override
  final Profile self;

  @override
  String get identifier => 'client-${self.identifier}';

  /// The view force-unwraps this one, so it has to resolve.
  @override
  T? getComponent<T extends Component>() => polls is T ? polls as T : null;

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
  String get userName => identifier;

  @override
  String? get detail => null;

  @override
  String? get avatarId => null;

  @override
  ImageProvider? get avatar => null;

  @override
  Color get defaultColor => const Color(0xFF534CDD);
}
