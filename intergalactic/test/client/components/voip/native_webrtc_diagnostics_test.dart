import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/native_webrtc_diagnostics.dart';

void main() {
  group('NativeWebrtcDiagnostics', () {
    late File sidecar;

    setUp(() async {
      sidecar = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        '${NativeWebrtcDiagnostics.fileName}',
      );
      await NativeWebrtcDiagnostics.clear();
    });

    tearDown(() async {
      await NativeWebrtcDiagnostics.clear();
    });

    test('reads recent native WebRTC sidecar text', () async {
      await sidecar.writeAsString(
        'ordinary line\n'
        '2026-05-19T15:00:00.000Z native-webrtc '
        'Inter Galactic: Media Foundation H.264 encoder timing frame=30\n',
      );

      final text = await NativeWebrtcDiagnostics.recentText();

      expect(text, contains('ordinary line'));
      expect(text, contains('Media Foundation H.264 encoder timing'));
    });

    test('clear truncates the sidecar log', () async {
      await sidecar.writeAsString(
        'Inter Galactic desktop capture pipeline native_source=1920x1080\n',
      );

      await NativeWebrtcDiagnostics.clear();

      expect(await NativeWebrtcDiagnostics.recentText(), isEmpty);
    });
  });
}
