import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/voip/call_voice_input_level_monitor.dart';
import 'package:intergalactic/client/components/voip/share_session/share_session.dart';
import 'package:intergalactic/client/components/voip/voip_call_diagnostics.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';

void main() {
  group('CallVoiceInputLevelMonitor', () {
    test('updates input level from active visualizer events', () async {
      final scheduler = _FakePollScheduler();
      final audio = _FakeVoipStream.audio(audiolevel: 0.1);
      final session = _FakeVoipSession(streams: [audio]);
      final levels = <double>[];
      final monitor = CallVoiceInputLevelMonitor(
        onLevelChanged: levels.add,
        timerFactory: scheduler.create,
      );

      monitor.attach(session);
      await _flushMicrotasks();
      audio.audiolevel = 0.65;
      session.emitVisualizerUpdate();
      await _flushMicrotasks();

      expect(levels, [0.1, 0.65]);
      expect(session.updateStatsCalls, 2);

      monitor.dispose();
      await session.close();
    });

    test(
      'ignores late pending refreshes and timer ticks after dispose',
      () async {
        final scheduler = _FakePollScheduler();
        final audio = _FakeVoipStream.audio(audiolevel: 0.2);
        final session = _FakeVoipSession(streams: [audio]);
        final pendingStats = Completer<void>();
        session.nextUpdateStatsCompleter = pendingStats;
        final levels = <double>[];
        final monitor = CallVoiceInputLevelMonitor(
          onLevelChanged: levels.add,
          timerFactory: scheduler.create,
        );

        monitor.attach(session);
        expect(levels, [0.2]);
        expect(session.updateStatsCalls, 1);

        audio.audiolevel = 0.9;
        monitor.dispose();
        scheduler.latestTimer?.tickEvenIfCancelled();
        session.emitVisualizerUpdate();
        pendingStats.complete();
        await _flushMicrotasks();

        expect(monitor.isDisposed, isTrue);
        expect(scheduler.latestTimer?.cancelled, isTrue);
        expect(levels, [0.2]);

        await session.close();
      },
    );

    test(
      'cancels stale session listeners when the active session changes',
      () async {
        final scheduler = _FakePollScheduler();
        final oldAudio = _FakeVoipStream.audio(audiolevel: 0.25);
        final oldSession = _FakeVoipSession(streams: [oldAudio]);
        final oldPendingStats = Completer<void>();
        oldSession.nextUpdateStatsCompleter = oldPendingStats;
        final newAudio = _FakeVoipStream.audio(audiolevel: 0.4);
        final newSession = _FakeVoipSession(streams: [newAudio]);
        final levels = <double>[];
        final monitor = CallVoiceInputLevelMonitor(
          onLevelChanged: levels.add,
          timerFactory: scheduler.create,
        );

        monitor.attach(oldSession);
        monitor.attach(newSession);
        await _flushMicrotasks();

        oldAudio.audiolevel = 0.95;
        oldSession.emitVisualizerUpdate();
        oldPendingStats.complete();
        await _flushMicrotasks();

        newAudio.audiolevel = 0.55;
        newSession.emitVisualizerUpdate();
        await _flushMicrotasks();

        expect(levels, [0.25, 0.4, 0.55]);
        expect(scheduler.timers.first.cancelled, isTrue);
        expect(oldSession.updateStatsCalls, 1);
        expect(newSession.updateStatsCalls, 2);

        monitor.dispose();
        await oldSession.close();
        await newSession.close();
      },
    );

    test('resolves microphone level from outgoing audio only', () {
      final incoming = _FakeVoipStream.audio(
        audiolevel: 1,
        direction: VoipStreamDirection.incoming,
      );
      final mutedOutgoing = _FakeVoipStream.audio(audiolevel: 0.75);
      final mutedSession = _FakeVoipSession(
        streams: [incoming, mutedOutgoing],
        isMicrophoneMuted: true,
      );

      expect(CallVoiceInputLevelMonitor.microphoneLevelFor(mutedSession), 0);

      final invalid = _FakeVoipStream.audio(audiolevel: double.nan);
      final loud = _FakeVoipStream.audio(audiolevel: 1.5);
      final video = _FakeVoipStream(
        audiolevel: 0.5,
        type: VoipStreamType.video,
        direction: VoipStreamDirection.outgoing,
      );
      final activeSession = _FakeVoipSession(
        streams: [incoming, invalid, video, loud],
      );

      expect(CallVoiceInputLevelMonitor.microphoneLevelFor(activeSession), 1);
    });

    test('recovers visualizer subscription cancellation failures', () async {
      final subscription = _FailingCancelSubscription();

      await expectLater(
        debugCancelCallVoiceInputLevelSubscriptionForTesting(subscription),
        completes,
      );

      expect(subscription.cancelAttempts, 1);
    });
  });
}

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakePollScheduler {
  final timers = <_FakePollTimer>[];

  _FakePollTimer? get latestTimer =>
      timers.isEmpty ? null : timers[timers.length - 1];

  CallVoiceInputLevelPollTimer create(
    Duration interval,
    void Function() onTick,
  ) {
    final timer = _FakePollTimer(interval, onTick);
    timers.add(timer);
    return timer;
  }
}

