import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_member.dart';
import 'package:matrix/matrix.dart' as matrix;

void main() {
  group('MatrixMember', () {
    test('uses explicit avatar URL when room membership state has none', () {
      final fallbackAvatar = Uri.parse('mxc://example.org/profile-avatar');
      final member = MatrixMember(
        _FakeMatrixClient(),
        matrix.User(
          '@finn:example.org',
          membership: matrix.Membership.join.name,
          displayName: 'Finn',
          room: _FakeSdkRoom(),
        ),
        avatarUrl: fallbackAvatar,
      );

      expect(member.avatarId, fallbackAvatar.toString());
    });

    test('keeps room membership avatar when no fallback is supplied', () {
      final roomAvatar = Uri.parse('mxc://example.org/room-avatar');
      final member = MatrixMember(
        _FakeMatrixClient(),
        matrix.User(
          '@rey:example.org',
          membership: matrix.Membership.join.name,
          displayName: 'Rey',
          avatarUrl: roomAvatar.toString(),
          room: _FakeSdkRoom(),
        ),
      );

      expect(member.avatarId, roomAvatar.toString());
    });
  });
}

class _FakeMatrixClient implements MatrixClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSdkRoom implements matrix.Room {
  @override
  String get id => '!room:example.org';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
