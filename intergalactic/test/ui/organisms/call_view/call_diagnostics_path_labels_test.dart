import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/organisms/call_view/call_diagnostics_path_labels.dart';

void main() {
  group('diagnosticLocalPathName', () {
    test('keeps only the local path leaf', () {
      expect(
        diagnosticLocalPathName(
          r'<local-app-data>\InterGalactic\stream-test\report.md',
        ),
        'report.md',
      );
      expect(
        diagnosticLocalPathName(
          r'<local-app-data>\InterGalactic\rnnoise-capture\',
        ),
        'rnnoise-capture',
      );
      expect(
        diagnosticLocalPathName('/tmp/intergalactic-test/Logs/report.json'),
        'report.json',
      );
    });

    test('does not surface root paths as names', () {
      expect(diagnosticLocalPathName(r'<drive>:\'), isNull);
      expect(diagnosticLocalPathName('/'), isNull);
      expect(diagnosticLocalPathName(null), isNull);
      expect(diagnosticLocalPathName(''), isNull);
    });
  });

  test('stream test report label is basename-only', () {
    final label = streamTestReportExportDisplayLabel(
      markdownPath: r'<local-app-data>\InterGalactic\stream-test\run.md',
      jsonPath: r'<local-app-data>\InterGalactic\stream-test\run.json',
    );

    expect(label, 'report files: markdown=run.md, json=run.json');
    expect(label, isNot(contains('<local-app-data>')));
    expect(label, isNot(contains(r'\')));
  });

  test('stream test report label handles unavailable paths', () {
    expect(
      streamTestReportExportDisplayLabel(markdownPath: null, jsonPath: null),
      'report files unavailable',
    );
  });

  test('call diagnostics save message is basename-only', () {
    final message = savedCallDiagnosticsDisplayMessage(
      r'<downloads>\call-diagnostics.txt',
    );

    expect(message, 'Saved call diagnostics (call-diagnostics.txt).');
    expect(message, isNot(contains('<downloads>')));
  });

  test('rnnoise folder line is basename-only', () {
    final line = rnnoiseDiagnosticFolderDisplayLine(
      r'<local-app-data>\InterGalactic\rnnoise-capture',
    );

    expect(line, 'Folder: rnnoise-capture');
    expect(line, isNot(contains('<local-app-data>')));
  });

  test('rnnoise capture completion message is basename-only', () {
    final message = rnnoiseDiagnosticCaptureCompleteDisplayMessage(
      writtenFiles: 4,
      directoryLabel: r'<local-app-data>\InterGalactic\rnnoise-capture',
    );

    expect(
      message,
      'Wrote 4 RNNoise diagnostic WAV files. WAV bug-report submission is '
      'disabled; captures stay local. Folder: rnnoise-capture.',
    );
    expect(message, isNot(contains('<local-app-data>')));
  });
}
