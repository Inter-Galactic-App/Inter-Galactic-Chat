import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/push_rule_state_cache.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';

/// Guards the CALL, not the parts either side of it.
///
/// `PushRuleStateCache` and `syncCarriesPushRules` are covered on their own,
/// but both can be correct while `onMatrixClientSync` simply never invokes the
/// refresh - and BUG-319 would be unfixed with every other test still green.
/// These cases drive a real `MatrixClient`'s sync handler, so deleting the
/// `_invalidatePushRuleCaches(update)` line turns them red.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('push-rule cache refresh is wired into the sync handler', () {
    late MatrixClient client;
    late _SpyRoom room;
    late _SpySpace space;

    matrix.SyncUpdate syncWith(List<String> accountDataTypes) =>
        matrix.SyncUpdate(
          nextBatch: 'batch',
          accountData: [
            for (final type in accountDataTypes)
              matrix.BasicEvent(type: type, content: const {}),
          ],
        );

    setUp(() async {
      // A real MatrixClient reaches preferences during construction.
      SharedPreferences.setMockInitialValues({});
      await globals.preferences.init();
      client = MatrixClient(
        identifier: 'push-rule-wiring',
        database: _FakeMatrixDatabase(),
      );
      room = _SpyRoom();
      space = _SpySpace();
      client.rooms.add(room);
      client.spaces.add(space);
    });

    test('a sync carrying m.push_rules refreshes rooms and spaces', () {
      client.onMatrixClientSync(syncWith(['m.push_rules']));

      expect(room.invalidations, 1);
      expect(space.invalidations, 1);
    });

    test('push rules alongside other account data still refresh', () {
      client.onMatrixClientSync(
        syncWith(['m.direct', 'm.push_rules', 'm.tag_order']),
      );

      expect(room.invalidations, 1);
      expect(space.invalidations, 1);
    });

    test('an ordinary sync refreshes nothing', () {
      client.onMatrixClientSync(syncWith(['m.direct']));

      expect(room.invalidations, 0);
      expect(space.invalidations, 0);
    });

    test('a sync with no account data at all refreshes nothing', () {
      client.onMatrixClientSync(matrix.SyncUpdate(nextBatch: 'batch'));

      expect(room.invalidations, 0);
      expect(space.invalidations, 0);
    });
  });
}

class _SpyRoom implements Room, PushRuleCacheHolder {
  int invalidations = 0;

  @override
  bool invalidatePushRuleCache() {
    invalidations++;
    return true;
  }

  @override
  String get identifier => '!spy-room:example.org';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _SpySpace implements Space, PushRuleCacheHolder {
  int invalidations = 0;

  @override
  bool invalidatePushRuleCache() {
    invalidations++;
    return true;
  }

  @override
  String get identifier => '!spy-space:example.org';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeMatrixDatabase implements matrix.DatabaseApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
