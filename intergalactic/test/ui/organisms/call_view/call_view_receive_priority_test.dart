import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/ui/organisms/call_view/call_view.dart';

void main() {
  test('sets requested receive priority for call-view streams', () async {
    final stream = _RecordingVoipStream();

    await debugSetCallViewReceivePriorityForTesting(
      stream,
      VoipStreamReceivePriority.medium,
    );

    expect(stream.priorities, [VoipStreamReceivePriority.medium]);
  });

  test('recovers stale call-view stream receive-priority failures', () async {
    final stream = _FailingVoipStream();

    await expectLater(
      debugSetCallViewReceivePriorityForTesting(
        stream,
        VoipStreamReceivePriority.high,
      ),
      completes,
    );

    expect(stream.priorityAttempts, 1);
  });

  test('keeps fullscreen stream subscribed when grid tile is hidden', () {
    final priority = debugResolveCallViewReceivePriorityForTesting(
      type: VoipStreamType.screenshare,
      direction: VoipStreamDirection.incoming,
      hidden: true,
      focused: false,
      fullscreen: true,
      poppedOut: false,
      visibleVideoStreamCount: 0,
      visibleScreenshareCount: 0,
    );

    expect(priority, VoipStreamReceivePriority.high);
  });

  test('keeps hidden non-fullscreen stream unsubscribed', () {
    final priority = debugResolveCallViewReceivePriorityForTesting(
      type: VoipStreamType.screenshare,
      direction: VoipStreamDirection.incoming,
      hidden: true,
      focused: false,
      fullscreen: false,
      poppedOut: false,
      visibleVideoStreamCount: 0,
      visibleScreenshareCount: 0,
    );

    expect(priority, VoipStreamReceivePriority.disabled);
  });

  test('selects visible remote video for native picture-in-picture', () {
    final selectedIndex = debugSelectNativePictureInPictureTileIndexForTesting(
      tiles: const [
        (
          tileId: 'local-video',
          type: VoipStreamType.video,
          direction: VoipStreamDirection.outgoing,
          hidden: false,
          audioLevel: 1,
        ),
        (
          tileId: 'hidden-remote-video',
          type: VoipStreamType.video,
          direction: VoipStreamDirection.incoming,
          hidden: true,
          audioLevel: 0.9,
        ),
        (
          tileId: 'visible-remote-video',
          type: VoipStreamType.video,
          direction: VoipStreamDirection.incoming,
          hidden: false,
          audioLevel: 0.2,
        ),
      ],
    );

    expect(selectedIndex, 2);
  });

  test('focused native picture-in-picture tile wins selection', () {
    final selectedIndex = debugSelectNativePictureInPictureTileIndexForTesting(
      focusedTileId: 'focused-local-video',
      tiles: const [
        (
          tileId: 'visible-remote-video',
          type: VoipStreamType.video,
          direction: VoipStreamDirection.incoming,
          hidden: false,
          audioLevel: 1,
        ),
        (
          tileId: 'focused-local-video',
          type: VoipStreamType.video,
          direction: VoipStreamDirection.outgoing,
          hidden: false,
          audioLevel: 0,
        ),
      ],
    );

    expect(selectedIndex, 1);
  });

  test('native picture-in-picture hash is stable and redacted', () {
    final first = debugSafePiPHashForTesting('@alice:example.test');
    final second = debugSafePiPHashForTesting('@alice:example.test');
    final other = debugSafePiPHashForTesting('@bob:example.test');

    expect(first, second);
    expect(first, isNot(other));
    expect(first, matches(RegExp(r'^[a-f0-9]{12}$')));
  });
}

class _RecordingVoipStream implements VoipStream {
  final List<VoipStreamReceivePriority> priorities = [];

  @override
  Future<void> setReceivePriority(VoipStreamReceivePriority priority) async {
    priorities.add(priority);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingVoipStream extends _RecordingVoipStream {
  int priorityAttempts = 0;

  @override
  Future<void> setReceivePriority(VoipStreamReceivePriority priority) async {
    priorityAttempts++;
    throw StateError('stream disposed');
  }
}
