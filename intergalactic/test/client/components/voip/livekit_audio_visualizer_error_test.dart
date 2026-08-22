import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart';

void main() {
  group('isLiveKitAudioVisualizerPluginError', () {
    test('matches LiveKit visualizer MissingPluginException', () {
      final error = MissingPluginException(
        'No implementation found for method cancel on channel '
        'io.livekit.audio.visualizer/eventChannel-track-visualizer',
      );

      expect(isLiveKitAudioVisualizerPluginError(error), isTrue);
    });

    test('matches LiveKit visualizer PlatformException', () {
      final error = PlatformException(
        code: 'error',
        message:
            'io.livekit.audio.visualizer/eventChannel-track-visualizer failed',
      );

      expect(isLiveKitAudioVisualizerPluginError(error), isTrue);
    });

    test('does not match unrelated plugin failures', () {
      final error = MissingPluginException(
        'No implementation found for method cancel on channel unrelated',
      );

      expect(isLiveKitAudioVisualizerPluginError(error), isFalse);
    });
  });
}
