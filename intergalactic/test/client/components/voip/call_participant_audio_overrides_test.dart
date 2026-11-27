import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/voip/call_participant_audio_overrides.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';

void main() {
  group('CallParticipantAudioOverrides', () {
    test('keys participant audio by stable Matrix user identity', () async {
      final overrides = CallParticipantAudioOverrides();
      final original = _FakePlaybackStream(
        streamUserId: '@friend:example.org',
        streamId: 'livekit-audio-sid-1',
        localVolume: 1,
      );
      final replacement = _FakePlaybackStream(
        streamUserId: '@friend:example.org',
        streamId: 'livekit-audio-sid-2',
        localVolume: 1,
      );

      overrides.remember(
        original,
        volume: 0.35,
        defaultVolume: 1,
        isMicrophoneAudio: true,
      );

      final restored = await overrides.restore(
        replacement,
        isMicrophoneAudio: true,
      );

      expect(restored, isTrue);
      expect(replacement.setVolumes, [0.35]);
      expect(overrides.length, 1);
    });

    test(
      'survives UI rebuild-style helper recreation with retained state',
      () async {
        final retainedState = <String, double>{};
        final firstBuildOverrides = CallParticipantAudioOverrides(
          initialValues: retainedState,
        );
        final rebuiltOverrides = CallParticipantAudioOverrides(
          initialValues: retainedState,
        );
        final original = _FakePlaybackStream(
          streamUserId: '@rebuild:example.org',
          streamId: 'stream-before-rebuild',
          localVolume: 1,
        );
        final replacement = _FakePlaybackStream(
          streamUserId: '@rebuild:example.org',
          streamId: 'stream-after-rebuild',
          localVolume: 1,
        );

        firstBuildOverrides.remember(
          original,
          volume: 0.45,
          defaultVolume: 1,
          isMicrophoneAudio: true,
        );

        final restored = await rebuiltOverrides.restore(
          replacement,
          isMicrophoneAudio: true,
        );

        expect(restored, isTrue);
        expect(replacement.setVolumes, [0.45]);
        expect(firstBuildOverrides.length, 1);
        expect(rebuiltOverrides.length, 1);
      },
    );

    test('metadata updates do not reset a stable-user override', () async {
      final overrides = CallParticipantAudioOverrides();
      final original = _FakePlaybackStream(
        streamUserId: '@renamed:example.org',
        streamId: 'stream-before-metadata',
        label: 'Old display name',
        localVolume: 1,
      );
      final metadataReplacement = _FakePlaybackStream(
        streamUserId: '@renamed:example.org',
        streamId: 'stream-after-metadata',
        label: 'New display name',
        localVolume: 1,
      );

      overrides.remember(
        original,
        volume: 0,
        defaultVolume: 1,
        isMicrophoneAudio: true,
      );

      final restored = await overrides.restore(
        metadataReplacement,
        isMicrophoneAudio: true,
      );

      expect(restored, isTrue);
      expect(metadataReplacement.setVolumes, [0]);
      expect(metadataReplacement.locallyMuted, isTrue);
      expect(overrides.length, 1);
    });

    test(
      'shared display metadata does not leak override across users',
      () async {
        final overrides = CallParticipantAudioOverrides();
        final original = _FakePlaybackStream(
          streamUserId: '@alpha:example.org',
          streamId: 'alpha-stream',
          label: 'Shared display name',
          localVolume: 1,
        );
        final differentUser = _FakePlaybackStream(
          streamUserId: '@beta:example.org',
          streamId: 'beta-stream',
          label: 'Shared display name',
          localVolume: 1,
        );

        overrides.remember(
          original,
          volume: 0.3,
          defaultVolume: 1,
          isMicrophoneAudio: true,
        );

        final restored = await overrides.restore(
          differentUser,
          isMicrophoneAudio: true,
        );

        expect(restored, isFalse);
        expect(differentUser.setVolumes, isEmpty);
        expect(overrides.length, 1);
      },
    );

    test(
      'restores independent overrides after participants leave and rejoin',
      () async {
        final overrides = CallParticipantAudioOverrides();
        final alphaBefore = _FakePlaybackStream(
          streamUserId: '@alpha:example.org',
          streamId: 'alpha-before',
          localVolume: 1,
        );
        final betaBefore = _FakePlaybackStream(
          streamUserId: '@beta:example.org',
          streamId: 'beta-before',
          localVolume: 1,
        );
        final alphaAfterRejoin = _FakePlaybackStream(
          streamUserId: '@alpha:example.org',
          streamId: 'alpha-after-rejoin',
          localVolume: 1,
        );
        final betaAfterRejoin = _FakePlaybackStream(
          streamUserId: '@beta:example.org',
          streamId: 'beta-after-rejoin',
          localVolume: 1,
        );

        overrides.remember(
          alphaBefore,
          volume: 0,
          defaultVolume: 1,
          isMicrophoneAudio: true,
        );
        overrides.remember(
          betaBefore,
          volume: 0.65,
          defaultVolume: 1,
          isMicrophoneAudio: true,
        );

        expect(
          await overrides.restore(alphaAfterRejoin, isMicrophoneAudio: true),
          isTrue,
        );
        expect(
          await overrides.restore(betaAfterRejoin, isMicrophoneAudio: true),
          isTrue,
        );

        expect(alphaAfterRejoin.setVolumes, [0]);
        expect(alphaAfterRejoin.locallyMuted, isTrue);
        expect(betaAfterRejoin.setVolumes, [0.65]);
        expect(betaAfterRejoin.locallyMuted, isFalse);
        expect(overrides.length, 2);
      },
    );

    test(
      'restores zero volume as a local mute on replacement stream',
      () async {
        final overrides = CallParticipantAudioOverrides();
        final original = _FakePlaybackStream(
          streamUserId: '@muted:example.org',
          streamId: 'stream-before',
          localVolume: 1,
        );
        final replacement = _FakePlaybackStream(
          streamUserId: '@muted:example.org',
          streamId: 'stream-after',
          localVolume: 1,
        );

        overrides.remember(
          original,
          volume: 0,
          defaultVolume: 1,
          isMicrophoneAudio: true,
        );

        final restored = await overrides.restore(
          replacement,
          isMicrophoneAudio: true,
        );

        expect(restored, isTrue);
        expect(replacement.setVolumes, [0]);
        expect(replacement.locallyMuted, isTrue);
      },
    );

    test(
      'reports stale stream restore failure without dropping override',
      () async {
        final overrides = CallParticipantAudioOverrides();
        final original = _FakePlaybackStream(
          streamUserId: '@stale:example.org',
          streamId: 'stream-before',
          localVolume: 1,
        );
        final staleReplacement = _FakePlaybackStream(
          streamUserId: '@stale:example.org',
          streamId: 'stream-stale',
          localVolume: 1,
          throwOnSetLocalVolume: true,
        );
        final healthyReplacement = _FakePlaybackStream(
          streamUserId: '@stale:example.org',
          streamId: 'stream-after',
          localVolume: 1,
        );
        Object? reportedError;
        StackTrace? reportedStackTrace;

        overrides.remember(
          original,
          volume: 0.4,
          defaultVolume: 1,
          isMicrophoneAudio: true,
        );

        final staleRestored = await overrides.restore(
          staleReplacement,
          isMicrophoneAudio: true,
          onError: (error, stackTrace) {
            reportedError = error;
            reportedStackTrace = stackTrace;
          },
        );
        final healthyRestored = await overrides.restore(
          healthyReplacement,
          isMicrophoneAudio: true,
        );

        expect(staleRestored, isFalse);
        expect(reportedError, isA<StateError>());
        expect(reportedStackTrace, isNotNull);
        expect(overrides.length, 1);
        expect(healthyRestored, isTrue);
        expect(healthyReplacement.setVolumes, [0.4]);
      },
    );

    test('clears stored override when volume returns to default', () async {
      final overrides = CallParticipantAudioOverrides();
      final stream = _FakePlaybackStream(
        streamUserId: '@friend:example.org',
        streamId: 'livekit-audio-sid',
        localVolume: 0.5,
      );

      overrides.remember(
        stream,
        volume: 0.5,
        defaultVolume: 1,
        isMicrophoneAudio: true,
      );
      overrides.remember(
        stream,
        volume: 1,
        defaultVolume: 1,
        isMicrophoneAudio: true,
      );

      final restored = await overrides.restore(stream, isMicrophoneAudio: true);

      expect(overrides.length, 0);
      expect(stream.clearOverrideCount, 1);
      expect(restored, isFalse);
    });

    test('ignores screenshare and non-microphone audio streams', () async {
      final overrides = CallParticipantAudioOverrides();
      final screenshare = _FakePlaybackStream(
        streamUserId: '@friend:example.org',
        streamId: 'screen',
        type: VoipStreamType.screenshare,
      );
      final sharedAudio = _FakePlaybackStream(
        streamUserId: '@friend:example.org',
        streamId: 'screen-audio',
      );

      overrides.remember(
        screenshare,
        volume: 0.2,
        defaultVolume: 1,
        isMicrophoneAudio: true,
      );
      overrides.remember(
        sharedAudio,
        volume: 0.2,
        defaultVolume: 1,
        isMicrophoneAudio: false,
      );

      expect(overrides.length, 0);
      expect(
        await overrides.restore(screenshare, isMicrophoneAudio: true),
        isFalse,
      );
      expect(
        await overrides.restore(sharedAudio, isMicrophoneAudio: false),
        isFalse,
      );
      expect(screenshare.setVolumes, isEmpty);
      expect(sharedAudio.setVolumes, isEmpty);
    });

    test('skips restore when the replacement already matches', () async {
      final overrides = CallParticipantAudioOverrides();
      final stream = _FakePlaybackStream(
        streamUserId: '@friend:example.org',
        streamId: 'stream',
        localVolume: 0.5,
      );

      overrides.remember(
        stream,
        volume: 0.5,
        defaultVolume: 1,
        isMicrophoneAudio: true,
      );

      final restored = await overrides.restore(stream, isMicrophoneAudio: true);

      expect(restored, isFalse);
      expect(stream.setVolumes, isEmpty);
    });

    test('restore does not un-deafen a participant (BUG-282)', () async {
      // Regression for 2026-08-02T01:38:27.890Z: the two participants holding a
      // stored non-default volume un-deafened themselves 3 ms after Deafen was
      // pressed, because restore ran from the call-tile build path on the very
      // next frame.
      final overrides = CallParticipantAudioOverrides();
      final stream = _FakePlaybackStream(
        streamUserId: '@friend:example.org',
        streamId: 'TR_AMQjM67kWjTj7Y',
        localVolume: 1.1,
      );

      overrides.remember(
        stream,
        volume: 1.1,
        defaultVolume: 1.25,
        isMicrophoneAudio: true,
      );

      // Deafen: the mute bit is asserted, the volume is deliberately untouched.
      stream.ownerMuted = true;

      final restored = await overrides.restore(stream, isMicrophoneAudio: true);

      expect(restored, isFalse, reason: 'restore must not fight deafen');
      expect(stream.setVolumes, isEmpty);
      expect(stream.ownerMuted, isTrue, reason: 'still deafened');
      expect(stream.localVolume, 1.1, reason: 'stored volume kept for unmute');
    });

    test(
      'restore still corrects a stale volume without unmuting (BUG-282)',
      () async {
        // The republish case: a new stream object starts at the default volume
        // and the stored override must still be reinstated - but a mute that
        // was asserted meanwhile is not the restorer's to clear.
        final overrides = CallParticipantAudioOverrides();
        final original = _FakePlaybackStream(
          streamUserId: '@friend:example.org',
          streamId: 'TR_old',
          localVolume: 1.1,
        );
        overrides.remember(
          original,
          volume: 1.1,
          defaultVolume: 1.25,
          isMicrophoneAudio: true,
        );

        final replacement = _FakePlaybackStream(
          streamUserId: '@friend:example.org',
          streamId: 'TR_new',
          localVolume: 1.25,
        )..ownerMuted = true;

        final restored = await overrides.restore(
          replacement,
          isMicrophoneAudio: true,
        );

        expect(restored, isTrue, reason: 'volume genuinely differed');
        expect(replacement.setVolumes, [1.1]);
        expect(
          replacement.ownerMuted,
          isTrue,
          reason: 'correcting the volume must not clear the mute',
        );
      },
    );

    test('restore of a stored zero still mutes a fresh stream', () async {
      // Guard the other direction: preserving-mute must not become
      // never-mute. A remembered 0.0 is the user muting that participant.
      final overrides = CallParticipantAudioOverrides();
      final original = _FakePlaybackStream(
        streamUserId: '@friend:example.org',
        streamId: 'TR_old',
        localVolume: 0,
      );
      overrides.remember(
        original,
        volume: 0,
        defaultVolume: 1.25,
        isMicrophoneAudio: true,
      );

      final replacement = _FakePlaybackStream(
        streamUserId: '@friend:example.org',
        streamId: 'TR_new',
        localVolume: 1.25,
      );

      final restored = await overrides.restore(
        replacement,
        isMicrophoneAudio: true,
      );

      expect(restored, isTrue);
      expect(replacement.setVolumes, [0]);
      expect(replacement.locallyMuted, isTrue);
    });
  });

  group('CallParticipantAudioOverridesStore', () {
    setUp(CallParticipantAudioOverridesStore.reset);
    tearDown(CallParticipantAudioOverridesStore.reset);

    test('survives leaving and rejoining the same room', () {
      // The whole point of the store: the same client and room resolve to the
      // same key on every join, so a rejoin gets the same volumes back. The
      // container this replaced was keyed partly on `identityHashCode(session)`
      // and a rejoin produces a fresh session object, so it came back empty.
      //
      // This calls `keyFor` with an explicit session id, which exercises the
      // optional narrowing branch rather than the production entry point. The
      // `keyForSession` test below is the one that pins the real key contract.
      final key = CallParticipantAudioOverridesStore.keyFor(
        clientIdentifier: 'client-1',
        roomId: '!room:example.org',
        sessionId: 'client-1_!room:example.org_@me:example.org',
      );
      final stream = _FakePlaybackStream(
        streamUserId: '@friend:example.org',
        streamId: 'livekit-audio-sid-1',
        localVolume: 1,
      );

      CallParticipantAudioOverridesStore.forKey(key).remember(
        stream,
        volume: 1.4,
        defaultVolume: 1,
        isMicrophoneAudio: true,
      );

      final afterRejoin = CallParticipantAudioOverridesStore.forKey(key);

      expect(afterRejoin.length, 1);
      expect(afterRejoin.storedVolumes, [1.4]);
    });

    test('keeps different rooms and different clients apart', () {
      final roomA = CallParticipantAudioOverridesStore.keyFor(
        clientIdentifier: 'client-1',
        roomId: '!a:example.org',
        sessionId: 'session-a',
      );
      final roomB = CallParticipantAudioOverridesStore.keyFor(
        clientIdentifier: 'client-1',
        roomId: '!b:example.org',
        sessionId: 'session-b',
      );
      final otherClient = CallParticipantAudioOverridesStore.keyFor(
        clientIdentifier: 'client-2',
        roomId: '!a:example.org',
        sessionId: 'session-a',
      );

      expect(roomA, isNot(roomB));
      expect(roomA, isNot(otherClient));
      expect(
        CallParticipantAudioOverridesStore.forKey(roomA),
        isNot(same(CallParticipantAudioOverridesStore.forKey(roomB))),
      );
    });

    test('keyForSession ignores the session id entirely', () {
      // The regression guard for the direct-call defect. `keyForSession`
      // deliberately does not pass `session.sessionId`, because the two session
      // types spell it differently and only one is stable:
      // `MatrixLivekitVoipSession` gives `client_room_stateKey`, but
      // `MatrixVoipSession` gives `client_callId` and the SDK mints a fresh
      // `callId` per direct call - so 1:1 calls re-keyed on every call and lost
      // the volumes this store exists to preserve.
      //
      // Two sessions, same client and room, deliberately different session ids.
      // This fails the moment someone puts `session.sessionId` back.
      final client = _FakeClient('client-1');
      final firstCall = _FakeKeySession(
        client: client,
        roomId: '!room:example.org',
        sessionId: 'client-1_call-aaaa',
      );
      final secondCall = _FakeKeySession(
        client: client,
        roomId: '!room:example.org',
        sessionId: 'client-1_call-bbbb',
      );

      expect(
        CallParticipantAudioOverridesStore.keyForSession(firstCall),
        CallParticipantAudioOverridesStore.keyForSession(secondCall),
      );
      expect(
        CallParticipantAudioOverridesStore.forSession(firstCall),
        same(CallParticipantAudioOverridesStore.forSession(secondCall)),
      );

      // The grain is still per room: a different room must not collide.
      final otherRoom = _FakeKeySession(
        client: client,
        roomId: '!other:example.org',
        sessionId: 'client-1_call-aaaa',
      );
      expect(
        CallParticipantAudioOverridesStore.keyForSession(firstCall),
        isNot(CallParticipantAudioOverridesStore.keyForSession(otherRoom)),
      );
    });

    test('falls back to a stable key when the session id is blank', () {
      expect(
        CallParticipantAudioOverridesStore.keyFor(
          clientIdentifier: 'client-1',
          roomId: '!room:example.org',
          sessionId: '   ',
        ),
        CallParticipantAudioOverridesStore.keyFor(
          clientIdentifier: 'client-1',
          roomId: '!room:example.org',
          sessionId: '',
        ),
      );
    });

    // FIFO, not LRU, and this test is what pins that. `call-0` is READ
    // immediately before the overflow insert and is still the entry evicted -
    // a least-recently-used store would have renewed it on that read and
    // evicted `call-1` instead. If a later change makes eviction LRU, this
    // test is the one that should fail, and this is the reason.
    test('evicts the oldest INSERTED call once the cap is reached', () {
      for (
        var i = 0;
        i < CallParticipantAudioOverridesStore.maxRetainedCalls;
        i++
      ) {
        CallParticipantAudioOverridesStore.forKey('call-$i');
      }
      final firstBeforeOverflow = CallParticipantAudioOverridesStore.forKey(
        'call-0',
      );
      final survivorBeforeOverflow = CallParticipantAudioOverridesStore.forKey(
        'call-1',
      );

      CallParticipantAudioOverridesStore.forKey('call-overflow');

      // "Evict one, keep the rest" - not merely "evict something". A store that
      // cleared every entry on reaching the cap would satisfy the eviction
      // assertion below on its own, and would silently drop every other call's
      // volumes.
      //
      // Asserted FIRST, and that ordering is load-bearing: `forKey` is a read
      // that inserts on a miss, so re-reading the evicted `call-0` below is
      // itself an overflow insert, and it evicts the next-oldest key - which is
      // `call-1`. Checking the survivor afterwards would fail against a
      // perfectly healthy store.
      expect(
        CallParticipantAudioOverridesStore.forKey('call-1'),
        same(survivorBeforeOverflow),
      );
      expect(
        CallParticipantAudioOverridesStore.forKey('call-0'),
        isNot(same(firstBeforeOverflow)),
      );
    });
  });
}

