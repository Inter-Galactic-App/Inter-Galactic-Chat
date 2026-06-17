import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/ui/organisms/call_view/call_stream_popout_identity.dart';
import 'package:intergalactic/utils/call_popout_controller.dart';

void main() {
  group('CallPopoutController', () {
    test('full session popout clears and blocks per-stream popouts', () {
      final controller = CallPopoutController();

      controller.popOutStream('session-1', 'participant:@friend:example.org');
      expect(controller.hasPoppedStreams('session-1'), isTrue);

      controller.popOutSession('session-1');
      expect(controller.isSessionPoppedOut('session-1'), isTrue);
      expect(controller.hasPoppedStreams('session-1'), isFalse);
      expect(controller.poppedStreams, isEmpty);

      controller.popOutStream('session-1', 'participant:@friend:example.org');
      expect(controller.hasPoppedStreams('session-1'), isFalse);
    });
  });

  group('callStreamPopoutIdForStream', () {
    test('uses participant identity for ordinary audio and video tiles', () {
      expect(
        callStreamPopoutIdForStream(
          const _FakeVoipStream(
            type: VoipStreamType.audio,
            streamUserId: '@friend:example.org',
          ),
        ),
        'participant:@friend:example.org',
      );
      expect(
        callStreamPopoutIdForStream(
          const _FakeVoipStream(
            type: VoipStreamType.video,
            streamUserId: '@friend:example.org',
          ),
        ),
        'participant:@friend:example.org',
      );
    });

    test('uses screenshare identity for non-LiveKit screenshares', () {
      expect(
        callStreamPopoutIdForStream(
          const _FakeVoipStream(
            type: VoipStreamType.screenshare,
            streamUserId: '@friend:example.org',
          ),
        ),
        'screenshare:@friend:example.org',
      );
    });
  });
}

class _FakeVoipStream implements VoipStream {
  const _FakeVoipStream({
    required this.type,
    required this.streamUserId,
  });

  @override
  final VoipStreamType type;

  @override
  final String streamUserId;

  @override
  double? get aspectRatio => 1;

  @override
  double get audiolevel => 0;

  @override
  VoipStreamDirection get direction => VoipStreamDirection.incoming;

  @override
  bool get isMuted => false;

  @override
  String get label => 'fake';

  @override
  Stream<void> get onStreamChanged => const Stream<void>.empty();

  @override
  VoipStreamReceivePriority get receivePriority =>
      VoipStreamReceivePriority.high;

  @override
  String get streamId => 'fake-stream';

  @override
  Widget? buildVideoRenderer(BoxFit fit, Key key) => null;

  @override
  Future<void> setReceivePriority(VoipStreamReceivePriority priority) async {}
}
