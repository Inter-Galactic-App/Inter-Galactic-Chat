import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/matrix_room_notification_snooze.dart';
import 'package:matrix/matrix.dart' as matrix;

void main() {
  group('MatrixRoomNotificationSnoozes', () {
    const roomId = '!room:example.org';
    const otherRoomId = '!other:example.org';
    final now = DateTime.utc(2026, 9, 3, 12);

    late _FakeClient client;
    late List<String> changedRooms;
    late MatrixRoomNotificationSnoozes snoozes;

    MatrixRoomNotificationSnoozes build() => MatrixRoomNotificationSnoozes(
      client: client,
      clientId: '@alice:example.org',
      onRoomChanged: changedRooms.add,
    );

    setUp(() {
      client = _FakeClient(roomIds: const [roomId, otherRoomId]);
      changedRooms = [];
      snoozes = build();
    });

    tearDown(() => snoozes.dispose());

    String ruleFor(String id) => snoozes.ruleId(id);

    /// The rule the manager is supposed to install, asserted in full.
    ///
    /// Recording only the rule id let the whole policy drift: an underride
    /// rule, a rule whose actions still notify, or a rule with no `room_id`
    /// condition all carry the same id and so passed every case in this file
    /// while silencing nothing, or silencing every room.
    void expectSnoozeRuleFor(String id, {required String reason}) {
      final rule = client.writtenRules[snoozes.ruleId(id)];
      expect(rule, isNotNull, reason: reason);
      expect(
        rule!.kind,
        matrix.PushRuleKind.override,
        reason: 'only an override rule outranks the room rule it suspends',
      );
      expect(
        rule.actions,
        isEmpty,
        reason: 'empty actions is what suppresses the notification',
      );
      expect(rule.conditions, hasLength(1));
      final condition = rule.conditions!.single;
      expect(condition.kind, matrix.PushRuleConditions.eventMatch.name);
      expect(condition.key, 'room_id');
      expect(
        condition.pattern,
        id,
        reason:
            'without this the override matches every room, so snoozing one '
            'room silences the account',
      );
    }

    test('set writes the push rule and the record together', () async {
      await snoozes.set(roomId, const Duration(hours: 1), source: 'test');

      expect(client.ruleIds, [ruleFor(roomId)]);
      expectSnoozeRuleFor(roomId, reason: 'set installed no rule at all');
      expect(
        client.roomAccountDataWrites[roomId]?[MatrixRoomNotificationSnoozes
            .accountDataType],
        isNotEmpty,
      );
      expect(snoozes.get(roomId, now: now), isNotNull);
      expect(changedRooms, [roomId]);
    });

    test('set rolls the push rule back when the record write fails', () async {
      client.failAccountDataWrites = true;

      await expectLater(
        snoozes.set(roomId, const Duration(hours: 1), source: 'test'),
        throwsA(isA<StateError>()),
      );

      expect(
        client.ruleIds,
        isEmpty,
        reason: 'the compensating delete must remove the rule it just wrote',
      );
      expect(snoozes.get(roomId, now: now), isNull);
    });

    test('clear removes the rule and empties the record', () async {
      await snoozes.set(roomId, const Duration(hours: 1), source: 'test');
      changedRooms.clear();

      await snoozes.clear(roomId);

      expect(client.ruleIds, isEmpty);
      expect(
        client.roomAccountDataWrites[roomId]?[MatrixRoomNotificationSnoozes
            .accountDataType],
        isEmpty,
      );
      expect(snoozes.get(roomId, now: now), isNull);
      expect(changedRooms, [roomId]);
    });

    test('reconcile expires an active record once it lapses', () async {
      await snoozes.set(
        roomId,
        const Duration(minutes: 30),
        source: 'test',
        now: now,
      );
      changedRooms.clear();

      await snoozes.reconcile(now: now.add(const Duration(minutes: 31)));

      expect(client.ruleIds, isEmpty);
      expect(
        client.roomAccountDataWrites[roomId]?[MatrixRoomNotificationSnoozes
            .accountDataType],
        isEmpty,
      );
      expect(changedRooms, [roomId]);
    });

    test('reconcile keeps a rule whose record is still active', () async {
      await snoozes.set(
        roomId,
        const Duration(hours: 2),
        source: 'test',
        now: now,
      );

      await snoozes.reconcile(now: now.add(const Duration(minutes: 5)));

      expect(client.ruleIds, [ruleFor(roomId)]);
      expect(client.deletedRuleIds, isEmpty);
    });

    test('reconcile restores a missing rule for an active record', () async {
      await snoozes.set(
        roomId,
        const Duration(hours: 2),
        source: 'test',
        now: now,
      );
      client.removeRuleSilently(ruleFor(roomId));
      client.writtenRules.clear();

      await snoozes.reconcile(now: now.add(const Duration(minutes: 5)));

      expect(client.ruleIds, [ruleFor(roomId)]);
      // `_ensurePushRule` builds the rule a second time, independently of
      // `set`. Restoring an id with a policy that no longer suppresses
      // anything is a rule that exists and does nothing.
      expectSnoozeRuleFor(
        roomId,
        reason: 'reconcile restored the id without re-installing the policy',
      );
    });

    group('orphan sweep', () {
      test('deletes a snooze rule that has no record at all', () async {
        // The unrecoverable state: set() wrote the rule, then both its
        // account-data write and its compensating delete failed.
        client.addRuleSilently(ruleFor(roomId));

        await snoozes.reconcile(now: now);

        expect(client.ruleIds, isEmpty);
        expect(client.deletedRuleIds, [ruleFor(roomId)]);
      });

      // This test used to assert the opposite - that an unresolved room's rule
      // is deleted. It cannot be: at runtime "the user left this room" and
      // "this room has not synced yet" are the same observation, an absent
      // room. reconcile() runs on every sync including early ones, so the old
      // behaviour deleted a snooze another device had set for a room this
      // client had yet to receive, leaving no record to restore it from.
      // Deferring costs at most a stale override rule with empty actions,
      // matching a room that sends this user nothing.
      test('defers an orphan whose room the client cannot resolve', () async {
        client.addRuleSilently(ruleFor('!left:example.org'));

        await snoozes.reconcile(now: now);

        expect(client.ruleIds, [ruleFor('!left:example.org')]);
        expect(client.deletedRuleIds, isEmpty);
      });

      test('sweeps an orphan while preserving an active rule', () async {
        await snoozes.set(
          roomId,
          const Duration(hours: 2),
          source: 'test',
          now: now,
        );
        client.addRuleSilently(ruleFor(otherRoomId));

        await snoozes.reconcile(now: now.add(const Duration(minutes: 5)));

        expect(client.ruleIds, [ruleFor(roomId)]);
        expect(client.deletedRuleIds, [ruleFor(otherRoomId)]);
      });

      test('leaves override rules owned by anything else alone', () async {
        client.addRuleSilently('.m.rule.master');
        client.addRuleSilently(roomId);

        await snoozes.reconcile(now: now);

        expect(client.deletedRuleIds, isEmpty);
        expect(client.ruleIds, ['.m.rule.master', roomId]);
      });
    });

    // _scheduleExpiry scanned only _client.rooms while get() and reconcile()
    // both answer from _pending as well, so a snooze set on a room this client
    // has not synced yet got no expiry timer at all: set() wrote the override
    // push rule, and nothing local was ever going to remove it after
    // snoozedUntil. The room stayed silent until some unrelated sync happened
    // to run reconcile.
    test('a pending snooze for an unsynced room is scheduled to expire', () {
      fakeAsync((async) {
        final unsyncedClient = _FakeClient(roomIds: const []);
        final pendingSnoozes = MatrixRoomNotificationSnoozes(
          client: unsyncedClient,
          clientId: '@alice:example.org',
          onRoomChanged: (_) {},
        );

        unawaited(
          pendingSnoozes.set(roomId, const Duration(hours: 1), source: 'test'),
        );
        async.flushMicrotasks();

        expect(
          unsyncedClient.ruleIds,
          [pendingSnoozes.ruleId(roomId)],
          reason:
              'arms the check: set() must have completed and written the '
              'override rule that now needs removing on expiry',
        );
        expect(
          pendingSnoozes.get(roomId),
          isNotNull,
          reason:
              'arms the check: the snooze is live for a room _client.rooms '
              'does not list, which is the whole case under test',
        );
        expect(
          async.pendingTimers,
          isNotEmpty,
          reason:
              'without an expiry timer the override push rule outlives '
              'snoozedUntil with nothing local left to remove it',
        );

        // `isNotEmpty` alone says a timer exists, not that it expires THIS
        // snooze: a timer armed for the wrong instant - a fixed poll interval,
        // or `nearest` taken from a room the client HAS synced - satisfies it
        // while the override rule still outlives `snoozedUntil`. The deadline
        // is the only part of the timer observable without a fakeable clock,
        // so it is asserted here and the callback's effect is asserted in the
        // test below.
        final expiry = async.pendingTimers.single;
        expect(expiry.isPeriodic, isFalse);
        expect(
          expiry.duration,
          lessThanOrEqualTo(const Duration(hours: 1)),
          reason:
              'the deadline is `snoozedUntil`, so it cannot be later than the '
              'hour that was asked for',
        );
        expect(
          expiry.duration,
          greaterThan(const Duration(minutes: 59)),
          reason:
              'only set() and _scheduleExpiry run between the two clock reads, '
              'so anything short of an hour means the deadline came from '
              'somewhere other than this snooze',
        );

        unawaited(pendingSnoozes.dispose());
        async.flushMicrotasks();
      });
    });

    // The other half of the same guard, and the half `pendingTimers` cannot
    // reach: what the callback DOES. A no-op callback passes every assertion
    // above.
    //
    // It cannot be asserted by elapsing fake time.
    // `MatrixRoomNotificationSnoozes` reads `DateTime.now()` directly, and
    // `fakeAsync` fakes `clock.now()`, not `DateTime.now()`. Elapsing an hour
    // inside the test above fires the timer, but the `reconcile()` it runs
    // still reads the real wall clock, still calls the snooze active, and so
    // deletes nothing - the assertions would be checking the fake clock's
    // opinion, not the code's.
    //
    // `set()` takes an injectable `now`, so a snooze that is already past
    // gives a real-clock `reconcile()` the same verdict a fake-clock one would
    // have given after an hour. `_scheduleExpiry` clamps the negative delay to
    // `Duration.zero`; it is the same timer running the same callback.
    test('the pending expiry timer removes the rule and the record', () async {
      final unsyncedClient = _FakeClient(roomIds: const []);
      final pendingSnoozes = MatrixRoomNotificationSnoozes(
        client: unsyncedClient,
        clientId: '@alice:example.org',
        onRoomChanged: (_) {},
      );
      addTearDown(pendingSnoozes.dispose);

      final setAt = DateTime.now().subtract(const Duration(hours: 2));
      await pendingSnoozes.set(
        roomId,
        const Duration(hours: 1),
        source: 'test',
        now: setAt,
      );

      expect(
        unsyncedClient.ruleIds,
        [pendingSnoozes.ruleId(roomId)],
        reason:
            'arms the check: with no rule written there is nothing for the '
            'expiry to remove and everything below passes vacuously',
      );
      expect(
        pendingSnoozes.get(roomId, now: setAt),
        isNotNull,
        reason: 'arms the check: the snooze was live at the moment it was set',
      );

      // Nothing here calls reconcile(). Whatever happens next is the timer.
      await pumpEventQueue();

      expect(
        unsyncedClient.deletedRuleIds,
        [pendingSnoozes.ruleId(roomId)],
        reason:
            'the room is not in _client.rooms, so the expired override rule is '
            'reachable only through the pending record the timer reconciles',
      );
      expect(unsyncedClient.ruleIds, isEmpty);
      expect(
        pendingSnoozes.get(roomId),
        isNull,
        reason:
            'a sweep that removes the rule but keeps the record re-installs it '
            'on the next reconcile',
      );
    });

    test('_runSerialized applies concurrent calls in order', () async {
      client.gateWrites = true;

      final first = snoozes.set(
        roomId,
        const Duration(hours: 1),
        source: 'first',
      );
      final second = snoozes.clear(roomId);

      // The gate is already holding a write by the time this runs, so no
      // `await` is needed first: a Dart async body runs synchronously to its
      // first await, so set() got as far as _maybeGate's `await gate.future`
      // before it returned above. Drop _runSerialized and clear() parks on the
      // same gate instead of queueing behind set(), so both writes resume from
      // one completion and the recorded order becomes setPushRule,
      // deletePushRule, accountData, accountData - which this fails on.
      client.releaseWrites();
      await Future.wait([first, second]);

      expect(
        client.callLog,
        [
          'setPushRule:${ruleFor(roomId)}',
          'accountData:$roomId',
          'deletePushRule:${ruleFor(roomId)}',
          'accountData:$roomId',
        ],
        reason: 'clear must not interleave with the set it followed',
      );
      expect(snoozes.get(roomId, now: now), isNull);
    });
  });
}