class _FakePlaybackStream implements VoipStream, LocalPlaybackVolumeStream {
  _FakePlaybackStream({
    required this.streamUserId,
    required this.streamId,
    this.type = VoipStreamType.audio,
    String? label,
    this.localVolume = 1,
    this.throwOnSetLocalVolume = false,
  }) : label = label ?? streamUserId;

  @override
  final String streamUserId;

  @override
  final String streamId;

  @override
  final VoipStreamType type;

  @override
  double localVolume;

  final bool throwOnSetLocalVolume;
  final List<double> setVolumes = <double>[];
  int clearOverrideCount = 0;

  /// Mute asserted by an owner other than the volume slider - deafen, or the
  /// screenshare tile-visibility policy.
  ///
  /// Production keeps this separate from the volume
  /// (`MatrixLivekitVoipStream._locallyMuted`), and the two disagree in exactly
  /// the state that caused BUG-282: deafened at volume 1.10. This fake used to
  /// derive `locallyMuted` from `localVolume <= 0`, which made that state
  /// unrepresentable - so no test in this file could observe the bug.
  bool ownerMuted = false;

  @override
  bool get hasLocalPlaybackAudio => true;

  @override
  bool get hasLocalPlaybackVolumeOverride => setVolumes.isNotEmpty;

  @override
  bool get locallyMuted => ownerMuted || localVolume <= 0;

