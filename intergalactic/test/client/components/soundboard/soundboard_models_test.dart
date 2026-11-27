import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_authority_contract.dart';

void main() {
  group('SoundboardSound', () {
    test('round-trips Matrix state content', () {
      final createdAt = DateTime.utc(2026, 4, 26, 12);
      final sound = SoundboardSound(
        id: 'sound-1',
        name: 'Air horn',
        emoji: '📣',
        mxcUri: Uri.parse('mxc://example.org/media'),
        mimeType: 'audio/ogg',
        uploadedBy: '@alice:example.org',
        createdAt: createdAt,
        sizeBytes: 1234,
        durationMs: 900,
        volume: 72,
        packId: 'pack-1',
      );

      final parsed = SoundboardSound.fromState(
        sound.id,
        sound.toStateContent(),
      );

      expect(sound.toStateContent()['volume'], 72);
      expect(sound.toStateContent()['volume'], isA<int>());
      expect(parsed, isNotNull);
      expect(parsed!.id, sound.id);
      expect(parsed.name, sound.name);
      expect(parsed.emoji, sound.emoji);
      expect(parsed.mxcUri, sound.mxcUri);
      expect(parsed.mimeType, sound.mimeType);
      expect(parsed.uploadedBy, sound.uploadedBy);
      expect(parsed.createdAt, createdAt);
      expect(parsed.sizeBytes, sound.sizeBytes);
      expect(parsed.durationMs, sound.durationMs);
      expect(parsed.volume, sound.volume);
      expect(parsed.packId, sound.packId);
      expect(parsed.hasExplicitPackReference, isTrue);
      expect(parsed.legacyPackId, isNull);
      expect(parsed.isAvailable, isTrue);
    });

    test('defaults and clamps shared volume', () {
      final createdAt = DateTime.utc(2026, 4, 26, 12);
      final missingVolume = SoundboardSound.fromState('sound-1', {
        'name': 'Default',
        'emoji': 'x',
        'url': 'mxc://example.org/media',
        'mimetype': 'audio/ogg',
        'uploaded_by': '@alice:example.org',
        'created_at': createdAt.toIso8601String(),
        'size_bytes': 10,
      });
      final loudVolume = SoundboardSound.fromState('sound-2', {
        'name': 'Loud',
        'emoji': 'x',
        'url': 'mxc://example.org/media',
        'mimetype': 'audio/ogg',
        'uploaded_by': '@alice:example.org',
        'created_at': createdAt.toIso8601String(),
        'size_bytes': 10,
        'volume': 999,
      });
      final invalidVolume = SoundboardSound.fromState('sound-3', {
        'name': 'Invalid',
        'emoji': 'x',
        'url': 'mxc://example.org/media',
        'mimetype': 'audio/ogg',
        'uploaded_by': '@alice:example.org',
        'created_at': createdAt.toIso8601String(),
        'size_bytes': 10,
        'volume': double.nan,
      });

      expect(missingVolume?.volume, SoundboardSound.defaultVolume);
      expect(loudVolume?.volume, SoundboardSound.maxVolume);
      expect(invalidVolume?.volume, SoundboardSound.defaultVolume);
    });

    test('serializes fractional shared volume as canonical Matrix JSON', () {
      final sound = SoundboardSound(
        id: 'sound-1',
        name: 'Air horn',
        emoji: '📣',
        mxcUri: Uri.parse('mxc://example.org/media'),
        mimeType: 'audio/ogg',
        uploadedBy: '@alice:example.org',
        createdAt: DateTime.utc(2026, 4, 26, 12),
        sizeBytes: 1234,
        volume: 72.6,
      );

      expect(sound.toStateContent()['volume'], 73);
      expect(sound.toStateContent()['volume'], isA<int>());
    });

    test('rejects invalid state and hidden sounds are unavailable', () {
      expect(
        SoundboardSound.fromState('bad', {'url': 'https://example.org'}),
        isNull,
      );

      final hidden = SoundboardSound.fromState('sound-1', {
        'name': 'Hidden',
        'emoji': 'x',
        'url': 'mxc://example.org/media',
        'mimetype': 'audio/ogg',
        'uploaded_by': '@alice:example.org',
        'created_at': DateTime.utc(2026).toIso8601String(),
        'size_bytes': 10,
        'deleted': true,
      });

      expect(hidden, isNotNull);
      expect(hidden!.isAvailable, isFalse);
    });

    test(
      'only an absent pack reference uses deterministic legacy grouping',
      () {
        final createdAt = DateTime.utc(2026, 4, 26, 12).toIso8601String();
        Map<String, dynamic> content({Object? packId = _absent}) => {
          'name': 'Legacy sound',
          'emoji': 'x',
          'url': 'mxc://example.org/media',
          'mimetype': 'audio/ogg',
          'uploaded_by': '@alice:example.org',
          'created_at': createdAt,
          'size_bytes': 10,
          if (!identical(packId, _absent)) 'pack_id': packId,
        };

        final looseOne = SoundboardSound.fromState('sound-1', content());
        final looseTwo = SoundboardSound.fromState('sound-2', content());
        final explicit = SoundboardSound.fromState(
          'sound-3',
          content(packId: 'missing-pack'),
        );

        expect(looseOne?.hasExplicitPackReference, isFalse);
        expect(looseOne?.legacyPackId, looseTwo?.legacyPackId);
        expect(
          looseOne?.legacyPackId,
          SoundboardPack.legacyIdForUploader('@alice:example.org'),
        );
        expect(explicit?.hasExplicitPackReference, isTrue);
        expect(explicit?.legacyPackId, isNull);
        expect(SoundboardSound.fromState('bad', content(packId: '')), isNull);
        expect(SoundboardSound.fromState('bad', content(packId: 7)), isNull);
      },
    );
  });

  group('SoundboardPack', () {
    test('round-trips canonical Matrix state and source availability', () {
      final createdAt = DateTime.utc(2026, 7, 11, 12);
      final updatedAt = DateTime.utc(2026, 7, 11, 13);
      final pack = SoundboardPack(
        id: 'pack-1',
        name: 'Alerts',
        createdBy: '@alice:example.org',
        createdAt: createdAt,
        updatedAt: updatedAt,
        enabled: false,
        isLegacy: true,
      );

      final content = pack.toStateContent();
      final parsed = SoundboardPack.fromState(pack.id, content);

      expect(content, {
        'name': 'Alerts',
        'created_by': '@alice:example.org',
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'enabled': false,
        'deleted': false,
        'legacy': true,
      });
      expect(parsed?.id, pack.id);
      expect(parsed?.name, pack.name);
      expect(parsed?.createdBy, pack.createdBy);
      expect(parsed?.createdAt, createdAt);
      expect(parsed?.updatedAt, updatedAt);
      expect(parsed?.isLegacy, isTrue);
      expect(parsed?.isAvailable, isFalse);
    });

    test('parses the authority service pack schema (protected space)', () {
      // A service-written pack (protected space) records `creator_user_id` and
      // the inverse `disabled` instead of the app's `created_by`/`enabled`.
      // fromState must parse it, or the pack silently vanishes from the UI
      // ("packs don't create" / "rename reverts") - regression for QA 2026-07-19.
      final parsed = SoundboardPack.fromState('svc-pack', {
        'schema_version': 1,
        'pack_id': 'svc-pack',
        'name': 'Service Pack',
        'emoji': '🔊',
        'creator_user_id': '@alice:example.org',
        'created_at': '2026-07-19T00:00:00Z',
        'updated_at': '2026-07-19T00:00:00Z',
        'updated_by': '@alice:example.org',
        'revision': 4,
        'disabled': true,
        'deleted': false,
      });

      expect(parsed, isNotNull);
      expect(parsed!.name, 'Service Pack');
      expect(parsed.createdBy, '@alice:example.org'); // from creator_user_id
      expect(parsed.enabled, isFalse); // derived from disabled: true
      expect(parsed.isAvailable, isFalse);
      expect(parsed.revision, 4);
    });

    test('prefers the app enabled field over the service disabled field', () {
      // If both are present, the canonical `enabled` wins.
      final parsed = SoundboardPack.fromState('pack-1', {
        'name': 'Alerts',
        'created_by': '@alice:example.org',
        'created_at': '2026-07-19T00:00:00Z',
        'updated_at': '2026-07-19T00:00:00Z',
        'enabled': true,
        'disabled': true,
      });
      expect(parsed?.enabled, isTrue);
    });

    test('round-trips an optional icon emoji and omits it when unset', () {
      final base = SoundboardPack(
        id: 'pack-1',
        name: 'Alerts',
        createdBy: '@alice:example.org',
        createdAt: DateTime.utc(2026, 7, 11, 12),
        updatedAt: DateTime.utc(2026, 7, 11, 13),
      );

      // Unset: the emoji key is absent from state.
      expect(base.toStateContent().containsKey('emoji'), isFalse);
      expect(
        SoundboardPack.fromState(base.id, base.toStateContent())?.emoji,
        isNull,
      );

      final withIcon = base.copyWith(emoji: ':star:');
      final parsed = SoundboardPack.fromState(
        withIcon.id,
        withIcon.toStateContent(),
      );
      expect(withIcon.toStateContent()['emoji'], ':star:');
      expect(parsed?.emoji, ':star:');

      // clearEmoji drops it back to null.
      final cleared = withIcon.copyWith(clearEmoji: true);
      expect(cleared.emoji, isNull);
      expect(cleared.toStateContent().containsKey('emoji'), isFalse);

      // A blank/whitespace stored emoji parses as no icon.
      expect(
        SoundboardPack.fromState(base.id, {
          ...base.toStateContent(),
          'emoji': '   ',
        })?.emoji,
        isNull,
      );
    });

    test('derives stable opaque legacy ids per uploader', () {
      final aliceOne = SoundboardPack.legacyIdForUploader('@alice:example.org');
      final aliceTwo = SoundboardPack.legacyIdForUploader('@alice:example.org');
      final bob = SoundboardPack.legacyIdForUploader('@bob:example.org');

      expect(aliceOne, aliceTwo);
      expect(aliceOne, isNot(bob));
      expect(aliceOne, startsWith('legacy:'));
      expect(aliceOne, isNot(contains('@alice:example.org')));
    });

    test('numbers duplicate default legacy captions deterministically', () {
      final first = SoundboardPack.legacyForUploader(
        '@alice:example.org',
        createdAt: DateTime.utc(2026, 7, 1),
      );
      final second = SoundboardPack.legacyForUploader(
        '@bob:example.org',
        createdAt: DateTime.utc(2026, 7, 2),
      );
      final renamed = SoundboardPack.legacyForUploader(
        '@carol:example.org',
        createdAt: DateTime.utc(2026, 7, 3),
      ).copyWith(name: 'Carol\'s archive');
      final packs = [second, renamed, first];

      expect(soundboardPackDisplayName(first, packs), 'Legacy sounds 1');
      expect(soundboardPackDisplayName(second, packs), 'Legacy sounds 2');
      expect(soundboardPackDisplayName(renamed, packs), 'Carol\'s archive');
      expect(
        first.id,
        SoundboardPack.legacyIdForUploader('@alice:example.org'),
      );
      expect(first.name, 'Legacy sounds');
    });

    test('leaves a lone default legacy caption unnumbered', () {
      final only = SoundboardPack.legacyForUploader(
        '@alice:example.org',
        createdAt: DateTime.utc(2026, 7, 1),
      );
      final renamed = SoundboardPack.legacyForUploader(
        '@bob:example.org',
        createdAt: DateTime.utc(2026, 7, 2),
      ).copyWith(name: 'Bob\'s archive');

      // Alone in the space there is nothing to disambiguate against, so the
      // caption must stay bare. A gratuitous ' 1' on every single-uploader
      // space is the blemish this whole feature exists to avoid.
      expect(soundboardPackDisplayName(only, [only]), 'Legacy sounds');

      // A renamed pack is already distinct, so it must not be counted toward
      // the series and must not push the remaining default caption into one.
      expect(soundboardPackDisplayName(only, [only, renamed]), 'Legacy sounds');
      expect(
        soundboardPackDisplayName(renamed, [only, renamed]),
        'Bob\'s archive',
      );
    });

    test(
      'numbers persisted fallback captions without the historical legacy flag',
      () {
        final earlier = SoundboardPack(
          id: 'persisted-legacy-earlier',
          name: SoundboardPack.legacyDefaultName,
          createdBy: '@earlier:example.org',
          createdAt: DateTime.utc(2026, 8, 1),
          updatedAt: DateTime.utc(2026, 8, 1),
        );
        final later = SoundboardPack(
          id: 'persisted-legacy-later',
          name: SoundboardPack.legacyDefaultName,
          createdBy: '@later:example.org',
          createdAt: DateTime.utc(2026, 8, 2),
          updatedAt: DateTime.utc(2026, 8, 2),
        );
        final packs = [later, earlier];

        expect(earlier.isLegacy, isFalse);
        expect(later.isLegacy, isFalse);
        expect(soundboardPackDisplayName(earlier, packs), 'Legacy sounds 1');
        expect(soundboardPackDisplayName(later, packs), 'Legacy sounds 2');
      },
    );

    test('rejects malformed or inconsistent pack state', () {
      final valid = {
        'name': 'Alerts',
        'created_by': '@alice:example.org',
        'created_at': DateTime.utc(2026, 7, 11, 13).toIso8601String(),
        'updated_at': DateTime.utc(2026, 7, 11, 12).toIso8601String(),
      };

      expect(SoundboardPack.fromState('', valid), isNull);
      expect(
        SoundboardPack.fromState('pack-1', {...valid, 'name': ''}),
        isNull,
      );
      expect(SoundboardPack.fromState('pack-1', valid), isNull);
    });
  });

  group('SoundboardDestinationPolicy', () {
    test('absence allows external packs and explicit state round-trips', () {
      expect(
        SoundboardDestinationPolicy.fromState(null)?.allowExternalPacks,
        isTrue,
      );

      const blocked = SoundboardDestinationPolicy(allowExternalPacks: false);
      expect(
        SoundboardDestinationPolicy.fromState(
          blocked.toStateContent(),
        )?.allowExternalPacks,
        isFalse,
      );
    });

    test('rejects malformed explicit policy state', () {
      expect(
        SoundboardDestinationPolicy.fromState({'allow_external_packs': 'no'}),
        isNull,
      );
    });
  });

  group('SoundboardPlayEvent', () {
    test('round-trips play event content', () {
      const event = SoundboardPlayEvent(
        soundId: 'sound-1',
        spaceRoomId: '!space:example.org',
        nonce: 'nonce-1',
        source: 'manual',
        callSessionId: 'call-1',
      );

      final parsed = SoundboardPlayEvent.fromContent(event.toContent());

      expect(parsed, isNotNull);
      expect(parsed!.soundId, event.soundId);
      expect(parsed.spaceRoomId, event.spaceRoomId);
      expect(parsed.nonce, event.nonce);
      expect(parsed.source, event.source);
      expect(parsed.callSessionId, event.callSessionId);
    });

    test('falls back to manual source and rejects missing ids', () {
      final parsed = SoundboardPlayEvent.fromContent({
        'sound_id': 'sound-1',
        'space_room_id': '!space:example.org',
        'nonce': 'nonce-1',
      });

      expect(parsed?.source, 'manual');
      expect(SoundboardPlayEvent.fromContent({'sound_id': 'sound-1'}), isNull);
    });

    test('omits empty call session ids', () {
      const event = SoundboardPlayEvent(
        soundId: 'sound-1',
        spaceRoomId: '!space:example.org',
        nonce: 'nonce-1',
        source: 'manual',
        callSessionId: '',
      );

      expect(event.toContent().containsKey('call_session_id'), isFalse);
      expect(
        SoundboardPlayEvent.fromContent({
          ...event.toContent(),
          'call_session_id': '',
        })?.callSessionId,
        isNull,
      );
    });

    test('round-trips a source-qualified versioned playback snapshot', () {
      final playedAt = DateTime.utc(2026, 7, 11, 12);
      // This event is cross-space (source != destination), which since U7
      // requires a signed authorization to parse at all — see
      // soundboard_play_event_authorization_test.dart for that rule. The
      // authorization is included here so this test keeps testing what it is
      // about: snapshot round-tripping.
      final event = SoundboardPlayEvent.versioned(
        soundId: 'sound-1',
        packId: 'pack-1',
        sourceSpaceRoomId: '!source:example.org',
        destinationSpaceRoomId: '!destination:example.org',
        nonce: 'dedupe-1234',
        source: 'manual',
        callSessionId: 'call-1',
        playedAt: playedAt,
        snapshot: SoundboardPlaySnapshot(
          mxcUri: Uri.parse('mxc://example.org/media'),
          mimeType: 'audio/ogg',
          sizeBytes: 1234,
          durationMs: 900,
          volume: 72,
        ),
        authorization: SoundboardPlaybackAuthorization(
          schemaVersion: 1,
          authorizedUserId: '@alice:example.org',
          sourceSpaceId: '!source:example.org',
          destinationRoomId: '!destination:example.org',
          callSessionId: 'call-1',
          packId: 'pack-1',
          soundId: 'sound-1',
          media: SoundboardAuthorityMediaDescriptor(
            mxcUri: Uri.parse('mxc://example.org/media'),
            mimeType: 'audio/ogg',
            sizeBytes: 1234,
            durationMs: 900,
          ),
          nonce: 'dedupe-1234',
          expiresAt: DateTime.parse('2026-07-11T12:02:00.000Z'),
          expiresAtRaw: '2026-07-11T12:02:00.000Z',
          kid: 'sb-2026-07',
          signature: 'SIGNATURE',
        ),
      );

      final content = event.toContent();
      final parsed = SoundboardPlayEvent.fromContent(content, now: playedAt);

      expect(content['v'], SoundboardPlayEvent.currentVersion);
      expect(content['snapshot'], {
        'url': 'mxc://example.org/media',
        'mimetype': 'audio/ogg',
        'size_bytes': 1234,
        'duration_ms': 900,
        'volume': 72,
      });
      expect(parsed?.isLegacy, isFalse);
      expect(parsed?.soundId, event.soundId);
      expect(parsed?.packId, event.packId);
      expect(parsed?.sourceSpaceRoomId, event.sourceSpaceRoomId);
      expect(parsed?.destinationSpaceRoomId, event.destinationSpaceRoomId);
      expect(parsed?.spaceRoomId, event.sourceSpaceRoomId);
      expect(parsed?.playedAt, playedAt);
      expect(parsed?.snapshot?.mxcUri, event.snapshot?.mxcUri);
      expect(
        parsed?.isFreshAt(playedAt.add(const Duration(seconds: 31))),
        isFalse,
      );
    });

    test('rejects malformed, incomplete, or unsafe versioned snapshots', () {
      final now = DateTime.utc(2026, 7, 11, 12);
      final valid = SoundboardPlayEvent.versioned(
        soundId: 'sound-1',
        packId: 'pack-1',
        sourceSpaceRoomId: '!source:example.org',
        destinationSpaceRoomId: '!destination:example.org',
        nonce: 'dedupe-1234',
        source: 'manual',
        callSessionId: 'call-1',
        playedAt: now,
        snapshot: SoundboardPlaySnapshot(
          mxcUri: Uri.parse('mxc://example.org/media'),
          mimeType: 'audio/ogg',
          sizeBytes: 1234,
          durationMs: 900,
          volume: 72,
        ),
      ).toContent();

      Map<String, dynamic> withSnapshot(String key, Object? value) => {
        ...valid,
        'snapshot': {
          ...(valid['snapshot']! as Map<String, dynamic>),
          key: value,
        },
      };

      expect(
        SoundboardPlayEvent.fromContent({...valid, 'v': 99}, now: now),
        isNull,
      );
      expect(
        SoundboardPlayEvent.fromContent(
          {...valid}..remove('pack_id'),
          now: now,
        ),
        isNull,
      );
      expect(
        SoundboardPlayEvent.fromContent({
          ...valid,
          'source_space_room_id': '',
        }, now: now),
        isNull,
      );
      expect(
        SoundboardPlayEvent.fromContent({
          ...valid,
          'destination_space_room_id': '',
        }, now: now),
        isNull,
      );
      expect(
        SoundboardPlayEvent.fromContent({
          ...valid,
          'nonce': 'bad id!',
        }, now: now),
        isNull,
      );
      expect(
        SoundboardPlayEvent.fromContent(
          {...valid}..remove('snapshot'),
          now: now,
        ),
        isNull,
      );
      expect(
        SoundboardPlayEvent.fromContent(
          withSnapshot('url', 'https://x'),
          now: now,
        ),
        isNull,
      );
      expect(
        SoundboardPlayEvent.fromContent(
          withSnapshot('mimetype', 'text/x'),
          now: now,
        ),
        isNull,
      );
      expect(
        SoundboardPlayEvent.fromContent(
          withSnapshot('size_bytes', 0),
          now: now,
        ),
        isNull,
      );
      expect(
        SoundboardPlayEvent.fromContent(
          withSnapshot('size_bytes', SoundboardPlaySnapshot.maxSizeBytes + 1),
          now: now,
        ),
        isNull,
      );
      expect(
        SoundboardPlayEvent.fromContent(
          withSnapshot('duration_ms', 0),
          now: now,
        ),
        isNull,
      );
      expect(
        SoundboardPlayEvent.fromContent(
          withSnapshot('duration_ms', SoundboardPlaySnapshot.maxDurationMs + 1),
          now: now,
        ),
        isNull,
      );
      expect(
        SoundboardPlayEvent.fromContent(withSnapshot('volume', 151), now: now),
        isNull,
      );
      expect(
        SoundboardPlayEvent.fromContent({
          ...valid,
          'played_at': now
              .subtract(SoundboardPlayEvent.maxSnapshotAge)
              .subtract(const Duration(milliseconds: 1))
              .toIso8601String(),
        }, now: now),
        isNull,
      );
      expect(
        SoundboardPlayEvent.fromContent({
          ...valid,
          'played_at': now
              .add(SoundboardPlayEvent.maxFutureSkew)
              .add(const Duration(milliseconds: 1))
              .toIso8601String(),
        }, now: now),
        isNull,
      );
    });
  });

  group('SoundboardLocalPackSettings', () {
    test('round-trips overrides and drops malformed entries', () {
      const settings = SoundboardLocalPackSettings(
        overrides: {'pack-a': true, 'pack-b': false},
      );

      final parsed = SoundboardLocalPackSettings.fromContent(
        settings.toContent(),
      );
      expect(parsed.overrides, {'pack-a': true, 'pack-b': false});

      final tolerant = SoundboardLocalPackSettings.fromContent({
        'active_overrides': {
          'pack-a': true,
          'pack-bad': 'yes',
          '': true,
          'pack-c': false,
        },
      });
      expect(tolerant.overrides, {'pack-a': true, 'pack-c': false});

      expect(SoundboardLocalPackSettings.fromContent(null).overrides, isEmpty);
      expect(
        SoundboardLocalPackSettings.fromContent({
          'active_overrides': 3,
        }).overrides,
        isEmpty,
      );
    });

    test('withOverride sets and removes deviations', () {
      const settings = SoundboardLocalPackSettings(overrides: {'pack-a': true});

      expect(settings.withOverride('pack-b', false).overrides, {
        'pack-a': true,
        'pack-b': false,
      });
      expect(settings.withOverride('pack-a', null).overrides, isEmpty);
    });
  });

  group('SoundboardSound pack reference copyWith', () {
    test('clearPackId removes the reference; packId keeps or replaces it', () {
      final sound = SoundboardSound(
        id: 'sound-1',
        name: 'Sound',
        emoji: '🔊',
        mxcUri: Uri.parse('mxc://example.org/sound-1'),
        mimeType: 'audio/ogg',
        uploadedBy: '@alice:example.org',
        createdAt: DateTime.utc(2026, 7, 1),
        sizeBytes: 100,
        packId: 'pack-a',
      );

      expect(sound.copyWith().packId, 'pack-a');
      expect(sound.copyWith(packId: 'pack-b').packId, 'pack-b');

      final cleared = sound.copyWith(clearPackId: true);
      expect(cleared.packId, isNull);
      expect(cleared.hasExplicitPackReference, isFalse);
      expect(
        cleared.legacyPackId,
        SoundboardPack.legacyIdForUploader('@alice:example.org'),
      );
      expect(cleared.toStateContent().containsKey('pack_id'), isFalse);
    });
  });
}

const Object _absent = Object();
