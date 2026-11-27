import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:commet_calendar_widget/calendar.dart' as calendar_widget;
import 'package:commet_calendar_widget/rfc8984.dart' as rfc8984;
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intergalactic/cache/file_provider.dart';
import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/auth.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/calendar_room/calendar_room_component.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_component.dart';
import 'package:intergalactic/client/components/emoticon_recent/recent_emoticon_component.dart';
import 'package:intergalactic/client/components/forum_room/forum_room_component.dart';
import 'package:intergalactic/client/components/photo_album_room/photo.dart';
import 'package:intergalactic/client/components/photo_album_room/photo_album_entry.dart';
import 'package:intergalactic/client/components/photo_album_room/photo_album_room_component.dart';
import 'package:intergalactic/client/components/photo_album_room/photo_album_timeline.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/read_receipts/read_receipt_component.dart';
import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/client/components/space_banner/space_banner_component.dart';
import 'package:intergalactic/client/components/space_component.dart';
import 'package:intergalactic/client/components/stories/story_component.dart';
import 'package:intergalactic/client/components/threads/thread_component.dart';
import 'package:intergalactic/client/components/typing_indicators/typing_indicator_component.dart';
import 'package:intergalactic/client/components/user_presence/user_presence_component.dart';
import 'package:intergalactic/client/components/voip/share_session/share_session.dart';
import 'package:intergalactic/client/components/voip/voip_call_diagnostics.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/components/voip_room/voip_room_component.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/client/permissions.dart';
import 'package:intergalactic/client/role.dart';
import 'package:intergalactic/client/room_preview.dart';
import 'package:intergalactic/client/space_child.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_encrypted.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_feature_reactions.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_feature_related.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/utils/stored_stream_controller.dart';
import 'package:intergalactic/utils/emoji/unicode_emoji.dart';
import 'package:matrix_widget_api/matrix_widget_api.dart';

class DemoClient extends Client {
  DemoClient._() {
    self = _DemoPerson(
      identifier: '@demo:intergalactic.local',
      userName: 'demo',
      displayName: 'Inter Galactic Demo',
      detail: 'Offline demo account',
      defaultColor: const Color(0xFF2FB5FF),
      avatarAsset: demoAvatarSelf,
    );

    _people.addAll([
      self! as _DemoPerson,
      _DemoPerson(
        identifier: '@mira:intergalactic.local',
        userName: 'mira',
        displayName: 'Mira',
        detail: 'Guild lead',
        defaultColor: const Color(0xFFFF9F1C),
        avatarAsset: demoAvatarMira,
      ),
      _DemoPerson(
        identifier: '@theo:intergalactic.local',
        userName: 'theo',
        displayName: 'Theo',
        detail: 'Voice chat regular',
        defaultColor: const Color(0xFF7CFFB2),
        avatarAsset: demoAvatarTheo,
      ),
      _DemoPerson(
        identifier: '@nova:intergalactic.local',
        userName: 'nova',
        displayName: 'Nova',
        detail: 'Calendar coordinator',
        defaultColor: const Color(0xFFE86AFF),
        avatarAsset: demoAvatarNova,
      ),
      _DemoPerson(
        identifier: '@iris:intergalactic.local',
        userName: 'iris',
        displayName: 'Iris',
        detail: 'Forum moderator',
        defaultColor: const Color(0xFFFF6B6B),
        avatarAsset: demoAvatarIris,
      ),
    ]);

    _components.addAll([
      DemoProfileComponent(this),
      DemoUserPresenceComponent(this),
      DemoDirectMessagesComponent(this),
      DemoStoryComponent(this),
      DemoEmoticonComponent(this),
      DemoRecentEmoticonComponent(this),
      DemoThreadsComponent(this),
    ]);

    _seedDemoData();
  }

  static DemoClient createOfflineDemo() => DemoClient._();

  static DemoClient createAppleReviewDemo() => createOfflineDemo();

  static const demoIdentifier = 'offline-demo:intergalactic';
  static const demoSpaceId = '!demo-space:intergalactic.local';
  static const demoLoungeRoomId = '!demo-lounge:intergalactic.local';
  static const demoForumRoomId = '!demo-forum:intergalactic.local';
  static const demoVoiceRoomId = '!demo-call:intergalactic.local';
  static const demoCalendarRoomId = '!demo-calendar:intergalactic.local';
  static const demoPhotoAlbumRoomId = '!demo-photos:intergalactic.local';
  static const demoPhotoStackRootEventId = r'$demo-photo-stack-1';
  static const demoEncryptedRoomId = '!demo-encryption:intergalactic.local';
  static const demoMiraDmRoomId = '!demo-dm-mira:intergalactic.local';

  /// Bundled NASA Goddard demo imagery (public domain) used in place of the
  /// placeholder icons offline demo mode would otherwise show. See
  /// assets/images/placeholders/demo/CREDITS.md.
  static const _demoAssetDir = 'assets/images/placeholders/demo';
  static const demoAvatarSelf = '$_demoAssetDir/avatar-demo.jpg';
  static const demoAvatarMira = '$_demoAssetDir/avatar-mira.jpg';
  static const demoAvatarTheo = '$_demoAssetDir/avatar-theo.jpg';
  static const demoAvatarNova = '$_demoAssetDir/avatar-nova.jpg';
  static const demoAvatarIris = '$_demoAssetDir/avatar-iris.jpg';
  static const demoSpaceIcon = '$_demoAssetDir/space-icon.jpg';
  static const demoSpaceBanner = '$_demoAssetDir/space-banner.jpg';
  static const demoRoomLounge = '$_demoAssetDir/room-lounge.jpg';
  static const demoRoomForum = '$_demoAssetDir/room-feedback-forum.jpg';
  static const demoRoomVault = '$_demoAssetDir/room-memory-vault.jpg';
  static const demoRoomVoice = '$_demoAssetDir/room-game-night-voice.jpg';
  static const demoRoomCalendar = '$_demoAssetDir/room-guild-calendar.jpg';
  static const demoRoomEncrypted = '$_demoAssetDir/room-encrypted-lab.jpg';
  static const demoStoryMira = '$_demoAssetDir/story-mira.jpg';

  final List<DemoRoom> _rooms = [];
  final List<DemoSpace> _spaces = [];
  final List<_DemoPerson> _people = [];
  final List<Component> _components = [];
  final StreamController<int> _onRoomAdded = StreamController.broadcast();
  final StreamController<int> _onSpaceAdded = StreamController.broadcast();
  final StreamController<int> _onRoomRemoved = StreamController.broadcast();
  final StreamController<int> _onSpaceRemoved = StreamController.broadcast();
  final StreamController<int> _onPeerAdded = StreamController.broadcast();
  final StreamController<void> _onSync = StreamController.broadcast();
  final StreamController<void> _onSelfUpdated = StreamController.broadcast();
  final StoredStreamController<ClientConnectionStatusUpdate> _connectionStatus =
      StoredStreamController(
        ClientConnectionStatusUpdate(ClientConnectionStatus.connected),
      );

  bool _loggedIn = true;

  @override
  String get identifier => demoIdentifier;

  @override
  bool get supportsE2EE => _rooms.any((room) => room.isE2EE);

  @override
  int? get maxFileSize => null;

  @override
  List<Room> get singleRooms => const [];

  @override
  List<Room> get rooms => _rooms;

  @override
  List<Space> get spaces => _spaces;

  @override
  List<Peer> get peers => _people;

  @override
  Stream<int> get onRoomAdded => _onRoomAdded.stream;

  @override
  Stream<int> get onSpaceAdded => _onSpaceAdded.stream;

  @override
  Stream<int> get onRoomRemoved => _onRoomRemoved.stream;

  @override
  Stream<int> get onSpaceRemoved => _onSpaceRemoved.stream;

  @override
  Stream<int> get onPeerAdded => _onPeerAdded.stream;

  @override
  Stream<void> get onSync => _onSync.stream;

  @override
  Stream<void> get onSelfUpdated => _onSelfUpdated.stream;

  @override
  StoredStreamController<ClientConnectionStatusUpdate>
  get connectionStatusChanged => _connectionStatus;

  @override
  Future<void> init(
    bool loadingFromCache, {
    bool isBackgroundService = false,
  }) async {
    _connectionStatus.add(
      ClientConnectionStatusUpdate(ClientConnectionStatus.connected),
    );
  }

  @override
  Future<(bool, List<LoginFlow>?)> setHomeserver(Uri uri) async =>
      (false, null);

  @override
  Future<LoginResult> executeLoginFlow(LoginFlow flow) async =>
      LoginResultError('Offline demo mode does not connect to a homeserver.');

  @override
  Future<LoginResult> registerAccount({
    required String username,
    required String password,
    String? registrationToken,
    String? registrationSession,
  }) async =>
      LoginResultError('Offline demo mode cannot create server accounts.');

  @override
  Future<void> logout() async {
    _loggedIn = false;
  }

  @override
  bool isLoggedIn() => _loggedIn;

  @override
  bool hasSpace(String identifier) => getSpace(identifier) != null;

  @override
  bool hasRoom(String identifier) => getRoom(identifier) != null;

  @override
  bool hasPeer(String identifier) =>
      _people.any((peer) => peer.identifier == identifier);

  @override
  Room? getRoom(String identifier) =>
      _rooms.where((room) => room.identifier == identifier).firstOrNull;

  @override
  Room? getRoomByAlias(String identifier) => getRoom(identifier);

  @override
  Space? getSpace(String identifier) =>
      _spaces.where((space) => space.identifier == identifier).firstOrNull;

  @override
  Future<Room> createRoom(CreateRoomArgs args) async {
    final room = DemoRoom(
      client: this,
      identifier:
          '!demo-created-${DateTime.now().microsecondsSinceEpoch}:intergalactic.local',
      displayName: args.name ?? 'Demo Room',
      topic: args.topic,
      memberIds: _people.map((person) => person.identifier).toList(),
      roomType: args.roomType,
    );
    _addRoom(room);
    return room;
  }

  @override
  Future<Space> createSpace(CreateRoomArgs args) async {
    final space = DemoSpace(
      client: this,
      identifier:
          '!demo-space-${DateTime.now().microsecondsSinceEpoch}:intergalactic.local',
      displayName: args.name ?? 'Demo Space',
      topic: args.topic ?? 'A local-only demo space.',
      color: const Color(0xFF2FB5FF),
    );
    _addSpace(space);
    return space;
  }

  @override
  Future<Space> joinSpace(String address) =>
      throw UnsupportedError('Offline demo mode cannot join remote spaces.');

  @override
  Future<Room> joinRoom(String address) =>
      throw UnsupportedError('Offline demo mode cannot join remote rooms.');

  @override
  Future<RoomPreviewJoinResult> joinRoomFromPreview(RoomPreview preview) =>
      throw UnsupportedError('Offline demo mode cannot join remote previews.');

  @override
  Future<void> leaveRoom(Room room) async {
    final index = _rooms.indexWhere((entry) => entry == room);
    if (index < 0) return;
    for (final space in List<DemoSpace>.from(_spaces)) {
      await space.detachRoom(room);
    }
    _rooms.removeAt(index);
    getComponent<DemoDirectMessagesComponent>()?.removeDirectMessageRoom(room);
    _onRoomRemoved.add(index);
    _onSync.add(null);
  }

  @override
  Future<void> leaveSpace(Space space) async {
    final index = _spaces.indexWhere((entry) => entry == space);
    if (index < 0) return;
    _spaces.removeAt(index);
    _onSpaceRemoved.add(index);
    _onSync.add(null);
  }

  @override
  Future<RoomPreview?> getSpacePreview(String address) async => null;

  @override
  Future<RoomPreview?> getRoomPreview(String address) async => null;

  @override
  Future<void> setAvatar(Uint8List bytes, String mimeType) async {}

  @override
  Future<void> setDisplayName(String name) async {
    final demoSelf = self;
    if (demoSelf is _DemoPerson) {
      demoSelf.displayName = name;
      _onSelfUpdated.add(null);
    }
  }

  @override
  Future<void> close() async {
    await Future.wait(_rooms.map((room) => room.close()));
    await Future.wait(_spaces.map((space) => space.close()));
    for (final component in _components) {
      if (component is DisposableComponent) {
        await (component as DisposableComponent).dispose();
      }
    }
    await _onRoomAdded.close();
    await _onSpaceAdded.close();
    await _onRoomRemoved.close();
    await _onSpaceRemoved.close();
    await _onPeerAdded.close();
    await _onSync.close();
    await _onSelfUpdated.close();
    await _connectionStatus.close();
  }

  @override
  Iterable<Room> getEligibleRoomsForSpace(Space space) {
    return _rooms.where((room) => !space.containsRoom(room.identifier));
  }

  @override
  Widget buildDebugInfo() {
    return const Text(
      'Offline Inter Galactic demo client. No homeserver, sync, push, or Matrix '
      'network calls are used.',
    );
  }

  @override
  T? getComponent<T extends Component>() {
    for (final component in _components) {
      if (component is T) return component;
    }
    return null;
  }

  @override
  List<T>? getAllComponents<T extends Component>() =>
      _components.whereType<T>().toList();

  _DemoPerson getPerson(String identifier) {
    return _people
            .where((person) => person.identifier == identifier)
            .firstOrNull ??
        _DemoPerson(
          identifier: identifier,
          userName: identifier.split(':').first.replaceFirst('@', ''),
          displayName: identifier.split(':').first.replaceFirst('@', ''),
          defaultColor: _colorFor(identifier),
        );
  }

  Color colorFor(String seed) => _colorFor(seed);

  void _addRoom(DemoRoom room) {
    _rooms.add(room);
    _onRoomAdded.add(_rooms.length - 1);
    _onSync.add(null);
  }

  void _addSpace(DemoSpace space) {
    _spaces.add(space);
    _onSpaceAdded.add(_spaces.length - 1);
    _onSync.add(null);
  }

