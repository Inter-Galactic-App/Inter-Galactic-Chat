import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/cache/file_provider.dart';
import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/client/permissions.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/molecules/room_timeline_widget/room_timeline_widget_view.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_attachments.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_message.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.layoutOverride.set('desktop');
  });

  testWidgets('keeps history loader visible during decrypt recovery', (
    tester,
  ) async {
    final timeline = _FakeTimeline(
      room: _FakeRoom(identifier: '!room:example.org', client: _FakeClient()),
    );
    final viewKey = GlobalKey<RoomTimelineWidgetViewState>();
    final recoveryCompleter = Completer<bool>();
    var recoveryCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 500,
            child: RoomTimelineWidgetView(
              key: viewKey,
              timeline: timeline,
              onHistoryPageLoaded: (_) {
                recoveryCalls++;
                return recoveryCompleter.future;
              },
            ),
          ),
        ),
      ),
    );

    final loadFuture = viewKey.currentState!.loadMoreHistory();
    await tester.pump();

    expect(timeline.loadMoreHistoryCount, 1);
    expect(recoveryCalls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    recoveryCompleter.complete(true);
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(
      RoomTimelineWidgetViewState.historyDecryptRecoveryMinLoaderDuration,
    );
    await loadFuture;
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
    'runs history recovery against the timeline that loaded history',
    (tester) async {
      final loadMoreCompleter = Completer<void>();
      final timelineA = _FakeTimeline(
        room: _FakeRoom(
          identifier: '!room-a:example.org',
          client: _FakeClient(),
        ),
        loadMoreHistoryCompleter: loadMoreCompleter,
      );
      final timelineB = _FakeTimeline(
        room: _FakeRoom(
          identifier: '!room-b:example.org',
          client: _FakeClient(),
        ),
      );
      final viewKey = GlobalKey<RoomTimelineWidgetViewState>();
      final recoveryTimelines = <Timeline>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 500,
              child: RoomTimelineWidgetView(
                key: viewKey,
                timeline: timelineA,
                onHistoryPageLoaded: (timeline) async {
                  recoveryTimelines.add(timeline);
                  return false;
                },
              ),
            ),
          ),
        ),
      );

      final loadFuture = viewKey.currentState!.loadMoreHistory();
      await tester.pump();
      viewKey.currentState!.initFromTimeline(timelineB);
      loadMoreCompleter.complete();
      await loadFuture;

      expect(recoveryTimelines, [same(timelineA)]);
    },
  );

  testWidgets(
    'renders image stack grouping when room media previews are disabled',
    (tester) async {
      final room = _FakeRoom(
        identifier: '!room:example.org',
        client: _FakeClient(),
      );
      final timeline = _FakeTimeline(room: room);
      final baseTime = DateTime.utc(2026, 7, 5, 12);
      timeline.events = [
        _FakeImageMessageEvent(
          eventId: r'$image-2',
          senderId: '@alice:example.org',
          originServerTs: baseTime.add(const Duration(seconds: 20)),
          attachmentName: 'second.png',
        ),
        _FakeImageMessageEvent(
          eventId: r'$image-1',
          senderId: '@alice:example.org',
          originServerTs: baseTime,
          attachmentName: 'first.png',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: TimelineEventViewMessage(
                timeline: timeline,
                initialIndex: 0,
                previewMedia: room.shouldPreviewMedia,
              ),
            ),
          ),
        ),
      );

      expect(room.shouldPreviewMedia, isFalse);
      expect(find.byType(PhotoStackAttachmentView), findsOneWidget);
      expect(find.text('2 photos'), findsOneWidget);
      expect(find.byIcon(Icons.image_not_supported_outlined), findsWidgets);
      expect(find.byType(Image), findsNothing);
    },
  );

  testWidgets('renders image stack grouping for generated image bodies', (
    tester,
  ) async {
    final room = _FakeRoom(
      identifier: '!room:example.org',
      client: _FakeClient(),
    );
    final timeline = _FakeTimeline(room: room);
    final baseTime = DateTime.utc(2026, 7, 5, 12);
    timeline.events = [
      _FakeImageMessageEvent(
        eventId: r'$image-2',
        senderId: '@alice:example.org',
        originServerTs: baseTime.add(const Duration(seconds: 20)),
        attachmentName: 'processed-second.png',
        body: 'second.png',
      ),
      _FakeImageMessageEvent(
        eventId: r'$image-1',
        senderId: '@alice:example.org',
        originServerTs: baseTime,
        attachmentName: 'processed-first.png',
        body: 'first.png',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: TimelineEventViewMessage(
              timeline: timeline,
              initialIndex: 0,
              previewMedia: true,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(PhotoStackAttachmentView), findsOneWidget);
    expect(find.text('2 photos'), findsOneWidget);
  });

  testWidgets('keeps captioned image messages out of image stack grouping', (
    tester,
  ) async {
    final room = _FakeRoom(
      identifier: '!room:example.org',
      client: _FakeClient(),
    );
    final timeline = _FakeTimeline(room: room);
    final baseTime = DateTime.utc(2026, 7, 5, 12);
    timeline.events = [
      _FakeImageMessageEvent(
        eventId: r'$image-2',
        senderId: '@alice:example.org',
        originServerTs: baseTime.add(const Duration(seconds: 20)),
        attachmentName: 'second.png',
        body: 'second caption',
      ),
      _FakeImageMessageEvent(
        eventId: r'$image-1',
        senderId: '@alice:example.org',
        originServerTs: baseTime,
        attachmentName: 'first.png',
        body: 'first caption',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: TimelineEventViewMessage(
              timeline: timeline,
              initialIndex: 0,
              previewMedia: true,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(PhotoStackAttachmentView), findsNothing);
    expect(find.text('2 photos'), findsNothing);
  });
}

class _FakeClient implements Client {
  @override
  Profile? self = const _FakeProfile('@self:example.org');

  @override
  String get identifier => 'fake-client';

  @override
  bool get supportsE2EE => true;

  @override
  T? getComponent<T extends Component>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRoom implements Room {
  _FakeRoom({required this.identifier, required this.client});

  @override
  final String identifier;

  @override
  final Client client;

  @override
  String get localId => '${client.identifier}:$identifier';

  @override
  bool get shouldPreviewMedia => false;

  @override
  Stream<void> get onUpdate => const Stream<void>.empty();

  @override
  Permissions get permissions => _FakePermissions();

  @override
  T? getComponent<T extends RoomComponent>() => null;

  @override
  Member getMemberOrFallback(String id) => _FakeMember(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePermissions extends Permissions {}

class _FakeTimeline extends Timeline {
  _FakeTimeline({required Room room, this.loadMoreHistoryCompleter}) {
    this.room = room;
    client = room.client;
    events = List<TimelineEvent>.empty(growable: true);
  }

  int loadMoreHistoryCount = 0;
  final Completer<void>? loadMoreHistoryCompleter;

  @override
  bool get canLoadFuture => false;

  @override
  bool get canLoadHistory => loadMoreHistoryCount == 0;

  @override
  bool get isLoadingFuture => false;

  @override
  bool get isLoadingHistory => false;

  @override
  Stream<void> get onLoadingStatusChanged => const Stream<void>.empty();

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
  Future<void> loadMoreHistory() async {
    loadMoreHistoryCount++;
    await loadMoreHistoryCompleter?.future;
  }

  @override
  void markAsRead(TimelineEvent event) {}
}

class _FakeMember implements Member {
  const _FakeMember(this.identifier);

  @override
  final String identifier;

  @override
  String get userName => identifier;

  @override
  String get displayName => 'Alice';

  @override
  String? get detail => null;

  @override
  String? get avatarId => null;

  @override
  ImageProvider? get avatar => null;

  @override
  Color get defaultColor => Colors.teal;
}

class _FakeProfile implements Profile {
  const _FakeProfile(this.identifier);

  @override
  final String identifier;

  @override
  String get userName => identifier;

  @override
  String get displayName => 'Self';

  @override
  String? get detail => null;

  @override
  ImageProvider? get avatar => null;

  @override
  ImageProvider? get banner => null;

  @override
  Color get defaultColor => Colors.blue;

  @override
  String get source => '{}';
}

class _FakeImageMessageEvent implements TimelineEventMessage {
  _FakeImageMessageEvent({
    required this.eventId,
    required this.senderId,
    required this.originServerTs,
    required String attachmentName,
    String? body,
  }) : _attachmentName = attachmentName,
       _body = body ?? attachmentName;

  final String _attachmentName;
  final String _body;

  @override
  final String eventId;

  @override
  final String senderId;

  @override
  final DateTime originServerTs;

  @override
  TimelineEventStatus get status => TimelineEventStatus.synced;

  @override
  String get plainTextBody => _body;

  @override
  String get source => '{}';

  @override
  bool get editable => false;

  @override
  String? get body => _body;

  @override
  String? get bodyFormat => null;

  @override
  String? get formattedBody => null;

  @override
  List<Attachment>? get attachments => [
    ImageAttachment(
      MemoryImage(_transparentPng),
      _FakeFileProvider(_attachmentName),
      name: _attachmentName,
      mimeType: 'image/png',
      fileSize: _transparentPng.length,
      width: 1,
      height: 1,
    ),
  ];

  @override
  Widget? buildFormattedContent({Timeline? timeline}) => null;

  @override
  String getPlaintextBody(Timeline timeline) => plainTextBody;

  @override
  bool isEdited(Timeline timeline) => false;

  @override
  List<Uri>? getLinks({Timeline? timeline}) => const [];
}

class _FakeFileProvider implements FileProvider {
  const _FakeFileProvider(this.fileIdentifier);

  @override
  final String fileIdentifier;

  @override
  Stream<DownloadProgress>? get onProgressChanged => null;

  @override
  Future<Uint8List?> getFileData() async => _transparentPng;

  @override
  Future<Uri?> resolve() async => Uri.parse('memory:$fileIdentifier');

  @override
  Future<void> save(String filepath) async {}
}

final _transparentPng = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
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
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);
