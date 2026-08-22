import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/call_manager.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_authority_contract.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_playback_service.dart';
import 'package:intergalactic/client/components/space_component.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';
import 'package:intergalactic/utils/notifying_list.dart';

const _alice = '@alice:example.org';
const _spaceId = '!space:example.org';
const _callRoomId = '!call:example.org';
const _otherSpaceId = '!other:example.org';

/// CHARACTERIZATION coverage for the receiver's play-event handling, written
/// BEFORE U7 changes receiver resolution (per the soundboard-packs plan's
/// execution note for U7). These pin the behaviour that must survive the
/// change: the start-up timing gate, dedupe, session/space/room matching, and
/// the bounded retry.
///
/// Scope boundary: every case here is decided BEFORE the service reaches audio
/// playback, so none of them touch media_kit. Cases that reach playback are
/// covered by live QA, not here.
void main() {
  late SoundboardPlaybackService service;
  late _FakeCallManager callManager;
  late _FakeMatrixClient client;
  late _FakeMatrixRoom callRoom;
  late _FakeMatrixSpace space;

  /// An event timestamp the service will not reject as pre-startup. The
  /// service records its start as "30 seconds ago", so "now" is always inside
  /// the accepted window.
  DateTime freshTs() => DateTime.now().toUtc();

  Map<String, dynamic> legacyContent({
    String soundId = 'sound-1',
    String spaceRoomId = _spaceId,
    String nonce = 'nonce-1',
    String source = 'manual',
    String? callSessionId,
  }) => {
    'sound_id': soundId,
    'space_room_id': spaceRoomId,
    'nonce': nonce,
    'source': source,
    if (callSessionId != null) 'call_session_id': callSessionId,
  };

  /// A v2 cross-space play whose call lives in the DESTINATION space
  /// (_spaceId) while the sound is owned by a different SOURCE space
  /// (_otherSpaceId) the receiver need not belong to. The authorization parses
  /// (the signature is not cryptographically checked until the destination
  /// component runs verification), which is all this suite needs.
  Map<String, dynamic> crossSpaceContent({
    String soundId = 'sound-1',
    String sourceSpaceRoomId = _otherSpaceId,
    String destinationSpaceRoomId = _spaceId,
    String nonce = 'nonce-x1',
    String callSessionId = 'session-1',
  }) {
    final expiresAt = DateTime.now().toUtc().add(const Duration(minutes: 1));
    final auth = SoundboardPlaybackAuthorization(
      schemaVersion: 1,
      authorizedUserId: _alice,
      sourceSpaceId: sourceSpaceRoomId,
      destinationRoomId: _callRoomId,
      callSessionId: callSessionId,
      packId: 'pack-1',
      soundId: soundId,
      media: SoundboardAuthorityMediaDescriptor(
        mxcUri: Uri.parse('mxc://example.org/media'),
        mimeType: 'audio/ogg',
        sizeBytes: 12345,
      ),
      nonce: 'nonce-auth-1',
      expiresAt: expiresAt,
      expiresAtRaw: expiresAt.toIso8601String(),
      kid: 'sb-2026-07',
      signature: 'AA',
    );
    return SoundboardPlayEvent.versioned(
      soundId: soundId,
      packId: 'pack-1',
      sourceSpaceRoomId: sourceSpaceRoomId,
      destinationSpaceRoomId: destinationSpaceRoomId,
      nonce: nonce,
      source: 'manual',
      callSessionId: callSessionId,
      playedAt: DateTime.now().toUtc(),
      snapshot: SoundboardPlaySnapshot(
        mxcUri: Uri.parse('mxc://example.org/media'),
        mimeType: 'audio/ogg',
        sizeBytes: 12345,
        volume: 100,
      ),
      authorization: auth,
    ).toContent();
  }

  setUp(() {
    callManager = _FakeCallManager();
    space = _FakeMatrixSpace(_spaceId, roomIds: [_callRoomId]);
    callRoom = _FakeMatrixRoom(_callRoomId);
    client = _FakeMatrixClient(spaces: [space]);
    service = SoundboardPlaybackService()..configure(callManager);
  });

  tearDown(() async {
    await service.dispose();
  });

  Future<void> handle(
    Map<String, dynamic>? content, {
    DateTime? originServerTs,
    String senderId = _alice,
  }) => service.handleMatrixPlayEvent(
    client,
    callRoom,
    content,
    originServerTs: originServerTs ?? freshTs(),
    senderId: senderId,
  );

  group('startup timing gate', () {
    test('an event from before the service started is ignored', () async {
      // Joining a room replays history; without this gate every historical
      // play event would fire at once on startup.
      await handle(
        legacyContent(),
        originServerTs: DateTime.now().toUtc().subtract(
          const Duration(hours: 1),
        ),
      );

      expect(callManager.sessionLookups, 0);
    });

    test('a current event passes the gate and is processed', () async {
      await handle(legacyContent());

      expect(callManager.sessionLookups, greaterThan(0));
    });
  });

  group('content validation', () {
    test('null content is ignored', () async {
      await handle(null);
      expect(callManager.sessionLookups, 0);
    });

    test('content missing required fields is ignored', () async {
      for (final content in <Map<String, dynamic>>[
        {},
        {'sound_id': 'sound-1'},
        {'sound_id': 'sound-1', 'space_room_id': _spaceId},
        {'sound_id': '', 'space_room_id': _spaceId, 'nonce': 'n'},
      ]) {
        await handle(content);
      }

      expect(callManager.sessionLookups, 0);
    });

    test(
      'an unknown event version is ignored, not treated as legacy',
      () async {
        // A future version must not be reinterpreted under today's rules.
        await handle({
          'v': 99,
          'sound_id': 'sound-1',
          'space_room_id': _spaceId,
          'nonce': 'nonce-1',
        });

        expect(callManager.sessionLookups, 0);
      },
    );
  });

  group('session matching', () {
    // `sessionLookups > 0` only proves the gate was consulted - it is equally
    // true when a session matched. `space.componentLookups` is what separates
    // the two: the handler only reaches the component once a session has
    // matched and the space resolved, so 0 means it stopped at the gate.

    test('with no active call the event is not played immediately', () async {
      await handle(legacyContent());

      // Deferred rather than dropped: the play can arrive before the call
      // registers locally.
      expect(callManager.sessionLookups, greaterThan(0));
      expect(space.componentLookups, 0);
    });

    test('a session on a different client does not match', () async {
      callManager.sessions.add(
        _FakeVoipSession(
          client: _FakeMatrixClient(spaces: const []),
          roomId: _callRoomId,
          sessionId: 'session-1',
          state: VoipState.connected,
        ),
      );

      await handle(legacyContent());

      expect(callManager.sessionLookups, greaterThan(0));
      expect(space.componentLookups, 0);
    });

    test('a disconnected session does not match', () async {
      callManager.sessions.add(
        _FakeVoipSession(
          client: client,
          roomId: _callRoomId,
          sessionId: 'session-1',
          state: VoipState.ended,
        ),
      );

      await handle(legacyContent());

      expect(callManager.sessionLookups, greaterThan(0));
      expect(space.componentLookups, 0);
    });

    test('a connected session on this client does match', () async {
      // The negative cases above are only meaningful if the same assertion
      // moves when a session genuinely matches.
      callManager.sessions.add(
        _FakeVoipSession(
          client: client,
          roomId: _callRoomId,
          sessionId: 'session-1',
          state: VoipState.connected,
        ),
      );

      await handle(legacyContent());

      expect(space.componentLookups, greaterThan(0));
    });
  });

  group('space and room agreement', () {
    test(
      'an event naming a space this client cannot see is deferred',
      () async {
        callManager.sessions.add(
          _FakeVoipSession(
            client: client,
            roomId: _callRoomId,
            sessionId: 'session-1',
            state: VoipState.connected,
          ),
        );

        await handle(legacyContent(spaceRoomId: _otherSpaceId));

        // The space may still be loading, so this defers rather than rejects.
        expect(client.spaceLookups, contains(_otherSpaceId));
      },
    );

    test('a room outside the named space is rejected outright', () async {
      // This one is a mismatch, not a timing problem: the sender named a space
      // that does not contain the room the event landed in.
      final strayRoom = _FakeMatrixRoom('!stray:example.org');
      callManager.sessions.add(
        _FakeVoipSession(
          client: client,
          roomId: '!stray:example.org',
          sessionId: 'session-1',
          state: VoipState.connected,
        ),
      );

      await service.handleMatrixPlayEvent(
        client,
        strayRoom,
        legacyContent(),
        originServerTs: freshTs(),
        senderId: _alice,
      );

      // Space was resolved, and the mismatch stopped it before any sound
      // lookup on the space's soundboard.
      expect(space.componentLookups, 0);
    });

    test(
      'a cross-space play is dispatched before the source-space check',
      () async {
        // REGRESSION (live QA 2026-07-29, both clients on the U7 build): every
        // cross-space play was rejected with "room does not belong to space".
        // play.spaceRoomId is the SOURCE space for a cross-space event, but the
        // call lives in the DESTINATION space, so the room/space-agreement check
        // rejected it before the authorization was ever examined - and a receiver
        // not a member of the source space could not resolve it at all. The
        // isCrossSpace dispatch must run first.
        callManager.sessions.add(
          _FakeVoipSession(
            client: client,
            roomId: _callRoomId,
            sessionId: 'session-1',
            state: VoipState.connected,
          ),
        );

        await handle(crossSpaceContent());

        // The cross-space handler resolves the DESTINATION space from the call
        // room and asks it for its soundboard component. The source space
        // (_otherSpaceId) is not even known to this client, so reaching the
        // destination's component lookup proves the source-space belong-check no
        // longer short-circuits the play.
        expect(space.componentLookups, greaterThan(0));
      },
    );

    test(
      'the destination is the space the event names, not the first parent',
      () async {
        // REGRESSION: the destination used to be resolved as "the first space
        // in client.spaces containing the call room". A room can sit in
        // several spaces, so iteration order decided whose destination policy
        // was applied - a sibling space could enforce its boundary on a play
        // it has no say over, or refuse a legitimate one.
        final sibling = _FakeMatrixSpace(
          '!sibling:example.org',
          roomIds: [_callRoomId],
        );
        final destination = _FakeMatrixSpace(_spaceId, roomIds: [_callRoomId]);
        // Sibling first: this is the one the old resolution would have picked.
        final multiParent = _FakeMatrixClient(spaces: [sibling, destination]);
        callManager.sessions.add(
          _FakeVoipSession(
            client: multiParent,
            roomId: _callRoomId,
            sessionId: 'session-1',
            state: VoipState.connected,
          ),
        );

        await service.handleMatrixPlayEvent(
          multiParent,
          callRoom,
          crossSpaceContent(),
          originServerTs: freshTs(),
          senderId: _alice,
        );

        expect(destination.componentLookups, greaterThan(0));
        expect(sibling.componentLookups, 0);
      },
    );

    test(
      'a named destination that does not contain the call room is refused',
      () async {
        // destination_space_room_id is in the event body and NOT covered by
        // the signature, so without this check a sender could name whichever
        // space happens to have the most permissive policy.
        final elsewhere = _FakeMatrixSpace(_spaceId, roomIds: const []);
        final client = _FakeMatrixClient(spaces: [elsewhere]);
        callManager.sessions.add(
          _FakeVoipSession(
            client: client,
            roomId: _callRoomId,
            sessionId: 'session-1',
            state: VoipState.connected,
          ),
        );

        await service.handleMatrixPlayEvent(
          client,
          callRoom,
          crossSpaceContent(),
          originServerTs: freshTs(),
          senderId: _alice,
        );

        expect(elsewhere.componentLookups, 0);
      },
    );
  });

  group('dedupe', () {
    test('a nonce is only retired once playback actually happens', () async {
      // Worth pinning because it is the opposite of the obvious guess: merely
      // receiving an event does NOT consume its nonce. A play that was
      // deferred (no session yet) must stay eligible, otherwise the retry that
      // the service itself scheduled would be dropped as a duplicate.
      callManager.sessions.add(
        _FakeVoipSession(
          client: client,
          roomId: _callRoomId,
          sessionId: 'session-1',
          state: VoipState.connected,
        ),
      );

      await handle(legacyContent(nonce: 'dupe-nonce'));
      final afterFirst = callManager.sessionLookups;
      await handle(legacyContent(nonce: 'dupe-nonce'));

      // Neither attempt reached playback (no sound state), so the second was
      // still processed rather than short-circuited by the nonce set.
      expect(callManager.sessionLookups, greaterThan(afterFirst));
    });
  });

  group('nonce set is bounded', () {
    test('stops growing past the cap and evicts the oldest', () {
      final cap = SoundboardPlaybackService.maxRememberedNonces;

      // The first nonce is the oldest; fill past the cap so it is evicted.
      expect(service.debugRememberNonce('oldest'), isTrue);
      for (var i = 0; i < cap + 10; i++) {
        service.debugRememberNonce('n-$i');
      }

      // Exactly the cap, not merely at-or-under it: eviction trims back to the
      // cap after every overflow, so an off-by-one there would leave cap-1 or
      // cap+1 and a <= assertion would wave both through.
      expect(service.debugRememberedNonceCount, cap);

      // The oldest was evicted, so its nonce is treated as new again...
      expect(service.debugRememberNonce('oldest'), isTrue);
      // ...while a recently-seen one is still deduped.
      expect(service.debugRememberNonce('n-${cap + 5}'), isFalse);
    });

    test('a repeated nonce is always a duplicate while still remembered', () {
      expect(service.debugRememberNonce('once'), isTrue);
      expect(service.debugRememberNonce('once'), isFalse);
    });
  });

  test('disposing cancels pending retries without throwing', () async {
    await handle(legacyContent());
    await service.dispose();

    // A second dispose is a no-op rather than an error.
    await service.dispose();
  });
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeCallManager implements CallManager {
  final NotifyingList<VoipSession> sessions = NotifyingList.empty(
    growable: true,
  );
  int sessionLookups = 0;

  @override
  NotifyingList<VoipSession> get currentSessions {
    sessionLookups++;
    return sessions;
  }

  @override
  bool get isDeafened => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVoipSession implements VoipSession {
  _FakeVoipSession({
    required this.client,
    required this.roomId,
    required this.sessionId,
    required this.state,
  });

  @override
  final Client client;

  @override
  final String roomId;

  @override
  final String sessionId;

  @override
  final VoipState state;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMatrixClient implements MatrixClient {
  _FakeMatrixClient({required List<Space> spaces}) : _spaces = spaces;

  final List<Space> _spaces;
  final List<String> spaceLookups = [];

  @override
  List<Space> get spaces => _spaces;

  @override
  Space? getSpace(String identifier) {
    spaceLookups.add(identifier);
    for (final space in _spaces) {
      if (space.identifier == identifier) {
        return space;
      }
    }
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMatrixRoom implements MatrixRoom {
  _FakeMatrixRoom(this._identifier);

  final String _identifier;

  @override
  String get identifier => _identifier;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMatrixSpace implements MatrixSpace {
  _FakeMatrixSpace(this._identifier, {required List<String> roomIds})
    : _rooms = roomIds.map(_FakeMatrixRoom.new).toList();

  final String _identifier;
  final List<_FakeMatrixRoom> _rooms;
  int componentLookups = 0;

  @override
  String get identifier => _identifier;

  @override
  List<Room> get roomsWithChildren => _rooms;

  @override
  T? getComponent<T extends SpaceComponent>() {
    componentLookups++;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
