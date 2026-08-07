import 'dart:async';
import 'dart:collection';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/message_effects/message_effect_particles.dart';
import 'package:intergalactic/ui/molecules/overlapping_panels.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

class EventBus {
  /// First string is room id, Second string is client id
  static StreamController<(String, String?)> openRoom =
      StreamController<(String, String?)>.broadcast();
  static final ListQueue<(String, String?)> _pendingOpenRoomQueue =
      ListQueue<(String, String?)>();
  static final Set<String> _notificationOpenRoomKeys = {};
  static final Set<String> _shortcutOpenRoomKeys = {};

  static void openRoomFromNotification((String, String?) room) {
    _notificationOpenRoomKeys.add(_openRoomKey(room));
    if (!openRoom.hasListener) {
      _pendingOpenRoomQueue.addLast(room);
      return;
    }
    openRoom.add(room);
  }

  static void openRoomFromShortcut((String, String?) room) {
    _shortcutOpenRoomKeys.add(_openRoomKey(room));
    if (!openRoom.hasListener) {
      _pendingOpenRoomQueue.addLast(room);
      return;
    }
    openRoom.add(room);
  }

  static (String, String?)? takePendingOpenRoom() {
    if (_pendingOpenRoomQueue.isEmpty) {
      return null;
    }
    return _pendingOpenRoomQueue.removeFirst();
  }

  static bool consumeNotificationOpenRoom((String, String?) room) {
    return _notificationOpenRoomKeys.remove(_openRoomKey(room));
  }

  static bool consumeShortcutOpenRoom((String, String?) room) {
    return _shortcutOpenRoomKeys.remove(_openRoomKey(room));
  }

  static String _openRoomKey((String, String?) room) {
    return "${room.$2 ?? ''}\u0000${room.$1}";
  }

  static StreamController<StoryOpenRequest> openStory =
      StreamController<StoryOpenRequest>.broadcast();
  static StreamController<StoryOpenRequest> onStoryOpened =
      StreamController<StoryOpenRequest>.broadcast();
  static final ListQueue<StoryOpenRequest> _pendingOpenStoryQueue =
      ListQueue<StoryOpenRequest>();
  static final Set<String> _notificationOpenStoryKeys = {};

  static void openStoryFromNotification(StoryOpenRequest request) {
    _notificationOpenStoryKeys.add(request.routeKey);
    if (!openStory.hasListener) {
      _pendingOpenStoryQueue.addLast(request);
      return;
    }
    openStory.add(request);
  }

  static StoryOpenRequest? takePendingOpenStory() {
    if (_pendingOpenStoryQueue.isEmpty) {
      return null;
    }
    return _pendingOpenStoryQueue.removeFirst();
  }

  static bool consumeNotificationOpenStory(StoryOpenRequest request) {
    return _notificationOpenStoryKeys.remove(request.routeKey);
  }

  /// First string is space id or address, Second string is client id
  static StreamController<(String, String?)> openSpace =
      StreamController<(String, String?)>.broadcast();
  static final ListQueue<(String, String?)> _pendingOpenSpaceQueue =
      ListQueue<(String, String?)>();

  static void openSpaceFromShortcut((String, String?) space) {
    if (!openSpace.hasListener) {
      _pendingOpenSpaceQueue.addLast(space);
      return;
    }
    openSpace.add(space);
  }

  static (String, String?)? takePendingOpenSpace() {
    if (_pendingOpenSpaceQueue.isEmpty) {
      return null;
    }
    return _pendingOpenSpaceQueue.removeFirst();
  }

  /// First string is user id, Second string is client id, third string is context room
  static StreamController<(String, String, String?)> openUserProfile =
      StreamController<(String, String, String?)>.broadcast();

  /// 0] Client Id
  /// 1] Room Id
  /// 2] Thread Root Event Id
  static StreamController<(String, String, String)> openThread =
      StreamController<(String, String, String)>.broadcast();

  static StreamController<void> closeThread = StreamController.broadcast();

  static StreamController<Client?> setFilterClient =
      StreamController.broadcast();

  static StreamController<bool> onTextFieldFocused =
      StreamController.broadcast();

  /// Called when the user initially logs in to the app, or on app startup when atleast one user account is already logged in
  static StreamController<BuildContext> onLoggedIn =
      StreamController<BuildContext>.broadcast();

  static StreamController<DropDoneDetails> onFileDropped =
      StreamController<DropDoneDetails>.broadcast();

  static StreamController<Space?> onSelectedSpaceChanged =
      StreamController<Space?>.broadcast();

  static StreamController<Room?> onSelectedRoomChanged =
      StreamController<Room?>.broadcast();

  static StreamController<void> startSearch = StreamController.broadcast();

  static StreamController<void> openPinnedMessages =
      StreamController.broadcast();

  static StreamController<void> openCalendar = StreamController.broadcast();

  static StreamController<void> toggleRoomSidePanel =
      StreamController.broadcast();

  static StreamController<String> jumpToEvent = StreamController.broadcast();

  static StreamController<void> focusTimeline = StreamController.broadcast();

  static StreamController<void> wrapComposerSelectionInBrackets =
      StreamController.broadcast();

  static StreamController<MessageEffectParticles> doMessageEffect =
      StreamController.broadcast();

  static StreamController<ScopePopped> onPopInvoked =
      StreamController.broadcast(sync: true);
}

class ScopePopped {
  RevealSide? currentMobileSide;
  bool handled = false;
}

class StoryOpenRequest {
  const StoryOpenRequest({
    required this.roomId,
    required this.clientId,
    required this.storySenderId,
    required this.storyId,
    this.storyEventId,
  });

  final String roomId;
  final String clientId;
  final String storySenderId;
  final String storyId;
  final String? storyEventId;

  (String, String?) get roomRoute => (roomId, clientId);

  String get routeKey =>
      "$clientId\u0000$roomId\u0000$storySenderId\u0000$storyId\u0000${storyEventId ?? ''}";
}
