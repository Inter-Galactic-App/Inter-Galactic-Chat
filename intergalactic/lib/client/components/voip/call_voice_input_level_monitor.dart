import 'dart:async';
import 'dart:math';

import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/utils/safe_stream_subscription_cancel.dart';

abstract class CallVoiceInputLevelPollTimer {
  void cancel();
}

Future<void> debugCancelCallVoiceInputLevelSubscriptionForTesting(
  StreamSubscription? subscription,
) {
  return _cancelCallVoiceInputLevelSubscription(subscription);
}

Future<void> _cancelCallVoiceInputLevelSubscription(
  StreamSubscription? subscription,
) async {
  return safeCancelStreamSubscription(
    subscription,
    content: 'Recovered call voice input-level subscription cancel failure',
    category: LogCategory.webrtc,
    source: 'voice-quick-menu',
  );
}

typedef CallVoiceInputLevelPollTimerFactory =
    CallVoiceInputLevelPollTimer Function(
      Duration interval,
      void Function() onTick,
    );

class CallVoiceInputLevelMonitor {
  CallVoiceInputLevelMonitor({
    required void Function(double level) onLevelChanged,
    Duration pollInterval = defaultPollInterval,
    CallVoiceInputLevelPollTimerFactory? timerFactory,
  }) : _onLevelChanged = onLevelChanged,
       _pollInterval = pollInterval,
       _timerFactory = timerFactory ?? _dartTimer;

  static const defaultPollInterval = Duration(milliseconds: 250);

  final void Function(double level) _onLevelChanged;
  final Duration _pollInterval;
  final CallVoiceInputLevelPollTimerFactory _timerFactory;
  StreamSubscription<void>? _volumeSub;
  CallVoiceInputLevelPollTimer? _pollTimer;
  VoipSession? _session;
  double? _lastLevel;
  int _generation = 0;
  int? _refreshInFlightGeneration;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  static double microphoneLevelFor(VoipSession session) {
    if (session.isMicrophoneMuted) {
      return 0;
    }

    var level = 0.0;
    for (final stream in session.streams) {
      if (stream.direction != VoipStreamDirection.outgoing ||
          stream.type != VoipStreamType.audio) {
        continue;
      }

      final audioLevel = stream.audiolevel;
      if (!audioLevel.isFinite) {
        continue;
      }

      level = max(level, audioLevel);
    }
    return level.clamp(0.0, 1.0).toDouble();
  }

  void attach(VoipSession session) {
    if (_disposed || identical(_session, session)) {
      return;
    }

    _generation++;
    _cancelSessionBindings();
    _session = session;

    final generation = _generation;
    _emit(microphoneLevelFor(session));
    _volumeSub = session.onUpdateVolumeVisualizers.listen((_) {
      unawaited(_refreshIfCurrent(session, generation));
    });
    _pollTimer = _timerFactory(_pollInterval, () {
      unawaited(_refreshIfCurrent(session, generation));
    });
    unawaited(_refreshIfCurrent(session, generation));
  }

  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;
    _generation++;
    _session = null;
    _cancelSessionBindings();
  }

  Future<void> _refreshIfCurrent(VoipSession session, int generation) async {
    if (!_isCurrent(session, generation) ||
        _refreshInFlightGeneration == generation) {
      return;
    }

    _refreshInFlightGeneration = generation;
    try {
      await session.updateStats();
      if (!_isCurrent(session, generation)) {
        return;
      }
      _emit(microphoneLevelFor(session));
    } catch (error) {
      if (_isCurrent(session, generation)) {
        Log.w(
          'call_voice_menu event=input_level_poll result=recovered_error '
          'error_type=${error.runtimeType}',
          category: LogCategory.webrtc,
          source: 'voice-quick-menu',
        );
      }
    } finally {
      if (_refreshInFlightGeneration == generation) {
        _refreshInFlightGeneration = null;
      }
    }
  }

  bool _isCurrent(VoipSession session, int generation) {
    return !_disposed &&
        generation == _generation &&
        identical(_session, session);
  }

  void _emit(double level) {
    if (_disposed || _lastLevel == level) {
      return;
    }

    _lastLevel = level;
    _onLevelChanged(level);
  }

  void _cancelSessionBindings() {
    final volumeSub = _volumeSub;
    _volumeSub = null;
    unawaited(_cancelCallVoiceInputLevelSubscription(volumeSub));
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  static CallVoiceInputLevelPollTimer _dartTimer(
    Duration interval,
    void Function() onTick,
  ) {
    return _DartCallVoiceInputLevelPollTimer(
      Timer.periodic(interval, (_) => onTick()),
    );
  }
}

class _DartCallVoiceInputLevelPollTimer
    implements CallVoiceInputLevelPollTimer {
  const _DartCallVoiceInputLevelPollTimer(this._timer);

  final Timer _timer;

  @override
  void cancel() {
    _timer.cancel();
  }
}
