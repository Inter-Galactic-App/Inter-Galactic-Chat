import 'package:flutter/widgets.dart';
import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/components/url_preview/matrix_url_preview_component.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:test/test.dart';

void main() {
  test('getPreview returns null when a synced event has no current links',
      () async {
    final mxClient = _FakeMatrixClient('client-a');
    final room = _FakeRoom(
      identifier: '!room:example.org',
      client: mxClient,
    );
    final event = _FakeMessageEvent(eventId: r'$no-link', links: const []);
    final timeline = _FakeTimeline(room: room, events: [event]);

    var responseCalls = 0;
    final component = MatrixUrlPreviewComponent(
      mxClient,
      responseFetcher: (_, __) async {
        responseCalls += 1;
        return {'og:title': 'Should not load'};
      },
      directFetcher: (_) async => null,
      uriNormalizer: (uri) async => uri,
      matrixClientProvider: (_) => _FakeSdkClient(),
    );

    final preview = await component.getPreview(timeline, event);

    expect(preview, isNull);
    expect(responseCalls, 0);
  });
}

class _FakeMatrixClient implements MatrixClient {
  _FakeMatrixClient(this.identifier);

  @override
  final String identifier;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSdkClient implements matrix.Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRoom implements Room {
  _FakeRoom({
    required this.identifier,
    required this.client,
  });

  @override
  final String identifier;

  @override
  final Client client;

  @override
  bool get isE2EE => false;

  @override
  bool get shouldPreviewMedia => true;

  @override
  Timeline? get timeline => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTimeline extends Timeline {
  _FakeTimeline({
    required Room room,
    required List<TimelineEvent> events,
  }) {
    this.room = room;
    client = room.client;
    this.events = List<TimelineEvent>.from(events);
  }

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
  Future<void> close() async {}

  @override
  bool canDeleteEvent(TimelineEvent event) => false;

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

class _FakeMessageEvent implements TimelineEventMessage {
  _FakeMessageEvent({
    required this.eventId,
    required List<Uri> links,
  }) : _links = links;

  final List<Uri> _links;

  @override
  final String eventId;

  @override
  TimelineEventStatus get status => TimelineEventStatus.synced;

  @override
  String get senderId => '@sender:example.org';

  @override
  DateTime get originServerTs => DateTime(2026, 6, 13);

  @override
  String get plainTextBody => _links.map((uri) => uri.toString()).join(' ');

  @override
  String get source => plainTextBody;

  @override
  bool get editable => true;

  @override
  String? get body => plainTextBody;

  @override
  String? get bodyFormat => null;

  @override
  String? get formattedBody => plainTextBody;

  @override
  List<Attachment>? get attachments => null;

  @override
  Widget? buildFormattedContent({Timeline? timeline}) => null;

  @override
  List<Uri>? getLinks({Timeline? timeline}) =>
      _links.isEmpty ? null : List<Uri>.from(_links);

  @override
  String getPlaintextBody(Timeline timeline) => plainTextBody;

  @override
  bool isEdited(Timeline timeline) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