  void _seedDemoData() {
    final allMemberIds = _people.map((person) => person.identifier).toList();
    final now = DateTime.now();

    final chat = DemoRoom(
      client: this,
      identifier: demoLoungeRoomId,
      displayName: 'lounge',
      topic: 'A friendly demo chat room with sample messages.',
      memberIds: allMemberIds,
      roomType: RoomType.defaultRoom,
      avatarAsset: demoRoomLounge,
    );
    chat.replaceTimeline(
      DemoTimeline(
        client: this,
        room: chat,
        initialEvents: [
          DemoTimelineMessage(
            eventId: r'$demo-lounge-5',
            senderId: self!.identifier,
            body:
                'Perfect. Reviewers can explore chat, forums, voice rooms, and calendar without a test homeserver.',
            originServerTs: now.subtract(const Duration(minutes: 4)),
          ),
          DemoTimelineMessage(
            eventId: r'$demo-lounge-4',
            senderId: '@nova:intergalactic.local',
            body:
                'I added a calendar event for tonight and a recurring campaign planning slot.',
            originServerTs: now.subtract(const Duration(minutes: 12)),
          ),
          DemoTimelineMessage(
            eventId: r'$demo-lounge-3',
            senderId: '@theo:intergalactic.local',
            body:
                'Voice room is staged too. No real call server is contacted in demo mode.',
            originServerTs: now.subtract(const Duration(minutes: 22)),
          ),
          DemoTimelineMessage(
            eventId: r'$demo-lounge-2',
            senderId: '@mira:intergalactic.local',
            body:
                'Forum tags are ready: announcements, feedback, session-notes, and bugs.',
            originServerTs: now.subtract(const Duration(minutes: 36)),
          ),
          DemoTimelineMessage(
            eventId: r'$demo-lounge-1',
            senderId: '@iris:intergalactic.local',
            body:
                'Welcome to the Inter Galactic review space. This whole account is local sample data.',
            originServerTs: now.subtract(const Duration(minutes: 48)),
          ),
        ],
      ),
    );

    final forum = DemoRoom(
      client: this,
      identifier: demoForumRoomId,
      displayName: 'feedback-forum',
      topic: 'Structured discussion using forum posts and tags.',
      memberIds: allMemberIds,
      roomType: RoomType.forum,
      avatarAsset: demoRoomForum,
    );
    final forumComponent = DemoForumRoomComponent(
      client: this,
      room: forum,
      availableTags: const [
        'announcements',
        'feedback',
        'session-notes',
        'bugs',
      ],
      initialPosts: [
        ForumPost(
          eventId: r'$demo-forum-3',
          title: 'Mobile UI polish checklist',
          excerpt:
              'Keyboard behavior, compact reaction menus, and transparent message input treatments for image backgrounds.',
          tags: const ['feedback', 'bugs'],
          senderId: '@iris:intergalactic.local',
          senderDisplayName: 'Iris',
          senderAvatar: const AssetImage(demoAvatarIris),
          replyCount: 3,
          timestamp: now.subtract(const Duration(hours: 2)),
          editableContent: const {},
        ),
        ForumPost(
          eventId: r'$demo-forum-2',
          title: 'Tonight\'s game night plan',
          excerpt:
              'Session timing, voice room etiquette, and the calendar invite for anyone joining late.',
          tags: const ['session-notes'],
          senderId: '@nova:intergalactic.local',
          senderDisplayName: 'Nova',
          senderAvatar: const AssetImage(demoAvatarNova),
          replyCount: 2,
          timestamp: now.subtract(const Duration(hours: 5)),
          editableContent: const {},
        ),
        ForumPost(
          eventId: r'$demo-forum-1',
          title: 'Welcome to Inter Galactic',
          excerpt:
              'This forum demonstrates how a small friend group can keep announcements separate from live chat.',
          tags: const ['announcements'],
          senderId: '@mira:intergalactic.local',
          senderDisplayName: 'Mira',
          senderAvatar: const AssetImage(demoAvatarMira),
          replyCount: 4,
          timestamp: now.subtract(const Duration(days: 1)),
          editableContent: const {},
        ),
      ],
    );
    forum.addComponent(forumComponent);
    _seedForumThreads(forum, forumComponent.posts);

    final callRoom = DemoRoom(
      client: this,
      identifier: demoVoiceRoomId,
      displayName: 'game-night-voice',
      topic: 'A sample LiveKit-style voice room for review.',
      memberIds: allMemberIds,
      roomType: RoomType.voipRoom,
      avatarAsset: demoRoomVoice,
    );
    callRoom.addComponent(
      DemoVoipRoomComponent(
        client: this,
        room: callRoom,
        participants: const [
          '@mira:intergalactic.local',
          '@theo:intergalactic.local',
          '@nova:intergalactic.local',
        ],
      ),
    );

    final calendarRoom = DemoRoom(
      client: this,
      identifier: demoCalendarRoomId,
      displayName: 'guild-calendar',
      topic: 'Upcoming demo events and reminders.',
      memberIds: allMemberIds,
      roomType: RoomType.calendar,
      avatarAsset: demoRoomCalendar,
    );
    calendarRoom.addComponent(
      DemoCalendarRoomComponent(
        client: this,
        room: calendarRoom,
        events: [
          rfc8984.RFC8984CalendarEvent(
            uid: 'demo-session-zero',
            updated: now.toUtc(),
            title: 'Session Zero',
            description: 'Character setup and voice check.',
            start: DateTime(now.year, now.month, now.day, 20),
            duration: const Duration(hours: 2),
            attendeeReminderOffsetsMinutes: const [30, 10],
          ),
          rfc8984.RFC8984CalendarEvent(
            uid: 'demo-weekly-planning',
            updated: now.toUtc(),
            title: 'Weekly Planning',
            description: 'Recurring calendar sample.',
            start: DateTime(now.year, now.month, now.day + 2, 19),
            duration: const Duration(hours: 1),
            recurrenceRules: [
              rfc8984.RFC8984RecurrenceRule(
                frequency: 'weekly',
                byDay: [rfc8984.Rfc8984NDay('fr')],
                count: 6,
              ),
            ],
          ),
        ],
      ),
    );

    final photoRoom = DemoRoom(
      client: this,
      identifier: demoPhotoAlbumRoomId,
      displayName: 'memory-vault',
      topic: 'Demo photo album with individual photos, stacks, and comments.',
      memberIds: allMemberIds,
      roomType: RoomType.photoAlbum,
      avatarAsset: demoRoomVault,
    );
    final photoAlbum = DemoPhotoAlbumRoomComponent.demo(
      client: this,
      room: photoRoom,
      now: now,
    );
    photoRoom.addComponent(photoAlbum);
    photoRoom.replaceTimeline(
      DemoTimeline(
        client: this,
        room: photoRoom,
        initialEvents: photoAlbum.rootEvents,
      ),
    );
    _seedPhotoThreads(photoRoom, photoAlbum.photos);

    final encryptedRoom = DemoRoom(
      client: this,
      identifier: demoEncryptedRoomId,
      displayName: 'encrypted-lab',
      topic: 'A demo encrypted room with recovery examples.',
      memberIds: allMemberIds,
      roomType: RoomType.defaultRoom,
      encrypted: true,
      notificationCount: 2,
      highlightedNotificationCount: 1,
      avatarAsset: demoRoomEncrypted,
    );
    encryptedRoom.replaceTimeline(
      DemoTimeline(
        client: this,
        room: encryptedRoom,
        initialEvents: [
          DemoEncryptedTimelineMessage(
            eventId: r'$demo-encrypted-3',
            senderId: '@iris:intergalactic.local',
            body:
                'Unable to decrypt message. Tap the room padlock to retry key recovery.',
            originServerTs: now.subtract(const Duration(minutes: 5)),
            errorStyle: true,
          ),
          DemoTimelineMessage(
            eventId: r'$demo-encrypted-2',
            senderId: self!.identifier,
            body:
                'This room is staged so the tutorial can explain keys, sessions, and recovery.',
            originServerTs: now.subtract(const Duration(minutes: 16)),
          ),
          DemoTimelineMessage(
            eventId: r'$demo-encrypted-1',
            senderId: '@mira:intergalactic.local',
            body: 'Encryption depends on the room and your Matrix sessions.',
            originServerTs: now.subtract(const Duration(minutes: 33)),
          ),
        ],
      ),
    );

    final directMessages = getComponent<DemoDirectMessagesComponent>()!;
    final miraDm = _createDirectMessageRoom(
      partner: getPerson('@mira:intergalactic.local'),
      identifier: demoMiraDmRoomId,
      now: now,
      messages: [
        DemoTimelineMessage(
          eventId: r'$demo-dm-mira-4',
          senderId: '@mira:intergalactic.local',
          body:
              'Perfect. I will keep the forum announcement short enough for the guide screenshots.',
          originServerTs: now.subtract(const Duration(minutes: 7)),
        ),
        DemoTimelineMessage(
          eventId: r'$demo-dm-mira-3',
          senderId: self!.identifier,
          body:
              'Could you pin the welcome post after I grab the desktop screenshots?',
          originServerTs: now.subtract(const Duration(minutes: 12)),
        ),
        DemoTimelineMessage(
          eventId: r'$demo-dm-mira-2',
          senderId: '@mira:intergalactic.local',
          body:
              'The demo lounge looks ready. Forum tags are visible on desktop too.',
          originServerTs: now.subtract(const Duration(minutes: 25)),
        ),
      ],
    );
    final theoDm = _createDirectMessageRoom(
      partner: getPerson('@theo:intergalactic.local'),
      identifier: '!demo-dm-theo:intergalactic.local',
      now: now,
      messages: [
        DemoTimelineMessage(
          eventId: r'$demo-dm-theo-3',
          senderId: '@theo:intergalactic.local',
          body:
              'I queued a game-night voice room so the guide can show calls without connecting to LiveKit.',
          originServerTs: now.subtract(const Duration(minutes: 18)),
        ),
        DemoTimelineMessage(
          eventId: r'$demo-dm-theo-2',
          senderId: self!.identifier,
          body:
              'Nice. I only need the room list, chat, and call preview shots today.',
          originServerTs: now.subtract(const Duration(minutes: 31)),
        ),
      ],
    );
    final novaDm = _createDirectMessageRoom(
      partner: getPerson('@nova:intergalactic.local'),
      identifier: '!demo-dm-nova:intergalactic.local',
      now: now,
      messages: [
        DemoTimelineMessage(
          eventId: r'$demo-dm-nova-3',
          senderId: '@nova:intergalactic.local',
          body:
              'Calendar samples are set for tonight and Friday, with reminders enabled.',
          originServerTs: now.subtract(const Duration(hours: 1, minutes: 8)),
        ),
        DemoTimelineMessage(
          eventId: r'$demo-dm-nova-2',
          senderId: self!.identifier,
          body: 'Thanks. That gives the guide a clean scheduling example.',
          originServerTs: now.subtract(const Duration(hours: 1, minutes: 17)),
        ),
      ],
    );

    final space = DemoSpace(
      client: this,
      identifier: demoSpaceId,
      displayName: 'Inter Galactic Demo',
      topic: 'Offline demo data: chat, forum, voice, and calendar rooms.',
      color: const Color(0xFF2FB5FF),
      avatarAsset: demoSpaceIcon,
    );
    space.addComponent(
      DemoSoundboardComponent.demo(client: this, space: space, now: now),
    );
    space.addComponent(DemoSpaceEmoticonComponent(this, space));
    space.addComponent(
      DemoSpaceBannerComponent(this, space, bannerAsset: demoSpaceBanner),
    );

    for (final room in [
      chat,
      forum,
      photoRoom,
      callRoom,
      calendarRoom,
      encryptedRoom,
    ]) {
      _addRoom(room);
      space.addRoom(room);
    }
    _addSpace(space);

    for (final room in [miraDm, theoDm, novaDm]) {
      _addRoom(room);
      directMessages.addDirectMessageRoom(room);
    }
  }

  DemoRoom _createDirectMessageRoom({
    required _DemoPerson partner,
    required String identifier,
    required DateTime now,
    required List<DemoTimelineMessage> messages,
  }) {
    final room = DemoRoom(
      client: this,
      identifier: identifier,
      displayName: partner.displayName,
      topic: 'Direct message with ${partner.displayName}.',
      memberIds: [self!.identifier, partner.identifier],
      roomType: RoomType.defaultRoom,
      // DM surfaces (list, recent activity) read the room avatar, so mirror
      // the partner's profile picture onto the room.
      avatarAsset: partner.avatarAsset,
    );
    room.replaceTimeline(
      DemoTimeline(
        client: this,
        room: room,
        initialEvents: [
          ...messages,
          DemoTimelineMessage(
            eventId: r'$demo-dm-start-' + partner.userName.replaceAll(' ', '-'),
            senderId: partner.identifier,
            body:
                'This is a local-only sample direct message for the demo account.',
            originServerTs: now.subtract(const Duration(hours: 2)),
          ),
        ],
      ),
    );
    return room;
  }

  void _seedForumThreads(DemoRoom room, List<ForumPost> posts) {
    final threads = getComponent<DemoThreadsComponent>()!;
    final now = DateTime.now();
    for (final post in posts) {
      final root = DemoTimelineMessage(
        eventId: post.eventId,
        senderId: post.senderId,
        body: '${post.title}\n\n${post.excerpt}',
        originServerTs: post.timestamp,
      );
      final replies = [
        DemoTimelineMessage(
          eventId: '${post.eventId}-reply-2',
          senderId: self!.identifier,
          body: 'This is visible in the offline thread demo.',
          originServerTs: now.subtract(const Duration(minutes: 16)),
          relatedEventId: post.eventId,
        ),
        DemoTimelineMessage(
          eventId: '${post.eventId}-reply-1',
          senderId: '@theo:intergalactic.local',
          body: 'Looks good for a review walkthrough.',
          originServerTs: now.subtract(const Duration(minutes: 28)),
          relatedEventId: post.eventId,
        ),
      ];
      threads.setThreadTimeline(
        room,
        post.eventId,
        DemoTimeline(
          client: this,
          room: room,
          initialEvents: [replies[0], replies[1], root],
        ),
      );
    }
  }

  void _seedPhotoThreads(DemoRoom room, List<DemoPhoto> photos) {
    final threads = getComponent<DemoThreadsComponent>()!;
    final now = DateTime.now();
    for (final photo in photos.where((photo) => !photo.isThreadReply)) {
      final root = DemoTimelineMessage(
        eventId: photo.id,
        senderId: photo.senderId,
        body: photo.stack == null
            ? 'Shared ${photo.name}.'
            : 'Shared photo stack ${photo.stack!.id}.',
        originServerTs: photo.originServerTs,
      );
      final replies = List<DemoTimelineMessage>.generate(
        photo.threadReplyCount,
        (index) => DemoTimelineMessage(
          eventId: '${photo.id}-comment-${index + 1}',
          senderId: index.isEven
              ? '@mira:intergalactic.local'
              : '@theo:intergalactic.local',
          body: index.isEven
              ? 'This is perfect for the tutorial walkthrough.'
              : 'The comments stay attached to the photo root.',
          originServerTs: now.subtract(Duration(minutes: 9 + index * 8)),
          relatedEventId: photo.id,
        ),
      );

      threads.setThreadTimeline(
        room,
        photo.id,
        DemoTimeline(
          client: this,
          room: room,
          initialEvents: [...replies, root],
        ),
      );
    }
  }
}

class DemoRoom extends Room {
  DemoRoom({
    required this.client,
    required this.identifier,
    required String displayName,
    required String? topic,
    required List<String> memberIds,
    required this.roomType,
    this.avatarAsset,
    bool encrypted = false,
    int notificationCount = 0,
    int highlightedNotificationCount = 0,
  }) : _displayName = displayName,
       _topic = topic,
       _memberIds = memberIds,
       _encrypted = encrypted,
       _notificationCount = notificationCount,
       _highlightedNotificationCount = highlightedNotificationCount {
    _timeline = DemoTimeline(client: client, room: this);
    _components.addAll([
      DemoReadReceiptComponent(client, this),
      DemoTypingIndicatorComponent(client, this),
      DemoRoomEmoticonComponent(client, this),
    ]);
  }

  @override
  final DemoClient client;

  @override
  final String identifier;

  final RoomType roomType;

  /// Optional bundled demo room icon. Offline demo mode has no homeserver to
  /// fetch avatars from, so demo rooms point at a local asset instead.
  final String? avatarAsset;

  final List<String> _memberIds;
  final List<RoomComponent> _components = [];
  final StreamController<void> _onUpdate = StreamController.broadcast();
  final DemoPermissions _permissions = DemoPermissions();
  final bool _encrypted;
  final int _notificationCount;
  final int _highlightedNotificationCount;
  DemoTimeline? _timeline;
  String _displayName;
  String? _topic;
  PushRule _pushRule = PushRule.notify;
  RoomVisibility _visibility = RoomVisibilityPrivate();

  @override
  Timeline? get timeline => _timeline;

  @override
  ImageProvider? get avatar =>
      avatarAsset == null ? null : AssetImage(avatarAsset!);

  @override
  String? get avatarId => avatarAsset;

  @override
  Iterable<String> get memberIds => _memberIds;

  @override
  String get displayName => _displayName;

  @override
  String? get topic => _topic;

  @override
  Permissions get permissions => _permissions;

  @override
  bool get isE2EE => _encrypted;

  @override
  bool get isSpecialRoomType => roomType != RoomType.defaultRoom;

  @override
  bool get shouldPreviewMedia => true;

  @override
  Color get defaultColor => client.colorFor(identifier);