/// Only the members [MatrixRoomNotificationSnoozes] actually calls are
/// implemented; anything else reaching this fake is a real change in what the
/// manager depends on and should fail loudly rather than return a default.
class _FakeClient implements matrix.Client {
  _FakeClient({required List<String> roomIds}) {
    for (final id in roomIds) {
      _rooms.add(matrix.Room(id: id, client: this));
    }
  }

  final List<matrix.Room> _rooms = [];
  final Map<String, Map<String, Map<String, Object?>>> roomAccountDataWrites =
      {};
  final List<String> deletedRuleIds = [];
  final List<String> callLog = [];
  final List<String> _ruleIds = [];

  /// The full arguments of the last `setPushRule` for each rule id.
  ///
  /// Recording the id alone made `kind`, `actions` and `conditions`
  /// unobservable, so the tests could not tell a working snooze rule from an
  /// override that matches nothing - or from one that matches everything.
  final Map<String, _WrittenPushRule> writtenRules = {};

  bool failAccountDataWrites = false;
  bool gateWrites = false;
  Completer<void>? _gate;

  List<String> get ruleIds => List.unmodifiable(_ruleIds);

  /// Puts a rule on the server without a matching record, the way a failed
  /// `set()` rollback or an older build does.
  void addRuleSilently(String ruleId) => _ruleIds.add(ruleId);

