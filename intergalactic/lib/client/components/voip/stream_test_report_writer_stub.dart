import 'package:intergalactic/client/components/voip/stream_test_runner.dart';

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
    return const StreamTestReportWriteResult(
      supported: false,
      error: 'Stream test report export is unsupported on this platform.',
    );
  }
}
