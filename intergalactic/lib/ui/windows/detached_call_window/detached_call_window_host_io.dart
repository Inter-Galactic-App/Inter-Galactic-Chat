// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:intergalactic/client/call_manager.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/organisms/call_view/call.dart';
import 'package:intergalactic/utils/app_icon/app_icon_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/foundation/_features.dart' show isWindowingEnabled;
import 'package:flutter/src/widgets/_window.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

bool get supportsDetachedCallWindows =>
    BuildConfig.ENABLE_NATIVE_DETACHED_CALL_WINDOWS &&
    Platform.isWindows &&
    isWindowingEnabled;

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

  late final List<StreamSubscription> _subscriptions;
  final Map<String, _DetachedCallWindowEntry> _entriesBySessionId =
      <String, _DetachedCallWindowEntry>{};

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

    _subscriptions = [
      callPopoutController.onChanged.listen((_) => _syncDetachedWindows()),
      _callManager.currentSessions.onListUpdated
          .listen((_) => _syncDetachedWindows()),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncDetachedWindows();
    });
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }

    callPopoutController.configureNativeDetachedSessions(enabled: false);
    for (final sessionId in _entriesBySessionId.keys.toList(growable: false)) {
      _destroyDetachedSessionWindow(sessionId, updateState: false);
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
          child: _DetachedCallWindowView(
            callManager: _callManager,
            sessionId: entry.sessionId,
          ),
        ),
    ];

    return ViewAnchor(
      view: windows.isEmpty ? null : ViewCollection(views: windows),
      child: widget.child,
    );
  }

  VoipSession? _findSession(String sessionId) {
    return _callManager.currentSessions
        .firstWhereOrNull((session) => session.sessionId == sessionId);
  }

  String _windowTitleForSession(VoipSession session) {
    return "${session.roomName} Call | ${BuildConfig.app}";
  }

  void _syncDetachedWindows() {
    final activeSessionIds = _callManager.currentSessions
        .map((session) => session.sessionId)
        .toSet();
    callPopoutController.clearMissingSessions(activeSessionIds);

    final desiredSessionIds = callPopoutController.poppedSessionIds.toSet();
    final staleSessionIds = _entriesBySessionId.keys
        .where((sessionId) =>
            !desiredSessionIds.contains(sessionId) ||
            !activeSessionIds.contains(sessionId))
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

    if (mounted) {
      setState(() {});
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
    _setNativeTransparentOverlay(
      _entriesBySessionId[session.sessionId]!,
      false,
    );
    unawaited(AppIconManager.instance.apply());
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

  void _destroyDetachedSessionWindow(
    String sessionId, {
    bool updateState = true,
  }) {
    final entry = _entriesBySessionId.remove(sessionId);
    if (entry == null) {
      return;
    }

    entry.controller.destroy();
    if (updateState && mounted) {
      setState(() {});
    }
  }

  Future<void> _focusDetachedSessionWindow(String sessionId) async {
    _entriesBySessionId[sessionId]?.controller.activate();
  }

  Future<bool> _isSessionAlwaysOnTop(String sessionId) async {
    return _entriesBySessionId[sessionId]?.isAlwaysOnTop ?? false;
  }

  Future<void> _setSessionAlwaysOnTop(String sessionId, bool value) async {
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

  Future<bool> _isSessionTransparentChrome(String sessionId) async {
    return _entriesBySessionId[sessionId]?.transparentChrome ?? false;
  }

  Future<void> _setSessionTransparentChrome(
      String sessionId, bool value) async {
    final entry = _entriesBySessionId[sessionId];
    if (entry == null) {
      return;
    }

    entry.transparentChrome = value;
    _setNativeTransparentOverlay(entry, value);
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

  void _setNativeTransparentOverlay(
    _DetachedCallWindowEntry entry,
    bool enabled,
  ) {
    if (!Platform.isWindows) {
      return;
    }

    final dynamic nativeController = entry.controller;
    final ffi.Pointer<ffi.Void> hwnd =
        nativeController.getWindowHandle() as ffi.Pointer<ffi.Void>;

    if (entry.originalStyle == null || entry.originalExStyle == null) {
      entry.originalStyle = _getWindowLongPtr(hwnd, _gwlStyle);
      entry.originalExStyle = _getWindowLongPtr(hwnd, _gwlExStyle);
    }

    final originalStyle = entry.originalStyle!;
    final originalExStyle = entry.originalExStyle!;

    if (enabled) {
      final framelessStyle =
          originalStyle & ~(_wsCaption | _wsThickFrame | _wsBorder);
      _setWindowLongPtr(hwnd, _gwlStyle, framelessStyle);
      _setWindowLongPtr(hwnd, _gwlExStyle, originalExStyle);
    } else {
      _setWindowLongPtr(hwnd, _gwlStyle, originalStyle);
      _setWindowLongPtr(hwnd, _gwlExStyle, originalExStyle);
    }

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
  }
}

class _DetachedCallWindowEntry {
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

class _DetachedWindowDelegate with RegularWindowControllerDelegate {
  _DetachedWindowDelegate({
    required this.handleWindowDestroyed,
  });

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
  });

  final CallManager callManager;
  final String sessionId;

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

  @override
  void initState() {
    super.initState();
    _sessionsSubscription = widget.callManager.currentSessions.onListUpdated
        .listen((_) => _refresh());
    _popoutSubscription =
        callPopoutController.onChanged.listen((_) => _refresh());
    _loadWindowState();
  }

  @override
  void dispose() {
    _sessionsSubscription?.cancel();
    _popoutSubscription?.cancel();
    super.dispose();
  }

  VoipSession? get _session {
    return widget.callManager.currentSessions
        .firstWhereOrNull((session) => session.sessionId == widget.sessionId);
  }

  Future<void> _loadWindowState() async {
    final pinValue =
        await callPopoutController.isSessionWindowAlwaysOnTop(widget.sessionId);
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
      return Center(
        child: tiamat.Text.labelLow("Closing detached call window..."),
      );
    }

    final transparentChrome = _transparentChrome;
    final showChrome = !transparentChrome || _isHovered;
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = transparentChrome
        ? const Color(0x06111214)
        : colorScheme.surfaceContainerLowest;

    return MouseRegion(
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
        decoration: BoxDecoration(
          color: backgroundColor,
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CallWidget(
                session,
                showSessionPopoutButton: false,
                transparentBackground: transparentChrome,
              ),
            ),
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
        maxWidth: expanded ? 168 : 48,
      ),
      decoration: BoxDecoration(
        color: chromeColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
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
          horizontal: expanded ? 10 : 7,
          vertical: 5,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            tiamat.IconButton(
              icon: transparentChrome
                  ? Icons.opacity_rounded
                  : Icons.opacity_outlined,
              size: 16,
              onPressed: onToggleTransparentChrome,
            ),
            if (expanded) ...[
              const SizedBox(width: 4),
              tiamat.IconButton(
                icon: isAlwaysOnTop ? Icons.push_pin : Icons.push_pin_outlined,
                size: 16,
                onPressed: onToggleAlwaysOnTop,
              ),
              const SizedBox(width: 4),
              tiamat.IconButton(
                size: 16,
                onPressed: onDock,
                icon: Icons.call_merge_rounded,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

typedef _SetWindowPosNative = ffi.Int32 Function(
  ffi.Pointer<ffi.Void> hWnd,
  ffi.Pointer<ffi.Void> hWndInsertAfter,
  ffi.Int32 x,
  ffi.Int32 y,
  ffi.Int32 cx,
  ffi.Int32 cy,
  ffi.Uint32 uFlags,
);

typedef _SetWindowPosDart = int Function(
  ffi.Pointer<ffi.Void> hWnd,
  ffi.Pointer<ffi.Void> hWndInsertAfter,
  int x,
  int y,
  int cx,
  int cy,
  int uFlags,
);

typedef _GetWindowLongPtrNative = ffi.IntPtr Function(
  ffi.Pointer<ffi.Void> hWnd,
  ffi.Int32 nIndex,
);

typedef _GetWindowLongPtrDart = int Function(
  ffi.Pointer<ffi.Void> hWnd,
  int nIndex,
);

typedef _SetWindowLongPtrNative = ffi.IntPtr Function(
  ffi.Pointer<ffi.Void> hWnd,
  ffi.Int32 nIndex,
  ffi.IntPtr dwNewLong,
);

typedef _SetWindowLongPtrDart = int Function(
  ffi.Pointer<ffi.Void> hWnd,
  int nIndex,
  int dwNewLong,
);

final ffi.DynamicLibrary _user32 = ffi.DynamicLibrary.open("user32.dll");
final _SetWindowPosDart _setWindowPos = _user32
    .lookupFunction<_SetWindowPosNative, _SetWindowPosDart>("SetWindowPos");
final _GetWindowLongPtrDart _getWindowLongPtr =
    _user32.lookupFunction<_GetWindowLongPtrNative, _GetWindowLongPtrDart>(
  "GetWindowLongPtrW",
);
final _SetWindowLongPtrDart _setWindowLongPtr =
    _user32.lookupFunction<_SetWindowLongPtrNative, _SetWindowLongPtrDart>(
  "SetWindowLongPtrW",
);

final ffi.Pointer<ffi.Void> _hwndTopMost =
    ffi.Pointer<ffi.Void>.fromAddress(0xFFFFFFFFFFFFFFFF);
final ffi.Pointer<ffi.Void> _hwndNotTopMost =
    ffi.Pointer<ffi.Void>.fromAddress(0xFFFFFFFFFFFFFFFE);

const int _swpNoSize = 0x0001;
const int _swpNoMove = 0x0002;
const int _swpNoZOrder = 0x0004;
const int _swpNoActivate = 0x0010;
const int _swpFrameChanged = 0x0020;

const int _gwlStyle = -16;
const int _gwlExStyle = -20;
const int _wsBorder = 0x00800000;
const int _wsCaption = 0x00C00000;
const int _wsThickFrame = 0x00040000;
