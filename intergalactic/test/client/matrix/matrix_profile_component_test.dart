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
}
