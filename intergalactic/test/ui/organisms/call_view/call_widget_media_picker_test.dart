import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/ui/organisms/call_view/call.dart';

void main() {
  test('applies picked screenshare source while mounted', () async {
    final source = _FakeScreenCaptureSource();
    final applied = <ScreenCaptureSource>[];

    await debugApplyPickedScreenShareForTesting(
      isMounted: true,
      source: source,
      setScreenShare: (source) async => applied.add(source),
    );

    expect(applied, [source]);
  });

  test('ignores missing screenshare source', () async {
    var calls = 0;

    await debugApplyPickedScreenShareForTesting(
      isMounted: true,
      source: null,
      setScreenShare: (_) async => calls++,
    );

    expect(calls, 0);
  });

  test('ignores picked screenshare source after disposal', () async {
    var calls = 0;

    await debugApplyPickedScreenShareForTesting(
      isMounted: false,
      source: _FakeScreenCaptureSource(),
      setScreenShare: (_) async => calls++,
    );

    expect(calls, 0);
  });

  test('applies picked camera while mounted, including default null', () async {
    final applied = <MediaDeviceInfo?>[];

    await debugApplyPickedCameraForTesting(
      isMounted: true,
      camera: null,
      setCamera: (camera) async => applied.add(camera),
    );

    expect(applied, hasLength(1));
    expect(applied.single, isNull);
  });

  test('ignores picked camera after disposal', () async {
    var calls = 0;

    await debugApplyPickedCameraForTesting(
      isMounted: false,
      camera: null,
      setCamera: (_) async => calls++,
    );

    expect(calls, 0);
  });
}

class _FakeScreenCaptureSource implements ScreenCaptureSource {}
