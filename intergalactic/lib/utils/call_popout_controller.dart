import 'dart:async';

typedef CallPopoutDiagnosticLogger = void Function(String message);

class CallStreamPopoutEntry {
  const CallStreamPopoutEntry({
    required this.sessionId,
    required this.streamId,
  });

  final String sessionId;
  final String streamId;
}

class CallPopoutController {
  CallPopoutController({CallPopoutDiagnosticLogger? diagnosticLogger})
    : _diagnosticLogger = diagnosticLogger;

  final StreamController<void> _onChangedController =
      StreamController<void>.broadcast();
  final CallPopoutDiagnosticLogger? _diagnosticLogger;
  Future<void> Function(String sessionId)? _focusSessionWindow;
  Future<bool> Function(String sessionId)? _isSessionAlwaysOnTop;
  Future<void> Function(String sessionId, bool value)? _setSessionAlwaysOnTop;
  Future<bool> Function(String sessionId)? _isSessionTransparentChrome;
  Future<void> Function(String sessionId, bool value)?
  _setSessionTransparentChrome;
  Future<void> Function(String sessionId, String streamId)? _focusStreamWindow;
  Future<bool> Function(String sessionId, String streamId)?
  _isStreamAlwaysOnTop;
  Future<void> Function(String sessionId, String streamId, bool value)?
  _setStreamAlwaysOnTop;
  Future<bool> Function(String sessionId, String streamId)?
  _isStreamTransparentChrome;
  Future<void> Function(String sessionId, String streamId, bool value)?
  _setStreamTransparentChrome;
  bool _usesNativeDetachedSessions = false;
  bool _usesNativeDetachedStreams = false;

  Stream<void> get onChanged => _onChangedController.stream;

  final Set<String> _poppedSessionIds = <String>{};
  final Map<String, Set<String>> _poppedStreamIdsBySession =
      <String, Set<String>>{};

  List<String> get poppedSessionIds =>
      _poppedSessionIds.toList(growable: false);

  bool get usesNativeDetachedSessionPopouts => _usesNativeDetachedSessions;

  bool get usesNativeDetachedStreamPopouts => _usesNativeDetachedStreams;

  String get fullSessionPopoutRoute => _usesNativeDetachedSessions
      ? 'native-session'
      : 'desktop-fallback-session';

  String get streamPopoutRoute =>
      _usesNativeDetachedStreams ? 'native-stream' : 'stream-overlay';

  int get poppedStreamCount => _poppedStreamIdsBySession.values.fold(
    0,
    (count, streams) => count + streams.length,
  );

  List<CallStreamPopoutEntry> get poppedStreams => [
    for (final entry in _poppedStreamIdsBySession.entries)
      for (final streamId in entry.value)
        CallStreamPopoutEntry(sessionId: entry.key, streamId: streamId),
  ];

  bool isSessionPoppedOut(String sessionId) {
    return _poppedSessionIds.contains(sessionId);
  }

  bool isStreamPoppedOut(String sessionId, String streamId) {
    return _poppedStreamIdsBySession[sessionId]?.contains(streamId) == true;
  }

  bool hasPoppedStreams(String sessionId) {
    return (_poppedStreamIdsBySession[sessionId]?.isNotEmpty ?? false);
  }

  void configureNativeDetachedSessions({
    required bool enabled,
    Future<void> Function(String sessionId)? focusSessionWindow,
    Future<bool> Function(String sessionId)? isSessionAlwaysOnTop,
    Future<void> Function(String sessionId, bool value)? setSessionAlwaysOnTop,
    Future<bool> Function(String sessionId)? isSessionTransparentChrome,
    Future<void> Function(String sessionId, bool value)?
    setSessionTransparentChrome,
  }) {
    _usesNativeDetachedSessions = enabled;
    _focusSessionWindow = enabled ? focusSessionWindow : null;
    _isSessionAlwaysOnTop = enabled ? isSessionAlwaysOnTop : null;
    _setSessionAlwaysOnTop = enabled ? setSessionAlwaysOnTop : null;
    _isSessionTransparentChrome = enabled ? isSessionTransparentChrome : null;
    _setSessionTransparentChrome = enabled ? setSessionTransparentChrome : null;
    _log(
      'call_popout event=native_session_configured enabled=$enabled '
      'route=$fullSessionPopoutRoute '
      'focus_callback=${_focusSessionWindow != null} '
      'always_on_top_callback=${_setSessionAlwaysOnTop != null} '
      'transparent_callback=${_setSessionTransparentChrome != null} '
      'session_popouts=${_poppedSessionIds.length} '
      'stream_popouts=$poppedStreamCount',
    );
    _emitChanged();
  }

