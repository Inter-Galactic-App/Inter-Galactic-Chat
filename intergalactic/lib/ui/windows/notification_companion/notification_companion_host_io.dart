// ignore_for_file: implementation_imports
// ignore_for_file: invalid_use_of_internal_member

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/src/foundation/_features.dart' show isWindowingEnabled;
import 'package:flutter/src/widgets/_window.dart';
import 'package:ffi/ffi.dart' as pkg_ffi;
import 'package:intergalactic/client/components/push_notification/notification_companion_controller.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/windows/notification_companion/notification_companion_preview_widgets.dart';
import 'package:window_manager/window_manager.dart';

bool get isNotificationCompanionPlatformSupported =>
    Platform.isWindows || Platform.isMacOS;

bool get isNotificationCompanionWindowingEnabled => isWindowingEnabled;

bool get wasNotificationCompanionWindowingForced =>
    BuildConfig.ENABLE_NATIVE_DETACHED_CALL_WINDOWS &&
    isNotificationCompanionPlatformSupported &&
    !Platform.isMacOS &&
    !isNotificationCompanionWindowingEnabled;

bool get supportsNotificationCompanionOverlay =>
    BuildConfig.ENABLE_NATIVE_DETACHED_CALL_WINDOWS &&
    isNotificationCompanionPlatformSupported &&
    (isNotificationCompanionWindowingEnabled ||
        wasNotificationCompanionWindowingForced);

@visibleForTesting
Widget debugBuildNotificationCompanionRootForTesting({required Widget child}) {
  return _buildNotificationCompanionRoot(child: child);
}

@visibleForTesting
({
  int style,
  int exStyle,
  int frameLeft,
  int frameRight,
  int frameTop,
  int frameBottom,
})
debugResolveNotificationCompanionChromeProfileForTesting({
  required int style,
  required int exStyle,
}) {
  final profile = _notificationCompanionChromeProfile(
    originalStyle: style,
    originalExStyle: exStyle,
  );

  return (
    style: profile.style,
    exStyle: profile.exStyle,
    frameLeft: profile.dwmFrameMargins.left,
    frameRight: profile.dwmFrameMargins.right,
    frameTop: profile.dwmFrameMargins.top,
    frameBottom: profile.dwmFrameMargins.bottom,
  );
}

Widget _buildNotificationCompanionRoot({required Widget child}) {
  return _NotificationCompanionRootSurface(child: Overlay.wrap(child: child));
}

class _NotificationCompanionRootSurface extends StatelessWidget {
  const _NotificationCompanionRootSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: ColoredBox(
        color: Colors.transparent,
        child: SizedBox.expand(child: child),
      ),
    );
  }
}

class NotificationCompanionHost extends StatefulWidget {
  const NotificationCompanionHost({super.key, required this.child});

  final Widget child;

  @override
  State<NotificationCompanionHost> createState() =>
      _NotificationCompanionHostState();
}

class _NotificationCompanionHostState extends State<NotificationCompanionHost> {
  static const Size _windowSize = Size(308, 252);
  static const Duration _messageDisplayDuration = Duration(seconds: 10);

  _NotificationCompanionWindowEntry? _entry;
  NotificationCompanionState _state =
      NotificationCompanionController.instance.state;
  NotificationCompanionMessage? _bubbleMessage;
  Timer? _messageTimeout;
  bool _menuExpanded = false;
  bool _destroyingWindowFromHost = false;
  late final List<StreamSubscription> _subscriptions;

