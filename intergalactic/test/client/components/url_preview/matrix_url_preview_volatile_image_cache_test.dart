import 'package:flutter/widgets.dart';
import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/url_preview/url_preview_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/components/url_preview/matrix_url_preview_component.dart';
import 'package:intergalactic/client/matrix/components/url_preview/url_preview_durable_cache.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('direct social preview restores signed thumbnail after room reentry',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final durableCache = UrlPreviewDurableCache(
      preferences: prefs,
      prefix: 'url-preview-volatile-reentry-test',
    );
    final previewUri =
        Uri.parse('https://www.tiktok.com/@demo/video/1234567890');
    final thumbnailUri = Uri.parse(
      'https://p16-sign-va.tiktokcdn.com/obj/tos-maliva-p-0068/demo.jpeg'
      '?x-expires=1893456000&x-signature=public-cdn-signature',
    );

    final firstClient = _FakeMatrixClient('client-a');
    final firstRoom = _FakeRoom(
      identifier: '!room:example.org',
      client: firstClient,
    );
    final firstEvent = _FakeMessageEvent(
      eventId: r'$tiktok-first',
      links: [previewUri],
    );
    final firstTimeline = _FakeTimeline(room: firstRoom, events: [firstEvent]);

    var directCalls = 0;
    var networkCalls = 0;
    final firstComponent = MatrixUrlPreviewComponent(
      firstClient,
      responseFetcher: (_, __) async {
        networkCalls += 1;
        return null;
      },
      directFetcher: (uri) async {
        directCalls += 1;
        return UrlPreviewData(
          uri,
          siteName: 'TikTok',
          title: 'Fresh TikTok preview',
          image: NetworkImage(thumbnailUri.toString()),
          imageUri: thumbnailUri,
          imageWidth: 1,
          imageHeight: 1,
        );
      },
      uriNormalizer: (uri) async => uri,
      matrixClientProvider: (_) => _FakeSdkClient(),
      durableCache: durableCache,
    );

    final firstPreview =
        await firstComponent.getPreview(firstTimeline, firstEvent);

    expect(firstPreview?.image, isA<NetworkImage>());
    expect(firstPreview?.imageUri, thumbnailUri);
    expect(directCalls, 1);
    expect(networkCalls, 1);

    final secondClient = _FakeMatrixClient('client-b');
    final secondRoom = _FakeRoom(
      identifier: '!room:example.org',
      client: secondClient,
    );
    final secondEvent = _FakeMessageEvent(
      eventId: r'$tiktok-second',
      links: [previewUri],
    );
    final secondTimeline =
        _FakeTimeline(room: secondRoom, events: [secondEvent]);
    final secondComponent = MatrixUrlPreviewComponent(
      secondClient,
      responseFetcher: (_, __) async {
        networkCalls += 1;
        return null;
      },
      directFetcher: (_) async {
        directCalls += 1;
        return null;
      },
      uriNormalizer: (uri) async => uri,
      matrixClientProvider: (_) => _FakeSdkClient(),
      durableCache: durableCache,
    );

    final restoredPreview =
        await secondComponent.getPreview(secondTimeline, secondEvent);

    expect(restoredPreview?.title, 'Fresh TikTok preview');
    expect(restoredPreview?.image, isA<NetworkImage>());
    expect(restoredPreview?.imageUri, thumbnailUri);
    expect(directCalls, 1);
    expect(networkCalls, 1);
  });

  test('transient signed thumbnails expire before durable preview metadata',
      () async {
    final prefs = await SharedPreferences.getInstance();
    var now = DateTime.utc(2026, 6, 15, 12);
    final durableCache = UrlPreviewDurableCache(
      preferences: prefs,
      now: () => now,
      volatileImageTtl: const Duration(hours: 1),
      prefix: 'url-preview-volatile-image-expiry-test',
    );
    final previewUri =
        Uri.parse('https://www.tiktok.com/@demo/video/1234567890');
    final thumbnailUri = Uri.parse(
      'https://p16-sign-va.tiktokcdn.com/obj/tos-maliva-p-0068/demo.jpeg'
      '?x-expires=1893456000&x-signature=public-cdn-signature',
    );

    await durableCache.put(
      previewUri,
      UrlPreviewData(
        previewUri,
        siteName: 'TikTok',
        title: 'Stored TikTok preview',
        image: NetworkImage(thumbnailUri.toString()),
        imageUri: thumbnailUri,
        imageWidth: 1,
        imageHeight: 1,
      ),
    );

    final freshHit = await durableCache.get(previewUri, _FakeSdkClient());
    expect(freshHit?.data.title, 'Stored TikTok preview');
    expect(freshHit?.data.image, isA<NetworkImage>());
    expect(freshHit?.data.imageUri, thumbnailUri);
    expect(freshHit?.data.volatileImageOmitted, isTrue);

    now = now.add(const Duration(hours: 2));

    final expiredHit = await durableCache.get(previewUri, _FakeSdkClient());
    expect(expiredHit?.data.title, 'Stored TikTok preview');
    expect(expiredHit?.data.image, isNull);
    expect(expiredHit?.data.imageUri, isNull);
    expect(expiredHit?.data.volatileImageOmitted, isTrue);
  });

  test('transient signed thumbnails with token queries are not persisted',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final durableCache = UrlPreviewDurableCache(
      preferences: prefs,
      prefix: 'url-preview-volatile-secret-image-test',
    );
    final previewUri =
        Uri.parse('https://www.tiktok.com/@demo/video/1234567890');
    final thumbnailUri = Uri.parse(
      'https://p16-sign-va.tiktokcdn.com/obj/tos-maliva-p-0068/demo.jpeg'
      '?x-expires=1893456000'
      '&x-signature=public-cdn-signature'
      '&access_token=super-secret',
    );

    await durableCache.put(
      previewUri,
      UrlPreviewData(
        previewUri,
        title: 'Stored TikTok preview',
        image: NetworkImage(thumbnailUri.toString()),
        imageUri: thumbnailUri,
      ),
    );

    final hit = await durableCache.get(previewUri, _FakeSdkClient());

    expect(hit?.data.title, 'Stored TikTok preview');
    expect(hit?.data.image, isNull);
    expect(hit?.data.imageUri, isNull);
    expect(hit?.data.volatileImageOmitted, isTrue);
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
  DateTime get originServerTs => DateTime(2026, 6, 15);

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