  void configureNativeDetachedStreams({
    required bool enabled,
    Future<void> Function(String sessionId, String streamId)? focusStreamWindow,
    Future<bool> Function(String sessionId, String streamId)?
    isStreamAlwaysOnTop,
    Future<void> Function(String sessionId, String streamId, bool value)?
    setStreamAlwaysOnTop,
    Future<bool> Function(String sessionId, String streamId)?
    isStreamTransparentChrome,
    Future<void> Function(String sessionId, String streamId, bool value)?
    setStreamTransparentChrome,
  }) {
    _usesNativeDetachedStreams = enabled;
    _focusStreamWindow = enabled ? focusStreamWindow : null;
    _isStreamAlwaysOnTop = enabled ? isStreamAlwaysOnTop : null;
    _setStreamAlwaysOnTop = enabled ? setStreamAlwaysOnTop : null;
    _isStreamTransparentChrome = enabled ? isStreamTransparentChrome : null;
    _setStreamTransparentChrome = enabled ? setStreamTransparentChrome : null;
    _log(
      'call_popout event=native_stream_configured enabled=$enabled '
      'route=$streamPopoutRoute '
      'focus_callback=${_focusStreamWindow != null} '
      'always_on_top_callback=${_setStreamAlwaysOnTop != null} '
      'transparent_callback=${_setStreamTransparentChrome != null} '
      'session_popouts=${_poppedSessionIds.length} '
      'stream_popouts=$poppedStreamCount',
    );
    _emitChanged();
  }

  void markNativeDetachedStreamsUnavailable({required String reason}) {
    if (!_usesNativeDetachedStreams) {
      return;
    }

    _usesNativeDetachedStreams = false;
    _focusStreamWindow = null;
    _isStreamAlwaysOnTop = null;
    _setStreamAlwaysOnTop = null;
    _isStreamTransparentChrome = null;
    _setStreamTransparentChrome = null;
    _log(
      'call_popout event=native_stream_unavailable '
      'route=$streamPopoutRoute reason=$reason '
      'session_popouts=${_poppedSessionIds.length} '
      'stream_popouts=$poppedStreamCount',
    );
    _emitChanged();
  }

  void popOutSession(String sessionId) {
    final removedStreamPopouts =
        _poppedStreamIdsBySession.remove(sessionId)?.isNotEmpty == true;
    if (_poppedSessionIds.add(sessionId)) {
      _log(
        'call_popout event=pop_out_session route=$fullSessionPopoutRoute '
        'result=added removed_stream_popouts=$removedStreamPopouts '
        'session_popouts=${_poppedSessionIds.length} '
        'stream_popouts=$poppedStreamCount',
      );
      _emitChanged();
      return;
    }

    if (removedStreamPopouts) {
      _log(
        'call_popout event=pop_out_session route=$fullSessionPopoutRoute '
        'result=refreshed removed_stream_popouts=true '
        'session_popouts=${_poppedSessionIds.length} '
        'stream_popouts=$poppedStreamCount',
      );
      _emitChanged();
      return;
    }

    _log(
      'call_popout event=pop_out_session route=$fullSessionPopoutRoute '
      'result=already_popped session_popouts=${_poppedSessionIds.length} '
      'stream_popouts=$poppedStreamCount',
    );
  }

  void restoreSession(String sessionId) {
    if (_poppedSessionIds.remove(sessionId)) {
      _log(
        'call_popout event=restore_session route=$fullSessionPopoutRoute '
        'result=removed session_popouts=${_poppedSessionIds.length} '
        'stream_popouts=$poppedStreamCount',
      );
      _emitChanged();
    }
  }

  void popOutStream(String sessionId, String streamId) {
    if (_poppedSessionIds.contains(sessionId)) {
      _log(
        'call_popout event=pop_out_stream route=$streamPopoutRoute '
        'result=blocked reason=session_popped '
        'session_popouts=${_poppedSessionIds.length} '
        'stream_popouts=$poppedStreamCount',
      );
      return;
    }

    final streams = _poppedStreamIdsBySession.putIfAbsent(
      sessionId,
      () => <String>{},
    );
    if (streams.add(streamId)) {
      _log(
        'call_popout event=pop_out_stream route=$streamPopoutRoute '
        'result=added '
        'session_popouts=${_poppedSessionIds.length} '
        'stream_popouts=$poppedStreamCount',
      );
      _emitChanged();
    }
  }

  void restoreStream(String sessionId, String streamId) {
    final streams = _poppedStreamIdsBySession[sessionId];
    if (streams == null) {
      return;
    }

    final removed = streams.remove(streamId);
    if (streams.isEmpty) {
      _poppedStreamIdsBySession.remove(sessionId);
    }

    if (removed) {
      _log(
        'call_popout event=restore_stream route=$streamPopoutRoute '
        'result=removed session_popouts=${_poppedSessionIds.length} '
        'stream_popouts=$poppedStreamCount',
      );
      _emitChanged();
    }
  }

