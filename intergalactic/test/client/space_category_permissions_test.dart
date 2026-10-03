import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/favorite_room_categories.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';
import 'package:intergalactic/client/permissions.dart';
import 'package:intergalactic/client/space.dart';
import 'package:intergalactic/client/space_room_categories.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Limbs 2 and 3 of the space-categories audit
/// (docs/audit/space-categories-queue-record-2026-08-21.md).
///
/// LIMB 3: the permission gate required power level 100 AND
/// `canChangeStateEvent`. The hardcoded half could only ever disagree with the
/// room by REFUSING something the room had allowed - a space that grants the
/// category event at PL 50 in its own `m.room.power_levels` events map was
/// still refused by the client, with nothing to tell the user why. Matrix has
/// no notion of "space admin" beyond what the space declares.
///
/// LIMB 2: the device-local store and the shared room-state store both took a
/// bare `String spaceLocalId`, so a Matrix space could be written to the local
/// one. Nothing reads it back for a Matrix space, so the copy sat there
/// diverging silently. A type removes the call rather than rejecting it.
void main() {
  group('canManageSpaceRoomCategories defers to the room', () {
    test('a space that grants the event below PL 100 is allowed', () {
      final space = _FakeMatrixSpace(canChangeCategories: true);

      expect(
        canManageSpaceRoomCategories(space),
        isTrue,
        reason:
            'the space granted this event in its own power levels; the client '
            'has no separate say',
      );
    });

    test('a space that does not grant the event is refused', () {
      final space = _FakeMatrixSpace(canChangeCategories: false);

      expect(canManageSpaceRoomCategories(space), isFalse);
    });

    // The gate asks about THIS event type, not about being an admin generally.
    test('the question asked is about the category event type', () {
      final space = _FakeMatrixSpace(canChangeCategories: true);

      canManageSpaceRoomCategories(space);

      expect(space.askedAbout, [matrixSpaceRoomCategoriesEventType]);
    });

    test('a non-Matrix space falls back to its own child permission', () {
      expect(
        canManageSpaceRoomCategories(_FakeLocalSpace(canEditChildren: true)),
        isTrue,
      );
      expect(
        canManageSpaceRoomCategories(_FakeLocalSpace(canEditChildren: false)),
        isFalse,
      );
    });
  });

  group(
    'LocalSpaceCategoryScope keeps Matrix spaces out of the local store',
    () {
      test('a Matrix space cannot be given a local scope', () {
        expect(
          () => LocalSpaceCategoryScope.forSpace(
            _FakeMatrixSpace(canChangeCategories: true),
          ),
          throwsArgumentError,
          reason:
              'a Matrix space keeps categories in room state; a local copy of '
              'them is the stale divergence this type exists to prevent',
        );
      });

      test('a non-Matrix space gets its own local id', () {
        final scope = LocalSpaceCategoryScope.forSpace(
          _FakeLocalSpace(canEditChildren: true, localId: '!local:example.org'),
        );

        expect(scope.localId, '!local:example.org');
      });

      test('the favourites pseudo-space is a local scope', () {
        expect(
          LocalSpaceCategoryScope.favorites.localId,
          favoriteRoomCategoriesLocalId,
        );
      });
    },
  );
}

class _FakeMatrixSpace implements MatrixSpace {
  _FakeMatrixSpace({required this.canChangeCategories});

  final bool canChangeCategories;
  final List<String> askedAbout = [];

  @override
  String get identifier => '!space:example.org';

  @override
  matrix.Room get matrixRoom => _FakeSdkRoom(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSdkRoom implements matrix.Room {
  _FakeSdkRoom(this._space);

  final _FakeMatrixSpace _space;

  @override
  bool canChangeStateEvent(String action) {
    _space.askedAbout.add(action);
    return _space.canChangeCategories;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeLocalSpace implements Space {
  _FakeLocalSpace({
    required this.canEditChildren,
    this.localId = 'local-space',
  });

  final bool canEditChildren;

  @override
  final String localId;

  @override
  Permissions get permissions =>
      _FakePermissions(canEditChildren: canEditChildren);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakePermissions implements Permissions {
  _FakePermissions({required this.canEditChildren});

  @override
  final bool canEditChildren;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
