// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart' as pkg_ffi;
import 'package:collection/collection.dart';
import 'package:flutter/gestures.dart';
import 'package:intergalactic/client/call_manager.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/organisms/call_view/call.dart';
import 'package:intergalactic/ui/organisms/call_view/call_stream_popout_panel.dart';
import 'package:intergalactic/utils/app_icon/app_icon_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/foundation/_features.dart' show isWindowingEnabled;
import 'package:flutter/src/widgets/_window.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

bool get isDetachedCallWindowPlatformSupported =>
    Platform.isWindows || Platform.isMacOS;

bool get isDetachedCallWindowingEnabled => isWindowingEnabled;

bool get wasDetachedCallWindowingForced =>
    BuildConfig.ENABLE_NATIVE_DETACHED_CALL_WINDOWS &&
    isDetachedCallWindowPlatformSupported &&
    !isDetachedCallWindowingEnabled;

bool get supportsDetachedCallWindows =>
    BuildConfig.ENABLE_NATIVE_DETACHED_CALL_WINDOWS &&
    isDetachedCallWindowPlatformSupported &&
    (isDetachedCallWindowingEnabled || wasDetachedCallWindowingForced);

const double _detachedCallWindowTitleBarHeight = 40;
const double _detachedWindowChromeCollapsedWidth = 64;
const double _detachedWindowChromeExpandedWidth = 168;
const double _detachedWindowChromeCollapsedHorizontalPadding = 5;
const double _detachedWindowChromeExpandedHorizontalPadding = 10;
const double _detachedWindowChromeButtonMinimumSize = 40;
const double _detachedWindowChromeButtonSpacing = 4;
const double _detachedWindowChromeBorderWidth = 1;
const double _detachedWindowChromeExpandedControlsWidth =
    _detachedWindowChromeButtonMinimumSize * 3 +
    _detachedWindowChromeButtonSpacing * 2;

String get detachedCallWindowSupportReason {
  if (!BuildConfig.ENABLE_NATIVE_DETACHED_CALL_WINDOWS) {
    return 'disabled_by_build_define';
  }
  if (!isDetachedCallWindowPlatformSupported) {
    return 'unsupported_platform';
  }
  if (isDetachedCallWindowingEnabled) {
    return 'windowing_enabled';
  }
  if (wasDetachedCallWindowingForced) {
    return 'supported_runtime_override';
  }
  return 'flutter_windowing_disabled';
}

bool _usesCustomDetachedWindowChrome() => Platform.isWindows;

bool _shouldShowDetachedWindowTitleBar({
  required bool transparentChrome,
  required bool usesCustomChrome,
}) {
  return usesCustomChrome && !transparentChrome;
}

Color _detachedWindowBackgroundColor(
  ColorScheme colorScheme, {
  required bool transparentChrome,
}) {
  return transparentChrome
      ? Colors.transparent
      : colorScheme.surfaceContainerLowest;
}

@visibleForTesting
bool debugShouldShowDetachedWindowTitleBarForTesting({
  required bool transparentChrome,
  bool usesCustomChrome = true,
}) {
  return _shouldShowDetachedWindowTitleBar(
    transparentChrome: transparentChrome,
    usesCustomChrome: usesCustomChrome,
  );
}

@visibleForTesting
Color debugDetachedWindowBackgroundColorForTesting(
  ColorScheme colorScheme, {
  required bool transparentChrome,
}) {
  return _detachedWindowBackgroundColor(
    colorScheme,
    transparentChrome: transparentChrome,
  );
}

@visibleForTesting
int debugResolveDetachedWindowStyleForTesting(
  int style, {
  required bool transparentChrome,
}) {
  return _detachedWindowChromeProfile(
    originalStyle: style,
    originalExStyle: 0,
    transparentChrome: transparentChrome,
  ).style;
}

@visibleForTesting
int debugResolveDetachedWindowExStyleForTesting(
  int exStyle, {
  required bool transparentChrome,
}) {
  return _detachedWindowChromeProfile(
    originalStyle: 0,
    originalExStyle: exStyle,
    transparentChrome: transparentChrome,
  ).exStyle;
}

@visibleForTesting
({
  String profileName,
  int style,
  int exStyle,
  int frameLeft,
  int frameRight,
  int frameTop,
  int frameBottom,
})
debugResolveDetachedWindowChromeProfileForTesting({
  required int style,
  required int exStyle,
  required bool transparentChrome,
}) {
  final profile = _detachedWindowChromeProfile(
    originalStyle: style,
    originalExStyle: exStyle,
    transparentChrome: transparentChrome,
  );

  return (
    profileName: profile.name,
    style: profile.style,
    exStyle: profile.exStyle,
    frameLeft: profile.dwmFrameMargins.left,
    frameRight: profile.dwmFrameMargins.right,
    frameTop: profile.dwmFrameMargins.top,
    frameBottom: profile.dwmFrameMargins.bottom,
  );
}

@visibleForTesting
String debugClassifyDetachedWindowEdgeOwnershipForTesting({
  required bool transparentChrome,
  required int style,
  required int exStyle,
  int? visibleFrameBorderThickness,
  int? dwmBorderColor,
  bool sampledWindowEdgeIsLight = false,
  bool sampledFlutterSceneEdgeIsLight = false,
}) {
  return _classifyDetachedWindowEdgeOwnership(
    transparentChrome: transparentChrome,
    style: style,
    exStyle: exStyle,
    visibleFrameBorderThickness: visibleFrameBorderThickness,
    dwmBorderColor: dwmBorderColor,
    sampledWindowEdgeIsLight: sampledWindowEdgeIsLight,
    sampledFlutterSceneEdgeIsLight: sampledFlutterSceneEdgeIsLight,
  );
}

@visibleForTesting
({
  double collapsedMaxWidth,
  double expandedMaxWidth,
  double collapsedHorizontalPadding,
  double expandedHorizontalPadding,
  double borderWidth,
  double buttonMinimumSize,
  double expandedControlsWidth,
})
debugDetachedWindowCollapsedChromeMetricsForTesting() {
  return (
    collapsedMaxWidth: _detachedWindowChromeCollapsedWidth,
    expandedMaxWidth: _detachedWindowChromeExpandedWidth,
    collapsedHorizontalPadding: _detachedWindowChromeCollapsedHorizontalPadding,
    expandedHorizontalPadding: _detachedWindowChromeExpandedHorizontalPadding,
    borderWidth: _detachedWindowChromeBorderWidth,
    buttonMinimumSize: _detachedWindowChromeButtonMinimumSize,
    expandedControlsWidth: _detachedWindowChromeExpandedControlsWidth,
  );
}

@visibleForTesting
bool debugShouldShowDetachedWindowExpandedChromeForTesting({
  required bool expanded,
  required double availableWidth,
}) {
  return _shouldShowDetachedWindowExpandedChrome(
    expanded: expanded,
    availableWidth: availableWidth,
  );
}

@visibleForTesting
Widget debugBuildDetachedWindowRootForTesting({
  required bool transparentChrome,
  required Widget child,
}) {
  return _buildDetachedWindowRoot(
    transparentChrome: transparentChrome,
    child: child,
  );
}

Widget _buildDetachedWindowRoot({
  required bool transparentChrome,
  required Widget child,
}) {
  // The Material must wrap the local Overlay so tooltip/menu entries inherit it.
  return _DetachedWindowRootSurface(
    transparentChrome: transparentChrome,
    child: Overlay.wrap(child: child),
  );
}

class _DetachedWindowRootSurface extends StatelessWidget {
  const _DetachedWindowRootSurface({
    required this.transparentChrome,
    required this.child,
  });

  final bool transparentChrome;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = _detachedWindowBackgroundColor(
      Theme.of(context).colorScheme,
      transparentChrome: transparentChrome,
    );

    return Material(
      type: MaterialType.transparency,
      child: ColoredBox(
        color: backgroundColor,
        child: SizedBox.expand(child: child),
      ),
    );
  }
}

class DetachedCallWindowHost extends StatefulWidget {
  const DetachedCallWindowHost({
    super.key,
    required this.callManager,
    required this.child,
  });

  final CallManager callManager;
  final Widget child;

  @override
  State<DetachedCallWindowHost> createState() => _DetachedCallWindowHostState();
}

class _DetachedCallWindowHostState extends State<DetachedCallWindowHost> {
  static const Size _detachedWindowSize = Size(1180, 760);
  static const BoxConstraints _detachedWindowConstraints = BoxConstraints(
    minWidth: 640,
    minHeight: 420,
  );
  static const Size _detachedStreamWindowSize = Size(560, 360);
  static const Size _detachedScreenShareWindowSize = Size(720, 420);
  static const BoxConstraints _detachedStreamWindowConstraints = BoxConstraints(
    minWidth: 280,
    minHeight: 220,
  );

  late final List<StreamSubscription> _subscriptions;
  final Map<String, _DetachedCallWindowEntry> _entriesBySessionId =
      <String, _DetachedCallWindowEntry>{};
  final Map<String, _DetachedStreamWindowEntry> _entriesByStreamKey =
      <String, _DetachedStreamWindowEntry>{};
  final Map<String, _DetachedSessionStateSubscription>
  _sessionStateSubscriptions = <String, _DetachedSessionStateSubscription>{};
  final Set<String> _streamKeysClosingFromNative = <String>{};
  bool _syncScheduled = false;

  CallManager get _callManager => widget.callManager;

