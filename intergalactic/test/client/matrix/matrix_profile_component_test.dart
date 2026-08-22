import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/user_presence/user_presence_component.dart';
import 'package:intergalactic/client/matrix/components/profile/matrix_profile_component.dart';

void main() {
  group('matrixProfilePresenceWithFallback', () {
    test('fills blank live presence with profile status', () {
      final presence = matrixProfilePresenceWithFallback(
        UserPresence(UserPresenceStatus.online),
        {MatrixProfileComponent.statusKey: 'Back after dinner'},
      );

      expect(presence?.status, UserPresenceStatus.online);
      expect(presence?.message?.message, 'Back after dinner');
    });

    test('keeps live presence message over profile status', () {
      final presence = matrixProfilePresenceWithFallback(
        UserPresence(
          UserPresenceStatus.online,
          message: UserPresenceMessage(
            'Listening to Artist - Song',
            PresenceMessageType.userCustom,
          ),
        ),
        {MatrixProfileComponent.statusKey: 'Back after dinner'},
      );

      expect(presence?.message?.message, 'Listening to Artist - Song');
    });
  });

  group('MatrixProfile.validateBadgeSignature', () {
    test('returns false for an entry with no signatures', () async {
      expect(
        await MatrixProfile.validateBadgeSignature({
          'signed': {'sender': '@awards:data.commet.chat'},
        }),
        isFalse,
      );
    });

    test('returns false for an entry with no signed block', () async {
      expect(
        await MatrixProfile.validateBadgeSignature({
          'signatures': {
            '@awards:data.commet.chat': {'8d4f773c': 'sig'},
          },
        }),
        isFalse,
      );
    });

    test('returns false when signatures is not a map', () async {
      expect(
        await MatrixProfile.validateBadgeSignature({
          'signed': {'sender': '@awards:data.commet.chat'},
          'signatures': 'not-a-map',
        }),
        isFalse,
      );
    });

    test('returns false for an empty entry (no throw)', () async {
      expect(
        await MatrixProfile.validateBadgeSignature(<String, dynamic>{}),
        isFalse,
      );
    });

    test(
      'returns false for a well-formed entry from an unknown sender',
      () async {
        expect(
          await MatrixProfile.validateBadgeSignature(<String, dynamic>{
            'signed': <String, dynamic>{'sender': '@someone:example.org'},
            'signatures': <String, dynamic>{
              '@someone:example.org': <String, dynamic>{'abc': 'sig'},
            },
          }),
          isFalse,
        );
      },
    );
  });
}
