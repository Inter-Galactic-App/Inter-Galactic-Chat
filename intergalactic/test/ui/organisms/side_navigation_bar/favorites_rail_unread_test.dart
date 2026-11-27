import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/atoms/dot_indicator.dart';
import 'package:intergalactic/ui/atoms/notification_badge.dart';
import 'package:intergalactic/ui/organisms/side_navigation_bar/side_navigation_bar.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

import '../../pages/main/main_page_test_harness.dart';

/// Closes the gap the UI polish bundle left open and then MISDESCRIBED.
///
/// That row said the favourites unread marks could not reasonably be tested
/// because a rail test would need a ClientManager provider and a space tree
/// that did not exist, and that the rail had no test at all. Both were wrong.
/// `main_page_test_harness.dart` had been mounting a real ClientManager behind
/// a Provider since 2026-09-02, `SideNavigationBar` has no required
/// constructor arguments, and `side_navigation_bar_tooltip_test.dart` has
/// existed since 2026-08-20 - it just never pumps the widget, which is why the
/// gap itself was real even though the reason given for it was not.
///
/// What was actually uncovered, and is covered here: that the marks reach the
/// favourites button at all, and that they APPEAR without something unrelated
/// happening to rebuild the rail. The counting rule already has its own unit
/// test against `FavoritesUnread.from`; this is the wiring on either side of it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.layoutOverride.set('desktop');
  });

  tearDown(() async {
    await globals.preferences.layoutOverride.set(null);
  });

  /// Mounts the rail alone rather than the whole shell. Its only hard
  /// dependency is the Provider, so a MainPage would add a room list, a header
  /// and a timeline that this test would then have to keep working.
  Future<ClientManager> pumpRail(
    WidgetTester tester, {
    required FakeHarnessClient client,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final clientManager = ClientManager();
    clientManager.addClient(client);

    // Shell widgets reach for the global rather than the tree, the same way
    // the MainPage harness has to set it.
    final previousGlobal = globals.clientManager;
    globals.clientManager = clientManager;
    addTearDown(() => globals.clientManager = previousGlobal);

    await tester.pumpWidget(
      Provider<ClientManager>.value(
        value: clientManager,
        child: MaterialApp(
          theme: ThemeData.light().copyWith(
            extensions: const <ThemeExtension<dynamic>>[ThemeSettings()],
          ),
          home: const Scaffold(body: SideNavigationBar()),
        ),
      ),
    );
    await tester.pump();

    return clientManager;
  }

  Future<FakeHarnessClient> clientWith(List<FakeHarnessRoom> rooms) async {
    final client = FakeHarnessClient(
      identifier: 'client-1',
      rooms: rooms,
      self: FakeHarnessProfile('@self:example.org'),
    );
    addTearDown(client.dispose);
    return client;
  }

  /// Stages favourite membership the way the rail currently reads it.
  ///
  /// THE ONE LINE IN THIS FILE THAT IS EXPECTED TO CHANGE. The m.favourite tag
  /// migration (queue row "Favourite rooms are device-local and do not sync")
  /// moves the rail's membership predicate from `preferences.isRoomFavorite`
  /// to a coordinator, after which the stored preference list is no longer
  /// authoritative. Nothing else here is affected - the unread, dot and badge
  /// logic under test does not care how a room became a favourite - so when
  /// that lands, this body is the whole fixup.
  Future<void> star(FakeHarnessRoom room, {bool favorite = true}) {
    return globals.preferences.setRoomFavorite(
      room.favoriteStorageId,
      favorite,
      legacyRoomId: room.localId,
    );
  }

  testWidgets('the rail agrees with how this file stages a favourite', (
    tester,
  ) async {
    // A canary for the m.favourite migration, not a behaviour test. If [star]
    // stops being authoritative, every unread assertion below fails as "no dot
    // found", which reads like the marks broke. This one fails first and says
    // what actually happened.
    //
    // It is deliberately the WEAKEST possible assertion - one starred room with
    // unread produces one mark - so it can only fail for the staging reason and
    // not for anything about how the marks are drawn.
    final room = FakeHarnessRoom(
      identifier: '!canary:example.org',
      notificationCount: 1,
    );
    final client = await clientWith([room]);
    await star(room);
    await pumpRail(tester, client: client);

    expect(
      find.byType(DotIndicator),
      findsOneWidget,
      reason:
          'the rail no longer reads favourite membership from where star() '
          'writes it. If the m.favourite migration has landed, stage through '
          'the coordinator instead - the rest of this file is unaffected',
    );
  });

  testWidgets('a quiet favourite leaves the rail unmarked', (tester) async {
    final room = FakeHarnessRoom(identifier: '!quiet:example.org');
    final client = await clientWith([room]);
    await star(room);
    await pumpRail(tester, client: client);

    expect(find.byType(DotIndicator), findsNothing);
    expect(find.byType(NotificationBadge), findsNothing);
  });

  testWidgets('an unread favourite puts a dot on the rail', (tester) async {
    final room = FakeHarnessRoom(
      identifier: '!busy:example.org',
      notificationCount: 3,
    );
    final client = await clientWith([room]);
    await star(room);
    await pumpRail(tester, client: client);

    expect(
      find.byType(DotIndicator),
      findsOneWidget,
      reason:
          'the whole point of the change: a favourite with a new message must '
          'say so on the favourites button, not only inside its space',
    );
  });

  testWidgets('a room that is NOT a favourite marks nothing', (tester) async {
    // The other half of the same rule. A rail that lit up for every unread
    // room would pass the test above and mean nothing.
    final room = FakeHarnessRoom(
      identifier: '!busy:example.org',
      notificationCount: 3,
    );
    final client = await clientWith([room]);
    await pumpRail(tester, client: client);

    expect(find.byType(DotIndicator), findsNothing);
  });

  testWidgets('a mention on a favourite shows a count badge', (tester) async {
    final room = FakeHarnessRoom(
      identifier: '!mention:example.org',
      notificationCount: 4,
      highlightedNotificationCount: 2,
    );
    final client = await clientWith([room]);
    await star(room);
    await pumpRail(tester, client: client);

    final badge = tester.widget<NotificationBadge>(
      find.byType(NotificationBadge),
    );
    expect(badge.count, 2);
    expect(badge.exclamation, isFalse);
  });

  testWidgets('a room-wide mention marks the badge as an exclamation', (
    tester,
  ) async {
    final room = FakeHarnessRoom(
      identifier: '!atroom:example.org',
      notificationCount: 1,
      hasRoomWideMentionNotification: true,
    );
    final client = await clientWith([room]);
    await star(room);
    await pumpRail(tester, client: client);

    expect(
      tester
          .widget<NotificationBadge>(find.byType(NotificationBadge))
          .exclamation,
      isTrue,
    );
  });

  testWidgets('a muted favourite stays silent on the rail', (tester) async {
    // The rule the unit test already covers, asserted once here at the surface
    // the user actually looks at - a dot they cannot trace to any room they
    // can hear is worse than no dot.
    final room = FakeHarnessRoom(
      identifier: '!muted:example.org',
      notificationCount: 9,
      highlightedNotificationCount: 4,
      pushRule: PushRule.dontNotify,
    );
    final client = await clientWith([room]);
    await star(room);
    await pumpRail(tester, client: client);

    expect(find.byType(DotIndicator), findsNothing);
    expect(find.byType(NotificationBadge), findsNothing);
  });

  testWidgets('a message arriving while the rail is on screen marks it', (
    tester,
  ) async {
    // THE ONE WITH NO COVERAGE AT ALL BEFORE THIS FILE. Nothing else in the
    // rail listens to individual rooms, so without its own per-room
    // subscription the mark would only appear the next time something
    // unrelated rebuilt the rail - which, on a rail, can be a long time.
    final room = FakeHarnessRoom(identifier: '!quiet:example.org');
    final client = await clientWith([room]);
    await star(room);
    await pumpRail(tester, client: client);
    expect(find.byType(DotIndicator), findsNothing);

    room.notificationCount = 2;
    room.emitUpdate();
    await tester.pumpAndSettle();

    expect(
      find.byType(DotIndicator),
      findsOneWidget,
      reason:
          'the rail is not listening to its favourite rooms, so a message that '
          'arrives while it is on screen never shows up',
    );
  });

  testWidgets('starring a room that already has unread marks the rail', (
    tester,
  ) async {
    // The re-subscribe path. Starring changes WHICH rooms the rail has to
    // listen to, not just what it draws, and no room update follows.
    final room = FakeHarnessRoom(
      identifier: '!busy:example.org',
      notificationCount: 5,
    );
    final client = await clientWith([room]);
    await pumpRail(tester, client: client);
    expect(find.byType(DotIndicator), findsNothing);

    await star(room);
    await tester.pumpAndSettle();

    expect(find.byType(DotIndicator), findsOneWidget);
  });

  testWidgets('a message in a room starred AFTER mount marks the rail', (
    tester,
  ) async {
    // Starring changes which rooms the rail must listen to, not just what it
    // draws. Re-rendering alone passes the previous test, because the count is
    // recomputed every build - only this one needs the subscription list to
    // have been rebuilt, and it is the case a user actually hits: star a quiet
    // room, then wait for someone to say something in it.
    final room = FakeHarnessRoom(identifier: '!later:example.org');
    final client = await clientWith([room]);
    await pumpRail(tester, client: client);

    await star(room);
    await tester.pumpAndSettle();
    expect(find.byType(DotIndicator), findsNothing);

    room.notificationCount = 1;
    room.emitUpdate();
    await tester.pumpAndSettle();

    expect(
      find.byType(DotIndicator),
      findsOneWidget,
      reason:
          'the rail re-rendered when the room was starred but never subscribed '
          'to it, so nothing it does afterwards reaches the rail',
    );
  });

  testWidgets('unstarring a room clears the mark', (tester) async {
    final room = FakeHarnessRoom(
      identifier: '!busy:example.org',
      notificationCount: 5,
    );
    final client = await clientWith([room]);
    await star(room);
    await pumpRail(tester, client: client);
    expect(find.byType(DotIndicator), findsOneWidget);

    await star(room, favorite: false);
    await tester.pumpAndSettle();

    expect(find.byType(DotIndicator), findsNothing);
  });
}