  @override
  void initState() {
    super.initState();
    callPopoutController.configureNativeDetachedSessions(
      enabled: true,
      focusSessionWindow: _focusDetachedSessionWindow,
      isSessionAlwaysOnTop: _isSessionAlwaysOnTop,
      setSessionAlwaysOnTop: _setSessionAlwaysOnTop,
      isSessionTransparentChrome: _isSessionTransparentChrome,
      setSessionTransparentChrome: _setSessionTransparentChrome,
    );
    callPopoutController.configureNativeDetachedStreams(
      enabled: true,
      focusStreamWindow: _focusDetachedStreamWindow,
      isStreamAlwaysOnTop: _isStreamAlwaysOnTop,
      setStreamAlwaysOnTop: _setStreamAlwaysOnTop,
      isStreamTransparentChrome: _isStreamTransparentChrome,
      setStreamTransparentChrome: _setStreamTransparentChrome,
    );

    _subscriptions = [
      callPopoutController.onChanged.listen(
        (_) => _scheduleSyncDetachedWindows(),
      ),
      _callManager.currentSessions.onListUpdated.listen(
        (_) => _scheduleSyncDetachedWindows(),
      ),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleSyncDetachedWindows();
    });
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    for (final entry in _sessionStateSubscriptions.values.toList(
      growable: false,
    )) {
      entry.subscription.cancel();
    }
    _sessionStateSubscriptions.clear();

    callPopoutController.configureNativeDetachedSessions(enabled: false);
    callPopoutController.configureNativeDetachedStreams(enabled: false);
    for (final sessionId in _entriesBySessionId.keys.toList(growable: false)) {
      _destroyDetachedSessionWindow(sessionId, updateState: false);
    }
    for (final streamKey in _entriesByStreamKey.keys.toList(growable: false)) {
      _destroyDetachedStreamWindow(streamKey, updateState: false);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final windows = <Widget>[
      for (final entry in _entriesBySessionId.values)
        RegularWindow(
          key: entry.windowKey,
          controller: entry.controller,
          child: _buildDetachedWindowRoot(
            transparentChrome: entry.transparentChrome,
            child: _DetachedCallWindowView(
              callManager: _callManager,
              sessionId: entry.sessionId,
              controller: entry.controller,
            ),
          ),
        ),
      for (final entry in _entriesByStreamKey.values)
        RegularWindow(
          key: entry.windowKey,
          controller: entry.controller,
          child: _buildDetachedWindowRoot(
            transparentChrome: entry.transparentChrome,
            child: _DetachedStreamWindowView(
              callManager: _callManager,
              sessionId: entry.sessionId,
              streamId: entry.streamId,
              controller: entry.controller,
            ),
          ),
        ),
    ];

    return ViewAnchor(
      view: windows.isEmpty ? null : ViewCollection(views: windows),
      child: widget.child,
    );
  }

  VoipSession? _findSession(String sessionId) {
    return _callManager.currentSessions.firstWhereOrNull(
      (session) => session.sessionId == sessionId,
    );
  }

  String _windowTitleForSession(VoipSession session) {
    return "${session.roomName} Call | ${BuildConfig.app}";
  }

  String _streamWindowKey(String sessionId, String streamId) {
    return '$sessionId::$streamId';
  }

  String _windowTitleForStream(ResolvedCallStreamPopout popout) {
    return "${popout.title} | ${BuildConfig.app}";
  }

  void _scheduleSyncDetachedWindows() {
    if (_syncScheduled) {
      return;
    }
    _syncScheduled = true;
    Timer.run(() {
      _syncScheduled = false;
      if (!mounted) {
        return;
      }
      _syncDetachedWindows();
    });
  }

  void _syncDetachedWindows() {
    final activeSessionsById = <String, VoipSession>{
      for (final session in _callManager.currentSessions)
        session.sessionId: session,
    };
    _syncSessionStateSubscriptions(activeSessionsById);

    final activeSessionIds = activeSessionsById.keys.toSet();
    callPopoutController.clearMissingSessions(activeSessionIds);

    final desiredSessionIds = callPopoutController.poppedSessionIds.toSet();
    final staleSessionIds = _entriesBySessionId.keys
        .where(
          (sessionId) =>
              !desiredSessionIds.contains(sessionId) ||
              !activeSessionIds.contains(sessionId),
        )
        .toList(growable: false);

    for (final sessionId in staleSessionIds) {
      _destroyDetachedSessionWindow(sessionId, updateState: false);
    }

    for (final sessionId in desiredSessionIds) {
      if (!activeSessionIds.contains(sessionId)) {
        continue;
      }

      final session = _findSession(sessionId);
      if (session == null) {
        continue;
      }

      final existingEntry = _entriesBySessionId[sessionId];
      if (existingEntry == null) {
        _createDetachedSessionWindow(session);
      } else {
        existingEntry.controller.setTitle(_windowTitleForSession(session));
      }
    }

    final desiredStreamPopouts = <String, ResolvedCallStreamPopout>{};
    for (final streamEntry in callPopoutController.poppedStreams) {
      final streamKey = _streamWindowKey(
        streamEntry.sessionId,
        streamEntry.streamId,
      );
      if (_streamKeysClosingFromNative.contains(streamKey)) {
        continue;
      }
      if (!activeSessionIds.contains(streamEntry.sessionId) ||
          callPopoutController.isSessionPoppedOut(streamEntry.sessionId)) {
        continue;
      }

      final resolvedStream = resolveCallStreamPopout(
        callManager: _callManager,
        sessionId: streamEntry.sessionId,
        streamId: streamEntry.streamId,
      );
      if (resolvedStream == null) {
        callPopoutController.restoreStream(
          streamEntry.sessionId,
          streamEntry.streamId,
        );
        continue;
      }

      desiredStreamPopouts[streamKey] = resolvedStream;
    }

    final staleStreamKeys = _entriesByStreamKey.entries
        .where(
          (entry) =>
              !desiredStreamPopouts.containsKey(entry.key) ||
              !activeSessionIds.contains(entry.value.sessionId) ||
              callPopoutController.isSessionPoppedOut(entry.value.sessionId),
        )
        .map((entry) => entry.key)
        .toList(growable: false);

    for (final streamKey in staleStreamKeys) {
      _destroyDetachedStreamWindow(streamKey, updateState: false);
    }

    for (final entry in desiredStreamPopouts.entries) {
      final streamKey = entry.key;
      final resolvedStream = entry.value;
      final existingEntry = _entriesByStreamKey[streamKey];
      if (existingEntry == null) {
        _createDetachedStreamWindow(resolvedStream);
      } else {
        existingEntry.controller.setTitle(
          _windowTitleForStream(resolvedStream),
        );
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _syncSessionStateSubscriptions(
    Map<String, VoipSession> activeSessionsById,
  ) {
    final staleSessionIds = _sessionStateSubscriptions.keys
        .where((sessionId) => !activeSessionsById.containsKey(sessionId))
        .toList(growable: false);
    for (final sessionId in staleSessionIds) {
      final removed = _sessionStateSubscriptions.remove(sessionId);
      removed?.subscription.cancel();
    }

    for (final entry in activeSessionsById.entries) {
      final existing = _sessionStateSubscriptions[entry.key];
      if (existing != null && identical(existing.session, entry.value)) {
        continue;
      }

      existing?.subscription.cancel();
      _sessionStateSubscriptions[entry.key] = _DetachedSessionStateSubscription(
        session: entry.value,
        subscription: entry.value.onStateChanged.listen(
          (_) => _scheduleSyncDetachedWindows(),
        ),
      );
    }
  }

  void _createDetachedSessionWindow(VoipSession session) {
    final controller = RegularWindowController(
      preferredSize: _detachedWindowSize,
      preferredConstraints: _detachedWindowConstraints,
      title: _windowTitleForSession(session),
      delegate: _DetachedWindowDelegate(
        handleWindowDestroyed: () =>
            _onDetachedWindowDestroyed(session.sessionId),
      ),
    );

    _entriesBySessionId[session.sessionId] = _DetachedCallWindowEntry(
      sessionId: session.sessionId,
      windowKey: ValueKey("detached-call-window-${session.sessionId}"),
      controller: controller,
    );

    controller.activate();
    _applyNativeWindowChrome(_entriesBySessionId[session.sessionId]!);
    unawaited(AppIconManager.instance.apply());
  }

  void _createDetachedStreamWindow(ResolvedCallStreamPopout popout) {
    final streamKey = _streamWindowKey(
      popout.session.sessionId,
      popout.popoutId,
    );
    RegularWindowController? controller;
    try {
      controller = RegularWindowController(
        preferredSize: popout.isScreenshare
            ? _detachedScreenShareWindowSize
            : _detachedStreamWindowSize,
        preferredConstraints: _detachedStreamWindowConstraints,
        title: _windowTitleForStream(popout),
        delegate: _DetachedWindowDelegate(
          handleWindowDestroyed: () =>
              _onDetachedStreamWindowDestroyed(streamKey),
        ),
      );

      _entriesByStreamKey[streamKey] = _DetachedStreamWindowEntry(
        sessionId: popout.session.sessionId,
        streamId: popout.popoutId,
        windowKey: ValueKey('detached-call-stream-window-$streamKey'),
        controller: controller,
      );

      controller.activate();
      _applyNativeWindowChrome(_entriesByStreamKey[streamKey]!);
      unawaited(AppIconManager.instance.apply());
    } catch (error, stackTrace) {
      _entriesByStreamKey.remove(streamKey);
      callPopoutController.markNativeDetachedStreamsUnavailable(
        reason: 'window_create_failed',
      );
      _destroyRecoveredStreamController(controller);
      Log.onError(
        error,
        stackTrace,
        content:
            'Recovered detached stream call window creation failure; falling back to in-app stream popout overlay',
        category: LogCategory.webrtc,
        source: 'detached-call-window',
      );
    }
  }

  void _destroyRecoveredStreamController(RegularWindowController? controller) {
    if (controller == null) {
      return;
    }

    try {
      controller.destroy();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Recovered detached stream call window cleanup failure',
        category: LogCategory.webrtc,
        source: 'detached-call-window',
      );
    }
  }

  void _onDetachedWindowDestroyed(String sessionId) {
    final removed = _entriesBySessionId.remove(sessionId);
    if (removed == null) {
      return;
    }

    callPopoutController.restoreSession(sessionId);
    if (mounted) {
      setState(() {});
    }
  }

  void _onDetachedStreamWindowDestroyed(String streamKey) {
    final removed = _entriesByStreamKey.remove(streamKey);
    if (removed == null) {
      return;
    }

    _streamKeysClosingFromNative.add(streamKey);
    _restoreStreamAfterNativeWindowClose(removed, streamKey);
    if (mounted) {
      setState(() {});
    }
  }

  void _restoreStreamAfterNativeWindowClose(
    _DetachedStreamWindowEntry entry,
    String streamKey,
  ) {
    Timer.run(() {
      unawaited(_completeStreamWindowNativeClose(entry, streamKey));
    });
  }

  Future<void> _completeStreamWindowNativeClose(
    _DetachedStreamWindowEntry entry,
    String streamKey,
  ) async {
    try {
      if (!mounted) {
        return;
      }

      final popout = resolveCallStreamPopout(
        callManager: _callManager,
        sessionId: entry.sessionId,
        streamId: entry.streamId,
      );
      if (shouldStopDeadLocalScreensharePopoutOnNativeClose(
        popout: popout,
        localUserId: popout?.session.client.self?.identifier,
      )) {
        await _stopDeadLocalScreensharePopout(popout!);
      }

      callPopoutController.restoreStream(entry.sessionId, entry.streamId);
    } finally {
      _streamKeysClosingFromNative.remove(streamKey);
      if (mounted) {
        _scheduleSyncDetachedWindows();
      }
    }
  }

  Future<void> _stopDeadLocalScreensharePopout(
    ResolvedCallStreamPopout popout,
  ) async {
    try {
      await popout.session.stopScreenshare();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Recovered dead detached screen-share popout stop failure',
        category: LogCategory.webrtc,
        source: 'detached-call-window',
      );
    }
  }

  void _destroyDetachedSessionWindow(
    String sessionId, {
    bool updateState = true,
  }) {
    final entry = _entriesBySessionId.remove(sessionId);
    if (entry == null) {
      return;
    }

    _destroyDetachedWindowController(
      entry.controller,
      content: 'Recovered detached call window destroy failure',
    );
    if (updateState && mounted) {
      setState(() {});
    }
  }

  void _destroyDetachedStreamWindow(
    String streamKey, {
    bool updateState = true,
  }) {
    final entry = _entriesByStreamKey.remove(streamKey);
    if (entry == null) {
      return;
    }

    _destroyDetachedWindowController(
      entry.controller,
      content: 'Recovered detached stream call window destroy failure',
    );
    if (updateState && mounted) {
      setState(() {});
    }
  }

  void _destroyDetachedWindowController(
    RegularWindowController controller, {
    required String content,
  }) {
    try {
      controller.destroy();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: content,
        category: LogCategory.webrtc,
        source: 'detached-call-window',
      );
    }
  }

