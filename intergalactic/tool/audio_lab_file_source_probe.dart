import 'dart:io';

import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_audio_file_source.dart';

Future<void> main(List<String> arguments) async {
  final options = _parseArguments(arguments);
  if (options.containsKey('help')) {
    _printHelp();
    return;
  }

  final input = _requiredOption(options, 'input');
  final outputRoot = options['output-root'] ??
      _join(Directory.current.path, 'runtime_audio_lab_app_source');
  final runName = options['run-name'] ?? _defaultRunName();
  final outputDirectory = _join(outputRoot, runName);
  final targetSampleRateHz = _parseInt(
    options['target-sample-rate'],
    NoiseSuppressionAudioFileSource.defaultTargetSampleRateHz,
  );
  final frameDurationMs = _parseInt(
    options['frame-ms'],
    NoiseSuppressionAudioFileSource.defaultFrameDurationMs,
  );
  final realtimePacing = _parseBool(options['realtime'], true);

  final report = await const NoiseSuppressionAudioFileSource().prepareFile(
    inputPath: input,
    outputDirectoryPath: outputDirectory,
    targetSampleRateHz: targetSampleRateHz,
    frameDurationMs: frameDurationMs,
    realtimePacing: realtimePacing,
  );
  stdout.writeln('Audio Lab app-source report: ${report.markdownReportPath}');
}

Map<String, String> _parseArguments(List<String> arguments) {
  final parsed = <String, String>{};
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (!argument.startsWith('--')) {
      throw ArgumentError('Unexpected argument: $argument');
    }
    final keyAndValue = argument.substring(2).split('=');
    final key = keyAndValue.first.toLowerCase();
    if (keyAndValue.length > 1) {
      parsed[key] = keyAndValue.sublist(1).join('=');
      continue;
    }
    if (index + 1 < arguments.length &&
        !arguments[index + 1].startsWith('--')) {
      parsed[key] = arguments[index + 1];
      index++;
    } else {
      parsed[key] = 'true';
    }
  }
  return parsed;
}

String _requiredOption(Map<String, String> options, String key) {
  final value = options[key];
  if (value == null || value.trim().isEmpty) {
    throw ArgumentError('Missing required --$key option.');
  }
  return value;
}

int _parseInt(String? value, int fallback) {
  if (value == null || value.trim().isEmpty) {
    return fallback;
  }
  return int.parse(value);
}

bool _parseBool(String? value, bool fallback) {
  if (value == null || value.trim().isEmpty) {
    return fallback;
  }
  return value.toLowerCase() == 'true' || value == '1';
}

String _defaultRunName() {
  return DateTime.now()
      .toUtc()
      .toIso8601String()
      .replaceAll(RegExp(r'[:.]'), '-');
}

String _join(String base, String child) {
  if (base.endsWith(Platform.pathSeparator)) {
    return '$base$child';
  }
  return '$base${Platform.pathSeparator}$child';
}

void _printHelp() {
  stdout.writeln('''
Audio Lab app file-source probe

Required:
  --input <wav>

Optional:
  --output-root <directory>
  --run-name <name>
  --target-sample-rate <hz>
  --frame-ms <milliseconds>
  --realtime true|false
''');
}