  @override
  void initState() {
    super.initState();
    NotificationCompanionController.instance.setOverlayHostAvailable(true);
    _subscriptions = [
      NotificationCompanionController.instance.stateChanges.listen(_onState),
      preferences.notificationCompanionEnabled.onChanged.listen((enabled) {
        if (enabled) {
          _ensureWindow();
        } else {
          NotificationCompanionController.instance.clearPending();
          _destroyWindow();
        }
      }),
      preferences.notificationCompanionShowPreviews.onChanged.listen(
        (_) => _refresh(),
      ),
      preferences.notificationCompanionHidePreviewsWhileScreenSharing.onChanged
          .listen((_) => _refresh()),
      preferences.notificationCompanionReducedMotion.onChanged.listen(
        (_) => _refresh(),
      ),
      preferences.notificationCompanionClickToOpen.onChanged.listen(
        (_) => _refresh(),
      ),
      preferences.notificationCompanionAvatarVariant.onChanged.listen(
        (_) => _refresh(),
      ),
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (preferences.notificationCompanionEnabled.value) {
        _ensureWindow();
      }
    });
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _messageTimeout?.cancel();
    _destroyWindow(updateState: false);
    NotificationCompanionController.instance.setOverlayHostAvailable(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    return ViewAnchor(
      view: entry == null
          ? null
          : ViewCollection(
              views: [
                RegularWindow(
                  key: entry.windowKey,
                  controller: entry.controller,
                  child: _NotificationCompanionWindow(
                    state: _state,
                    bubbleMessage: _bubbleMessage,
                    menuExpanded: _menuExpanded,
                    windowPosition: Offset(
                      entry.x.toDouble(),
                      entry.y.toDouble(),
                    ),
                    windowSize: _windowSize,
                    monitorBounds: _monitorBoundsForWindow(
                      Offset(entry.x.toDouble(), entry.y.toDouble()),
                    ),
                    onToggleMenu: _toggleMenu,
                    onClose: _disableCompanion,
                    onNotificationTap: _openNotification,
                    onDragStart: _beginWindowDrag,
                    onDragUpdate: _dragWindowToCursor,
                    onDragEnd: _endWindowDrag,
                  ),
                ),
              ],
            ),
      child: widget.child,
    );
  }

  void _onState(NotificationCompanionState state) {
    final previousLatestEventId = _state.latest?.eventId;
    _state = state;

    if (state.count == 0) {
      _messageTimeout?.cancel();
      _bubbleMessage = null;
      _menuExpanded = false;
    } else if (state.latest?.eventId != previousLatestEventId) {
      _bubbleMessage = state.latest;
      _startMessageTimeout(state.latest!);
    }

    if (!preferences.notificationCompanionEnabled.value) {
      _destroyWindow();
      _refresh();
      return;
    }

    _ensureWindow();
    _applyNativeOverlayStyle();
    _refresh();
  }

  void _startMessageTimeout(NotificationCompanionMessage message) {
    _messageTimeout?.cancel();
    _messageTimeout = Timer(_messageDisplayDuration, () {
      if (!mounted || _bubbleMessage?.eventId != message.eventId) {
        return;
      }

      setState(() {
        _bubbleMessage = null;
      });
    });
  }

  void _toggleMenu() {
    setState(() {
      _menuExpanded = !_menuExpanded;
    });
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  void _ensureWindow() {
    if (_entry != null) {
      return;
    }

    try {
      _destroyingWindowFromHost = false;
      final initialPosition = _clampWindowPosition(
        Offset(
          preferences.notificationCompanionWindowX.value,
          preferences.notificationCompanionWindowY.value,
        ),
      );

      final controller = RegularWindowController(
        preferredSize: _windowSize,
        preferredConstraints: const BoxConstraints.tightFor(
          width: 308,
          height: 252,
        ),
        title: "${BuildConfig.app} Companion",
        delegate: _NotificationCompanionWindowDelegate(
          handleWindowDestroyed: _onWindowDestroyed,
        ),
      );

      _entry = _NotificationCompanionWindowEntry(
        windowKey: const ValueKey<String>("notification-companion-window"),
        controller: controller,
        x: initialPosition.dx.round(),
        y: initialPosition.dy.round(),
      );

      NotificationCompanionController.instance.setOverlayHostAvailable(true);
      NotificationCompanionController.instance.setOverlayOpen(true);
      _refresh();
      _scheduleWindowActivation(_entry!);
    } catch (error, stackTrace) {
      _recoverWindowCreationFailure(error, stackTrace);
    }
  }

  void _scheduleWindowActivation(_NotificationCompanionWindowEntry entry) {
    if (entry.activationScheduled || entry.activated) {
      return;
    }

    entry.activationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_entry, entry)) {
        return;
      }

