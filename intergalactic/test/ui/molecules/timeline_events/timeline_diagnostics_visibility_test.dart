import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_diagnostics_visibility.dart';

void main() {
  group('shouldShowTimelineDiagnostics', () {
    test('is disabled when developer mode and the timeline toggle are off', () {
      expect(
        shouldShowTimelineDiagnostics(
          developerMode: false,
          developerUiHidden: false,
          showTimelineDiagnostics: false,
        ),
        isFalse,
      );
    });

    test('is disabled when only developer mode is on', () {
      expect(
        shouldShowTimelineDiagnostics(
          developerMode: true,
          developerUiHidden: false,
          showTimelineDiagnostics: false,
        ),
        isFalse,
      );
    });

    test('is disabled when only the timeline toggle is on', () {
      expect(
        shouldShowTimelineDiagnostics(
          developerMode: false,
          developerUiHidden: false,
          showTimelineDiagnostics: true,
        ),
        isFalse,
      );
    });

    test(
      'is enabled only when developer mode and the timeline toggle are on',
      () {
        expect(
          shouldShowTimelineDiagnostics(
            developerMode: true,
            developerUiHidden: false,
            showTimelineDiagnostics: true,
          ),
          isTrue,
        );
      },
    );

    test('is disabled when developer-only app UI is hidden', () {
      expect(
        shouldShowTimelineDiagnostics(
          developerMode: true,
          developerUiHidden: true,
          showTimelineDiagnostics: true,
        ),
        isFalse,
      );
    });
  });
}
