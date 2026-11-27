import 'dart:async';
import 'dart:collection';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_draft.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_payload.dart';
import 'package:intergalactic/client/components/message_effects/message_effect_particles.dart';
import 'package:intergalactic/ui/molecules/overlapping_panels.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

class EventBus {
  /// A selected inbound share bound to its exact room/client pair. This is not a room-open request.
  static final StreamController<InboundShareDraft> inboundShareDraft =
      StreamController<InboundShareDraft>.broadcast();
  static final StreamController<InboundSharePayload> inboundSharePayload =
      StreamController<InboundSharePayload>.broadcast();

  /// Claimed by identity, never by value. [claimPendingInboundSharePayload]
  /// removes with `ListQueue.remove`, which compares using `==`, and
  /// `InboundSharePayload` deliberately keeps the default identity `==`: two
  /// shares carrying the same items are still two distinct deliveries. Giving
  /// that class value equality would make a claim remove the wrong entry and
  /// silently drop one share, with no error anywhere.
  static final ListQueue<InboundSharePayload> _pendingInboundSharePayloads =
      ListQueue<InboundSharePayload>();

  static void emitInboundSharePayload(InboundSharePayload payload) {
    // Retain every payload until a live MainPage explicitly claims it. A
    // broadcast listener can exist before its Navigator is ready, or while it
    // is being replaced, so hasListener alone is not a delivery guarantee.
    _pendingInboundSharePayloads.addLast(payload);
    if (inboundSharePayload.hasListener) {
      inboundSharePayload.add(payload);
    }
  }

  static List<InboundSharePayload> get pendingInboundSharePayloads =>
      _pendingInboundSharePayloads.toList(growable: false);

  /// A share that produced nothing to review, so the user can be told.
  static final StreamController<InboundShareFailure> inboundShareFailure =
      StreamController<InboundShareFailure>.broadcast();

  static final ListQueue<InboundShareFailure> _pendingInboundShareFailures =
      ListQueue<InboundShareFailure>();

  /// Retained like a payload, and for the same reason: a share can fail during
  /// a cold start, before any MainPage exists to hear about it. Dropping it
  /// then would restore the silent failure this exists to remove.
  static void emitInboundShareFailure(InboundShareFailure failure) {
    if (_pendingInboundShareFailures.isNotEmpty &&
        _pendingInboundShareFailures.last == failure) {
      return;
    }
    _pendingInboundShareFailures.addLast(failure);
    if (inboundShareFailure.hasListener) {
      inboundShareFailure.add(failure);
    }
  }

  static List<InboundShareFailure> get pendingInboundShareFailures =>
      _pendingInboundShareFailures.toList(growable: false);

  /// Claimed by value, unlike payloads. A failure carries no identity worth
  /// preserving, and two shares failing the same way are not worth reporting
  /// twice in a row - so `remove` dropping the first equal entry is correct
  /// here even though it would be a bug for [claimPendingInboundSharePayload].
  static bool claimPendingInboundShareFailure(InboundShareFailure failure) =>
      _pendingInboundShareFailures.remove(failure);

  static bool claimPendingInboundSharePayload(InboundSharePayload payload) =>
      _pendingInboundSharePayloads.remove(payload);

  static InboundSharePayload? takePendingInboundSharePayload() =>
      _pendingInboundSharePayloads.isEmpty
      ? null
      : _pendingInboundSharePayloads.removeFirst();

  /// First string is room id, Second string is client id
  static StreamController<(String, String?)> openRoom =
      StreamController<(String, String?)>.broadcast();
  static final ListQueue<(String, String?)> _pendingOpenRoomQueue =
      ListQueue<(String, String?)>();
  static final Set<String> _notificationOpenRoomKeys = {};
  static final Set<String> _notificationOpenRoomSettingsKeys = {};
  static final Set<String> _shortcutOpenRoomKeys = {};
  static final Set<String> _streamLabOpenRoomKeys = {};
  static final Map<String, StreamLabOpenRoomMetadata>
  _streamLabOpenRoomMetadata = {};

  static void openRoomFromNotification((String, String?) room) {
    _notificationOpenRoomKeys.add(_openRoomKey(room));
    if (!openRoom.hasListener) {
      _pendingOpenRoomQueue.addLast(room);
      return;
    }
    openRoom.add(room);
  }

  /// Opens the target room's notification settings after the normal
  /// notification route has resolved its account and room. Keeping this as an
  /// intent alongside [openRoom] preserves cold-start queuing and account
  /// switching rather than attempting to navigate from a background callback.
  static void openRoomSettingsFromNotification((String, String?) room) {
    _notificationOpenRoomSettingsKeys.add(_openRoomKey(room));
    openRoomFromNotification(room);
  }

