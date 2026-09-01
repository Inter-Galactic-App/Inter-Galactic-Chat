import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/matrix/extensions/matrix_event_extensions.dart';
import 'package:intergalactic/client/matrix/matrix_mxc_file_provider.dart';
import 'package:intergalactic/client/matrix/matrix_mxc_image_provider.dart';
import 'package:intergalactic/client/timeline.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_sticker.dart';
import 'package:intergalactic/utils/mime.dart';
import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart' as matrix;

bool matrixBackgroundEventIsSticker(matrix.MatrixEvent event) {
  return event.type == matrix.EventTypes.Sticker ||
      (event.type == matrix.EventTypes.Message &&
          event.content['msgtype'] == 'm.image' &&
          event.content['chat.commet.type'] == 'chat.commet.sticker');
}

bool matrixBackgroundEventIsNotificationCandidate(matrix.MatrixEvent event) {
  return {
    matrix.EventTypes.Encrypted,
    matrix.EventTypes.Message,
    matrix.EventTypes.Sticker,
  }.contains(event.type);
}

class MatrixBackgroundTimelineEventMessage implements TimelineEventMessage {
  matrix.MatrixEvent event;
  final matrix.Client? mediaClient;
  final matrix.Event? mediaEvent;

  MatrixBackgroundTimelineEventMessage(
    this.event, {
    this.mediaClient,
    this.mediaEvent,
  });

  @override
  late final List<Attachment>? attachments = _parseAttachments();

  List<Attachment>? _parseAttachments() {
    final mediaClient = this.mediaClient;
    final mediaEvent = this.mediaEvent;
    if (mediaClient == null ||
        mediaEvent == null ||
        !mediaEvent.hasAttachment) {
      return null;
    }

    final mediaUri = mediaEvent.attachmentMxcUrl;
    if (mediaUri == null) {
      return null;
    }

    final mimeType = mediaEvent.attachmentMimetype;
    // `info.mimetype` is optional in Matrix m.image events. The message type
    // remains authoritative here, and Android preview staging converts the
    // decoded image to PNG before exposing it to the notification renderer.
    final previewMimeType = Mime.imageTypes.contains(mimeType)
        ? mimeType
        : 'image/png';
    final filename = mediaEvent.content['filename'] is String
        ? mediaEvent.content['filename'] as String
        : mediaEvent.plaintextBody;
    return [
      ImageAttachment(
        MatrixMxcImage(
          mediaUri,
          mediaClient,
          doThumbnail: mediaEvent.hasThumbnail,
          doFullres: true,
          autoLoadFullRes: !mediaEvent.hasThumbnail,
          matrixEvent: mediaEvent,
        ),
        MxcFileProvider(mediaClient, mediaUri, event: mediaEvent),
        name: filename,
        mimeType: previewMimeType,
        width: mediaEvent.attachmentWidth,
        height: mediaEvent.attachmentHeight,
      ),
    ];
  }

  @override
  String? get body => event.content.toString();

  @override
  String? get bodyFormat => null;

  @override
  Widget? buildFormattedContent({Timeline? timeline}) {
    return null;
  }

  @override
  bool get editable => false;

  @override
  String get eventId => event.eventId;

  @override
  String? get formattedBody => null;

  @override
  List<Uri>? getLinks({Timeline? timeline}) {
    throw UnimplementedError();
  }

  @override
  bool isEdited(Timeline timeline) {
    throw UnimplementedError();
  }

  @override
  DateTime get originServerTs => event.originServerTs;

  @override
  String get plainTextBody {
    if (event.type == matrix.EventTypes.Encrypted) {
      return "Sent a message";
    }

    if (event.type == matrix.EventTypes.Message ||
        event.type == matrix.EventTypes.Sticker) {
      if (event.content["body"] is String) {
        return event.content["body"] as String;
      }
    }

    // A sticker whose media could not be resolved falls back to this wrapper,
    // and it is still a perfectly valid sticker event. Reporting it as an
    // unknown type put "Unknown event type" in the notification.
    if (event.type == matrix.EventTypes.Sticker) {
      return "Sticker";
    }

    return "Unknown event type";
  }

  @override
  String get senderId => event.senderId;

  @override
  String get source => throw UnimplementedError();

  @override
  TimelineEventStatus get status => throw UnimplementedError();

  @override
  String getPlaintextBody(Timeline timeline) {
    return plainTextBody;
  }
}

class MatrixBackgroundTimelineEventSticker
    implements TimelineEventSticker, TimelineEventAnimatedSticker {
  MatrixBackgroundTimelineEventSticker._(
    this.event, {
    required matrix.Client mediaClient,
    required matrix.Event mediaEvent,
    required Uri mediaUri,
  }) : stickerImage = MatrixMxcImage(
         mediaUri,
         mediaClient,
         doThumbnail: mediaEvent.hasThumbnail,
         doFullres: true,
         autoLoadFullRes: !mediaEvent.hasThumbnail,
         matrixEvent: mediaEvent,
       );

  final matrix.MatrixEvent event;

  @override
  final MatrixMxcImage stickerImage;

  static MatrixBackgroundTimelineEventSticker? tryCreate(
    matrix.MatrixEvent event, {
    required matrix.Client mediaClient,
    required matrix.Event mediaEvent,
  }) {
    final mediaUri = _mediaUri(mediaEvent);
    if (mediaUri == null) {
      return null;
    }
    return MatrixBackgroundTimelineEventSticker._(
      event,
      mediaClient: mediaClient,
      mediaEvent: mediaEvent,
      mediaUri: mediaUri,
    );
  }

  static Uri? _mediaUri(matrix.Event event) {
    final mediaUri = event.attachmentMxcUrl;
    if (mediaUri != null) return mediaUri;

    final file = event.content['file'];
    final rawUri =
        event.content['url'] ??
        (file is Map<String, dynamic> ? file['url'] : null);
    final parsedUri = rawUri is String ? Uri.tryParse(rawUri) : null;
    return parsedUri?.scheme == 'mxc' ? parsedUri : null;
  }

  @override
  String get stickerName => event.content['body'] is String
      ? event.content['body'] as String
      : 'sticker';

  @override
  bool get isAnimatedSticker =>
      timelineStickerIsAnimated(event.content, stickerName);

  @override
  String get plainTextBody => stickerName;

  @override
  bool get editable => false;

  @override
  String get eventId => event.eventId;

  @override
  DateTime get originServerTs => event.originServerTs;

  @override
  String get senderId => event.senderId;

  @override
  String get source => throw UnimplementedError();

  @override
  TimelineEventStatus get status => throw UnimplementedError();
}
