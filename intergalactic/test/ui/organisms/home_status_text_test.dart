import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/user_presence/user_presence_component.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_status_strip.dart';

void main() {
  test('profile status fallback remains visible when live presence is blank',
      () {
    final profile = _StatusProfile('Listening to Artist - Yesterday');

    expect(homeStatusText(null, profile), 'Listening to Artist - Yesterday');
    expect(
      homeStatusText(UserPresence(UserPresenceStatus.online), profile),
      'Listening to Artist - Yesterday',
    );
    expect(
      homeStatusText(
        UserPresence(
          UserPresenceStatus.online,
          message: UserPresenceMessage(
            'Listening to Artist - Current Song',
            PresenceMessageType.userCustom,
          ),
        ),
        profile,
      ),
      'Listening to Artist - Current Song',
    );
  });
}

class _StatusProfile implements Profile, ProfileWithPresence {
  _StatusProfile(String status)
      : precence = UserPresence(
          UserPresenceStatus.online,
          message: UserPresenceMessage(
            status,
            PresenceMessageType.userCustom,
          ),
        );

  @override
  UserPresence? precence;

  @override
  ImageProvider<Object>? get avatar => null;

  @override
  ImageProvider<Object>? get banner => null;

  @override
  Color get defaultColor => Colors.blue;

  @override
  String get detail => '';

  @override
  String get displayName => 'Status Profile';

  @override
  String get identifier => '@status:example.test';

  @override
  String get source => identifier;

  @override
  String get userName => 'status';
}
