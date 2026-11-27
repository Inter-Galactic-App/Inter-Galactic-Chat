import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/client/components/url_preview/url_preview_component.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_url_previews.dart';
import 'package:intergalactic/ui/molecules/url_preview_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

/// The row-refresh contract this view shares with reactions and polls: the
/// owning entry bumps `updateRevision` when the event at an index is replaced
/// in place. These tests exist because the BUG-298 refactor made every child
/// view react to the index alone, and a sender's own link preview - mounted
/// while the message is still `sending` - was never requested afterwards.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.layoutOverride.set('mobile');
    Log.log.clear();
  });

  final previewData = UrlPreviewData(
    Uri.parse('https://example.org/article'),
    siteName: 'Example',
    title: 'An article',
    description: 'Worth a preview',
  );

  Widget subject({
    required Timeline timeline,
    required UrlPreviewComponent component,
    required int revision,
    ValueChanged<bool>? onPreviewVisibilityChanged,
    int index = 0,
  }) => MaterialApp(
    // The preview renders through a tiamat Tile, which reads ThemeSettings
    // off the theme unconditionally.
    theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
    home: Scaffold(
      body: TimelineEventViewUrlPreviews(
        index: index,
        updateRevision: revision,
        timeline: timeline,
        component: component,
        onPreviewVisibilityChanged: onPreviewVisibilityChanged,
      ),
    ),
  );

  testWidgets('requests the preview once the same event has synced', (
    tester,
  ) async {
    final event = _FakeMessageEvent(status: TimelineEventStatus.sending);
    final timeline = _FakeTimeline(events: [event]);
    final component = _FakeUrlPreviewComponent()
      ..fetched[event.eventId] = previewData;

    await tester.pumpWidget(
      subject(timeline: timeline, component: component, revision: 0),
    );
    await tester.pump();
    expect(
      component.previewRequests,
      isEmpty,
      reason: 'a local echo has no server-side event to preview yet',
    );
    expect(find.byType(UrlPreviewWidget), findsNothing);

    // The echo synced. Same index, same timeline - only the event changed,
    // and the entry says so through the revision.
    event.status = TimelineEventStatus.synced;
    await tester.pumpWidget(
      subject(timeline: timeline, component: component, revision: 1),
    );
    await tester.pump();

    expect(
      component.previewRequests,
      [event.eventId],
      reason:
          'the view kept its sending-time decision after the event synced - '
          'didUpdateWidget is not reacting to the revision',
    );
    await tester.pump();
    expect(find.byType(UrlPreviewWidget), findsOneWidget);
    expect(
      tester.widget<UrlPreviewWidget>(find.byType(UrlPreviewWidget)).data,
      same(previewData),
    );
  });

  testWidgets(
    'a revision bump while a request is in flight does not restart it',
    (tester) async {
      // Room updates arrive many times a minute in a busy room, and each one
      // reaches this view as a revision bump. Restarting the request on every
      // bump would discard the result in flight every time, and the preview
      // would never land.
      final event = _FakeMessageEvent(status: TimelineEventStatus.synced);
      final timeline = _FakeTimeline(events: [event]);
      final pending = Completer<UrlPreviewData?>();
      final component = _FakeUrlPreviewComponent()..pending = pending;

      await tester.pumpWidget(
        subject(timeline: timeline, component: component, revision: 0),
      );
      await tester.pump();
      expect(component.previewRequests, [event.eventId]);

      await tester.pumpWidget(
        subject(timeline: timeline, component: component, revision: 1),
      );
      await tester.pump();
      await tester.pumpWidget(
        subject(timeline: timeline, component: component, revision: 2),
      );
      await tester.pump();
      expect(
        component.previewRequests,
        [event.eventId],
        reason: 'two revision bumps must not become two more requests',
      );

      pending.complete(previewData);
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<UrlPreviewWidget>(find.byType(UrlPreviewWidget)).data,
        same(previewData),
        reason: 'the original request\'s result was discarded',
      );
    },
  );

  testWidgets('a rejected request does not wedge the row', (tester) async {
    // refreshSameEvent skips a row while `loading` is set. Without an error
    // handler a rejected getPreview left it set forever, and every later
    // revision bump was ignored. Review finding, 2026-09-02.
    final event = _FakeMessageEvent(status: TimelineEventStatus.synced);
    final timeline = _FakeTimeline(events: [event]);
    final failing = Completer<UrlPreviewData?>();
    final component = _FakeUrlPreviewComponent()..pending = failing;
    final visibilityChanges = <bool>[];

    await tester.pumpWidget(
      subject(
        timeline: timeline,
        component: component,
        revision: 0,
        onPreviewVisibilityChanged: visibilityChanges.add,
      ),
    );
    await tester.pump();
    expect(component.previewRequests, [event.eventId]);

    failing.completeError(StateError('durable cache unavailable'));
    await tester.pump();
    await tester.pump();
    expect(visibilityChanges, [false]);

    component
      ..pending = null
      ..fetched[event.eventId] = previewData;
    await tester.pumpWidget(
      subject(timeline: timeline, component: component, revision: 1),
    );
    await tester.pump();
    expect(
      component.previewRequests,
      [event.eventId, event.eventId],
      reason: 'the failed request left the row marked loading',
    );
    await tester.pump();
    expect(
      tester.widget<UrlPreviewWidget>(find.byType(UrlPreviewWidget)).data,
      same(previewData),
    );
  });

  testWidgets('reports a resolved preview to its parent row', (tester) async {
    final event = _FakeMessageEvent(status: TimelineEventStatus.synced);
    final timeline = _FakeTimeline(events: [event]);
    final pending = Completer<UrlPreviewData?>();
    final component = _FakeUrlPreviewComponent()..pending = pending;
    final visibilityChanges = <bool>[];

    await tester.pumpWidget(
      subject(
        timeline: timeline,
        component: component,
        revision: 0,
        onPreviewVisibilityChanged: visibilityChanges.add,
      ),
    );
    await tester.pump();

    pending.complete(previewData);
    await tester.pump();
    await tester.pump();

    expect(visibilityChanges, [true]);
  });

  testWidgets('a revision bump with unchanged cached data keeps the widget', (
    tester,
  ) async {
    // The preview widget is GlobalKey-keyed so a new preview gets a fresh
    // element. Handing out a fresh key when nothing changed re-inflates the
    // preview image on every room update - which is what dropped images look
    // like - so the State must survive a bump that changes nothing.
    final event = _FakeMessageEvent(status: TimelineEventStatus.synced);
    final timeline = _FakeTimeline(events: [event]);
    final component = _FakeUrlPreviewComponent()
      ..cached[event.eventId] = previewData;

    await tester.pumpWidget(
      subject(timeline: timeline, component: component, revision: 0),
    );
    await tester.pump();
    final before = tester.state(find.byType(UrlPreviewWidget));

    await tester.pumpWidget(
      subject(timeline: timeline, component: component, revision: 1),
    );
    await tester.pump();
    expect(
      tester.state(find.byType(UrlPreviewWidget)),
      same(before),
      reason: 'the preview widget was re-created for an unchanged preview',
    );
    expect(component.previewRequests, isEmpty);
  });

  testWidgets(
    'a failed preview retries once the invalid-cache sentinel expires',
    (tester) async {
      // Owner-reported, 2026-09-11: a link whose preview failed
      // never retried while its row stayed mounted. Mechanism: the failed
      // fetch caches UrlPreviewComponent.invalidPreviewData for a TTL: a
      // revision bump inside that TTL runs refreshSameEvent, which sees the
      // sentinel as non-null cached data and assigns it into `data`. Once the
      // TTL passes, getCachedPreview goes back to null, but refreshSameEvent
      // then saw `data != null` (still the sentinel) and read that as "a
      // preview is on screen, keep it" - so it never called getPreview again.
      // Only a full remount (setStateFromIndex) ever retried.
      //
      // This widget never reads a clock itself - the TTL lives in the real
      // component - so the fake's `cached` map is toggled directly to
      // simulate the two states a real component's cache would produce
      // before and after that TTL expires, rather than injecting one.
      final event = _FakeMessageEvent(status: TimelineEventStatus.synced);
      final timeline = _FakeTimeline(events: [event]);
      final failing = Completer<UrlPreviewData?>();
      final component = _FakeUrlPreviewComponent()..pending = failing;

      await tester.pumpWidget(
        subject(timeline: timeline, component: component, revision: 0),
      );
      await tester.pump();
      expect(component.previewRequests, [event.eventId]);

      // The fetch resolves with no preview - a failure, not an error.
      failing.complete(null);
      component.pending = null;
      await tester.pump();
      await tester.pump();

      // A revision bump inside the invalid-cache TTL: the component's cache
      // now answers with the failure sentinel.
      component.cached[event.eventId] = UrlPreviewComponent.invalidPreviewData;
      await tester.pumpWidget(
        subject(timeline: timeline, component: component, revision: 1),
      );
      await tester.pump();
      expect(
        component.previewRequests,
        [event.eventId],
        reason: 'the sentinel is cached data, so this bump must not retry',
      );

      // The TTL has now passed: the component's cache no longer has
      // anything for this event.
      component.cached.remove(event.eventId);
      await tester.pumpWidget(
        subject(timeline: timeline, component: component, revision: 2),
      );
      await tester.pump();

      expect(
        component.previewRequests,
        [event.eventId, event.eventId],
        reason:
            'the sentinel expiring must let this row try again - a row '
            'holding the failure sentinel is not "a preview is on screen"',
      );
    },
  );

  testWidgets(
    'an image failure that leaves nothing else on the card hides the row '
    'rather than showing a site-name-only card',
    (tester) async {
      // REVIEW, 2026-09-11 (queue row "URL preview: blank TikTok and
      // Instagram cards..."): _withoutPreviewImage rebuilds a preview
      // without its image on a load failure, and nothing checked whether
      // anything was left afterward - a preview that carried only siteName
      // and an image became a card with only siteName, which reads as
      // blank. This event's only content beyond its image is the site
      // name, so stripping the image must hide the row entirely rather
      // than leave that near-empty card on screen.
      final event = _FakeMessageEvent(status: TimelineEventStatus.synced);
      final timeline = _FakeTimeline(events: [event]);
      final component = _FakeUrlPreviewComponent()
        ..cached[event.eventId] = UrlPreviewData(
          Uri.parse('https://example.org/article'),
          siteName: 'Example',
          image: NetworkImage('https://example.org/thumb.jpg'),
        )
        ..imageFailureRefresh = null;

      await tester.pumpWidget(
        subject(timeline: timeline, component: component, revision: 0),
      );
      await tester.pump();
      expect(find.byType(UrlPreviewWidget), findsOneWidget);

      final onImageError = tester
          .widget<UrlPreviewWidget>(find.byType(UrlPreviewWidget))
          .onImageError!;
      onImageError(Object(), StackTrace.empty);
      await tester.pump();
      await tester.pump();

      expect(
        find.byType(UrlPreviewWidget),
        findsNothing,
        reason:
            'siteName alone is not a preview - the row must hide, not '
            'render a card with only a site name',
      );
    },
  );

  testWidgets(
    'an image failure that recovers nothing logs the attempt and the drop',
    (tester) async {
      // The row this covers: before 2026-09-12 an image failure here was
      // entirely silent, so a capture could not say whether a refresh was
      // attempted, nor whether _withoutPreviewImage had reduced a card to
      // the invalid sentinel - the route PR #398 fixed without evidence
      // either way.
      final event = _FakeMessageEvent(status: TimelineEventStatus.synced);
      final timeline = _FakeTimeline(events: [event]);
      final component = _FakeUrlPreviewComponent()
        ..cached[event.eventId] = UrlPreviewData(
          Uri.parse('https://example.org/article'),
          siteName: 'Example',
          image: NetworkImage('https://example.org/thumb.jpg'),
        )
        ..imageFailureRefresh = null;

      await tester.pumpWidget(
        subject(timeline: timeline, component: component, revision: 0),
      );
      await tester.pump();
      tester
          .widget<UrlPreviewWidget>(find.byType(UrlPreviewWidget))
          .onImageError!(Object(), StackTrace.empty);
      await tester.pump();
      await tester.pump();

      final refreshLines = Log.log
          .where((entry) => entry.content.contains('URL preview image refresh'))
          .map((entry) => entry.content)
          .toList();
      // Armed on the list being non-empty: every claim below is about what
      // these lines say, and an empty list would satisfy none of them
      // silently.
      expect(refreshLines, isNotEmpty);
      expect(
        refreshLines.where((line) => line.contains('outcome=started')),
        hasLength(1),
      );
      expect(
        refreshLines.where(
          (line) => line.contains('outcome=failed_no_replacement'),
        ),
        hasLength(1),
      );
      expect(
        refreshLines.where(
          (line) => line.contains('outcome=card_dropped_nothing_survived'),
        ),
        hasLength(1),
        reason:
            'the drop is the whole question this line exists to answer - '
            'whether the site-name-only route ever fires in the field',
      );
      expect(
        refreshLines.every((line) => line.contains('host=example.org')),
        isTrue,
        reason: 'paired with the resolved line by host',
      );
    },
  );

  testWidgets('a repeated failure for the same image says it was skipped, not '
      'that nothing happened', (tester) async {
    final event = _FakeMessageEvent(status: TimelineEventStatus.synced);
    final timeline = _FakeTimeline(events: [event]);
    final component = _FakeUrlPreviewComponent()
      ..cached[event.eventId] = UrlPreviewData(
        Uri.parse('https://example.org/article'),
        siteName: 'Example',
        title: 'An article',
        description: 'Worth a preview',
        image: NetworkImage('https://example.org/thumb.jpg'),
      )
      ..imageFailureRefresh = null;

    await tester.pumpWidget(
      subject(timeline: timeline, component: component, revision: 0),
    );
    await tester.pump();
    final onImageError = tester
        .widget<UrlPreviewWidget>(find.byType(UrlPreviewWidget))
        .onImageError!;
    onImageError(Object(), StackTrace.empty);
    await tester.pump();
    await tester.pump();
    onImageError(Object(), StackTrace.empty);
    await tester.pump();

    expect(
      Log.log
          .where(
            (entry) =>
                entry.content.contains('outcome=skipped_already_attempted'),
          )
          .length,
      1,
      reason:
          'a second failure for an image already refreshed once is '
          'deliberate; unlogged it reads as the refresh never running',
    );
  });

  testWidgets('an index past the end of the timeline renders nothing', (
    tester,
  ) async {
    // The index arrives from the owning entry and is only accurate when it is
    // handed over. `events[index]` was read unguarded, so a list that shrank
    // before this row was rebuilt threw RangeError. Clearing rather than
    // returning early matters: keeping the render would leave a preview
    // attached to a message that is no longer in the timeline.
    final event = _FakeMessageEvent(status: TimelineEventStatus.synced);
    final timeline = _FakeTimeline(events: [event]);
    final component = _FakeUrlPreviewComponent()
      ..cached[event.eventId] = previewData;

    await tester.pumpWidget(
      subject(timeline: timeline, component: component, revision: 0),
    );
    await tester.pump();
    expect(find.byType(UrlPreviewWidget), findsOneWidget);

    await tester.pumpWidget(
      subject(timeline: timeline, component: component, revision: 0, index: 1),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      find.byType(UrlPreviewWidget),
      findsNothing,
      reason: 'an out-of-range index must clear, not keep the previous event',
    );
  });

  testWidgets('a revision bump after the event was removed keeps the row', (
    tester,
  ) async {
    // refreshSameEvent runs on every revision bump, which is many a minute in
    // a busy room, and it read `events[index]` unguarded too. Its contract is
    // the opposite of setStateFromIndex's: same row, same event, so with
    // nothing left to re-read it must leave what is on screen alone rather
    // than blank a row that is about to be rebuilt or removed anyway.
    final event = _FakeMessageEvent(status: TimelineEventStatus.synced);
    final timeline = _FakeTimeline(events: [event]);
    final component = _FakeUrlPreviewComponent()
      ..cached[event.eventId] = previewData;

    await tester.pumpWidget(
      subject(timeline: timeline, component: component, revision: 0),
    );
    await tester.pump();
    expect(find.byType(UrlPreviewWidget), findsOneWidget);

    // The redaction that removes the event lands before this row is rebuilt
    // with a new index - the entry only bumps the revision.
    timeline.events = <TimelineEvent>[];
    await tester.pumpWidget(
      subject(timeline: timeline, component: component, revision: 1),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(UrlPreviewWidget), findsOneWidget);
  });
}