  /// Drops a rule without touching the record, the way another device does.
  void removeRuleSilently(String ruleId) => _ruleIds.remove(ruleId);

  void releaseWrites() {
    gateWrites = false;
    _gate?.complete();
    _gate = null;
  }

  Future<void> _maybeGate() async {
    if (!gateWrites) {
      return;
    }
    final gate = _gate ??= Completer<void>();
    await gate.future;
  }

  @override
  String? get userID => '@alice:example.org';

  @override
  List<matrix.Room> get rooms => List.unmodifiable(_rooms);

  @override
  matrix.Room? getRoomById(String id) =>
      _rooms.where((room) => room.id == id).firstOrNull;

  @override
  matrix.PushRuleSet? get globalPushRules => matrix.PushRuleSet(
    override: [
      for (final ruleId in _ruleIds)
        matrix.PushRule(
          ruleId: ruleId,
          actions: const [],
          default$: false,
          enabled: true,
        ),
    ],
  );

  @override
  Future<void> setPushRule(
    matrix.PushRuleKind kind,
    String ruleId,
    List<Object?> actions, {
    String? before,
    String? after,
    List<matrix.PushCondition>? conditions,
    String? pattern,
  }) async {
    await _maybeGate();
    callLog.add('setPushRule:$ruleId');
    // Copied, not aliased. Handing the caller's own growable lists back would
    // let a later mutation rewrite what this test recorded as written.
    writtenRules[ruleId] = _WrittenPushRule(
      kind: kind,
      actions: List<Object?>.unmodifiable(actions),
      conditions: conditions == null
          ? null
          : List<matrix.PushCondition>.unmodifiable(conditions),
    );
    if (!_ruleIds.contains(ruleId)) {
      _ruleIds.add(ruleId);
    }
  }

