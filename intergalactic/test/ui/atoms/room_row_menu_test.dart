import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/invitation/invitation_component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/client/permissions.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/atoms/adaptive_context_menu.dart';
import 'package:intergalactic/ui/atoms/room_text_button.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

/// Owner request, 2026-09-06: the room right-click menu should offer mute and
/// invite. Both already existed elsewhere - mute inside the room's notification
/// settings, invite in the room's quick-access menu - so the gap was reach, not
/// capability.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.layoutOverride.set('desktop');
  });

  Future<List<String>> menuItems(WidgetTester tester, _FakeRoom room) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
        home: Scaffold(body: SizedBox(width: 320, child: RoomTextButton(room))),
      ),
    );
    await tester.pump();

    // Read the menu's ITEMS rather than opening it: the desktop menu only
    // builds its entries once the pointer opens it, and what is under test is
    // which actions the row offers, not the popup's own machinery.
    return tester
        .widget<AdaptiveContextMenu>(find.byType(AdaptiveContextMenu))
        .items
        .map((item) => item.text)
        .toList();
  }

  testWidgets('an unmuted room offers Mute', (tester) async {
    final items = await menuItems(tester, _FakeRoom());

    expect(items, contains('Mute Room'));
    expect(items, isNot(contains('Unmute Room')));
  });

  testWidgets('a muted room offers Unmute', (tester) async {
    final items = await menuItems(
      tester,
      _FakeRoom(pushRule: PushRule.dontNotify),
    );

    expect(items, contains('Unmute Room'));
    expect(items, isNot(contains('Mute Room')));
  });

  testWidgets('a mentions-only room reads as unmuted', (tester) async {
    // Three push-rule states, two menu labels. Mentions-only is not silence,
    // so offering "Unmute" there would claim the room is quiet when it is not.
    final items = await menuItems(
      tester,
      _FakeRoom(pushRule: PushRule.mentionsOnly),
    );

    expect(items, contains('Mute Room'));
    expect(items, isNot(contains('Unmute Room')));
  });

  testWidgets('choosing Mute sets the room to silent', (tester) async {
    final room = _FakeRoom();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
        home: Scaffold(body: SizedBox(width: 320, child: RoomTextButton(room))),
      ),
    );
    await tester.pump();

    final menu = tester.widget<AdaptiveContextMenu>(
      find.byType(AdaptiveContextMenu),
    );
    menu.items.firstWhere((item) => item.text == 'Mute Room').onPressed?.call();
    await tester.pump();

    expect(room.pushRule, PushRule.dontNotify);
  });

  testWidgets('a room the user may invite to offers Invite', (tester) async {
    final items = await menuItems(tester, _FakeRoom(canInvite: true));

    expect(items, contains('Invite'));
  });

  testWidgets('a room the user may not invite to does not', (tester) async {
    final items = await menuItems(tester, _FakeRoom(canInvite: false));

    expect(
      items,
      isNot(contains('Invite')),
      reason:
          'offering an action the server will refuse is worse than not '
          'offering it',
    );
  });

  testWidgets('an account with no invitation component does not', (
    tester,
  ) async {
    // Permission is not the only gate: without the component there is nothing
    // to open, and the entry would dead-end.
    final items = await menuItems(
      tester,
      _FakeRoom(canInvite: true, hasInvitationComponent: false),
    );

    expect(items, isNot(contains('Invite')));
  });

  testWidgets('the existing entries are still there', (tester) async {
    final items = await menuItems(tester, _FakeRoom());

    expect(items, contains('Mark as Read'));
    expect(items, contains('Add to Favorites'));
  });
}

class _FakeRoom extends Room {
  _FakeRoom({
    PushRule pushRule = PushRule.notify,
    bool canInvite = true,
    this.hasInvitationComponent = true,
  }) : _pushRule = pushRule,
       _permissions = _FakePermissions(canInvite: canInvite) {
    client = _FakeClient(hasInvitationComponent: hasInvitationComponent);
  }

  PushRule _pushRule;
  final Permissions _permissions;
  final bool hasInvitationComponent;

  @override
  late final Client client;

  @override
  String get identifier => '!room:example.org';

  @override
  String get localId => 'client:!room:example.org';

  @override
  String get displayName => 'A Room';

  @override
  ImageProvider? get avatar => null;

  @override
  Color get defaultColor => Colors.blue;

  @override
  int get notificationCount => 0;

  @override
  int get highlightedNotificationCount => 0;

  @override
  bool get isSpecialRoomType => false;

  @override
  Permissions get permissions => _permissions;

  @override
  PushRule get pushRule => _pushRule;

  @override
  Future<void> setPushRule(PushRule rule) async {
    _pushRule = rule;
  }

  @override
  Stream<void> get onUpdate => const Stream<void>.empty();

  @override
  T? getComponent<T extends RoomComponent>() => null;

  @override
  Iterable<String> get memberIds => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePermissions extends Permissions {
  _FakePermissions({required this.canInvite});

  final bool canInvite;

  @override
  bool get canInviteUser => canInvite;
}

class _FakeClient implements Client {
  _FakeClient({required this.hasInvitationComponent});

  final bool hasInvitationComponent;

  @override
  String get identifier => 'client';

  @override
  Profile? get self => const _FakeProfile();

  @override
  T? getComponent<T extends Component>() {
    if (T == InvitationComponent && hasInvitationComponent) {
      return _FakeInvitationComponent() as T;
    }

    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfile implements Profile {
  const _FakeProfile();

  @override
  String get identifier => '@self:example.org';

  @override
  String get displayName => 'Self';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInvitationComponent implements InvitationComponent {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
