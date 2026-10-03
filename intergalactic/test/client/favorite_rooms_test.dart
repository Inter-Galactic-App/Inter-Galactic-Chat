import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/favorite_rooms.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The seven cases named in
/// `docs/agent-control/review/favorite-room-sync-decision-2026-08-16.md`.
///
/// Favourites used to be a device-local `SharedPreferences` list. Moving them
/// to the `m.favourite` room tag makes them server state, which means three
/// new ways to be wrong that a local list could not be: a write can FAIL, the
/// server can already hold favourites THIS DEVICE has never seen, and the
/// device can hold leftovers belonging to a DIFFERENT ACCOUNT. Each of those
/// has a case here, because none of them is visible from the happy path.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    favoriteRoomStore.clearForTesting();
  });

  group('order values', () {
    test('are strictly inside the spec range', () {
      for (final order in evenlySpacedOrders(4)) {
        expect(order, greaterThan(0));
        expect(order, lessThan(1));
      }
    });

    test('ascend with position', () {
      final orders = evenlySpacedOrders(5);
      expect(orders, orderedEquals([...orders]..sort()));
      expect(orders.toSet(), hasLength(5));
    });

    test('an empty list produces no orders', () {
      expect(evenlySpacedOrders(0), isEmpty);
    });
  });

  group('serverFavoritesInOrder', () {
    test('sorts by the tag order, not by insertion', () {
      expect(serverFavoritesInOrder({'!c': 0.9, '!a': 0.1, '!b': 0.5}), [
        '!a',
        '!b',
        '!c',
      ]);
    });

    // The spec makes `order` optional. A tag without one has no defined
    // position, so it must not be able to displace a room that does have one.
    test('tags without an order come last, deterministically', () {
      expect(
        serverFavoritesInOrder({'!z': null, '!m': null, '!ordered': 0.5}),
        ['!ordered', '!m', '!z'],
      );
    });
  });

  group('mergeFavoritesForMigration', () {
    // Case 1: nothing on the server yet.
    test('with no server tags the local list is imported in its order', () {
      expect(
        mergeFavoritesForMigration(
          serverFavoriteRoomIds: const [],
          localFavoriteRoomIds: const ['!first', '!second', '!third'],
        ),
        ['!first', '!second', '!third'],
      );
    });

    // Case 2: the one that matters. A favourite set in Element must survive a
    // migration run on a device that has never heard of it.
    test('server membership survives and server order is not reversed', () {
      final merged = mergeFavoritesForMigration(
        serverFavoriteRoomIds: const ['!fromElement', '!alsoElement'],
        localFavoriteRoomIds: const ['!localOnly'],
      );

      expect(merged, ['!fromElement', '!alsoElement', '!localOnly']);
      expect(
        merged.indexOf('!fromElement'),
        lessThan(merged.indexOf('!alsoElement')),
        reason: 'the server pair kept its relative order',
      );
    });

    test('a room on both sides is not duplicated', () {
      expect(
        mergeFavoritesForMigration(
          serverFavoriteRoomIds: const ['!both'],
          localFavoriteRoomIds: const ['!both', '!localOnly'],
        ),
        ['!both', '!localOnly'],
      );
    });
  });

  group('migration', () {
    test('case 1: local membership and order become tags', () async {
      final harness = _Harness('@me:example.org');
      final first = harness.addRoom('!first:example.org');
      final second = harness.addRoom('!second:example.org');
      await globals.preferences.setRoomFavorite(second.favoriteStorageId, true);
      await globals.preferences.setRoomFavorite(first.favoriteStorageId, true);
      // Stored order is second-then-first; the tags must say the same.
      await globals.preferences.setFavoriteRoomOrder([
        second.favoriteStorageId,
        first.favoriteStorageId,
      ]);

      final result = await favoriteRoomStore.migrateClient(harness.client);

      expect(result.outcome, FavoriteMigrationOutcome.completed);
      expect(result.importedCount, 2);
      expect(harness.sdkRoom('!second:example.org').favoriteOrder, isNotNull);
      expect(
        harness.sdkRoom('!second:example.org').favoriteOrder!,
        lessThan(harness.sdkRoom('!first:example.org').favoriteOrder!),
      );
      expect(
        globals.preferences.isFavoriteRoomTagsMigrated('@me:example.org'),
        isTrue,
      );
    });

    test('case 2: a server favourite this device never saw is kept', () async {
      final harness = _Harness('@me:example.org');
      final fromElement = harness.addRoom('!element:example.org');
      final localOnly = harness.addRoom('!local:example.org');
      harness.sdkRoom('!element:example.org').setFavoriteTag(0.5);
      await globals.preferences.setRoomFavorite(
        localOnly.favoriteStorageId,
        true,
      );

      final result = await favoriteRoomStore.migrateClient(harness.client);

      expect(result.outcome, FavoriteMigrationOutcome.completed);
      expect(result.serverCount, 1);
      expect(result.importedCount, 1);
      expect(
        favoriteRoomStore.isFavorite(fromElement),
        isTrue,
        reason: 'the migration must never drop a favourite set elsewhere',
      );
      expect(
        harness.sdkRoom('!element:example.org').favoriteOrder!,
        lessThan(harness.sdkRoom('!local:example.org').favoriteOrder!),
        reason: 'the server room keeps its place ahead of the imported one',
      );
    });

    test(
      'migrated tags remain visible before the server echoes them',
      () async {
        final harness = _Harness('@me:example.org');
        final room = harness.addRoom('!pending:example.org');
        await globals.preferences.setRoomFavorite(room.favoriteStorageId, true);
        harness.sdkRoom(room.identifier).echoWrites = false;

        final result = await favoriteRoomStore.migrateClient(harness.client);

        expect(result.outcome, FavoriteMigrationOutcome.completed);
        expect(favoriteRoomStore.isFavorite(room), isTrue);
        expect(harness.sdkRoom(room.identifier).favoriteOrder, isNull);
      },
    );

    // Case 3. The stored list is device-wide, so account B's migration sees
    // account A's entries. Resolving an entry only against rooms THIS account
    // knows is what stops it writing a tag on B's behalf.
    test('case 3: another account\'s leftovers are not written', () async {
      // The SHARED room is the whole point. Both accounts are in
      // !shared:example.org, so account A's stored entry and account B's own
      // key differ only in the account half - which is exactly the part a
      // suffix or room-id match would throw away.
      final accountA = _Harness('@a:example.org');
      final sharedForA = accountA.addRoom('!shared:example.org');
      await globals.preferences.setRoomFavorite(
        sharedForA.favoriteStorageId,
        true,
      );

      final accountB = _Harness('@b:example.org');
      accountB.addRoom('!shared:example.org');
      accountB.addRoom('!bOnly:example.org');

      final result = await favoriteRoomStore.migrateClient(accountB.client);

      expect(result.outcome, FavoriteMigrationOutcome.completed);
      expect(
        result.importedCount,
        0,
        reason: "account A's favourite is not account B's to upload",
      );
      expect(accountB.sdkRoom('!shared:example.org').favoriteOrder, isNull);
      expect(accountB.sdkRoom('!bOnly:example.org').favoriteOrder, isNull);
      expect(accountA.sdkRoom('!shared:example.org').favoriteOrder, isNull);
    });

    // Case 4. A half-migrated account marked as done never runs again, and its
    // remaining favourites are lost the moment the local list is retired.
    test('case 4: a failed write leaves the marker unset', () async {
      final harness = _Harness('@me:example.org');
      final room = harness.addRoom('!room:example.org');
      await globals.preferences.setRoomFavorite(room.favoriteStorageId, true);
      harness.sdkRoom('!room:example.org').failWrites = true;

      final result = await favoriteRoomStore.migrateClient(harness.client);

      expect(result.outcome, FavoriteMigrationOutcome.failed);
      expect(
        globals.preferences.isFavoriteRoomTagsMigrated('@me:example.org'),
        isFalse,
      );
    });

    test('runs once: a second call reports it was already done', () async {
      final harness = _Harness('@me:example.org');
      harness.addRoom('!room:example.org');

      expect(
        (await favoriteRoomStore.migrateClient(harness.client)).outcome,
        FavoriteMigrationOutcome.completed,
      );
      expect(
        (await favoriteRoomStore.migrateClient(harness.client)).outcome,
        FavoriteMigrationOutcome.alreadyMigrated,
      );
    });

    test('a signed-out client is not ready and sets no marker', () async {
      final harness = _Harness('@me:example.org', signedIn: false);
      harness.addRoom('!room:example.org');

      final result = await favoriteRoomStore.migrateClient(harness.client);

      expect(result.outcome, FavoriteMigrationOutcome.notReady);
      expect(
        globals.preferences.isFavoriteRoomTagsMigrated('@me:example.org'),
        isFalse,
      );
    });
  });

  group('membership after migration', () {
    // Case 5. Nothing local changes here: only the room's own account data
    // does, which is what a remote m.tag arriving in a sync looks like. The
    // favourites surfaces re-read this on every build and resubscribe on the
    // room's onUpdate, so a remote change reaches them without a restart.
    test(
      'case 5: a remote tag change is visible with no local write',
      () async {
        final harness = _Harness('@me:example.org');
        final room = harness.addRoom('!room:example.org');
        await favoriteRoomStore.migrateClient(harness.client);

        expect(favoriteRoomStore.isFavorite(room), isFalse);

        harness.sdkRoom('!room:example.org').setFavoriteTag(0.5);

        expect(favoriteRoomStore.isFavorite(room), isTrue);
        expect(
          globals.preferences.getFavoriteRoomIds(),
          isEmpty,
          reason: 'membership came from the server, not from a local write',
        );
      },
    );

    test('the stored list no longer decides membership', () async {
      final harness = _Harness('@me:example.org');
      final room = harness.addRoom('!room:example.org');
      await favoriteRoomStore.migrateClient(harness.client);
      // A stale local entry, the shape left behind by the legacy list.
      await globals.preferences.setRoomFavorite(room.favoriteStorageId, true);

      expect(
        favoriteRoomStore.isFavorite(room),
        isFalse,
        reason: 'after migration the server tag is the only source of truth',
      );
    });

    test('a failed toggle does not create a local-only favourite', () async {
      final harness = _Harness('@me:example.org');
      final room = harness.addRoom('!room:example.org');
      await favoriteRoomStore.migrateClient(harness.client);
      harness.sdkRoom('!room:example.org').failWrites = true;

      final result = await favoriteRoomStore.setFavorite(room, true);

      expect(result, FavoriteWriteResult.failed);
      expect(favoriteRoomStore.isFavorite(room), isFalse);
      expect(globals.preferences.getFavoriteRoomIds(), isEmpty);
    });

    test(
      'a successful toggle shows immediately, before the next sync',
      () async {
        final harness = _Harness('@me:example.org');
        final room = harness.addRoom('!room:example.org');
        await favoriteRoomStore.migrateClient(harness.client);
        // The SDK performs the request but injects no synthetic m.tag event, so
        // without the pending state the star would not light until a sync.
        harness.sdkRoom('!room:example.org').echoWrites = false;

        expect(
          await favoriteRoomStore.setFavorite(room, true),
          FavoriteWriteResult.applied,
        );

        expect(favoriteRoomStore.isFavorite(room), isTrue);
      },
    );

    test('an un-migrated account still uses the local list', () async {
      final harness = _Harness('@me:example.org');
      final room = harness.addRoom('!room:example.org');

      expect(
        await favoriteRoomStore.setFavorite(room, true),
        FavoriteWriteResult.applied,
      );

      expect(favoriteRoomStore.isFavorite(room), isTrue);
      expect(globals.preferences.getFavoriteRoomIds(), isNotEmpty);
      expect(harness.sdkRoom('!room:example.org').favoriteOrder, isNull);
    });
  });

  group('reorder', () {
    // Case 6.
    test('case 6: writes valid orders and keeps every member', () async {
      final harness = _Harness('@me:example.org');
      final first = harness.addRoom('!first:example.org');
      final second = harness.addRoom('!second:example.org');
      harness.sdkRoom('!first:example.org').setFavoriteTag(0.3);
      harness.sdkRoom('!second:example.org').setFavoriteTag(0.6);
      await favoriteRoomStore.migrateClient(harness.client);

      final result = await favoriteRoomStore.setFavoriteOrder(
        orderedStorageIds: [second.favoriteStorageId, first.favoriteStorageId],
        knownRooms: harness.client.rooms,
      );

      expect(result, FavoriteWriteResult.applied);
      expect(favoriteRoomStore.isFavorite(first), isTrue);
      expect(favoriteRoomStore.isFavorite(second), isTrue);
      expect(
        favoriteRoomStore
            .sortFavorites([first, second])
            .map((room) => room.identifier),
        ['!second:example.org', '!first:example.org'],
      );
      for (final id in ['!first:example.org', '!second:example.org']) {
        expect(harness.sdkRoom(id).favoriteOrder, greaterThan(0.0));
        expect(harness.sdkRoom(id).favoriteOrder, lessThan(1.0));
      }
    });

    test('a failed reorder reports failure', () async {
      final harness = _Harness('@me:example.org');
      final first = harness.addRoom('!first:example.org');
      final second = harness.addRoom('!second:example.org');
      harness.sdkRoom('!first:example.org').setFavoriteTag(0.3);
      harness.sdkRoom('!second:example.org').setFavoriteTag(0.6);
      await favoriteRoomStore.migrateClient(harness.client);
      harness.sdkRoom('!second:example.org').failWrites = true;

      expect(
        await favoriteRoomStore.setFavoriteOrder(
          orderedStorageIds: [
            second.favoriteStorageId,
            first.favoriteStorageId,
          ],
          knownRooms: harness.client.rooms,
        ),
        FavoriteWriteResult.failed,
      );
    });

    // A request that names ids none of which resolve against knownRooms
    // wrote zero tags and still returned FavoriteWriteResult.applied, which
    // is indistinguishable from a working reorder - the same vacuous-pass
    // shape as dart_format_check reporting ok on an empty file list.
    test('a reorder that matches no known room reports failure, not a vacuous '
        'success', () async {
      final harness = _Harness('@me:example.org');
      harness.addRoom('!first:example.org');
      await favoriteRoomStore.migrateClient(harness.client);

      expect(
        await favoriteRoomStore.setFavoriteOrder(
          orderedStorageIds: ['!unknown:example.org'],
          knownRooms: harness.client.rooms,
        ),
        FavoriteWriteResult.failed,
      );
    });
  });

  group('sorting', () {
    // Case 7, the storage half: a favourite that arrived from another client
    // carries no local anything - no category, and possibly no `order`. It has
    // to keep a defined, stable place rather than disappearing or shuffling.
    test('case 7: a favourite with no order sorts last but stays', () async {
      final harness = _Harness('@me:example.org');
      final ordered = harness.addRoom('!ordered:example.org');
      final unordered = harness.addRoom('!unordered:example.org');
      harness.sdkRoom('!ordered:example.org').setFavoriteTag(0.5);
      harness.sdkRoom('!unordered:example.org').setFavoriteTag(null);
      await favoriteRoomStore.migrateClient(harness.client);
      // Migration assigns orders; drop one back to the shape another client
      // can produce.
      harness.sdkRoom('!unordered:example.org').setFavoriteTag(null);

      final sorted = favoriteRoomStore.sortFavorites([unordered, ordered]);

      expect(sorted.map((room) => room.identifier), [
        '!ordered:example.org',
        '!unordered:example.org',
      ]);
      expect(favoriteRoomStore.isFavorite(unordered), isTrue);
    });

    test('sorting is stable for two rooms with the same order', () async {
      final harness = _Harness('@me:example.org');
      final a = harness.addRoom('!a:example.org');
      final b = harness.addRoom('!b:example.org');
      harness.sdkRoom('!a:example.org').setFavoriteTag(0.5);
      harness.sdkRoom('!b:example.org').setFavoriteTag(0.5);
      await globals.preferences.markFavoriteRoomTagsMigrated('@me:example.org');

      expect(
        favoriteRoomStore.sortFavorites([b, a]).map((room) => room.identifier),
        ['!a:example.org', '!b:example.org'],
      );
    });
  });
}

