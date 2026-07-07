import 'dart:async';

import 'package:collection/collection.dart';
import 'package:intergalactic/client/call_manager.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_local_sound_resolver.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';
import 'package:intergalactic/config/app_globals.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:media_kit/media_kit.dart';

class SoundboardPlaybackService {
  final DateTime _startedAt =
      DateTime.now().toUtc().subtract(const Duration(seconds: 30));
  final Set<String> _playedNonces = {};
  final Set<String> _joinSoundSessionKeys = {};
  final Map<String, Timer> _pendingMatrixPlayRetries = {};
  Future<void> _playerOperation = Future.value();
  bool _isDisposed = false;
  Player? _player;

  CallManager? _callManager;

  static const Duration _matrixPlayRetryDelay = Duration(milliseconds: 750);
  static const int _maxMatrixPlayRetryAttempts = 2;

  void configure(CallManager callManager) {
    _callManager = callManager;
  }

  bool get isDeafened => _callManager?.isDeafened ?? false;

  Future<void> handleMatrixPlayEvent(
    MatrixClient client,
    MatrixRoom room,
    Map<String, dynamic>? content, {
    required DateTime originServerTs,
    required String senderId,
    int retryAttempt = 0,
  }) async {
    if (originServerTs.toUtc().isBefore(_startedAt)) {
      return;
    }

    final play = SoundboardPlayEvent.fromContent(content);
    if (play == null) {
      Log.w('Ignoring invalid soundboard play event in ${room.identifier}');
      return;
    }
    if (_playedNonces.contains(play.nonce)) {
      return;
    }

    final session = _activeSessionFor(
      client,
      room,
      callSessionId: play.callSessionId,
      spaceRoomId: play.spaceRoomId,
    );
    if (session == null) {
      Log.i(
        'Soundboard play ${play.soundId} is waiting for an active call '
        'session in ${room.identifier} (attempt $retryAttempt)',
      );
      _scheduleMatrixPlayRetry(
        client,
        room,
        content,
        originServerTs: originServerTs,
        senderId: senderId,
        play: play,
        retryAttempt: retryAttempt,
      );
      return;
    }
    _pendingMatrixPlayRetries.remove(play.nonce)?.cancel();

    final space = client.getSpace(play.spaceRoomId);
    if (space is! MatrixSpace) {
      Log.w(
        'Soundboard play ${play.soundId} is waiting for space '
        '${play.spaceRoomId} to load (attempt $retryAttempt)',
      );
      _scheduleMatrixPlayRetry(
        client,
        room,
        content,
        originServerTs: originServerTs,
        senderId: senderId,
        play: play,
        retryAttempt: retryAttempt,
      );
      return;
    }
    final roomBelongsToSpace = space.identifier == room.identifier ||
        space.roomsWithChildren.any(
          (candidate) => candidate.identifier == room.identifier,
        );
    if (!roomBelongsToSpace) {
      Log.w(
        'Ignoring soundboard play ${play.soundId}; room ${room.identifier} '
        'does not belong to space ${play.spaceRoomId}',
      );
      return;
    }

    final component = space.getComponent<SoundboardComponent>();
    var sound = component?.sounds.firstWhereOrNull(
      (sound) => sound.id == play.soundId && sound.isAvailable,
    );
    if (sound == null) {
      if (component != null && retryAttempt < _maxMatrixPlayRetryAttempts) {
        Log.i(
          'Soundboard play ${play.soundId} arrived before local sound state '
          'was ready in ${play.spaceRoomId}; refreshing soundboard state '
          '(attempt $retryAttempt)',
        );
        try {
          await component.refreshSounds();
          sound = component.sounds.firstWhereOrNull(
            (sound) => sound.id == play.soundId && sound.isAvailable,
          );
        } catch (error, stackTrace) {
          Log.onError(
            error,
            stackTrace,
            content: 'Failed to refresh soundboard state for ${play.soundId}',
          );
        }
      }

      if (sound == null && retryAttempt < _maxMatrixPlayRetryAttempts) {
        _scheduleMatrixPlayRetry(
          client,
          room,
          content,
          originServerTs: originServerTs,
          senderId: senderId,
          play: play,
          retryAttempt: retryAttempt,
        );
        return;
      }

      Log.w(
        'Ignoring soundboard play ${play.soundId}; sound is not available '
        'in space ${play.spaceRoomId}',
      );
      return;
    }

    if (!_playedNonces.add(play.nonce)) {
      Log.i('Ignoring duplicate soundboard play nonce ${play.nonce}');
      return;
    }

    Log.i(
      'Playing remote soundboard sound ${sound.id}; '
      'room=${room.identifier} space=${space.identifier} source=${play.source}',
    );
    await _playSoundFile(
      client,
      sound,
      senderId: senderId,
      source: play.source,
      respectDeafen: true,
    );
  }

