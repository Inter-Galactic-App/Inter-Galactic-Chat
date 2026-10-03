import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_service.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_tuning_profile.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/developer/developer_log_actions.dart';
import 'package:intergalactic_noise_suppression/intergalactic_noise_suppression.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class DeveloperTitleBarMenu extends StatefulWidget {
  const DeveloperTitleBarMenu({required this.navigatorKey, super.key});

  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<DeveloperTitleBarMenu> createState() => _DeveloperTitleBarMenuState();
}

class _DeveloperTitleBarMenuState extends State<DeveloperTitleBarMenu> {
  static const double _buttonHeight = 40;
  static const double _buttonWidth = 116;
  static const double _menuItemWidth = 238;
  static const Duration _hoverCloseDelay = Duration(milliseconds: 260);

  final MenuController _menuController = MenuController();
  final GlobalKey _buttonKey = GlobalKey();
  final Map<Object, Rect> _menuHoverRects = <Object, Rect>{};
  StreamSubscription? _preferenceSubscription;
  Timer? _hoverCloseTimer;
  Offset? _lastPointerPosition;
  FocusNode? _focusBeforeMenuOpen;
  bool _buttonHovered = false;
  bool _globalPointerRouteRegistered = false;
  bool _menuInputCaptureActive = false;

  @override
  void initState() {
    super.initState();
    _preferenceSubscription = preferences.onSettingChanged.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _hoverCloseTimer?.cancel();
    _stopGlobalPointerTracking();
    _preferenceSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!preferences.developerMode.value) {
      return const SizedBox.shrink();
    }