/// One Matrix account with real [MatrixRoom] instances over fake SDK objects.
///
/// Real `MatrixRoom`s rather than a `Room` fake, because the coordinator
/// deliberately asks `room is MatrixRoom` to decide whether a room can carry
/// tags at all - a fake implementing `Room` would take the local branch and
/// every case here would pass without touching a tag.
class _Harness {
  _Harness(this.userId, {bool signedIn = true}) {
    sdkClient = _FakeSdkClient(userId);
    client = _FakeMatrixClient(
      sdk: sdkClient,
      self: signedIn ? _FakeProfile(userId) : null,
    );
  }

  final String userId;
  late final _FakeSdkClient sdkClient;
  late final _FakeMatrixClient client;
  final Map<String, _FakeSdkRoom> _sdkRooms = {};

  Room addRoom(String roomId) {
    final sdkRoom = _FakeSdkRoom(sdkClient, roomId);
    _sdkRooms[roomId] = sdkRoom;
    final room = MatrixRoom(client, sdkRoom, sdkClient);
    client.rooms.add(room);
    return room;
  }

  _FakeSdkRoom sdkRoom(String roomId) => _sdkRooms[roomId]!;
}

class _FakeProfile implements Profile {
  _FakeProfile(this.identifier);

  @override
  final String identifier;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeMatrixClient implements MatrixClient {
  _FakeMatrixClient({required this.sdk, required this.self});

  final _FakeSdkClient sdk;

  @override
  Profile? self;

  @override
  String get identifier => 'client-${sdk.userId}';

  @override
  final List<Room> rooms = [];

  @override
  bool get firstSyncComplete => true;

  @override
  matrix.Client getMatrixClient() => sdk;

  @override
  matrix.Client get matrixClient => sdk;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSdkClient implements matrix.Client {
  _FakeSdkClient(this.userId);

  final String userId;

  @override
  String? get userID => userId;

  @override
  final CachedStreamController<
    ({String roomId, matrix.StrippedStateEvent state})
  >
  onRoomState = CachedStreamController();

  @override
  final CachedStreamController<matrix.SyncUpdate> onSync =
      CachedStreamController();

  @override
  final CachedStreamController<matrix.Event> onTimelineEvent =
      CachedStreamController();

  @override
  final CachedStreamController<matrix.Event> onNotification =
      CachedStreamController();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A room whose `m.favourite` tag is real state that the fake keeps.
///
/// `tags`, `isFavourite`, `addTag` and `removeTag` are all overridden together
/// so a write is observable through exactly the reader production uses. A fake
/// that recorded calls without changing what a later read returns would let a
/// write-nothing regression pass.
class _FakeSdkRoom implements matrix.Room {
  _FakeSdkRoom(this._client, this.id);

  final matrix.Client _client;

  @override
  final String id;

  /// Set to make every tag request throw, the way an offline device does.
  bool failWrites = false;

  /// Set false to model the SDK's real behaviour of not injecting a synthetic
  /// `m.tag` event locally: the request succeeds, but a read still shows the
  /// old value until the next sync.
  bool echoWrites = true;

  matrix.Tag? _favoriteTag;

  double? get favoriteOrder => _favoriteTag?.order;

  void setFavoriteTag(double? order) => _favoriteTag = matrix.Tag(order: order);

  @override
  Map<String, matrix.Tag> get tags => {
    if (_favoriteTag case final tag?) matrix.TagType.favourite: tag,
  };

  @override
  bool get isFavourite => _favoriteTag != null;

  @override
  Future<void> addTag(String tag, {double? order}) async {
    if (failWrites) throw StateError('offline');
    if (tag != matrix.TagType.favourite) return;
    if (echoWrites) _favoriteTag = matrix.Tag(order: order);
  }

  @override
  Future<void> removeTag(String tag) async {
    if (failWrites) throw StateError('offline');
    if (tag != matrix.TagType.favourite) return;
    if (echoWrites) _favoriteTag = null;
  }

  @override
  matrix.Client get client => _client;

  @override
  String getLocalizedDisplayname([dynamic i18n, dynamic _]) => 'Room';

  @override
  matrix.Event? get lastEvent => null;

  @override
  Map<String, Map<String, matrix.StrippedStateEvent>> get states => const {};

  @override
  Map<String, matrix.BasicEvent> get roomAccountData => const {};

  @override
  bool get encrypted => false;

  @override
  matrix.Membership get membership => matrix.Membership.join;

  @override
  bool get isSpace => false;

  @override
  bool get isDirectChat => false;

  @override
  Future<void> postLoad() async {}

  @override
  Uri? get avatar => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
