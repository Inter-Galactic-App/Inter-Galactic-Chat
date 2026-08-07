bool shouldShowTimelineDiagnostics({
  required bool developerMode,
  required bool developerUiHidden,
  required bool showTimelineDiagnostics,
}) {
  return developerMode && !developerUiHidden && showTimelineDiagnostics;
}