class _FakeUrlPreviewComponent implements UrlPreviewComponent {
  /// Returned by [getCachedPreview].
  final Map<String, UrlPreviewData> cached = {};

  /// Returned by [getPreview] when [pending] is not set.
  final Map<String, UrlPreviewData> fetched = {};

  /// When set, every [getPreview] call returns this future.
  Completer<UrlPreviewData?>? pending;

  final List<String> previewRequests = [];

  /// Returned by [refreshPreviewAfterImageFailure]. Null by default, which
  /// models a refresh that could not recover anything - the caller then
  /// falls back to stripping the image from the data it already had.
  UrlPreviewData? imageFailureRefresh;

  @override
  UrlPreviewData? getCachedPreview(Timeline timeline, TimelineEvent event) =>
      cached[event.eventId];

  @override
  Future<UrlPreviewData?> refreshPreviewAfterImageFailure(
    Timeline timeline,
    TimelineEvent event,
    UrlPreviewData failedData,
  ) async => imageFailureRefresh;

  @override
  Future<UrlPreviewData?> getPreview(Timeline timeline, TimelineEvent event) {
    previewRequests.add(event.eventId);
    final inFlight = pending;
    if (inFlight != null) {
      return inFlight.future;
    }
    return Future.value(fetched[event.eventId]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMessageEvent implements TimelineEvent {
  _FakeMessageEvent({required this.status});

  @override
  TimelineEventStatus status;

  @override
  String get eventId => r'$link-message';

  @override
  String get senderId => '@alice:example.org';

  @override
  DateTime get originServerTs => DateTime.utc(2026, 9, 2, 10);

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
