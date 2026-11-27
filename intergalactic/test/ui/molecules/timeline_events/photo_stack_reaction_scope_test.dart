import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/cache/file_provider.dart';
import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/client/permissions.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_feature_reactions.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/atoms/emoji_reaction.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_attachments.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_message.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_reactions.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner report, 2026-09-05, with a screenshot of a two-photo stack: a reaction
/// left on the stack as a whole was drawn twice - once as the message's own
/// reaction row under the stack, and again as the numbered chip for photo 2.
///
/// The cause is structural rather than a drawing mistake. A stack of N photos
/// offers N+1 reaction scopes, a Matrix reaction can only target a real event,
/// and the stack has no event of its own - so the whole-stack scope is stored
/// on the stack's ANCHOR event, which is also its last photo. Both surfaces
/// then rendered the same event, one calling it the stack and one calling it
/// photo N.
///
/// The fix keeps one chip per scope: the anchor is labelled "All", it is
/// dropped from the numbered chips, and the message's own reaction row is
/// suppressed while the stack is on screen.
///
/// The alias itself survives and is deliberate: reacting to the last photo in
/// the focus view is still, at the protocol level, reacting to the stack, which
/// is why the focused view labels that photo's reactions "All" rather than
/// pretending they are photo-local.
const _reactorId = '@second:example.org';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.layoutOverride.set('desktop');
  });

  group('photoStackReactionChipOrder', () {
    // These drive the ordering as a pure function of an explicit scope id
    // rather than through a pumped widget, so every shape below is reachable
    // without building a timeline that happens to anchor the way we want.
    test('the stack scope leads the row and is labelled All', () {
      final items = _items(reacted: const {0, 1});
      final specs = photoStackReactionChipOrder(
        items: items,
        timeline: _FakeTimeline(events: items.map((i) => i.event).toList()),
        scopeEventId: items.last.event.eventId,
      );

      expect(specs.map((spec) => spec.label), [photoStackAllScopeLabel, '1']);
    });

    test('the scope event is never also drawn as a numbered photo', () {
      final items = _items(reacted: const {0, 1});
      final specs = photoStackReactionChipOrder(
        items: items,
        timeline: _FakeTimeline(events: items.map((i) => i.event).toList()),
        scopeEventId: items.last.event.eventId,
      );

      expect(
        specs.map((spec) => spec.item.event.eventId).toList(),
        [items.last.event.eventId, items.first.event.eventId],
        reason:
            'the last photo is the scope event; drawing it again under the '
            'number 2 is the duplicate the owner reported',
      );
      expect(specs.map((spec) => spec.label), isNot(contains('2')));
    });

    test('numbers follow the photo position, not the chip position', () {
      // Photo 2 of 3 is the only numbered photo with reactions. Numbering the
      // chips as they are emitted would call it 1 and point at the wrong photo.
      final items = _items(count: 3, reacted: const {1, 2});
      final specs = photoStackReactionChipOrder(
        items: items,
        timeline: _FakeTimeline(events: items.map((i) => i.event).toList()),
        scopeEventId: items.last.event.eventId,
      );

      expect(specs.map((spec) => spec.label), [photoStackAllScopeLabel, '2']);
    });

    test('photos with no reactions produce no chip', () {
      final items = _items(count: 3, reacted: const {0});
      final specs = photoStackReactionChipOrder(
        items: items,
        timeline: _FakeTimeline(events: items.map((i) => i.event).toList()),
        scopeEventId: items.last.event.eventId,
      );

      expect(specs.map((spec) => spec.label), ['1']);
    });

    test('with no scope event every photo keeps its number', () {
      // The photo album opens the same lightbox with no anchor event standing
      // in for the stack, so "All" must not appear there.
      final items = _items(count: 2, reacted: const {0, 1});
      final specs = photoStackReactionChipOrder(
        items: items,
        timeline: _FakeTimeline(events: items.map((i) => i.event).toList()),
        scopeEventId: null,
      );

      expect(specs.map((spec) => spec.label), ['1', '2']);
    });
  });

  group('the stack in the timeline', () {
    testWidgets('draws the stack reaction once, as All', (tester) async {
      // events[0] is the newest, and _resolvePhotoStack anchors on it while
      // ordering the photos oldest-first - so the anchor is photo 2 of 2, which
      // is exactly the collision in the owner's screenshot.
      final timeline = _timelineWithStack(
        anchorReactions: {
          const _FakeEmoticon(shortcode: 'joy', key: '\u{1F602}'): 3,
        },
        firstPhotoReactions: {const _FakeEmoticon(): 3},
      );

      await tester.pumpWidget(_subject(timeline));
      await tester.pump();

      expect(find.byType(PhotoStackAttachmentView), findsOneWidget);
      expect(find.text(photoStackAllScopeLabel), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(
        find.text('2'),
        findsNothing,
        reason:
            'the anchor event is the stack scope; numbering it as photo 2 is '
            'the mislabelled half of the duplicate',
      );
      expect(
        find.byType(EmojiReaction),
        findsNWidgets(2),
        reason:
            'one chip per scope. A third means the message row is still '
            'printing the anchor event underneath the stack',
      );
    });

    testWidgets('a stack with only whole-stack reactions shows just All', (
      tester,
    ) async {
      final timeline = _timelineWithStack(
        anchorReactions: {const _FakeEmoticon(): 3},
        firstPhotoReactions: const {},
      );

      await tester.pumpWidget(_subject(timeline));
      await tester.pump();

      expect(find.text(photoStackAllScopeLabel), findsOneWidget);
      expect(find.byType(EmojiReaction), findsOneWidget);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('an unstacked image keeps its ordinary reaction row', (
      tester,
    ) async {
      // The suppression is scoped to the stack. A lone image is not a stack, so
      // removing its reaction row would be a regression rather than a fix.
      final lone = _FakeStackPhotoEvent(
        eventId: r'$only',
        originServerTs: DateTime.utc(2026, 9, 5, 12),
        attachmentName: 'only.png',
        reactions: {const _FakeEmoticon(): 3},
      );
      final timeline = _FakeTimeline(events: [lone]);

      await tester.pumpWidget(_subject(timeline));
      await tester.pump();

      expect(find.byType(PhotoStackAttachmentView), findsNothing);
      expect(find.byType(EmojiReaction), findsOneWidget);
      expect(find.text(photoStackAllScopeLabel), findsNothing);
    });
  });

  group('the focused photo', () {
    testWidgets('shows the reactions of the photo being viewed', (
      tester,
    ) async {
      final timeline = _timelineWithStack(
        anchorReactions: const {},
        firstPhotoReactions: {const _FakeEmoticon(): 3},
      );
      final items = _itemsFromTimeline(timeline);

      await tester.pumpWidget(
        _focusSubject(item: items.first, timeline: timeline, scope: null),
      );
      await tester.pump();

      expect(find.byType(EmojiReaction), findsOneWidget);
      expect(
        find.text(photoStackAllScopeLabel),
        findsNothing,
        reason: 'photo 1 is not the stack scope',
      );
    });

    testWidgets(
      'labels the scope photo All rather than pretending it is local',
      (tester) async {
        final timeline = _timelineWithStack(
          anchorReactions: {const _FakeEmoticon(): 3},
          firstPhotoReactions: const {},
        );
        final items = _itemsFromTimeline(timeline);
        final anchor = items.last;

        await tester.pumpWidget(
          _focusSubject(
            item: anchor,
            timeline: timeline,
            scope: anchor.event.eventId,
          ),
        );
        await tester.pump();

        expect(find.byType(EmojiReaction), findsOneWidget);
        expect(find.text(photoStackAllScopeLabel), findsOneWidget);
      },
    );

    testWidgets('a photo with no reactions renders nothing at all', (
      tester,
    ) async {
      final timeline = _timelineWithStack(
        anchorReactions: const {},
        firstPhotoReactions: const {},
      );
      final items = _itemsFromTimeline(timeline);

      await tester.pumpWidget(
        _focusSubject(item: items.first, timeline: timeline, scope: null),
      );
      await tester.pump();

      expect(find.byType(TimelineEventViewReactions), findsNothing);
    });

    testWidgets('picks up a reaction that lands while the lightbox is open', (
      tester,
    ) async {
      // The lightbox is a route ABOVE the timeline, so nothing rebuilds it when
      // a reaction arrives - including the one the viewer just added from the
      // focused-media React button. Without its own subscription the chip
      // simply never appears.
      final timeline = _timelineWithStack(
        anchorReactions: const {},
        firstPhotoReactions: const {},
      );
      final items = _itemsFromTimeline(timeline);
      final photo = items.first.event as _FakeStackPhotoEvent;

      await tester.pumpWidget(
        _focusSubject(item: items.first, timeline: timeline, scope: null),
      );
      await tester.pump();
      expect(find.byType(EmojiReaction), findsNothing);

      photo.reactions[const _FakeEmoticon()] = 3;
      timeline.notifyChanged(
        timeline.events.indexWhere((event) => event.eventId == photo.eventId),
      );
      await tester.pump();

      expect(
        find.byType(EmojiReaction),
        findsOneWidget,
        reason:
            'the focused view is not listening to the timeline, so a reaction '
            'added from the lightbox never shows up in it',
      );
    });

    testWidgets('survives the event being removed from the timeline', (
      tester,
    ) async {
      // Redaction while the lightbox is open. The item holds an index captured
      // when the stack was resolved; using it blindly reads a neighbour or
      // throws.
      final timeline = _timelineWithStack(
        anchorReactions: const {},
        firstPhotoReactions: {const _FakeEmoticon(): 3},
      );
      final items = _itemsFromTimeline(timeline);

      await tester.pumpWidget(
        _focusSubject(item: items.first, timeline: timeline, scope: null),
      );
      await tester.pump();
      expect(find.byType(EmojiReaction), findsOneWidget);

      timeline.removeEvent(items.first.event.eventId);
      await tester.pump();

      expect(find.byType(EmojiReaction), findsNothing);
    });
  });
}

Widget _subject(_FakeTimeline timeline) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: 800,
      child: TimelineEventViewMessage(timeline: timeline, index: 0),
    ),
  ),
);

