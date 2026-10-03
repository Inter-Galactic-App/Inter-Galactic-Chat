// AUD-107 / AUD-097 (queue row "AUD-107/110/097 UI lifecycle leaks",
// 2026-09-10): MainPage subscribed EventBus.setFilterClient and
// EventBus.openUserProfile in initState without storing the returned
// StreamSubscription, and MainPageViewMobile did the same for
// EventBus.openThread, EventBus.closeThread and EventBus.focusTimeline.
// MainPage is recreated on every logout/login, so each cycle left the old
// widget's listeners attached to these static, app-lifetime StreamControllers
// with no way to ever detach them.
//
// The armed assertion is `EventBus.<stream>.hasListener` after
// `pumpWidget(SizedBox.shrink())`, not "cancel() was called". That call
// disposes the WHOLE tree the harness mounted, not MainPage alone, and three
// of these five streams have OTHER listeners that plausibly mount as
// MainPage's own descendants in this harness (setFilterClient:
// side_navigation_bar_direct_messages.dart, side_navigation_bar.dart,
// direct_message_list.dart, home_screen.dart; openThread/closeThread:
// room_side_panel.dart - checked by grep, not asserted from memory). So
// "false after unmount" is evidence that EVERY subscriber in the tree
// cancelled, MainPage's included - which is what the armed control below
// actually isolates: reverting only MainPage's/MainPageViewMobile's own
// storage flips these same asserts red without touching any descendant, so
// the failure is tied to this fix's five, not to some other widget's
// teardown. It is incidentally a stronger guard than "just these five": it
// would also catch a descendant like side_navigation_bar leaking
// setFilterClient, since that would leave hasListener true too.
//
// The "true while mounted" sanity asserts are NOT all equally meaningful,
// for the same reason. For openUserProfile and focusTimeline - no other
// listener found by that grep - hasListener true is real evidence this
// widget subscribed. For setFilterClient, openThread and closeThread, a
// descendant's listener alone would make hasListener true even if MainPage's
// own listen() call were deleted outright, so those three sanity asserts
// prove only that SOMETHING in the tree is listening, not that MainPage is.
// They are marked below rather than removed, since it is still true and
// worth stating as a checked fact - just not proof of this fix.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/utils/event_bus.dart';

import 'main_page_test_harness.dart';

void main() {
  setUp(() async {
    await initMainPageHarnessGlobals();
  });

  tearDown(() async {
    await resetMainPageHarnessGlobals();
  });

  testWidgets(
    'disposing MainPage cancels the setFilterClient and openUserProfile '
    'EventBus subscriptions',
    (tester) async {
      await pumpMainPage(tester);

      expect(
        EventBus.setFilterClient.hasListener,
        isTrue,
        reason:
            'sanity: SOMETHING in the tree should be listening while '
            'mounted. Not proof MainPage itself subscribed - '
            'side_navigation_bar/direct_message_list/home_screen also '
            'listen to this stream, so this alone would still pass with '
            "MainPage's own listen() call deleted.",
      );
      expect(
        EventBus.openUserProfile.hasListener,
        isTrue,
        reason:
            'sanity: MainPage should have subscribed while mounted - no '
            'other listener on this stream per grep, so this one is real '
            'evidence.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(
        EventBus.setFilterClient.hasListener,
        isFalse,
        reason: 'MainPage.dispose must cancel this subscription',
      );
      expect(
        EventBus.openUserProfile.hasListener,
        isFalse,
        reason: 'MainPage.dispose must cancel this subscription',
      );
    },
  );

  testWidgets(
    'disposing MainPage cancels the three MainPageViewMobile EventBus '
    'subscriptions',
    (tester) async {
      // HarnessLayout.mobile is pumpMainPage's default, which is what mounts
      // MainPageViewMobile rather than the desktop view.
      await pumpMainPage(tester);

      expect(
        EventBus.openThread.hasListener,
        isTrue,
        reason:
            'sanity: SOMETHING in the tree should be listening while '
            'mounted. Not proof MainPageViewMobile itself subscribed - '
            'room_side_panel.dart also listens to this stream, so this '
            "alone would still pass with MainPageViewMobile's own "
            'listen() call deleted.',
      );
      expect(
        EventBus.closeThread.hasListener,
        isTrue,
        reason:
            'sanity: SOMETHING in the tree should be listening while '
            'mounted. Not proof MainPageViewMobile itself subscribed - '
            'room_side_panel.dart also listens to this stream, so this '
            "alone would still pass with MainPageViewMobile's own "
            'listen() call deleted.',
      );
      expect(
        EventBus.focusTimeline.hasListener,
        isTrue,
        reason:
            'sanity: MainPageViewMobile should have subscribed - no other '
            'listener on this stream per grep, so this one is real '
            'evidence.',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      expect(
        EventBus.openThread.hasListener,
        isFalse,
        reason: 'MainPageViewMobile.dispose must cancel this subscription',
      );
      expect(
        EventBus.closeThread.hasListener,
        isFalse,
        reason: 'MainPageViewMobile.dispose must cancel this subscription',
      );
      expect(
        EventBus.focusTimeline.hasListener,
        isFalse,
        reason: 'MainPageViewMobile.dispose must cancel this subscription',
      );
    },
  );
}