  @override
  Stream<void> get onUpdate => _onUpdate.stream;

  @override
  PushRule get pushRule => _pushRule;

  @override
  DateTime get lastEventTimestamp =>
      lastEvent?.originServerTs ?? DateTime.now();

  @override
  String get developerInfo => const JsonEncoder.withIndent('  ').convert({
    'type': 'offline-demo-room',
    'identifier': identifier,
    'roomType': roomType.name,
  });

  @override
  int get notificationCount => _notificationCount;

  @override
  int get highlightedNotificationCount => _highlightedNotificationCount;

  @override
  RoomVisibility get visibility => _visibility;

  @override
  TimelineEvent? get lastEvent => _timeline?.events.firstOrNull;

  void addComponent(RoomComponent component) {
    _components.add(component);
  }

  void replaceTimeline(DemoTimeline timeline) {
    _timeline = timeline;
  }

  @override
  Future<TimelineEvent?> sendMessage({
    String? message,
    TimelineEvent? inReplyTo,
    TimelineEvent? replaceEvent,
    List<ProcessedAttachment> processedAttachments = const [],
  }) async {
    if (message == null || message.trim().isEmpty) return null;

    if (replaceEvent is DemoTimelineMessage) {
      replaceEvent.replaceBody(message.trim());
      final index = _timeline?.events.indexOf(replaceEvent) ?? -1;
      if (index >= 0) _timeline?.notifyChanged(index);
      return replaceEvent;
    }

    final event = DemoTimelineMessage(
      eventId:
          r'$demo-local-' + DateTime.now().microsecondsSinceEpoch.toString(),
      senderId: client.self!.identifier,
      body: message.trim(),
      originServerTs: DateTime.now(),
      relatedEventId: inReplyTo?.eventId,
    );
    _timeline?.insertEvent(0, event);
    _onUpdate.add(null);
    return event;
  }

  @override
  Future<void> cancelSend(TimelineEvent event) async {}

  @override
  Future<void> retrySend(TimelineEvent event) async {}

  @override
  Future<TimelineEvent?> addReaction(
    TimelineEvent reactingTo,
    Emoticon reaction,
  ) async {
    if (reactingTo is DemoTimelineMessage) {
      reactingTo.addReaction(reaction, client.self!.identifier);
      final index = _timeline?.events.indexOf(reactingTo) ?? -1;
      if (index >= 0) _timeline?.notifyChanged(index);
    }
    return null;
  }

  @override
  Future<void> removeReaction(
    TimelineEvent reactingTo,
    Emoticon reaction,
  ) async {
    if (reactingTo is DemoTimelineMessage) {
      reactingTo.removeReaction(reaction, client.self!.identifier);
      final index = _timeline?.events.indexOf(reactingTo) ?? -1;
      if (index >= 0) _timeline?.notifyChanged(index);
    }
  }

  @override
  Future<List<ProcessedAttachment>> processAttachments(
    List<PendingFileAttachment> attachments,
  ) async => const [];

  @override
  List<Member> membersList() =>
      _memberIds.map((id) => client.getPerson(id)).toList();

  @override
  Future<List<Member>> fetchMembersList({bool cache = false}) async =>
      membersList();

  @override
  List<(Member, Role)> importantMembers() => membersList()
      .take(4)
      .map((member) => (member, const DemoRole('Member', Icons.person)))
      .toList();

  @override
  Role getMemberRole(String identifier) =>
      const DemoRole('Member', Icons.person);

  @override
  bool get isMembersListComplete => true;

  @override
  Future<void> setDisplayName(String newName) async {
    _displayName = newName;
    _onUpdate.add(null);
  }

  @override
  Future<void> setRoomAvatar(Uint8List bytes, String? mimeType) async {}

  @override
  Future<void> setPushRule(PushRule rule) async {
    _pushRule = rule;
    _onUpdate.add(null);
  }

  @override
  Future<void> setVisibility(RoomVisibility visibility) async {
    _visibility = visibility;
    _onUpdate.add(null);
  }

  @override
  Color getColorOfUser(String userId) => client.colorFor(userId);

  @override
  Future<Timeline> getTimeline({String? contextEventId}) async => _timeline!;

  @override
  Future<void> enableE2EE() async {}

  @override
  Future<void> close() async {
    for (final component in _components) {
      if (component is DisposableComponent) {
        await (component as DisposableComponent).dispose();
      }
    }
    await _timeline?.close();
    await _onUpdate.close();
  }

  @override
  bool shouldNotify(TimelineEvent event) => false;

  @override
  T? getComponent<T extends RoomComponent>() {
    for (final component in _components) {
      if (component is T) return component;
    }
    return null;
  }

  @override
  List<T> getAllComponents<T extends RoomComponent<Client, Room>>() =>
      _components.whereType<T>().toList();

  @override
  Future<ImageProvider?> getShortcutImage() async => null;

  @override
  Future<TimelineEvent?> getEvent(String eventId) async =>
      _timeline?.fetchEventById(eventId);

  @override
  Future<void> kickUser(String id) async {}

  @override
  Future<void> banUser(String id) async {}

  @override
  Member getMemberOrFallback(String id) => client.getPerson(id);

  @override
  Member? getMember(String id) => client.getPerson(id);

  @override
  Future<Member> fetchMember(String id) async => client.getPerson(id);

  @override
  List<Role> get availableRoles => const [
    DemoRole('Admin', Icons.shield),
    DemoRole('Moderator', Icons.verified_user),
    DemoRole('Member', Icons.person),
  ];

  @override
  Future<void> setMemberRole(String id, Role role) async {}

  @override
  Future<void> setMemberNickname(String id, String? nickname) async {}

  @override
  Future<void> setTopic(String topic) async {
    _topic = topic;
    _onUpdate.add(null);
  }

  @override
  Future<void> markAsRead() async {}
}

class DemoSpace extends Space {
  DemoSpace({
    required this.client,
    required this.identifier,
    required String displayName,
    required String topic,
    required this.color,
    this.avatarAsset,
  }) : _displayName = displayName,
       _topic = topic;

  @override
  final DemoClient client;

  @override
  final String identifier;

  @override
  final Color color;

  /// Optional bundled demo space icon. Offline demo mode has no homeserver to
  /// fetch avatars from, so demo spaces point at a local asset instead.
  final String? avatarAsset;

  final List<Room> _rooms = [];
  final List<Space> _subspaces = [];
  final List<SpaceChild> _children = [];
  final List<RoomPreview> _previews = [];
  final List<SpaceComponent> _components = [];
  final StreamController<void> _onUpdate = StreamController.broadcast();
  final StreamController<Room> _onChildRoomUpdated =
      StreamController.broadcast();
  final StreamController<int> _onRoomAdded = StreamController.broadcast();
  final StreamController<int> _onRoomRemoved = StreamController.broadcast();
  final StreamController<void> _onChildRoomsUpdated =
      StreamController.broadcast();
  final StreamController<int> _onChildRoomPreviewAdded =
      StreamController.broadcast();
  final StreamController<int> _onChildRoomPreviewRemoved =
      StreamController.broadcast();
  final StreamController<int> _onChildSpaceAdded = StreamController.broadcast();
  final StreamController<int> _onChildSpaceRemoved =
      StreamController.broadcast();
  final StreamController<void> _onChildRoomPreviewsUpdated =
      StreamController.broadcast();
  final DemoPermissions _permissions = DemoPermissions();
  String _displayName;
  String _topic;
  PushRule _pushRule = PushRule.notify;
  RoomVisibility _visibility = RoomVisibilityPrivate();

  @override
  Permissions get permissions => _permissions;

  @override
  String get displayName => _displayName;

  @override
  ImageProvider? get avatar =>
      avatarAsset == null ? null : AssetImage(avatarAsset!);

  @override
  List<Room> get rooms => _rooms;

  @override
  List<Space> get subspaces => _subspaces;

  @override
  List<SpaceChild> get children => _children;

  @override
  Future<void> setChildrenOrder(
    List<SpaceChild> children, {
    Function(double?)? onProgressChanged,
  }) async {
    _children
      ..clear()
      ..addAll(children);
    onProgressChanged?.call(1);
    _onChildRoomsUpdated.add(null);
  }

  @override
  bool get isTopLevel => true;

  @override
  String get topic => _topic;

  @override
  PushRule get pushRule => _pushRule;

  @override
  RoomVisibility get visibility => _visibility;

  @override
  String get developerInfo => const JsonEncoder.withIndent(
    '  ',
  ).convert({'type': 'offline-demo-space', 'identifier': identifier});

  @override
  Stream<void> get onUpdate => _onUpdate.stream;

  @override
  Stream<Room> get onChildRoomUpdated => _onChildRoomUpdated.stream;

  @override
  Stream<int> get onRoomAdded => _onRoomAdded.stream;

  @override
  Stream<int> get onRoomRemoved => _onRoomRemoved.stream;

  @override
  Stream<void> get onChildRoomsUpdated => _onChildRoomsUpdated.stream;

  @override
  Stream<int> get onChildRoomPreviewAdded => _onChildRoomPreviewAdded.stream;

  @override
  Stream<int> get onChildRoomPreviewRemoved =>
      _onChildRoomPreviewRemoved.stream;

  @override
  Stream<int> get onChildSpaceAdded => _onChildSpaceAdded.stream;

  @override
  Stream<int> get onChildSpaceRemoved => _onChildSpaceRemoved.stream;

  @override
  Stream<void> get onChildRoomPreviewsUpdated =>
      _onChildRoomPreviewsUpdated.stream;

  @override
  List<RoomPreview> get childPreviews => _previews;

  @override
  bool get fullyLoaded => true;

  void addRoom(Room room) {
    _rooms.add(room);
    _children.add(SpaceChildRoom(room));
    _previews.add(
      GenericRoomPreview(
        room.identifier,
        displayName: room.displayName,
        type: (room as DemoRoom).roomType,
        topic: room.topic,
        visibility: room.visibility,
        numMembers: room.memberIds.length,
      ),
    );
    _onRoomAdded.add(_rooms.length - 1);
    _onChildRoomsUpdated.add(null);
  }

  void addComponent(SpaceComponent component) {
    _components.add(component);
  }

  @override
  bool containsRoom(String identifier) =>
      _rooms.any((room) => room.identifier == identifier) ||
      _subspaces.any((space) => space.containsRoom(identifier));

  @override
  Future<List<RoomPreview>> fetchChildren() async => _previews;

  @override
  Future<Room> createRoom(String name, CreateRoomArgs args) async {
    final room = await client.createRoom(args..name = name);
    await setSpaceChildRoom(room);
    return room;
  }

  @override
  Future<void> setSpaceChildRoom(Room room) async {
    if (containsRoom(room.identifier)) return;
    addRoom(room);
  }

  @override
  Future<void> setSpaceChildSpace(Space room) async {
    _subspaces.add(room);
    _children.add(SpaceChildSpace(room));
    _onChildSpaceAdded.add(_subspaces.length - 1);
  }

  @override
  Future<void> removeChild(SpaceChild child) async {
    if (child is SpaceChildRoom) {
      await detachRoom(child.child);
      return;
    }

    _children.remove(child);
    if (child is SpaceChildSpace) {
      final index = _subspaces.indexOf(child.child);
      if (index >= 0) {
        _subspaces.removeAt(index);
        _onChildSpaceRemoved.add(index);
      }
    }
    _onChildRoomsUpdated.add(null);
  }

  Future<bool> detachRoom(Room room) async {
    var removed = false;

    final roomIndex = _rooms.indexWhere(
      (entry) => entry.identifier == room.identifier,
    );
    if (roomIndex >= 0) {
      _rooms.removeAt(roomIndex);
      _onRoomRemoved.add(roomIndex);
      removed = true;
    }

    final previewIndex = _previews.indexWhere(
      (entry) => entry.roomId == room.identifier,
    );
    if (previewIndex >= 0) {
      _previews.removeAt(previewIndex);
      _onChildRoomPreviewRemoved.add(previewIndex);
      removed = true;
    }

    final childIndex = _children.indexWhere(
      (entry) =>
          entry is SpaceChildRoom && entry.child.identifier == room.identifier,
    );
    if (childIndex >= 0) {
      _children.removeAt(childIndex);
      removed = true;
    }

    for (final subspace in List<Space>.from(_subspaces)) {
      if (subspace is DemoSpace) {
        removed = await subspace.detachRoom(room) || removed;
      }
    }

    if (removed) {
      _onChildRoomsUpdated.add(null);
    }

    return removed;
  }

  @override
  Future<void> setTopic(String topic) async {
    _topic = topic;
    _onUpdate.add(null);
  }

  @override
  Future<void> loadExtra() async {}

  @override
  Future<void> close() async {
    for (final component in _components) {
      if (component is DisposableComponent) {
        await (component as DisposableComponent).dispose();
      }
    }
    await _onUpdate.close();
    await _onChildRoomUpdated.close();
    await _onRoomAdded.close();
    await _onRoomRemoved.close();
    await _onChildRoomsUpdated.close();
    await _onChildRoomPreviewAdded.close();
    await _onChildRoomPreviewRemoved.close();
    await _onChildSpaceAdded.close();
    await _onChildSpaceRemoved.close();
    await _onChildRoomPreviewsUpdated.close();
  }

  @override
  Future<void> setDisplayName(String newName) async {
    _displayName = newName;
    _onUpdate.add(null);
  }

  @override
  Future<void> changeAvatar(Uint8List bytes, String? mimeType) async {}

  @override
  Future<void> setPushRule(PushRule rule) async {
    _pushRule = rule;
    _onUpdate.add(null);
  }

  @override
  T? getComponent<T extends SpaceComponent>() {
    for (final component in _components) {
      if (component is T) return component;
    }
    return null;
  }
}

class DemoTimeline extends Timeline {
  DemoTimeline({
    required DemoClient client,
    required DemoRoom room,
    List<TimelineEvent> initialEvents = const [],
  }) {
    this.client = client;
    this.room = room;
    for (final event in initialEvents) {
      insertEvent(events.length, event);
    }
  }

  final StreamController<void> _loadingController =
      StreamController.broadcast();

  @override
  void markAsRead(TimelineEvent event) {}

  @override
  Future<void> loadMoreHistory() async {}

  @override
  Future<void> loadMoreFuture() async {}

  @override
  bool get isLoadingHistory => false;

  @override
  bool get isLoadingFuture => false;

  @override
  bool get canLoadFuture => false;

  @override
  bool get canLoadHistory => false;

  @override
  Stream<void> get onLoadingStatusChanged => _loadingController.stream;

  @override
  Future<void> close() async {
    await _loadingController.close();
    await onEventAdded.close();
    await onChange.close();
    await onRemove.close();
  }

  @override
  Future<TimelineEvent?> fetchEventByIdInternal(String eventId) async =>
      events.where((event) => event.eventId == eventId).firstOrNull;

  @override
  bool canDeleteEvent(TimelineEvent event) =>
      event.senderId == room.client.self?.identifier;

  @override
  void deleteEvent(TimelineEvent event) {
    final index = events.indexOf(event);
    if (index < 0) return;
    events.removeAt(index);
    onRemove.add(index);
  }

  @override
  bool isEventRedacted(TimelineEvent event) => false;
}

