import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/inbox/inbox_query.dart';
import 'package:intergalactic/ui/pages/inbox/inbox_navigation.dart';
import 'package:intergalactic/ui/pages/inbox/inbox_room_card.dart';
import 'package:intergalactic/ui/pages/inbox/inbox_view.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final time = DateTime.utc(2026, 8, 16, 12);

  // Every class literal in Dart is a Type, so the previous form of this group -
  // expect(InboxPage, isA<Type>()) - passed for every class in the language and
  // could not fail even with the route completely broken. These drive
  // InboxNavigation.show and assert the one thing the class actually owns: the
  // desktop presentation is a non-opaque panel over the caller, the mobile one
  // replaces it.
  group('adaptive Inbox route presentation', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await globals.preferences.init();
    });

    Future<void> pumpAndShow(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => InboxNavigation.show<void>(
                  context,
                  const Scaffold(
                    // Keyed and full-bleed on purpose: the assertion has to
                    // measure the PANEL the route builds around this page, not
                    // the text inside it. A full-window route still renders
                    // narrow text, so measuring the text passes even when the
                    // desktop panel is unbounded.
                    body: SizedBox.expand(
                      key: ValueKey<String>('inbox-panel-body'),
                      child: Text('inbox panel'),
                    ),
                  ),
                ),
                child: const Text('caller surface'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('caller surface'));
      await tester.pumpAndSettle();
    }

    testWidgets('desktop presents Inbox over the caller, not instead of it', (
      tester,
    ) async {
      await globals.preferences.layoutOverride.set('desktop');
      await pumpAndShow(tester);

      expect(find.text('inbox panel'), findsOneWidget);
      // The route is non-opaque, so the surface that opened it is still built.
      expect(find.text('caller surface'), findsOneWidget);
      // And the panel is a bounded side panel, never the full window. Measured
      // on the expanded body, which fills whatever the route gives it, so an
      // unbounded desktop route shows up as full window width.
      final panelWidth = tester
          .getSize(find.byKey(const ValueKey<String>('inbox-panel-body')))
          .width;
      final windowWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(panelWidth, lessThanOrEqualTo(540.0));
      expect(
        panelWidth,
        lessThan(windowWidth),
        reason: 'the desktop route is not bounded - it filled the window',
      );
    });

    testWidgets(
      'mobile presents Inbox as a full route that replaces the caller',
      (tester) async {
        await globals.preferences.layoutOverride.set('mobile');
        await pumpAndShow(tester);

        expect(find.text('inbox panel'), findsOneWidget);
        // An opaque full-screen route: the caller is no longer built.
        expect(find.text('caller surface'), findsNothing);
      },
    );
  });

  InboxRoomSnapshot snapshot({
    String roomName = 'Launch room',
    String body = 'Please review the launch plan',
    String sender = '@maya:example.org',
  }) => InboxRoomSnapshot(
    clientIdentifier: 'one',
    roomId: '!room:example.org',
    roomName: roomName,
    unreadCount: 3,
    isSidebarEligible: true,
    readTargetEventId: r'$event',
    newestUnreadEvent: InboxEventSnapshot(
      eventId: r'$event',
      timestamp: time,
      senderId: sender,
      plainTextBody: body,
      isDirectMention: true,
    ),
  );

  InboxState state({
    InboxFilter filter = InboxFilter.all,
    List<InboxRoomSnapshot>? snapshots,
    bool isLoading = false,
    bool hasError = false,
  }) {
    final rows = snapshots ?? [snapshot()];
    return InboxState(
      filter: filter,
      allSnapshots: rows,
      visibleSnapshots: rows,
      isLoading: isLoading,
      hasError: hasError,
    );
  }

  testWidgets('shows a readable room card and opens its newest unread event', (
    tester,
  ) async {
    // Disposed in a finally, not addTearDown: flutter_test verifies semantics
    // handles at the END OF THE TEST BODY, before teardowns run, so
    // addTearDown(semantics.dispose) is too late and fails the test outright.
    // A bare dispose() after the expectations is also wrong - a failing one
    // throws past it and leaves the handle open.
    final semantics = tester.ensureSemantics();
    try {
      InboxRoomSnapshot? opened;
      await tester.pumpWidget(
        _app(state: state(), onOpen: (value, _) => opened = value),
      );

      expect(find.text('Launch room'), findsOneWidget);
      expect(find.text('@maya:example.org'), findsOneWidget);
      expect(find.text('Please review the launch plan'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp(r'Launch room.*3 unread messages')),
        findsOneWidget,
      );

      await tester.tap(find.text('Launch room'));
      expect(opened?.newestUnreadEvent.eventId, r'$event');
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('opens and presents the direct mention selected by Tagged me', (
    tester,
  ) async {
    final directMention = InboxEventSnapshot(
      eventId: r'$direct-mention',
      timestamp: time.subtract(const Duration(minutes: 2)),
      senderId: '@maya:example.org',
      plainTextBody: 'You were tagged in this message',
      isDirectMention: true,
    );
    final taggedSnapshot = InboxRoomSnapshot(
      clientIdentifier: 'one',
      roomId: '!room:example.org',
      roomName: 'Launch room',
      unreadCount: 3,
      isSidebarEligible: true,
      readTargetEventId: r'$latest',
      newestUnreadEvent: InboxEventSnapshot(
        eventId: r'$latest',
        timestamp: time,
        senderId: '@maya:example.org',
        plainTextBody: 'A newer non-mention message',
        isDirectMention: false,
      ),
      newestDirectMention: directMention,
    );
    InboxEventSnapshot? opened;

    await tester.pumpWidget(
      _app(
        state: state(filter: InboxFilter.tagged, snapshots: [taggedSnapshot]),
        onOpen: (_, event) => opened = event,
      ),
    );

    expect(find.text('You were tagged in this message'), findsOneWidget);
    expect(find.text('A newer non-mention message'), findsNothing);
    await tester.tap(find.text('Launch room'));
    expect(opened?.eventId, r'$direct-mention');
  });

  testWidgets('communicates and invokes the visible-set mark-all action', (
    tester,
  ) async {
    var marked = false;
    await tester.pumpWidget(
      _app(state: state(), onMarkAll: () => marked = true),
    );

    expect(find.text('Mark all as read'), findsOneWidget);
    await tester.tap(find.text('Mark all as read'));
    expect(marked, isTrue);

    await tester.pumpWidget(_app(state: state(filter: InboxFilter.tagged)));
    expect(find.text('Mark tagged as read'), findsOneWidget);
  });

  testWidgets('masks all private preview details before displaying the card', (
    tester,
  ) async {
    await tester.pumpWidget(_app(state: state(), isMasked: (_) => true));

    expect(find.text('Locked conversation'), findsOneWidget);
    expect(find.text('@maya:example.org'), findsNothing);
    expect(find.text('Please review the launch plan'), findsNothing);
  });

  testWidgets('announces each row fact once, not twice', (tester) async {
    // The card wraps the whole row in Semantics(button, label: '<room>, N
    // unread messages'), but its children were NOT excluded, so the room name
    // Text and _UnreadCount's own Semantics merged straight back in. A screen
    // reader heard: "Launch room, 3 unread messages | Launch room | 8:00 AM |
    // 3 unread messages | @maya:example.org".
    // Disposed in a finally, not addTearDown: flutter_test verifies semantics
    // handles at the END OF THE TEST BODY, before teardowns run, so
    // addTearDown(semantics.dispose) is too late and fails the test outright.
    // A bare dispose() after the expectations is also wrong - a failing one
    // throws past it and leaves the handle open.
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(_app(state: state()));

      final row = tester.getSemantics(find.byType(InboxRoomCard)).label;

      expect(
        'Launch room'.allMatches(row).length,
        1,
        reason: 'the room name is announced more than once: "$row"',
      );
      expect(
        '3 unread messages'.allMatches(row).length,
        1,
        reason: 'the unread count is announced more than once: "$row"',
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('holds the refresh spinner until the refresh actually completes', (
    tester,
  ) async {
    // onRetry used to be a VoidCallback wrapped in `() async => onRetry()`, so
    // the future RefreshIndicator awaited was already complete when it got it:
    // the spinner vanished on gesture end and reported success before any work
    // had run. Drive a refresh that does not complete and assert the indicator
    // is still up.
    final gate = Completer<void>();
    await tester.pumpWidget(_app(state: state(), onRetry: () => gate.future));

    await tester.fling(find.text('Launch room'), const Offset(0, 300), 1000);
    await tester.pump();
    // Drive real frames rather than one long pump. Two earlier drafts of this
    // test both passed against the very defect they were written to catch: the
    // first checked at 1s, where the fling is still settling so BOTH the fixed
    // and broken versions show a spinner; the second used a single
    // pump(8 seconds), which advances the clock but rebuilds once, so the
    // dismissal animation never actually ran.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(
      find.byType(RefreshProgressIndicator),
      findsOneWidget,
      reason: 'the spinner dismissed before the refresh future completed',
    );

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(RefreshProgressIndicator), findsNothing);
  });

  testWidgets('keeps a stable retry action when refresh fails', (tester) async {
    var retried = false;
    await tester.pumpWidget(
      _app(state: state(hasError: true), onRetry: () async => retried = true),
    );

    expect(
      find.text(
        'Inbox could not refresh. Your current list is still available.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    expect(retried, isTrue);
  });
}

Widget _app({
  required InboxState state,
  bool Function(InboxRoomSnapshot)? isMasked,
  void Function(InboxRoomSnapshot, InboxEventSnapshot)? onOpen,
  VoidCallback? onMarkAll,
  Future<void> Function()? onRetry,
}) => MaterialApp(
  home: Scaffold(
    body: InboxView(
      state: state,
      isMasked: isMasked ?? (_) => false,
      onFilterChanged: (_) {},
      onOpen: onOpen ?? (_, __) {},
      onMarkAllRead: onMarkAll ?? () {},
      onRetry: onRetry ?? () async {},
    ),
  ),
);
