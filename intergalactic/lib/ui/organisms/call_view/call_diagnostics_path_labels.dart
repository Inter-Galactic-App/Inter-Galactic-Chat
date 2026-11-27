String? diagnosticLocalPathName(String? localPath) {
  final trimmed = localPath?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }

  final withoutTrailingSeparators = trimmed.replaceAll(RegExp(r'[\\/]+$'), '');
  if (withoutTrailingSeparators.isEmpty) {
    return null;
  }

  final parts = withoutTrailingSeparators
      .split(RegExp(r'[\\/]'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) {
    return null;
  }

  final name = parts.last.trim();
  if (name.isEmpty || name.endsWith(':')) {
    return null;
  }
  return name;
}

String streamTestReportExportDisplayLabel({
  required String? markdownPath,
  required String? jsonPath,
}) {
  final markdownName = diagnosticLocalPathName(markdownPath);
  final jsonName = diagnosticLocalPathName(jsonPath);
  final parts = [
    if (markdownName != null) 'markdown=$markdownName',
    if (jsonName != null) 'json=$jsonName',
  ];

  if (parts.isEmpty) {
    return 'report files unavailable';
  }

  return 'report files: ${parts.join(', ')}';
}

String savedCallDiagnosticsDisplayMessage(String? destinationPath) {
  final name = diagnosticLocalPathName(destinationPath);
  if (name == null) {
    return 'Saved call diagnostics.';
  }
  return 'Saved call diagnostics ($name).';
}

String rnnoiseDiagnosticFolderDisplayLine(String? directoryPath) {
  final name = diagnosticLocalPathName(directoryPath);
  if (name == null) {
    return 'Folder: local diagnostics folder';
  }
  return 'Folder: $name';
}

String rnnoiseDiagnosticCaptureCompleteDisplayMessage({
  required int writtenFiles,
  required String? directoryLabel,
}) {
  final folderName = diagnosticLocalPathName(directoryLabel);
  final folderText = folderName == null ? '' : ' Folder: $folderName.';
  return 'Wrote $writtenFiles RNNoise diagnostic WAV files. '
      'WAV bug-report submission is disabled; captures stay local.$folderText';
}