  void clearForSession(String sessionId) {
    final removedSession = _poppedSessionIds.remove(sessionId);
    final removedStreams =
        _poppedStreamIdsBySession.remove(sessionId)?.isNotEmpty == true;

    if (removedSession || removedStreams) {
      _log(
        'call_popout event=clear_for_session result=cleared '
        'removed_session=$removedSession removed_streams=$removedStreams '
        'session_popouts=${_poppedSessionIds.length} '
        'stream_popouts=$poppedStreamCount',
      );
      _emitChanged();
    }
  }

  void clearMissingSessions(Iterable<String> activeSessionIds) {
    final active = activeSessionIds.toSet();
    var changed = false;

    final missingSessions = _poppedSessionIds
        .where((sessionId) => !active.contains(sessionId))
        .toList(growable: false);
    final missingSessionCount = missingSessions.length;
    if (missingSessions.isNotEmpty) {
      _poppedSessionIds.removeAll(missingSessions);
      changed = true;
    }

    final missingStreamSessions = _poppedStreamIdsBySession.keys
        .where((sessionId) => !active.contains(sessionId))
        .toList(growable: false);
    final missingStreamSessionCount = missingStreamSessions.length;
    if (missingStreamSessions.isNotEmpty) {
      for (final sessionId in missingStreamSessions) {
        _poppedStreamIdsBySession.remove(sessionId);
      }
      changed = true;
    }

    if (changed) {
      _log(
        'call_popout event=clear_missing_sessions result=cleared '
        'missing_session_popouts=$missingSessionCount '
        'missing_stream_sessions=$missingStreamSessionCount '
        'session_popouts=${_poppedSessionIds.length} '
        'stream_popouts=$poppedStreamCount',
      );
      _emitChanged();
    }
  }

  Future<void> focusSessionWindow(String sessionId) async {
    final focusSessionWindow = _focusSessionWindow;
    if (focusSessionWindow == null) {
      _log(
        'call_popout event=focus_session_window route=$fullSessionPopoutRoute '
        'result=unavailable reason=no_native_focus_callback',
      );
      return;
    }

    _log(
      'call_popout event=focus_session_window route=$fullSessionPopoutRoute '
      'result=requested',
    );
    await focusSessionWindow(sessionId);
  }

  Future<bool> isSessionWindowAlwaysOnTop(String sessionId) async {
    return await _isSessionAlwaysOnTop?.call(sessionId) ?? false;
  }

  Future<void> setSessionWindowAlwaysOnTop(String sessionId, bool value) async {
    await _setSessionAlwaysOnTop?.call(sessionId, value);
  }

  Future<bool> isSessionWindowTransparentChrome(String sessionId) async {
    return await _isSessionTransparentChrome?.call(sessionId) ?? false;
  }

  Future<void> setSessionWindowTransparentChrome(
    String sessionId,
    bool value,
  ) async {
    await _setSessionTransparentChrome?.call(sessionId, value);
  }

  Future<void> focusStreamWindow(String sessionId, String streamId) async {
    final focusStreamWindow = _focusStreamWindow;
    if (focusStreamWindow == null) {
      _log(
        'call_popout event=focus_stream_window route=$streamPopoutRoute '
        'result=unavailable reason=no_native_focus_callback',
      );
      return;
    }

    _log(
      'call_popout event=focus_stream_window route=$streamPopoutRoute '
      'result=requested',
    );
    await focusStreamWindow(sessionId, streamId);
  }

  Future<bool> isStreamWindowAlwaysOnTop(
    String sessionId,
    String streamId,
  ) async {
    return await _isStreamAlwaysOnTop?.call(sessionId, streamId) ?? false;
  }

  Future<void> setStreamWindowAlwaysOnTop(
    String sessionId,
    String streamId,
    bool value,
  ) async {
    await _setStreamAlwaysOnTop?.call(sessionId, streamId, value);
  }

  Future<bool> isStreamWindowTransparentChrome(
    String sessionId,
    String streamId,
  ) async {
    return await _isStreamTransparentChrome?.call(sessionId, streamId) ?? false;
  }

  Future<void> setStreamWindowTransparentChrome(
    String sessionId,
    String streamId,
    bool value,
  ) async {
    await _setStreamTransparentChrome?.call(sessionId, streamId, value);
  }

  void _emitChanged() {
    _onChangedController.add(null);
  }

  void _log(String message) {
    _diagnosticLogger?.call(message);
  }
}