    return MenuAnchor(
      controller: _menuController,
      alignmentOffset: const Offset(0, -2),
      consumeOutsideTap: _menuInputCaptureActive,
      useRootOverlay: false,
      onOpen: _handleMenuOpen,
      onClose: _handleMenuClose,
      style: _menuStyle(context),
      menuChildren: [
        _submenu(
          context,
          label: 'Logs',
          icon: Icons.text_snippet_outlined,
          children: [
            _actionItem(
              context,
              label: 'Open Log folder',
              icon: Icons.folder_open_outlined,
              action: _openLogFolder,
            ),
            _actionItem(
              context,
              label: 'Copy Recent',
              icon: Icons.copy_all_outlined,
              action: _copyRecentLogs,
            ),
            _actionItem(
              context,
              label: 'Clear',
              icon: Icons.delete_sweep_outlined,
              action: _clearLogs,
            ),
            _actionItem(
              context,
              label: 'Save',
              icon: Icons.save_alt_outlined,
              action: _saveLogs,
            ),
          ],
        ),
        _submenu(
          context,
          label: 'Noise Suppression',
          icon: Icons.graphic_eq_outlined,
          children: [
            _submenu(
              context,
              label: 'Hook Mode',
              icon: Icons.tune_outlined,
              children: [
                for (final mode in _hookModeOptions)
                  _checkedItem(
                    context,
                    label: _hookModeLabel(mode),
                    selected:
                        preferences.voipNoiseSuppressionHookMode.value == mode,
                    onPressed: () => _setHookMode(mode),
                  ),
              ],
            ),
            _checkboxItem(
              context,
              label: 'Transient Click Guard',
              value: preferences
                  .voipNoiseSuppressionDeepFilterNetTransientSuppression
                  .value,
              onChanged: (value) => _setNoiseSupportToggle(
                preferences
                    .voipNoiseSuppressionDeepFilterNetTransientSuppression
                    .set,
                value,
              ),
            ),
            _checkboxItem(
              context,
              label: 'Hush Voice Isolation',
              value: preferences
                  .voipNoiseSuppressionDeepFilterNetHushSuppression
                  .value,
              onChanged: (value) => _setNoiseSupportToggle(
                preferences
                    .voipNoiseSuppressionDeepFilterNetHushSuppression
                    .set,
                value,
              ),
            ),
            _submenu(
              context,
              label: 'Audio capture Frontend Override',
              icon: Icons.mic_external_on_outlined,
              children: [
                _checkboxItem(
                  context,
                  label: 'Audio capture Frontend Override',
                  value: preferences.voipAudioCaptureDebugOverride.value,
                  onChanged: (value) => _setAudioCaptureToggle(
                    preferences.voipAudioCaptureDebugOverride.set,
                    value,
                  ),
                ),
                const Divider(height: 8),
                _checkboxItem(
                  context,
                  label: 'WebRTC Echo cancellation',
                  value: preferences.voipAudioCaptureEchoCancellation.value,
                  enabled: preferences.voipAudioCaptureDebugOverride.value,
                  onChanged: (value) => _setAudioCaptureToggle(
                    preferences.voipAudioCaptureEchoCancellation.set,
                    value,
                  ),
                ),
                _checkboxItem(
                  context,
                  label: 'WebRTC Auto Gain',
                  value: preferences.voipAudioCaptureAutoGainControl.value,
                  enabled: preferences.voipAudioCaptureDebugOverride.value,
                  onChanged: (value) => _setAudioCaptureToggle(
                    preferences.voipAudioCaptureAutoGainControl.set,
                    value,
                  ),
                ),
                _checkboxItem(
                  context,
                  label: 'WebRTC High-Pass Filter',
                  value: preferences.voipAudioCaptureHighPassFilter.value,
                  enabled: preferences.voipAudioCaptureDebugOverride.value,
                  onChanged: (value) => _setAudioCaptureToggle(
                    preferences.voipAudioCaptureHighPassFilter.set,
                    value,
                  ),
                ),
                _checkboxItem(
                  context,
                  label: 'WebRTC Typing noise detection',
                  value: preferences.voipAudioCaptureTypingNoiseDetection.value,
                  enabled: preferences.voipAudioCaptureDebugOverride.value,
                  onChanged: (value) => _setAudioCaptureToggle(
                    preferences.voipAudioCaptureTypingNoiseDetection.set,
                    value,
                  ),
                ),
                _checkboxItem(
                  context,
                  label: 'Request 48 kHz mono',
                  value:
                      preferences.voipAudioCaptureRequestReferenceFormat.value,
                  enabled: preferences.voipAudioCaptureDebugOverride.value,
                  onChanged: (value) => _setAudioCaptureToggle(
                    preferences.voipAudioCaptureRequestReferenceFormat.set,
                    value,
                  ),
                ),
                _checkboxItem(
                  context,
                  label: 'Send Mic Volume Constraint',
                  value: preferences.voipAudioCaptureVolumeConstraint.value,
                  enabled: preferences.voipAudioCaptureDebugOverride.value,
                  onChanged: (value) => _setAudioCaptureToggle(
                    preferences.voipAudioCaptureVolumeConstraint.set,
                    value,
                  ),
                ),
              ],
            ),
          ],
        ),
        _submenu(
          context,
          label: 'Stream',
          icon: Icons.screen_share_outlined,
          children: [
            _checkboxItem(
              context,
              label: 'Advanced Stream Override',
              value: preferences.streamAdvancedOverride.value,
              onChanged: preferences.streamAdvancedOverride.set,
            ),
            _checkboxItem(
              context,
              label: 'Adaptive Stream fallback',
              value: preferences.streamAdaptiveFallbackEnabled.value,
              onChanged: preferences.streamAdaptiveFallbackEnabled.set,
            ),
            _checkboxItem(
              context,
              label: 'GPU pipeline test mode',
              value: preferences.streamGpuPipelineTestMode.value,
              onChanged: preferences.streamGpuPipelineTestMode.set,
            ),
            _checkboxItem(
              context,
              label: 'Prefer Hardware Encoder',
              value: preferences.streamHardwareEncodingFirst.value,
              onChanged: preferences.streamHardwareEncodingFirst.set,
            ),
            _checkboxItem(
              context,
              label: 'Show call/stream stats',
              value: preferences.showCallStreamStats.value,
              onChanged: preferences.showCallStreamStats.set,
            ),
          ],
        ),
        _submenu(
          context,
          label: 'Other',
          icon: Icons.more_horiz_rounded,
          children: [
            _checkboxItem(
              context,
              label: 'Debug translations',
              value: preferences.debugTranslations.value,
              onChanged: preferences.debugTranslations.set,
            ),
            _checkboxItem(
              context,
              label: 'Show timeline diagnostics',
              value: preferences.showTimelineDiagnostics.value,
              onChanged: preferences.showTimelineDiagnostics.set,
            ),
            _checkboxItem(
              context,
              label: 'Hide Developer Settings',
              value: preferences.hideDeveloperSettings.value,
              onChanged: preferences.hideDeveloperSettings.set,
            ),
          ],
        ),
      ],
      builder: (context, controller, child) {
        return MouseRegion(
          key: _buttonKey,
          cursor: SystemMouseCursors.click,
          onEnter: (event) {
            _lastPointerPosition = event.position;
            _buttonHovered = true;
            _cancelHoverClose();
            if (!controller.isOpen) {
              controller.open();
            }
            setState(() {});
          },
          onHover: (event) {
            _lastPointerPosition = event.position;
          },
          onExit: (event) {
            _lastPointerPosition = event.position;
            _buttonHovered = false;
            _scheduleHoverClose();
            setState(() {});
          },
          child: tiamat.Tooltip(
            text: 'Developer quick controls',
            child: Semantics(
              button: true,
              label: 'Developer quick controls',
              onTap: _toggleMenu,
              child: SizedBox(
                width: _buttonWidth,
                height: _buttonHeight,
                child: TextButton.icon(
                  style: _buttonStyle(context),
                  icon: const Icon(Icons.code_rounded, size: 17),
                  label: const Text(
                    'Developer',
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: _toggleMenu,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  MenuStyle _menuStyle(BuildContext context, {double maxWidth = 300}) {
    final scheme = Theme.of(context).colorScheme;
    return MenuStyle(
      backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
      elevation: const WidgetStatePropertyAll(8),
      maximumSize: WidgetStatePropertyAll(Size(maxWidth, double.infinity)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 6)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.34)),
        ),
      ),
    );
  }

  ButtonStyle _menuItemStyle(BuildContext context, {double width = 240}) {
    return ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(width, 40)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  ButtonStyle _buttonStyle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = scheme.onSurface.withValues(alpha: 0.92);
    final background = _buttonHovered || _menuController.isOpen
        ? scheme.surfaceContainerHigh
        : Colors.transparent;

    return TextButton.styleFrom(
      foregroundColor: foreground,
      backgroundColor: background,
      disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.34),
      minimumSize: const Size(_buttonWidth, _buttonHeight),
      maximumSize: const Size(_buttonWidth, _buttonHeight),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
      ),
    ).copyWith(
      animationDuration: InterGalacticMotion.duration(
        context,
        InterGalacticMotion.short,
      ),
    );
  }

  Widget _submenu(
    BuildContext context, {
    required String label,
    required IconData icon,
    required List<Widget> children,
  }) {
    return _hoverTrackedMenuChild(
      SubmenuButton(
        style: _menuItemStyle(context),
        menuStyle: _menuStyle(context),
        leadingIcon: Icon(icon, size: 18),
        menuChildren: children,
        child: SizedBox(width: _menuItemWidth - 58, child: Text(label)),
      ),
    );
  }

  Widget _actionItem(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Future<void> Function() action,
  }) {
    return _hoverTrackedMenuChild(
      MenuItemButton(
        style: _menuItemStyle(context),
        leadingIcon: Icon(icon, size: 18),
        onPressed: () {
          _menuController.close();
          unawaited(action());
        },
        child: SizedBox(width: _menuItemWidth - 58, child: Text(label)),
      ),
    );
  }

  Widget _checkboxItem(
    BuildContext context, {
    required String label,
    required bool value,
    required Future<void> Function(bool value) onChanged,
    bool enabled = true,
  }) {
    return _hoverTrackedMenuChild(
      CheckboxMenuButton(
        style: _menuItemStyle(context),
        value: value,
        onChanged: enabled
            ? (nextValue) {
                unawaited(onChanged(nextValue ?? false));
              }
            : null,
        child: SizedBox(width: _menuItemWidth - 38, child: Text(label)),
      ),
    );
  }

  Widget _checkedItem(
    BuildContext context, {
    required String label,
    required bool selected,
    required Future<void> Function() onPressed,
  }) {
    return _hoverTrackedMenuChild(
      MenuItemButton(
        style: _menuItemStyle(context),
        leadingIcon: selected
            ? const Icon(Icons.check_rounded, size: 18)
            : const SizedBox(width: 18, height: 18),
        onPressed: () {
          unawaited(onPressed());
        },
        child: SizedBox(width: _menuItemWidth - 58, child: Text(label)),
      ),
    );
  }

  Widget _hoverTrackedMenuChild(Widget child) {
    return _MenuHoverRegion(
      onHoverChanged: _handleMenuHoverChanged,
      child: child,
    );
  }

  void _toggleMenu() {
    _cancelHoverClose();
    if (_menuController.isOpen || _menuInputCaptureActive) {
      _requestMenuClose();
    } else {
      _menuController.open();
    }
    setState(() {});
  }

  void _handleMenuOpen() {
    _cancelHoverClose();
    _focusBeforeMenuOpen = FocusManager.instance.primaryFocus;
    _menuInputCaptureActive = true;
    _startGlobalPointerTracking();
    if (mounted) {
      setState(() {});
    }
  }

  void _handleMenuClose() {
    _releaseMenuInputCapture();
    if (mounted) {
      setState(() {});
    }
  }

  void _handleMenuHoverChanged(
    Object token,
    bool hovering,
    Offset pointerPosition,
    Rect bounds,
  ) {
    if (!mounted) {
      return;
    }
    if (!_menuInputCaptureActive) {
      return;
    }
    _lastPointerPosition = pointerPosition;
    if (hovering) {
      _menuHoverRects[token] = bounds;
      _cancelHoverClose();
    } else {
      _menuHoverRects.remove(token);
      _scheduleHoverClose();
    }
  }

  void _startGlobalPointerTracking() {
    if (_globalPointerRouteRegistered) {
      return;
    }
    GestureBinding.instance.pointerRouter.addGlobalRoute(
      _handleGlobalPointerEvent,
    );
    _globalPointerRouteRegistered = true;
  }

  void _stopGlobalPointerTracking() {
    if (!_globalPointerRouteRegistered) {
      return;
    }
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _handleGlobalPointerEvent,
    );
    _globalPointerRouteRegistered = false;
  }

