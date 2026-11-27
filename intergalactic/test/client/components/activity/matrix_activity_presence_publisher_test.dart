import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/activity/activity_settings.dart';
import 'package:intergalactic/client/components/activity/game_activity_overlay.dart';
import 'package:intergalactic/client/components/activity/publishers/matrix_activity_presence_publisher.dart';
import 'package:intergalactic/client/components/user_presence/user_presence_component.dart';
import 'package:intergalactic/client/matrix/components/user_presence/matrix_user_presence.dart';
import 'package:matrix/matrix.dart' show MatrixException, PresenceType;

void main() {
  group('MatrixActivityPresencePublisher', () {
    test('publishes formatted activity to Matrix presence', () async {
      final presence = _FakePresenceComponent();
      final ownershipStore = _FakeOwnershipStore();
      final publisher = MatrixActivityPresencePublisher(
        targetProvider: () => [
          ActivityPresenceTarget(
            id: 'matrix',
            presence: presence,
            selfUserId: '@me:example.test',
          ),
        ],
        ownershipStore: ownershipStore,
      );

      await publisher.publish(
        _music(),
        const ActivitySettings(
          publishBasicStatus: true,
          showSpotify: true,
        ),
      );

      expect(presence.calls.single.message, 'Listening to Artist - Song');
      expect(presence.calls.single.status, UserPresenceStatus.online);
      expect(
        await ownershipStore.readSummary('matrix'),
        'Listening to Artist - Song',
      );
    });

    test('publishes marked game activity to Matrix presence', () async {
      final presence = _FakePresenceComponent();
      final ownershipStore = _FakeOwnershipStore();
      final publisher = MatrixActivityPresencePublisher(
        targetProvider: () => [
          ActivityPresenceTarget(
            id: 'matrix',
            presence: presence,
            selfUserId: '@me:example.test',
          ),
        ],
        ownershipStore: ownershipStore,
      );
      final expectedSummary = formatGameActivityPresenceSummary('Portal')!;

      await publisher.publish(
        _game(),
        const ActivitySettings(
          publishBasicStatus: true,
          showGameActivity: true,
        ),
      );

      expect(presence.calls.single.message, expectedSummary);
      expect(presence.calls.single.status, UserPresenceStatus.online);
      expect(await ownershipStore.readSummary('matrix'), expectedSummary);
    });

    test('does not republish unchanged summaries', () async {
      final presence = _FakePresenceComponent();
      final publisher = MatrixActivityPresencePublisher(
        targetProvider: () => [
          ActivityPresenceTarget(id: 'matrix', presence: presence),
        ],
        ownershipStore: _FakeOwnershipStore(),
      );

      await publisher.publish(
        _music(),
        const ActivitySettings(
          publishBasicStatus: true,
          showSpotify: true,
        ),
      );
      await publisher.publish(
        _music(),
        const ActivitySettings(
          publishBasicStatus: true,
          showSpotify: true,
        ),
      );

      expect(presence.calls, hasLength(1));
    });

    test('clears owned presence when publishing is disabled', () async {
      final presence = _FakePresenceComponent();
      final publisher = MatrixActivityPresencePublisher(
        targetProvider: () => [
          ActivityPresenceTarget(id: 'matrix', presence: presence),
        ],
        ownershipStore: _FakeOwnershipStore(),
      );

      await publisher.publish(
        _music(),
        const ActivitySettings(
          publishBasicStatus: true,
          showSpotify: true,
        ),
      );
      await publisher.publish(null, const ActivitySettings());

      expect(presence.calls.last.clearMessage, isTrue);
    });

    test('retries failed Matrix presence clears', () async {
      final presence = _FakePresenceComponent(clearFailuresRemaining: 1);
      final publisher = MatrixActivityPresencePublisher(
        targetProvider: () => [
          ActivityPresenceTarget(id: 'matrix', presence: presence),
        ],
        ownershipStore: _FakeOwnershipStore(),
        retryDelays: const [Duration(milliseconds: 1)],
      );

      await publisher.publish(
        _music(),
        const ActivitySettings(
          publishBasicStatus: true,
          showSpotify: true,
        ),
      );
      await publisher.publish(null, const ActivitySettings());

      expect(presence.calls.where((call) => call.clearMessage), isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(presence.calls.where((call) => call.clearMessage), hasLength(1));
    });

    test('honors Matrix retry-after while coalescing newer activity', () async {
      final presence = _FakePresenceComponent(
        publishFailuresRemaining: 1,
        publishErrorFactory: () => MatrixException.fromJson({
          'errcode': 'M_LIMIT_EXCEEDED',
          'error': 'Too many requests',
          'retry_after_ms': 40,
        }),
      );
      final publisher = MatrixActivityPresencePublisher(
        targetProvider: () => [
          ActivityPresenceTarget(
            id: 'matrix',
            presence: presence,
            selfUserId: '@me:example.test',
          ),
        ],
        ownershipStore: _FakeOwnershipStore(),
        retryDelays: const [Duration(milliseconds: 1)],
        serverRetryPadding: Duration.zero,
      );

      await publisher.publish(
        _music(title: 'Old Song'),
        const ActivitySettings(
          publishBasicStatus: true,
          showSpotify: true,
        ),
      );
      await publisher.publish(
        _music(title: 'New Song'),
        const ActivitySettings(
          publishBasicStatus: true,
          showSpotify: true,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 15));

      expect(presence.calls, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(presence.calls.single.message, 'Listening to Artist - New Song');
    });

    test('honors shared presence backoff while coalescing newer activity',
        () async {
      final presence = _FakePresenceComponent(
        publishFailuresRemaining: 1,
        publishErrorFactory: () => const UserPresenceRateLimitException(
          retryAfter: Duration(milliseconds: 40),
        ),
      );
      final publisher = MatrixActivityPresencePublisher(
        targetProvider: () => [
          ActivityPresenceTarget(
            id: 'matrix',
            presence: presence,
            selfUserId: '@me:example.test',
          ),
        ],
        ownershipStore: _FakeOwnershipStore(),
        retryDelays: const [Duration(milliseconds: 1)],
        serverRetryPadding: Duration.zero,
      );

      await publisher.publish(
        _music(title: 'Old Song'),
        const ActivitySettings(
          publishBasicStatus: true,
          showSpotify: true,
        ),
      );
      await publisher.publish(
        _music(title: 'New Song'),
        const ActivitySettings(
          publishBasicStatus: true,
          showSpotify: true,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 15));

      expect(presence.calls, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 80));

      expect(presence.calls.single.message, 'Listening to Artist - New Song');
    });

    test('retries publishing when Matrix targets appear later', () async {
      final presence = _FakePresenceComponent();
      var includeTarget = false;
      final publisher = MatrixActivityPresencePublisher(
        targetProvider: () => includeTarget
            ? [
                ActivityPresenceTarget(
                  id: 'matrix',
                  presence: presence,
                  selfUserId: '@me:example.test',
                ),
              ]
            : const [],
        ownershipStore: _FakeOwnershipStore(),
        retryDelays: const [Duration(milliseconds: 1)],
      );

      await publisher.publish(
        _music(),
        const ActivitySettings(
          publishBasicStatus: true,
          showSpotify: true,
        ),
      );

      expect(presence.calls, isEmpty);

      includeTarget = true;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(presence.calls.single.message, 'Listening to Artist - Song');
    });

    test('drops startup activity retry after an empty refresh before targets',
        () async {
      final presence = _FakePresenceComponent();
      var includeTarget = false;
      final publisher = MatrixActivityPresencePublisher(
        targetProvider: () => includeTarget
            ? [
                ActivityPresenceTarget(
                  id: 'matrix',
                  presence: presence,
                  selfUserId: '@me:example.test',
                ),
              ]
            : const [],
        ownershipStore: _FakeOwnershipStore(),
        retryDelays: const [Duration(milliseconds: 20)],
      );
      const settings = ActivitySettings(
        publishBasicStatus: true,
        showSpotify: true,
      );

      await publisher.publish(_music(), settings);
      await publisher.publish(null, settings);

      expect(presence.calls, isEmpty);

      includeTarget = true;
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(presence.calls, isEmpty);
    });

    test('drops startup activity retry when sharing is disabled before targets',
        () async {
      final presence = _FakePresenceComponent();
      var includeTarget = false;
      final publisher = MatrixActivityPresencePublisher(
        targetProvider: () => includeTarget
            ? [
                ActivityPresenceTarget(
                  id: 'matrix',
                  presence: presence,
                  selfUserId: '@me:example.test',
                ),
              ]
            : const [],
        ownershipStore: _FakeOwnershipStore(),
        retryDelays: const [Duration(milliseconds: 20)],
      );

      await publisher.publish(
        _music(),
        const ActivitySettings(
          publishBasicStatus: true,
          showSpotify: true,
        ),
      );
      await publisher.publish(null, const ActivitySettings());

      includeTarget = true;
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(presence.calls, isEmpty);
    });

    test('skips publishing when presence read fails', () async {
      final presence = _FakePresenceComponent(
        status: UserPresenceStatus.offline,
        readFailuresRemaining: 1,
      );
      final publisher = MatrixActivityPresencePublisher(
        targetProvider: () => [
          ActivityPresenceTarget(
            id: 'matrix',
            presence: presence,
            selfUserId: '@me:example.test',
          ),
        ],
        ownershipStore: _FakeOwnershipStore(),
        retryDelays: const [],
      );

      await publisher.publish(
        _music(),
        const ActivitySettings(
          publishBasicStatus: true,
          showSpotify: true,
        ),
      );

      expect(presence.calls, isEmpty);
    });

    test('publishes active activity online when current presence is offline',
        () async {
      final presence = _FakePresenceComponent(
        status: UserPresenceStatus.offline,
      );
      final publisher = MatrixActivityPresencePublisher(
        targetProvider: () => [
          ActivityPresenceTarget(
            id: 'matrix',
            presence: presence,
            selfUserId: '@me:example.test',
          ),
        ],
        ownershipStore: _FakeOwnershipStore(),
      );

      await publisher.publish(
        _music(),
        const ActivitySettings(
          publishBasicStatus: true,
          showSpotify: true,
        ),
      );

      expect(presence.calls.single.status, UserPresenceStatus.online);
    });

    test('preserves the current away status while publishing activity',
        () async {
      final presence = _FakePresenceComponent(
        status: UserPresenceStatus.unavailable,
      );
      final publisher = MatrixActivityPresencePublisher(
        targetProvider: () => [
          ActivityPresenceTarget(
            id: 'matrix',
            presence: presence,
            selfUserId: '@me:example.test',
          ),
        ],
        ownershipStore: _FakeOwnershipStore(),
      );

      await publisher.publish(
        _music(),
        const ActivitySettings(
          publishBasicStatus: true,
          showSpotify: true,
        ),
      );

      expect(presence.calls.single.status, UserPresenceStatus.unavailable);
    });

    test('clears the last owned target when target provider goes empty',
        () async {
      final presence = _FakePresenceComponent();
      var includeTarget = true;
      final publisher = MatrixActivityPresencePublisher(
        targetProvider: () => includeTarget
            ? [
                ActivityPresenceTarget(
                  id: 'matrix',
                  presence: presence,
                  selfUserId: '@me:example.test',
                ),
              ]
            : const [],
        ownershipStore: _FakeOwnershipStore(),
      );

      await publisher.publish(
        _music(),
        const ActivitySettings(
          publishBasicStatus: true,
          showSpotify: true,
        ),
      );
      includeTarget = false;
      await publisher.publish(null, const ActivitySettings());

      expect(presence.calls.last.clearMessage, isTrue);
    });

    test('clears stale app-owned status without in-memory ownership', () async {
      final portalSummary = formatGameActivityPresenceSummary('Portal')!;
      final presence = _FakePresenceComponent(message: portalSummary);
      final ownershipStore = _FakeOwnershipStore(
        {'matrix': portalSummary},
      );
      final publisher = MatrixActivityPresencePublisher(
        targetProvider: () => [
          ActivityPresenceTarget(
            id: 'matrix',
            presence: presence,
            selfUserId: '@me:example.test',
          ),
        ],
        ownershipStore: ownershipStore,
      );

      await publisher.publish(null, const ActivitySettings());

      expect(presence.calls.single.clearMessage, isTrue);
      expect(presence.message, isNull);
      expect(await ownershipStore.readSummary('matrix'), isNull);
    });

    test('keeps stale app-owned status when presence read fails', () async {
      final presence = _FakePresenceComponent(
        message: 'Listening to Artist - Yesterday',
        readFailuresRemaining: 1,
      );
      final ownershipStore = _FakeOwnershipStore(
        {'matrix': 'Listening to Artist - Yesterday'},
      );
      final publisher = MatrixActivityPresencePublisher(
        targetProvider: () => [
          ActivityPresenceTarget(
            id: 'matrix',
            presence: presence,
            selfUserId: '@me:example.test',
          ),
        ],
        ownershipStore: ownershipStore,
        retryDelays: const [],
      );

      await publisher.publish(null, const ActivitySettings());

      expect(presence.calls, isEmpty);
      expect(presence.message, 'Listening to Artist - Yesterday');
      expect(
        await ownershipStore.readSummary('matrix'),
        'Listening to Artist - Yesterday',
      );
    });

    test('retries clearing persisted status when targets appear later',
        () async {
      final yesterdaySummary = formatGameActivityPresenceSummary('Yesterday')!;
      final presence = _FakePresenceComponent(message: yesterdaySummary);
      final ownershipStore = _FakeOwnershipStore(
        {'matrix': yesterdaySummary},
      );
      var includeTarget = false;
      final publisher = MatrixActivityPresencePublisher(
        targetProvider: () => includeTarget
            ? [
                ActivityPresenceTarget(
                  id: 'matrix',
                  presence: presence,
                  selfUserId: '@me:example.test',
                ),
              ]
            : const [],
        ownershipStore: ownershipStore,
        retryDelays: const [Duration(milliseconds: 1)],
      );

      await publisher.publish(null, const ActivitySettings());

      expect(presence.calls, isEmpty);

      includeTarget = true;
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(presence.calls.single.clearMessage, isTrue);
      expect(presence.message, isNull);
      expect(await ownershipStore.readSummary('matrix'), isNull);
    });

    test('does not clear custom status without in-memory ownership', () async {
      final presence = _FakePresenceComponent(message: 'Back after dinner');
      final publisher = MatrixActivityPresencePublisher(
        targetProvider: () => [
          ActivityPresenceTarget(
            id: 'matrix',
            presence: presence,
            selfUserId: '@me:example.test',
          ),
        ],
        ownershipStore: _FakeOwnershipStore(),
      );

      await publisher.publish(null, const ActivitySettings());

      expect(presence.calls, isEmpty);
      expect(presence.message, 'Back after dinner');
    });

    test('does not clear custom status shaped like an activity summary',
        () async {
      final presence = _FakePresenceComponent(message: 'Playing guitar');
      final publisher = MatrixActivityPresencePublisher(
        targetProvider: () => [
          ActivityPresenceTarget(
            id: 'matrix',
            presence: presence,
            selfUserId: '@me:example.test',
          ),
        ],
        ownershipStore: _FakeOwnershipStore(),
      );

      await publisher.publish(null, const ActivitySettings());

      expect(presence.calls, isEmpty);
      expect(presence.message, 'Playing guitar');
    });

    test('drops stale ownership marker when the current status changed',
        () async {
      final portalSummary = formatGameActivityPresenceSummary('Portal')!;
      final presence = _FakePresenceComponent(message: 'Playing guitar');
      final ownershipStore = _FakeOwnershipStore(
        {'matrix': portalSummary},
      );
      final publisher = MatrixActivityPresencePublisher(
        targetProvider: () => [
          ActivityPresenceTarget(
            id: 'matrix',
            presence: presence,
            selfUserId: '@me:example.test',
          ),
        ],
        ownershipStore: ownershipStore,
      );

      await publisher.publish(null, const ActivitySettings());

      expect(presence.calls, isEmpty);
      expect(presence.message, 'Playing guitar');
      expect(await ownershipStore.readSummary('matrix'), isNull);
    });

    test('presence clear sends an explicit empty message', () {
      expect(
        matrixPresenceStatusMessageForUpdate(
          'Playing Half-Life',
          clearMessage: true,
        ),
        '',
      );
      expect(
        matrixPresenceStatusMessageForUpdate(
          'Existing status',
          message: 'Playing Portal',
        ),
        'Playing Portal',
      );
      expect(
        matrixPresenceStatusMessageForUpdate('Existing status'),
        'Existing status',
      );
    });

    test('presence updates prefer authenticated Matrix user id', () {
      expect(
        matrixPresenceUserIdForUpdate(
          matrixUserId: '@session:example.test',
          profileUserId: '@profile:example.test',
        ),
        '@session:example.test',
      );
      expect(
        matrixPresenceUserIdForUpdate(
          matrixUserId: null,
          profileUserId: '@profile:example.test',
        ),
        '@profile:example.test',
      );
      expect(
        matrixPresenceUserIdForUpdate(
          matrixUserId: '',
          profileUserId: '',
        ),
        isNull,
      );
    });

    test('presence update matching detects no-op writes', () {
      expect(
        matrixPresenceUpdateMatchesCurrent(
          currentPresence: PresenceType.online,
          currentStatusMessage: 'Listening to Artist - Song',
          nextPresence: PresenceType.online,
          nextStatusMessage: 'Listening to Artist - Song',
        ),
        isTrue,
      );
      expect(
        matrixPresenceUpdateMatchesCurrent(
          currentPresence: PresenceType.online,
          currentStatusMessage: 'Listening to Artist - Song',
          nextPresence: PresenceType.unavailable,
          nextStatusMessage: 'Listening to Artist - Song',
        ),
        isFalse,
      );
      expect(
        matrixPresenceUpdateMatchesCurrent(
          currentPresence: PresenceType.online,
          currentStatusMessage: null,
          nextPresence: PresenceType.online,
          nextStatusMessage: '',
        ),
        isTrue,
      );
    });

    test('presence cache helper normalizes explicit clears', () {
      expect(matrixPresenceStatusMessageForCache(null), isNull);
      expect(matrixPresenceStatusMessageForCache(''), isNull);
      expect(matrixPresenceStatusMessageForCache('   '), isNull);
      expect(
        matrixPresenceStatusMessageForCache('Listening to Artist - Song'),
        'Listening to Artist - Song',
      );
    });

    test('blank cached presence refreshes only after throttle window', () {
      final now = DateTime(2026, 6, 4, 23);

      expect(
        matrixPresenceShouldRefreshCachedPresence(
          statusMsg: null,
          lastRefresh: null,
          now: now,
        ),
        isTrue,
      );
      expect(
        matrixPresenceShouldRefreshCachedPresence(
          statusMsg: '',
          lastRefresh: now.subtract(const Duration(seconds: 10)),
          now: now,
        ),
        isFalse,
      );
      expect(
        matrixPresenceShouldRefreshCachedPresence(
          statusMsg: '',
          lastRefresh: now.subtract(matrixPresenceServerRefreshInterval),
          now: now,
        ),
        isTrue,
      );
      expect(
        matrixPresenceShouldRefreshCachedPresence(
          statusMsg: 'Back after dinner',
          lastRefresh: null,
          now: now,
        ),
        isFalse,
      );
    });

    test('presence retry helper handles shared backoff exceptions', () {
      expect(
        matrixPresenceRetryDelay(
          const UserPresenceRateLimitException(
            retryAfter: Duration(seconds: 12),
          ),
        ),
        const Duration(seconds: 12),
      );
    });

    test(
        'presence failure summary is redacted and does not include status text',
        () {
      final exception = MatrixException.fromJson({
        'errcode': 'M_FORBIDDEN',
        'error': 'Cannot set presence for @other:example.test',
      });

      final summary = matrixPresenceFailureSummary(
        exception,
        userId: '@me:example.test',
        presence: PresenceType.online,
        statusMsg: 'Listening to Artist - Secret Song',
        clearMessage: false,
      );

      expect(summary, contains('presence=online'));
      expect(summary, contains('status_msg=present'));
      expect(summary, contains('errcode=M_FORBIDDEN'));
      expect(summary, isNot(contains('@me:example.test')));
      expect(summary, isNot(contains('@other:example.test')));
      expect(summary, isNot(contains('Secret Song')));
      expect(summary, isNot(contains('Artist')));
    });

    test('presence failure summary marks explicit clears', () {
      final summary = matrixPresenceFailureSummary(
        const MatrixPresenceUpdateException(
          statusCode: 502,
          responseBody: 'bad gateway',
        ),
        userId: '@me:example.test',
        presence: PresenceType.online,
        statusMsg: '',
        clearMessage: true,
      );

      expect(summary, contains('status_msg=clear'));
      expect(summary, contains('status_msg_length=0'));
      expect(summary, contains('http_status=502'));
    });
  });
}

class _FakeOwnershipStore implements ActivityPresenceOwnershipStore {
  _FakeOwnershipStore([Map<String, String>? summaries])
      : summaries = Map<String, String>.from(summaries ?? const {});

  final Map<String, String> summaries;

  @override
  Future<void> clearSummary(String targetId) async {
    summaries.remove(targetId);
  }

  @override
  Future<String?> readSummary(String targetId) async {
    return summaries[targetId];
  }

  @override
  Future<void> writeSummary(String targetId, String summary) async {
    summaries[targetId] = summary;
  }
}

UserActivity _music({
  String title = 'Song',
  String subtitle = 'Artist',
}) {
  return UserActivity(
    id: 'spotify',
    provider: 'spotify',
    kind: ActivityKind.music,
    title: title,
    subtitle: subtitle,
    metadata: const {'state': 'playing'},
  );
}

UserActivity _game({String title = 'Portal'}) {
  return UserActivity(
    id: 'steam',
    provider: 'steam',
    kind: ActivityKind.game,
    title: title,
  );
}

class _PresenceCall {
  const _PresenceCall({
    required this.status,
    this.message,
    this.clearMessage = false,
  });

  final UserPresenceStatus status;
  final String? message;
  final bool clearMessage;
}

class _FakePresenceComponent implements UserPresenceComponent<Client> {
  _FakePresenceComponent({
    this.status = UserPresenceStatus.online,
    this.message,
    this.clearFailuresRemaining = 0,
    this.readFailuresRemaining = 0,
    this.publishFailuresRemaining = 0,
    this.publishErrorFactory,
  });

  final calls = <_PresenceCall>[];
  final StreamController<(String, UserPresence)> _controller =
      StreamController.broadcast();
  final UserPresenceStatus status;
  String? message;
  int clearFailuresRemaining;
  int readFailuresRemaining;
  int publishFailuresRemaining;
  Object Function()? publishErrorFactory;

  @override
  Stream<(String, UserPresence)> get onPresenceChanged => _controller.stream;

  @override
  bool get typingIndicatorEnabled => true;

  @override
  bool get usePublicReadReceipts => true;

  @override
  Future<UserPresence> getUserPresence(String userId) async {
    if (readFailuresRemaining > 0) {
      readFailuresRemaining--;
      throw StateError('presence read failed');
    }

    return UserPresence(
      status,
      message: message == null
          ? null
          : UserPresenceMessage(message!, PresenceMessageType.userCustom),
    );
  }

  @override
  Future<void> setStatus(
    UserPresenceStatus status, {
    String? message,
    bool clearMessage = false,
  }) async {
    if (!clearMessage && publishFailuresRemaining > 0) {
      publishFailuresRemaining--;
      throw publishErrorFactory?.call() ?? StateError('publish failed');
    }

    if (clearMessage && clearFailuresRemaining > 0) {
      clearFailuresRemaining--;
      throw StateError('clear failed');
    }

    calls.add(
      _PresenceCall(
        status: status,
        message: message,
        clearMessage: clearMessage,
      ),
    );
    this.message = clearMessage ? null : message;
  }

  @override
  Future<void> setTypingIndicatorEnabled(bool value) async {}

  @override
  Future<void> setUsePublicReadReceipts(bool value) async {}

  @override
  Client get client => throw UnimplementedError();
}
