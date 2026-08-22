import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/timeline.dart';
import 'package:intergalactic/client/timeline_events/local_media_send_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';

void main() {
  test('creates a sender-local image event from a pending image', () async {
    var retryCount = 0;
    var cancelCount = 0;
    final pending = PendingFileAttachment(
      name: 'photo.png',
      data: _transparentPng,
      mimeType: 'image/png',
      size: _transparentPng.length,
    );

    final event = LocalMediaSendEvent.fromPendingAttachment(
      eventId: 'local-media-1',
      senderId: '@alice:example.test',
      originServerTs: DateTime.fromMillisecondsSinceEpoch(10),
      pendingAttachment: pending,
      body: 'caption',
      onRetry: (_) async {
        retryCount += 1;
      },
      onCancel: (_) async {
        cancelCount += 1;
      },
    );

    expect(event, isNotNull);
    expect(event!.plainTextBody, 'caption');
    expect(event.status, TimelineEventStatus.sending);
    expect(event.attachments.single, isA<ImageAttachment>());

    event.mark(LocalMediaSendState.failed, error: StateError('upload failed'));
    expect(event.status, TimelineEventStatus.error);

    await event.retrySend();
    await event.cancelSend();

    expect(retryCount, 1);
    expect(cancelCount, 1);
    expect(event.sendState, LocalMediaSendState.cancelled);
  });

  test('creates a sender-local video event from a pending video', () {
    final pending = PendingFileAttachment(
      name: 'clip.mp4',
      data: Uint8List.fromList([1, 2, 3]),
      mimeType: 'video/mp4',
      size: 3,
      spoiler: true,
    );

    final event = LocalMediaSendEvent.fromPendingAttachment(
      eventId: 'local-media-2',
      senderId: '@alice:example.test',
      originServerTs: DateTime.fromMillisecondsSinceEpoch(20),
      pendingAttachment: pending,
      onRetry: (_) async {},
      onCancel: (_) async {},
    );

    expect(event, isNotNull);
    final attachment = event!.attachments.single;
    expect(attachment, isA<VideoAttachment>());
    expect((attachment as VideoAttachment).spoiler, isTrue);
    expect(event.plainTextBody, 'clip.mp4');
  });

  test('ignores unsupported pending attachments', () {
    final pending = PendingFileAttachment(
      name: 'archive.zip',
      data: Uint8List.fromList([1, 2, 3]),
      mimeType: 'application/zip',
    );

    final event = LocalMediaSendEvent.fromPendingAttachment(
      eventId: 'local-media-3',
      senderId: '@alice:example.test',
      originServerTs: DateTime.fromMillisecondsSinceEpoch(30),
      pendingAttachment: pending,
      onRetry: (_) async {},
      onCancel: (_) async {},
    );

    expect(event, isNull);
  });

  test('timeline remove notifies before removing the local event', () {
    final timeline = _FakeTimeline();
    final event = LocalMediaSendEvent.fromPendingAttachment(
      eventId: 'local-media-4',
      senderId: '@alice:example.test',
      originServerTs: DateTime.fromMillisecondsSinceEpoch(40),
      pendingAttachment: PendingFileAttachment(
        name: 'photo.png',
        data: _transparentPng,
        mimeType: 'image/png',
      ),
      onRetry: (_) async {},
      onCancel: (_) async {},
    )!;
    final observedEventIds = <String>[];

    timeline.insertEvent(0, event);
    timeline.onRemove.stream.listen((index) {
      observedEventIds.add(timeline.events[index].eventId);
    });

    expect(timeline.removeEvent(event.eventId), isTrue);

    expect(observedEventIds, [event.eventId]);
    expect(timeline.events, isEmpty);
  });
}

final _transparentPng = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1f,
  0x15,
  0xc4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0a,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9c,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0d,
  0x0a,
  0x2d,
  0xb4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4e,
  0x44,
  0xae,
  0x42,
  0x60,
  0x82,
]);

class _FakeTimeline extends Timeline {
  @override
  bool get canLoadFuture => false;

  @override
  bool get canLoadHistory => false;

  @override
  bool get isLoadingFuture => false;

  @override
  bool get isLoadingHistory => false;

  @override
  Stream<void> get onLoadingStatusChanged => const Stream.empty();

  @override
  bool canDeleteEvent(TimelineEvent event) => false;

  @override
  Future<void> close() async {}

  @override
  void deleteEvent(TimelineEvent event) {}

  @override
  Future<TimelineEvent?> fetchEventByIdInternal(String eventId) async => null;

  @override
  bool isEventRedacted(TimelineEvent event) => false;

  @override
  Future<void> loadMoreFuture() async {}

  @override
  Future<void> loadMoreHistory() async {}

  @override
  void markAsRead(TimelineEvent event) {}
}
