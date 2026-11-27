import 'dart:async';

import 'package:intergalactic/client/components/photo_album_room/photo.dart';
import 'package:intergalactic/client/components/photo_album_room/photo_album_entry.dart';
import 'package:intergalactic/client/components/photo_album_room/photo_album_timeline.dart';
import 'package:intergalactic/client/matrix/components/photo_album_room/matrix_photo.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/room_open_decrypt_retry.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:intergalactic/client/timeline.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/utils/mime.dart';
import 'package:intergalactic/utils/notifying_list.dart';

class MatrixPhotoAlbumTimeline implements PhotoAlbumTimeline {
  final MatrixRoom room;
  late Timeline matrixTimeline;
  final List<StreamSubscription> _subscriptions = [];
  bool _disposed = false;

  NotifyingList<Photo> _photos = NotifyingList.empty(growable: true);

  MatrixPhotoAlbumTimeline(this.room);

  @override
  Stream<int> get onAdded => _photos.onAdd;

  @override
  Stream<int> get onChanged => _photos.onItemUpdated;

  @override
  Stream<int> get onRemoved => _photos.onRemove;

  Future<void> initTimeline() async {
    matrixTimeline = await room.getTimeline();
    await roomOpenDecryptRetryCoordinator.maybeRetryForLoadedTimeline(
      matrixTimeline,
      trigger: 'photo_album_open',
    );
    if (_disposed) {
      return;
    }

    for (var i = 0; i < matrixTimeline.events.length; i++) {
      handleNewEvent(matrixTimeline.events[i], i);
    }

    _subscriptions.addAll([
      matrixTimeline.onEventAdded.stream.listen(onEventAdded),
      matrixTimeline.onChange.stream.listen(onEventChanged),
      matrixTimeline.onRemove.stream.listen(onEventRemoved),
    ]);
  }

  void handleNewEvent(TimelineEvent event, int index) {
    if (_disposed) {
      return;
    }

    print("Photo timeline handling event: $event");
    if (event is! MatrixTimelineEventMessage) return;
    if (event.event.attachmentMimetype == "") return;

    if (!(Mime.imageTypes.contains(event.event.attachmentMimetype) ||
        Mime.videoTypes.contains(event.event.attachmentMimetype))) {
      return;
    }

    if (index != 0) {
      index = _photos.length;
    }

    var newIndex = _photos.indexWhere((photo) {
      var p = photo as MatrixPhoto;
      return (p.event.eventId == event.eventId ||
          (p.event.event.transactionId != null &&
              p.event.event.transactionId == event.event.transactionId));
    });

    if (newIndex != -1) {
      print("New event already exists!");
      return;
    }

    var photo = eventToPhoto(event);
    if (photo != null) {
      _photos.insert(index, photo);
    }
  }

  MatrixPhoto? eventToPhoto(TimelineEventMessage event) {
    var photo = MatrixPhoto(event as MatrixTimelineEvent);
    if (photo.isThreadReply) {
      return null;
    }

    return photo;
  }

  @override
  List<Photo> get photos => _photos;

  @override
  List<PhotoAlbumEntry> get entries => buildPhotoAlbumEntries(_photos);

  void onEventAdded(int event) {
    if (_disposed) {
      return;
    }

    handleNewEvent(matrixTimeline.events[event], event);
  }

  @override
  bool get canLoadMorePhotos => matrixTimeline.canLoadHistory;

  @override
  Future<void> loadMorePhotos() async {
    await matrixTimeline.loadMoreHistory();
    await roomOpenDecryptRetryCoordinator.maybeRetryForLoadedTimeline(
      matrixTimeline,
      trigger: 'photo_album_history_pagination',
    );
  }

  void onEventChanged(int index) {
    if (_disposed) {
      return;
    }

    print("On Event Changed!");
    var event = matrixTimeline.events[index];

    if (event is! MatrixTimelineEventMessage) return;

    var newIndex = _photos.indexWhere((photo) {
      var p = photo as MatrixPhoto;
      return (p.event.eventId == event.eventId ||
          (p.event.event.transactionId != null &&
              p.event.event.transactionId == event.event.transactionId));
    });

    var newPhoto = eventToPhoto(event);
    if (newPhoto != null) {
      if (newIndex == -1) {
        _photos.insert(index == 0 ? 0 : _photos.length, newPhoto);
      } else {
        _photos[newIndex] = newPhoto;
      }
    } else {
      if (newIndex != -1) {
        _photos.removeAt(newIndex);
      }
    }
  }

  void onEventRemoved(int index) {
    if (_disposed) {
      return;
    }

    var event = matrixTimeline.events[index];

    _photos
        .removeWhere((e) => (e as MatrixPhoto).event.eventId == event.eventId);
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    await Future.wait(
      _subscriptions.map((subscription) => subscription.cancel()),
    );
    _subscriptions.clear();
    _photos.close();
  }
}