  Future<void> _focusDetachedSessionWindow(String sessionId) async {
    _entriesBySessionId[sessionId]?.controller.activate();
  }

  Future<void> _focusDetachedStreamWindow(
    String sessionId,
    String streamId,
  ) async {
    _entriesByStreamKey[_streamWindowKey(sessionId, streamId)]?.controller
        .activate();
  }

  Future<bool> _isSessionAlwaysOnTop(String sessionId) async {
    if (!Platform.isWindows) {
      return false;
    }
    return _entriesBySessionId[sessionId]?.isAlwaysOnTop ?? false;
  }

  Future<void> _setSessionAlwaysOnTop(String sessionId, bool value) async {
    if (!Platform.isWindows) {
      return;
    }
    final entry = _entriesBySessionId[sessionId];
    if (entry == null) {
      return;
    }

    _setWindowAlwaysOnTop(entry.controller, value);
    entry.isAlwaysOnTop = value;
    if (mounted) {
      setState(() {});
    }
  }

  Future<bool> _isStreamAlwaysOnTop(String sessionId, String streamId) async {
    if (!Platform.isWindows) {
      return false;
    }
    return _entriesByStreamKey[_streamWindowKey(sessionId, streamId)]
            ?.isAlwaysOnTop ??
        false;
  }

  Future<void> _setStreamAlwaysOnTop(
    String sessionId,
    String streamId,
    bool value,
  ) async {
    if (!Platform.isWindows) {
      return;
    }
    final entry = _entriesByStreamKey[_streamWindowKey(sessionId, streamId)];
    if (entry == null) {
      return;
    }

    _setWindowAlwaysOnTop(entry.controller, value);
    entry.isAlwaysOnTop = value;
    if (mounted) {
      setState(() {});
    }
  }

  Future<bool> _isSessionTransparentChrome(String sessionId) async {
    return _entriesBySessionId[sessionId]?.transparentChrome ?? false;
  }

  Future<void> _setSessionTransparentChrome(
    String sessionId,
    bool value,
  ) async {
    final entry = _entriesBySessionId[sessionId];
    if (entry == null) {
      return;
    }

    entry.transparentChrome = value;
    _applyNativeWindowChrome(entry);
    if (mounted) {
      setState(() {});
    }
  }

  Future<bool> _isStreamTransparentChrome(
    String sessionId,
    String streamId,
  ) async {
    return _entriesByStreamKey[_streamWindowKey(sessionId, streamId)]
            ?.transparentChrome ??
        false;
  }

  Future<void> _setStreamTransparentChrome(
    String sessionId,
    String streamId,
    bool value,
  ) async {
    final entry = _entriesByStreamKey[_streamWindowKey(sessionId, streamId)];
    if (entry == null) {
      return;
    }

    entry.transparentChrome = value;
    _applyNativeWindowChrome(entry);
    if (mounted) {
      setState(() {});
    }
  }

  void _setWindowAlwaysOnTop(RegularWindowController controller, bool value) {
    final dynamic nativeController = controller;
    final ffi.Pointer<ffi.Void> hwnd =
        nativeController.getWindowHandle() as ffi.Pointer<ffi.Void>;

    _setWindowPos(
      hwnd,
      value ? _hwndTopMost : _hwndNotTopMost,
      0,
      0,
      0,
      0,
      _swpNoMove | _swpNoSize | _swpNoActivate,
    );
  }

  void _applyNativeWindowChrome(_DetachedWindowEntry entry) {
    if (!Platform.isWindows) {
      return;
    }

    final dynamic nativeController = entry.controller;
    final ffi.Pointer<ffi.Void> hwnd =
        nativeController.getWindowHandle() as ffi.Pointer<ffi.Void>;
    final liveStyleBefore = _getWindowLongPtr(hwnd, _gwlStyle);
    final liveExStyleBefore = _getWindowLongPtr(hwnd, _gwlExStyle);

    if (entry.originalStyle == null || entry.originalExStyle == null) {
      entry.originalStyle = _detachedWindowChromeStyle(liveStyleBefore);
      entry.originalExStyle = liveExStyleBefore;
    }

    final profile = _detachedWindowChromeProfile(
      originalStyle: entry.originalStyle!,
      originalExStyle: entry.originalExStyle!,
      transparentChrome: entry.transparentChrome,
    );

    _setWindowLongPtr(hwnd, _gwlStyle, profile.style);
    _setWindowLongPtr(hwnd, _gwlExStyle, profile.exStyle);
    _applyDetachedWindowDwmChrome(hwnd, profile: profile);

    _setWindowPos(
      hwnd,
      ffi.nullptr,
      0,
      0,
      0,
      0,
      _swpNoMove |
          _swpNoSize |
          _swpNoZOrder |
          _swpNoActivate |
          _swpFrameChanged,
    );

    _recordDetachedWindowChromeDiagnostics(
      hwnd: hwnd,
      profile: profile,
      liveStyleBefore: liveStyleBefore,
      liveExStyleBefore: liveExStyleBefore,
    );
  }
}

abstract class _DetachedWindowEntry {
  RegularWindowController get controller;
  bool get isAlwaysOnTop;
  set isAlwaysOnTop(bool value);
  bool get transparentChrome;
  set transparentChrome(bool value);
  int? get originalStyle;
  set originalStyle(int? value);
  int? get originalExStyle;
  set originalExStyle(int? value);
}

class _DetachedCallWindowEntry implements _DetachedWindowEntry {
  _DetachedCallWindowEntry({
    required this.sessionId,
    required this.windowKey,
    required this.controller,
  });

  final String sessionId;
  final ValueKey<String> windowKey;
  final RegularWindowController controller;
  bool isAlwaysOnTop = false;
  bool transparentChrome = false;
  int? originalStyle;
  int? originalExStyle;
}

class _DetachedStreamWindowEntry implements _DetachedWindowEntry {
  _DetachedStreamWindowEntry({
    required this.sessionId,
    required this.streamId,
    required this.windowKey,
    required this.controller,
  });

