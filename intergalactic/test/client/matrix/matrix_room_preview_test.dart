import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/matrix_room_preview.dart';
import 'package:intergalactic/client/room.dart';

void main() {
  group('MatrixSpaceRoomChunkPreview.visibilityFromJoinRule', () {
    test('treats absent join rules as neutral previews', () {
      expect(
        MatrixSpaceRoomChunkPreview.visibilityFromJoinRule(null, null),
        isNull,
      );
      expect(
        MatrixSpaceRoomChunkPreview.visibilityFromJoinRule('', null),
        isNull,
      );
    });

    test('maps public previews to public visibility', () {
      expect(
        MatrixSpaceRoomChunkPreview.visibilityFromJoinRule('public', null),
        isA<RoomVisibilityPublic>(),
      );
    });

    test('leaves unknown join rules unsupported', () {
      expect(
        MatrixSpaceRoomChunkPreview.visibilityFromJoinRule('custom', null),
        isNull,
      );
    });

    test('maps invite and private previews to private visibility', () {
      expect(
        MatrixSpaceRoomChunkPreview.visibilityFromJoinRule('invite', null),
        isA<RoomVisibilityPrivate>(),
      );
      expect(
        MatrixSpaceRoomChunkPreview.visibilityFromJoinRule('private', null),
        isA<RoomVisibilityPrivate>(),
      );
    });

    test('maps knock previews to knock visibility', () {
      expect(
        MatrixSpaceRoomChunkPreview.visibilityFromJoinRule('knock', null),
        isA<RoomVisibilityKnock>(),
      );
    });

    test('maps restricted previews with allowed space ids', () {
      final visibility = MatrixSpaceRoomChunkPreview.visibilityFromJoinRule(
        'restricted',
        ['!space:example.org'],
      );

      expect(visibility, isA<RoomVisibilityRestricted>());
      expect(
        (visibility! as RoomVisibilityRestricted).spaces,
        ['!space:example.org'],
      );
    });

    test('maps knock restricted previews with allowed space ids', () {
      final visibility = MatrixSpaceRoomChunkPreview.visibilityFromJoinRule(
        'knock_restricted',
        ['!space:example.org'],
      );

      expect(visibility, isA<RoomVisibilityKnockRestricted>());
      expect(
        (visibility! as RoomVisibilityKnockRestricted).spaces,
        ['!space:example.org'],
      );
    });
  });
}