  @override
  Future<void> setLocalVolume(double volume) async {
    if (throwOnSetLocalVolume) {
      throw StateError('stale playback stream');
    }
    localVolume = volume;
    ownerMuted = volume <= 0;
    setVolumes.add(volume);
  }

  @override
  Future<void> setLocalVolumePreservingMute(double volume) async {
    if (throwOnSetLocalVolume) {
      throw StateError('stale playback stream');
    }
    localVolume = volume;
    if (volume <= 0) {
      ownerMuted = true;
    }
    setVolumes.add(volume);
  }

  @override
  Future<void> setDefaultLocalVolume(double volume) {
    return setLocalVolume(volume);
  }

  @override
  void clearLocalPlaybackVolumeOverride() {
    clearOverrideCount++;
  }

  @override
  double? get aspectRatio => null;

  @override
  double get audiolevel => 0;

  @override
  Widget? buildVideoRenderer(BoxFit fit, Key key) => null;

  @override
  VoipStreamDirection get direction => VoipStreamDirection.incoming;

  @override
  bool get isMuted => locallyMuted;

  @override
  final String label;

  @override
  Stream<void> get onStreamChanged => const Stream<void>.empty();

  @override
  VoipStreamReceivePriority get receivePriority =>
      VoipStreamReceivePriority.high;

  @override
  Future<void> setReceivePriority(VoipStreamReceivePriority priority) async {}
}

/// Minimal client stand-in: `keyForSession` reads only [identifier].
class _FakeClient extends Fake implements Client {
  _FakeClient(this.identifier);

  @override
  final String identifier;
}

/// Session stand-in whose [sessionId] is deliberately variable.
///
/// `extends Fake` rather than a full `implements VoipSession`: every unstubbed
/// member throws, so if `keyForSession` ever starts reading something else this
/// test fails loudly instead of silently keying on a default.
class _FakeKeySession extends Fake implements VoipSession {
  _FakeKeySession({
    required this.client,
    required this.roomId,
    required this.sessionId,
  });

  @override
  final Client client;

  @override
  final String roomId;

  @override
  final String sessionId;
}
