import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/client/permissions.dart';
import 'package:intergalactic/client/role.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/members/room_members_settings_page.dart';

void main() {
  testWidgets('shows and approves pending join requests', (tester) async {
    final request = _FakeMember(
      identifier: '@new-user:example.org',
      displayName: 'New User',
    );
    final room = _FakeJoinRequestRoom(
      client: _FakeClient(),
      members: [
        _FakeMember(identifier: '@admin:example.org', displayName: 'Admin'),
      ],
      joinRequests: [request],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RoomMembersSettingsPage(room: room)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Join requests'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);

    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    expect(room.approvedJoinRequests, ['@new-user:example.org']);
    expect(find.text('Join requests'), findsNothing);
  });

  testWidgets('renders pending join request actions at compact width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final room = _FakeJoinRequestRoom(
      client: _FakeClient(),
      members: [
        _FakeMember(identifier: '@admin:example.org', displayName: 'Admin'),
      ],
      joinRequests: [
        _FakeMember(
          identifier: '@new-user:example.org',
          displayName: 'New User',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RoomMembersSettingsPage(room: room)),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
  });
}

class _FakeJoinRequestRoom implements Room, RoomJoinRequestActions {
  _FakeJoinRequestRoom({
    required this.client,
    required List<Member> members,
    required List<Member> joinRequests,
  }) : _members = List<Member>.from(members),
       _joinRequests = List<Member>.from(joinRequests);

  final List<Member> _members;
  final List<Member> _joinRequests;
  final List<String> approvedJoinRequests = [];
  final List<String> declinedJoinRequests = [];

  @override
  final Client client;

  @override
  String get identifier => '!room:example.org';

  @override
  String get displayName => 'Example Room';

  @override
  Permissions get permissions => _FakePermissions();

  @override
  Stream<void> get onUpdate => const Stream.empty();

  @override
  bool get isMembersListComplete => true;

  @override
  List<Member> membersList() => List<Member>.from(_members);

  @override
  Future<List<Member>> fetchMembersList({bool cache = false}) async =>
      membersList();

  @override
  List<Member> joinRequestsList() => List<Member>.from(_joinRequests);

  @override
  Future<List<Member>> fetchJoinRequests({bool cache = false}) async =>
      joinRequestsList();

  @override
  Future<void> approveJoinRequest(String id) async {
    approvedJoinRequests.add(id);
    _joinRequests.removeWhere((member) => member.identifier == id);
  }

  @override
  Future<void> declineJoinRequest(String id) async {
    declinedJoinRequests.add(id);
    _joinRequests.removeWhere((member) => member.identifier == id);
  }

  @override
  List<Role> get availableRoles => const [_FakeRole('Member', Icons.person)];

  @override
  Role getMemberRole(String identifier) => availableRoles.single;

  @override
  Member getMemberOrFallback(String id) {
    return [..._members, ..._joinRequests].firstWhere(
      (member) => member.identifier == id,
      orElse: () => _FakeMember(identifier: id, displayName: id),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePermissions extends Permissions {
  @override
  bool get canInviteUser => true;

  @override
  bool get canKick => true;
}

class _FakeRole implements Role {
  const _FakeRole(this.name, this.icon);

  @override
  final String name;

  @override
  final IconData icon;
}

class _FakeMember implements Member {
  const _FakeMember({required this.identifier, required this.displayName});

  @override
  final String identifier;

  @override
  final String displayName;

  @override
  String get userName => displayName;

  @override
  String? get detail => null;

  @override
  String? get avatarId => null;

  @override
  ImageProvider? get avatar => null;

  @override
  Color get defaultColor => Colors.blue;
}

class _FakeClient implements Client {
  @override
  String get identifier => 'client-a';

  @override
  Profile? get self => null;

  @override
  T? getComponent<T extends Component>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
