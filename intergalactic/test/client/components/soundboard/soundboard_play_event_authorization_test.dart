import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_authority_contract.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_playback_signing.dart';

const _sourceSpace = '!source:ourgalaxy.space';
const _destinationSpace = '!destination:ourgalaxy.space';

/// U7: the v2 play event carrying a signed authorization, and the rule that
/// makes cross-space playback unforgeable — an event that names a source space
/// other than the destination is not parseable at all without one.
void main() {
  SoundboardPlaybackAuthorization authorization({String soundId = 'sound-1'}) =>
      SoundboardPlaybackAuthorization(
        schemaVersion: 1,
        authorizedUserId: '@alice:ourgalaxy.space',
        sourceSpaceId: _sourceSpace,
        destinationRoomId: '!call:ourgalaxy.space',
        callSessionId: 'session-1',
        packId: 'pack-1',
        soundId: soundId,
        media: SoundboardAuthorityMediaDescriptor(
          mxcUri: Uri.parse('mxc://ourgalaxy.space/media'),
          mimeType: 'audio/ogg',
          sizeBytes: 12345,
          durationMs: 1200,
        ),
        nonce: 'nonce-play1',
        expiresAt: DateTime.parse('2026-07-28T00:02:00.000Z'),
        expiresAtRaw: '2026-07-28T00:02:00.000Z',
        kid: 'sb-2026-07',
        signature: 'SIGNATURE',
      );

  SoundboardPlaySnapshot snapshot() => SoundboardPlaySnapshot(
    mxcUri: Uri.parse('mxc://ourgalaxy.space/media'),
    mimeType: 'audio/ogg',
    sizeBytes: 12345,
    durationMs: 1200,
    volume: 100,
  );

  SoundboardPlayEvent event({
    String sourceSpaceRoomId = _sourceSpace,
    String destinationSpaceRoomId = _destinationSpace,
    SoundboardPlaybackAuthorization? auth,
    DateTime? playedAt,
  }) => SoundboardPlayEvent.versioned(
    soundId: 'sound-1',
    packId: 'pack-1',
    sourceSpaceRoomId: sourceSpaceRoomId,
    destinationSpaceRoomId: destinationSpaceRoomId,
    nonce: 'nonce-play-1',
    source: 'manual',
    playedAt: playedAt ?? DateTime.utc(2026, 7, 28),
    snapshot: snapshot(),
    callSessionId: 'session-1',
    authorization: auth,
  );

  final now = DateTime.utc(2026, 7, 28, 0, 0, 5);

  group('cross-space classification', () {
    test('a play into another space is cross-space', () {
      expect(event().isCrossSpace, isTrue);
    });

    test('a play within one space is not', () {
      expect(event(sourceSpaceRoomId: _destinationSpace).isCrossSpace, isFalse);
    });

    test('a legacy event is never cross-space', () {
      // Legacy events predate the concept and name a single space.
      const legacy = SoundboardPlayEvent(
        soundId: 'sound-1',
        spaceRoomId: _sourceSpace,
        nonce: 'nonce-1',
        source: 'manual',
      );

      expect(legacy.isCrossSpace, isFalse);
      expect(legacy.authorization, isNull);
    });
  });

  group('authorization transport', () {
    test('round-trips on the event content', () {
      final parsed = SoundboardPlayEvent.fromContent(
        event(auth: authorization()).toContent(),
        now: now,
      );

      expect(parsed, isNotNull);
      expect(parsed!.authorization, isNotNull);
      expect(parsed.authorization!.soundId, 'sound-1');
      expect(parsed.authorization!.kid, 'sb-2026-07');
      // The signed bytes survive transport unchanged, which is the whole point.
      expect(
        parsed.authorization!.signedBytes(),
        authorization().signedBytes(),
      );
    });

    test('a same-space play needs no authorization', () {
      final parsed = SoundboardPlayEvent.fromContent(
        event(sourceSpaceRoomId: _destinationSpace).toContent(),
        now: now,
      );

      expect(parsed, isNotNull);
      expect(parsed!.authorization, isNull);
      expect(parsed.isCrossSpace, isFalse);
    });

    test(
      'a same-space event omits the field entirely rather than nulling it',
      () {
        expect(
          event(sourceSpaceRoomId: _destinationSpace).toContent(),
          isNot(contains('authorization')),
        );
      },
    );
  });

  group('cross-space refusals at parse time', () {
    test('a cross-space play WITHOUT an authorization does not parse', () {
      // The important one: refusing here means no later code has to remember
      // to check. The only way to play another space's sound is to carry the
      // service's signature for it.
      final content = event().toContent();
      expect(content.containsKey('authorization'), isFalse);

      expect(SoundboardPlayEvent.fromContent(content, now: now), isNull);
    });

    test('a cross-space play with a stripped authorization does not parse', () {
      final content = Map<String, dynamic>.from(
        event(auth: authorization()).toContent(),
      )..remove('authorization');

      expect(SoundboardPlayEvent.fromContent(content, now: now), isNull);
    });

    test('a malformed authorization rejects the event, not just the field', () {
      // Otherwise a sender could attach garbage and have it silently dropped,
      // downgrading to an unauthorized play.
      for (final malformed in <Object?>[
        'nonsense',
        <String, dynamic>{},
        {'kid': 'sb-2026-07'},
      ]) {
        final content = Map<String, dynamic>.from(
          event(auth: authorization()).toContent(),
        )..['authorization'] = malformed;

        expect(
          SoundboardPlayEvent.fromContent(content, now: now),
          isNull,
          reason: 'malformed authorization $malformed must reject the event',
        );
      }
    });

    test('a stale cross-space event is still refused on freshness', () {
      // Carrying an authorization does not exempt an event from the snapshot
      // freshness window.
      final parsed = SoundboardPlayEvent.fromContent(
        event(auth: authorization()).toContent(),
        now: DateTime.utc(2026, 7, 28, 1),
      );

      expect(parsed, isNull);
    });
  });
}