  void _scheduleMatrixPlayRetry(
    MatrixClient client,
    MatrixRoom room,
    Map<String, dynamic>? content, {
    required DateTime originServerTs,
    required String senderId,
    required SoundboardPlayEvent play,
    required int retryAttempt,
  }) {
    if (_isDisposed) {
      return;
    }

    if (retryAttempt >= _maxMatrixPlayRetryAttempts) {
      Log.w(
        'Dropped soundboard play ${play.soundId}; matching call, space, '
        'or sound state was not ready after ${retryAttempt + 1} attempts',
      );
      return;
    }

    if (_pendingMatrixPlayRetries.containsKey(play.nonce)) {
      return;
    }

    final retryContent =
        content == null ? null : Map<String, dynamic>.from(content);
    _pendingMatrixPlayRetries[play.nonce] = Timer(_matrixPlayRetryDelay, () {
      _pendingMatrixPlayRetries.remove(play.nonce);
      unawaited(
        handleMatrixPlayEvent(
          client,
          room,
          retryContent,
          originServerTs: originServerTs,
          senderId: senderId,
          retryAttempt: retryAttempt + 1,
        ).catchError((Object error, StackTrace stackTrace) {
          Log.onError(
            error,
            stackTrace,
            content: 'Failed to retry soundboard play event',
          );
        }),
      );
    });
  }

  Future<void> playPreview(MatrixClient client, SoundboardSound sound) async {
    await _playSoundFile(
      client,
      sound,
      senderId: 'preview',
      source: 'preview',
      respectDeafen: false,
    );
  }

  bool hasActiveSessionForRoom(MatrixClient client, MatrixRoom room) {
    return _activeSessionFor(client, room) != null;
  }

  Future<void> playLocalAndDedupe(
    MatrixClient client,
    MatrixRoom room,
    SoundboardSound sound, {
    required String nonce,
    String? senderId,
    String source = 'manual',
    String? callSessionId,
    String? spaceRoomId,
  }) async {
    final session = _activeSessionFor(
      client,
      room,
      callSessionId: callSessionId,
      spaceRoomId: spaceRoomId,
    );
    if (session == null) {
      Log.w(
        'Playing local soundboard sound ${sound.id} without a matched '
        'active call session for ${room.identifier}',
      );
    }

    if (!_playedNonces.add(nonce)) {
      Log.i('Ignoring duplicate local soundboard play nonce $nonce');
      return;
    }

    Log.i(
      'Playing local soundboard sound ${sound.id}; '
      'room=${room.identifier} source=$source',
    );
    await _playSoundFile(
      client,
      sound,
      senderId: senderId ?? client.matrixClient.userID,
      source: source,
      respectDeafen: true,
    );
  }

  Future<void> playJoinSoundForSession(VoipSession session) async {
    if (session.state != VoipState.connected) {
      return;
    }

    final client = session.client;
    if (client is! MatrixClient) {
      return;
    }

    final userId = client.matrixClient.userID ?? client.self?.identifier;
    if (userId == null) {
      return;
    }

    final key = [
      client.identifier,
      session.roomId,
      session.sessionId,
      userId,
    ].join('|');
    if (!_joinSoundSessionKeys.add(key)) {
      return;
    }

    final room = client.getRoom(session.roomId);
    if (room is! MatrixRoom) {
      return;
    }

    final space = _spaceForRoom(client, session.roomId);
    final component = space?.getComponent<SoundboardComponent>();
    final soundId = component?.getJoinSoundId(userId);
    if (component == null || soundId == null) {
      return;
    }

    final sound = component.sounds.firstWhereOrNull(
      (sound) => sound.id == soundId && sound.isAvailable,
    );
    if (sound == null) {
      return;
    }

    await component.playSound(
      sound,
      room,
      source: 'join',
      callSessionId: session.sessionId,
    );
  }