  void _handleGlobalPointerEvent(PointerEvent event) {
    if (event is! PointerHoverEvent &&
        event is! PointerMoveEvent &&
        event is! PointerDownEvent) {
      return;
    }
    _lastPointerPosition = event.position;
    if (!_menuInputCaptureActive || !_menuController.isOpen) {
      _releaseMenuInputCapture(restoreFocus: false);
      return;
    }
    if (_isPointerInsideMenuStack()) {
      _cancelHoverClose();
    } else {
      _scheduleHoverClose();
    }
  }

  void _cancelHoverClose() {
    _hoverCloseTimer?.cancel();
    _hoverCloseTimer = null;
  }

  void _scheduleHoverClose() {
    if (!_menuController.isOpen || _isPointerInsideMenuStack()) {
      _cancelHoverClose();
      return;
    }
    if (_hoverCloseTimer != null) {
      return;
    }

    _hoverCloseTimer = Timer(_hoverCloseDelay, () {
      _hoverCloseTimer = null;
      if (!mounted || _isPointerInsideMenuStack()) {
        return;
      }
      if (_menuController.isOpen) {
        _requestMenuClose();
      } else {
        setState(() {});
      }
    });
  }

  void _requestMenuClose() {
    final wasOpen = _menuController.isOpen;
    _releaseMenuInputCapture(restoreFocus: !wasOpen);
    if (wasOpen) {
      _menuController.close();
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _releaseMenuInputCapture({bool restoreFocus = true}) {
    _cancelHoverClose();
    _stopGlobalPointerTracking();
    _menuHoverRects.clear();
    _lastPointerPosition = null;
    _menuInputCaptureActive = false;
    if (restoreFocus) {
      _restoreFocusAfterMenuClose();
    }
  }

  void _restoreFocusAfterMenuClose() {
    final focusToRestore = _focusBeforeMenuOpen;
    _focusBeforeMenuOpen = null;
    if (focusToRestore != null &&
        focusToRestore.context != null &&
        focusToRestore.canRequestFocus) {
      focusToRestore.requestFocus();
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
  }

  bool _isPointerInsideMenuStack() {
    final position = _lastPointerPosition;
    if (position == null) {
      return _buttonHovered || _menuHoverRects.isNotEmpty;
    }

    if (_containsPointer(_globalRectFor(_buttonKey.currentContext), position)) {
      return true;
    }

    for (final rect in _menuHoverRects.values) {
      if (_containsPointer(rect, position)) {
        return true;
      }
    }
    return false;
  }

  bool _containsPointer(Rect? rect, Offset position) {
    return rect?.inflate(3).contains(position) ?? false;
  }

  Rect? _globalRectFor(BuildContext? context) {
    final renderObject = context?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return null;
    }
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  Future<void> _openLogFolder() {
    return _runAction(
      successMessage: 'Opened diagnostic log folder',
      failureMessage: 'Failed to open log folder',
      action: DeveloperLogActions.openLogFolder,
    );
  }

  Future<void> _copyRecentLogs() {
    return _runAction(
      successMessage: 'Copied recent logs',
      failureMessage: 'Failed to copy logs',
      action: DeveloperLogActions.copyRecentLogs,
    );
  }

  Future<void> _clearLogs() async {
    final dialogContext = widget.navigatorKey?.currentContext ?? context;
    final confirmed = await AdaptiveDialog.confirmation(
      dialogContext,
      title: 'Clear diagnostic logs?',
      prompt:
          'This removes saved diagnostic log files and clears the current in-app log list.',
      confirmationText: 'Clear Logs',
      cancelText: 'Cancel',
      dangerous: true,
    );
    if (confirmed != true) {
      return;
    }

    await _runAction(
      successMessage: 'Cleared logs',
      failureMessage: 'Failed to clear logs',
      action: DeveloperLogActions.clearLogs,
    );
  }

  Future<void> _saveLogs() async {
    try {
      final destinationPath = await DeveloperLogActions.saveLogs();
      if (destinationPath.isNotEmpty) {
        _showSnackBar('Saved logs');
      }
    } catch (error, trace) {
      Log.onError(error, trace, content: 'Failed to save logs');
      _showSnackBar('Failed to save logs');
    }
  }

  Future<void> _runAction({
    required String successMessage,
    required String failureMessage,
    required Future<void> Function() action,
  }) async {
    try {
      await action();
      _showSnackBar(successMessage);
    } catch (error, trace) {
      Log.onError(error, trace, content: failureMessage);
      _showSnackBar(failureMessage);
    }
  }

  void _showSnackBar(String message) {
    final messengerContext = widget.navigatorKey?.currentContext ?? context;
    ScaffoldMessenger.maybeOf(
      messengerContext,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setHookMode(String mode) async {
    await preferences.voipNoiseSuppressionHookMode.set(mode);
    await NoiseSuppressionService.instance.applyDiagnosticHookMode(
      _pipelineModeForHook(mode),
    );
    await NoiseSuppressionService.instance.refreshEnhancedBackendStatus();
  }

  Future<void> _setNoiseSupportToggle(
    Future<void> Function(bool value) setter,
    bool value,
  ) async {
    await setter(value);
    await _applyNoiseSuppressionPreference();
  }

  Future<void> _applyNoiseSuppressionPreference() async {
    await NoiseSuppressionService.instance.applyPreference(
      preferences.voipNoiseSuppressionEnabled.value,
      tuningProfile: NoiseSuppressionTuningProfile.fromPreferenceValues(
        presetKey: preferences.voipNoiseSuppressionPreset.value,
        customVadThreshold: preferences.voipNoiseSuppressionVadThreshold.value,
        customSpeechGraceMs:
            preferences.voipNoiseSuppressionSpeechGraceMs.value,
        customClosedGainPercent:
            preferences.voipNoiseSuppressionClosedGainPercent.value,
        customTransientSensitivityPercent:
            preferences.voipNoiseSuppressionTransientSensitivity.value,
      ),
    );
    await NoiseSuppressionService.instance.applyDiagnosticHookMode(
      _pipelineModeForHook(preferences.voipNoiseSuppressionHookMode.value),
    );
    if (preferences.voipNoiseSuppressionEnabled.value) {
      NoiseSuppressionService.instance.scheduleHealthRefresh();
    }
  }

  Future<void> _setAudioCaptureToggle(
    Future<void> Function(bool value) setter,
    bool value,
  ) async {
    await setter(value);
    await NoiseSuppressionService.instance.refresh();
  }

  NoiseSuppressionPipelineMode? _pipelineModeForHook(String mode) {
    return switch (mode) {
      'identity' => NoiseSuppressionPipelineMode.identity,
      'off' => NoiseSuppressionPipelineMode.off,
      NoiseSuppressionService.diagnosticEnhancedBackendModeKey =>
        NoiseSuppressionPipelineMode.deepFilterNet,
      _ => null,
    };
  }

  static const List<String> _hookModeOptions = [
    'rnnoise',
    NoiseSuppressionService.diagnosticEnhancedBackendModeKey,
    'identity',
    'off',
  ];

  String _hookModeLabel(String mode) {
    return switch (mode) {
      NoiseSuppressionService.diagnosticEnhancedBackendModeKey =>
        'Enhanced DeepFilterNet',
      'identity' => 'Identity',
      'off' => 'Off',
      _ => 'RNNoise',
    };
  }
}

class _MenuHoverRegion extends StatefulWidget {
  const _MenuHoverRegion({required this.onHoverChanged, required this.child});

  final void Function(
    Object token,
    bool hovering,
    Offset pointerPosition,
    Rect bounds,
  )
  onHoverChanged;
  final Widget child;

  @override
  State<_MenuHoverRegion> createState() => _MenuHoverRegionState();
}

class _MenuHoverRegionState extends State<_MenuHoverRegion> {
  final Object _hoverToken = Object();
  bool _hovering = false;
  Offset? _lastPointerPosition;

  @override
  void dispose() {
    _markExited();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerHover: (event) => _markHovering(event.position),
      onPointerMove: (event) => _markHovering(event.position),
      child: MouseRegion(
        onEnter: (event) => _markHovering(event.position),
        onExit: (event) => _markExited(event.position),
        child: widget.child,
      ),
    );
  }

  void _markHovering(Offset pointerPosition) {
    _lastPointerPosition = pointerPosition;
    _hovering = true;
    widget.onHoverChanged(_hoverToken, true, pointerPosition, _globalBounds());
  }

  void _markExited([Offset? pointerPosition]) {
    if (!_hovering) {
      return;
    }
    _hovering = false;
    widget.onHoverChanged(
      _hoverToken,
      false,
      pointerPosition ?? _lastPointerPosition ?? _globalBounds().center,
      _globalBounds(),
    );
  }

  Rect _globalBounds() {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return Rect.zero;
    }
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }
}
