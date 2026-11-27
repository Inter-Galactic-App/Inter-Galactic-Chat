import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/cache/file_provider.dart';
import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/client/permissions.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/molecules/room_timeline_widget/room_timeline_widget_view.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_attachments.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_message.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_view_entry.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.layoutOverride.set('desktop');
  });

  testWidgets('recreates entry keys when the recent timeline split collapses', (
    tester,
  ) async {
    final room = _FakeRoom(
      identifier: '!room:example.org',
      client: _FakeClient(),
    );
    final timeline = _FakeTimeline(room: room);
    final baseTime = DateTime.utc(2026, 8, 10, 18, 47);
    timeline.events = [
      _FakeImageMessageEvent(
        eventId: r'$newer-image',
        senderId: '@alice:example.org',
        originServerTs: baseTime.add(const Duration(seconds: 1)),
        attachmentName: 'newer.png',
        body: 'newer caption',
      ),
      _FakeImageMessageEvent(
        eventId: r'$older-image',
        senderId: '@alice:example.org',
        originServerTs: baseTime,
        attachmentName: 'older.png',
        body: 'older caption',
      ),
      _FakeImageMessageEvent(
        eventId: r'$oldest-image',
        senderId: '@alice:example.org',
        originServerTs: baseTime.subtract(const Duration(seconds: 1)),
        attachmentName: 'oldest.png',
        body: 'oldest caption',
      ),
      _FakeImageMessageEvent(
        eventId: r'$oldest-image-2',
        senderId: '@alice:example.org',
        originServerTs: baseTime.subtract(const Duration(seconds: 2)),
        attachmentName: 'oldest-2.png',
        body: 'oldest caption two',
      ),
    ];
    final viewKey = GlobalKey<RoomTimelineWidgetViewState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            child: RoomTimelineWidgetView(key: viewKey, timeline: timeline),
          ),
        ),
      ),
    );
    await tester.pump();

    final state = viewKey.currentState!;
    await tester.pump();
    expect(state.recentItemsCount, timeline.events.length);
    state.controller.jumpTo(state.controller.position.maxScrollExtent);
    await tester.pump();
    state.animateAndSnapToBottom();
    await tester.pump();
    final entryKeyDuringSnap = state.eventKeys.first.$1;
    expect(state.recentItemsCount, timeline.events.length);

    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(state.recentItemsCount, 0);
    expect(state.eventKeys.first.$1, isNot(same(entryKeyDuringSnap)));
  });

  testWidgets('refreshes mounted entries when a media event is prepended', (
    tester,
  ) async {
    final room = _FakeRoom(
      identifier: '!room:example.org',
      client: _FakeClient(),
    );
    final timeline = _FakeTimeline(room: room);
    final baseTime = DateTime.utc(2026, 8, 10, 19, 17);
    timeline.events = [
      _FakeImageMessageEvent(
        eventId: r'$existing-media',
        senderId: '@alice:example.org',
        originServerTs: baseTime,
        attachmentName: 'existing.png',
        body: 'existing media caption',
      ),
    ];
    final viewKey = GlobalKey<RoomTimelineWidgetViewState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            child: RoomTimelineWidgetView(key: viewKey, timeline: timeline),
          ),
        ),
      ),
    );
    await tester.pump();

    final state = viewKey.currentState!;
    await tester.pump();
    final existingEntry =
        state.eventKeys.single.$1.currentState as TimelineViewEntryState;
    expect(existingEntry.index, 0);

    timeline.insertEvent(
      0,
      _FakeImageMessageEvent(
        eventId: r'$new-media',
        senderId: '@alice:example.org',
        originServerTs: baseTime.add(const Duration(seconds: 1)),
        attachmentName: 'new.png',
        body: 'new media caption',
      ),
    );
    await tester.pump();

    expect(existingEntry.index, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'refreshes the unchanged photo-stack anchor when an older photo arrives',
    (tester) async {
      final room = _FakeRoom(
        identifier: '!room:example.org',
        client: _FakeClient(),
      );
      final timeline = _FakeTimeline(room: room);
      final baseTime = DateTime.utc(2026, 8, 21, 15, 12);
      timeline.events = [
        _FakeImageMessageEvent(
          eventId: r'$newer-image',
          senderId: '@alice:example.org',
          originServerTs: baseTime.add(const Duration(seconds: 1)),
          attachmentName: 'newer.png',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 500,
              child: RoomTimelineWidgetView(timeline: timeline),
            ),
          ),
        ),
      );
      await tester.pump();

      // The new event is inserted after the existing row, so the existing
      // anchor retains index 0. Its own event did not change, but its derived
      // photo-stack role did: it must rebuild from one image to a two-image
      // stack rather than keep rendering stale single-image state.
      timeline.insertEvent(
        1,
        _FakeImageMessageEvent(
          eventId: r'$older-image',
          senderId: '@alice:example.org',
          originServerTs: baseTime,
          attachmentName: 'older.png',
        ),
      );
      await tester.pump();

      final photoStacks = find.byType(PhotoStackAttachmentView);
      expect(photoStacks, findsOneWidget);
      expect(
        tester.widget<PhotoStackAttachmentView>(photoStacks).items,
        hasLength(2),
      );
    },
  );

  testWidgets(
    'a thread timeline does not claim the room\'s Inbox jump target',
    (tester) async {
      // The Inbox jump registry is keyed by account+room only, and the thread
      // side panel mounts a second RoomTimelineWidgetView for the same account
      // and room while the main timeline is still mounted. If the thread one
      // registers it silently displaces the main one and the jump lands in the
      // thread.
      final room = _FakeRoom(
        identifier: '!room:example.org',
        client: _FakeClient(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 500,
              child: RoomTimelineWidgetView(
                timeline: _FakeTimeline(room: room),
                isThreadTimeline: true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        EventBus.jumpToInboxEvent(
          clientIdentifier: room.client.identifier,
          roomIdentifier: room.identifier,
          eventId: r'$target',
        ),
        isFalse,
        reason: 'a thread timeline registered as the room\'s Inbox jump target',
      );
    },
  );

  testWidgets('an open thread panel does not steal the main timeline\'s jump', (
    tester,
  ) async {
    final room = _FakeRoom(
      identifier: '!room:example.org',
      client: _FakeClient(),
    );
    // Both carry the jump target, so whichever view receives the jump can
    // resolve it locally and the assertion is about *which* view moved rather
    // than about a history fetch.
    List<TimelineEvent> events() => [
      _FakeImageMessageEvent(
        eventId: r'$target',
        senderId: '@alice:example.org',
        originServerTs: DateTime.utc(2026, 8, 17, 9),
        attachmentName: 'target.png',
      ),
    ];
    final mainTimeline = _FakeTimeline(room: room)..events = events();
    final threadTimeline = _FakeTimeline(room: room)..events = events();
    final mainKey = GlobalKey<RoomTimelineWidgetViewState>();
    final threadKey = GlobalKey<RoomTimelineWidgetViewState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              // Mounted first, exactly as the main timeline is.
              Expanded(
                child: SizedBox(
                  height: 500,
                  child: RoomTimelineWidgetView(
                    key: mainKey,
                    timeline: mainTimeline,
                  ),
                ),
              ),
              // The side panel, mounted second, so it is the one that would
              // overwrite the shared account+room key.
              Expanded(
                child: SizedBox(
                  height: 500,
                  child: RoomTimelineWidgetView(
                    key: threadKey,
                    timeline: threadTimeline,
                    isThreadTimeline: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      EventBus.jumpToInboxEvent(
        clientIdentifier: room.client.identifier,
        roomIdentifier: room.identifier,
        eventId: r'$target',
      ),
      isTrue,
    );
    await tester.pump();

    expect(
      mainKey.currentState!.highlightedEventId,
      r'$target',
      reason: 'the Inbox jump did not reach the main timeline',
    );
    expect(
      threadKey.currentState!.highlightedEventId,
      isNull,
      reason: 'the Inbox jump was delivered to the thread timeline',
    );
  });

  testWidgets('keeps history loader visible during decrypt recovery', (
    tester,
  ) async {
    final timeline = _FakeTimeline(
      room: _FakeRoom(identifier: '!room:example.org', client: _FakeClient()),
    );
    final viewKey = GlobalKey<RoomTimelineWidgetViewState>();
    final recoveryCompleter = Completer<bool>();
    var recoveryCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            child: RoomTimelineWidgetView(
              key: viewKey,
              timeline: timeline,
              onHistoryPageLoaded: (_) {
                recoveryCalls++;
                return recoveryCompleter.future;
              },
            ),
          ),
        ),
      ),
    );

    final loadFuture = viewKey.currentState!.loadMoreHistory();
    await tester.pump();

    expect(timeline.loadMoreHistoryCount, 1);
    expect(recoveryCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    recoveryCompleter.complete(true);
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(
      RoomTimelineWidgetViewState.historyDecryptRecoveryMinLoaderDuration,
    );
    await loadFuture;
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
    'releases superseded event-context timelines without replacing the room timeline',
    (tester) async {
      final room = _JumpTrackingRoom(
        identifier: '!room:example.org',
        client: _FakeClient(),
      );
      final initialTimeline = _FakeTimeline(room: room);
      initialTimeline.events = [_jumpEvent(r'$initial')];
      final viewKey = GlobalKey<RoomTimelineWidgetViewState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 500,
              child: RoomTimelineWidgetView(
                key: viewKey,
                timeline: initialTimeline,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      for (final eventId in [r'$first', r'$second', r'$third']) {
        viewKey.currentState!.jumpToEvent(eventId);
        await tester.pump();
      }

      expect(room.eventContextTimelines, hasLength(3));
      expect(initialTimeline.closeCount, 0);
      expect(room.eventContextTimelines[0].closeCount, 1);
      expect(room.eventContextTimelines[1].closeCount, 1);
      expect(room.eventContextTimelines[2].closeCount, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(room.eventContextTimelines[2].closeCount, 1);
    },
  );

  testWidgets('snap to bottom releases the owned event-context timeline', (
    tester,
  ) async {
    final room = _JumpTrackingRoom(
      identifier: '!room:example.org',
      client: _FakeClient(),
    );
    final roomTimeline = _FakeTimeline(room: room);
    roomTimeline.events = [_jumpEvent(r'$initial')];
    final viewKey = GlobalKey<RoomTimelineWidgetViewState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            child: RoomTimelineWidgetView(key: viewKey, timeline: roomTimeline),
          ),
        ),
      ),
    );
    await tester.pump();

    viewKey.currentState!.jumpToEvent(r'$older');
    await tester.pump();
    expect(room.eventContextTimelines, hasLength(1));
    expect(room.eventContextTimelines.single.closeCount, 0);

    viewKey.currentState!.animateAndSnapToBottom();
    await tester.pump();

    expect(viewKey.currentState!.timeline, same(roomTimeline));
    expect(room.eventContextTimelines.single.closeCount, 1);
    expect(roomTimeline.closeCount, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(room.eventContextTimelines.single.closeCount, 1);
  });

  testWidgets('failed event-context lookup clears the loading overlay', (
    tester,
  ) async {
    final room = _FailingJumpRoom(
      identifier: '!room:example.org',
      client: _FakeClient(),
    );
    final timeline = _FakeTimeline(room: room);
    timeline.events = [_jumpEvent(r'$initial')];
    final viewKey = GlobalKey<RoomTimelineWidgetViewState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            child: RoomTimelineWidgetView(key: viewKey, timeline: timeline),
          ),
        ),
      ),
    );
    await tester.pump();

    viewKey.currentState!.jumpToEvent(r'$missing');
    await tester.pump();

    expect(viewKey.currentState!.loading, isFalse);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(timeline.closeCount, 0);
  });

  testWidgets(
    'runs history recovery against the timeline that loaded history',
    (tester) async {
      final loadMoreCompleter = Completer<void>();
      final timelineA = _FakeTimeline(
        room: _FakeRoom(
          identifier: '!room-a:example.org',
          client: _FakeClient(),
        ),
        loadMoreHistoryCompleter: loadMoreCompleter,
      );
      final timelineB = _FakeTimeline(
        room: _FakeRoom(
          identifier: '!room-b:example.org',
          client: _FakeClient(),
        ),
      );
      final viewKey = GlobalKey<RoomTimelineWidgetViewState>();
      final recoveryTimelines = <Timeline>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 500,
              child: RoomTimelineWidgetView(
                key: viewKey,
                timeline: timelineA,
                onHistoryPageLoaded: (timeline) async {
                  recoveryTimelines.add(timeline);
                  return false;
                },
              ),
            ),
          ),
        ),
      );

      final loadFuture = viewKey.currentState!.loadMoreHistory();
      await tester.pump();
      viewKey.currentState!.initFromTimeline(timelineB);
      loadMoreCompleter.complete();
      await loadFuture;

      expect(recoveryTimelines, [same(timelineA)]);
    },
  );

  testWidgets(
    'renders image stack grouping when room media previews are disabled',
    (tester) async {
      final room = _FakeRoom(
        identifier: '!room:example.org',
        client: _FakeClient(),
      );
      final timeline = _FakeTimeline(room: room);
      final baseTime = DateTime.utc(2026, 7, 5, 12);
      timeline.events = [
        _FakeImageMessageEvent(
          eventId: r'$image-2',
          senderId: '@alice:example.org',
          originServerTs: baseTime.add(const Duration(seconds: 20)),
          attachmentName: 'second.png',
        ),
        _FakeImageMessageEvent(
          eventId: r'$image-1',
          senderId: '@alice:example.org',
          originServerTs: baseTime,
          attachmentName: 'first.png',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: TimelineEventViewMessage(
                timeline: timeline,
                index: 0,
                previewMedia: room.shouldPreviewMedia,
              ),
            ),
          ),
        ),
      );

      expect(room.shouldPreviewMedia, isFalse);
      expect(find.byType(PhotoStackAttachmentView), findsOneWidget);
      expect(find.text('2 photos'), findsOneWidget);
      expect(find.byIcon(Icons.image_not_supported_outlined), findsWidgets);
      expect(find.byType(Image), findsNothing);
    },
  );

  testWidgets('renders image stack grouping for generated image bodies', (
    tester,
  ) async {
    final room = _FakeRoom(
      identifier: '!room:example.org',
      client: _FakeClient(),
    );
    final timeline = _FakeTimeline(room: room);
    final baseTime = DateTime.utc(2026, 7, 5, 12);
    timeline.events = [
      _FakeImageMessageEvent(
        eventId: r'$image-2',
        senderId: '@alice:example.org',
        originServerTs: baseTime.add(const Duration(seconds: 20)),
        attachmentName: 'processed-second.png',
        body: 'second.png',
      ),
      _FakeImageMessageEvent(
        eventId: r'$image-1',
        senderId: '@alice:example.org',
        originServerTs: baseTime,
        attachmentName: 'processed-first.png',
        body: 'first.png',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: TimelineEventViewMessage(
              timeline: timeline,
              index: 0,
              previewMedia: true,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(PhotoStackAttachmentView), findsOneWidget);
    expect(find.text('2 photos'), findsOneWidget);
  });

  testWidgets(
    'hides video metadata header for bubble messages without a custom color',
    (tester) async {
      await globals.preferences.bubbleMessages.set(true);
      final room = _FakeRoom(
        identifier: '!room:example.org',
        client: _FakeClient(),
      );
      final timeline = _FakeTimeline(room: room);
      timeline.events = [
        _FakeVideoMessageEvent(
          eventId: r'$video',
          senderId: '@alice:example.org',
          originServerTs: DateTime.utc(2026, 8, 10, 20),
          attachmentName: 'clip.mp4',
          body: 'video caption',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: TimelineEventViewMessage(
                timeline: timeline,
                index: 0,
                previewMedia: true,
              ),
            ),
          ),
        ),
      );

      expect(find.textContaining('Video'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hides image stack child messages when previews are enabled', (
    tester,
  ) async {
    final room = _FakeRoom(
      identifier: '!room:example.org',
      client: _FakeClient(),
    );
    final timeline = _FakeTimeline(room: room);
    final baseTime = DateTime.utc(2026, 7, 5, 12);
    timeline.events = [
      _FakeImageMessageEvent(
        eventId: r'$image-2',
        senderId: '@alice:example.org',
        originServerTs: baseTime.add(const Duration(seconds: 20)),
        attachmentName: 'second.png',
      ),
      _FakeImageMessageEvent(
        eventId: r'$image-1',
        senderId: '@alice:example.org',
        originServerTs: baseTime,
        attachmentName: 'first.png',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: Column(
              children: [
                TimelineEventViewMessage(
                  timeline: timeline,
                  index: 0,
                  previewMedia: true,
                ),
                TimelineEventViewMessage(
                  timeline: timeline,
                  index: 1,
                  previewMedia: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byType(PhotoStackAttachmentView), findsOneWidget);
    expect(find.text('2 photos'), findsOneWidget);
    expect(find.byType(TimelineEventViewAttachments), findsNothing);
  });

  testWidgets('hides image stack child messages when previews are disabled', (
    tester,
  ) async {
    final room = _FakeRoom(
      identifier: '!room:example.org',
      client: _FakeClient(),
    );
    final timeline = _FakeTimeline(room: room);
    final baseTime = DateTime.utc(2026, 7, 5, 12);
    timeline.events = [
      _FakeImageMessageEvent(
        eventId: r'$image-2',
        senderId: '@alice:example.org',
        originServerTs: baseTime.add(const Duration(seconds: 20)),
        attachmentName: 'second.png',
      ),
      _FakeImageMessageEvent(
        eventId: r'$image-1',
        senderId: '@alice:example.org',
        originServerTs: baseTime,
        attachmentName: 'first.png',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: Column(
              children: [
                TimelineEventViewMessage(
                  timeline: timeline,
                  index: 0,
                  previewMedia: false,
                ),
                TimelineEventViewMessage(
                  timeline: timeline,
                  index: 1,
                  previewMedia: false,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // The non-anchor child stays hidden in the previews-disabled branch too.
    expect(find.byType(PhotoStackAttachmentView), findsOneWidget);
    expect(find.text('2 photos'), findsOneWidget);
    expect(find.byType(TimelineEventViewAttachments), findsNothing);
  });

  testWidgets('keeps captioned image messages out of image stack grouping', (
    tester,
  ) async {
    final room = _FakeRoom(
      identifier: '!room:example.org',
      client: _FakeClient(),
    );
    final timeline = _FakeTimeline(room: room);
    final baseTime = DateTime.utc(2026, 7, 5, 12);
    timeline.events = [
      _FakeImageMessageEvent(
        eventId: r'$image-2',
        senderId: '@alice:example.org',
        originServerTs: baseTime.add(const Duration(seconds: 20)),
        attachmentName: 'second.png',
        body: 'second caption',
      ),
      _FakeImageMessageEvent(
        eventId: r'$image-1',
        senderId: '@alice:example.org',
        originServerTs: baseTime,
        attachmentName: 'first.png',
        body: 'first caption',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: TimelineEventViewMessage(
              timeline: timeline,
              index: 0,
              previewMedia: true,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(PhotoStackAttachmentView), findsNothing);
    expect(find.text('2 photos'), findsNothing);
  });

  // Regression for the call-room chat defect: pagination is driven by SCROLL
  // EXTENT, but an event that classifies as `hidden` renders `Container()` and
  // contributes zero height. In a call room the timeline is dominated by
  // `org.matrix.msc3401.call.member`, republished every 25s per participant, and
  // every one of those is hidden.
  //
  // The loop is self-driving and needs no user scrolling: loadMoreHistory()'s
  // `finally` posts `onScroll()` to the next frame, which re-tests the boundary,
  // which calls loadMoreHistory() again. One network fetch per frame, forever,
  // while the visible list never grows.
  //
  // The guard at `onScroll()` only special-cases `historyItemsCount == 0`. One
  // hidden event makes the count non-zero, so the flat 500px threshold is used
  // and zero-height children can never beat it.
  //
  // See docs/audit/voip-room-rebuild-storm-and-call-chat-architecture-2026-08-21.md
  testWidgets('does not paginate forever when fetched events have no height', (
    tester,
  ) async {
    final room = _FakeRoom(
      identifier: '!call:example.org',
      client: _FakeClient(),
    );
    final timeline = _EndlessHiddenTimeline(room: room);
    // Seeded before the view exists, so no listener is attached yet.
    timeline.appendHiddenEvents(20, notify: false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            child: RoomTimelineWidgetView(timeline: timeline),
          ),
        ),
      ),
    );

    // Each frame gives the post-frame onScroll() a chance to re-enter.
    for (var i = 0; i < 30; i++) {
      await tester.pump();
    }

    // The assertion is deliberately generous. The point is not the exact
    // number, it is that the count must not track the frame count.
    expect(
      timeline.loadMoreHistoryCount,
      lessThan(5),
      reason:
          'loadMoreHistory ran ${timeline.loadMoreHistoryCount} times across 30 '
          'frames. Hidden events add no scroll extent, so the history boundary '
          'stays true and each load posts another. This is the call-room chat '
          'symptom: the loader flickers, no old message ever appears, and the '
          'fetching never stops',
    );
  });

  // The other half of the circuit breaker. Stopping the runaway is only
  // correct if the user can still reach older history afterwards, and the
  // re-arm originally required `ScrollStartNotification.dragDetails`.
  //
  // Only a drag-backed activity attaches those. `ScrollPosition.pointerScroll`
  // - the mouse wheel path - calls `didStartScroll()` on an idle activity, so
  // its notification carries none. The breaker therefore latched forever for
  // wheel users, on the very platform the runaway was reported on. Owner smoke
  // test 2026-08-21: the runaway stopped and older messages never loaded.
  testWidgets('a mouse wheel re-arms history loading after the breaker trips', (
    tester,
  ) async {
    final room = _FakeRoom(
      identifier: '!call:example.org',
      client: _FakeClient(),
    );
    final timeline = _EndlessHiddenTimeline(room: room);
    timeline.appendHiddenEvents(20, notify: false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            child: RoomTimelineWidgetView(timeline: timeline),
          ),
        ),
      ),
    );

    for (var i = 0; i < 30; i++) {
      await tester.pump();
    }

    final trippedAt = timeline.loadMoreHistoryCount;
    expect(
      trippedAt,
      lessThan(5),
      reason: 'precondition: the breaker must have tripped before we re-arm it',
    );

    // A wheel produces a ScrollStartNotification whose dragDetails is null -
    // that is the whole distinction the old guard got wrong - so the
    // notification is raised directly here.
    //
    // Limit of this test, stated rather than implied: it exercises the
    // notification contract, not the full pointer -> ScrollPosition -> notification
    // chain. It cannot, because these fake events are zero-height, so the list
    // has no scroll extent and `ScrollPosition.pointerScroll` returns early
    // without notifying. That early return is itself a real residual - see the
    // boundary note in the fix commit.
    final scrollableContext = tester.element(find.byType(Scrollable).first);
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    ScrollStartNotification(
      metrics: position.copyWith(),
      context: scrollableContext,
    ).dispatch(scrollableContext);

    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }

    expect(
      timeline.loadMoreHistoryCount,
      greaterThan(trippedAt),
      reason:
          'after the breaker tripped, a scroll start with no dragDetails - what '
          'a mouse wheel raises - must resume automatic history loading. It did '
          'not, so older history is unreachable for anyone not using a touch drag',
    );
  });

  // The raw-pointer path, which the test above cannot reach.
  //
  // These fake events are zero-height, so the list has no scroll range at all -
  // and that is precisely when ScrollPosition.pointerScroll clamps its target
  // to the current pixels and returns without dispatching any notification. So
  // the Listener on the raw PointerScrollEvent is the ONLY path that can
  // re-arm here, which also makes this the case a notification-based test can
  // never cover.
  //
  // Direction matters and is easy to invert: the list is `reverse: true`, and
  // Scrollable negates the raw delta for a reversed axis, so NEGATIVE dy is
  // what scrolls back through history.
  testWidgets('a raw wheel event re-arms when there is no scroll range', (
    tester,
  ) async {
    final room = _FakeRoom(
      identifier: '!call:example.org',
      client: _FakeClient(),
    );
    final timeline = _EndlessHiddenTimeline(room: room);
    timeline.appendHiddenEvents(20, notify: false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            child: RoomTimelineWidgetView(timeline: timeline),
          ),
        ),
      ),
    );

    for (var i = 0; i < 30; i++) {
      await tester.pump();
    }

    final trippedAt = timeline.loadMoreHistoryCount;
    expect(
      trippedAt,
      lessThan(5),
      reason: 'precondition: the breaker must have tripped before we re-arm it',
    );

    final center = tester.getCenter(find.byType(CustomScrollView).first);
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(center));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -80)));
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }

    expect(
      timeline.loadMoreHistoryCount,
      greaterThan(trippedAt),
      reason:
          'a wheel scrolled toward history must resume loading even with no '
          'scroll range. If this fails the direction check is inverted, or the '
          'raw pointer signal is not being observed at all',
    );
  });

  // Counting displayable rows as progress must not count the RECENT end.
  //
  // A live message arriving while a history page is in flight would otherwise
  // look like history progress and reset the breaker on a page that fetched
  // nothing but hidden events. An active call room produces exactly that
  // traffic, so the wider count would defeat the breaker in the one case it
  // exists for.
  testWidgets('live messages during a hidden history load do not re-arm', (
    tester,
  ) async {
    final room = _FakeRoom(
      identifier: '!call:example.org',
      client: _FakeClient(),
    );
    final timeline = _EndlessHiddenTimeline(room: room)
      ..injectLiveEventPerLoad = true;
    timeline.appendHiddenEvents(20, notify: false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            child: RoomTimelineWidgetView(timeline: timeline),
          ),
        ),
      ),
    );

    for (var i = 0; i < 30; i++) {
      await tester.pump();
    }

    expect(
      timeline.loadMoreHistoryCount,
      lessThan(5),
      reason:
          'the breaker must still stop after ${timeline.loadMoreHistoryCount} '
          'loads. Every page returned only hidden events; the visible ones '
          'arrived at the recent end and are not history progress',
    );
  });
}

