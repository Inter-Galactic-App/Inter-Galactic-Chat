import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/navigation/desktop_navigation_history.dart';

void main() {
  group('DesktopNavigationHistoryController', () {
    test('keeps duplicate entries from growing history', () {
      final controller = DesktopNavigationHistoryController();
      addTearDown(controller.dispose);

      controller.record(const DesktopNavigationEntry.home());
      controller.record(const DesktopNavigationEntry.home());

      expect(controller.current, const DesktopNavigationEntry.home());
      expect(controller.canGoBack, isFalse);
      expect(controller.canGoForward, isFalse);
    });

    test('emits back and forward requests in order', () async {
      final controller = DesktopNavigationHistoryController();
      addTearDown(controller.dispose);
      final requests = <DesktopNavigationEntry>[];
      final sub = controller.requests.listen(requests.add);
      addTearDown(sub.cancel);

      const home = DesktopNavigationEntry.home();
      const favorites = DesktopNavigationEntry.favorites();
      const room = DesktopNavigationEntry.room(
        clientId: 'client-a',
        roomId: 'room-a',
      );

      controller.record(home);
      controller.record(favorites);
      controller.record(room);

      controller.goBack();
      controller.goBack();
      controller.goForward();

      await pumpEventQueue();

      expect(requests, [favorites, home, favorites]);
      expect(controller.current, favorites);
      expect(controller.canGoBack, isTrue);
      expect(controller.canGoForward, isTrue);
    });

    test('clamps old back entries', () {
      final controller = DesktopNavigationHistoryController(maxEntries: 2);
      addTearDown(controller.dispose);

      controller.record(const DesktopNavigationEntry.home());
      controller.record(const DesktopNavigationEntry.favorites());
      controller.record(
        const DesktopNavigationEntry.space(
          clientId: 'client-a',
          spaceId: 'space-a',
        ),
      );
      controller.record(
        const DesktopNavigationEntry.room(
          clientId: 'client-a',
          roomId: 'room-a',
        ),
      );

      controller.goBack();
      controller.goBack();

      expect(controller.current, const DesktopNavigationEntry.favorites());
      expect(controller.canGoBack, isFalse);
    });

    test('reset clears history and current', () {
      final controller = DesktopNavigationHistoryController();
      addTearDown(controller.dispose);

      controller.record(const DesktopNavigationEntry.home());
      controller.record(const DesktopNavigationEntry.favorites());
      controller.goBack();

      controller.reset();

      expect(controller.current, isNull);
      expect(controller.canGoBack, isFalse);
      expect(controller.canGoForward, isFalse);
    });
  });
}
