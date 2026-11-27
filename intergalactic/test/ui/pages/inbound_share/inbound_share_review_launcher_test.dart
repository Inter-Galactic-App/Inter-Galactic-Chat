import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/pages/inbound_share/inbound_share_review_launcher.dart';

void main() {
  group('uniquePreselectedDestination', () {
    test('returns the only matching destination', () {
      final match = InboundShareReviewLauncher.uniquePreselectedDestination(
        const ['personal', 'work'],
        (destination) => destination == 'work',
      );

      expect(match, 'work');
    });

    test('returns null when no destination matches', () {
      final match = InboundShareReviewLauncher.uniquePreselectedDestination(
        const ['personal', 'work'],
        (destination) => destination == 'missing',
      );

      expect(match, isNull);
    });

    test('returns null when the room is ambiguous across accounts', () {
      final match = InboundShareReviewLauncher.uniquePreselectedDestination(
        const ['personal', 'work'],
        (_) => true,
      );

      expect(match, isNull);
    });
  });
}