class _FakePollTimer implements CallVoiceInputLevelPollTimer {
  _FakePollTimer(this.interval, this._onTick);

  final Duration interval;
  final void Function() _onTick;
  bool cancelled = false;

  @override
  void cancel() {
    cancelled = true;
  }

  void tickEvenIfCancelled() {
    _onTick();
  }
}

class _FailingCancelSubscription implements StreamSubscription<void> {
  int cancelAttempts = 0;

  @override
  Future<void> cancel() {
    cancelAttempts++;
    return Future<void>.error(StateError('visualizer cancel failed'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVoipSession implements VoipSession {
  _FakeVoipSession({required this.streams, this.isMicrophoneMuted = false});

  final _visualizerController = StreamController<void>.broadcast(sync: true);
  int updateStatsCalls = 0;
  Completer<void>? nextUpdateStatsCompleter;

  @override
  final List<VoipStream> streams;

  @override
  final bool isMicrophoneMuted;

  void emitVisualizerUpdate() {
    _visualizerController.add(null);
  }

  Future<void> close() {
    return _visualizerController.close();
  }

  @override
  Client get client => throw UnimplementedError();

  @override
  String get sessionId => 'session';

  @override
  String get roomId => '!room:example.test';

  @override
  String? get remoteUserId => '@remote:example.test';

  @override
  String? get remoteUserName => 'Remote';

  @override
  String get roomName => 'Room';

  @override
  VoipState get state => VoipState.connected;

  @override
  bool get supportsScreenshare => false;

  @override
  bool get isSharingScreen => false;

  @override
  ShareSession? get currentShareSession => null;

  @override
  bool get isCameraEnabled => false;

  @override
  double get generalAudioLevel => 0;

  @override
  VoipStream? get remoteUserMediaStream => null;

  @override
  Future<void> acceptCall({
    bool withMicrophone = false,
    bool withCamera = false,
  }) async {}

  @override
  Future<void> declineCall() async {}

  @override
  Future<void> hangUpCall() async {}

  @override
  Stream<VoipState> get onConnectionStateChanged =>
      const Stream<VoipState>.empty();

  @override
  Stream<void> get onStateChanged => const Stream<void>.empty();

  @override
  Stream<void> get onUpdateVolumeVisualizers => _visualizerController.stream;

  @override
  VoipCallDiagnosticsSnapshot get diagnosticsSnapshot =>
      throw UnimplementedError();

  @override
  Stream<void> get onDiagnosticsChanged => const Stream<void>.empty();

  @override
  Future<void> setMicrophoneMute(bool state, {bool stopOnMute = true}) async {}

  @override
  Future<void> updateStats() {
    updateStatsCalls++;
    final completer = nextUpdateStatsCompleter;
    if (completer != null) {
      nextUpdateStatsCompleter = null;
      return completer.future;
    }
    return Future<void>.value();
  }

  @override
  Future<ScreenCaptureSource?> pickScreenCapture(BuildContext context) async {
    return null;
  }

  @override
  Future<void> setScreenShare(ScreenCaptureSource source) async {}

  @override
  Future<void> stopScreenshare() async {}

  @override
  Future<void> setCamera(MediaDeviceInfo? device) async {}

  @override
  Future<void> stopCamera() async {}
}

class _FakeVoipStream implements VoipStream {
  _FakeVoipStream({
    required this.audiolevel,
    required this.type,
    required this.direction,
  });

  _FakeVoipStream.audio({
    required this.audiolevel,
    this.direction = VoipStreamDirection.outgoing,
  }) : type = VoipStreamType.audio;

  @override
  double audiolevel;

  @override
  final VoipStreamType type;

  @override
  final VoipStreamDirection direction;

  @override
  Widget? buildVideoRenderer(BoxFit fit, Key key) => null;

  @override
  Stream<void> get onStreamChanged => const Stream<void>.empty();

  @override
  VoipStreamReceivePriority get receivePriority =>
      VoipStreamReceivePriority.medium;

  @override
  Future<void> setReceivePriority(VoipStreamReceivePriority priority) async {}

  @override
  String get streamUserId => '@user:example.test';

  @override
  String get label => streamId;

  @override
  String get streamId => 'stream-$type-$direction';

  @override
  bool get isMuted => false;

  @override
  double? get aspectRatio => null;
}