  VoipSession? _activeSessionFor(
    MatrixClient client,
    MatrixRoom room, {
    String? callSessionId,
    String? spaceRoomId,
  }) {
    final space = spaceRoomId == null ? null : client.getSpace(spaceRoomId);
    return _callManager?.currentSessions.firstWhereOrNull((session) {
      if (session.client != client ||
          (session.state != VoipState.connected &&
              session.state != VoipState.connecting)) {
        return false;
      }

      if (callSessionId != null && session.sessionId == callSessionId) {
        return true;
      }

      if (session.roomId == room.identifier) {
        return true;
      }

      if (space is MatrixSpace) {
        return space.roomsWithChildren.any(
          (candidate) => candidate.identifier == session.roomId,
        );
      }

      return false;
    });
  }

  MatrixSpace? _spaceForRoom(MatrixClient client, String roomId) {
    return client.spaces.whereType<MatrixSpace>().firstWhereOrNull((space) {
      return space.roomsWithChildren.any((room) => room.identifier == roomId);
    });
  }

  Future<void> _playSoundFile(
    MatrixClient client,
    SoundboardSound sound, {
    required String? senderId,
    required String source,
    required bool respectDeafen,
  }) async {
    if (_isDisposed) {
      return;
    }

    if (respectDeafen && isDeafened) {
      Log.i('Skipping soundboard sound ${sound.id}; this device is deafened');
      return;
    }

    try {
      await _enqueuePlayerOperation(() async {
        final player = _soundPlayer;
        // Stop before resolving/pruning so retention cleanup never deletes a
        // file that media_kit is still using for the previous sound.
        await player.stop();

        final localUri = await resolveSoundboardLocalUri(client, sound);
        if (localUri == null) {
          Log.w('Failed to resolve soundboard sound ${sound.id}');
          return;
        }

        try {
          final pruneResult = await pruneSoundboardLocalCache(
            protectedUri: localUri,
          );
          if (pruneResult.didDelete) {
            Log.i(
              'Pruned soundboard temp cache after resolving ${sound.id}; '
              'deleted=${pruneResult.deletedFiles} '
              'bytes=${pruneResult.deletedBytes}',
            );
          }
        } catch (error, stackTrace) {
          Log.onError(
            error,
            stackTrace,
            content: 'Failed to prune soundboard temp cache',
          );
        }

        final effectiveVolume = _effectiveVolume(
          localVolume: preferences.soundboardVolume.value,
          soundVolume: sound.volume,
        );
        await player.setVolume(effectiveVolume);
        await player.setPlaylistMode(PlaylistMode.none);
        try {
          await player.open(Media(localUri.toString()), play: true);
          Log.i(
            'Started soundboard sound ${sound.id}; source=$source '
            'sender=${senderId ?? 'unknown'} volume=${effectiveVolume.toStringAsFixed(0)} '
            'mime=${sound.mimeType}; uri=$localUri',
          );
        } catch (error, stackTrace) {
          Log.onError(
            error,
            stackTrace,
            content:
                'Failed to open soundboard sound ${sound.id}; mime=${sound.mimeType}; uri=$localUri',
          );
          rethrow;
        }
      });
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to play soundboard sound ${sound.id}',
      );
    }
  }

  Player get _soundPlayer {
    if (_isDisposed) {
      throw StateError('SoundboardPlaybackService has been disposed.');
    }

    _player ??= Player(configuration: PlayerConfiguration());
    return _player!;
  }

  double _effectiveVolume({
    required double localVolume,
    required double soundVolume,
  }) {
    final normalizedSoundVolume = SoundboardSound.normalizeVolume(soundVolume);
    final normalizedLocalVolume =
        localVolume.clamp(SoundboardSound.minVolume, SoundboardSound.maxVolume);
    return (normalizedLocalVolume * normalizedSoundVolume / 100)
        .clamp(SoundboardSound.minVolume, SoundboardSound.maxVolume)
        .toDouble();
  }

  Future<void> _enqueuePlayerOperation(
    Future<void> Function() operation,
  ) {
    final currentOperation = _playerOperation.catchError((_) {});
    final nextOperation = currentOperation.then((_) => operation());
    _playerOperation = nextOperation.catchError((_) {});
    return nextOperation;
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;
    for (final timer in _pendingMatrixPlayRetries.values) {
      timer.cancel();
    }
    _pendingMatrixPlayRetries.clear();
    await _playerOperation.catchError((_) {});
    final player = _player;
    _player = null;
    await player?.dispose();
  }
}
