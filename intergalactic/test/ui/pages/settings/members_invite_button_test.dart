import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/invitation/invitation_component.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/client/permissions.dart';
import 'package:intergalactic/client/role.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/pages/settings/categories/room/members/room_members_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Owner request, 2026-09-06: "on the members page for space and room settings
/// add an invite button."
///
/// One page serves both - the space Members tab builds this same widget over
/// the space's own room - so the button lands in both places at once, and the
/// copy deliberately names neither a room nor a space.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.layoutOverride.set('desktop');
  });

  Future<void> pump(WidgetTester tester, _FakeRoom room) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
        home: Scaffold(
          body: SingleChildScrollView(
            child: RoomMembersSettingsPage(room: room),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder inviteButton() =>
      find.widgetWithText(tiamat.Button, 'Invite').hitTestable();

  testWidgets('a member who may invite gets the button', (tester) async {
    await pump(tester, _FakeRoom());

    expect(find.text('Invite people'), findsOneWidget);
    expect(inviteButton(), findsOneWidget);
  });

  testWidgets('a member who may not invite does not', (tester) async {
    await pump(tester, _FakeRoom(canInvite: false));

    expect(
      find.text('Invite people'),
      findsNothing,
      reason:
          'the server would refuse the invite, so offering it here only '
          'produces a failure the user cannot act on',
    );
    // The heading and the button are separate widgets. Only the button can be
    // pressed, so it is the one that has to be gone.
    expect(inviteButton(), findsNothing);
  });

  testWidgets('an account with no invitation component does not', (
    tester,
  ) async {
    // Permission is not the only gate. Without the component the button has
    // nothing to open.
    await pump(tester, _FakeRoom(hasInvitationComponent: false));

    expect(find.text('Invite people'), findsNothing);
    expect(inviteButton(), findsNothing);
  });

  testWidgets('the button says where the invite goes afterwards', (
    tester,
  ) async {
    // The page already has a Pending invites section, and an invite lands
    // there rather than in the member list. Saying so up front is what stops
    // the invite reading as having failed.
    await pump(tester, _FakeRoom());

    expect(find.textContaining('Pending invites'), findsOneWidget);
  });
}

class _FakeRoom extends Room {
  _FakeRoom({bool canInvite = true, this.hasInvitationComponent = true})
    : _permissions = _FakePermissions(canInvite: canInvite) {
    client = _FakeClient(hasInvitationComponent: hasInvitationComponent);
  }

  final Permissions _permissions;
  final bool hasInvitationComponent;

  @override
  late final Client client;

  @override
  String get identifier => '!room:example.org';

  @override
  String get displayName => 'A Room';

  @override
  Permissions get permissions => _permissions;

  @override
  bool get isMembersListComplete => true;

  @override
  List<Member> membersList() => const [];

  @override
  List<Role> get availableRoles => const [];

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

  @override
  bool get canChangeRoles => false;

  @override
  bool get canKick => false;
}

class _FakeClient implements Client {
  _FakeClient({required this.hasInvitationComponent});

  final bool hasInvitationComponent;

  @override
  String get identifier => 'client';

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

class _FakeInvitationComponent implements InvitationComponent {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
