import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/voip/direct_call_session_owner.dart';

void main() {
  group('DirectCallSessionOwner', () {
    test('reuses the started wrapper when the call ends', () {
      final owner = DirectCallSessionOwner<_Session>();
      final started = owner.start('call-1', _Session.new);

      final ended = owner.end('call-1', _Session.new);

      expect(ended, same(started));
      expect(owner.end('call-1', _Session.new), isNot(same(started)));
    });

    test('releases every wrapper still owned at component disposal', () async {
      final owner = DirectCallSessionOwner<_Session>();
      final first = owner.start('call-1', _Session.new);
      final second = owner.start('call-2', _Session.new);

      await owner.dispose((session) async {
        session.releases++;
      });

      expect(first.releases, 1);
      expect(second.releases, 1);
      expect(owner.end('call-1', _Session.new), isNot(same(first)));
    });
  });
}

class _Session {
  int releases = 0;
}
