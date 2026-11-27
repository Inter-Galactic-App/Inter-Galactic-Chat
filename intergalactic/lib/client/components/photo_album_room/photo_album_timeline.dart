import 'package:intergalactic/client/components/photo_album_room/photo_album_entry.dart';
import 'package:intergalactic/client/components/photo_album_room/photo.dart';

abstract class PhotoAlbumTimeline {
  Stream<int> get onAdded;
  Stream<int> get onChanged;
  Stream<int> get onRemoved;

  List<Photo> get photos;

  List<PhotoAlbumEntry> get entries;

  bool get canLoadMorePhotos;
  Future<void> loadMorePhotos();
}