class DemoTimelineMessage
    implements
        TimelineEventMessage,
        TimelineEventFeatureRelated,
        TimelineEventFeatureReactions {
  DemoTimelineMessage({
    required this.eventId,
    required this.senderId,
    required String body,
    required this.originServerTs,
    this.relatedEventId,
    this.errorStyle = false,
  }) : _body = body;

  String _body;
  final Map<Emoticon, Set<String>> _reactions = {};
  final bool errorStyle;

  @override
  final String eventId;

  @override
  final String senderId;

  @override
  final DateTime originServerTs;

  @override
  final String? relatedEventId;

  @override
  TimelineEventStatus get status => TimelineEventStatus.synced;

  @override
  String get plainTextBody => _body;

  @override
  String get source => const JsonEncoder.withIndent('  ').convert({
    'type': 'm.room.message',
    'content': {'msgtype': 'm.text', 'body': _body},
    'sender': senderId,
    'event_id': eventId,
    'demo': true,
  });

  @override
  bool get editable => true;

  @override
  String getPlaintextBody(Timeline timeline) => _body;

  @override
  Widget? buildFormattedContent({Timeline? timeline}) {
    if (!errorStyle) {
      return Text(_body);
    }

    return Builder(
      builder: (context) => Text(
        _body,
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  @override
  String? get body => _body;

  @override
  String? get bodyFormat => null;

  @override
  String? get formattedBody => null;

  @override
  List<Attachment>? get attachments => null;

  @override
  bool isEdited(Timeline timeline) => false;

  @override
  List<Uri>? getLinks({Timeline? timeline}) {
    final matches = RegExp(r'https?://[^\s]+').allMatches(_body);
    final links = matches
        .map((match) => Uri.tryParse(match.group(0)!))
        .whereType<Uri>()
        .toList();
    return links.isEmpty ? null : links;
  }

  @override
  EventRelationshipType? get relationshipType =>
      relatedEventId == null ? null : EventRelationshipType.reply;

  @override
  bool hasReactions(Timeline timeline) => _reactions.isNotEmpty;

  @override
  Map<Emoticon, Set<String>> getReactions(Timeline timeline) => _reactions;

  void replaceBody(String body) {
    _body = body;
  }

  void addReaction(Emoticon reaction, String userId) {
    _reactions.putIfAbsent(reaction, () => <String>{}).add(userId);
  }

  void removeReaction(Emoticon reaction, String userId) {
    _reactions[reaction]?.remove(userId);
    if (_reactions[reaction]?.isEmpty == true) {
      _reactions.remove(reaction);
    }
  }
}

class DemoEncryptedTimelineMessage extends DemoTimelineMessage
    implements TimelineEventEncrypted {
  DemoEncryptedTimelineMessage({
    required super.eventId,
    required super.senderId,
    required super.body,
    required super.originServerTs,
    super.relatedEventId,
    super.errorStyle = true,
  });

  @override
  Future<TimelineEvent?> attemptDecrypt(Room room) async => null;
}

class DemoForumRoomComponent
    implements ForumRoomComponent<DemoClient, DemoRoom> {
  DemoForumRoomComponent({
    required this.client,
    required this.room,
    required List<String> availableTags,
    required List<ForumPost> initialPosts,
  }) : _availableTags = availableTags,
       _posts = List.of(initialPosts);

  @override
  final DemoClient client;

  @override
  final DemoRoom room;

  final List<String> _availableTags;
  final List<ForumPost> _posts;
  final StreamController<void> _postsController = StreamController.broadcast();

  @override
  List<String> get availableTags => _availableTags;

  @override
  Stream<void> get onPostsChanged => _postsController.stream;

  @override
  List<ForumPost> get posts => _posts;

  @override
  bool get canPost => true;

  @override
  Future<void> loadPosts() async {}

  @override
  Future<void> createPost({
    required String title,
    required String body,
    required List<String> tags,
  }) async {
    final eventId =
        r'$demo-forum-local-' +
        DateTime.now().microsecondsSinceEpoch.toString();
    final post = ForumPost(
      eventId: eventId,
      title: title,
      excerpt: body,
      tags: tags,
      senderId: client.self!.identifier,
      senderDisplayName: client.self!.displayName,
      replyCount: 0,
      timestamp: DateTime.now(),
      editableContent: {
        'body': body,
        'ig.forum.title': title,
        'ig.forum.tags': tags,
      },
    );
    _posts.insert(0, post);
    room.timeline?.insertEvent(
      0,
      DemoTimelineMessage(
        eventId: eventId,
        senderId: client.self!.identifier,
        body: '$title\n\n$body',
        originServerTs: post.timestamp,
      ),
    );
    client.getComponent<DemoThreadsComponent>()?.setThreadTimeline(
      room,
      eventId,
      DemoTimeline(
        client: client,
        room: room,
        initialEvents: [
          DemoTimelineMessage(
            eventId: eventId,
            senderId: client.self!.identifier,
            body: '$title\n\n$body',
            originServerTs: post.timestamp,
          ),
        ],
      ),
    );
    _postsController.add(null);
  }

  @override
  bool canEditTags(ForumPost post) => post.senderId == client.self!.identifier;

  @override
  Future<void> editPostTags(ForumPost post, List<String> newTags) async {
    final index = _posts.indexWhere((item) => item.eventId == post.eventId);
    if (index < 0) return;
    final replacement = ForumPost(
      eventId: post.eventId,
      title: post.title,
      excerpt: post.excerpt,
      previewImage: post.previewImage,
      tags: List.of(newTags),
      senderId: post.senderId,
      senderDisplayName: post.senderDisplayName,
      senderAvatar: post.senderAvatar,
      replyCount: post.replyCount,
      timestamp: post.timestamp,
      editableContent: {
        ...post.editableContent,
        'ig.forum.tags': List.of(newTags),
      },
    );
    _posts[index] = replacement;
    _postsController.add(null);
  }
}

class DemoCalendarRoomComponent
    implements CalendarRoom<DemoClient, DemoRoom>, DisposableComponent {
  DemoCalendarRoomComponent({
    required this.client,
    required this.room,
    required List<rfc8984.RFC8984CalendarEvent> events,
  }) {
    final api = _DemoMatrixWidgetApi(client.self!.identifier);
    _calendar = calendar_widget.MatrixCalendar(
      api,
      config: _DemoCalendarConfig(room),
    );
    _calendarChangedListener = () {
      if (!_eventsChanged.isClosed) {
        _eventsChanged.add(null);
      }
    };
    _calendar!.controller.addListener(_calendarChangedListener);

    for (final event in events) {
      for (var calendarEvent in _calendar!.fromRfcEvent(event)) {
        final state = calendarEvent.event;
        if (state != null) {
          state.senderId = client.self!.identifier;
          state.loaded = true;
          state.eventId = r'$demo-calendar-' + event.uid;
        }
        calendarEvent = calendarEvent.copyWith(
          color: room.getColorOfUser(client.self!.identifier),
        );
        _calendar!.controller.add(calendarEvent);
      }
    }
  }

  @override
  final DemoClient client;

  @override
  final DemoRoom room;

  calendar_widget.MatrixCalendar? _calendar;
  late final VoidCallback _calendarChangedListener;
  final StreamController<void> _eventsChanged = StreamController.broadcast();
  final StoredStreamController<Map<String, SyncedCalendar>> _syncedCalendars =
      StoredStreamController<Map<String, SyncedCalendar>>(
        const <String, SyncedCalendar>{},
      );

  @override
  calendar_widget.MatrixCalendar? get calendar => _calendar;

  @override
  bool get hasCalendar => true;

  @override
  bool get isCalendarRoom => true;

  @override
  Stream<void> get onEventsChanged => _eventsChanged.stream;

  @override
  List<calendar_widget.MatrixCalendarEventState> getEventsOnDay(
    DateTime date,
  ) => _calendar?.getEventsOnDay(date) ?? const [];

  @override
  StoredStreamController<Map<String, SyncedCalendar>> get syncedCalendars =>
      _syncedCalendars;

  @override
  Future<List<rfc8984.RFC8984CalendarEvent>> getEventsFromIcsUrl(
    Uri uri, {
    String? calendarId,
  }) async => const [];

  @override
  Future<void> addSyncedCalendar(SyncedCalendar calendar) async {}

  @override
  Future<void> removeSyncedCalendar(String id) async {}

  @override
  Future<void> runCalendarSync() async {}

  @override
  Future<void> dispose() async {
    final calendar = _calendar;
    if (calendar != null) {
      calendar.controller.removeListener(_calendarChangedListener);
    }
    _calendar = null;
    await _eventsChanged.close();
    await _syncedCalendars.close();
  }
}

class DemoUserPresenceComponent
    implements UserPresenceComponent<DemoClient>, DisposableComponent {
  DemoUserPresenceComponent(this.client);

  @override
  final DemoClient client;

  final StreamController<(String, UserPresence)> _presenceChanged =
      StreamController.broadcast();
  bool _usePublicReadReceipts = true;
  bool _typingIndicatorEnabled = true;
  UserPresenceStatus _status = UserPresenceStatus.online;

  @override
  Stream<(String, UserPresence)> get onPresenceChanged =>
      _presenceChanged.stream;

  @override
  bool get usePublicReadReceipts => _usePublicReadReceipts;

  @override
  Future<void> setUsePublicReadReceipts(bool value) async {
    _usePublicReadReceipts = value;
  }

  @override
  bool get typingIndicatorEnabled => _typingIndicatorEnabled;

  @override
  Future<void> setTypingIndicatorEnabled(bool value) async {
    _typingIndicatorEnabled = value;
  }

  @override
  Future<UserPresence> getUserPresence(String userId) async =>
      UserPresence(_status);

  @override
  Future<void> setStatus(
    UserPresenceStatus status, {
    String? message,
    bool clearMessage = false,
  }) async {
    _status = status;
    _presenceChanged.add((client.self!.identifier, UserPresence(status)));
  }

  @override
  Future<void> dispose() async {
    await _presenceChanged.close();
  }
}

class DemoReadReceiptComponent
    implements ReadReceiptComponent<DemoClient, DemoRoom>, DisposableComponent {
  DemoReadReceiptComponent(this.client, this.room);

  @override
  final DemoClient client;

  @override
  final DemoRoom room;

  final StreamController<String> _readReceiptsUpdated =
      StreamController.broadcast();
  bool? _usePublicReadReceiptsForRoom;

  @override
  Stream<String> get onReadReceiptsUpdated => _readReceiptsUpdated.stream;

  @override
  bool? get usePublicReadReceiptsForRoom => _usePublicReadReceiptsForRoom;

  @override
  Future<void> setUsePublicReadReceiptsForRoom(bool? value) async {
    _usePublicReadReceiptsForRoom = value;
    _readReceiptsUpdated.add(room.identifier);
  }

  @override
  List<String>? getReceipts(TimelineEvent event) => const [];

  @override
  Future<void> dispose() async {
    await _readReceiptsUpdated.close();
  }
}

class DemoTypingIndicatorComponent
    implements
        TypingIndicatorComponent<DemoClient, DemoRoom>,
        DisposableComponent {
  DemoTypingIndicatorComponent(this.client, this.room);

  @override
  final DemoClient client;

  @override
  final DemoRoom room;

  final StreamController<void> _typingUsersUpdated =
      StreamController.broadcast();
  bool? _typingIndicatorEnabledForRoom;

  @override
  Stream<void> get onTypingUsersUpdated => _typingUsersUpdated.stream;

  @override
  bool? get typingIndicatorEnabledForRoom => _typingIndicatorEnabledForRoom;

  @override
  Future<void> setTypingIndicatorEnabledForRoom(bool? value) async {
    _typingIndicatorEnabledForRoom = value;
    _typingUsersUpdated.add(null);
  }

  @override
  List<Member> get typingUsers => const [];

  @override
  Future<void> setTypingStatus(bool status) async {}

  @override
  Future<void> dispose() async {
    await _typingUsersUpdated.close();
  }
}

class DemoVoipRoomComponent implements VoipRoomComponent<DemoClient, DemoRoom> {
  DemoVoipRoomComponent({
    required this.client,
    required this.room,
    required List<String> participants,
  }) : _participants = participants;

  @override
  final DemoClient client;

  @override
  final DemoRoom room;

  final List<String> _participants;
  final StreamController<void> _participantsChanged =
      StreamController.broadcast();
  DemoVoipSession? _currentSession;
  StreamSubscription<VoipState>? _currentSessionSubscription;

  @override
  List<String> getCurrentParticipants() => _participants;

  @override
  Stream<void> get onParticipantsChanged => _participantsChanged.stream;

  @override
  VoipSession? get currentSession => _currentSession;

  @override
  /// Mirrors what [joinCall] will actually do, including the replacement path.
  ///
  /// `_currentSession == null` alone contradicted [joinCall]: that method
  /// replaces a session whose state `isFinishing`, but `_currentSession` is
  /// only cleared asynchronously when the ended event arrives. For that window
  /// a surface gating on this getter refused a join the method would have
  /// accepted - the same "I left the call and the button does nothing" shape
  /// the real join guard was fixed for.
  bool get canJoinCall {
    final session = _currentSession;
    return session == null || session.state.isFinishing;
  }

  @override
  Future<VoipSession?> joinCall() async {
    final currentSession = _currentSession;
    // `!isFinishing` rather than `!= ended`: a session in `leaving` is not a
    // usable call, and handing it back is the same defect A3 fixed on the real
    // join guard.
    if (currentSession != null && !currentSession.state.isFinishing) {
      return currentSession;
    }

    final session = DemoVoipSession(client: client, room: room);
    _currentSession = session;
    await _currentSessionSubscription?.cancel();
    _currentSessionSubscription = session.onConnectionStateChanged.listen((
      state,
    ) {
      if (state == VoipState.ended && identical(_currentSession, session)) {
        _currentSession = null;
      }
    });
    return session;
  }

  @override
  Future<String?> getCallServerUrl() async => 'Offline demo voice room';

  @override
  Future<void> clearAllCallMembershipStatus() async {}
}

class DemoVoipSession implements VoipSession {
  DemoVoipSession({required this.client, required DemoRoom room})
    : roomId = room.identifier,
      roomName = room.displayName;

  @override
  final DemoClient client;

  @override
  final String roomId;

  @override
  final String roomName;

  final StreamController<VoipState> _connectionState =
      StreamController.broadcast();
  final StreamController<void> _stateChanged = StreamController.broadcast();
  final StreamController<void> _volumeVisualizers =
      StreamController.broadcast();
  final StreamController<void> _diagnosticsChanged =
      StreamController.broadcast();
  late final List<VoipStream> _streams = [
    DemoVoipStream(
      type: VoipStreamType.video,
      direction: VoipStreamDirection.outgoing,
      streamUserId: client.self!.identifier,
      label: 'Demo camera',
      streamId: 'demo-local-video',
      isMuted: true,
      audiolevel: 0,
    ),
    DemoVoipStream(
      type: VoipStreamType.audio,
      direction: VoipStreamDirection.incoming,
      streamUserId: '@mira:intergalactic.local',
      label: 'Mira microphone',
      streamId: 'demo-mira-audio',
      audiolevel: 0.48,
    ),
    DemoVoipStream(
      type: VoipStreamType.video,
      direction: VoipStreamDirection.incoming,
      streamUserId: '@mira:intergalactic.local',
      label: 'Mira camera',
      streamId: 'demo-mira-video',
      audiolevel: 0.48,
    ),
    DemoVoipStream(
      type: VoipStreamType.audio,
      direction: VoipStreamDirection.incoming,
      streamUserId: '@theo:intergalactic.local',
      label: 'Theo microphone',
      streamId: 'demo-theo-audio',
      isMuted: true,
      audiolevel: 0.12,
    ),
    DemoVoipStream(
      type: VoipStreamType.screenshare,
      direction: VoipStreamDirection.incoming,
      streamUserId: '@theo:intergalactic.local',
      label: 'Theo stream',
      streamId: 'demo-theo-screen',
      aspectRatio: 16 / 9,
    ),
  ];
  VoipState _state = VoipState.connected;
  bool _disposed = false;

  @override
  String get sessionId => 'offline-demo-call';

  @override
  String? get remoteUserId => null;

  @override
  String? get remoteUserName => null;

  @override
  VoipState get state => _state;

  @override
  bool get isMicrophoneMuted => true;

  @override
  bool get supportsScreenshare => false;

  @override
  bool get isSharingScreen => false;

  @override
  ShareSession? get currentShareSession => null;

  @override
  bool get isCameraEnabled => false;

  @override
  double get generalAudioLevel => 0;

  @override
  VoipStream? get remoteUserMediaStream => null;

  @override
  List<VoipStream> get streams => List.unmodifiable(_streams);

  @override
  Future<void> acceptCall({
    bool withMicrophone = false,
    bool withCamera = false,
  }) async {}

  @override
  Future<void> declineCall() async {
    await hangUpCall();
  }

  @override
  Future<void> hangUpCall() async {
    if (!_disposed && _state != VoipState.ended) {
      _state = VoipState.ended;
      _connectionState.add(_state);
      _stateChanged.add(null);
    }
    await dispose();
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    await Future.wait(
      _streams.whereType<DemoVoipStream>().map((stream) => stream.dispose()),
    );
    await _connectionState.close();
    await _stateChanged.close();
    await _volumeVisualizers.close();
    await _diagnosticsChanged.close();
  }

  @override
  Stream<VoipState> get onConnectionStateChanged => _connectionState.stream;

  @override
  Stream<void> get onStateChanged => _stateChanged.stream;

  @override
  Stream<void> get onUpdateVolumeVisualizers => _volumeVisualizers.stream;

  @override
  VoipCallDiagnosticsSnapshot get diagnosticsSnapshot =>
      VoipCallDiagnosticsSnapshot.empty();

  @override
  Stream<void> get onDiagnosticsChanged => _diagnosticsChanged.stream;

  @override
  Future<void> setMicrophoneMute(bool state, {bool stopOnMute = true}) async {}

  @override
  Future<void> updateStats() async {}

  @override
  Future<ScreenCaptureSource?> pickScreenCapture(BuildContext context) async =>
      null;

  @override
  Future<void> setScreenShare(ScreenCaptureSource source) async {}

  @override
  Future<void> stopScreenshare() async {}

  @override
  Future<void> setCamera(MediaDeviceInfo? device) async {}

  @override
  Future<void> stopCamera() async {}
}

class DemoVoipStream implements VoipStream {
  DemoVoipStream({
    required this.type,
    required this.direction,
    required this.streamUserId,
    required this.label,
    required this.streamId,
    this.audiolevel = 0,
    this.isMuted = false,
    this.aspectRatio,
  });

  @override
  final VoipStreamType type;

  @override
  final VoipStreamDirection direction;

  @override
  final String streamUserId;

  @override
  final String label;

  @override
  final String streamId;

  @override
  final double audiolevel;

  @override
  final bool isMuted;

  @override
  final double? aspectRatio;

  final StreamController<void> _changed = StreamController.broadcast();
  VoipStreamReceivePriority _receivePriority = VoipStreamReceivePriority.high;
  bool _disposed = false;

  @override
  Stream<void> get onStreamChanged => _changed.stream;

  @override
  VoipStreamReceivePriority get receivePriority => _receivePriority;

  @override
  Widget? buildVideoRenderer(BoxFit fit, Key key) => null;

  @override
  Future<void> setReceivePriority(VoipStreamReceivePriority priority) async {
    if (_disposed) {
      return;
    }

    _receivePriority = priority;
    _changed.add(null);
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    await _changed.close();
  }
}

class DemoThreadsComponent implements ThreadsComponent<DemoClient> {
  DemoThreadsComponent(this.client);

  @override
  final DemoClient client;

  final Map<String, DemoTimeline> _threads = {};

  String _key(Room room, String threadRootEventId) =>
      '${room.identifier}:$threadRootEventId';

  void setThreadTimeline(
    Room room,
    String threadRootEventId,
    DemoTimeline timeline,
  ) {
    _threads[_key(room, threadRootEventId)] = timeline;
  }

  @override
  bool isEventInResponseToThread(TimelineEvent event, Timeline timeline) {
    if (event is! TimelineEventFeatureRelated) return false;
    final related = event as TimelineEventFeatureRelated;
    return related.relationshipType == EventRelationshipType.reply &&
        related.relatedEventId != null;
  }

  @override
  bool isHeadOfThread(TimelineEvent event, Timeline timeline) =>
      _threads.containsKey(_key(timeline.room, event.eventId));

  @override
  Future<Timeline?> getThreadTimeline({
    required Timeline roomTimeline,
    required String threadRootEventId,
  }) async => _threads[_key(roomTimeline.room, threadRootEventId)];

  @override
  Future<TimelineEvent?> sendMessage({
    required String threadRootEventId,
    required Room room,
    String? message,
    TimelineEvent? inReplyTo,
    TimelineEvent? replaceEvent,
    List<ProcessedAttachment>? processedAttachments,
  }) async {
    final timeline = _threads[_key(room, threadRootEventId)];
    if (timeline == null || message == null || message.trim().isEmpty) {
      return null;
    }

    final event = DemoTimelineMessage(
      eventId:
          r'$demo-thread-local-' +
          DateTime.now().microsecondsSinceEpoch.toString(),
      senderId: client.self!.identifier,
      body: message.trim(),
      originServerTs: DateTime.now(),
      relatedEventId: inReplyTo?.eventId ?? threadRootEventId,
    );
    timeline.insertEvent(0, event);
    return event;
  }

  @override
  TimelineEvent? getFirstReplyToThread(TimelineEvent event, Timeline timeline) {
    final thread = _threads[_key(timeline.room, event.eventId)];
    return thread?.events
        .where((candidate) => candidate.eventId != event.eventId)
        .lastOrNull;
  }
}

class DemoPhotoAlbumRoomComponent
    implements PhotoAlbumRoom<DemoClient, DemoRoom>, DisposableComponent {
  DemoPhotoAlbumRoomComponent({
    required this.client,
    required this.room,
    required List<DemoPhoto> photos,
  }) : _photos = List.of(photos),
       _timeline = DemoPhotoAlbumTimeline(List.of(photos));

  factory DemoPhotoAlbumRoomComponent.demo({
    required DemoClient client,
    required DemoRoom room,
    required DateTime now,
  }) {
    final stackId = 'demo-stack-game-night';
    final photos = [
      DemoPhoto.image(
        id: r'$demo-photo-single-1',
        senderId: '@mira:intergalactic.local',
        name: 'starlight-table.png',
        originServerTs: now.subtract(const Duration(minutes: 42)),
        width: 960,
        height: 720,
        threadReplyCount: 2,
      ),
      DemoPhoto.image(
        id: DemoClient.demoPhotoStackRootEventId,
        senderId: '@nova:intergalactic.local',
        name: 'game-night-1.png',
        originServerTs: now.subtract(const Duration(minutes: 31)),
        width: 800,
        height: 1000,
        threadReplyCount: 3,
        stack: PhotoStackMetadata(id: stackId, index: 0, count: 3),
      ),
      DemoPhoto.image(
        id: r'$demo-photo-stack-2',
        senderId: '@nova:intergalactic.local',
        name: 'game-night-2.png',
        originServerTs: now.subtract(const Duration(minutes: 30)),
        width: 1000,
        height: 850,
        threadReplyCount: 0,
        stack: PhotoStackMetadata(id: stackId, index: 1, count: 3),
      ),
      DemoPhoto.image(
        id: r'$demo-photo-stack-3',
        senderId: '@nova:intergalactic.local',
        name: 'game-night-3.png',
        originServerTs: now.subtract(const Duration(minutes: 29)),
        width: 900,
        height: 900,
        threadReplyCount: 0,
        stack: PhotoStackMetadata(id: stackId, index: 2, count: 3),
      ),
    ];

    return DemoPhotoAlbumRoomComponent(
      client: client,
      room: room,
      photos: photos,
    );
  }

  @override
  final DemoClient client;

  @override
  final DemoRoom room;

  final List<DemoPhoto> _photos;
  final DemoPhotoAlbumTimeline _timeline;

  List<DemoPhoto> get photos => List.unmodifiable(_photos);

  List<DemoTimelineMessage> get rootEvents => _photos
      .where((photo) => !photo.isThreadReply)
      .map(
        (photo) => DemoTimelineMessage(
          eventId: photo.id,
          senderId: photo.senderId,
          body: photo.stack == null
              ? 'Shared ${photo.name}.'
              : 'Shared ${photo.name} as part of a photo stack.',
          originServerTs: photo.originServerTs,
        ),
      )
      .toList(growable: false);

  @override
  bool get canUpload => true;

  @override
  Future<PhotoAlbumTimeline> getTimeline() async => _timeline;

  @override
  Future<void> uploadPhotos(
    List<PickedPhoto> photos, {
    PhotoAlbumUploadMode mode = PhotoAlbumUploadMode.individual,
    bool sendOriginal = false,
    bool extractMetadata = true,
  }) async {
    if (photos.isEmpty) {
      return;
    }

    final stackId = 'demo-local-stack-${DateTime.now().microsecondsSinceEpoch}';
    for (var i = 0; i < photos.length; i += 1) {
      final picked = photos[i];
      final photo = DemoPhoto.image(
        id:
            r'$demo-photo-local-' +
            DateTime.now().microsecondsSinceEpoch.toString() +
            '-$i',
        senderId: client.self!.identifier,
        name: picked.name,
        originServerTs: DateTime.now(),
        width: 900,
        height: 900,
        threadReplyCount: 0,
        stack: mode == PhotoAlbumUploadMode.stack
            ? PhotoStackMetadata(id: stackId, index: i, count: photos.length)
            : null,
      );
      _photos.insert(0, photo);
      _timeline.insert(0, photo);
    }
  }

  @override
  Future<void> dispose() => _timeline.dispose();
}

class DemoPhotoAlbumTimeline implements PhotoAlbumTimeline {
  DemoPhotoAlbumTimeline(List<DemoPhoto> photos) : _photos = photos;

  final List<DemoPhoto> _photos;
  final StreamController<int> _onAdded = StreamController.broadcast();
  final StreamController<int> _onChanged = StreamController.broadcast();
  final StreamController<int> _onRemoved = StreamController.broadcast();

  @override
  Stream<int> get onAdded => _onAdded.stream;

  @override
  Stream<int> get onChanged => _onChanged.stream;

  @override
  Stream<int> get onRemoved => _onRemoved.stream;

  @override
  List<Photo> get photos => List.unmodifiable(_photos);

  @override
  List<PhotoAlbumEntry> get entries => buildPhotoAlbumEntries(_photos);

  @override
  bool get canLoadMorePhotos => false;

  @override
  Future<void> loadMorePhotos() async {}

  void insert(int index, DemoPhoto photo) {
    _photos.insert(index, photo);
    _onAdded.add(index);
  }

  Future<void> dispose() async {
    await _onAdded.close();
    await _onChanged.close();
    await _onRemoved.close();
  }
}

class DemoPhoto implements Photo {
  DemoPhoto.image({
    required this.id,
    required this.senderId,
    required this.name,
    required this.originServerTs,
    required this.width,
    required this.height,
    required this.threadReplyCount,
    this.stack,
    this.isThreadReply = false,
  }) : attachment = ImageAttachment(
         AssetImage(_demoPhotoAssetForId(id)),
         DemoFileProvider('demo-photo-$id', _demoImageBytes),
         name: name,
         mimeType: 'image/png',
         width: width,
         height: height,
       );

  final String senderId;
  final String name;
  final DateTime originServerTs;

  @override
  final String id;

  @override
  final ImageAttachment attachment;

  @override
  final PhotoStackMetadata? stack;

  @override
  final bool isThreadReply;

  @override
  final int threadReplyCount;

  @override
  TimelineEventStatus get status => TimelineEventStatus.synced;

  @override
  final double? width;

  @override
  final double? height;
}

class DemoSoundboardComponent extends SoundboardComponent<DemoClient, DemoSpace>
    implements DisposableComponent {
  DemoSoundboardComponent.demo({
    required DemoClient client,
    required DemoSpace space,
    required DateTime now,
  }) : super(client, space) {
    const missionPackId = 'demo-pack-mission';
    _explicitPacks[missionPackId] = SoundboardPack(
      id: missionPackId,
      name: 'Mission sounds',
      createdBy: '@mira:intergalactic.local',
      createdAt: now.subtract(const Duration(days: 2)),
      updatedAt: now.subtract(const Duration(days: 2)),
    );
    _sounds.addAll([
      SoundboardSound(
        id: 'demo-launch',
        name: 'Launch',
        emoji: '🚀',
        mxcUri: Uri.parse('mxc://intergalactic.local/demo-launch'),
        mimeType: 'audio/ogg',
        uploadedBy: '@mira:intergalactic.local',
        createdAt: now.subtract(const Duration(days: 2)),
        sizeBytes: 42000,
        durationMs: 1200,
        packId: missionPackId,
      ),
      SoundboardSound(
        id: 'demo-sparkle',
        name: 'Sparkle',
        emoji: '✨',
        mxcUri: Uri.parse('mxc://intergalactic.local/demo-sparkle'),
        mimeType: 'audio/ogg',
        uploadedBy: '@nova:intergalactic.local',
        createdAt: now.subtract(const Duration(days: 1)),
        sizeBytes: 39000,
        durationMs: 850,
        packId: missionPackId,
      ),
      SoundboardSound(
        id: 'demo-chime',
        name: 'Join chime',
        emoji: '🔔',
        mxcUri: Uri.parse('mxc://intergalactic.local/demo-chime'),
        mimeType: 'audio/ogg',
        uploadedBy: client.self!.identifier,
        createdAt: now.subtract(const Duration(hours: 6)),
        sizeBytes: 51000,
        durationMs: 1600,
        packId: missionPackId,
      ),
    ]);
    _joinSounds[client.self!.identifier] = 'demo-chime';
    // All three seeded sounds carry missionPackId, so the demo presents ONE
    // named pack. Two of them previously carried none and fell into
    // per-uploader legacy packs, which the fallback captions identically —
    // the demo account then showed "Mission sounds", "Legacy sounds" and
    // "Legacy sounds" side by side. That collision is a real presentation
    // defect and is tracked on its own queue row; seeding around it here only
    // stops the demo from being the loudest example of it, and is not a fix.
    _packActiveOverrides[missionPackId] = true;
  }

  final List<SoundboardSound> _sounds = [];
  final Map<String, SoundboardPack> _explicitPacks = {};
  final Map<String, bool> _packActiveOverrides = {};
  final Map<String, String?> _joinSounds = {};
  final StreamController<void> _onChanged = StreamController.broadcast();

  List<SoundboardSound> get _availableSounds =>
      _sounds.where((sound) => sound.isAvailable).toList(growable: false);

  @override
  List<SoundboardSound> get sounds {
    return _availableSounds
        .where((sound) {
          final packId = sound.packId;
          if (packId == null) {
            final materialized =
                _explicitPacks[SoundboardPack.legacyIdForUploader(
                  sound.uploadedBy,
                )];
            return materialized == null || materialized.isAvailable;
          }
          final pack = _explicitPacks[packId];
          return pack != null && pack.isAvailable;
        })
        .toList(growable: false);
  }

  @override
  List<SoundboardPack> get packs {
    final visible = _explicitPacks.values
        .where((pack) => !pack.deleted)
        .toList();
    final legacy = SoundboardComponent.deriveLegacyPacks(
      _availableSounds,
      _explicitPacks.keys.toSet(),
    );
    return [...visible, ...legacy];
  }

  @override
  List<SoundboardSound> soundsInPack(String packId) => _availableSounds
      .where((sound) => effectivePackIdFor(sound) == packId)
      .toList(growable: false);

  @override
  Set<String> get activePackIds {
    final userId = client.self?.identifier;
    final result = <String>{};
    for (final pack in packs) {
      if (!pack.isAvailable) {
        continue;
      }
      final active =
          _packActiveOverrides[pack.id] ?? (pack.createdBy == userId);
      if (active) {
        result.add(pack.id);
      }
    }
    return result;
  }

  @override
  Stream<void> get onChanged => _onChanged.stream;

  @override
  bool get canUploadSound => true;

  @override
  bool get canCreatePack => true;

  @override
  bool get memberUploadsEnabled => true;

  @override
  bool get canEnableMemberUploads => true;

  @override
  int get soundUploadPowerLevel => 0;

  @override
  int get packCreationPowerLevel => 0;

  @override
  int get defaultUserPowerLevel => 0;

  @override
  int? get currentUserPowerLevel => 100;

  @override
  String? getJoinSoundId(String userId) => _joinSounds[userId];

  @override
  bool canManageSound(SoundboardSound sound, String userId) =>
      sound.uploadedBy == userId || userId == client.self?.identifier;

  @override
  bool canManagePack(SoundboardPack pack, String userId) =>
      pack.createdBy == userId || userId == client.self?.identifier;

  @override
  Future<void> refreshSounds() async {}

  @override
  Future<void> enableMemberUploads() async {}

  @override
  Future<void> alignPackCreationPermission() async {}

  @override
  Future<SoundboardPack> createPack(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('Sound packs need a name.');
    }
    final now = DateTime.now();
    final pack = SoundboardPack(
      id: 'demo-pack-${now.microsecondsSinceEpoch}',
      name: trimmedName,
      createdBy: client.self!.identifier,
      createdAt: now,
      updatedAt: now,
    );
    _explicitPacks[pack.id] = pack;
    _onChanged.add(null);
    return pack;
  }

  @override
  Future<void> renamePack(SoundboardPack pack, String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('Sound packs need a name.');
    }
    _explicitPacks[pack.id] = pack.copyWith(
      name: trimmedName,
      updatedAt: DateTime.now(),
    );
    _onChanged.add(null);
  }

  @override
  Future<void> setPackEmoji(SoundboardPack pack, String? emoji) async {
    final trimmed = emoji?.trim();
    _explicitPacks[pack.id] = pack.copyWith(
      emoji: trimmed != null && trimmed.isNotEmpty ? trimmed : null,
      clearEmoji: trimmed == null || trimmed.isEmpty,
      updatedAt: DateTime.now(),
    );
    _onChanged.add(null);
  }

  @override
  Future<void> setPackEnabled(SoundboardPack pack, bool enabled) async {
    _explicitPacks[pack.id] = pack.copyWith(
      enabled: enabled,
      updatedAt: DateTime.now(),
    );
    _onChanged.add(null);
  }

  @override
  Future<void> setPackActive(SoundboardPack pack, bool active) async {
    _packActiveOverrides[pack.id] = active;
    _onChanged.add(null);
  }

  @override
  Future<void> deletePack(SoundboardPack pack) async {
    _explicitPacks[pack.id] = pack.copyWith(
      enabled: false,
      deleted: true,
      updatedAt: DateTime.now(),
    );
    for (var index = 0; index < _sounds.length; index++) {
      if (effectivePackIdFor(_sounds[index]) == pack.id) {
        _sounds[index] = _sounds[index].copyWith(enabled: false, deleted: true);
      }
    }
    _onChanged.add(null);
  }

  @override
  Future<void> moveSoundToPack(SoundboardSound sound, String packId) async {
    final index = _sounds.indexWhere((entry) => entry.id == sound.id);
    if (index < 0) {
      return;
    }
    if (packId ==
        SoundboardPack.legacyIdForUploader(_sounds[index].uploadedBy)) {
      _sounds[index] = _sounds[index].copyWith(clearPackId: true);
    } else {
      _sounds[index] = _sounds[index].copyWith(packId: packId);
    }
    _onChanged.add(null);
  }

  @override
  Future<SoundboardSound> uploadSound({
    required String name,
    required String emoji,
    required Uint8List bytes,
    required String mimeType,
    int? durationMs,
    double volume = SoundboardSound.defaultVolume,
    String? packId,
  }) async {
    final sound = SoundboardSound(
      id: 'demo-sound-${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      emoji: emoji,
      mxcUri: Uri.parse('mxc://intergalactic.local/demo-upload'),
      mimeType: mimeType,
      uploadedBy: client.self!.identifier,
      createdAt: DateTime.now(),
      sizeBytes: bytes.length,
      durationMs: durationMs,
      volume: volume,
      packId:
          packId == SoundboardPack.legacyIdForUploader(client.self!.identifier)
          ? null
          : packId,
    );
    _sounds.add(sound);
    _onChanged.add(null);
    return sound;
  }

  @override
  Future<void> updateSoundVolume(SoundboardSound sound, double volume) async {
    final index = _sounds.indexWhere((entry) => entry.id == sound.id);
    if (index < 0) return;
    _sounds[index] = _sounds[index].copyWith(volume: volume);
    _onChanged.add(null);
  }

  @override
  Future<void> deleteSound(SoundboardSound sound) async {
    final index = _sounds.indexWhere((entry) => entry.id == sound.id);
    if (index < 0) return;
    _sounds[index] = _sounds[index].copyWith(deleted: true);
    _onChanged.add(null);
  }

  @override
  Future<void> setJoinSoundForUser(String userId, String? soundId) async {
    _joinSounds[userId] = soundId;
    _onChanged.add(null);
  }

  @override
  Future<SoundboardPlayOutcome> playSound(
    SoundboardSound sound,
    Room room, {
    String source = 'manual',
    String? callSessionId,
  }) async => const SoundboardPlayOutcome.started();

  @override
  Future<void> dispose() async {
    await _onChanged.close();
  }
}

class DemoFileProvider implements FileProvider {
  DemoFileProvider(this.fileIdentifier, this.bytes);

  @override
  final String fileIdentifier;

  final Uint8List bytes;

  @override
  Stream<DownloadProgress>? get onProgressChanged => null;

  @override
  Future<Uint8List?> getFileData() async => bytes;

  @override
  Future<Uri?> resolve() async => null;

  @override
  Future<void> save(String filepath) async {}
}

class DemoDirectMessagesComponent extends DirectMessagesComponent<DemoClient>
    implements DisposableComponent {
  DemoDirectMessagesComponent(this.client);

  @override
  final DemoClient client;

  final List<DemoRoom> _directMessageRooms = [];
  final Map<String, String> _partnerIdsByRoom = {};
  final StreamController<void> _roomsUpdated = StreamController.broadcast();
  final StreamController<void> _highlightedUpdated =
      StreamController.broadcast();

  @override
  List<Room> get directMessageRooms {
    _pruneRemovedRooms();
    return List.unmodifiable(_directMessageRooms);
  }

  @override
  List<Room> get highlightedRoomsList => const [];

  @override
  Stream<void> get onRoomsListUpdated => _roomsUpdated.stream;

  @override
  Stream<void> get onHighlightedRoomsListUpdated => _highlightedUpdated.stream;

  void addDirectMessageRoom(DemoRoom room) {
    final partnerId = getDirectMessagePartnerId(room);
    if (partnerId == null) return;

    if (!_directMessageRooms.any(
      (entry) => entry.identifier == room.identifier,
    )) {
      _directMessageRooms.add(room);
    }
    _partnerIdsByRoom[room.identifier] = partnerId;
    _roomsUpdated.add(null);
  }

  void removeDirectMessageRoom(Room room) {
    final before = _directMessageRooms.length;
    _directMessageRooms.removeWhere(
      (entry) => entry.identifier == room.identifier,
    );
    final removedPartner = _partnerIdsByRoom.remove(room.identifier) != null;
    if (_directMessageRooms.length != before || removedPartner) {
      _roomsUpdated.add(null);
    }
  }

  @override
  bool isRoomDirectMessage(Room room) {
    if (!_isLiveClientRoom(room)) {
      return false;
    }
    return _partnerIdsByRoom.containsKey(room.identifier) ||
        _getJoinedOneToOnePartnerId(room) != null;
  }

  @override
  String? getDirectMessagePartnerId(Room room) {
    if (!_isLiveClientRoom(room)) {
      return null;
    }
    return _partnerIdsByRoom[room.identifier] ??
        _getJoinedOneToOnePartnerId(room);
  }

  @override
  Future<Room?> createDirectMessage(String userId) async {
    final existing = _directMessageRooms
        .where((room) => getDirectMessagePartnerId(room) == userId)
        .firstOrNull;
    if (existing != null) {
      return existing;
    }

    final partner = client.getPerson(userId);
    final createdAt = DateTime.now();
    final createdAtMicros = createdAt.microsecondsSinceEpoch;
    final room = client._createDirectMessageRoom(
      partner: partner,
      identifier: '!demo-dm-$createdAtMicros:intergalactic.local',
      now: createdAt,
      messages: [
        DemoTimelineMessage(
          eventId: '\$demo-dm-created-$createdAtMicros',
          senderId: client.self!.identifier,
          body: 'Started a local-only demo direct message.',
          originServerTs: createdAt,
        ),
      ],
    );
    client._addRoom(room);
    addDirectMessageRoom(room);
    return room;
  }

  String? _getJoinedOneToOnePartnerId(Room room) {
    if (room.isSpecialRoomType) return null;

    final selfId = client.self?.identifier;
    if (selfId == null) return null;

    final members = room.memberIds.toSet();
    if (members.length != 2 || !members.contains(selfId)) {
      return null;
    }

    return members.firstWhere((id) => id != selfId);
  }

  void _pruneRemovedRooms() {
    final liveRoomIds = client.rooms.map((room) => room.identifier).toSet();
    _directMessageRooms.removeWhere(
      (room) => !liveRoomIds.contains(room.identifier),
    );
    _partnerIdsByRoom.removeWhere((roomId, _) => !liveRoomIds.contains(roomId));
  }

  bool _isLiveClientRoom(Room room) {
    return client.rooms.any((entry) => entry.identifier == room.identifier);
  }

  @override
  Future<void> dispose() async {
    await _roomsUpdated.close();
    await _highlightedUpdated.close();
  }
}

class DemoStoryComponent extends StoryComponent<DemoClient>
    implements DisposableComponent {
  DemoStoryComponent(super.client) {
    final now = DateTime.now().toUtc();
    addDemoStory(
      senderId: '@mira:intergalactic.local',
      displayName: 'Mira',
      createdAt: now.subtract(const Duration(minutes: 16)),
      expiresAt: now.add(const Duration(hours: 23, minutes: 44)),
      imageAsset: DemoClient.demoStoryMira,
    );
  }

  final StreamController<void> _storiesChanged = StreamController.broadcast();
  final Map<String, Map<String, StoryItem>> _stories = {};
  final Map<String, Map<String, StoryReaction>> _reactions = {};
  final Set<String> _seen = {};
  int _pendingUploadCount = 0;
  StoryNotificationSettings _notificationSettings =
      const StoryNotificationSettings();

  @override
  Stream<void> get onStoriesChanged => _storiesChanged.stream;

  @override
  Map<String, List<StoryItem>> get activeStoriesByUser {
    final now = DateTime.now().toUtc();
    return Map.unmodifiable({
      for (final entry in _stories.entries)
        entry.key: List<StoryItem>.unmodifiable(
          entry.value.values.where((story) => !story.isExpired(now)).toList()
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
        ),
    });
  }

  @override
  List<StoryItem> activeStoriesForUser(String userId) =>
      activeStoriesByUser[userId] ?? const [];

  @override
  bool hasUnseenStories(String userId) => activeStoriesForUser(
    userId,
  ).any((story) => !_seen.contains(story.seenKey));

  @override
  bool hasPendingStoryUpload(String userId) =>
      userId == client.self?.identifier && _pendingUploadCount > 0;

  @override
  Future<R> trackPendingStoryUpload<R>(Future<R> Function() action) async {
    _pendingUploadCount++;
    _storiesChanged.add(null);
    try {
      return await action();
    } finally {
      if (_pendingUploadCount > 0) {
        _pendingUploadCount--;
      }
      _storiesChanged.add(null);
    }
  }

  @override
  Map<String, List<StoryReaction>> get reactionsByStory => Map.unmodifiable({
    for (final entry in _reactions.entries)
      entry.key: List<StoryReaction>.unmodifiable(
        entry.value.values.toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      ),
  });

  @override
  List<StoryReaction> reactionsForStory(StoryItem story) =>
      reactionsByStory[story.seenKey] ?? const [];

  @override
  StoryReaction? reactionForStoryByCurrentUser(StoryItem story) {
    final ownUserId = client.self?.identifier;
    if (ownUserId == null) {
      return null;
    }
    return _reactions[story.seenKey]?[ownUserId];
  }

  @override
  Future<void> sendStoryReaction(StoryItem story, String reaction) async {
    final ownUserId = client.self?.identifier;
    if (ownUserId == null ||
        story.isOwn ||
        !storyReactionChoices.contains(reaction)) {
      return;
    }

    _reactions.putIfAbsent(story.seenKey, () => {})[ownUserId] = StoryReaction(
      roomId: story.roomId ?? 'demo-room',
      eventId: 'demo-reaction-${DateTime.now().microsecondsSinceEpoch}',
      storyId: story.storyId,
      storyEventId: story.eventId ?? 'demo-story-${story.storyId}',
      storySenderId: story.senderId,
      reactorId: ownUserId,
      reaction: reaction,
      createdAt: DateTime.now().toUtc(),
      mentionedUserIds: [story.senderId],
    );
    _storiesChanged.add(null);
  }

  @override
  StoryNotificationSettings get notificationSettings => _notificationSettings;

  @override
  Future<void> updateNotificationSettings(
    StoryNotificationSettings settings,
  ) async {
    _notificationSettings = settings;
    _storiesChanged.add(null);
  }

  @override
  Future<void> markStoriesSeen(
    String userId,
    Iterable<StoryItem> stories,
  ) async {
    var changed = false;
    for (final story in stories) {
      changed = _seen.add(story.seenKey) || changed;
    }
    if (changed) {
      _storiesChanged.add(null);
    }
  }

  @override
  Future<void> refreshStories() async {
    _pruneExpired();
  }

  @override
  Future<StoryUploadResult> uploadPhotos(List<StoryPhotoUpload> photos) async {
    final targets =
        client
            .getComponent<DemoDirectMessagesComponent>()
            ?.directMessageRooms ??
        const <Room>[];
    if (targets.isEmpty || photos.isEmpty) {
      return StoryUploadResult(
        storyCount: 0,
        sentEventCount: 0,
        targetRoomCount: targets.length,
        failedEventCount: photos.length * targets.length,
      );
    }

    final now = DateTime.now().toUtc();
    var storyCount = 0;
    var failedEventCount = 0;
    for (final (index, photo) in photos.indexed) {
      if (!storyImageSizeIsAllowed(photo.bytes.lengthInBytes)) {
        failedEventCount += targets.length;
        continue;
      }
      final storyId = 'demo-${now.microsecondsSinceEpoch}-$index';
      _addStory(
        StoryItem(
          client: client,
          storyId: storyId,
          senderId: client.self!.identifier,
          createdAt: now,
          expiresAt: now.add(storyLifetime),
          mediaUri: Uri.parse('mxc://demo.local/$storyId'),
          encrypted: false,
          isOwn: true,
          mentionedUserIds: photo.mentionedUserIds,
          image: MemoryImage(photo.bytes),
          rawContent: _demoStoryContent(
            storyId: storyId,
            name: photo.name,
            createdAt: now,
            expiresAt: now.add(storyLifetime),
            mimeType: photo.mimeType,
            size: photo.bytes.length,
            mentionedUserIds: photo.mentionedUserIds,
          ),
        ),
      );
      storyCount++;
    }

    _storiesChanged.add(null);
    return StoryUploadResult(
      storyCount: storyCount,
      sentEventCount: storyCount * targets.length,
      targetRoomCount: targets.length,
      failedEventCount: failedEventCount,
    );
  }

  @override
  Future<StoryUploadResult> uploadVideos(List<StoryVideoUpload> videos) async {
    final targets =
        client
            .getComponent<DemoDirectMessagesComponent>()
            ?.directMessageRooms ??
        const <Room>[];
    if (targets.isEmpty || videos.isEmpty) {
      return StoryUploadResult(
        storyCount: 0,
        sentEventCount: 0,
        targetRoomCount: targets.length,
        failedEventCount: videos.length * targets.length,
      );
    }

    final now = DateTime.now().toUtc();
    var storyCount = 0;
    var failedEventCount = 0;
    for (final (index, video) in videos.indexed) {
      if (!video.hasValidSelection ||
          !video.usesFullSource ||
          !storyVideoSizeIsAllowed(video.sizeBytes)) {
        failedEventCount += targets.length;
        continue;
      }
      final storyId = 'demo-video-${now.microsecondsSinceEpoch}-$index';
      _addStory(
        StoryItem(
          client: client,
          storyId: storyId,
          senderId: client.self!.identifier,
          createdAt: now,
          expiresAt: now.add(storyLifetime),
          mediaUri: Uri.parse('mxc://demo.local/$storyId'),
          mediaType: StoryMediaType.video,
          encrypted: false,
          isOwn: true,
          mimeType: video.mimeType,
          size: video.sizeBytes,
          durationMs: video.duration.inMilliseconds,
          width: video.width,
          height: video.height,
          displayWidth: video.displayWidth,
          displayHeight: video.displayHeight,
          hasBakedLetterbox: video.hasBakedLetterbox,
          trimStartMs: video.trimStart.inMilliseconds,
          trimEndMs: video.effectiveTrimEnd.inMilliseconds,
          overlays: video.overlays,
          mentionedUserIds: video.mentionedUserIds,
          backgroundColor: video.backgroundColor,
          backgroundGradientColor: video.backgroundGradientColor,
          backgroundMode: video.backgroundMode,
          fitMode: video.fitMode,
          canvasMode: StoryVideoCanvasMode.portrait,
          thumbnail: video.thumbnailBytes == null
              ? null
              : MemoryImage(video.thumbnailBytes!),
          video: SystemFileProvider(video.path),
          rawContent: _demoVideoStoryContent(
            storyId: storyId,
            name: video.name,
            createdAt: now,
            expiresAt: now.add(storyLifetime),
            mimeType: video.mimeType,
            size: video.sizeBytes,
            durationMs: video.duration.inMilliseconds,
            width: video.width,
            height: video.height,
            displayWidth: video.displayWidth,
            displayHeight: video.displayHeight,
            hasBakedLetterbox: video.hasBakedLetterbox,
            trimStartMs: video.trimStart.inMilliseconds,
            trimEndMs: video.effectiveTrimEnd.inMilliseconds,
            backgroundColor: video.backgroundColor,
            backgroundGradientColor: video.backgroundGradientColor,
            backgroundMode: video.backgroundMode,
            fitMode: video.fitMode,
            canvasMode: StoryVideoCanvasMode.portrait,
            overlays: video.overlays,
            mentionedUserIds: video.mentionedUserIds,
          ),
        ),
      );
      storyCount++;
    }

    _storiesChanged.add(null);
    return StoryUploadResult(
      storyCount: storyCount,
      sentEventCount: storyCount * targets.length,
      targetRoomCount: targets.length,
      failedEventCount: failedEventCount,
    );
  }

  @override
  Future<void> deleteStory(String storyId) async {
    var changed = false;
    for (final stories in _stories.values) {
      changed = stories.remove(storyId) != null || changed;
    }
    for (final storyKey in _reactions.keys.toList()) {
      if (storyKey.endsWith('|$storyId')) {
        _reactions.remove(storyKey);
        changed = true;
      }
    }
    if (changed) {
      _storiesChanged.add(null);
    }
  }

  void addDemoStory({
    required String senderId,
    required String displayName,
    required DateTime createdAt,
    required DateTime expiresAt,
    required String imageAsset,
  }) {
    final storyId = 'demo-$senderId-${createdAt.microsecondsSinceEpoch}';
    _addStory(
      StoryItem(
        client: client,
        storyId: storyId,
        senderId: senderId,
        createdAt: createdAt,
        expiresAt: expiresAt,
        mediaUri: Uri.parse('mxc://demo.local/$storyId'),
        encrypted: false,
        isOwn: senderId == client.self?.identifier,
        image: AssetImage(imageAsset),
        rawContent: _demoStoryContent(
          storyId: storyId,
          name: '$displayName story',
          createdAt: createdAt,
          expiresAt: expiresAt,
          mimeType: 'image/jpeg',
          size: _demoStoryImageBytes.length,
          mentionedUserIds: const [],
        ),
      ),
    );
  }

  void _addStory(StoryItem item) {
    _stories.putIfAbsent(item.senderId, () => {})[item.storyId] = item;
  }

  void _pruneExpired() {
    final now = DateTime.now().toUtc();
    var changed = false;
    for (final senderId in _stories.keys.toList()) {
      final stories = _stories[senderId]!;
      final before = stories.length;
      stories.removeWhere((_, story) => story.isExpired(now));
      if (stories.isEmpty) {
        _stories.remove(senderId);
      }
      changed = changed || before != stories.length;
    }
    if (changed) {
      _storiesChanged.add(null);
    }
  }

  @override
  Future<void> dispose() async {
    await _storiesChanged.close();
  }
}

Map<String, Object?> _demoStoryContent({
  required String storyId,
  required String name,
  required DateTime createdAt,
  required DateTime expiresAt,
  required String? mimeType,
  required int size,
  Iterable<Object?> mentionedUserIds = const [],
}) {
  final mentions = normalizeStoryMentionUserIds(mentionedUserIds);
  return {
    'v': 1,
    'story_id': storyId,
    'created_at': createdAt.millisecondsSinceEpoch,
    'expires_at': expiresAt.millisecondsSinceEpoch,
    'msgtype': 'm.image',
    'body': name,
    'filename': name,
    'url': 'mxc://demo.local/$storyId',
    'm.mentions': {'user_ids': mentions},
    'info': {'mimetype': mimeType ?? 'image/png', 'size': size, 'w': 1, 'h': 1},
  };
}

Map<String, Object?> _demoVideoStoryContent({
  required String storyId,
  required String name,
  required DateTime createdAt,
  required DateTime expiresAt,
  required String? mimeType,
  required int size,
  required int durationMs,
  required int? width,
  required int? height,
  required int? displayWidth,
  required int? displayHeight,
  required bool hasBakedLetterbox,
  required int trimStartMs,
  required int trimEndMs,
  required int backgroundColor,
  required int backgroundGradientColor,
  required StoryBackgroundMode backgroundMode,
  required StoryVideoFitMode fitMode,
  required StoryVideoCanvasMode canvasMode,
  Iterable<StoryMediaOverlay> overlays = const [],
  Iterable<Object?> mentionedUserIds = const [],
}) {
  final mentions = normalizeStoryMentionUserIds(mentionedUserIds);
  return {
    'v': 1,
    'story_id': storyId,
    'media_type': StoryMediaType.video.jsonValue,
    'created_at': createdAt.millisecondsSinceEpoch,
    'expires_at': expiresAt.millisecondsSinceEpoch,
    'duration_ms': durationMs,
    'trim_start_ms': trimStartMs,
    'trim_end_ms': trimEndMs,
    'background_color': backgroundColor,
    'background_gradient_color': backgroundGradientColor,
    'background_mode': backgroundMode.jsonValue,
    'media_fit': fitMode.jsonValue,
    'canvas_aspect': StoryVideoCanvasMode.portrait.jsonValue,
    if (displayWidth != null && displayHeight != null)
      'display_width': displayWidth,
    if (displayWidth != null && displayHeight != null)
      'display_height': displayHeight,
    if (hasBakedLetterbox && displayWidth != null && displayHeight != null)
      'baked_letterbox': true,
    'overlays': overlays.map((overlay) => overlay.toJson()).toList(),
    'msgtype': 'm.video',
    'body': name,
    'filename': name,
    'url': 'mxc://demo.local/$storyId',
    'm.mentions': {'user_ids': mentions},
    'info': {
      'mimetype': mimeType ?? 'video/mp4',
      'size': size,
      if (width != null) 'w': width,
      if (height != null) 'h': height,
      'duration': durationMs,
    },
  };
}

final Uint8List _demoStoryImageBytes = Uint8List.fromList(const [
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
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0xF8,
  0xCF,
  0xC0,
  0xF0,
  0x1F,
  0x00,
  0x05,
  0x00,
  0x01,
  0xFF,
  0xA5,
  0x5B,
  0xA7,
  0x69,
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

class DemoEmoticonComponent
    implements EmoticonComponent<DemoClient>, DisposableComponent {
  DemoEmoticonComponent(this.client);

  @override
  final DemoClient client;

  final StreamController<void> _stateChanged = StreamController.broadcast();
  final List<String> _packOrder = [];
  late final List<EmoticonPack> _personalPacks = [
    DemoEmoticonPack(
      identifier: '${client.identifier}:quick-reactions',
      displayName: 'Demo Quick Reactions',
      ownerId: client.self!.identifier,
      ownerDisplayName: client.self!.displayName,
      isGloballyAvailable: true,
      icon: Icons.favorite_rounded,
      emotes: const [
        DemoEmoticon(slug: '💚', shortcode: 'green_heart', key: '💚'),
        DemoEmoticon(slug: '✨', shortcode: 'sparkle', key: '✨'),
        DemoEmoticon(slug: '🚀', shortcode: 'rocket', key: '🚀'),
        DemoEmoticon(slug: '🪐', shortcode: 'planet', key: '🪐'),
      ],
    ),
  ];

  @override
  bool get canCreatePack => true;

  @override
  Stream<void> get onStateChanged => _stateChanged.stream;

  @override
  List<EmoticonPack> globalPacks() => availablePacks
      .where((pack) => pack.isGloballyAvailable)
      .toList(growable: false);

  @override
  List<EmoticonPack> get ownedPacks => List.unmodifiable(_personalPacks);

  @override
  List<EmoticonPack> get availablePacks => _orderPacks([
    ..._personalPacks,
    ..._joinedRoomPacks(),
    ..._joinedSpacePacks(),
  ]);

  List<EmoticonPack> _orderPacks(List<EmoticonPack> packs) {
    final orderIndex = <String, int>{};
    for (final key in _packOrder) {
      if (key.isNotEmpty) {
        orderIndex.putIfAbsent(key, () => orderIndex.length);
      }
    }
    final indexed = packs.indexed.toList();
    indexed.sort((a, b) {
      final aOrder = orderIndex[a.$2.orderKey];
      final bOrder = orderIndex[b.$2.orderKey];
      if (aOrder != null && bOrder != null) {
        return aOrder.compareTo(bOrder);
      }
      if (aOrder != null) return -1;
      if (bOrder != null) return 1;
      return a.$1.compareTo(b.$1);
    });
    return indexed.map((entry) => entry.$2).toList(growable: false);
  }

  @override
  Future<void> setPackOrder(List<String> orderKeys) async {
    _packOrder
      ..clear()
      ..addAll(orderKeys.where((key) => key.isNotEmpty).toSet());
    _stateChanged.add(null);
  }

  List<EmoticonPack> _joinedRoomPacks() {
    return client.rooms
        .map((room) => room.getComponent<RoomEmoticonComponent>())
        .whereType<RoomEmoticonComponent>()
        .expand((component) => component.ownedPacks)
        .toList(growable: false);
  }

  List<EmoticonPack> _joinedSpacePacks() {
    return client.spaces
        .map((space) => space.getComponent<SpaceEmoticonComponent>())
        .whereType<SpaceEmoticonComponent>()
        .expand((component) => component.ownedPacks)
        .toList(growable: false);
  }

  @override
  Future<void> createEmoticonPack(String name, Uint8List? avatarData) async {
    _personalPacks.add(
      DemoEmoticonPack(
        identifier:
            '${client.identifier}:personal-${DateTime.now().microsecondsSinceEpoch}',
        displayName: name,
        ownerId: client.self!.identifier,
        ownerDisplayName: client.self!.displayName,
        icon: Icons.emoji_emotions_outlined,
        emotes: const [],
      ),
    );
    _stateChanged.add(null);
  }

  @override
  Future<void> importEmoticonPack(
    String name,
    int avatarIndex,
    List<String> names,
    List<Uint8List> imageDatas,
  ) async {
    _personalPacks.add(
      DemoEmoticonPack(
        identifier:
            '${client.identifier}:import-${DateTime.now().microsecondsSinceEpoch}',
        displayName: name,
        ownerId: client.self!.identifier,
        ownerDisplayName: client.self!.displayName,
        icon: Icons.inventory_2_outlined,
        emotes: [
          for (final name in names)
            DemoEmoticon(slug: name, shortcode: name, key: name),
        ],
      ),
    );
    _stateChanged.add(null);
  }

  @override
  Future<void> deleteEmoticonPack(EmoticonPack pack) async {
    _personalPacks.removeWhere((entry) => entry.identifier == pack.identifier);
    _stateChanged.add(null);
  }

  @override
  Future<void> dispose() async {
    await _stateChanged.close();
  }
}

class DemoRecentEmoticonComponent
    implements RecentEmoticonComponent<DemoClient> {
  DemoRecentEmoticonComponent(this.client);

  @override
  final DemoClient client;

  late List<Emoticon> _quickReactions = [
    UnicodeEmoticon('💚'),
    UnicodeEmoticon('✨'),
    UnicodeEmoticon('🚀'),
    UnicodeEmoticon('😂'),
    UnicodeEmoticon('👍'),
    UnicodeEmoticon('❤️'),
    UnicodeEmoticon('🪐'),
    UnicodeEmoticon('🔥'),
  ];
  final List<Emoticon> _recentStickers = [];

  @override
  Future<void> clear() async {
    _recentStickers.clear();
  }

  @override
  List<Emoticon> getQuickReactionEmoticon(Room? room) =>
      _quickReactions.take(RecentEmoticonComponent.quickReactionCount).toList();

  @override
  List<Emoticon> getRecentReactionEmoticon(Room room) =>
      getQuickReactionEmoticon(room);

  @override
  List<Emoticon> getRecentTypedEmoticon(Room? room) =>
      getQuickReactionEmoticon(room);

  @override
  List<Emoticon> getRecentStickerEmoticon(Room? room) =>
      List.unmodifiable(_recentStickers);

  @override
  Future<void> reactedEmoticon(Room room, Emoticon emoticon) async {}

  @override
  Future<void> setQuickReactionEmoticon(
    int index,
    Emoticon emoticon, {
    Room? room,
  }) async {
    if (index < 0 || index >= RecentEmoticonComponent.quickReactionCount) {
      return;
    }

    final next = List<Emoticon>.from(_quickReactions);
    while (next.length <= index) {
      next.add(UnicodeEmoticon('✨'));
    }
    next[index] = emoticon;
    _quickReactions = next;
  }

  @override
  Future<void> typedEmoticon(Room room, Emoticon emoticon) async {}

  @override
  Future<void> stickerEmoticon(Room room, Emoticon emoticon) async {
    _recentStickers
      ..remove(emoticon)
      ..insert(0, emoticon);
    if (_recentStickers.length > 30) {
      _recentStickers.removeLast();
    }
  }
}

class DemoRoomEmoticonComponent
    implements
        RoomEmoticonComponent<DemoClient, DemoRoom>,
        DisposableComponent {
  DemoRoomEmoticonComponent(this.client, this.room);

  @override
  final DemoClient client;

  @override
  final DemoRoom room;

  final StreamController<void> _stateChanged = StreamController.broadcast();
  late final List<EmoticonPack> _packs = [
    DemoEmoticonPack(
      identifier: '${room.identifier}:galaxy',
      displayName: 'Galaxy Emoji',
      ownerId: client.self!.identifier,
      ownerDisplayName: client.self!.displayName,
      isGloballyAvailable: true,
      icon: Icons.auto_awesome_outlined,
      emotes: const [
        DemoEmoticon(slug: '✨', shortcode: 'sparkle', key: '✨'),
        DemoEmoticon(slug: '🚀', shortcode: 'rocket', key: '🚀'),
        DemoEmoticon(slug: '🪐', shortcode: 'planet', key: '🪐'),
      ],
    ),
    DemoEmoticonPack(
      identifier: '${room.identifier}:cats',
      displayName: 'Cosmic Cats',
      ownerId: '@mira:intergalactic.local',
      ownerDisplayName: 'Mira',
      icon: Icons.pets_outlined,
      emotes: const [
        DemoEmoticon(
          slug: '🐾',
          shortcode: 'catwave',
          key: '🐾',
          usage: EmoticonUsage.sticker,
        ),
        DemoEmoticon(
          slug: '💤',
          shortcode: 'catnap',
          key: '💤',
          usage: EmoticonUsage.sticker,
        ),
      ],
    ),
  ];

  @override
  List<EmoticonPack> globalPacks() =>
      _packs.where((pack) => pack.isGloballyAvailable).toList();

  @override
  List<EmoticonPack> get ownedPacks => _packs;

  @override
  List<EmoticonPack> get availablePacks => _packs;

  @override
  Future<void> setPackOrder(List<String> orderKeys) async {
    final orderIndex = <String, int>{};
    for (final key in orderKeys) {
      if (key.isNotEmpty) {
        orderIndex.putIfAbsent(key, () => orderIndex.length);
      }
    }
    final indexed = _packs.indexed.toList();
    indexed.sort((a, b) {
      final aOrder = orderIndex[a.$2.orderKey];
      final bOrder = orderIndex[b.$2.orderKey];
      if (aOrder != null && bOrder != null) {
        return aOrder.compareTo(bOrder);
      }
      if (aOrder != null) return -1;
      if (bOrder != null) return 1;
      return a.$1.compareTo(b.$1);
    });
    _packs
      ..clear()
      ..addAll(indexed.map((entry) => entry.$2));
    _stateChanged.add(null);
  }

  @override
  List<EmoticonPack> get availableEmoji =>
      _packs.where((pack) => pack.isEmojiPack).toList();

  @override
  List<EmoticonPack> get availableStickers =>
      _packs.where((pack) => pack.isStickerPack).toList();

  @override
  bool get canCreatePack => true;

  @override
  Stream<void> get onStateChanged => _stateChanged.stream;

  @override
  Future<void> createEmoticonPack(String name, Uint8List? avatarData) async {}

  @override
  Future<void> importEmoticonPack(
    String name,
    int avatarIndex,
    List<String> names,
    List<Uint8List> imageDatas,
  ) async {}

  @override
  Future<void> deleteEmoticonPack(EmoticonPack pack) async {}

  @override
  Future<TimelineEvent?> sendSticker(
    Emoticon sticker,
    TimelineEvent? inReplyTo,
  ) async => null;

  @override
  Future<void> dispose() async {
    await _stateChanged.close();
  }
}

/// Supplies the bundled demo space heading image. Offline demo mode has no
/// homeserver to fetch a banner from, so the banner is a local asset and the
/// edit paths are inert.
class DemoSpaceBannerComponent
    implements SpaceBannerComponent<DemoClient, DemoSpace> {
  DemoSpaceBannerComponent(this.client, this.space, {this.bannerAsset});

  @override
  final DemoClient client;

  @override
  final DemoSpace space;

  final String? bannerAsset;

  @override
  ImageProvider? get banner =>
      bannerAsset == null ? null : AssetImage(bannerAsset!);

  @override
  bool get canEditBanner => false;

  @override
  Future<void> setBanner(Uint8List data, {String? mimeType}) async {}

  @override
  Future<void> removeBanner() async {}
}

class DemoSpaceEmoticonComponent
    implements
        SpaceEmoticonComponent<DemoClient, DemoSpace>,
        DisposableComponent {
  DemoSpaceEmoticonComponent(this.client, this.space);

  @override
  final DemoClient client;

  @override
  final DemoSpace space;

  final StreamController<void> _stateChanged = StreamController.broadcast();
  late final List<EmoticonPack> _packs = [
    DemoEmoticonPack(
      identifier: '${space.identifier}:community',
      displayName: 'Demo Space Pack',
      ownerId: space.identifier,
      ownerDisplayName: space.displayName,
      isGloballyAvailable: false,
      icon: Icons.grid_view_rounded,
      emotes: const [
        DemoEmoticon(slug: '🌌', shortcode: 'galaxy', key: '🌌'),
        DemoEmoticon(slug: '🛰️', shortcode: 'satellite', key: '🛰️'),
        DemoEmoticon(slug: '☄️', shortcode: 'comet', key: '☄️'),
      ],
    ),
  ];

  @override
  bool get canCreatePack => true;

  @override
  Stream<void> get onStateChanged => _stateChanged.stream;

  @override
  List<EmoticonPack> globalPacks() =>
      _packs.where((pack) => pack.isGloballyAvailable).toList();

  @override
  List<EmoticonPack> get ownedPacks => _packs;

  @override
  List<EmoticonPack> get availablePacks => _packs;

  @override
  Future<void> setPackOrder(List<String> orderKeys) async {
    final orderIndex = <String, int>{};
    for (final key in orderKeys) {
      if (key.isNotEmpty) {
        orderIndex.putIfAbsent(key, () => orderIndex.length);
      }
    }
    final indexed = _packs.indexed.toList();
    indexed.sort((a, b) {
      final aOrder = orderIndex[a.$2.orderKey];
      final bOrder = orderIndex[b.$2.orderKey];
      if (aOrder != null && bOrder != null) {
        return aOrder.compareTo(bOrder);
      }
      if (aOrder != null) return -1;
      if (bOrder != null) return 1;
      return a.$1.compareTo(b.$1);
    });
    _packs
      ..clear()
      ..addAll(indexed.map((entry) => entry.$2));
    _stateChanged.add(null);
  }

  @override
  Future<void> createEmoticonPack(String name, Uint8List? avatarData) async {}

  @override
  Future<void> deleteEmoticonPack(EmoticonPack pack) async {}

  @override
  Future<void> importEmoticonPack(
    String name,
    int avatarIndex,
    List<String> names,
    List<Uint8List> imageDatas,
  ) async {}

  @override
  Future<void> dispose() async {
    await _stateChanged.close();
  }
}

class DemoEmoticonPack implements EmoticonPack {
  DemoEmoticonPack({
    required this.identifier,
    required this.displayName,
    required this.ownerId,
    required this.ownerDisplayName,
    required List<Emoticon> emotes,
    this.isGloballyAvailable = false,
    this.icon,
  }) : _emotes = List.of(emotes);

  @override
  final String identifier;

  @override
  final String displayName;

  @override
  final String ownerId;

  @override
  final String ownerDisplayName;

  @override
  String get orderKey => '$ownerId\u0000$identifier';

  @override
  bool isGloballyAvailable;

  @override
  final IconData? icon;

  final List<Emoticon> _emotes;

  @override
  String get attribution => 'Offline demo pack';

  @override
  List<Emoticon> get emotes => List.unmodifiable(_emotes);

  @override
  List<Emoticon> get emoji =>
      _emotes.where((emote) => emote.isEmoji).toList(growable: false);

  @override
  List<Emoticon> get stickers =>
      _emotes.where((emote) => emote.isSticker).toList(growable: false);

  @override
  ImageProvider? get image => null;

  @override
  EmoticonUsage get usage => EmoticonUsage.all;

  @override
  bool get isStickerPack => stickers.isNotEmpty;

  @override
  bool get isEmojiPack => emoji.isNotEmpty;

  @override
  List<String> getShortcodes() =>
      _emotes.map((emote) => emote.shortcode ?? emote.slug).toList();

  @override
  Emoticon? getByShortcode(String shortcode) => _emotes
      .where((emote) => emote.shortcode == shortcode || emote.slug == shortcode)
      .firstOrNull;

  @override
  Future<void> addEmoticon({
    required String slug,
    String? shortcode,
    required Uint8List data,
    String? mimeType,
    EmoticonUsage usage = EmoticonUsage.all,
  }) async {
    _emotes.add(
      DemoEmoticon(
        slug: slug,
        shortcode: shortcode,
        key: shortcode ?? slug,
        usage: usage,
      ),
    );
  }

  @override
  Future<void> deleteEmoticon(Emoticon emoticon) async {
    _emotes.removeWhere((entry) => entry.key == emoticon.key);
  }

  @override
  Future<void> markAsGlobal(bool isGlobal) async {
    isGloballyAvailable = isGlobal;
  }

  @override
  Future<void> setPackUsage(EmoticonUsage usage) async {}

  @override
  Future<void> reorderEmoticons(List<String> shortcodes) async {
    final remaining = List<Emoticon>.of(_emotes);
    final reordered = <Emoticon>[];
    for (final shortcode in shortcodes) {
      final index = remaining.indexWhere(
        (emoticon) => emoticon.shortcode == shortcode,
      );
      if (index >= 0) {
        reordered.add(remaining.removeAt(index));
      }
    }
    reordered.addAll(remaining);
    _emotes
      ..clear()
      ..addAll(reordered);
  }

  @override
  Future<void> updateEmoticon({
    String? slug,
    String? shortcode,
    Uint8List? data,
    String? mimeType,
    EmoticonUsage? usage,
    required Emoticon previous,
  }) async {}

  @override
  Future<void> updatePack({
    EmoticonUsage? usage,
    String? name,
    Uint8List? imageData,
  }) async {}
}

class DemoEmoticon implements Emoticon {
  const DemoEmoticon({
    required this.slug,
    required this.shortcode,
    required this.key,
    this.usage = EmoticonUsage.all,
  });

  @override
  ImageProvider? get image => null;

  @override
  final String slug;

  @override
  final String? shortcode;

  @override
  final String key;

  @override
  final EmoticonUsage usage;

  @override
  bool get isEmoji =>
      usage == EmoticonUsage.emoji || usage == EmoticonUsage.all;

  @override
  bool get isSticker =>
      usage == EmoticonUsage.sticker || usage == EmoticonUsage.all;
}

class DemoProfileComponent implements UserProfileComponent<DemoClient> {
  DemoProfileComponent(this.client);

  @override
  final DemoClient client;

  @override
  Future<Profile> getProfile(String identifier) async =>
      client.getPerson(identifier);

  @override
  Future<void> setBanner(Uint8List bytes) async {}

  @override
  Future<void> setProfileColorScheme(
    Color color,
    Brightness brightness,
  ) async {}

  @override
  Future<void> setStatus(String? status) async {}

  @override
  Future<void> setTimezone(String timezone) async {}

  @override
  Future<void> setBio(String bio) async {}

  @override
  Future<void> setPronouns(List<String> pronouns) async {}

  @override
  Future<void> removeBio() async {}

  @override
  Future<void> removeBanner() async {}

  @override
  Future<void> removeTimezone() async {}

  @override
  Future<List<ProfileBadge>> getAvailableBadges() async => const [];

  @override
  Future<void> setProfileBadges(List<ProfileBadge> badges) async {}
}

class _DemoPerson implements Profile, Member, Peer {
  _DemoPerson({
    required this.identifier,
    required this.userName,
    required this.displayName,
    this.detail,
    required this.defaultColor,
    this.avatarAsset,
  });

  /// Optional bundled demo profile picture. Offline demo mode has no
  /// homeserver to fetch avatars from, so demo people point at a local asset.
  final String? avatarAsset;

  @override
  final String identifier;

  @override
  final String userName;

  @override
  String displayName;

  @override
  final String? detail;

  @override
  String? get avatarId => avatarAsset;

  @override
  ImageProvider? get avatar =>
      avatarAsset == null ? null : AssetImage(avatarAsset!);

  @override
  ImageProvider? get banner => null;

  @override
  final Color defaultColor;

  @override
  String get source => identifier;
}

class DemoPermissions extends Permissions {
  DemoPermissions();

  @override
  bool get canSendMessage => true;

  @override
  bool get canEditName => true;

  @override
  bool get canEditTopic => true;

  @override
  bool get canChangeNotificationSettings => true;

  @override
  bool get canChangeOwnNickname => true;

  @override
  bool get canChangeOtherNicknames => true;

  @override
  bool get canUserEditMessages => true;

  @override
  bool get canInviteUser => false;
}

class DemoRole implements Role {
  const DemoRole(this.name, this.icon);

  @override
  final String name;

  @override
  final IconData icon;
}

class _DemoCalendarConfig extends calendar_widget.MatrixCalendarConfig {
  _DemoCalendarConfig(this.room);

  final DemoRoom room;

  @override
  ImageProvider? getUserAvatar(String userId) =>
      room.getMemberOrFallback(userId).avatar;

  @override
  String? getUserDisplayname(String userId) =>
      room.getMemberOrFallback(userId).displayName;

  @override
  Color getColorFromUser(String userId) => room.getColorOfUser(userId);
}

class _DemoMatrixWidgetApi implements MatrixWidgetApi {
  _DemoMatrixWidgetApi(this.userId);

  @override
  final String userId;

  final StreamController<void> _onReady = StreamController.broadcast();
  final Map<String, Map<String, dynamic>? Function(Map<String, dynamic>)>
  _callbacks = {};

  @override
  Future<void> requestCapabilities(List<String> capabilities) async {}

  @override
  void start() {
    _onReady.add(null);
  }

  @override
  void stop() {}

  @override
  Stream<void> get onReady => _onReady.stream;

  @override
  Future<Map<String, dynamic>> sendAction(
    String fromWidgetAction,
    Map<String, dynamic> data,
  ) async {
    if (fromWidgetAction == 'org.matrix.msc2762.read_relations') {
      return {'chunk': const []};
    }
    return {
      'event_id':
          r'$demo-calendar-action-' +
          DateTime.now().microsecondsSinceEpoch.toString(),
    };
  }

  @override
  void onAction(
    String toWidgetAction,
    Map<String, dynamic>? Function(Map<String, dynamic> data) callback, {
    preventDefaultHandler = false,
  }) {
    _callbacks[toWidgetAction] = callback;
  }
}

Color _colorFor(String seed) {
  const colors = [
    Color(0xFF2FB5FF),
    Color(0xFFFF9F1C),
    Color(0xFF7CFFB2),
    Color(0xFFE86AFF),
    Color(0xFFFF6B6B),
    Color(0xFFB6E880),
    Color(0xFFFFC857),
  ];
  return colors[seed.hashCode.abs() % colors.length];
}

final Uint8List _demoImageBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
);

String _demoPhotoAssetForId(String id) {
  const demoDir = 'assets/images/placeholders/demo';

  if (id == r'$demo-photo-single-1') {
    return '$demoDir/vault-starlight-table.jpg';
  }

  if (id == DemoClient.demoPhotoStackRootEventId) {
    return '$demoDir/vault-game-night-1.jpg';
  }

  if (id == r'$demo-photo-stack-2') {
    return '$demoDir/vault-game-night-2.jpg';
  }

  if (id == r'$demo-photo-stack-3') {
    return '$demoDir/vault-game-night-3.jpg';
  }

  return '$demoDir/vault-extra.jpg';
}
