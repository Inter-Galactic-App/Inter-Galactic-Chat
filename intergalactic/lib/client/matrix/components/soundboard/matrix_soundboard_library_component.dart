import 'dart:async';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_library_component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Matrix implementation of the account-global soundboard library (U5).
///
/// The reference document lives in this account's account data, so it is bound
/// to exactly one [MatrixClient]: every read, write, and subscription goes
/// through `client.matrixClient`, and a second signed-in account has its own
/// component over its own document. Nothing here consults a shared or
/// "primary" session.
class MatrixSoundboardLibraryComponent
    extends SoundboardLibraryComponent<MatrixClient>
    implements DisposableComponent {
  MatrixSoundboardLibraryComponent(super.client) {
    _syncSubscription = client.matrixClient.onSync.stream
        .where((update) => _touchesLibrary(update))
        .listen((_) => _emitChanged());
  }

  final StreamController<void> _onChanged = StreamController.broadcast();
  StreamSubscription? _syncSubscription;
  bool _disposed = false;

  /// Set while a write is in flight, so [entries] keeps showing the member's
  /// intent instead of flickering back to the server document until the write
  /// is confirmed by sync (or fails and is rolled back).
  SoundboardGlobalLibrary? _pendingLibrary;

  @override
  Stream<void> get onChanged => _onChanged.stream;

  /// [DisposableComponent] is what MatrixClient.close() looks for; without it
  /// this onSync subscription survives client teardown.
  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _syncSubscription?.cancel();
    _syncSubscription = null;
    await _onChanged.close();
  }

  bool _touchesLibrary(matrix.SyncUpdate update) {
    final accountData = update.accountData;
    if (accountData == null) {
      return false;
    }
    return accountData.any(
      (event) => event.type == SoundboardEventTypes.globalPackReferences,
    );
  }

  void _emitChanged() {
    if (_disposed || _onChanged.isClosed) {
      return;
    }
    // A sync carrying the document is the authoritative answer; any optimistic
    // copy has served its purpose.
    _pendingLibrary = null;
    _onChanged.add(null);
  }

  /// Emits without discarding the optimistic document, for the in-flight write
  /// in [_write] — unlike [_emitChanged], which only runs once a sync has
  /// superseded it.
  ///
  /// Guarded for the same reason [_emitChanged] is: a write still in flight
  /// when [dispose] runs would otherwise `add` to a closed broadcast
  /// controller, and on the failure path that `StateError` would replace the
  /// write error the caller is about to see.
  void _notifyPending() {
    if (_disposed || _onChanged.isClosed) {
      return;
    }
    _onChanged.add(null);
  }

  /// The document as last synchronized from the server, or the optimistic copy
  /// while a write is in flight.
  SoundboardGlobalLibrary get library {
    final pending = _pendingLibrary;
    if (pending != null) {
      return pending;
    }
    return _serverLibrary;
  }

  SoundboardGlobalLibrary get _serverLibrary =>
      SoundboardGlobalLibrary.fromContent(
        client
            .matrixClient
            .accountData[SoundboardEventTypes.globalPackReferences]
            ?.content,
      );

  @override
  List<SoundboardGlobalPackEntry> get entries {
    return library.references.map(_resolve).toList(growable: false);
  }

  /// Resolves a reference against the source space as this account sees it
  /// right now. A pack the account cannot read — left space, deleted pack,
  /// disabled pack — resolves to a stale entry rather than an error, because
  /// losing access to a source is ordinary and must not break the library.
  SoundboardGlobalPackEntry _resolve(SoundboardGlobalPackReference reference) {
    final space = _spaceById(reference.sourceSpaceId);
    final soundboard = space?.getComponent<SoundboardComponent>();
    if (space == null || soundboard == null) {
      return SoundboardGlobalPackEntry(reference: reference);
    }

    final pack = soundboard.packById(reference.packId);
    if (pack == null || pack.deleted || !pack.enabled) {
      return SoundboardGlobalPackEntry(
        reference: reference,
        sourceSpaceName: space.displayName,
      );
    }

    // soundsInPack resolves by EFFECTIVE pack id. Matching on the raw
    // sound.packId resolved every legacy pack to zero sounds - loose sounds
    // carry no pack_id at all and belong to their uploader's derived legacy
    // pack - so a member could enable their own pack globally and then never
    // see it in another space's picker, which drops sound-less entries.
    final sounds = soundboard.soundsInPack(reference.packId);

    return SoundboardGlobalPackEntry(
      reference: reference,
      sourceSpaceName: space.displayName,
      pack: pack,
      sounds: sounds,
    );
  }

  /// Scoped to THIS account's spaces. `clientManager.spaces` would span every
  /// signed-in account and could resolve another account's copy of the space.
  Space? _spaceById(String identifier) {
    for (final space in client.spaces) {
      if (space.identifier == identifier) {
        return space;
      }
    }
    return null;
  }

  @override
  bool isEnabled(String sourceSpaceId, String packId) =>
      library.contains(sourceSpaceId, packId);

  @override
  bool canEnable(String sourceSpaceId, String packId) {
    final space = _spaceById(sourceSpaceId);
    final soundboard = space?.getComponent<SoundboardComponent>();
    if (soundboard == null) {
      return false;
    }
    final pack = soundboard.packById(packId);
    return pack != null && !pack.deleted && pack.enabled;
  }

  @override
  Future<void> enablePack(String sourceSpaceId, String packId) async {
    if (!canEnable(sourceSpaceId, packId)) {
      throw Exception(
        'That sound pack is not available in its source space right now.',
      );
    }
    final reference = SoundboardGlobalPackReference(
      sourceSpaceId: sourceSpaceId,
      packId: packId,
      enabledAt: DateTime.now().toUtc(),
    );
    await _write(added: [reference]);
  }

  @override
  Future<void> disablePack(String sourceSpaceId, String packId) async {
    await _write(
      removedKeys: [
        SoundboardGlobalPackReference.keyFor(sourceSpaceId, packId),
      ],
    );
  }

  @override
  Future<void> pruneStaleReferences() async {
    final stale = entries.where((entry) => entry.isStale).toList();
    if (stale.isEmpty) {
      return;
    }
    try {
      await _write(removedKeys: stale.map((e) => e.reference.key).toList());
    } catch (error, stackTrace) {
      // Pruning is housekeeping. A failure leaves the references in place and
      // the entries merely stale, which is already handled everywhere.
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to prune ${stale.length} stale soundboard library '
            'reference(s); they remain listed as unavailable',
      );
    }
  }

  /// Read-modify-write against the newest synchronized document.
  ///
  /// Another device on this account may have toggled unrelated packs since the
  /// last read, so the change is rebased onto the server document rather than
  /// overwriting it — only the keys this call added or removed are imposed.
  Future<void> _write({
    List<SoundboardGlobalPackReference> added = const [],
    List<String> removedKeys = const [],
  }) async {
    final userId = client.matrixClient.userID;
    if (userId == null || userId.isEmpty) {
      throw StateError('This Matrix session does not have a user ID yet.');
    }

    final previous = _pendingLibrary;
    final next = library.mergeWith(
      _serverLibrary,
      added: added,
      removedKeys: removedKeys,
    );
    _pendingLibrary = next;
    _notifyPending();

    try {
      await client.matrixClient.setAccountData(
        userId,
        SoundboardEventTypes.globalPackReferences,
        next.toContent(),
      );
      Log.i(
        'soundboard event=global_library_written '
        'added=${added.length} removed=${removedKeys.length} '
        'total=${next.references.length}',
      );
    } catch (error) {
      // Restore the last confirmed state so the UI never shows a change the
      // server rejected.
      _pendingLibrary = previous;
      _notifyPending();
      rethrow;
    }
  }
}
