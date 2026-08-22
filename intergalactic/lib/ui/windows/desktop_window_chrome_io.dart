import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intergalactic/config/app_globals.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';
import 'package:intergalactic/ui/navigation/desktop_navigation_history.dart';
import 'package:intergalactic/ui/pages/settings/app_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/help/settings_category_help.dart';
import 'package:intergalactic/ui/pages/settings/settings_navigation.dart';
import 'package:intergalactic/ui/windows/developer_title_bar_menu.dart';
import 'package:window_manager/window_manager.dart';

class DesktopWindowFrame extends StatefulWidget {
  const DesktopWindowFrame({
    required this.child,
    this.navigatorKey,
    this.showNavigation = true,
    this.showHelp = true,
    this.showSmallWindowToggle = true,
    super.key,
  });

  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;
  final bool showNavigation;
  final bool showHelp;
  final bool showSmallWindowToggle;

  @override
  State<DesktopWindowFrame> createState() => _DesktopWindowFrameState();
}

class _DesktopWindowFrameState extends State<DesktopWindowFrame>
    with WindowListener {
  bool _isFullScreen = false;

  bool get _isEnabled => BuildConfig.DESKTOP && PlatformUtils.isWindows;

  @override
  void initState() {
    super.initState();
    if (_isEnabled) {
      windowManager.addListener(this);
      unawaited(_syncFullScreen());
    }
  }

  @override
  void dispose() {
    if (_isEnabled) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  Future<void> _syncFullScreen() async {
    try {
      final isFullScreen = await windowManager.isFullScreen();
      if (mounted) {
        setState(() => _isFullScreen = isFullScreen);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_isEnabled || _isFullScreen) {
      return widget.child;
    }

    return VirtualWindowFrame(
      child: Overlay.wrap(
        // The custom title bar is outside the app Navigator overlay. Give it a
        // local overlay so tooltips and transient chrome do not render as
        // Flutter error surfaces on Windows desktop.
        child: Column(
          children: [
            DesktopTitleBar(
              navigatorKey: widget.navigatorKey,
              showNavigation: widget.showNavigation,
              showHelp: widget.showHelp,
              showSmallWindowToggle: widget.showSmallWindowToggle,
            ),
            Expanded(child: widget.child),
          ],
        ),
      ),
    );
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) {
      setState(() => _isFullScreen = true);
    }
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) {
      setState(() => _isFullScreen = false);
    }
  }
}

class DesktopTitleBar extends StatefulWidget {
  const DesktopTitleBar({
    this.navigatorKey,
    this.showNavigation = true,
    this.showHelp = true,
    this.showSmallWindowToggle = true,
    super.key,
  });

  final GlobalKey<NavigatorState>? navigatorKey;
  final bool showNavigation;
  final bool showHelp;
  final bool showSmallWindowToggle;

  @override
  State<DesktopTitleBar> createState() => _DesktopTitleBarState();
}

