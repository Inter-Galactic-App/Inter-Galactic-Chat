enum WindowsScreenCaptureBackendMode {
  platformDefault,
  wgcOnly,
  directxOnly,
  windowCrop,
  gameD3d11HookExperimental,
}

enum WindowsScreenCaptureDirtyRegionMode {
  auto,
  forceFullFrame,
}

enum WindowsWindowGdiCaptureMode {
  defaultMode,
  printWindowFirst,
  bitBltFirst,
  bitBltOnly,
}

WindowsScreenCaptureBackendMode? defaultWindowsCaptureBackendMode({
  required bool isWindows,
  required bool isWebrtcDesktopSource,
  required bool isWindowSource,
  required WindowsScreenCaptureBackendMode? requestedMode,
  bool preferGameCaptureForWindowSource = false,
  String? sourceTitle,
}) {
  if (!isWindows || !isWebrtcDesktopSource) {
    return null;
  }
  if (requestedMode != null) {
    return requestedMode;
  }
  if (isWindowSource) {
    return preferGameCaptureForWindowSource &&
            !isLikelyNonGameWindowCaptureSource(sourceTitle)
        ? WindowsScreenCaptureBackendMode.gameD3d11HookExperimental
        : WindowsScreenCaptureBackendMode.directxOnly;
  }
  return null;
}

bool isLikelyNonGameWindowCaptureSource(String? sourceTitle) {
  final normalized = sourceTitle?.trim().toLowerCase() ?? '';
  if (normalized.isEmpty) {
    return true;
  }

  const browserMarkers = [
    ' - opera',
    'opera gx',
    ' - google chrome',
    ' - chrome',
    ' - microsoft edge',
    ' - firefox',
    'mozilla firefox',
    ' - brave',
    ' - vivaldi',
  ];
  const appMarkers = [
    'discord',
    'slack',
    'microsoft teams',
    'visual studio code',
    'windows powershell',
    'terminal',
    'file explorer',
    'notepad',
  ];

  return browserMarkers.any(normalized.contains) ||
      appMarkers.any(normalized.contains);
}

bool isAutomaticWindowsGameCaptureBackend({
  required WindowsScreenCaptureBackendMode? requestedMode,
  required WindowsScreenCaptureBackendMode? effectiveMode,
}) {
  return requestedMode == null &&
      effectiveMode ==
          WindowsScreenCaptureBackendMode.gameD3d11HookExperimental;
}

WindowsScreenCaptureDirtyRegionMode defaultWindowsCaptureDirtyRegionMode({
  required bool isWindows,
  required bool isWebrtcDesktopSource,
  required bool isWindowSource,
  required WindowsScreenCaptureBackendMode? effectiveBackendMode,
}) {
  if (!isWindows || !isWebrtcDesktopSource || !isWindowSource) {
    return WindowsScreenCaptureDirtyRegionMode.auto;
  }
  return switch (effectiveBackendMode) {
    WindowsScreenCaptureBackendMode.directxOnly ||
    WindowsScreenCaptureBackendMode.windowCrop ||
    WindowsScreenCaptureBackendMode.gameD3d11HookExperimental =>
      WindowsScreenCaptureDirtyRegionMode.auto,
    _ => WindowsScreenCaptureDirtyRegionMode.forceFullFrame,
  };
}

const streamTestWindowsCaptureBackendModes = [
  WindowsScreenCaptureBackendMode.platformDefault,
  WindowsScreenCaptureBackendMode.wgcOnly,
  WindowsScreenCaptureBackendMode.directxOnly,
  WindowsScreenCaptureBackendMode.gameD3d11HookExperimental,
];

const streamTestWindowsWindowGdiCaptureModes = [
  WindowsWindowGdiCaptureMode.defaultMode,
  WindowsWindowGdiCaptureMode.printWindowFirst,
  WindowsWindowGdiCaptureMode.bitBltFirst,
  WindowsWindowGdiCaptureMode.bitBltOnly,
];

