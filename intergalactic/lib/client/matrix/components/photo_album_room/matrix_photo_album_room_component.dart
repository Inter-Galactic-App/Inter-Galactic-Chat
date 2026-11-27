import 'package:intergalactic/client/components/photo_album_room/photo_album_room_component.dart';
import 'package:intergalactic/client/components/photo_album_room/photo_album_entry.dart';
import 'package:intergalactic/client/components/photo_album_room/photo_album_timeline.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/matrix/components/matrix_sync_listener.dart';
import 'package:intergalactic/client/matrix/components/photo_album_room/matrix_photo_album_timeline.dart';
import 'package:intergalactic/client/matrix/components/photo_album_room/matrix_upload_photos_task.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/main.dart';
import 'package:matrix/matrix.dart';

class MatrixPhotoAlbumRoomComponent
    implements
        PhotoAlbumRoom<MatrixClient, MatrixRoom>,
        MatrixRoomSyncListener,
        DisposableComponent {
  @override
  MatrixClient client;

  @override
  MatrixRoom room;

  final List<MatrixPhotoAlbumTimeline> _timelines = [];
  bool _disposed = false;

  MatrixPhotoAlbumRoomComponent(this.client, this.room);

  @override
  onSync(JoinedRoomUpdate update) {
    if (_disposed) {
      return;
    }
  }

  static bool isPhotoAlbumRoom(MatrixRoom room) {
    return room.matrixRoom.getState(EventTypes.RoomCreate)?.content['type'] ==
        "chat.commet.photo_album";
  }

  @override
  bool get canUpload => room.permissions.canSendMessage;

  @override
  Future<PhotoAlbumTimeline> getTimeline() async {
    if (_disposed) {
      throw StateError('Photo album room component has been disposed');
    }

    var timeline = MatrixPhotoAlbumTimeline(room);
    await timeline.initTimeline();
    if (_disposed) {
      await timeline.dispose();
      throw StateError('Photo album room component has been disposed');
    }

    _timelines.add(timeline);
    return timeline;
  }

  @override
  Future<void> uploadPhotos(
    List<PickedPhoto> photos, {
    PhotoAlbumUploadMode mode = PhotoAlbumUploadMode.individual,
    bool sendOriginal = false,
    bool extractMetadata = true,
  }) async {
    if (_disposed) {
      return;
    }

    var task = MatrixUploadPhotosTask(
      photos,
      room,
      mode: mode,
      sendOriginal: sendOriginal,
      extractMetadata: extractMetadata,
    );
    backgroundTaskManager.addTask(task);
    await task.uploadImages();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    await Future.wait(_timelines.map((timeline) => timeline.dispose()));
    _timelines.clear();
  }
}
