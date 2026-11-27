import 'dart:ffi';

import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';

typedef _SetDuckingEnabledNative = Void Function(Bool enabled);
typedef _SetDuckingEnabledDart = void Function(bool enabled);

typedef _DuckingSupportedNative = Bool Function();
typedef _DuckingSupportedDart = bool Function();

/// Windows implementation of the call-audio ducking opt-out.
///
/// Resolves the entry point out of the already-loaded `libwebrtc.dll` rather
/// than adding a plugin: `flutter_webrtc` has the DLL in the process by the
/// time any of this runs, and `DynamicLibrary.open` on Windows returns the
/// handle to the loaded module.
///
/// Everything here is best-effort. A build running an older `libwebrtc.zip`
/// artifact simply has no such export; the toggle then does nothing rather
/// than throwing, and the reason is logged once.
class WindowsCallAudioDucking {
  const WindowsCallAudioDucking._();

  static const String _libraryName = 'libwebrtc.dll';
  static const String _setEnabledSymbol =
      'IntergalacticSetCallAudioDuckingEnabled';
  static const String _supportedSymbol =
      'IntergalacticCallAudioDuckingSupported';

  static bool _resolveAttempted = false;
  static _SetDuckingEnabledDart? _setEnabled;
  static bool _loggedApplied = false;

  static bool get isSupportedPlatform => PlatformUtils.isWindows;

  /// Whether the native control has already resolved. Resolution is lazy, so
  /// this reports false until something has triggered it; use
  /// [ensureAvailable] when the answer needs to be authoritative.
  static bool get isAvailable => _setEnabled != null;

  /// Resolves the native control if that has not been attempted yet, and
  /// reports whether the toggle can actually do anything. Cached, so this is
  /// cheap to call from a widget build.
  static bool ensureAvailable() {
    if (!isSupportedPlatform) {
      return false;
    }
    return _resolveSetEnabled() != null;
  }

  /// Applies the user's "Lower other app's volumes during calls" choice.
  ///
  /// [enabled] true keeps Windows' default behaviour of attenuating other
  /// applications during a call; false asks Windows to leave them alone.
  ///
  /// Takes effect for render streams opened from now on and, in the patched
  /// artifact, for a render stream that is already live, so toggling during a
  /// call does not require rejoining it.
  static void setLowerOtherAppVolumes(bool enabled) {
    if (!isSupportedPlatform) {
      return;
    }

    final setEnabled = _resolveSetEnabled();
    if (setEnabled == null) {
      return;
    }

    try {
      setEnabled(enabled);
      if (!_loggedApplied) {
        _loggedApplied = true;
        Log.i(
          'Windows call audio ducking applied: lowerOtherAppVolumes=$enabled',
          category: LogCategory.webrtc,
          source: 'WindowsCallAudioDucking',
        );
      }
    } catch (error, trace) {
      // Do not disable the resolved function: a transient failure here should
      // not permanently silence later toggles.
      Log.onError(
        error,
        trace,
        content: 'Failed to apply Windows call audio ducking preference',
        category: LogCategory.webrtc,
        source: 'WindowsCallAudioDucking',
      );
    }
  }

  static _SetDuckingEnabledDart? _resolveSetEnabled() {
    if (_resolveAttempted) {
      return _setEnabled;
    }
    _resolveAttempted = true;

    try {
      final library = DynamicLibrary.open(_libraryName);

      // Present only in artifacts that were built with the ducking patch. Its
      // absence is the expected state on an older libwebrtc.zip, so treat the
      // lookup failure as "feature not shipped yet", not as an error.
      final supported = library
          .lookupFunction<_DuckingSupportedNative, _DuckingSupportedDart>(
            _supportedSymbol,
          );
      if (!supported()) {
        Log.w(
          'Windows call audio ducking unavailable: $_libraryName reports no '
          'IAudioClientDuckingControl support',
          category: LogCategory.webrtc,
          source: 'WindowsCallAudioDucking',
        );
        return null;
      }

      _setEnabled = library
          .lookupFunction<_SetDuckingEnabledNative, _SetDuckingEnabledDart>(
            _setEnabledSymbol,
          );
    } catch (error) {
      Log.w(
        'Windows call audio ducking unavailable: could not resolve '
        '$_setEnabledSymbol from $_libraryName ($error). The setting will have '
        'no effect until a patched libwebrtc artifact is installed.',
        category: LogCategory.webrtc,
        source: 'WindowsCallAudioDucking',
      );
      return null;
    }

    return _setEnabled;
  }

  /// Test seam: forget the cached resolution so a later call retries.
  static void resetForTesting() {
    _resolveAttempted = false;
    _setEnabled = null;
    _loggedApplied = false;
  }
}