extension WindowsScreenCaptureBackendModeDetails
    on WindowsScreenCaptureBackendMode {
  String get constraintValue => switch (this) {
        WindowsScreenCaptureBackendMode.platformDefault => 'default',
        WindowsScreenCaptureBackendMode.wgcOnly => 'wgc-only',
        WindowsScreenCaptureBackendMode.directxOnly => 'directx-only',
        WindowsScreenCaptureBackendMode.windowCrop => 'window-crop',
        WindowsScreenCaptureBackendMode.gameD3d11HookExperimental =>
          'game-d3d11-hook-experimental',
      };

  String get label => switch (this) {
        WindowsScreenCaptureBackendMode.platformDefault => 'Native default',
        WindowsScreenCaptureBackendMode.wgcOnly => 'WGC only',
        WindowsScreenCaptureBackendMode.directxOnly =>
          'DirectX / Window GDI only',
        WindowsScreenCaptureBackendMode.windowCrop => 'Window crop fallback',
        WindowsScreenCaptureBackendMode.gameD3d11HookExperimental =>
          'D3D11 game hook (experimental)',
      };

  String get description => switch (this) {
        WindowsScreenCaptureBackendMode.platformDefault =>
          'Forces the patched libwebrtc/native backend default instead of the app-level source default.',
        WindowsScreenCaptureBackendMode.wgcOnly =>
          'Windows Graphics Capture without fallback.',
        WindowsScreenCaptureBackendMode.directxOnly =>
          'Legacy DirectX screen path; window sources may use WebRTC window-gdi.',
        WindowsScreenCaptureBackendMode.windowCrop =>
          'Legacy window-cropping fallback path.',
        WindowsScreenCaptureBackendMode.gameD3d11HookExperimental =>
          'Debug-only D3D11 Present-hook source for selected game windows.',
      };

  bool get streamTestSelectable =>
      this != WindowsScreenCaptureBackendMode.windowCrop;

  static WindowsScreenCaptureBackendMode fromConstraintValue(String value) {
    final normalized = value.trim().toLowerCase();
    return WindowsScreenCaptureBackendMode.values.firstWhere(
      (mode) => mode.constraintValue == normalized,
      orElse: () => WindowsScreenCaptureBackendMode.platformDefault,
    );
  }
}

extension WindowsWindowGdiCaptureModeDetails on WindowsWindowGdiCaptureMode {
  String get constraintValue => switch (this) {
        WindowsWindowGdiCaptureMode.defaultMode => 'default',
        WindowsWindowGdiCaptureMode.printWindowFirst => 'print-window-first',
        WindowsWindowGdiCaptureMode.bitBltFirst => 'bitblt-first',
        WindowsWindowGdiCaptureMode.bitBltOnly => 'bitblt-only',
      };

  String get label => switch (this) {
        WindowsWindowGdiCaptureMode.defaultMode =>
          'Current PrintWindow full-content first',
        WindowsWindowGdiCaptureMode.printWindowFirst =>
          'Plain PrintWindow first',
        WindowsWindowGdiCaptureMode.bitBltFirst => 'BitBlt first',
        WindowsWindowGdiCaptureMode.bitBltOnly => 'BitBlt only',
      };

  String get shortLabel => switch (this) {
        WindowsWindowGdiCaptureMode.defaultMode => 'GDI current',
        WindowsWindowGdiCaptureMode.printWindowFirst => 'GDI plain print',
        WindowsWindowGdiCaptureMode.bitBltFirst => 'GDI BitBlt first',
        WindowsWindowGdiCaptureMode.bitBltOnly => 'GDI BitBlt only',
      };

  String get description => switch (this) {
        WindowsWindowGdiCaptureMode.defaultMode =>
          'Uses the current WebRTC order: PW_RENDERFULLCONTENT first, then fallback calls only if needed.',
        WindowsWindowGdiCaptureMode.printWindowFirst =>
          'Diagnostic mode: tries plain PrintWindow before the full-content call.',
        WindowsWindowGdiCaptureMode.bitBltFirst =>
          'Diagnostic mode: tries BitBlt first, then falls back if the call fails.',
        WindowsWindowGdiCaptureMode.bitBltOnly =>
          'Diagnostic mode: tries only BitBlt so timing and black-frame behavior are unambiguous.',
      };

  static WindowsWindowGdiCaptureMode fromConstraintValue(String value) {
    final normalized = value.trim().toLowerCase();
    return WindowsWindowGdiCaptureMode.values.firstWhere(
      (mode) => mode.constraintValue == normalized,
      orElse: () => WindowsWindowGdiCaptureMode.defaultMode,
    );
  }
}

extension WindowsScreenCaptureDirtyRegionModeDetails
    on WindowsScreenCaptureDirtyRegionMode {
  String get constraintValue => switch (this) {
        WindowsScreenCaptureDirtyRegionMode.auto => 'auto',
        WindowsScreenCaptureDirtyRegionMode.forceFullFrame =>
          'force-full-frame',
      };

  String get label => switch (this) {
        WindowsScreenCaptureDirtyRegionMode.auto => 'Auto dirty regions',
        WindowsScreenCaptureDirtyRegionMode.forceFullFrame =>
          'Force full-frame dirty regions',
      };

  String get description => switch (this) {
        WindowsScreenCaptureDirtyRegionMode.auto =>
          'Uses the native capturer updated-region behavior.',
        WindowsScreenCaptureDirtyRegionMode.forceFullFrame =>
          'Diagnostic mode: disables updated-region differ wrappers where '
              'possible and labels delivered frames as full-frame updates.',
      };

  static WindowsScreenCaptureDirtyRegionMode fromConstraintValue(String value) {
    final normalized = value.trim().toLowerCase();
    return WindowsScreenCaptureDirtyRegionMode.values.firstWhere(
      (mode) => mode.constraintValue == normalized,
      orElse: () => WindowsScreenCaptureDirtyRegionMode.auto,
    );
  }
}