class _FakeClient implements Client {
  @override
  Profile? self = const _FakeProfile('@self:example.org');

  @override
  String get identifier => 'fake-client';

  @override
  bool get supportsE2EE => true;

  @override
  T? getComponent<T extends Component>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRoom implements Room {
  _FakeRoom({required this.identifier, required this.client});

  @override
  final String identifier;

  @override
  final Client client;

  @override
  String get localId => '${client.identifier}:$identifier';

  @override
  bool get shouldPreviewMedia => false;

  @override
  Stream<void> get onUpdate => const Stream<void>.empty();

  @override
  Permissions get permissions => _FakePermissions();

  @override
  T? getComponent<T extends RoomComponent>() => null;

  @override
  Member getMemberOrFallback(String id) => _FakeMember(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _JumpTrackingRoom extends _FakeRoom {
  _JumpTrackingRoom({required super.identifier, required super.client});

  final eventContextTimelines = <_FakeTimeline>[];

  @override
  Future<RoomTimelineLease> getTimelineForEventContext(
    String contextEventId,
  ) async {
    final timeline = _FakeTimeline(room: this);
    timeline.events = [_jumpEvent(contextEventId)];
    eventContextTimelines.add(timeline);
    return RoomTimelineLease.owned(timeline);
  }
}

class _FailingJumpRoom extends _FakeRoom {
  _FailingJumpRoom({required super.identifier, required super.client});

  @override
  Future<RoomTimelineLease> getTimelineForEventContext(String eventId) async {
    throw StateError('context unavailable');
  }
}

class _FakePermissions extends Permissions {}

class _FakeTimeline extends Timeline {
  _FakeTimeline({required Room room, this.loadMoreHistoryCompleter}) {
    this.room = room;
    client = room.client;
    events = List<TimelineEvent>.empty(growable: true);
  }

  int loadMoreHistoryCount = 0;
  int closeCount = 0;
  final Completer<void>? loadMoreHistoryCompleter;

  @override
  bool get canLoadFuture => false;

  @override
  bool get canLoadHistory => loadMoreHistoryCount == 0;

  @override
  bool get isLoadingFuture => false;

  @override
  bool get isLoadingHistory => false;

  @override
  Stream<void> get onLoadingStatusChanged => const Stream<void>.empty();

  @override
  Future<void> close() async {
    closeCount++;
  }

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
  Future<void> loadMoreHistory() async {
    loadMoreHistoryCount++;
    await loadMoreHistoryCompleter?.future;
  }

  @override
  void markAsRead(TimelineEvent event) {}
}

_FakeImageMessageEvent _jumpEvent(String eventId) => _FakeImageMessageEvent(
  eventId: eventId,
  senderId: '@alice:example.org',
  originServerTs: DateTime.utc(2026, 9, 23),
  attachmentName: 'timeline.png',
);

class _FakeMember implements Member {
  const _FakeMember(this.identifier);

  @override
  final String identifier;

  @override
  String get userName => identifier;

  @override
  String get displayName => 'Alice';

  @override
  String? get detail => null;

  @override
  String? get avatarId => null;

  @override
  ImageProvider? get avatar => null;

  @override
  Color get defaultColor => Colors.teal;
}

class _FakeProfile implements Profile {
  const _FakeProfile(this.identifier);

  @override
  final String identifier;

  @override
  String get userName => identifier;

  @override
  String get displayName => 'Self';

  @override
  String? get detail => null;

  @override
  ImageProvider? get avatar => null;

  @override
  ImageProvider? get banner => null;

  @override
  Color get defaultColor => Colors.blue;

  @override
  String get source => '{}';
}

class _FakeImageMessageEvent implements TimelineEventMessage {
  _FakeImageMessageEvent({
    required this.eventId,
    required this.senderId,
    required this.originServerTs,
    required String attachmentName,
    String? body,
  }) : _attachmentName = attachmentName,
       _body = body ?? attachmentName;

  final String _attachmentName;
  final String _body;

  @override
  final String eventId;

  @override
  final String senderId;

  @override
  final DateTime originServerTs;

  @override
  TimelineEventStatus get status => TimelineEventStatus.synced;

  @override
  String get plainTextBody => _body;

  @override
  String get source => '{}';

  @override
  bool get editable => false;

  @override
  String? get body => _body;

  @override
  String? get bodyFormat => null;

  @override
  String? get formattedBody => null;

  @override
  List<Attachment>? get attachments => [
    ImageAttachment(
      MemoryImage(_transparentPng),
      _FakeFileProvider(_attachmentName),
      name: _attachmentName,
      mimeType: 'image/png',
      fileSize: _transparentPng.length,
      width: 1,
      height: 1,
    ),
  ];

  @override
  Widget? buildFormattedContent({Timeline? timeline}) => null;

  @override
  String getPlaintextBody(Timeline timeline) => plainTextBody;

  @override
  bool isEdited(Timeline timeline) => false;

  @override
  List<Uri>? getLinks({Timeline? timeline}) => const [];
}

class _FakeVideoMessageEvent extends _FakeImageMessageEvent {
  _FakeVideoMessageEvent({
    required super.eventId,
    required super.senderId,
    required super.originServerTs,
    required super.attachmentName,
    super.body,
  });

  @override
  List<Attachment>? get attachments => [
    VideoAttachment(
      _FakeFileProvider(_attachmentName),
      name: _attachmentName,
      mimeType: 'video/mp4',
      fileSize: 10842275,
      width: 9,
      height: 16,
    ),
  ];
}

class _FakeFileProvider implements FileProvider {
  const _FakeFileProvider(this.fileIdentifier);

  @override
  final String fileIdentifier;

  @override
  Stream<DownloadProgress>? get onProgressChanged => null;

  @override
  Future<Uint8List?> getFileData() async => _transparentPng;

  @override
  Future<Uri?> resolve() async => Uri.parse('memory:$fileIdentifier');

  @override
  Future<void> save(String filepath) async {}
}

final _transparentPng = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

/// An event that `eventToDisplayType` cannot classify, so it renders as a
/// zero-height `Container()`. `org.matrix.msc3401.call.member` behaves exactly
/// this way: it is absent from the switch in `matrix_room.dart`, so it becomes
/// an unknown event and falls through to `hidden`.
class _HiddenEvent implements TimelineEvent {
  _HiddenEvent({required this.eventId, required this.originServerTs});

  @override
  final String eventId;

  @override
  final DateTime originServerTs;

  @override
  String get senderId => '@alice:example.org';

  @override
  TimelineEventStatus get status => TimelineEventStatus.synced;

  @override
  String get plainTextBody => '';

  @override
  String get source => '{}';

  @override
  bool get editable => false;
}

/// Renders as a message rather than falling through to `hidden`, so it counts
/// as a displayable row.
class _VisibleEvent extends _HiddenEvent implements TimelineEventMessage {
  _VisibleEvent({required super.eventId, required super.originServerTs});

  @override
  String get plainTextBody => 'visible';

  @override
  String? get body => 'visible';

  @override
  String? get bodyFormat => null;

  @override
  String? get formattedBody => null;

  @override
  List<Attachment>? get attachments => null;

  @override
  String getPlaintextBody(Timeline timeline) => 'visible';

  @override
  Widget? buildFormattedContent({Timeline? timeline}) => null;

  @override
  bool isEdited(Timeline timeline) => false;

  @override
  List<Uri>? getLinks({Timeline? timeline}) => null;
}

/// A server that always has more history and only ever returns hidden events.
class _EndlessHiddenTimeline extends _FakeTimeline {
  _EndlessHiddenTimeline({required super.room});

  var _seq = 0;

  /// Appends at the history end and notifies, the way a real paginated fetch
  /// does. Mutating `events` without firing `onEventAdded` desynchronises the
  /// view's `eventKeys` and throws a RangeError mid-build, which is a harness
  /// artefact rather than the defect under test.
  void appendHiddenEvents(int count, {bool notify = true}) {
    for (var i = 0; i < count; i++) {
      _seq++;
      events.add(
        _HiddenEvent(
          eventId: '\$hidden-$_seq',
          originServerTs: DateTime.utc(
            2026,
            8,
            21,
          ).subtract(Duration(seconds: _seq)),
        ),
      );
      if (notify) {
        onEventAdded.add(events.length - 1);
      }
    }
  }

  @override
  bool get canLoadHistory => true;

  /// Simulates a live message arriving while a history page is in flight, the
  /// way an active call room does. Inserted at index 0 - the recent end - and
  /// `recentItemsCount` moves with it, so it is NOT history progress.
  bool injectLiveEventPerLoad = false;

  @override
  Future<void> loadMoreHistory() async {
    loadMoreHistoryCount++;
    if (injectLiveEventPerLoad) {
      _seq++;
      events.insert(
        0,
        _VisibleEvent(
          eventId: '\$live-$_seq',
          originServerTs: DateTime.utc(
            2026,
            8,
            21,
          ).add(Duration(seconds: _seq)),
        ),
      );
      onEventAdded.add(0);
    }
    appendHiddenEvents(20);
  }
}