      entry.activationScheduled = false;
      _activateWindow(entry);
    });
  }

  void _activateWindow(_NotificationCompanionWindowEntry entry) {
    try {
      entry.controller.activate();
      entry.activated = true;
      _applyNativeOverlayStyle();
      _refresh();
    } catch (error, stackTrace) {
      if (identical(_entry, entry)) {
        _destroyRecoveredWindowController(entry);
        _recoverWindowCreationFailure(error, stackTrace);
      }
    }
  }

  void _destroyRecoveredWindowController(
    _NotificationCompanionWindowEntry entry,
  ) {
    try {
      entry.controller.destroy();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Recovered notification companion window cleanup failure',
        category: LogCategory.notifications,
        source: 'notification-companion',
      );
    }
  }

  void _recoverWindowCreationFailure(Object error, StackTrace stackTrace) {
    _entry = null;
    NotificationCompanionController.instance.setOverlayHostAvailable(false);
    NotificationCompanionController.instance.setOverlayOpen(false);
    unawaited(preferences.notificationCompanionEnabled.set(false));
    Log.onError(
      error,
      stackTrace,
      content:
          'Recovered notification companion window creation failure; companion disabled',
      category: LogCategory.notifications,
      source: 'notification-companion',
    );
    _refresh();
  }

  void _destroyWindow({bool updateState = true}) {
    final entry = _entry;
    if (entry == null) {
      return;
    }

    _entry = null;
    NotificationCompanionController.instance.setOverlayOpen(false);
    _saveWindowPosition(entry);
    _destroyingWindowFromHost = true;
    try {
      entry.controller.destroy();
    } catch (error, stackTrace) {
      _destroyingWindowFromHost = false;
      Log.onError(
        error,
        stackTrace,
        content: 'Recovered notification companion window cleanup failure',
        category: LogCategory.notifications,
        source: 'notification-companion',
      );
    }
    if (updateState) {
      _refresh();
    }
  }

  void _onWindowDestroyed() {
    final shouldDisablePreference = !_destroyingWindowFromHost;
    _destroyingWindowFromHost = false;
    _entry = null;
    NotificationCompanionController.instance.setOverlayOpen(false);
    if (mounted && shouldDisablePreference) {
      unawaited(preferences.notificationCompanionEnabled.set(false));
      setState(() {});
    }
  }

  void _disableCompanion() {
    unawaited(preferences.notificationCompanionEnabled.set(false));
  }

  void _openNotification(NotificationCompanionMessage message) {
    final shouldOpen = preferences.notificationCompanionClickToOpen.value;
    NotificationCompanionController.instance.open(message);
    if (shouldOpen) {
      unawaited(_showMainWindowForNotification());
    }
  }

  Future<void> _showMainWindowForNotification() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to show main window from notification companion',
        category: LogCategory.notifications,
        source: 'notification-companion',
      );
    }
  }

  void _beginWindowDrag() {
    final entry = _entry;
    if (entry == null) {
      return;
    }

    final cursorPosition = _cursorPosition();
    if (cursorPosition == null) {
      return;
    }

    entry
      ..dragCursorOrigin = cursorPosition
      ..dragWindowOrigin = Offset(entry.x.toDouble(), entry.y.toDouble());
  }

  void _dragWindowToCursor() {
    final entry = _entry;
    if (entry == null) {
      return;
    }

    final cursorPosition = _cursorPosition();
    final dragCursorOrigin = entry.dragCursorOrigin;
    final dragWindowOrigin = entry.dragWindowOrigin;
    if (cursorPosition == null ||
        dragCursorOrigin == null ||
        dragWindowOrigin == null) {
      return;
    }

    final dragOffset = cursorPosition - dragCursorOrigin;
    final nextPosition = _clampWindowPosition(dragWindowOrigin + dragOffset);
    entry
      ..x = nextPosition.dx.round()
      ..y = nextPosition.dy.round();

    _positionWindow(entry, applyFrameChange: false);
  }

  void _endWindowDrag() {
    final entry = _entry;
    if (entry == null) {
      return;
    }

    entry
      ..dragCursorOrigin = null
      ..dragWindowOrigin = null;
    _saveWindowPosition(entry);
    _refresh();
  }

  Offset _clampWindowPosition(Offset position) {
    final bounds = _monitorBoundsForWindow(position);
    final minX = bounds.left;
    final minY = bounds.top;
    final maxX = bounds.right - _windowSize.width < minX
        ? minX
        : bounds.right - _windowSize.width;
    final maxY = bounds.bottom - _windowSize.height < minY
        ? minY
        : bounds.bottom - _windowSize.height;

    return Offset(
      position.dx.clamp(minX, maxX).toDouble(),
      position.dy.clamp(minY, maxY).toDouble(),
    );
  }

  void _saveWindowPosition(_NotificationCompanionWindowEntry entry) {
    unawaited(preferences.notificationCompanionWindowX.set(entry.x.toDouble()));
    unawaited(preferences.notificationCompanionWindowY.set(entry.y.toDouble()));
  }

  Offset? _cursorPosition() {
    if (!Platform.isWindows) {
      return null;
    }

    final point = pkg_ffi.calloc<_Point>();
    try {
      if (_getCursorPos(point) == 0) {
        return null;
      }

      return Offset(point.ref.x.toDouble(), point.ref.y.toDouble());
    } finally {
      pkg_ffi.calloc.free(point);
    }
  }

  _ScreenBounds _monitorBoundsForWindow(Offset windowPosition) {
    if (!Platform.isWindows) {
      return _fallbackScreenBounds;
    }

    final rect = pkg_ffi.calloc<_Rect>();
    final monitorInfo = pkg_ffi.calloc<_MonitorInfo>();

    try {
      rect.ref
        ..left = windowPosition.dx.round()
        ..top = windowPosition.dy.round()
        ..right = windowPosition.dx.round() + _windowSize.width.round()
        ..bottom = windowPosition.dy.round() + _windowSize.height.round();

      final monitor = _monitorFromRect(rect, _monitorDefaultToNearest);
      if (monitor.address == 0) {
        return _virtualScreenBounds;
      }

      monitorInfo.ref.cbSize = ffi.sizeOf<_MonitorInfo>();
      if (_getMonitorInfo(monitor, monitorInfo) == 0) {
        return _virtualScreenBounds;
      }

      final monitorRect = monitorInfo.ref.rcMonitor;
      return _ScreenBounds(
        left: monitorRect.left.toDouble(),
        top: monitorRect.top.toDouble(),
        right: monitorRect.right.toDouble(),
        bottom: monitorRect.bottom.toDouble(),
      );
    } finally {
      pkg_ffi.calloc.free(rect);
      pkg_ffi.calloc.free(monitorInfo);
    }
  }

  _ScreenBounds get _virtualScreenBounds {
    if (!Platform.isWindows) {
      return _fallbackScreenBounds;
    }

    final left = _getSystemMetrics(_smXVirtualScreen);
    final top = _getSystemMetrics(_smYVirtualScreen);
    final width = _getSystemMetrics(_smCxVirtualScreen);
    final height = _getSystemMetrics(_smCyVirtualScreen);

    if (width <= 0 || height <= 0) {
      return const _ScreenBounds(left: 0, top: 0, right: 1920, bottom: 1080);
    }

    return _ScreenBounds(
      left: left.toDouble(),
      top: top.toDouble(),
      right: (left + width).toDouble(),
      bottom: (top + height).toDouble(),
    );
  }

  void _applyNativeOverlayStyle() {
    final entry = _entry;
    if (entry == null || !entry.activated || !Platform.isWindows) {
      return;
    }

    final dynamic nativeController = entry.controller;
    final ffi.Pointer<ffi.Void> hwnd =
        nativeController.getWindowHandle() as ffi.Pointer<ffi.Void>;

    if (entry.originalStyle == null || entry.originalExStyle == null) {
      entry.originalStyle = _getWindowLongPtr(hwnd, _gwlStyle);
      entry.originalExStyle = _getWindowLongPtr(hwnd, _gwlExStyle);
    }

    final profile = _notificationCompanionChromeProfile(
      originalStyle: entry.originalStyle!,
      originalExStyle: entry.originalExStyle!,
    );

    _setWindowLongPtr(hwnd, _gwlStyle, profile.style);
    _setWindowLongPtr(hwnd, _gwlExStyle, profile.exStyle);
    _applyTransparentDwmChrome(hwnd, profile: profile);
    _positionWindow(entry, applyFrameChange: true);
  }

  void _applyTransparentDwmChrome(
    ffi.Pointer<ffi.Void> hwnd, {
    required _NotificationCompanionChromeProfile profile,
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
        content: 'Recovered notification companion native transparency failure',
        category: LogCategory.notifications,
        source: 'notification-companion',
      );
    } finally {
      pkg_ffi.calloc.free(cornerPreference);
      pkg_ffi.calloc.free(borderColor);
      pkg_ffi.calloc.free(frameMargins);
    }
  }

  void _positionWindow(
    _NotificationCompanionWindowEntry entry, {
    required bool applyFrameChange,
  }) {
    if (!Platform.isWindows) {
      return;
    }

    final dynamic nativeController = entry.controller;
    final ffi.Pointer<ffi.Void> hwnd =
        nativeController.getWindowHandle() as ffi.Pointer<ffi.Void>;

    _setWindowPos(
      hwnd,
      _hwndTopMost,
      entry.x,
      entry.y,
      _windowSize.width.round(),
      _windowSize.height.round(),
      _swpNoActivate |
          _swpShowWindow |
          (applyFrameChange ? _swpFrameChanged : 0),
    );
  }
}