Widget _focusSubject({
  required PhotoStackAttachmentItem item,
  required _FakeTimeline timeline,
  required String? scope,
}) => MaterialApp(
  home: Scaffold(
    body: PhotoStackFocusedReactions(
      item: item,
      timeline: timeline,
      scopeEventId: scope,
    ),
  ),
);

/// A two-photo stack shaped like the owner's screenshot: the newest event, at
/// index 0, is the anchor and therefore photo 2.
_FakeTimeline _timelineWithStack({
  required Map<Emoticon, int> anchorReactions,
  required Map<Emoticon, int> firstPhotoReactions,
}) {
  final baseTime = DateTime.utc(2026, 9, 5, 12);
  return _FakeTimeline(
    events: [
      _FakeStackPhotoEvent(
        eventId: r'$photo-2',
        originServerTs: baseTime.add(const Duration(seconds: 20)),
        attachmentName: 'second.png',
        reactions: Map.of(anchorReactions),
      ),
      _FakeStackPhotoEvent(
        eventId: r'$photo-1',
        originServerTs: baseTime,
        attachmentName: 'first.png',
        reactions: Map.of(firstPhotoReactions),
      ),
    ],
  );
}

/// Oldest first, matching the order the stack resolver produces.
List<PhotoStackAttachmentItem> _itemsFromTimeline(_FakeTimeline timeline) {
  final ordered = timeline.events.reversed.toList(growable: false);
  return [
    for (final event in ordered.cast<_FakeStackPhotoEvent>())
      PhotoStackAttachmentItem(
        event: event,
        index: timeline.events.indexOf(event),
        attachment: event.attachments!.single as ImageAttachment,
      ),
  ];
}

