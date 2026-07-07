import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';

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
      expect(SoundboardSound.fromState('bad', {'url': 'https://example.org'}),
          isNull);

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
  });
}
