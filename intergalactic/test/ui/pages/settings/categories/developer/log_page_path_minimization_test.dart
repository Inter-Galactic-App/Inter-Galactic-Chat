import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/pages/settings/categories/developer/log_page.dart';

void main() {
  test('diagnostic log folder status does not expose local paths', () {
    expect(
      diagnosticLogFolderExportStatus(
        r'<local-app-data>\InterGalactic\logs',
      ),
      'available',
    );
    expect(
      diagnosticLogFolderExportStatus(
        '/tmp/intergalactic-test/Logs/InterGalactic',
      ),
      'available',
    );
    expect(diagnosticLogFolderExportStatus(null), 'unavailable');
    expect(diagnosticLogFolderExportStatus(''), 'unavailable');
  });
}
