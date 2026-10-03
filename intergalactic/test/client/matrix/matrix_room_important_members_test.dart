import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';

void main() {
  test('includes room-version-12 creators omitted from explicit users', () {
    expect(
      matrixImportantMemberIds(
        explicitUsers: <Object?, Object?>{'@moderator:example.org': 50},
        immutableCreatorIds: const ['@creator:example.org'],
      ),
      {'@moderator:example.org', '@creator:example.org'},
    );
  });

  test('handles rooms without explicit power-level users', () {
    expect(
      matrixImportantMemberIds(
        explicitUsers: null,
        immutableCreatorIds: const ['@creator:example.org'],
      ),
      {'@creator:example.org'},
    );
  });

  test('recognizes only non-empty tombstone replacements', () {
    expect(matrixRoomHasReplacementId(null), isFalse);
    expect(matrixRoomHasReplacementId('  '), isFalse);
    expect(matrixRoomHasReplacementId('!successor:example.org'), isTrue);
  });
}
