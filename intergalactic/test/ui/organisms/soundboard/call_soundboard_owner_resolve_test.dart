import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/ui/organisms/soundboard/call_soundboard_panel.dart';

/// The picker re-resolves a tapped sound against the component that OWNS it
/// (resolveOwnedPlaySound) at tap time. For a cross-space pack the owner is the
/// SOURCE space's component, not the destination's — resolving against the
/// destination finds nothing and drops the tap silently, which was the bug the
/// owner routing fixed.
///
/// These are pure unit tests of the resolver, deliberately kept out of the
/// widget-test files: pumping the full panel needs a live VoipSession +
/// CallManager, and a plain unit test should not be gated behind the Flutter
/// binding init (which currently fails to load on Windows widget tests).
SoundboardSound _sound(
  String id, {
  required String name,
  bool deleted = false,
}) => SoundboardSound(
  id: id,
  name: name,
  emoji: 'x',
  mxcUri: Uri.parse('mxc://example.org/$id'),
  mimeType: 'audio/ogg',
  uploadedBy: '@alice:example.org',
  createdAt: DateTime.utc(2026, 7, 1),
  sizeBytes: 1000,
  deleted: deleted,
);

void main() {
  final owner = _FakeOwner([
    _sound('remote-1', name: 'Remote horn'),
    _sound('gone-but-deleted', name: 'Deleted', deleted: true),
  ]);
  final otherComponent = _FakeOwner([_sound('local-1', name: 'Local horn')]);

  test('resolves the tapped sound against the owner, by id', () {
    // A stale tapped copy resolves to the owner's CURRENT instance.
    final resolved = resolveOwnedPlaySound(
      owner,
      _sound('remote-1', name: 'stale copy'),
    );

    expect(resolved, isNotNull);
    expect(resolved!.name, 'Remote horn');
  });

  test('resolves against the OWNER, not some other component', () {
    // The cross-space fix: remote-1 lives only in `owner`; resolving it against
    // a different component must find nothing.
    expect(
      resolveOwnedPlaySound(otherComponent, _sound('remote-1', name: 'x')),
      isNull,
    );
    expect(
      resolveOwnedPlaySound(owner, _sound('remote-1', name: 'x')),
      isNotNull,
    );
  });

  test('a sound the owner no longer has resolves to null', () {
    expect(resolveOwnedPlaySound(owner, _sound('gone', name: 'Gone')), isNull);
  });

  test('an unavailable owner sound resolves to null', () {
    // Present in the owner's list but not available (deleted) — must not play.
    expect(
      resolveOwnedPlaySound(owner, _sound('gone-but-deleted', name: 'Deleted')),
      isNull,
    );
  });

  group('soundboardPlayFailureMessage', () {
    // The refusal codes the authority service can return on the playback path
    // cannot positively identify "the service is not in the source space", so
    // the service's own explanation must survive EVERY refusal. An earlier
    // revision replaced it on forbidden/not_found, which turned four unrelated
    // failures into "ask an admin to enable sound protection" — wrong advice,
    // and it presented an optional space feature as a prerequisite
    // (docs/DECISIONS.md, 2026-08-08).
    const hintFragment = 'can happen if';

    test('appends the source-space hint after the service message', () {
      final message = soundboardPlayFailureMessage(
        reason: SoundboardPlayRefusal.sourceSpaceUnavailable,
        serviceMessage: 'Source space is not available to the service.',
        sourceSpaceName: 'Space A',
      );

      // The service explanation must not be discarded.
      expect(
        message,
        startsWith('Source space is not available to the service.'),
      );
      expect(message, contains('Space A'));
      // Phrased as a possibility, never as an instruction: the cause was
      // narrowed, not confirmed.
      expect(message, contains(hintFragment));
      expect(message, isNot(contains('Ask an admin')));
      expect(message, isNot(contains('sound protection')));
      // Appending must not double the service message's full stop.
      expect(message, isNot(contains('..')));
    });

    test('adds the sentence break the service message did not end with', () {
      // The other half of the punctuation branch. The test above pins the
      // already-terminated case; without this one, deleting the `'$message.'`
      // fallback keeps the suite green and the hint runs straight on from the
      // service's own sentence.
      final message = soundboardPlayFailureMessage(
        reason: SoundboardPlayRefusal.sourceSpaceUnavailable,
        serviceMessage: 'Source space is not available to the service',
        sourceSpaceName: 'Space A',
      );

      expect(
        message,
        startsWith('Source space is not available to the service. This'),
      );
      expect(message, isNot(contains('..')));
    });

    test('quotes a space name that ends in punctuation', () {
      // An unquoted name ending in a full stop rendered as
      // `if My Space. is not set up`, which reads as a sentence that ended and
      // then carried on.
      final message = soundboardPlayFailureMessage(
        reason: SoundboardPlayRefusal.sourceSpaceUnavailable,
        serviceMessage: null,
        sourceSpaceName: 'My Space.',
      );

      expect(message, contains('"My Space."'));
    });

    test('names that space when the space name is blank', () {
      final message = soundboardPlayFailureMessage(
        reason: SoundboardPlayRefusal.sourceSpaceUnavailable,
        serviceMessage: null,
        sourceSpaceName: '   ',
      );

      expect(message, startsWith('Failed to play soundboard sound.'));
      expect(message, contains('that space'));
      expect(message, contains(hintFragment));
    });

    test('a deleted source sound keeps its message, no hint', () {
      // `forbidden` + "Source sound is unavailable." — the sound was deleted.
      // Enabling protection on the source space would change nothing.
      const service = 'Source sound is unavailable.';
      final message = soundboardPlayFailureMessage(
        reason: SoundboardPlayRefusal.authorizationRefused,
        serviceMessage: service,
        sourceSpaceName: 'Space A',
      );

      expect(message, service);
      expect(message, isNot(contains(hintFragment)));
    });

    test('a deleted or unshared pack keeps its message, no hint', () {
      const service = 'Source pack is unavailable.';
      final message = soundboardPlayFailureMessage(
        reason: SoundboardPlayRefusal.authorizationRefused,
        serviceMessage: service,
        sourceSpaceName: 'Space A',
      );

      expect(message, service);
      expect(message, isNot(contains(hintFragment)));
    });

    test('a caller-permission failure keeps its message, no hint', () {
      // The CALLER lacks source-space access; nothing an admin does to the
      // space's soundboard settings addresses it.
      const service = 'Caller cannot access the source space.';
      final message = soundboardPlayFailureMessage(
        reason: SoundboardPlayRefusal.authorizationRefused,
        serviceMessage: service,
        sourceSpaceName: 'Space A',
      );

      expect(message, service);
      expect(message, isNot(contains(hintFragment)));
    });

    test('a blocked destination policy keeps its message, no hint', () {
      const policy = 'This space does not allow sound packs from other spaces.';
      final message = soundboardPlayFailureMessage(
        reason: SoundboardPlayRefusal.authorizationRefused,
        serviceMessage: policy,
        sourceSpaceName: 'Space A',
      );

      // The hint would be wrong here: a blocked DESTINATION policy is not a
      // SOURCE-space setup problem.
      expect(message, policy);
      expect(message, isNot(contains(hintFragment)));
    });

    test('a missing message falls back to a generic string', () {
      final message = soundboardPlayFailureMessage(
        reason: SoundboardPlayRefusal.emissionFailed,
        serviceMessage: null,
        sourceSpaceName: 'Space A',
      );

      expect(message, 'Failed to play soundboard sound');
    });

    test('a blank service message is treated as missing', () {
      final message = soundboardPlayFailureMessage(
        reason: SoundboardPlayRefusal.emissionFailed,
        serviceMessage: '   ',
        sourceSpaceName: 'Space A',
      );

      expect(message, 'Failed to play soundboard sound');
    });
  });
}

class _FakeOwner implements SoundboardComponent {
  _FakeOwner(this._sounds);

  final List<SoundboardSound> _sounds;

  @override
  List<SoundboardSound> get sounds => _sounds;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
