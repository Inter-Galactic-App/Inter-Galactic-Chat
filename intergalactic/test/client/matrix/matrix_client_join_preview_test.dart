import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/room_preview.dart';

void main() {
  test('knock-only preview requests knock without joining', () async {
    final preview = GenericRoomPreview(
      '!room:example.org',
      displayName: 'Knock room',
      type: RoomType.defaultRoom,
      visibility: RoomVisibilityKnock(),
    );
    final knockedRooms = <({String roomId, List<String>? via})>[];
    var joinCalled = false;

    final result = await joinRoomFromPreviewWithMatrixActions(
      preview: preview,
      parseAddressToIdAndVia: (address) {
        expect(address, '!room:example.org');
        return (address, ['example.org']);
      },
      knockRoom: (roomId, {via}) async {
        knockedRooms.add((roomId: roomId, via: via));
      },
      joinRoom: (roomId, {via}) async {
        joinCalled = true;
        return roomId;
      },
      waitForRoomInSync: (_) async {
        throw StateError('Knock previews must not wait for room sync');
      },
      hasRoom: (_) => false,
      getRoom: (_) => null,
      createJoinedRoom: (_) {
        throw StateError('Knock previews must not create joined rooms');
      },
    );

    expect(result.outcome, RoomPreviewJoinOutcome.knockRequested);
    expect(result.room, isNull);
    expect(joinCalled, isFalse);
    expect(knockedRooms, hasLength(1));
    expect(knockedRooms.single.roomId, '!room:example.org');
    expect(knockedRooms.single.via, ['example.org']);
  });
}
