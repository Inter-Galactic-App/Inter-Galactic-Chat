import 'package:intergalactic/client/components/photo_album_room/photo.dart';

enum PhotoAlbumUploadMode {
  individual,
  stack,
}

class PhotoStackMetadata {
  const PhotoStackMetadata({
    required this.id,
    required this.index,
    required this.count,
  });

  static const eventContentKey = 'chat.intergalactic.photo_stack';

  final String id;
  final int index;
  final int count;

  static PhotoStackMetadata? fromContent(Object? value) {
    if (value is! Map) {
      return null;
    }

    final id = value['id'];
    final index = value['index'];
    final count = value['count'];

    if (id is! String || id.trim().isEmpty) {
      return null;
    }

    if (index is! int || count is! int) {
      return null;
    }

    if (count < 2 || index < 0 || index >= count) {
      return null;
    }

    return PhotoStackMetadata(
      id: id,
      index: index,
      count: count,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'index': index,
        'count': count,
      };

  static Map<String, dynamic>? eventContentForUpload({
    required PhotoAlbumUploadMode mode,
    required String stackId,
    required int index,
    required int count,
  }) {
    if (mode != PhotoAlbumUploadMode.stack) {
      return null;
    }

    if (stackId.trim().isEmpty || count < 2 || index < 0 || index >= count) {
      return null;
    }

    final metadata = PhotoStackMetadata(
      id: stackId,
      index: index,
      count: count,
    );

    return {
      eventContentKey: metadata.toJson(),
    };
  }
}

abstract class PhotoAlbumEntry {
  String get id;
  Photo get coverPhoto;
  Photo get rootPhoto;
  List<Photo> get photos;
  int get displayCount;
  bool get isStack;
}

class SinglePhotoAlbumEntry implements PhotoAlbumEntry {
  const SinglePhotoAlbumEntry(this.photo);

  final Photo photo;

  @override
  String get id => photo.id;

  @override
  Photo get coverPhoto => photo;

  @override
  Photo get rootPhoto => photo;

  @override
  List<Photo> get photos => [photo];

  @override
  int get displayCount => 1;

  @override
  bool get isStack => false;
}

class PhotoStackAlbumEntry implements PhotoAlbumEntry {
  PhotoStackAlbumEntry({
    required this.stackId,
    required List<Photo> photos,
  }) : photos = List.unmodifiable(photos) {
    assert(photos.length >= 2);
  }

  final String stackId;

  @override
  final List<Photo> photos;

  @override
  String get id => stackId;

  @override
  Photo get coverPhoto => rootPhoto;

  @override
  Photo get rootPhoto {
    return photos.firstWhere(
      (photo) => photo.stack?.index == 0,
      orElse: () => photos.first,
    );
  }

  @override
  int get displayCount => photos.length;

  @override
  bool get isStack => true;
}

List<PhotoAlbumEntry> buildPhotoAlbumEntries(Iterable<Photo> photos) {
  final orderedItems = <Object>[];
  final stackGroups = <String, List<Photo>>{};

  for (final photo in photos) {
    if (photo.isThreadReply) {
      continue;
    }

    final stack = photo.stack;
    if (stack == null) {
      orderedItems.add(photo);
      continue;
    }

    final group = stackGroups.putIfAbsent(stack.id, () {
      orderedItems.add(stack.id);
      return <Photo>[];
    });
    group.add(photo);
  }

  final result = <PhotoAlbumEntry>[];
  for (final item in orderedItems) {
    if (item is Photo) {
      result.add(SinglePhotoAlbumEntry(item));
      continue;
    }

    final group = stackGroups[item] ?? const <Photo>[];
    final entry = _buildStackEntry(group);
    if (entry != null) {
      result.add(entry);
    } else {
      result.addAll(group.map(SinglePhotoAlbumEntry.new));
    }
  }

  return result;
}

PhotoStackAlbumEntry? _buildStackEntry(List<Photo> group) {
  if (group.length < 2) {
    return null;
  }

  final firstStack = group.first.stack;
  if (firstStack == null) {
    return null;
  }

  if (group.length != firstStack.count) {
    return null;
  }

  final seenIndices = <int>{};
  for (final photo in group) {
    final stack = photo.stack;
    if (stack == null ||
        stack.id != firstStack.id ||
        stack.count != firstStack.count ||
        !seenIndices.add(stack.index)) {
      return null;
    }
  }

  final sorted = List<Photo>.from(group)
    ..sort((left, right) => left.stack!.index.compareTo(right.stack!.index));

  return PhotoStackAlbumEntry(
    stackId: firstStack.id,
    photos: sorted,
  );
}
