import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/room.dart';
import 'package:matrix/matrix.dart' as matrix;

void main() {
  test('maps Matrix knock join rules to visibility variants', () {
    expect(
      MatrixRoom.visibilityFromMatrixJoinRules(matrix.JoinRules.knock, null),
      isA<RoomVisibilityKnock>(),
    );

    final visibility = MatrixRoom.visibilityFromMatrixJoinRules(
      matrix.JoinRules.knockRestricted,
      {
        'join_rule': 'knock_restricted',
        'allow': [
          {
            'room_id': '!space:example.org',
            'type': 'm.room_membership',
          },
        ],
      },
    );

    expect(visibility, isA<RoomVisibilityKnockRestricted>());
    expect(
      (visibility as RoomVisibilityKnockRestricted).spaces,
      ['!space:example.org'],
    );
  });

  test('writes Matrix knock join rule content', () {
    expect(
      MatrixRoom.joinRulesContentForVisibility(RoomVisibilityKnock()),
      {'join_rule': 'knock'},
    );

    expect(
      MatrixRoom.joinRulesContentForVisibility(
        RoomVisibilityKnockRestricted(['!space:example.org']),
      ),
      {
        'join_rule': 'knock_restricted',
        'allow': [
          {
            'room_id': '!space:example.org',
            'type': 'm.room_membership',
          },
        ],
      },
    );
  });

  test('visibility equality keeps matching hash codes', () {
    expect(RoomVisibilityPublic(), RoomVisibilityPublic());
    expect(RoomVisibilityPublic().hashCode, RoomVisibilityPublic().hashCode);
    expect(RoomVisibilityPrivate(), RoomVisibilityPrivate());
    expect(RoomVisibilityPrivate().hashCode, RoomVisibilityPrivate().hashCode);
    expect(RoomVisibilityKnock(), RoomVisibilityKnock());
    expect(RoomVisibilityKnock().hashCode, RoomVisibilityKnock().hashCode);

    final restrictedA = RoomVisibilityRestricted(['!space:example.org']);
    final restrictedB = RoomVisibilityRestricted(['!space:example.org']);
    expect(restrictedA, restrictedB);
    expect(restrictedA.hashCode, restrictedB.hashCode);

    final knockRestrictedA =
        RoomVisibilityKnockRestricted(['!space:example.org']);
    final knockRestrictedB =
        RoomVisibilityKnockRestricted(['!space:example.org']);
    expect(knockRestrictedA, knockRestrictedB);
    expect(knockRestrictedA.hashCode, knockRestrictedB.hashCode);
  });

  test('maps knock restricted rooms to the restricted preview policy', () {
    expect(
      MatrixRoom.shouldPreviewMediaForJoinRules(
        matrix.JoinRules.knock,
        previewPublicRooms: false,
        previewPrivateRooms: true,
        containedInPublicSpace: false,
      ),
      isTrue,
    );

    expect(
      MatrixRoom.shouldPreviewMediaForJoinRules(
        matrix.JoinRules.knockRestricted,
        previewPublicRooms: false,
        previewPrivateRooms: true,
        containedInPublicSpace: false,
      ),
      isTrue,
    );

    expect(
      MatrixRoom.shouldPreviewMediaForJoinRules(
        matrix.JoinRules.knockRestricted,
        previewPublicRooms: true,
        previewPrivateRooms: false,
        containedInPublicSpace: true,
      ),
      isTrue,
    );

    expect(
      MatrixRoom.shouldPreviewMediaForJoinRules(
        matrix.JoinRules.knockRestricted,
        previewPublicRooms: false,
        previewPrivateRooms: true,
        containedInPublicSpace: true,
      ),
      isFalse,
    );
  });

  test('hydrates missing member avatars only for knock-style rooms', () {
    expect(
      MatrixRoom.shouldHydrateMissingMemberAvatarsForJoinRules(
        matrix.JoinRules.knock,
      ),
      isTrue,
    );
    expect(
      MatrixRoom.shouldHydrateMissingMemberAvatarsForJoinRules(
        matrix.JoinRules.knockRestricted,
      ),
      isTrue,
    );
    expect(
      MatrixRoom.shouldHydrateMissingMemberAvatarsForJoinRules(
        matrix.JoinRules.public,
      ),
      isFalse,
    );
    expect(
      MatrixRoom.shouldHydrateMissingMemberAvatarsForJoinRules(
        matrix.JoinRules.invite,
      ),
      isFalse,
    );
  });
}
