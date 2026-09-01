/// Non-FFI fallback for [WindowsCallAudioDucking]. Web has no WASAPI stream to
/// opt out of, so every entry point is inert.
class WindowsCallAudioDucking {
  const WindowsCallAudioDucking._();

  /// Whether this platform can host the native ducking control at all.
  static bool get isSupportedPlatform => false;

  /// Whether the loaded `libwebrtc.dll` actually exports the control.
  ///
  /// Always false here; nothing has been resolved.
  static bool get isAvailable => false;

  /// Always false here; there is no native control to resolve.
  static bool ensureAvailable() => false;

  /// Applies the user's "Lower other app's volumes during calls" choice.
  ///
  /// [enabled] true keeps Windows' default behaviour of attenuating other
  /// applications; false asks Windows to leave them alone.
  static void setLowerOtherAppVolumes(bool enabled) {}

  /// Test seam. No state to reset in the stub.
  static void resetForTesting() {}
}
