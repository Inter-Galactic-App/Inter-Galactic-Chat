import 'dart:io';

import 'package:intergalactic/client/components/voip/stream_test_runner.dart';
import 'package:intergalactic/config/app_config.dart';
import 'package:path/path.dart' as path;

class StreamTestReportWriteResult {
  const StreamTestReportWriteResult({
    required this.supported,
    this.jsonPath,
    this.markdownPath,
    this.error,
  });

  final bool supported;
  final String? jsonPath;
  final String? markdownPath;
  final String? error;
}

class StreamTestReportWriter {
  const StreamTestReportWriter();

  Future<StreamTestReportWriteResult> write(StreamTestRunResult result) async {
    try {
      final root = Directory(
        path.join(await AppConfig.getLogDirectoryPath(), 'stream-tests'),
      );
      await root.create(recursive: true);

      final stamp = result.startedAt
          .toUtc()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      final basePath = path.join(root.path, 'stream-test-$stamp');
      final jsonPath = '$basePath.json';
      final markdownPath = '$basePath.md';

      await File(jsonPath).writeAsString(result.toJsonText(), flush: true);
      await File(markdownPath).writeAsString(result.toMarkdown(), flush: true);

      return StreamTestReportWriteResult(
        supported: true,
        jsonPath: jsonPath,
        markdownPath: markdownPath,
      );
    } catch (error) {
      return StreamTestReportWriteResult(
        supported: true,
        error: error.toString(),
      );
    }
  }
}