  @override
  Future<void> deletePushRule(matrix.PushRuleKind kind, String ruleId) async {
    await _maybeGate();
    callLog.add('deletePushRule:$ruleId');
    if (!_ruleIds.remove(ruleId)) {
      throw matrix.MatrixException.fromJson(const {
        'errcode': 'M_NOT_FOUND',
        'error': 'Rule not found',
      });
    }
    deletedRuleIds.add(ruleId);
  }

  @override
  Future<void> setAccountDataPerRoom(
    String userId,
    String roomId,
    String type,
    Map<String, Object?> content,
  ) async {
    await _maybeGate();
    callLog.add('accountData:$roomId');
    if (failAccountDataWrites) {
      throw StateError('account data write failed');
    }
    roomAccountDataWrites.putIfAbsent(roomId, () => {})[type] = Map.of(content);
    final room = getRoomById(roomId);
    if (room != null) {
      room.roomAccountData[type] = matrix.BasicEvent(
        type: type,
        content: Map.of(content),
      );
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// One `setPushRule` call, kept whole.
class _WrittenPushRule {
  const _WrittenPushRule({
    required this.kind,
    required this.actions,
    required this.conditions,
  });

  final matrix.PushRuleKind kind;
  final List<Object?> actions;
  final List<matrix.PushCondition>? conditions;
}
