import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/organisms/call_view/voip_fullscreen_stream_view.dart';

void main() {
  test(
    'fullscreen route actions still run through the recovery wrapper',
    () async {
      var ran = false;

      await debugRunVoipFullscreenRouteForTesting(() {
        ran = true;
      });

      expect(ran, isTrue);
    },
  );

  test('sync fullscreen route action failures are recovered', () async {
    await expectLater(
      debugRunVoipFullscreenRouteForTesting(() {
        throw StateError('navigator unavailable');
      }),
      completes,
    );
  });

  test('async fullscreen route action failures are recovered', () async {
    await expectLater(
      debugRunVoipFullscreenRouteForTesting(() async {
        throw StateError('route push failed');
      }),
      completes,
    );
  });
}
