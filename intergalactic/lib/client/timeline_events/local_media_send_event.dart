import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intergalactic/cache/cache_file_provider.dart';
import 'package:intergalactic/cache/file_provider.dart';
import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/timeline.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/utils/mime.dart';

enum LocalMediaSendState {
  preparing,
  uploading,
  sending,
  sent,
  failed,
  cancelled,
}

class LocalMediaSendEvent implements TimelineEventMessage {
  LocalMediaSendEvent({
    required this.eventId,
    required this.senderId,
    required this.originServerTs,
    required Attachment attachment,
    required this.onRetry,
    required this.onCancel,
    String? body,
  })  : _body = body,
        attachments = [attachment];

  static LocalMediaSendEvent? fromPendingAttachment({
    required String eventId,
    required String senderId,
    required DateTime originServerTs,
    required PendingFileAttachment pendingAttachment,
    required Future<void> Function(LocalMediaSendEvent event) onRetry,
    required Future<void> Function(LocalMediaSendEvent event) onCancel,
    String? body,
  }) {
    final mimeType = pendingAttachment.mimeType;
    if (mimeType == null) {
      return null;
    }

    final fileProvider = _fileProviderFor(eventId, pendingAttachment);
    final name = pendingAttachment.name ?? 'media';
    final size = pendingAttachment.size ?? pendingAttachment.data?.length;

    if (Mime.imageTypes.contains(mimeType)) {
      final image = pendingAttachment.getAsImage();
      if (image == null) {
        return null;
      }

      return LocalMediaSendEvent(
        eventId: eventId,
        senderId: senderId,
        originServerTs: originServerTs,
        body: body,
        onRetry: onRetry,
        onCancel: onCancel,
        attachment: ImageAttachment(
          image,
          fileProvider,
          name: name,
          mimeType: mimeType,
          fileSize: size,
          spoiler: pendingAttachment.spoiler,
          width: pendingAttachment.dimensions?.width,
          height: pendingAttachment.dimensions?.height,
        ),
      );
    }

    if (Mime.videoTypes.contains(mimeType)) {
      final thumbnail = pendingAttachment.thumbnailFile == null
          ? null
          : MemoryImage(pendingAttachment.thumbnailFile!);

      return LocalMediaSendEvent(
        eventId: eventId,
        senderId: senderId,
        originServerTs: originServerTs,
        body: body,
        onRetry: onRetry,
        onCancel: onCancel,
        attachment: VideoAttachment(
          fileProvider,
          name: name,
          mimeType: mimeType,
          fileSize: size,
          spoiler: pendingAttachment.spoiler,
          thumbnail: thumbnail,
          width: pendingAttachment.dimensions?.width,
          height: pendingAttachment.dimensions?.height,
          duration: pendingAttachment.length,
        ),
      );
    }

    return null;
  }

  final String? _body;
  final Future<void> Function(LocalMediaSendEvent event) onRetry;
  final Future<void> Function(LocalMediaSendEvent event) onCancel;
  LocalMediaSendState sendState = LocalMediaSendState.preparing;
  Object? sendError;

  bool get isCancelled => sendState == LocalMediaSendState.cancelled;

  void mark(LocalMediaSendState nextState, {Object? error}) {
    sendState = nextState;
    sendError = error;
  }

  Future<void> retrySend() => onRetry(this);

  Future<void> cancelSend() async {
    mark(LocalMediaSendState.cancelled);
    await onCancel(this);
  }

  @override
  final String eventId;

  @override
  final String senderId;

  @override
  final DateTime originServerTs;

  @override
  final List<Attachment> attachments;

  @override
  TimelineEventStatus get status => sendState == LocalMediaSendState.failed
      ? TimelineEventStatus.error
      : TimelineEventStatus.sending;

  @override
  bool get editable => false;

  @override
  String get source => jsonEncode({
        'type': 'chat.intergalactic.local_media_send',
        'state': sendState.name,
        'attachment_count': attachments.length,
      });

  @override
  String get plainTextBody =>
      body?.trim().isNotEmpty == true ? body!.trim() : attachments.first.name;

  @override
  String? get body => _body;

  @override
  String? get bodyFormat => null;

  @override
  String? get formattedBody => null;

  @override
  Widget? buildFormattedContent({Timeline? timeline}) {
    final text = body?.trim();
    if (text == null || text.isEmpty) {
      return null;
    }

    return Text(text);
  }

  @override
  String getPlaintextBody(Timeline timeline) => plainTextBody;

  @override
  bool isEdited(Timeline timeline) => false;

  @override
  List<Uri>? getLinks({Timeline? timeline}) => null;
}

FileProvider _fileProviderFor(
  String eventId,
  PendingFileAttachment pendingAttachment,
) {
  final path = pendingAttachment.path;
  if (path != null) {
    return SystemFileProvider(path);
  }

  final bytes = pendingAttachment.data ?? Uint8List(0);
  return CacheFileProvider('pending-media-$eventId', () async => bytes);
}
