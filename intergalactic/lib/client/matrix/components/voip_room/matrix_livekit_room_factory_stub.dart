import 'package:livekit_client/livekit_client.dart' as lk;

lk.Room createMatrixLivekitRoom({required lk.RoomOptions roomOptions}) {
  return lk.Room(roomOptions: roomOptions);
}