class _DesktopTitleBarState extends State<DesktopTitleBar> with WindowListener {
  static const double _height = 40;
  bool _isMaximized = false;
  bool _smallWindowMode = preferences.desktopSmallWindowMode.value;
  StreamSubscription<bool>? _smallWindowModeSubscription;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_syncMaximized());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DesktopRouteStackController.instance.refresh();
    });
    if (widget.showSmallWindowToggle) {
      _smallWindowModeSubscription = preferences
          .desktopSmallWindowMode
          .onChanged
          .listen((value) {
            if (mounted) {
              setState(() => _smallWindowMode = value);
            }
          });
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    unawaited(_smallWindowModeSubscription?.cancel());
    super.dispose();
  }

  Future<void> _syncMaximized() async {
    try {
      final isMaximized = await windowManager.isMaximized();
      if (mounted) {
        setState(() => _isMaximized = isMaximized);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surfaceContainerLowest,
      child: SizedBox(
        height: _height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: scheme.outline.withValues(alpha: 0.22)),
            ),
          ),
          child: Row(
            children: [
              _NavigationButtons(
                navigatorKey: widget.navigatorKey,
                showNavigation: widget.showNavigation,
              ),
              Expanded(
                child: DragToMoveArea(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        BuildConfig.app,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              DeveloperTitleBarMenu(navigatorKey: widget.navigatorKey),
              if (widget.showSmallWindowToggle)
                _TitleBarButton(
                  icon: _smallWindowMode
                      ? Icons.open_in_full_rounded
                      : Icons.close_fullscreen_rounded,
                  tooltip: _smallWindowMode
                      ? 'Exit small-window mode'
                      : 'Enter small-window mode',
                  semanticLabel: _smallWindowMode
                      ? 'Exit small-window mode'
                      : 'Enter small-window mode',
                  onPressed: () {
                    unawaited(
                      preferences.desktopSmallWindowMode.set(!_smallWindowMode),
                    );
                  },
                  active: _smallWindowMode,
                ),
              if (widget.showHelp)
                _TitleBarButton(
                  icon: Icons.help_outline_rounded,
                  tooltip: 'Open FAQ',
                  semanticLabel: 'Open FAQ',
                  onPressed: _openFaq,
                ),
              _TitleBarButton(
                icon: Icons.remove_rounded,
                tooltip: 'Minimize',
                semanticLabel: 'Minimize window',
                onPressed: () => unawaited(windowManager.minimize()),
                width: 46,
              ),
              _TitleBarButton(
                icon: _isMaximized
                    ? Icons.filter_none_rounded
                    : Icons.crop_square_rounded,
                tooltip: _isMaximized ? 'Restore' : 'Maximize',
                semanticLabel: _isMaximized
                    ? 'Restore window'
                    : 'Maximize window',
                onPressed: _toggleMaximize,
                width: 46,
              ),
              _TitleBarButton(
                icon: Icons.close_rounded,
                tooltip: 'Close',
                semanticLabel: 'Close window',
                onPressed: () => unawaited(windowManager.close()),
                width: 46,
                danger: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openFaq() {
    final context = widget.navigatorKey?.currentContext;
    if (context == null) {
      return;
    }

    unawaited(
      SettingsNavigation.show(
        context,
        const AppSettingsPage(initialTabId: SettingsCategoryHelp.tabIdFaq),
      ),
    );
  }

  void _toggleMaximize() {
    unawaited(() async {
      try {
        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
        await _syncMaximized();
      } catch (_) {}
    }());
  }

  @override
  void onWindowMaximize() {
    if (mounted) {
      setState(() => _isMaximized = true);
    }
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) {
      setState(() => _isMaximized = false);
    }
  }
}

class _NavigationButtons extends StatelessWidget {
  const _NavigationButtons({
    required this.navigatorKey,
    required this.showNavigation,
  });

  final GlobalKey<NavigatorState>? navigatorKey;
  final bool showNavigation;

  @override
  Widget build(BuildContext context) {
    final history = DesktopNavigationHistoryController.instance;
    final routes = DesktopRouteStackController.instance;

    return AnimatedBuilder(
      animation: Listenable.merge([history, routes]),
      builder: (context, child) {
        final canPopRoute = routes.canPop;
        final canGoBack = showNavigation && (canPopRoute || history.canGoBack);
        final canGoForward = showNavigation && history.canGoForward;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TitleBarButton(
              icon: Icons.arrow_back_rounded,
              tooltip: canGoBack ? 'Back' : 'Back unavailable',
              semanticLabel: canGoBack ? 'Go back' : 'Go back unavailable',
              onPressed: canGoBack ? _goBack : null,
              width: 38,
            ),
            _TitleBarButton(
              icon: Icons.arrow_forward_rounded,
              tooltip: canGoForward ? 'Forward' : 'Forward unavailable',
              semanticLabel: canGoForward
                  ? 'Go forward'
                  : 'Go forward unavailable',
              onPressed: canGoForward
                  ? DesktopNavigationHistoryController.instance.goForward
                  : null,
              width: 38,
            ),
          ],
        );
      },
    );
  }

  void _goBack() {
    final navigator = navigatorKey?.currentState;
    if (navigator != null && navigator.canPop()) {
      unawaited(navigator.maybePop());
      DesktopRouteStackController.instance.refresh();
      return;
    }

    DesktopNavigationHistoryController.instance.goBack();
  }
}

class _TitleBarButton extends StatefulWidget {
  const _TitleBarButton({
    required this.icon,
    required this.tooltip,
    required this.semanticLabel,
    required this.onPressed,
    this.width = 40,
    this.danger = false,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final double width;
  final bool danger;
  final bool active;

  @override
  State<_TitleBarButton> createState() => _TitleBarButtonState();
}

class _TitleBarButtonState extends State<_TitleBarButton> {
  late final FocusNode _focusNode = FocusNode(debugLabel: widget.semanticLabel);
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onPressed != null;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color foreground;
    final Color background;

    if (!_enabled) {
      foreground = scheme.onSurface.withValues(alpha: 0.34);
      background = Colors.transparent;
    } else if (widget.danger && (_hovered || _pressed || _focused)) {
      foreground = scheme.onErrorContainer;
      background = scheme.errorContainer;
    } else {
      foreground = widget.active
          ? scheme.primary
          : scheme.onSurface.withValues(alpha: _pressed ? 0.82 : 0.92);
      background = _hovered || _pressed || _focused
          ? scheme.surfaceContainerHigh.withValues(alpha: _pressed ? 0.74 : 1)
          : Colors.transparent;
    }

    Widget result = MouseRegion(
      cursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
        onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: InterGalacticMotion.duration(
            context,
            InterGalacticMotion.short,
          ),
          width: widget.width,
          height: 40,
          color: background,
          child: Icon(widget.icon, size: 18, color: foreground),
        ),
      ),
    );

    result = Focus(
      focusNode: _focusNode,
      onFocusChange: (value) {
        if (_focused == value) return;
        setState(() => _focused = value);
      },
      onKeyEvent: (_, event) {
        if (!_enabled || event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space) {
          widget.onPressed?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        label: widget.semanticLabel,
        button: true,
        enabled: _enabled,
        onTap: _enabled ? widget.onPressed : null,
        child: result,
      ),
    );

    return Tooltip(message: widget.tooltip, child: result);
  }
}
