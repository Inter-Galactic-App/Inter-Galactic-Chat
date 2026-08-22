import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/voip/direct_call_camera_release.dart';
import 'package:webrtc_interface/webrtc_interface.dart';

void main() {
  group('DirectCallCameraOperationQueue', () {
    test('serializes camera operations', () async {
      final queue = DirectCallCameraOperationQueue();
      final firstCanFinish = Completer<void>();
      final events = <String>[];

      final first = queue.run(() async {
        events.add('first-start');
        await firstCanFinish.future;
        events.add('first-end');
      });
      final second = queue.run(() async {
        events.add('second');
      });

      await Future<void>.delayed(Duration.zero);
      expect(events, ['first-start']);

      firstCanFinish.complete();
      await Future.wait([first, second]);

      expect(events, ['first-start', 'first-end', 'second']);
    });

    test('continues after failed operations', () async {
      final queue = DirectCallCameraOperationQueue();

      final first = queue.run(() async {
        throw StateError('camera operation failed');
      });

      await expectLater(first, throwsA(isA<StateError>()));

      var secondRan = false;
      await queue.run(() async {
        secondRan = true;
      });

      expect(secondRan, isTrue);
    });
  });

  group('stopAndRemoveDirectCallCameraTracks', () {
    test('stops and removes video tracks without touching audio', () async {
      final audio = _FakeMediaStreamTrack(id: 'audio-1', kind: 'audio');
      final videoOne = _FakeMediaStreamTrack(id: 'video-1', kind: 'video');
      final videoTwo = _FakeMediaStreamTrack(id: 'video-2', kind: 'video');
      final stream = _FakeMediaStream([audio, videoOne, videoTwo]);

      final stopped = await stopAndRemoveDirectCallCameraTracks(stream);

      expect(stopped, 2);
      expect(stream.getTracks(), [audio]);
      expect(audio.stopped, isFalse);
      expect(videoOne.stopped, isTrue);
      expect(videoTwo.stopped, isTrue);
    });

    test('falls back to local removal if native removal fails', () async {
      final video = _FakeMediaStreamTrack(id: 'video-1', kind: 'video');
      final stream = _FakeMediaStream(
        [video],
        throwNativeRemove: true,
      );
      final errors = <String>[];

      final stopped = await stopAndRemoveDirectCallCameraTracks(
        stream,
        onError: (error, stackTrace, content) => errors.add(content),
      );

      expect(stopped, 1);
      expect(stream.getTracks(), isEmpty);
      expect(video.stopped, isTrue);
      expect(
        errors,
        contains('Failed to remove direct-call camera track from local stream'),
      );
    });

    test('is a no-op for audio-only streams', () async {
      final audio = _FakeMediaStreamTrack(id: 'audio-1', kind: 'audio');
      final stream = _FakeMediaStream([audio]);

      final stopped = await stopAndRemoveDirectCallCameraTracks(stream);

      expect(stopped, 0);
      expect(stream.getTracks(), [audio]);
      expect(audio.stopped, isFalse);
    });
  });
}

class _FakeMediaStream extends MediaStream {
  _FakeMediaStream(
    List<MediaStreamTrack> tracks, {
    this.throwNativeRemove = false,
  })  : _tracks = List<MediaStreamTrack>.from(tracks),
        super('stream-1', 'test');

  final bool throwNativeRemove;
  final List<MediaStreamTrack> _tracks;

  @override
  bool? get active => _tracks.isNotEmpty;

  @override
  Future<void> addTrack(
    MediaStreamTrack track, {
    bool addToNative = true,
  }) async {
    _tracks.add(track);
  }

  @override
  Future<MediaStream> clone() async => _FakeMediaStream(_tracks);

  @override
  Future<void> dispose() async {
    _tracks.clear();
  }

  @override
  Future<void> getMediaTracks() async {}

  @override
  List<MediaStreamTrack> getAudioTracks() =>
      _tracks.where((track) => track.kind == 'audio').toList();

  @override
  MediaStreamTrack? getTrackById(String trackId) {
    for (final track in _tracks) {
      if (track.id == trackId) {
        return track;
      }
    }
    return null;
  }

  @override
  List<MediaStreamTrack> getTracks() => List<MediaStreamTrack>.from(_tracks);

  @override
  List<MediaStreamTrack> getVideoTracks() =>
      _tracks.where((track) => track.kind == 'video').toList();

  @override
  Future<void> removeTrack(
    MediaStreamTrack track, {
    bool removeFromNative = true,
  }) async {
    if (throwNativeRemove && removeFromNative) {
      throw StateError('native remove failed');
    }
    _tracks.remove(track);
  }
}

class _FakeMediaStreamTrack extends MediaStreamTrack {
  _FakeMediaStreamTrack({
    required String id,
    required String kind,
  })  : _id = id,
        _kind = kind;

  final String _id;
  final String _kind;
  bool stopped = false;
  bool _enabled = true;

  @override
  Future<void> applyConstraints([Map<String, dynamic>? constraints]) async {}

  @override
  Future<ByteBuffer> captureFrame() {
    throw UnimplementedError();
  }

  @override
  Future<MediaStreamTrack> clone() async =>
      _FakeMediaStreamTrack(id: _id, kind: _kind);

  @override
  Future<void> dispose() => stop();

  @override
  bool get enabled => _enabled;

  @override
  set enabled(bool b) {
    _enabled = b;
  }

  @override
  Map<String, dynamic> getConstraints() => const {};

  @override
  Map<String, dynamic> getSettings() => const {};

  @override
  Future<bool> hasTorch() async => false;

  @override
  String? get id => _id;

  @override
  String? get kind => _kind;

  @override
  String? get label => _id;

  @override
  bool? get muted => false;

  @override
  Future<void> setTorch(bool torch) async {}

  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  Future<bool> switchCamera() async => false;
}