List<PhotoStackAttachmentItem> _items({
  int count = 2,
  Set<int> reacted = const {},
}) {
  final baseTime = DateTime.utc(2026, 9, 5, 12);
  return [
    for (var i = 0; i < count; i++)
      () {
        final event = _FakeStackPhotoEvent(
          eventId: '\$photo-$i',
          originServerTs: baseTime.add(Duration(seconds: i * 10)),
          attachmentName: 'photo-$i.png',
          reactions: reacted.contains(i) ? {const _FakeEmoticon(): 3} : {},
        );
        return PhotoStackAttachmentItem(
          event: event,
          index: i,
          attachment: event.attachments!.single as ImageAttachment,
        );
      }(),
  ];
}

class _FakeStackPhotoEvent
    implements TimelineEventMessage, TimelineEventFeatureReactions {
  _FakeStackPhotoEvent({
    required this.eventId,
    required this.originServerTs,
    required String attachmentName,
    required this.reactions,
  }) : _attachmentName = attachmentName;

  final String _attachmentName;

  /// Emoticon to reactor count. Mutable so a test can land a reaction while a
  /// widget is on screen.
  final Map<Emoticon, int> reactions;

  @override
  final String eventId;

  @override
  final DateTime originServerTs;

  @override
  String get senderId => '@alice:example.org';

  @override
  TimelineEventStatus get status => TimelineEventStatus.synced;

  @override
  String get plainTextBody => _attachmentName;

  @override
  String get source => '{}';

  @override
  bool get editable => false;

  @override
  String? get body => _attachmentName;

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

  @override
  bool hasReactions(Timeline timeline) => reactions.isNotEmpty;

  /// A snapshot, like the real implementation. Handing out the live map lets a
  /// stale view mutate underneath itself and pass against its own defect.
  @override
  Map<Emoticon, Set<String>> getReactions(Timeline timeline) => {
    for (final entry in reactions.entries)
      entry.key: {for (var i = 0; i < entry.value; i++) '$_reactorId-$i'},
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeEmoticon implements Emoticon {
  const _FakeEmoticon({this.shortcode = 'thumbsup', this.key = '\u{1F44D}'});

  @override
  ImageProvider? get image => null;

  @override
  String get slug => shortcode;

  @override
  final String shortcode;

  @override
  final String key;

  @override
  EmoticonUsage get usage => EmoticonUsage.emoji;

  @override
  bool get isSticker => false;

  @override
  bool get isEmoji => true;

  @override
  bool operator ==(Object other) =>
      other is _FakeEmoticon &&
      other.key == key &&
      other.shortcode == shortcode;

  @override
  int get hashCode => Object.hash(key, shortcode);
}

class _FakeTimeline extends Timeline {
  _FakeTimeline({required List<TimelineEvent> events}) {
    room = _FakeRoom(client: _FakeClient('@self:example.org'));
    client = room.client;
    this.events = List<TimelineEvent>.of(events);
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
  Future<void> loadMoreHistory() async {}

  @override
  void markAsRead(TimelineEvent event) {}
}

class _FakeRoom implements Room {
  _FakeRoom({required this.client});

  @override
  final Client client;

  @override
  String get identifier => '!room:example.org';

  @override
  String get localId => '${client.identifier}:$identifier';

  @override
  bool get shouldPreviewMedia => false;

  @override
  Stream<void> get onUpdate => const Stream<void>.empty();

  @override
  Permissions get permissions => _FakePermissions();

  @override
  Member getMemberOrFallback(String id) => _FakeMember(id);

  @override
  T? getComponent<T extends RoomComponent>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePermissions extends Permissions {}

class _FakeClient implements Client {
  _FakeClient(String selfId) : self = _FakeProfile(selfId);

  @override
  final Profile self;

  @override
  String get identifier => 'client-${self.identifier}';

  @override
  bool get supportsE2EE => true;

  @override
  T? getComponent<T extends Component>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfile implements Profile {
  const _FakeProfile(this.identifier);

  @override
  final String identifier;

  @override
  String get displayName => identifier;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMember implements Member {
  _FakeMember(this.identifier);

  @override
  final String identifier;

  @override
  String get displayName => identifier;

  @override
  String get userName => identifier;

  @override
  ImageProvider? get avatar => null;

  @override
  Color get defaultColor => Colors.blue;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);