class _NotificationCompanionWindowEntry {
  _NotificationCompanionWindowEntry({
    required this.windowKey,
    required this.controller,
    required this.x,
    required this.y,
  });

  final ValueKey<String> windowKey;
  final RegularWindowController controller;
  int x;
  int y;
  int? originalStyle;
  int? originalExStyle;
  Offset? dragCursorOrigin;
  Offset? dragWindowOrigin;
  bool activated = false;
  bool activationScheduled = false;
}

class _NotificationCompanionWindowDelegate
    with RegularWindowControllerDelegate {
  _NotificationCompanionWindowDelegate({required this.handleWindowDestroyed});

  final VoidCallback handleWindowDestroyed;

  @override
  void onWindowDestroyed() {
    handleWindowDestroyed();
  }
}

class _NotificationCompanionWindow extends StatefulWidget {
  const _NotificationCompanionWindow({
    required this.state,
    required this.bubbleMessage,
    required this.menuExpanded,
    required this.windowPosition,
    required this.windowSize,
    required this.monitorBounds,
    required this.onToggleMenu,
    required this.onClose,
    required this.onNotificationTap,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final NotificationCompanionState state;
  final NotificationCompanionMessage? bubbleMessage;
  final bool menuExpanded;
  final Offset windowPosition;
  final Size windowSize;
  final _ScreenBounds monitorBounds;
  final VoidCallback onToggleMenu;
  final VoidCallback onClose;
  final ValueChanged<NotificationCompanionMessage> onNotificationTap;
  final VoidCallback onDragStart;
  final VoidCallback onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  State<_NotificationCompanionWindow> createState() =>
      _NotificationCompanionWindowState();
}

class _NotificationCompanionWindowState
    extends State<_NotificationCompanionWindow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _idleController;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _idleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion = preferences.notificationCompanionReducedMotion.value;
    final placement = _resolvePanelPlacement();
    final bubbleTop = placement.showBelow ? 132.0 : null;
    final bubbleBottom = placement.showBelow ? null : 132.0;
    final bubbleLeft = placement.alignLeft ? 14.0 : null;
    final bubbleRight = placement.alignLeft ? null : 14.0;
    final menuPanelTop = placement.showBelow ? 142.0 : 8.0;
    final menuHeight = _menuHeightFor(
      messageCount: widget.state.messages.length,
      showBelow: placement.showBelow,
    );
    final menuTop = placement.showBelow ? menuPanelTop : 116.0 - menuHeight;

    return _buildNotificationCompanionRoot(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        opaque: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) {
            _setDragging(true);
            widget.onDragStart();
          },
          onPanEnd: (_) {
            _setDragging(false);
            widget.onDragEnd();
          },
          onPanCancel: () {
            _setDragging(false);
            widget.onDragEnd();
          },
          onPanUpdate: (_) => widget.onDragUpdate(),
          child: SizedBox.expand(
            child: AnimatedBuilder(
              animation: _idleController,
              builder: (context, child) {
                final idleLift = reducedMotion || _isDragging
                    ? 0.0
                    : (_idleController.value - 0.5) * 4;
                return Transform.translate(
                  offset: Offset(0, idleLift),
                  child: child,
                );
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: placement.alignLeft ? 20 : null,
                    right: placement.alignLeft ? null : 20,
                    top: placement.showBelow ? 14 : null,
                    bottom: placement.showBelow ? null : 14,
                    width: 120,
                    height: 120,
                    child: _CompanionAvatar(
                      notificationCount: widget.state.count,
                      onTap: widget.state.latest == null
                          ? null
                          : () =>
                                widget.onNotificationTap(widget.state.latest!),
                    ),
                  ),
                  Positioned(
                    left: placement.alignLeft ? 148 : null,
                    right: placement.alignLeft ? null : 148,
                    top: placement.showBelow ? 76 : null,
                    bottom: placement.showBelow ? null : 76,
                    child: _CompanionMenuButton(
                      expanded: widget.menuExpanded,
                      onTap: widget.onToggleMenu,
                    ),
                  ),
                  Positioned(
                    top: bubbleTop,
                    bottom: bubbleBottom,
                    left: bubbleLeft,
                    right: bubbleRight,
                    width: 164,
                    child: AnimatedSwitcher(
                      duration: reducedMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      child: widget.bubbleMessage == null
                          ? const SizedBox.shrink()
                          : _CompanionBubble(
                              key: ValueKey<String>(
                                widget.bubbleMessage!.eventId,
                              ),
                              message: widget.bubbleMessage!,
                              onTap: () => widget.onNotificationTap(
                                widget.bubbleMessage!,
                              ),
                            ),
                    ),
                  ),
                  Positioned(
                    top: menuTop,
                    left: placement.alignLeft ? 78 : null,
                    right: placement.alignLeft ? null : 78,
                    width: 204,
                    child: AnimatedSwitcher(
                      duration: reducedMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 160),
                      child: widget.menuExpanded
                          ? _CompanionNotificationMenu(
                              messages: widget.state.messages,
                              height: menuHeight,
                              onClose: widget.onClose,
                              onNotificationTap: widget.onNotificationTap,
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setDragging(bool value) {
    if (_isDragging == value) {
      return;
    }

    setState(() {
      _isDragging = value;
    });

    if (value) {
      _idleController.stop();
      return;
    }

    if (!preferences.notificationCompanionReducedMotion.value) {
      _idleController.repeat(reverse: true);
    }
  }

  _PanelPlacement _resolvePanelPlacement() {
    const edgePadding = 80.0;

    final nearTop =
        widget.windowPosition.dy <= widget.monitorBounds.top + edgePadding;
    final nearBottom =
        widget.windowPosition.dy + widget.windowSize.height >=
        widget.monitorBounds.bottom - edgePadding;
    final nearLeft =
        widget.windowPosition.dx <= widget.monitorBounds.left + edgePadding;
    final nearRight =
        widget.windowPosition.dx + widget.windowSize.width >=
        widget.monitorBounds.right - edgePadding;

    return _PanelPlacement(
      showBelow: nearTop && !nearBottom,
      alignLeft: nearLeft && !nearRight,
    );
  }

  double _menuHeightFor({required int messageCount, required bool showBelow}) {
    final visibleMessageCount = messageCount <= 0
        ? 1
        : messageCount > 3
        ? 3
        : messageCount;
    final desiredHeight = 50 + (visibleMessageCount * 42.0);
    final maxHeight = showBelow ? widget.windowSize.height - 150.0 : 108.0;

    return desiredHeight.clamp(82.0, maxHeight).toDouble();
  }
}

class _ScreenBounds {
  const _ScreenBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;
}

const _ScreenBounds _fallbackScreenBounds = _ScreenBounds(
  left: 0,
  top: 0,
  right: 1920,
  bottom: 1080,
);

class _PanelPlacement {
  const _PanelPlacement({required this.showBelow, required this.alignLeft});

  final bool showBelow;
  final bool alignLeft;
}

class _CompanionAvatar extends StatelessWidget {
  const _CompanionAvatar({
    required this.notificationCount,
    required this.onTap,
  });

  final int notificationCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return NotificationCompanionAvatarPreview(
      notificationCount: notificationCount,
      assetVariant: preferences.notificationCompanionAvatarVariant.value,
      onTap: onTap,
      size: 120,
    );
  }
}

class _CompanionMenuButton extends StatelessWidget {
  const _CompanionMenuButton({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colorScheme.surfaceContainerHighest.withAlpha(232),
          border: Border.all(color: colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(42),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          expanded
              ? Icons.keyboard_arrow_down_rounded
              : Icons.keyboard_arrow_up_rounded,
          color: colorScheme.onSurface,
          size: 24,
        ),
      ),
    );
  }
}

class _CompanionBubble extends StatelessWidget {
  const _CompanionBubble({
    super.key,
    required this.message,
    required this.onTap,
  });

  final NotificationCompanionMessage message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NotificationCompanionBubblePreview(
      roomName: message.roomName,
      senderName: message.senderName,
      body: message.body,
      isDirectMessage: message.isDirectMessage,
      onTap: onTap,
    );
  }
}

class _CompanionNotificationMenu extends StatelessWidget {
  const _CompanionNotificationMenu({
    required this.messages,
    required this.height,
    required this.onClose,
    required this.onNotificationTap,
  });

  final List<NotificationCompanionMessage> messages;
  final double height;
  final VoidCallback onClose;
  final ValueChanged<NotificationCompanionMessage> onNotificationTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final visibleMessages = messages.reversed.toList();

    return Material(
      color: Colors.transparent,
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withAlpha(246),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(48),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "${messages.length} pending",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: onClose,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close_rounded,
                          size: 15,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: visibleMessages.isEmpty
                      ? Align(
                          alignment: Alignment.topLeft,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4, 4, 4, 7),
                            child: Text(
                              "No pending notifications",
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (final message in visibleMessages)
                                _CompanionNotificationMenuItem(
                                  message: message,
                                  onTap: () => onNotificationTap(message),
                                ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompanionNotificationMenuItem extends StatelessWidget {
  const _CompanionNotificationMenuItem({
    required this.message,
    required this.onTap,
  });

  final NotificationCompanionMessage message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            Icon(
              Icons.mode_comment_rounded,
              size: 15,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.roomName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    message.senderName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationCompanionChromeProfile {
  const _NotificationCompanionChromeProfile({
    required this.style,
    required this.exStyle,
    required this.dwmFrameMargins,
  });

  final int style;
  final int exStyle;
  final _NotificationCompanionDwmFrameMargins dwmFrameMargins;
}

class _NotificationCompanionDwmFrameMargins {
  const _NotificationCompanionDwmFrameMargins({
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });

  static const fullClient = _NotificationCompanionDwmFrameMargins(
    left: -1,
    right: -1,
    top: -1,
    bottom: -1,
  );

  final int left;
  final int right;
  final int top;
  final int bottom;
}

_NotificationCompanionChromeProfile _notificationCompanionChromeProfile({
  required int originalStyle,
  required int originalExStyle,
}) {
  return _NotificationCompanionChromeProfile(
    style: _notificationCompanionWindowStyle(originalStyle),
    exStyle: _notificationCompanionWindowExStyle(originalExStyle),
    dwmFrameMargins: _NotificationCompanionDwmFrameMargins.fullClient,
  );
}

int _notificationCompanionWindowStyle(int style) {
  return (style &
          ~(_wsCaption |
              _wsThickFrame |
              _wsBorder |
              _wsSysMenu |
              _wsMinimizeBox |
              _wsMaximizeBox)) |
      _wsPopup;
}

int _notificationCompanionWindowExStyle(int exStyle) {
  return (exStyle | _wsExToolWindow) &
      ~(_wsExAppWindow |
          _wsExWindowEdge |
          _wsExClientEdge |
          _wsExDlgModalFrame |
          _wsExStaticEdge);
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

final class _Point extends ffi.Struct {
  @ffi.Int32()
  external int x;

  @ffi.Int32()
  external int y;
}

final class _Rect extends ffi.Struct {
  @ffi.Int32()
  external int left;

  @ffi.Int32()
  external int top;

  @ffi.Int32()
  external int right;

  @ffi.Int32()
  external int bottom;
}

final class _MonitorInfo extends ffi.Struct {
  @ffi.Uint32()
  external int cbSize;

  external _Rect rcMonitor;

  external _Rect rcWork;

  @ffi.Uint32()
  external int dwFlags;
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

typedef _GetCursorPosNative = ffi.Int32 Function(ffi.Pointer<_Point> lpPoint);

typedef _GetCursorPosDart = int Function(ffi.Pointer<_Point> lpPoint);

typedef _GetSystemMetricsNative = ffi.Int32 Function(ffi.Int32 nIndex);

typedef _GetSystemMetricsDart = int Function(int nIndex);

typedef _MonitorFromRectNative =
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<_Rect> lprc, ffi.Uint32 dwFlags);

typedef _MonitorFromRectDart =
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<_Rect> lprc, int dwFlags);

typedef _GetMonitorInfoNative =
    ffi.Int32 Function(
      ffi.Pointer<ffi.Void> hMonitor,
      ffi.Pointer<_MonitorInfo> lpmi,
    );

typedef _GetMonitorInfoDart =
    int Function(
      ffi.Pointer<ffi.Void> hMonitor,
      ffi.Pointer<_MonitorInfo> lpmi,
    );

ffi.DynamicLibrary? _user32Library;
ffi.DynamicLibrary? _dwmapiLibrary;

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

_SetWindowPosDart? _setWindowPosFunction;

_SetWindowPosDart get _setWindowPos => _setWindowPosFunction ??= _user32
    .lookupFunction<_SetWindowPosNative, _SetWindowPosDart>("SetWindowPos");

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

_GetCursorPosDart? _getCursorPosFunction;

_GetCursorPosDart get _getCursorPos => _getCursorPosFunction ??= _user32
    .lookupFunction<_GetCursorPosNative, _GetCursorPosDart>("GetCursorPos");

_GetSystemMetricsDart? _getSystemMetricsFunction;

_GetSystemMetricsDart get _getSystemMetrics => _getSystemMetricsFunction ??=
    _user32.lookupFunction<_GetSystemMetricsNative, _GetSystemMetricsDart>(
      "GetSystemMetrics",
    );

_MonitorFromRectDart? _monitorFromRectFunction;

_MonitorFromRectDart get _monitorFromRect => _monitorFromRectFunction ??=
    _user32.lookupFunction<_MonitorFromRectNative, _MonitorFromRectDart>(
      "MonitorFromRect",
    );

_GetMonitorInfoDart? _getMonitorInfoFunction;

_GetMonitorInfoDart get _getMonitorInfo => _getMonitorInfoFunction ??= _user32
    .lookupFunction<_GetMonitorInfoNative, _GetMonitorInfoDart>(
      "GetMonitorInfoW",
    );

_DwmSetWindowAttributeDart? _dwmSetWindowAttributeFunction;

_DwmSetWindowAttributeDart get _dwmSetWindowAttribute =>
    _dwmSetWindowAttributeFunction ??= _dwmapi
        .lookupFunction<
          _DwmSetWindowAttributeNative,
          _DwmSetWindowAttributeDart
        >("DwmSetWindowAttribute");

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

const int _swpNoActivate = 0x0010;
const int _swpFrameChanged = 0x0020;
const int _swpShowWindow = 0x0040;

const int _gwlStyle = -16;
const int _gwlExStyle = -20;
const int _monitorDefaultToNearest = 0x00000002;
const int _smXVirtualScreen = 76;
const int _smYVirtualScreen = 77;
const int _smCxVirtualScreen = 78;
const int _smCyVirtualScreen = 79;
const int _wsBorder = 0x00800000;
const int _wsCaption = 0x00C00000;
const int _wsMaximizeBox = 0x00010000;
const int _wsMinimizeBox = 0x00020000;
const int _wsPopup = 0x80000000;
const int _wsSysMenu = 0x00080000;
const int _wsThickFrame = 0x00040000;
const int _wsExClientEdge = 0x00000200;
const int _wsExDlgModalFrame = 0x00000001;
const int _wsExStaticEdge = 0x00020000;
const int _wsExToolWindow = 0x00000080;
const int _wsExAppWindow = 0x00040000;
const int _wsExWindowEdge = 0x00000100;
const int _dwmwaWindowCornerPreference = 33;
const int _dwmwaBorderColor = 34;
const int _dwmwcpDoNotRound = 1;
const int _dwmwaColorNone = 0xFFFFFFFE;
