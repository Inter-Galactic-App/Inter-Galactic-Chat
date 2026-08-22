import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';

const _source = '!source:example.org';
const _destination = '!destination:example.org';

/// U6: a destination space's policy on packs owned by other spaces, and the
/// single evaluator both the sender and the receiver run.
void main() {
  SoundboardExternalPackEvaluation evaluate({
    String sourceSpaceId = _source,
    String? destinationSpaceId = _destination,
    SoundboardDestinationPolicy policy = SoundboardDestinationPolicy.allowed,
  }) => SoundboardExternalPackEvaluation.evaluate(
    sourceSpaceId: sourceSpaceId,
    destinationSpaceId: destinationSpaceId,
    destinationPolicy: policy,
  );

  group('policy parsing (absence means allow)', () {
    test('a space with no policy event allows external packs', () {
      expect(
        SoundboardDestinationPolicy.resolve(null).allowExternalPacks,
        isTrue,
      );
    });

    test('only an explicit false blocks', () {
      expect(
        SoundboardDestinationPolicy.resolve({
          'allow_external_packs': false,
        }).allowExternalPacks,
        isFalse,
      );
      expect(
        SoundboardDestinationPolicy.resolve({
          'allow_external_packs': true,
        }).allowExternalPacks,
        isTrue,
      );
    });

    test('a malformed or future policy falls back to allow, not to block', () {
      // Failing closed here would silently break a space that never set a
      // policy, just because a newer client wrote a field this build cannot
      // read.
      for (final content in <Map<String, dynamic>>[
        {},
        {'allow_external_packs': 'false'},
        {'allow_external_packs': 0},
        {'schema_version': 99, 'policy': 'deny-all'},
      ]) {
        expect(
          SoundboardDestinationPolicy.resolve(content).allowExternalPacks,
          isTrue,
          reason: 'content $content should fall back to allow',
        );
      }
    });

    test('round-trips through state content', () {
      final blocked = SoundboardDestinationPolicy.resolve(
        const SoundboardDestinationPolicy(
          allowExternalPacks: false,
        ).toStateContent(),
      );
      expect(blocked.allowExternalPacks, isFalse);
    });
  });

  group('evaluation', () {
    test('an unconfigured destination permits an external pack', () {
      expect(evaluate().allowed, isTrue);
    });

    test('a blocked destination refuses an external pack, with a reason', () {
      final result = evaluate(
        policy: const SoundboardDestinationPolicy(allowExternalPacks: false),
      );

      expect(result.isBlocked, isTrue);
      expect(result.reason, isNotNull);
      expect(result.reason, contains('other spaces'));
    });

    test('same-space playback is never subject to the policy', () {
      // Blocking external packs must not disable a space's own soundboard.
      final result = evaluate(
        sourceSpaceId: _destination,
        destinationSpaceId: _destination,
        policy: const SoundboardDestinationPolicy(allowExternalPacks: false),
      );

      expect(result.allowed, isTrue);
    });

    test('a call with no destination space refuses external packs', () {
      // With no destination there is no policy to honour; allowing here would
      // let a sender route around a block by choosing a context that has none.
      for (final destination in <String?>[null, '']) {
        final result = evaluate(destinationSpaceId: destination);
        expect(result.isBlocked, isTrue);
        expect(result.reason, contains('no space'));
      }
    });

    test('the same call decides both emission and reception', () {
      // Sender and receiver run this identical evaluation, so a receiver that
      // refreshed policy after the sender emitted still refuses.
      const blocked = SoundboardDestinationPolicy(allowExternalPacks: false);

      final senderView = evaluate();
      final receiverView = evaluate(policy: blocked);

      expect(senderView.allowed, isTrue);
      expect(receiverView.isBlocked, isTrue);
    });

    test('re-allowing restores playback without any other change', () {
      expect(
        evaluate(
          policy: const SoundboardDestinationPolicy(allowExternalPacks: false),
        ).isBlocked,
        isTrue,
      );
      expect(
        evaluate(
          policy: const SoundboardDestinationPolicy(allowExternalPacks: true),
        ).allowed,
        isTrue,
      );
    });
  });
}
