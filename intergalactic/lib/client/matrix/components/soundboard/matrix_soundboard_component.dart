import 'dart:async';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:uuid/uuid.dart';

class MatrixSoundboardComponent
    implements SoundboardComponent<MatrixClient, MatrixSpace> {
  MatrixSoundboardComponent(this.client, this.space) {
    _stateSubscription = client.matrixClient.onRoomState.stream
        .where((event) =>
            event.roomId == space.identifier &&
            (event.state.type == SoundboardEventTypes.soundState ||
                event.state.type == SoundboardEventTypes.userState ||
                event.state.type == matrix.EventTypes.RoomPowerLevels))
        .listen((_) => _emitChanged());
  }

  static const _uuid = Uuid();
  static const _joinSoundAccountDataKey = SoundboardEventTypes.userState;

  final StreamController<void> _onChanged = StreamController.broadcast();
  final Map<String, SoundboardUserSettings> _localJoinSoundSettings = {};
  StreamSubscription? _stateSubscription;
  bool _disposed = false;

  @override
  MatrixClient client;

  @override
  MatrixSpace space;

  @override
  Stream<void> get onChanged => _onChanged.stream;

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    await _onChanged.close();
  }

  @override
  List<SoundboardSound> get sounds {
    final rawStates = space.matrixRoom.states[SoundboardEventTypes.soundState];
    if (rawStates == null) {
      return const [];
    }

    return rawStates.entries
        .map((entry) =>
            SoundboardSound.fromState(entry.key, entry.value.content))
        .whereType<SoundboardSound>()
        .where((sound) => sound.isAvailable)
        .sorted((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  bool get canUploadSound =>
      space.matrixRoom.canChangeStateEvent(SoundboardEventTypes.soundState);

  @override
  bool get memberUploadsEnabled =>
      soundUploadPowerLevel <= defaultUserPowerLevel;

  @override
  bool get canEnableMemberUploads => space.matrixRoom.canChangeStateEvent(
        matrix.EventTypes.RoomPowerLevels,
      );

  @override
  int get soundUploadPowerLevel =>
      _stateEventPowerLevel(SoundboardEventTypes.soundState);

  @override
  int get defaultUserPowerLevel =>
      _powerLevelInt(_powerLevelContent['users_default'], fallback: 0);

  @override
  int? get currentUserPowerLevel {
    final currentUserId = client.matrixClient.userID ?? client.self?.identifier;
    if (currentUserId == null) {
      return null;
    }
    final users = _powerLevelMap('users');
    return _powerLevelInt(
      users[currentUserId],
      fallback: defaultUserPowerLevel,
    );
  }

  @override
  bool canManageSound(SoundboardSound sound, String userId) {
    return sound.uploadedBy == userId || canEnableMemberUploads;
  }

  @override
  Future<void> refreshSounds() async {
    await space.matrixRoom.postLoad();
    _emitChanged();
    space.notifyUpdate();
  }

  @override
  String? getJoinSoundId(String userId) {
    final currentUserId = client.matrixClient.userID ?? client.self?.identifier;
    if (userId == currentUserId) {
      if (_localJoinSoundSettings.containsKey(userId)) {
        return _localJoinSoundSettings[userId]?.joinSoundId;
      }

      final accountData =
          space.matrixRoom.roomAccountData[_joinSoundAccountDataKey]?.content;
      if (accountData != null) {
        return SoundboardUserSettings.fromState(accountData).joinSoundId;
      }
    }

    final state = space.matrixRoom.getState(
      SoundboardEventTypes.userState,
      userId,
    );
    return SoundboardUserSettings.fromState(state?.content).joinSoundId;
  }

  @override
  Future<void> enableMemberUploads() async {
    if (!canEnableMemberUploads) {
      throw Exception('Only server admins can enable member sound uploads.');
    }

    final powerState =
        space.matrixRoom.getState(matrix.EventTypes.RoomPowerLevels);
    final content = Map<String, dynamic>.from(powerState?.content ?? {});
    final events = Map<String, dynamic>.from(
      content['events'] is Map ? content['events'] as Map : const {},
    );
    events[SoundboardEventTypes.soundState] = 0;
    events.remove(SoundboardEventTypes.userState);
    content['events'] = events;

    await client.matrixClient.setRoomStateWithKey(
      space.identifier,
      matrix.EventTypes.RoomPowerLevels,
      '',
      content,
    );
    await space.matrixRoom.waitForRoomInSync();
    _emitChanged();
  }

  @override
  Future<SoundboardSound> uploadSound({
    required String name,
    required String emoji,
    required Uint8List bytes,
    required String mimeType,
    int? durationMs,
    double volume = SoundboardSound.defaultVolume,
  }) async {
    if (!canUploadSound) {
      throw Exception(
        'Member sound uploads are not enabled for this server yet.',
      );
    }
    if (bytes.isEmpty || bytes.length > SoundboardComponent.maxSoundBytes) {
      throw Exception('Soundboard sounds must be 2 MB or smaller.');
    }
    if (!mimeType.startsWith('audio/')) {
      throw Exception('Only audio files can be uploaded to the soundboard.');
    }

    final userId = client.matrixClient.userID ?? client.self?.identifier;
    if (userId == null) {
      throw Exception('No active Matrix user is available for this upload.');
    }

    final id = _uuid.v4();
    try {
      final url = await client.matrixClient.uploadContent(
        bytes,
        contentType: mimeType,
      );
      final sound = SoundboardSound(
        id: id,
        name: name.trim(),
        emoji: emoji.trim(),
        mxcUri: url,
        mimeType: mimeType,
        uploadedBy: userId,
        createdAt: DateTime.now().toUtc(),
        sizeBytes: bytes.length,
        durationMs: durationMs,
        volume: SoundboardSound.normalizeVolume(volume),
      );

      await _setSoundState(sound);
      Log.i(
        'Uploaded soundboard sound ${sound.id} to ${space.identifier}; '
        'memberUploads=$memberUploadsEnabled required=$soundUploadPowerLevel '
        'currentUser=$currentUserPowerLevel',
      );
      return sound;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to upload soundboard sound to ${space.identifier}; '
            'canUpload=$canUploadSound memberUploads=$memberUploadsEnabled '
            'required=$soundUploadPowerLevel '
            'currentUser=$currentUserPowerLevel '
            'defaultUser=$defaultUserPowerLevel',
      );
      rethrow;
    }
  }

  @override
  Future<void> updateSoundVolume(
    SoundboardSound sound,
    double volume,
  ) async {
    final userId = client.matrixClient.userID ?? client.self?.identifier;
    if (userId == null || !canManageSound(sound, userId)) {
      throw Exception('You can only change sounds you uploaded.');
    }

    final currentSound = sounds.firstWhereOrNull(
      (candidate) => candidate.id == sound.id,
    );
    if (currentSound == null) {
      throw Exception('That sound is no longer available.');
    }

    await _setSoundState(
      currentSound.copyWith(
        volume: SoundboardSound.normalizeVolume(volume),
      ),
    );
  }

  @override
  Future<void> deleteSound(SoundboardSound sound) async {
    final userId = client.matrixClient.userID ?? client.self?.identifier;
    if (userId == null || !canManageSound(sound, userId)) {
      throw Exception('You can only delete sounds you uploaded.');
    }

    await _setSoundState(sound.copyWith(enabled: false, deleted: true));
  }

  Future<void> _setSoundState(SoundboardSound sound) async {
    final eventId = await client.matrixClient.setRoomStateWithKey(
      space.identifier,
      SoundboardEventTypes.soundState,
      sound.id,
      sound.toStateContent(),
    );
    final event = await space.matrixRoom.getEventById(eventId);
    final states = space.matrixRoom.states.putIfAbsent(
      SoundboardEventTypes.soundState,
      () => <String, matrix.StrippedStateEvent>{},
    );
    if (event != null) {
      states[sound.id] = event;
    }
    _emitChanged();
    space.notifyUpdate();
  }

  @override
  Future<void> setJoinSoundForUser(String userId, String? soundId) async {
    final currentUserId = client.matrixClient.userID ?? client.self?.identifier;
    if (currentUserId == null) {
      throw Exception('No active Matrix user is available.');
    }
    if (userId != currentUserId && !canEnableMemberUploads) {
      throw Exception('You can only set your own join sound.');
    }
    if (soundId != null && !sounds.any((sound) => sound.id == soundId)) {
      throw Exception('That sound is no longer available.');
    }

    final settings = SoundboardUserSettings(joinSoundId: soundId);
    if (userId == currentUserId) {
      await client.matrixClient.setAccountDataPerRoom(
        currentUserId,
        space.identifier,
        _joinSoundAccountDataKey,
        settings.toStateContent(),
      );
      _localJoinSoundSettings[userId] = settings;
      _emitChanged();
      return;
    }

    final eventId = await client.matrixClient.setRoomStateWithKey(
      space.identifier,
      SoundboardEventTypes.userState,
      userId,
      settings.toStateContent(),
    );
    final event = await space.matrixRoom.getEventById(eventId);
    final states = space.matrixRoom.states.putIfAbsent(
      SoundboardEventTypes.userState,
      () => <String, matrix.StrippedStateEvent>{},
    );
    if (event != null) {
      states[userId] = event;
    }
    _emitChanged();
  }

  @override
  Future<void> playSound(
    SoundboardSound sound,
    Room room, {
    String source = 'manual',
    String? callSessionId,
  }) async {
    if (room is! MatrixRoom) {
      return;
    }
    final userId = client.matrixClient.userID;
    if (userId == null) {
      return;
    }

    final nonce = _uuid.v4();
    final playEvent = SoundboardPlayEvent(
      soundId: sound.id,
      spaceRoomId: space.identifier,
      nonce: nonce,
      source: source,
      callSessionId: callSessionId,
    );
    await soundboardPlaybackService.playLocalAndDedupe(
      client,
      room,
      sound,
      nonce: nonce,
      senderId: userId,
      source: source,
      callSessionId: callSessionId,
      spaceRoomId: space.identifier,
    );

    try {
      Log.i(
        'Sending soundboard play ${sound.id} in ${room.identifier}; '
        'space=${space.identifier} source=$source session=${callSessionId ?? 'none'}',
      );
      final eventId = await room.matrixRoom.sendEvent(
        playEvent.toContent(),
        type: SoundboardEventTypes.play,
        displayPendingEvent: false,
      );
      if (eventId == null) {
        throw Exception('Homeserver did not accept soundboard play event.');
      }
      Log.i('Sent soundboard play ${sound.id}; event=$eventId');
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to send soundboard play ${sound.id} in '
            '${room.identifier}',
      );
      rethrow;
    }
  }

  void _emitChanged() {
    if (!_disposed && !_onChanged.isClosed) {
      _onChanged.add(null);
    }
  }

  Map<String, dynamic> get _powerLevelContent {
    final content =
        space.matrixRoom.getState(matrix.EventTypes.RoomPowerLevels)?.content;
    return Map<String, dynamic>.from(content ?? const {});
  }

  Map<String, dynamic> _powerLevelMap(String key) {
    final value = _powerLevelContent[key];
    return Map<String, dynamic>.from(value is Map ? value : const {});
  }

  int _stateEventPowerLevel(String eventType) {
    final events = _powerLevelMap('events');
    return _powerLevelInt(
      events[eventType],
      fallback:
          _powerLevelInt(_powerLevelContent['state_default'], fallback: 50),
    );
  }

  int _powerLevelInt(Object? value, {required int fallback}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return fallback;
  }
}