  static void openRoomFromShortcut((String, String?) room) {
    _shortcutOpenRoomKeys.add(_openRoomKey(room));
    if (!openRoom.hasListener) {
      _pendingOpenRoomQueue.addLast(room);
      return;
    }
    openRoom.add(room);
  }

  static void openRoomFromStreamLab(
    (String, String?) room, {
    String? requestNonce,
    String? roomHash,
  }) {
    final key = _openRoomKey(room);
    _streamLabOpenRoomKeys.add(key);
    final metadata = StreamLabOpenRoomMetadata(
      requestNonce: _trimmedOrNull(requestNonce),
      roomHash: _trimmedOrNull(roomHash),
    );
    if (metadata.isEmpty) {
      _streamLabOpenRoomMetadata.remove(key);
    } else {
      _streamLabOpenRoomMetadata[key] = metadata;
    }
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

  static bool hasNotificationOpenRoomSettings((String, String?) room) {
    return _notificationOpenRoomSettingsKeys.contains(_openRoomKey(room));
  }

  static bool consumeNotificationOpenRoomSettings((String, String?) room) {
    return _notificationOpenRoomSettingsKeys.remove(_openRoomKey(room));
  }

  static bool consumeShortcutOpenRoom((String, String?) room) {
    return _shortcutOpenRoomKeys.remove(_openRoomKey(room));
  }

  static bool consumeStreamLabOpenRoom((String, String?) room) {
    return _streamLabOpenRoomKeys.remove(_openRoomKey(room));
  }

  static StreamLabOpenRoomMetadata? takeStreamLabOpenRoomMetadata(
    (String, String?) room,
  ) {
    return _streamLabOpenRoomMetadata.remove(_openRoomKey(room));
  }

  static String _openRoomKey((String, String?) room) {
    return "${room.$2 ?? ''}\u0000${room.$1}";
  }

  static String? _trimmedOrNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
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

  /// Holds **exactly one** callback per account+room, and that callback must be
  /// the room's *main* timeline.
  ///
  /// The key carries no surface discriminator, so any second registration for
  /// the same account and room silently replaces the first. A room's thread
  /// timelines are mounted alongside its main timeline (the thread side panel),
  /// so they must not register - see `RoomTimelineWidgetViewState`
  /// `initFromTimeline`. Add a discriminator to [_inboxJumpKey] before letting
  /// any second surface register for one room.
  static final Map<String, void Function(String)> _inboxJumpTargets = {};

  /// Registers a mounted **main** timeline that can receive an Inbox event
  /// target.
  ///
  /// Unlike [jumpToEvent], an Inbox target is bound to an exact account and
  /// room. Its disposer only removes the callback it installed, so an older
  /// timeline cannot unregister a replacement that mounted later. Registering
  /// from a thread timeline would displace the main one; see
  /// [_inboxJumpTargets].
  static VoidCallback registerInboxJumpTarget({
    required String clientIdentifier,
    required String roomIdentifier,
    required void Function(String eventId) onJump,
  }) {
    final key = _inboxJumpKey(clientIdentifier, roomIdentifier);
    _inboxJumpTargets[key] = onJump;
    return () {
      if (identical(_inboxJumpTargets[key], onJump)) {
        _inboxJumpTargets.remove(key);
      }
    };
  }

  /// Delivers an Inbox event to the matching mounted timeline only.
  ///
  /// Returns false while that timeline has not mounted, allowing MainPage to
  /// retry without acknowledging a stale or unrelated listener.
  static bool jumpToInboxEvent({
    required String clientIdentifier,
    required String roomIdentifier,
    required String eventId,
  }) {
    final target =
        _inboxJumpTargets[_inboxJumpKey(clientIdentifier, roomIdentifier)];
    if (target == null) return false;
    target(eventId);
    return true;
  }

  static String _inboxJumpKey(String clientIdentifier, String roomIdentifier) =>
      '$clientIdentifier\u0000$roomIdentifier';

  static StreamController<void> focusTimeline = StreamController.broadcast();

  static StreamController<void> wrapComposerSelectionInBrackets =
      StreamController.broadcast();

  static StreamController<MessageEffectParticles> doMessageEffect =
      StreamController.broadcast();

  static StreamController<ScopePopped> onPopInvoked =
      StreamController.broadcast(sync: true);
}

class StreamLabOpenRoomMetadata {
  const StreamLabOpenRoomMetadata({this.requestNonce, this.roomHash});

  final String? requestNonce;
  final String? roomHash;

  bool get isEmpty => requestNonce == null && roomHash == null;
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
