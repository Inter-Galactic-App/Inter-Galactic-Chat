import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:matrix/matrix.dart' as matrix;

void main() {
  group('syncCarriesPushRules', () {
    matrix.SyncUpdate syncWith(List<String> accountDataTypes) =>
        matrix.SyncUpdate(
          nextBatch: 'batch',
          accountData: [
            for (final type in accountDataTypes)
              matrix.BasicEvent(type: type, content: const {}),
          ],
        );

    test('fires on the event push rules are derived from', () {
      expect(syncCarriesPushRules(syncWith(['m.push_rules'])), isTrue);
    });

    test('fires when push rules arrive alongside other account data', () {
      expect(
        syncCarriesPushRules(
          syncWith(['m.direct', 'm.push_rules', 'm.tag_order']),
        ),
        isTrue,
      );
    });

    test('stays quiet for unrelated account data', () {
      expect(syncCarriesPushRules(syncWith(['m.direct'])), isFalse);
    });

    test('stays quiet for an empty or absent account-data list', () {
      expect(syncCarriesPushRules(syncWith([])), isFalse);
      expect(
        syncCarriesPushRules(matrix.SyncUpdate(nextBatch: 'batch')),
        isFalse,
      );
    });
  });
}
