import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:matrix/matrix.dart' as matrix;

void main() {
  group('matrixThreadRelationExtraContent', () {
    test('returns no extra content outside threads', () {
      expect(
        matrixThreadRelationExtraContent(threadRootEventId: null),
        isNull,
      );
    });

    test('adds thread relation metadata for upload placeholders', () {
      final extraContent = matrixThreadRelationExtraContent(
        threadRootEventId: r'$root',
      );

      final relation = extraContent!['m.relates_to'] as Map<String, dynamic>;
      expect(relation['event_id'], r'$root');
      expect(relation['rel_type'], matrix.RelationshipTypes.thread);
      expect(relation['is_falling_back'], isTrue);
      expect(relation.containsKey('m.in_reply_to'), isFalse);
    });

    test('preserves the latest thread event when available', () {
      final extraContent = matrixThreadRelationExtraContent(
        threadRootEventId: r'$root',
        threadLastEventId: r'$last',
      );

      final relation = extraContent!['m.relates_to'] as Map<String, dynamic>;
      expect(relation['m.in_reply_to'], {'event_id': r'$last'});
    });
  });
}
