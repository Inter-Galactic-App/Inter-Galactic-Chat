import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/inbox/inbox_query.dart';
import 'package:intergalactic/client/components/url_preview/url_preview_component.dart';
import 'package:intergalactic/ui/pages/inbox/inbox_message_preview.dart';

/// Waits past `InboxStateController`'s refresh debounce.
///
/// A source update no longer starts a refresh synchronously: bursts are
/// collapsed into one pass, because refresh queries every registered source and
/// one sync touching N rooms otherwise did N passes over N sources. A
/// zero-duration pump therefore observes the state from BEFORE the update, so
/// these tests wait out the real window rather than stubbing it - the debounce
/// is behaviour worth exercising, not an obstacle to route around.
///
/// Polls for the outcome instead of sleeping past the window. A fixed 250ms
/// wait against a 150ms debounce leaves about 100ms of real-time margin, and a
/// loaded runner can miss it - at which point the assertion after the wait
/// reads pre-update state and the test fails for a reason unrelated to the
/// code. The ceiling below bounds a hang; it is not the thing being measured.
Future<void> _settleInboxRefreshDebounce(bool Function() until) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!until()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError(
        'the Inbox refresh debounce did not settle within 5s; the expected '
        'state never arrived',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  final baseTime = DateTime.utc(2026, 8, 16, 12);

  InboxEventSnapshot event({
    required String id,
    required Duration offset,
    bool isDirectMention = false,
  }) => InboxEventSnapshot(
    eventId: id,
    timestamp: baseTime.add(offset),
    senderId: '@sender:example.org',
    plainTextBody: id,
    isDirectMention: isDirectMention,
  );

  InboxRoomSnapshot room({
    required String clientId,
    required String roomId,
    required InboxEventSnapshot newestUnreadEvent,
    InboxEventSnapshot? newestDirectMention,
    bool isSidebarEligible = true,
    String? readTargetEventId,
  }) => InboxRoomSnapshot(
    clientIdentifier: clientId,
    roomId: roomId,
    roomName: roomId,
    unreadCount: 1,
    isSidebarEligible: isSidebarEligible,
    readTargetEventId: readTargetEventId ?? newestUnreadEvent.eventId,
    newestUnreadEvent: newestUnreadEvent,
    newestDirectMention: newestDirectMention,
  );

  test(
    'all inbox keeps sidebar-eligible rooms, dedupes, and sorts newest first',
    () {
      final older = room(
        clientId: 'one',
        roomId: '!older:example.org',
        newestUnreadEvent: event(
          id: r'$older',
          offset: const Duration(minutes: 1),
        ),
      );
      final newer = room(
        clientId: 'two',
        roomId: '!newer:example.org',
        newestUnreadEvent: event(
          id: r'$newer',
          offset: const Duration(minutes: 2),
        ),
      );
      final duplicateOlder = room(
        clientId: 'one',
        roomId: '!older:example.org',
        newestUnreadEvent: event(id: r'$stale', offset: Duration.zero),
      );
      final muted = room(
        clientId: 'three',
        roomId: '!muted:example.org',
        newestUnreadEvent: event(
          id: r'$muted',
          offset: const Duration(minutes: 3),
        ),
        isSidebarEligible: false,
      );

      expect(InboxQuery.select([older, newer, duplicateOlder, muted]), [
        newer,
        older,
      ]);
    },
  );

  test(
    'tagged filter includes only rooms with a structured direct mention',
    () {
      final directMention = event(
        id: r'$mention',
        offset: const Duration(minutes: 1),
        isDirectMention: true,
      );
      final tagged = room(
        clientId: 'one',
        roomId: '!tagged:example.org',
        newestUnreadEvent: event(
          id: r'$later',
          offset: const Duration(minutes: 2),
        ),
        newestDirectMention: directMention,
      );
      final keywordHighlight = room(
        clientId: 'one',
        roomId: '!keyword:example.org',
        newestUnreadEvent: event(
          id: r'$keyword',
          offset: const Duration(minutes: 3),
        ),
      );

      expect(
        InboxQuery.select([
          keywordHighlight,
          tagged,
        ], filter: InboxFilter.tagged),
        [tagged],
      );
      expect(InboxQuery.eventFor(tagged, InboxFilter.tagged), directMention);
    },
  );

  test(
    'direct mention matching is exact and only uses m.mentions user IDs',
    () {
      expect(
        InboxEventSnapshot.isStructuredDirectMention(
          mentionedUserIds: const ['@me:example.org'],
          selfId: '@me:example.org',
        ),
        isTrue,
      );
      expect(
        InboxEventSnapshot.isStructuredDirectMention(
          mentionedUserIds: const ['@someone-else:example.org'],
          selfId: '@me:example.org',
        ),
        isFalse,
      );
      expect(
        InboxEventSnapshot.isStructuredDirectMention(
          mentionedUserIds: const [],
          selfId: '@me:example.org',
        ),
        isFalse,
      );
    },
  );

  test('a retry issued while mark all is in flight still retries', () async {
    // The previous retry test awaited markAll first, so it always observed a
    // populated failure map and could never reach the capture-order defect:
    // retryFailures used to read _failedTargets at CALL time, which - queued
    // behind an in-flight markAll - saw an empty map, marked nothing, and then
    // cleared the failures markAll was about to record, putting them beyond a
    // second retry too.
    final gate = Completer<void>();
    final failingProvider = _FakeInboxProvider(
      failFirstAttempt: true,
      gate: gate.future,
    );
    final selected = [
      InboxReadTarget(
        provider: failingProvider,
        snapshot: room(
          clientId: 'one',
          roomId: '!retry:example.org',
          newestUnreadEvent: event(id: r'$retry', offset: Duration.zero),
        ),
      ),
    ];
    final controller = InboxReadController();

    // Deliberately NOT awaited: the retry must be issued while markAll is
    // still suspended inside the provider.
    final marking = controller.markAll(selected);
    final retrying = controller.retryFailures();
    gate.complete();

    final initial = await marking;
    final retried = await retrying;

    expect(initial.failedCount, 1);
    expect(
      retried.markedCount,
      1,
      reason: 'the retry ran before markAll recorded its failure',
    );
    expect(retried.failedCount, 0);
    expect(failingProvider.markedEventIds, [r'$retry', r'$retry']);
  });

  test('mark all uses frozen visible targets and retries failures', () async {
    final successfulProvider = _FakeInboxProvider();
    final failingProvider = _FakeInboxProvider(failFirstAttempt: true);
    final selected = [
      InboxReadTarget(
        provider: successfulProvider,
        snapshot: room(
          clientId: 'one',
          roomId: '!selected:example.org',
          newestUnreadEvent: event(id: r'$message', offset: Duration.zero),
          readTargetEventId: r'$state-event-after-message',
        ),
      ),
      InboxReadTarget(
        provider: failingProvider,
        snapshot: room(
          clientId: 'two',
          roomId: '!retry:example.org',
          newestUnreadEvent: event(id: r'$retry', offset: Duration.zero),
        ),
      ),
    ];
    final controller = InboxReadController();

    final initial = await controller.markAll(selected);

    expect(successfulProvider.markedEventIds, [r'$state-event-after-message']);
    expect(failingProvider.markedEventIds, [r'$retry']);
    expect(initial.markedCount, 1);
    expect(initial.failedCount, 1);

    final retried = await controller.retryFailures();

    expect(retried.markedCount, 1);
    expect(retried.failedCount, 0);
    expect(failingProvider.markedEventIds, [r'$retry', r'$retry']);
  });

  test('mark all stops before unstarted targets when cancelled', () async {
    final firstProvider = _FakeInboxProvider();
    final secondProvider = _FakeInboxProvider();
    var cancelled = false;
    final controller = InboxReadController();

    final result = await controller.markAll(
      [
        InboxReadTarget(
          provider: firstProvider,
          snapshot: room(
            clientId: 'one',
            roomId: '!first:example.org',
            newestUnreadEvent: event(id: r'$first', offset: Duration.zero),
          ),
        ),
        InboxReadTarget(
          provider: secondProvider,
          snapshot: room(
            clientId: 'one',
            roomId: '!second:example.org',
            newestUnreadEvent: event(id: r'$second', offset: Duration.zero),
          ),
        ),
      ],
      isCancelled: () => cancelled,
      onMarked: () => cancelled = true,
    );

    expect(firstProvider.markedEventIds, [r'$first']);
    expect(secondProvider.markedEventIds, isEmpty);
    expect(result.wasCancelled, isTrue);
  });

  test(
    'state controller filters snapshots and refreshes room updates',
    () async {
      final tagged = room(
        clientId: 'one',
        roomId: '!tagged:example.org',
        newestUnreadEvent: event(id: r'$tagged', offset: Duration.zero),
        newestDirectMention: event(
          id: r'$mention',
          offset: const Duration(minutes: 1),
          isDirectMention: true,
        ),
      );
      final ordinary = room(
        clientId: 'one',
        roomId: '!ordinary:example.org',
        newestUnreadEvent: event(
          id: r'$ordinary',
          offset: const Duration(minutes: 2),
        ),
      );
      final taggedSource = _FakeInboxSource(tagged);
      final ordinarySource = _FakeInboxSource(ordinary);
      final controller = InboxStateController();

      await controller.setSources([taggedSource, ordinarySource]);

      expect(controller.value.visibleSnapshots, [ordinary, tagged]);
      expect(controller.value.badgeCount, 2);

      controller.setFilter(InboxFilter.tagged);
      expect(controller.value.visibleSnapshots, [tagged]);

      taggedSource.snapshot = null;
      taggedSource.emitUpdate();
      await _settleInboxRefreshDebounce(
        () => controller.value.visibleSnapshots.isEmpty,
      );

      expect(controller.value.visibleSnapshots, isEmpty);
      expect(controller.value.filter, InboxFilter.tagged);
      controller.dispose();
    },
  );

  test(
    'state controller ignores stale source refreshes and disposes listeners',
    () async {
      final firstResult = Completer<InboxRoomSnapshot?>();
      final oldSource = _FakeInboxSource(null, () => firstResult.future);
      final newSnapshot = room(
        clientId: 'two',
        roomId: '!new:example.org',
        newestUnreadEvent: event(id: r'$new', offset: Duration.zero),
      );
      final newSource = _FakeInboxSource(newSnapshot);
      final controller = InboxStateController();

      unawaited(controller.setSources([oldSource]));
      await controller.setSources([newSource]);
      firstResult.complete(
        room(
          clientId: 'one',
          roomId: '!stale:example.org',
          newestUnreadEvent: event(id: r'$stale', offset: Duration.zero),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.value.visibleSnapshots, [newSnapshot]);

      final queryCountBeforeDispose = newSource.queryCount;
      controller.dispose();
      newSource.emitUpdate();
      await _settleInboxRefreshDebounce(
        () => newSource.queryCount == queryCountBeforeDispose,
      );

      expect(newSource.queryCount, queryCountBeforeDispose);
      await oldSource.close();
      await newSource.close();
    },
  );

  test(
    'state controller keeps successful and prior rows on a source error',
    () async {
      final stable = room(
        clientId: 'one',
        roomId: '!stable:example.org',
        newestUnreadEvent: event(id: r'$stable', offset: Duration.zero),
      );
      final flaky = room(
        clientId: 'one',
        roomId: '!flaky:example.org',
        newestUnreadEvent: event(id: r'$flaky', offset: Duration.zero),
      );
      final stableSource = _FakeInboxSource(stable);
      final flakySource = _FakeInboxSource(flaky);
      final controller = InboxStateController();

      await controller.setSources([stableSource, flakySource]);
      flakySource.shouldFail = true;
      flakySource.emitUpdate();
      await _settleInboxRefreshDebounce(() => controller.value.hasError);

      expect(controller.value.hasError, isTrue);
      expect(
        controller.value.visibleSnapshots,
        unorderedEquals([stable, flaky]),
      );

      controller.dispose();
      await stableSource.close();
      await flakySource.close();
    },
  );

  testWidgets('preview shows cached URL context and an explicit continuation', (
    tester,
  ) async {
    final snapshot = room(
      clientId: 'one',
      roomId: '!preview:example.org',
      newestUnreadEvent: InboxEventSnapshot(
        eventId: r'$preview',
        timestamp: baseTime,
        senderId: '@sender:example.org',
        plainTextBody: 'A message with a useful preview',
        isDirectMention: false,
        cachedUrlPreview: UrlPreviewData(
          Uri.parse('https://example.org/article'),
          title: 'Article title',
          description: 'Cached description',
        ),
      ),
    );
    var opened = false;

    await tester.pumpWidget(
      _testApp(
        InboxMessagePreview(
          event: snapshot.newestUnreadEvent,
          isMasked: false,
          onOpenMessage: () => opened = true,
        ),
      ),
    );

    expect(find.text('Article title'), findsOneWidget);
    expect(find.text('Cached description'), findsOneWidget);
    expect(find.text('Open full message'), findsOneWidget);
    await tester.tap(find.text('Open full message'));
    expect(opened, isTrue);
  });

  testWidgets('masked preview does not expose message or URL details', (
    tester,
  ) async {
    final snapshot = room(
      clientId: 'one',
      roomId: '!masked:example.org',
      newestUnreadEvent: InboxEventSnapshot(
        eventId: r'$masked',
        timestamp: baseTime,
        senderId: '@sender:example.org',
        plainTextBody: 'Do not expose this body',
        isDirectMention: false,
        cachedUrlPreview: UrlPreviewData(
          Uri.parse('https://example.org/private'),
          title: 'Do not expose this title',
        ),
      ),
    );

    await tester.pumpWidget(
      _testApp(
        InboxMessagePreview(
          event: snapshot.newestUnreadEvent,
          isMasked: true,
          onOpenMessage: () {},
        ),
      ),
    );

    expect(find.text('Locked conversation'), findsOneWidget);
    expect(find.text('Do not expose this body'), findsNothing);
    expect(find.text('Do not expose this title'), findsNothing);
  });

  testWidgets(
    'visible Inbox row resolves its permitted URL preview before opening',
    (tester) async {
      final preview = Completer<UrlPreviewData?>();
      var loadCount = 0;
      final snapshot = room(
        clientId: 'one',
        roomId: '!preview-load:example.org',
        newestUnreadEvent: InboxEventSnapshot(
          eventId: r'$preview-load',
          timestamp: baseTime,
          senderId: '@sender:example.org',
          plainTextBody: 'A new link message',
          isDirectMention: false,
          loadUrlPreview: () {
            loadCount++;
            return preview.future;
          },
        ),
      );

      await tester.pumpWidget(
        _testApp(
          InboxMessagePreview(
            event: snapshot.newestUnreadEvent,
            isMasked: false,
            onOpenMessage: () {},
          ),
        ),
      );
      await tester.pump();

      expect(loadCount, 1);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      preview.complete(
        UrlPreviewData(
          Uri.parse('https://example.org/article'),
          title: 'Resolved before opening',
          image: MemoryImage(
            Uint8List.fromList(const [
              137,
              80,
              78,
              71,
              13,
              10,
              26,
              10,
              0,
              0,
              0,
              13,
              73,
              72,
              68,
              82,
              0,
              0,
              0,
              1,
              0,
              0,
              0,
              1,
              8,
              6,
              0,
              0,
              0,
              31,
              21,
              196,
              137,
              0,
              0,
              0,
              13,
              73,
              68,
              65,
              84,
              8,
              215,
              99,
              248,
              207,
              192,
              240,
              31,
              0,
              5,
              0,
              1,
              255,
              137,
              153,
              61,
              29,
              0,
              0,
              0,
              0,
              73,
              69,
              78,
              68,
              174,
              66,
              96,
              130,
            ]),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Resolved before opening'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    },
  );

  testWidgets('off-screen Inbox rows defer URL preview loading until visible', (
    tester,
  ) async {
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    var firstLoadCount = 0;
    var secondLoadCount = 0;

    InboxMessagePreview preview(String eventId, VoidCallback onLoad) {
      return InboxMessagePreview(
        event: InboxEventSnapshot(
          eventId: eventId,
          timestamp: baseTime,
          senderId: '@sender:example.org',
          plainTextBody: 'Link message',
          isDirectMention: false,
          loadUrlPreview: () {
            onLoad();
            return Future.value(null);
          },
        ),
        isMasked: false,
        onOpenMessage: () {},
      );
    }

    await tester.pumpWidget(
      _testApp(
        SizedBox(
          height: 100,
          child: ListView(
            controller: scrollController,
            children: [
              SizedBox(
                height: 160,
                child: preview(r'$first', () => firstLoadCount++),
              ),
              SizedBox(
                height: 160,
                child: preview(r'$second', () => secondLoadCount++),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(firstLoadCount, 1);
    expect(secondLoadCount, 0);

    scrollController.jumpTo(160);
    await tester.pump();
    await tester.pump();

    expect(secondLoadCount, 1);
  });

  testWidgets('masked Inbox row never starts its URL preview loader', (
    tester,
  ) async {
    var loadCount = 0;
    final snapshot = room(
      clientId: 'one',
      roomId: '!masked-loader:example.org',
      newestUnreadEvent: InboxEventSnapshot(
        eventId: r'$masked-loader',
        timestamp: baseTime,
        senderId: '@sender:example.org',
        plainTextBody: 'Do not load this link',
        isDirectMention: false,
        loadUrlPreview: () {
          loadCount++;
          return Future.value(null);
        },
      ),
    );

    await tester.pumpWidget(
      _testApp(
        InboxMessagePreview(
          event: snapshot.newestUnreadEvent,
          isMasked: true,
          onOpenMessage: () {},
        ),
      ),
    );

    expect(loadCount, 0);
    expect(find.text('Locked conversation'), findsOneWidget);
  });
}

Widget _testApp(Widget child) => MaterialApp(home: Scaffold(body: child));

class _FakeInboxProvider implements InboxSnapshotProvider {
  _FakeInboxProvider({this.failFirstAttempt = false, this.gate});

  final bool failFirstAttempt;

  /// Holds the first mark open so a caller can issue a second operation while
  /// this one is genuinely still in flight.
  final Future<void>? gate;

  final List<String> markedEventIds = [];
  var _hasFailed = false;
  var _gateUsed = false;

  @override
  Future<InboxRoomSnapshot?> getInboxSnapshot() => Future.value(null);

  @override
  Future<void> markInboxSnapshotRead(InboxRoomSnapshot snapshot) async {
    if (gate != null && !_gateUsed) {
      _gateUsed = true;
      await gate;
    }
    markedEventIds.add(snapshot.readTargetEventId);
    if (failFirstAttempt && !_hasFailed) {
      _hasFailed = true;
      throw StateError('planned failure');
    }
  }
}

class _FakeInboxSource implements InboxRoomSource {
  _FakeInboxSource([
    this.snapshot,
    Future<InboxRoomSnapshot?> Function()? futureSnapshot,
  ]) : _futureSnapshot = futureSnapshot;

  InboxRoomSnapshot? snapshot;
  final Future<InboxRoomSnapshot?> Function()? _futureSnapshot;
  final StreamController<void> _updates = StreamController.broadcast();
  var queryCount = 0;
  var shouldFail = false;

  @override
  String get localRoomId => snapshot?.localRoomId ?? 'pending-source';

  @override
  Stream<void> get onInboxSourceUpdate => _updates.stream;

  @override
  Future<InboxRoomSnapshot?> getInboxSnapshot() {
    queryCount++;
    if (shouldFail) return Future.error(StateError('planned source failure'));
    return _futureSnapshot?.call() ?? Future.value(snapshot);
  }

  @override
  Future<void> markInboxSnapshotRead(InboxRoomSnapshot snapshot) async {}

  void emitUpdate() => _updates.add(null);

  Future<void> close() => _updates.close();
}
