import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/push_to_talk_hotkey_reader.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/shortcut_binding.dart';

typedef PushToTalkHotkeyPressedReader = bool Function(ShortcutBinding binding);

class PushToTalkHotkeyMonitor {
  PushToTalkHotkeyMonitor({
    required this.onPressed,
    required this.onReleased,
    Duration pollInterval = const Duration(milliseconds: 35),
    PushToTalkHotkeyPressedReader? isHotkeyPressedForTesting,
    bool? supportedForTesting,
    DefaultHotkeyPollingReader? reader,
  }) : _pollInterval = pollInterval,
       _isHotkeyPressedForTesting = isHotkeyPressedForTesting,
       _supportedForTesting = supportedForTesting,
       _reader = reader ?? DefaultHotkeyPollingReader();

  final VoidCallback onPressed;
  final VoidCallback onReleased;
  final Duration _pollInterval;
  final PushToTalkHotkeyPressedReader? _isHotkeyPressedForTesting;
  final bool? _supportedForTesting;
  final DefaultHotkeyPollingReader _reader;

  Timer? _timer;
  ShortcutBinding? _binding;
  bool _pressed = false;
  bool _disposed = false;
  bool _loggedPollFailure = false;
  bool _loggedCapabilityFailure = false;
  bool _handlingPollFailure = false;

  bool get isSupported => _supportedForTesting ?? _reader.isSupported;

  bool get isRunning => _timer != null;

  bool canMonitorHotkey(HotKey? hotkey) {
    return canMonitorBinding(ShortcutBinding.fromHotKey(hotkey));
  }

  bool canMonitorBinding(ShortcutBinding? binding) {
    if (binding == null || !isSupported) {
      return false;
    }
    if (_isHotkeyPressedForTesting != null) {
      return true;
    }
    try {
      return _reader.canReadBinding(binding);
    } catch (error, stackTrace) {
      _handleCapabilityError(error, stackTrace);
      return false;
    }
  }

  void configure(ShortcutBinding? binding) {
    _binding = binding;
    _loggedPollFailure = false;
    _loggedCapabilityFailure = false;
    if (binding == null) {
      stop();
    }
  }

  void start() {
    if (_disposed || !canMonitorBinding(_binding) || _timer != null) {
      return;
    }

    _timer = Timer.periodic(_pollInterval, (_) => _poll());
    _poll();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    if (_pressed) {
      _pressed = false;
      _notifyReleased();
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    stop();
  }

  void _poll() {
    final ShortcutBinding? binding;
    final bool pressed;
    try {
      binding = _binding;
      pressed = binding != null && _isHotkeyPressed(binding);
    } catch (error, stackTrace) {
      _handlePollError(error, stackTrace);
      return;
    }

    if (pressed == _pressed) {
      return;
    }

    _pressed = pressed;
    if (pressed) {
      _notifyPressed();
    } else {
      _notifyReleased();
    }
  }

  bool _isHotkeyPressed(ShortcutBinding binding) {
    final reader = _isHotkeyPressedForTesting;
    if (reader != null) {
      return reader(binding);
    }
    return _reader.isBindingPressed(binding);
  }

  void _notifyPressed() {
    try {
      onPressed();
    } catch (error, stackTrace) {
      _handlePollError(error, stackTrace);
    }
  }

  void _notifyReleased() {
    try {
      onReleased();
    } catch (error, stackTrace) {
      _handlePollError(error, stackTrace);
    }
  }

  void _handlePollError(Object error, StackTrace stackTrace) {
    if (_handlingPollFailure) {
      return;
    }
    _handlingPollFailure = true;
    stop();
    _handlingPollFailure = false;
    if (_loggedPollFailure) {
      return;
    }
    _loggedPollFailure = true;
    Log.onError(
      error,
      stackTrace,
      content:
          'Push to Talk hotkey monitor failed; polling stopped for this keybind',
      category: LogCategory.webrtc,
      source: 'push-to-talk',
    );
  }

  void _handleCapabilityError(Object error, StackTrace stackTrace) {
    stop();
    if (_loggedCapabilityFailure) {
      return;
    }
    _loggedCapabilityFailure = true;
    Log.onError(
      error,
      stackTrace,
      content:
          'Push to Talk hotkey monitor capability check failed; polling was not started',
      category: LogCategory.webrtc,
      source: 'push-to-talk',
    );
  }
}