  final String sessionId;
  final String streamId;
  final ValueKey<String> windowKey;
  @override
  final RegularWindowController controller;
  @override
  bool isAlwaysOnTop = false;
  @override
  bool transparentChrome = false;
  @override
  int? originalStyle;
  @override
  int? originalExStyle;
}

class _DetachedSessionStateSubscription {
  _DetachedSessionStateSubscription({
    required this.session,
    required this.subscription,
  });

  final VoipSession session;
  final StreamSubscription<void> subscription;
}

class _DetachedWindowDelegate with RegularWindowControllerDelegate {
  _DetachedWindowDelegate({required this.handleWindowDestroyed});

  final VoidCallback handleWindowDestroyed;

  @override
  void onWindowDestroyed() {
    handleWindowDestroyed();
  }
}

class _DetachedCallWindowView extends StatefulWidget {
  const _DetachedCallWindowView({
    required this.callManager,
    required this.sessionId,
    required this.controller,
  });

  final CallManager callManager;
  final String sessionId;
  final RegularWindowController controller;

  @override
  State<_DetachedCallWindowView> createState() =>
      _DetachedCallWindowViewState();
}

class _DetachedCallWindowViewState extends State<_DetachedCallWindowView> {
  StreamSubscription<void>? _sessionsSubscription;
  StreamSubscription<void>? _popoutSubscription;
  bool _isAlwaysOnTop = false;
  bool _transparentChrome = false;
  bool _isHovered = false;
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    _sessionsSubscription = widget.callManager.currentSessions.onListUpdated
        .listen((_) => _refresh());
    _popoutSubscription = callPopoutController.onChanged.listen(
      (_) => _refresh(),
    );
    widget.controller.addListener(_syncWindowState);
    _syncWindowState();
    _loadWindowState();
  }

  @override
  void didUpdateWidget(_DetachedCallWindowView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_syncWindowState);
      widget.controller.addListener(_syncWindowState);
      _syncWindowState();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncWindowState);
    _sessionsSubscription?.cancel();
    _popoutSubscription?.cancel();
    super.dispose();
  }

  VoipSession? get _session {
    return widget.callManager.currentSessions.firstWhereOrNull(
      (session) => session.sessionId == widget.sessionId,
    );
  }

  void _syncWindowState() {
    bool isMaximized;
    try {
      isMaximized = widget.controller.isMaximized;
    } catch (_) {
      return;
    }
    if (mounted && _isMaximized != isMaximized) {
      setState(() => _isMaximized = isMaximized);
    } else {
      _isMaximized = isMaximized;
    }
  }

  Future<void> _loadWindowState() async {
    final pinValue = await callPopoutController.isSessionWindowAlwaysOnTop(
      widget.sessionId,
    );
    final transparentValue = await callPopoutController
        .isSessionWindowTransparentChrome(widget.sessionId);
    if (mounted) {
      setState(() {
        _isAlwaysOnTop = pinValue;
        _transparentChrome = transparentValue;
      });
    }
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
    _loadWindowState();
  }

  Future<void> _toggleAlwaysOnTop() async {
    final newValue = !_isAlwaysOnTop;
    await callPopoutController.setSessionWindowAlwaysOnTop(
      widget.sessionId,
      newValue,
    );
    if (mounted) {
      setState(() {
        _isAlwaysOnTop = newValue;
      });
    }
  }

  Future<void> _toggleTransparentChrome() async {
    final newValue = !_transparentChrome;
    await callPopoutController.setSessionWindowTransparentChrome(
      widget.sessionId,
      newValue,
    );
    if (mounted) {
      setState(() {
        _transparentChrome = newValue;
        if (!newValue) {
          _isHovered = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) {
      return const _DetachedClosingWindowSurface(
        message: "Closing detached call window...",
      );
    }

    final transparentChrome = _transparentChrome;
    final showChrome = !transparentChrome || _isHovered;
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = _detachedWindowBackgroundColor(
      colorScheme,
      transparentChrome: transparentChrome,
    );
    final showTitleBar = _shouldShowDetachedWindowTitleBar(
      transparentChrome: transparentChrome,
      usesCustomChrome: _usesCustomDetachedWindowChrome(),
    );
    final callSurface = CallWidget(
      session,
      showSessionPopoutButton: false,
      transparentBackground: transparentChrome,
    );

    return Material(
      type: MaterialType.transparency,
      child: MouseRegion(
        onEnter: (_) {
          if (transparentChrome) {
            setState(() => _isHovered = true);
          }
        },
        onExit: (_) {
          if (transparentChrome) {
            setState(() => _isHovered = false);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(color: backgroundColor),
          child: Stack(
            children: [
              Positioned.fill(
                child: showTitleBar
                    ? Column(
                        children: [
                          _DetachedCallWindowTitleBar(
                            controller: widget.controller,
                            title: session.roomName,
                            isAlwaysOnTop: _isAlwaysOnTop,
                            isMaximized: _isMaximized,
                            onToggleTransparentChrome: _toggleTransparentChrome,
                            onToggleAlwaysOnTop: _toggleAlwaysOnTop,
                            onDock: () {
                              callPopoutController.restoreSession(
                                widget.sessionId,
                              );
                            },
                          ),
                          Expanded(child: callSurface),
                        ],
                      )
                    : callSurface,
              ),
              if (!showTitleBar)
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: _DetachedCallWindowChrome(
                      transparentChrome: transparentChrome,
                      expanded: showChrome,
                      isAlwaysOnTop: _isAlwaysOnTop,
                      onToggleTransparentChrome: _toggleTransparentChrome,
                      onToggleAlwaysOnTop: _toggleAlwaysOnTop,
                      onDock: () {
                        callPopoutController.restoreSession(widget.sessionId);
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetachedStreamWindowView extends StatefulWidget {
  const _DetachedStreamWindowView({
    required this.callManager,
    required this.sessionId,
    required this.streamId,
    required this.controller,
  });

  final CallManager callManager;
  final String sessionId;
  final String streamId;
  final RegularWindowController controller;

  @override
  State<_DetachedStreamWindowView> createState() =>
      _DetachedStreamWindowViewState();
}

class _DetachedStreamWindowViewState extends State<_DetachedStreamWindowView> {
  StreamSubscription<void>? _sessionsSubscription;
  StreamSubscription<void>? _popoutSubscription;
  bool _isAlwaysOnTop = false;
  bool _transparentChrome = false;
  bool _isHovered = false;
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    _sessionsSubscription = widget.callManager.currentSessions.onListUpdated
        .listen((_) => _refresh());
    _popoutSubscription = callPopoutController.onChanged.listen(
      (_) => _refresh(),
    );
    widget.controller.addListener(_syncWindowState);
    _syncWindowState();
    _loadWindowState();
  }

  @override
  void didUpdateWidget(_DetachedStreamWindowView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_syncWindowState);
      widget.controller.addListener(_syncWindowState);
      _syncWindowState();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncWindowState);
    _sessionsSubscription?.cancel();
    _popoutSubscription?.cancel();
    super.dispose();
  }

  ResolvedCallStreamPopout? get _popout {
    return resolveCallStreamPopout(
      callManager: widget.callManager,
      sessionId: widget.sessionId,
      streamId: widget.streamId,
    );
  }

  void _syncWindowState() {
    bool isMaximized;
    try {
      isMaximized = widget.controller.isMaximized;
    } catch (_) {
      return;
    }
    if (mounted && _isMaximized != isMaximized) {
      setState(() => _isMaximized = isMaximized);
    } else {
      _isMaximized = isMaximized;
    }
  }

  Future<void> _loadWindowState() async {
    final pinValue = await callPopoutController.isStreamWindowAlwaysOnTop(
      widget.sessionId,
      widget.streamId,
    );
    final transparentValue = await callPopoutController
        .isStreamWindowTransparentChrome(widget.sessionId, widget.streamId);
    if (mounted) {
      setState(() {
        _isAlwaysOnTop = pinValue;
        _transparentChrome = transparentValue;
      });
    }
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
    _loadWindowState();
  }

  Future<void> _toggleAlwaysOnTop() async {
    final newValue = !_isAlwaysOnTop;
    await callPopoutController.setStreamWindowAlwaysOnTop(
      widget.sessionId,
      widget.streamId,
      newValue,
    );
    if (mounted) {
      setState(() {
        _isAlwaysOnTop = newValue;
      });
    }
  }

  Future<void> _toggleTransparentChrome() async {
    final newValue = !_transparentChrome;
    await callPopoutController.setStreamWindowTransparentChrome(
      widget.sessionId,
      widget.streamId,
      newValue,
    );
    if (mounted) {
      setState(() {
        _transparentChrome = newValue;
        if (!newValue) {
          _isHovered = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final popout = _popout;
    if (popout == null) {
      return const _DetachedClosingWindowSurface(
        message: "Closing popped-out panel...",
      );
    }

    final transparentChrome = _transparentChrome;
    final showChrome = !transparentChrome || _isHovered;
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = _detachedWindowBackgroundColor(
      colorScheme,
      transparentChrome: transparentChrome,
    );
    final showTitleBar = _shouldShowDetachedWindowTitleBar(
      transparentChrome: transparentChrome,
      usesCustomChrome: _usesCustomDetachedWindowChrome(),
    );
    final popoutSurface = CallStreamPopoutContent(
      popout: popout,
      transparentChrome: transparentChrome,
    );

    return Material(
      type: MaterialType.transparency,
      child: MouseRegion(
        onEnter: (_) {
          if (transparentChrome) {
            setState(() => _isHovered = true);
          }
        },
        onExit: (_) {
          if (transparentChrome) {
            setState(() => _isHovered = false);
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(color: backgroundColor),
          child: Stack(
            children: [
              Positioned.fill(
                child: showTitleBar
                    ? Column(
                        children: [
                          _DetachedCallWindowTitleBar(
                            controller: widget.controller,
                            title: popout.title,
                            isAlwaysOnTop: _isAlwaysOnTop,
                            isMaximized: _isMaximized,
                            onToggleTransparentChrome: _toggleTransparentChrome,
                            onToggleAlwaysOnTop: _toggleAlwaysOnTop,
                            onDock: () {
                              callPopoutController.restoreStream(
                                widget.sessionId,
                                widget.streamId,
                              );
                            },
                          ),
                          Expanded(child: popoutSurface),
                        ],
                      )
                    : popoutSurface,
              ),
              if (!showTitleBar)
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: _DetachedCallWindowChrome(
                      transparentChrome: transparentChrome,
                      expanded: showChrome,
                      isAlwaysOnTop: _isAlwaysOnTop,
                      onToggleTransparentChrome: _toggleTransparentChrome,
                      onToggleAlwaysOnTop: _toggleAlwaysOnTop,
                      onDock: () {
                        callPopoutController.restoreStream(
                          widget.sessionId,
                          widget.streamId,
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetachedClosingWindowSurface extends StatelessWidget {
  const _DetachedClosingWindowSurface({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerLowest,
      child: Center(child: tiamat.Text.labelLow(message)),
    );
  }
}

class _DetachedCallWindowTitleBar extends StatelessWidget {
  const _DetachedCallWindowTitleBar({
    required this.controller,
    required this.title,
    required this.isAlwaysOnTop,
    required this.isMaximized,
    required this.onToggleTransparentChrome,
    required this.onToggleAlwaysOnTop,
    required this.onDock,
  });

  final RegularWindowController controller;
  final String title;
  final bool isAlwaysOnTop;
  final bool isMaximized;
  final VoidCallback onToggleTransparentChrome;
  final VoidCallback onToggleAlwaysOnTop;
  final VoidCallback onDock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Material(
      color: colorScheme.surfaceContainerLowest,
      child: SizedBox(
        height: _detachedCallWindowTitleBarHeight,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  supportedDevices: const {PointerDeviceKind.mouse},
                  onPanStart: _beginDrag,
                  onDoubleTap: _toggleMaximized,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _DetachedTitleBarButton(
                icon: Icons.opacity_outlined,
                tooltip: 'Transparent chrome',
                semanticLabel: 'Toggle transparent chrome',
                onPressed: onToggleTransparentChrome,
              ),
              _DetachedTitleBarButton(
                icon: isAlwaysOnTop
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
                tooltip: isAlwaysOnTop ? 'Unpin window' : 'Pin window',
                semanticLabel: isAlwaysOnTop
                    ? 'Unpin popout window'
                    : 'Pin popout window',
                onPressed: onToggleAlwaysOnTop,
              ),
              _DetachedTitleBarButton(
                icon: Icons.call_merge_rounded,
                tooltip: 'Dock',
                semanticLabel: 'Dock popout',
                onPressed: onDock,
              ),
              _DetachedTitleBarButton(
                icon: Icons.remove_rounded,
                tooltip: 'Minimize',
                semanticLabel: 'Minimize popout window',
                onPressed: _minimize,
              ),
              _DetachedTitleBarButton(
                icon: isMaximized
                    ? Icons.filter_none_rounded
                    : Icons.crop_square_rounded,
                tooltip: isMaximized ? 'Restore' : 'Maximize',
                semanticLabel: isMaximized
                    ? 'Restore popout window'
                    : 'Maximize popout window',
                onPressed: _toggleMaximized,
              ),
              _DetachedTitleBarButton(
                icon: Icons.close_rounded,
                tooltip: 'Close',
                semanticLabel: 'Close popout window',
                onPressed: onDock,
                danger: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _beginDrag(DragStartDetails _) {
    _beginNativeDetachedWindowDrag(controller);
  }

  void _minimize() {
    _runDetachedWindowAction(
      content: 'Recovered detached call window minimize failure',
      action: () => controller.setMinimized(true),
    );
  }

  void _toggleMaximized() {
    _runDetachedWindowAction(
      content: 'Recovered detached call window maximize failure',
      action: () => controller.setMaximized(!isMaximized),
    );
  }
}

class _DetachedTitleBarButton extends StatelessWidget {
  const _DetachedTitleBarButton({
    required this.icon,
    required this.tooltip,
    required this.semanticLabel,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final String semanticLabel;
  final VoidCallback onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 40,
      height: _detachedCallWindowTitleBarHeight,
      child: tiamat.IconButton(
        icon: icon,
        size: 17,
        tooltip: tooltip,
        semanticLabel: semanticLabel,
        minimumSize: _detachedCallWindowTitleBarHeight,
        backgroundColor: Colors.transparent,
        iconColor: danger ? colorScheme.error : colorScheme.onSurface,
        onPressed: onPressed,
      ),
    );
  }
}

class _DetachedCallWindowChrome extends StatelessWidget {
  const _DetachedCallWindowChrome({
    required this.transparentChrome,
    required this.expanded,
    required this.isAlwaysOnTop,
    required this.onToggleTransparentChrome,
    required this.onToggleAlwaysOnTop,
    required this.onDock,
  });

  final bool transparentChrome;
  final bool expanded;
  final bool isAlwaysOnTop;
  final VoidCallback onToggleTransparentChrome;
  final VoidCallback onToggleAlwaysOnTop;
  final VoidCallback onDock;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final chromeColor = transparentChrome
        ? Colors.black.withAlpha(expanded ? 154 : 106)
        : colorScheme.surfaceContainerHighest.withAlpha(238);
    final borderColor = transparentChrome
        ? Colors.white.withAlpha(expanded ? 76 : 48)
        : colorScheme.outlineVariant.withAlpha(expanded ? 90 : 54);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      constraints: BoxConstraints(
        minHeight: 40,
        maxWidth: expanded
            ? _detachedWindowChromeExpandedWidth
            : _detachedWindowChromeCollapsedWidth,
      ),
      decoration: BoxDecoration(
        color: chromeColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: borderColor,
          width: _detachedWindowChromeBorderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(expanded ? 70 : 34),
            blurRadius: expanded ? 18 : 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: expanded
              ? _detachedWindowChromeExpandedHorizontalPadding
              : _detachedWindowChromeCollapsedHorizontalPadding,
          vertical: 5,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showExpandedControls =
                _shouldShowDetachedWindowExpandedChrome(
                  expanded: expanded,
                  availableWidth: constraints.maxWidth,
                );

            return Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                tiamat.IconButton(
                  icon: transparentChrome
                      ? Icons.opacity_rounded
                      : Icons.opacity_outlined,
                  size: 16,
                  minimumSize: _detachedWindowChromeButtonMinimumSize,
                  tooltip: 'Transparent chrome',
                  semanticLabel: 'Toggle transparent chrome',
                  onPressed: onToggleTransparentChrome,
                ),
                if (showExpandedControls) ...[
                  const SizedBox(width: _detachedWindowChromeButtonSpacing),
                  tiamat.IconButton(
                    icon: isAlwaysOnTop
                        ? Icons.push_pin
                        : Icons.push_pin_outlined,
                    size: 16,
                    tooltip: isAlwaysOnTop ? 'Unpin window' : 'Pin window',
                    semanticLabel: isAlwaysOnTop
                        ? 'Unpin popout window'
                        : 'Pin popout window',
                    onPressed: onToggleAlwaysOnTop,
                  ),
                  const SizedBox(width: _detachedWindowChromeButtonSpacing),
                  tiamat.IconButton(
                    size: 16,
                    tooltip: 'Dock',
                    semanticLabel: 'Dock popout',
                    onPressed: onDock,
                    icon: Icons.call_merge_rounded,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

bool _shouldShowDetachedWindowExpandedChrome({
  required bool expanded,
  required double availableWidth,
}) {
  if (!expanded) {
    return false;
  }
  if (!availableWidth.isFinite) {
    return true;
  }
  return availableWidth >= _detachedWindowChromeExpandedControlsWidth;
}

final class _WinRect extends ffi.Struct {
  @ffi.Int32()
  external int left;

  @ffi.Int32()
  external int top;

  @ffi.Int32()
  external int right;

  @ffi.Int32()
  external int bottom;
}

final class _WinPoint extends ffi.Struct {
  @ffi.Int32()
  external int x;

  @ffi.Int32()
  external int y;
}

final class _WinMargins extends ffi.Struct {
  @ffi.Int32()
  external int left;

  @ffi.Int32()
  external int right;

  @ffi.Int32()
  external int top;

  @ffi.Int32()
  external int bottom;
}

class _DetachedWindowDwmFrameMargins {
  const _DetachedWindowDwmFrameMargins({
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });

  static const zero = _DetachedWindowDwmFrameMargins(
    left: 0,
    right: 0,
    top: 0,
    bottom: 0,
  );

  static const fullClient = _DetachedWindowDwmFrameMargins(
    left: -1,
    right: -1,
    top: -1,
    bottom: -1,
  );

  final int left;
  final int right;
  final int top;
  final int bottom;

  Map<String, int> toJson() => {
    'left': left,
    'right': right,
    'top': top,
    'bottom': bottom,
  };
}

class _DetachedWindowChromeProfile {
  const _DetachedWindowChromeProfile({
    required this.name,
    required this.transparentChrome,
    required this.style,
    required this.exStyle,
    required this.dwmFrameMargins,
  });

  final String name;
  final bool transparentChrome;
  final int style;
  final int exStyle;
  final _DetachedWindowDwmFrameMargins dwmFrameMargins;

  Map<String, Object?> toJson() => {
    'name': name,
    'transparentChrome': transparentChrome,
    'style': _formatHex(style),
    'exStyle': _formatHex(exStyle),
    'dwmFrameMargins': dwmFrameMargins.toJson(),
  };
}

class _WinRectData {
  const _WinRectData({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  factory _WinRectData.fromNative(_WinRect rect) => _WinRectData(
    left: rect.left,
    top: rect.top,
    right: rect.right,
    bottom: rect.bottom,
  );

  final int left;
  final int top;
  final int right;
  final int bottom;

  int get width => right - left;
  int get height => bottom - top;
  int get centerX => left + width ~/ 2;
  int get centerY => top + height ~/ 2;

  _WinRectData shift(int dx, int dy) => _WinRectData(
    left: left + dx,
    top: top + dy,
    right: right + dx,
    bottom: bottom + dy,
  );

  Map<String, int> toJson() => {
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
    'width': width,
    'height': height,
  };
}

typedef _SetWindowPosNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void> hWnd,
      ffi.Pointer<ffi.Void> hWndInsertAfter,
      ffi.Int32 x,
      ffi.Int32 y,
      ffi.Int32 cx,
      ffi.Int32 cy,
      ffi.Uint32 uFlags,
    );

typedef _SetWindowPosDart =
    int Function(
      ffi.Pointer<ffi.Void> hWnd,
      ffi.Pointer<ffi.Void> hWndInsertAfter,
      int x,
      int y,
      int cx,
      int cy,
      int uFlags,
    );

typedef _SendMessageNative =
    ffi.IntPtr Function(
      ffi.Pointer<ffi.Void> hWnd,
      ffi.Uint32 msg,
      ffi.IntPtr wParam,
      ffi.IntPtr lParam,
    );

typedef _SendMessageDart =
    int Function(ffi.Pointer<ffi.Void> hWnd, int msg, int wParam, int lParam);

typedef _ReleaseCaptureNative = ffi.Int32 Function();

typedef _ReleaseCaptureDart = int Function();

typedef _GetWindowLongPtrNative =
    ffi.IntPtr Function(ffi.Pointer<ffi.Void> hWnd, ffi.Int32 nIndex);

typedef _GetWindowLongPtrDart =
    int Function(ffi.Pointer<ffi.Void> hWnd, int nIndex);

typedef _SetWindowLongPtrNative =
    ffi.IntPtr Function(
      ffi.Pointer<ffi.Void> hWnd,
      ffi.Int32 nIndex,
      ffi.IntPtr dwNewLong,
    );

typedef _SetWindowLongPtrDart =
    int Function(ffi.Pointer<ffi.Void> hWnd, int nIndex, int dwNewLong);

typedef _GetWindowRectNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void> hWnd,
      ffi.Pointer<_WinRect> lpRect,
    );

typedef _GetWindowRectDart =
    int Function(ffi.Pointer<ffi.Void> hWnd, ffi.Pointer<_WinRect> lpRect);

typedef _GetClientRectNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void> hWnd,
      ffi.Pointer<_WinRect> lpRect,
    );

typedef _GetClientRectDart =
    int Function(ffi.Pointer<ffi.Void> hWnd, ffi.Pointer<_WinRect> lpRect);

typedef _ClientToScreenNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void> hWnd,
      ffi.Pointer<_WinPoint> lpPoint,
    );

typedef _ClientToScreenDart =
    int Function(ffi.Pointer<ffi.Void> hWnd, ffi.Pointer<_WinPoint> lpPoint);

typedef _GetDpiForWindowNative =
    ffi.Uint32 Function(ffi.Pointer<ffi.Void> hWnd);

typedef _GetDpiForWindowDart = int Function(ffi.Pointer<ffi.Void> hWnd);

typedef _GetDCNative =
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void> hWnd);

typedef _GetDCDart = ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Void> hWnd);

typedef _ReleaseDCNative =
    ffi.Int32 Function(ffi.Pointer<ffi.Void> hWnd, ffi.Pointer<ffi.Void> hDC);

typedef _ReleaseDCDart =
    int Function(ffi.Pointer<ffi.Void> hWnd, ffi.Pointer<ffi.Void> hDC);

typedef _GetPixelNative =
    ffi.Uint32 Function(ffi.Pointer<ffi.Void> hdc, ffi.Int32 x, ffi.Int32 y);

typedef _GetPixelDart = int Function(ffi.Pointer<ffi.Void> hdc, int x, int y);

typedef _DwmSetWindowAttributeNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void> hwnd,
      ffi.Uint32 dwAttribute,
      ffi.Pointer<ffi.Void> pvAttribute,
      ffi.Uint32 cbAttribute,
    );

typedef _DwmSetWindowAttributeDart =
    int Function(
      ffi.Pointer<ffi.Void> hwnd,
      int dwAttribute,
      ffi.Pointer<ffi.Void> pvAttribute,
      int cbAttribute,
    );

typedef _DwmGetWindowAttributeNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void> hwnd,
      ffi.Uint32 dwAttribute,
      ffi.Pointer<ffi.Void> pvAttribute,
      ffi.Uint32 cbAttribute,
    );

typedef _DwmGetWindowAttributeDart =
    int Function(
      ffi.Pointer<ffi.Void> hwnd,
      int dwAttribute,
      ffi.Pointer<ffi.Void> pvAttribute,
      int cbAttribute,
    );

typedef _DwmExtendFrameIntoClientAreaNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void> hwnd,
      ffi.Pointer<_WinMargins> pMarInset,
    );

typedef _DwmExtendFrameIntoClientAreaDart =
    int Function(
      ffi.Pointer<ffi.Void> hwnd,
      ffi.Pointer<_WinMargins> pMarInset,
    );

ffi.DynamicLibrary? _user32Library;
ffi.DynamicLibrary? _dwmapiLibrary;
ffi.DynamicLibrary? _gdi32Library;

ffi.DynamicLibrary get _user32 {
  if (!Platform.isWindows) {
    throw UnsupportedError(
      'Windows user32 APIs are only available on Windows.',
    );
  }
  return _user32Library ??= ffi.DynamicLibrary.open("user32.dll");
}

ffi.DynamicLibrary get _dwmapi {
  if (!Platform.isWindows) {
    throw UnsupportedError('Windows DWM APIs are only available on Windows.');
  }
  return _dwmapiLibrary ??= ffi.DynamicLibrary.open("dwmapi.dll");
}

ffi.DynamicLibrary get _gdi32 {
  if (!Platform.isWindows) {
    throw UnsupportedError('Windows GDI APIs are only available on Windows.');
  }
  return _gdi32Library ??= ffi.DynamicLibrary.open("gdi32.dll");
}

_SetWindowPosDart? _setWindowPosFunction;

_SetWindowPosDart get _setWindowPos => _setWindowPosFunction ??= _user32
    .lookupFunction<_SetWindowPosNative, _SetWindowPosDart>("SetWindowPos");

_SendMessageDart? _sendMessageFunction;

_SendMessageDart get _sendMessage => _sendMessageFunction ??= _user32
    .lookupFunction<_SendMessageNative, _SendMessageDart>("SendMessageW");

_ReleaseCaptureDart? _releaseCaptureFunction;

_ReleaseCaptureDart get _releaseCapture => _releaseCaptureFunction ??= _user32
    .lookupFunction<_ReleaseCaptureNative, _ReleaseCaptureDart>(
      "ReleaseCapture",
    );

_GetWindowLongPtrDart? _getWindowLongPtrFunction;

_GetWindowLongPtrDart get _getWindowLongPtr => _getWindowLongPtrFunction ??=
    _user32.lookupFunction<_GetWindowLongPtrNative, _GetWindowLongPtrDart>(
      "GetWindowLongPtrW",
    );

_SetWindowLongPtrDart? _setWindowLongPtrFunction;

_SetWindowLongPtrDart get _setWindowLongPtr => _setWindowLongPtrFunction ??=
    _user32.lookupFunction<_SetWindowLongPtrNative, _SetWindowLongPtrDart>(
      "SetWindowLongPtrW",
    );

_GetWindowRectDart? _getWindowRectFunction;

_GetWindowRectDart get _getWindowRect => _getWindowRectFunction ??= _user32
    .lookupFunction<_GetWindowRectNative, _GetWindowRectDart>("GetWindowRect");

_GetClientRectDart? _getClientRectFunction;

_GetClientRectDart get _getClientRect => _getClientRectFunction ??= _user32
    .lookupFunction<_GetClientRectNative, _GetClientRectDart>("GetClientRect");

_ClientToScreenDart? _clientToScreenFunction;

_ClientToScreenDart get _clientToScreen => _clientToScreenFunction ??= _user32
    .lookupFunction<_ClientToScreenNative, _ClientToScreenDart>(
      "ClientToScreen",
    );

_GetDpiForWindowDart? _getDpiForWindowFunction;

_GetDpiForWindowDart get _getDpiForWindow => _getDpiForWindowFunction ??=
    _user32.lookupFunction<_GetDpiForWindowNative, _GetDpiForWindowDart>(
      "GetDpiForWindow",
    );

_GetDCDart? _getDCFunction;

_GetDCDart get _getDC => _getDCFunction ??= _user32
    .lookupFunction<_GetDCNative, _GetDCDart>("GetDC");

_ReleaseDCDart? _releaseDCFunction;

_ReleaseDCDart get _releaseDC => _releaseDCFunction ??= _user32
    .lookupFunction<_ReleaseDCNative, _ReleaseDCDart>("ReleaseDC");

_GetPixelDart? _getPixelFunction;

_GetPixelDart get _getPixel => _getPixelFunction ??= _gdi32
    .lookupFunction<_GetPixelNative, _GetPixelDart>("GetPixel");

_DwmSetWindowAttributeDart? _dwmSetWindowAttributeFunction;

_DwmSetWindowAttributeDart get _dwmSetWindowAttribute =>
    _dwmSetWindowAttributeFunction ??= _dwmapi
        .lookupFunction<
          _DwmSetWindowAttributeNative,
          _DwmSetWindowAttributeDart
        >("DwmSetWindowAttribute");

_DwmGetWindowAttributeDart? _dwmGetWindowAttributeFunction;

_DwmGetWindowAttributeDart get _dwmGetWindowAttribute =>
    _dwmGetWindowAttributeFunction ??= _dwmapi
        .lookupFunction<
          _DwmGetWindowAttributeNative,
          _DwmGetWindowAttributeDart
        >("DwmGetWindowAttribute");

_DwmExtendFrameIntoClientAreaDart? _dwmExtendFrameIntoClientAreaFunction;

_DwmExtendFrameIntoClientAreaDart get _dwmExtendFrameIntoClientArea =>
    _dwmExtendFrameIntoClientAreaFunction ??= _dwmapi
        .lookupFunction<
          _DwmExtendFrameIntoClientAreaNative,
          _DwmExtendFrameIntoClientAreaDart
        >("DwmExtendFrameIntoClientArea");

final ffi.Pointer<ffi.Void> _hwndTopMost = ffi.Pointer<ffi.Void>.fromAddress(
  0xFFFFFFFFFFFFFFFF,
);
final ffi.Pointer<ffi.Void> _hwndNotTopMost = ffi.Pointer<ffi.Void>.fromAddress(
  0xFFFFFFFFFFFFFFFE,
);

void _beginNativeDetachedWindowDrag(RegularWindowController controller) {
  if (!Platform.isWindows) {
    return;
  }

  _runDetachedWindowAction(
    content: 'Recovered detached call window drag failure',
    action: () {
      final dynamic nativeController = controller;
      final ffi.Pointer<ffi.Void> hwnd =
          nativeController.getWindowHandle() as ffi.Pointer<ffi.Void>;
      _releaseCapture();
      _sendMessage(hwnd, _wmNcLButtonDown, _htCaption, 0);
    },
  );
}

void _runDetachedWindowAction({
  required String content,
  required VoidCallback action,
}) {
  try {
    action();
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: content,
      category: LogCategory.webrtc,
      source: 'detached-call-window',
    );
  }
}

_DetachedWindowChromeProfile _detachedWindowChromeProfile({
  required int originalStyle,
  required int originalExStyle,
  required bool transparentChrome,
}) {
  final baseStyle = _detachedWindowChromeStyle(originalStyle);
  final style = transparentChrome
      ? _detachedWindowTransparentStyle(baseStyle)
      : _detachedWindowCustomChromeStyle(baseStyle);
  final exStyle = transparentChrome
      ? _detachedWindowTransparentExStyle(originalExStyle)
      : _detachedWindowCustomChromeExStyle(originalExStyle);
  final dwmFrameMargins = transparentChrome
      ? _DetachedWindowDwmFrameMargins.fullClient
      : _DetachedWindowDwmFrameMargins.zero;

  return _DetachedWindowChromeProfile(
    name: transparentChrome
        ? 'transparent_locked_chrome'
        : 'opaque_custom_chrome',
    transparentChrome: transparentChrome,
    style: style,
    exStyle: exStyle,
    dwmFrameMargins: dwmFrameMargins,
  );
}

void _applyDetachedWindowDwmChrome(
  ffi.Pointer<ffi.Void> hwnd, {
  required _DetachedWindowChromeProfile profile,
}) {
  final cornerPreference = pkg_ffi.calloc<ffi.Uint32>();
  final borderColor = pkg_ffi.calloc<ffi.Uint32>();
  final frameMargins = pkg_ffi.calloc<_WinMargins>();

  try {
    frameMargins.ref
      ..left = profile.dwmFrameMargins.left
      ..right = profile.dwmFrameMargins.right
      ..top = profile.dwmFrameMargins.top
      ..bottom = profile.dwmFrameMargins.bottom;
    _dwmExtendFrameIntoClientArea(hwnd, frameMargins);

    cornerPreference.value = _dwmwcpDoNotRound;
    _dwmSetWindowAttribute(
      hwnd,
      _dwmwaWindowCornerPreference,
      cornerPreference.cast<ffi.Void>(),
      ffi.sizeOf<ffi.Uint32>(),
    );

    borderColor.value = _dwmwaColorNone;
    _dwmSetWindowAttribute(
      hwnd,
      _dwmwaBorderColor,
      borderColor.cast<ffi.Void>(),
      ffi.sizeOf<ffi.Uint32>(),
    );
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: 'Recovered detached call window native edge suppression failure',
      category: LogCategory.webrtc,
      source: 'detached-call-window',
    );
  } finally {
    pkg_ffi.calloc.free(cornerPreference);
    pkg_ffi.calloc.free(borderColor);
    pkg_ffi.calloc.free(frameMargins);
  }
}

String _classifyDetachedWindowEdgeOwnership({
  required bool transparentChrome,
  required int style,
  required int exStyle,
  required int? visibleFrameBorderThickness,
  required int? dwmBorderColor,
  required bool sampledWindowEdgeIsLight,
  required bool sampledFlutterSceneEdgeIsLight,
}) {
  if (sampledFlutterSceneEdgeIsLight) {
    return 'flutter_scene_owned';
  }

  final hasNativeFrameChrome =
      (style & (_wsCaption | _wsBorder | _wsThickFrame)) != 0 ||
      (exStyle &
              (_wsExDlgModalFrame |
                  _wsExWindowEdge |
                  _wsExClientEdge |
                  _wsExStaticEdge)) !=
          0;
  if (transparentChrome && hasNativeFrameChrome) {
    return 'state_leakage_owned';
  }

  if (sampledWindowEdgeIsLight &&
      ((visibleFrameBorderThickness ?? 0) > 0 ||
          (dwmBorderColor != null && dwmBorderColor != _dwmwaColorNone))) {
    return 'shadow_or_compositor_owned';
  }

  if (sampledWindowEdgeIsLight) {
    return 'flutter_host_view_background_owned';
  }

  if (hasNativeFrameChrome) {
    return 'native_window_chrome_owned';
  }

  return 'no_edge_artifact_detected';
}

void _recordDetachedWindowChromeDiagnostics({
  required ffi.Pointer<ffi.Void> hwnd,
  required _DetachedWindowChromeProfile profile,
  required int liveStyleBefore,
  required int liveExStyleBefore,
}) {
  if (!_detachedWindowEdgeDiagnosticsEnabled) {
    return;
  }

  try {
    final windowRect = _readWindowRect(hwnd);
    final clientRect = _readClientRect(hwnd);
    final clientScreenRect = _readClientScreenRect(hwnd, clientRect);
    final extendedFrameBounds = _readDwmRectAttribute(
      hwnd,
      _dwmwaExtendedFrameBounds,
    );
    final visibleFrameBorderThickness = _readDwmUint32Attribute(
      hwnd,
      _dwmwaVisibleFrameBorderThickness,
    );
    final dwmBorderColor = _readDwmUint32Attribute(hwnd, _dwmwaBorderColor);
    final cornerPreference = _readDwmUint32Attribute(
      hwnd,
      _dwmwaWindowCornerPreference,
    );
    final dpi = _readDpiForWindow(hwnd);
    final edgePixelSamples = _sampleDetachedWindowEdgePixels(windowRect);
    final sampledWindowEdgeIsLight = edgePixelSamples.values.any(
      (sample) => sample['isLight'] == true,
    );
    final classification = _classifyDetachedWindowEdgeOwnership(
      transparentChrome: profile.transparentChrome,
      style: profile.style,
      exStyle: profile.exStyle,
      visibleFrameBorderThickness: visibleFrameBorderThickness,
      dwmBorderColor: dwmBorderColor,
      sampledWindowEdgeIsLight: sampledWindowEdgeIsLight,
      sampledFlutterSceneEdgeIsLight: false,
    );

    final snapshot = <String, Object?>{
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'stage': 'after_apply_native_window_chrome',
      'hwnd': _formatHex(hwnd.address),
      'classification': classification,
      'chromeProfile': profile.toJson(),
      'style': {
        'before': _formatHex(liveStyleBefore),
        'after': _formatHex(profile.style),
      },
      'exStyle': {
        'before': _formatHex(liveExStyleBefore),
        'after': _formatHex(profile.exStyle),
      },
      'rects': {
        'window': windowRect?.toJson(),
        'client': clientRect?.toJson(),
        'clientScreen': clientScreenRect?.toJson(),
        'dwmExtendedFrameBounds': extendedFrameBounds?.toJson(),
      },
      'dwm': {
        'visibleFrameBorderThickness': visibleFrameBorderThickness,
        'borderColor': dwmBorderColor == null
            ? null
            : _formatHex(dwmBorderColor),
        'cornerPreference': cornerPreference,
        'frameMarginsApplied': profile.dwmFrameMargins.toJson(),
      },
      'dpi': dpi,
      'edgePixelSamples': edgePixelSamples,
      'screenshotPath': null,
      'note':
          'Pixel samples are captured from the native screen DC when diagnostics are enabled.',
    };

    final diagnosticsDirectory = _ensureDetachedWindowDiagnosticsDirectory();
    final fileStem = '${DateTime.now().microsecondsSinceEpoch}-${profile.name}';
    final jsonFile = File(
      '${diagnosticsDirectory.path}${Platform.pathSeparator}$fileStem.json',
    );
    jsonFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(snapshot),
    );
    final reportFile = File(
      '${diagnosticsDirectory.path}${Platform.pathSeparator}report.md',
    );
    reportFile.writeAsStringSync(
      _detachedWindowDiagnosticsMarkdown(snapshot, jsonFile.path),
      mode: FileMode.append,
    );
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: 'Recovered detached call window chrome diagnostics failure',
      category: LogCategory.webrtc,
      source: 'detached-call-window',
    );
  }
}

bool get _detachedWindowEdgeDiagnosticsEnabled {
  final value =
      Platform.environment['INTERGALACTIC_DETACHED_WINDOW_EDGE_DIAGNOSTICS'];
  return value == '1' || value == 'true' || value == 'TRUE';
}

Directory? _detachedWindowDiagnosticsDirectory;

Directory _ensureDetachedWindowDiagnosticsDirectory() {
  final existing = _detachedWindowDiagnosticsDirectory;
  if (existing != null) {
    return existing;
  }

  final override = Platform.environment['INTERGALACTIC_WINDOW_DIAGNOSTICS_DIR'];
  final root = override != null && override.trim().isNotEmpty
      ? Directory(override)
      : Directory(
          '${_workspaceRootForDiagnostics().path}${Platform.pathSeparator}'
          'runtime${Platform.pathSeparator}window-diagnostics',
        );
  final timestamp = DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(':', '')
      .replaceAll('.', '-');
  final directory = Directory(
    '${root.path}${Platform.pathSeparator}transparent-call-border-$timestamp',
  )..createSync(recursive: true);
  _detachedWindowDiagnosticsDirectory = directory;
  return directory;
}

Directory _workspaceRootForDiagnostics() {
  var directory = Directory.current;
  for (var index = 0; index < 8; index += 1) {
    final hasAgentDocs = Directory(
      '${directory.path}${Platform.pathSeparator}docs'
      '${Platform.pathSeparator}agent-control',
    ).existsSync();
    final hasAgentsFile = File(
      '${directory.path}${Platform.pathSeparator}AGENTS.md',
    ).existsSync();
    if (hasAgentDocs && hasAgentsFile) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      break;
    }
    directory = parent;
  }
  return Directory.current;
}

String _detachedWindowDiagnosticsMarkdown(
  Map<String, Object?> snapshot,
  String jsonPath,
) {
  final classification = snapshot['classification'];
  final profile = snapshot['chromeProfile'];
  return '''

## Detached Call Window Edge Capture

- JSON: `$jsonPath`
- Classification: `$classification`
- Profile: `$profile`

''';
}

_WinRectData? _readWindowRect(ffi.Pointer<ffi.Void> hwnd) {
  final rect = pkg_ffi.calloc<_WinRect>();
  try {
    if (_getWindowRect(hwnd, rect) == 0) {
      return null;
    }
    return _WinRectData.fromNative(rect.ref);
  } finally {
    pkg_ffi.calloc.free(rect);
  }
}

_WinRectData? _readClientRect(ffi.Pointer<ffi.Void> hwnd) {
  final rect = pkg_ffi.calloc<_WinRect>();
  try {
    if (_getClientRect(hwnd, rect) == 0) {
      return null;
    }
    return _WinRectData.fromNative(rect.ref);
  } finally {
    pkg_ffi.calloc.free(rect);
  }
}

_WinRectData? _readClientScreenRect(
  ffi.Pointer<ffi.Void> hwnd,
  _WinRectData? clientRect,
) {
  if (clientRect == null) {
    return null;
  }

  final point = pkg_ffi.calloc<_WinPoint>();
  try {
    point.ref
      ..x = 0
      ..y = 0;
    if (_clientToScreen(hwnd, point) == 0) {
      return null;
    }
    return clientRect.shift(point.ref.x, point.ref.y);
  } finally {
    pkg_ffi.calloc.free(point);
  }
}

_WinRectData? _readDwmRectAttribute(ffi.Pointer<ffi.Void> hwnd, int attribute) {
  final rect = pkg_ffi.calloc<_WinRect>();
  try {
    final result = _dwmGetWindowAttribute(
      hwnd,
      attribute,
      rect.cast<ffi.Void>(),
      ffi.sizeOf<_WinRect>(),
    );
    if (result != 0) {
      return null;
    }
    return _WinRectData.fromNative(rect.ref);
  } finally {
    pkg_ffi.calloc.free(rect);
  }
}

int? _readDwmUint32Attribute(ffi.Pointer<ffi.Void> hwnd, int attribute) {
  final value = pkg_ffi.calloc<ffi.Uint32>();
  try {
    final result = _dwmGetWindowAttribute(
      hwnd,
      attribute,
      value.cast<ffi.Void>(),
      ffi.sizeOf<ffi.Uint32>(),
    );
    if (result != 0) {
      return null;
    }
    return value.value;
  } finally {
    pkg_ffi.calloc.free(value);
  }
}

int? _readDpiForWindow(ffi.Pointer<ffi.Void> hwnd) {
  try {
    return _getDpiForWindow(hwnd);
  } catch (_) {
    return null;
  }
}

Map<String, Map<String, Object?>> _sampleDetachedWindowEdgePixels(
  _WinRectData? windowRect,
) {
  if (windowRect == null || windowRect.width <= 0 || windowRect.height <= 0) {
    return const {};
  }

  final hdc = _getDC(ffi.nullptr);
  if (hdc.address == 0) {
    return const {};
  }

  try {
    final points = <String, ({int x, int y})>{
      'topCenter': (x: windowRect.centerX, y: windowRect.top + 1),
      'rightCenter': (x: windowRect.right - 2, y: windowRect.centerY),
      'bottomCenter': (x: windowRect.centerX, y: windowRect.bottom - 2),
      'leftCenter': (x: windowRect.left + 1, y: windowRect.centerY),
    };

    return points.map((name, point) {
      final colorRef = _getPixel(hdc, point.x, point.y);
      return MapEntry(name, {
        'x': point.x,
        'y': point.y,
        'colorRef': colorRef == _clrInvalid ? null : _formatHex(colorRef),
        'isLight': _isLightEdgePixel(colorRef),
      });
    });
  } finally {
    _releaseDC(ffi.nullptr, hdc);
  }
}

bool _isLightEdgePixel(int colorRef) {
  if (colorRef == _clrInvalid) {
    return false;
  }
  final r = colorRef & 0xFF;
  final g = (colorRef >> 8) & 0xFF;
  final b = (colorRef >> 16) & 0xFF;
  return r >= 235 && g >= 235 && b >= 235;
}

String _formatHex(int value) => '0x${value.toUnsigned(64).toRadixString(16)}';

int _detachedWindowChromeStyle(int style) {
  return style |
      _wsCaption |
      _wsThickFrame |
      _wsSysMenu |
      _wsMinimizeBox |
      _wsMaximizeBox;
}

int _detachedWindowCustomChromeStyle(int style) {
  return (style & ~(_wsCaption | _wsBorder)) |
      _wsThickFrame |
      _wsSysMenu |
      _wsMinimizeBox |
      _wsMaximizeBox;
}

int _detachedWindowTransparentStyle(int style) {
  return (style &
          ~(_wsCaption |
              _wsThickFrame |
              _wsBorder |
              _wsSysMenu |
              _wsMinimizeBox |
              _wsMaximizeBox)) |
      _wsPopup;
}

int _detachedWindowCustomChromeExStyle(int exStyle) =>
    _detachedWindowEdgeSafeExStyle(exStyle);

int _detachedWindowTransparentExStyle(int exStyle) {
  return _detachedWindowEdgeSafeExStyle(exStyle);
}

int _detachedWindowEdgeSafeExStyle(int exStyle) {
  return exStyle &
      ~(_wsExDlgModalFrame |
          _wsExWindowEdge |
          _wsExClientEdge |
          _wsExStaticEdge);
}

const int _swpNoSize = 0x0001;
const int _swpNoMove = 0x0002;
const int _swpNoZOrder = 0x0004;
const int _swpNoActivate = 0x0010;
const int _swpFrameChanged = 0x0020;

const int _wmNcLButtonDown = 0x00A1;
const int _htCaption = 2;

const int _gwlStyle = -16;
const int _gwlExStyle = -20;
const int _wsExDlgModalFrame = 0x00000001;
const int _wsExWindowEdge = 0x00000100;
const int _wsExClientEdge = 0x00000200;
const int _wsExStaticEdge = 0x00020000;
const int _wsBorder = 0x00800000;
const int _wsCaption = 0x00C00000;
const int _wsMaximizeBox = 0x00010000;
const int _wsMinimizeBox = 0x00020000;
const int _wsPopup = 0x80000000;
const int _wsSysMenu = 0x00080000;
const int _wsThickFrame = 0x00040000;
const int _dwmwaExtendedFrameBounds = 9;
const int _dwmwaWindowCornerPreference = 33;
const int _dwmwaBorderColor = 34;
const int _dwmwaVisibleFrameBorderThickness = 37;
const int _dwmwcpDoNotRound = 1;
const int _dwmwaColorNone = 0xFFFFFFFE;
const int _clrInvalid = 0xFFFFFFFF;
