import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/activity/activity_publisher.dart';
import 'package:intergalactic/client/components/activity/activity_service.dart';
import 'package:intergalactic/client/components/activity/activity_settings.dart';
import 'package:intergalactic/client/components/activity/activity_source.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_playback.dart';

void main() {
  group('ActivityService', () {
    test('keeps activity hidden by default', () async {
      final source =
          _FakeActivitySource(id: 'spotify', kind: ActivityKind.music);
      final service = ActivityService()..registerSource(source);

      await service.start();
      source.setActivity(_music(provider: 'spotify'));
      await Future<void>.delayed(Duration.zero);

      expect(service.selectedActivity?.title, 'Song');
      expect(service.currentActivity, isNull);
    });

    test('emits local activity when settings allow it', () async {
      final source = _FakeActivitySource(id: 'demo', kind: ActivityKind.music);
      final service = ActivityService(
        settingsProvider: () => const ActivitySettings(showLocally: true),
      )..registerSource(source);

      await service.start();
      source.setActivity(_music(provider: 'demo'));
      await Future<void>.delayed(Duration.zero);

      expect(service.currentActivity?.title, 'Song');
    });

    test('hide current activity suppresses local rendering', () async {
      final source = _FakeActivitySource(id: 'demo', kind: ActivityKind.music);
      var settings = const ActivitySettings(showLocally: true);
      final service = ActivityService(settingsProvider: () => settings)
        ..registerSource(source);

      await service.start();
      source.setActivity(_music(provider: 'demo'));
      await Future<void>.delayed(Duration.zero);

      expect(service.currentActivity, isNotNull);

      settings = const ActivitySettings(
        showLocally: true,
        hideCurrentActivity: true,
      );
      service.refreshSettings();

      expect(service.selectedActivity, isNotNull);
      expect(service.currentActivity, isNull);
    });

    test('filters Spotify and game sources independently', () async {
      final spotify =
          _FakeActivitySource(id: 'spotify', kind: ActivityKind.music);
      final game = _FakeActivitySource(id: 'game', kind: ActivityKind.game);
      var settings = const ActivitySettings(showLocally: true);
      final service = ActivityService(settingsProvider: () => settings)
        ..registerSource(spotify)
        ..registerSource(game);

      await service.start();
      spotify.setActivity(_music(provider: 'spotify'));
      game.setActivity(_game());
      await Future<void>.delayed(Duration.zero);

      expect(service.currentActivity, isNull);

      settings = const ActivitySettings(
        showLocally: true,
        showGameActivity: true,
      );
      service.refreshSettings();

      expect(service.currentActivity?.kind, ActivityKind.game);
      expect(service.currentActivity?.title, 'Tunnel Bore');

      game.setActivity(null);
      settings = const ActivitySettings(
        showLocally: true,
        showSpotify: true,
      );
      service.refreshSettings();
      await Future<void>.delayed(Duration.zero);

      expect(service.currentActivity?.kind, ActivityKind.music);
      expect(service.currentActivity?.provider, 'spotify');
    });

    test('exposes all locally visible activities and swaps the primary card',
        () async {
      final spotify =
          _FakeActivitySource(id: 'spotify', kind: ActivityKind.music);
      final game = _FakeActivitySource(id: 'steam', kind: ActivityKind.game);
      final service = ActivityService(
        settingsProvider: () => const ActivitySettings(
          showLocally: true,
          showSpotify: true,
          showGameActivity: true,
        ),
      )
        ..registerSource(spotify)
        ..registerSource(game);

      await service.start();
      spotify.setActivity(_music(provider: 'spotify'));
      game.setActivity(_game());
      await Future<void>.delayed(Duration.zero);

      expect(service.currentActivities.map((activity) => activity.kind), [
        ActivityKind.game,
        ActivityKind.music,
      ]);
      expect(service.currentActivity?.kind, ActivityKind.game);
      expect(service.currentGameActivity?.kind, ActivityKind.game);
      expect(service.currentGameActivity?.title, 'Tunnel Bore');

      service.selectNextLocalActivity();

      expect(service.selectedActivity?.kind, ActivityKind.music);
      expect(service.currentActivity?.kind, ActivityKind.music);
      expect(service.currentGameActivity?.kind, ActivityKind.game);

      service.selectNextLocalActivity();

      expect(service.currentActivity?.kind, ActivityKind.game);
    });

    test('presence summary only publishes when enabled', () {
      const formatter = ActivityPresenceSummaryFormatter();
      final activity = _music(provider: 'demo');

      expect(formatter.format(activity, const ActivitySettings()), isNull);
      expect(
        formatter.format(
          activity,
          const ActivitySettings(publishBasicStatus: true),
        ),
        'Listening to Artist - Song',
      );
    });

    test('Spotify degraded states clear Matrix status', () {
      const formatter = ActivityPresenceSummaryFormatter();
      const settings = ActivitySettings(
        publishBasicStatus: true,
        showSpotify: true,
      );

      final degraded = UserActivity(
        id: 'spotify',
        kind: ActivityKind.music,
        provider: 'spotify',
        title: 'Spotify ready',
        visibility: ActivityVisibility.selfOnly,
        metadata: {'state': 'deviceAvailable'},
      );
      final playing = UserActivity(
        id: 'spotify',
        kind: ActivityKind.music,
        provider: 'spotify',
        title: 'Song',
        subtitle: 'Artist',
        visibility: ActivityVisibility.selfOnly,
        metadata: {'state': 'playing'},
      );

      expect(formatter.format(degraded, settings), isNull);
      expect(formatter.format(playing, settings), 'Listening to Artist - Song');
    });

    test('Spotify degraded states do not render local activity', () async {
      final source =
          _FakeActivitySource(id: 'spotify', kind: ActivityKind.music);
      final service = ActivityService(
        settingsProvider: () => const ActivitySettings(
          showLocally: true,
          showSpotify: true,
        ),
      )..registerSource(source);

      await service.start();
      source.setActivity(
        const SpotifyPlaybackSnapshot(
          state: SpotifyPlaybackState.deviceAvailable,
        ).toActivity(),
      );
      await Future<void>.delayed(Duration.zero);

      expect(source.currentActivity?.visibility, ActivityVisibility.off);
      expect(service.selectedActivity, isNull);
      expect(service.currentActivity, isNull);
    });

    test('invisible activity is not selected rendered or published', () async {
      final source = _FakeActivitySource(id: 'demo', kind: ActivityKind.music);
      final publisher = _FakePublisher();
      final service = ActivityService(
        settingsProvider: () => const ActivitySettings(
          showLocally: true,
          showSpotify: true,
          showGameActivity: true,
          publishBasicStatus: true,
        ),
      )
        ..registerSource(source)
        ..registerPublisher(publisher);

      await service.start();
      source.setActivity(
        _music(provider: 'demo').copyWith(visibility: ActivityVisibility.off),
      );
      await Future<void>.delayed(Duration.zero);

      expect(service.selectedActivity, isNull);
      expect(service.currentActivity, isNull);
      expect(service.currentActivities, isEmpty);
      expect(publisher.published, isNotEmpty);
      expect(publisher.published.last, isNull);
    });

    test('stale preferred local activity resets when a source disappears',
        () async {
      final spotify =
          _FakeActivitySource(id: 'spotify', kind: ActivityKind.music);
      final game = _FakeActivitySource(id: 'steam', kind: ActivityKind.game);
      final service = ActivityService(
        settingsProvider: () => const ActivitySettings(
          showLocally: true,
          showSpotify: true,
          showGameActivity: true,
        ),
      )
        ..registerSource(spotify)
        ..registerSource(game);

      await service.start();
      spotify.setActivity(_music(provider: 'spotify'));
      game.setActivity(_game());
      await Future<void>.delayed(Duration.zero);

      expect(service.currentActivity?.kind, ActivityKind.game);

      service.selectNextLocalActivity();

      expect(service.currentActivity?.kind, ActivityKind.music);

      spotify.setActivity(null);
      await Future<void>.delayed(Duration.zero);

      expect(service.selectedActivity?.kind, ActivityKind.game);
      expect(service.currentActivity?.kind, ActivityKind.game);

      service.selectNextLocalActivity();

      expect(service.currentActivity?.kind, ActivityKind.game);
    });

    test('publisher receives selected activity when publishing is enabled',
        () async {
      final source = _FakeActivitySource(id: 'demo', kind: ActivityKind.music);
      final publisher = _FakePublisher();
      final service = ActivityService(
        settingsProvider: () => const ActivitySettings(
          publishBasicStatus: true,
        ),
      )
        ..registerSource(source)
        ..registerPublisher(publisher);

      await service.start();
      source.setActivity(_music(provider: 'demo'));
      await Future<void>.delayed(Duration.zero);

      expect(
          publisher.published.whereType<UserActivity>().single.title, 'Song');
    });

    test('publisher receives null when publishing is disabled after activity',
        () async {
      final source = _FakeActivitySource(id: 'demo', kind: ActivityKind.music);
      final publisher = _FakePublisher();
      var settings = const ActivitySettings(publishBasicStatus: true);
      final service = ActivityService(settingsProvider: () => settings)
        ..registerSource(source)
        ..registerPublisher(publisher);

      await service.start();
      source.setActivity(_music(provider: 'demo'));
      await Future<void>.delayed(Duration.zero);

      settings = const ActivitySettings();
      service.refreshSettings();
      await Future<void>.delayed(Duration.zero);

      expect(publisher.published.last, isNull);
    });
  });
}

UserActivity _music({required String provider}) {
  return UserActivity(
    id: provider,
    kind: ActivityKind.music,
    provider: provider,
    title: 'Song',
    subtitle: 'Artist',
    visibility: ActivityVisibility.selfOnly,
  );
}

UserActivity _game() {
  return const UserActivity(
    id: 'game',
    kind: ActivityKind.game,
    title: 'Tunnel Bore',
    subtitle: 'Creative Mode',
    visibility: ActivityVisibility.selfOnly,
  );
}

class _FakeActivitySource implements ActivitySource {
  _FakeActivitySource({required this.id, required this.kind});

  final StreamController<UserActivity?> _controller =
      StreamController.broadcast();

  @override
  final String id;

  @override
  final ActivityKind kind;

  @override
  UserActivity? currentActivity;

  @override
  Stream<UserActivity?> get onActivityChanged => _controller.stream;

  void setActivity(UserActivity? activity) {
    currentActivity = activity;
    _controller.add(activity);
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  @override
  Future<void> executeControl(String controlId) async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

class _FakePublisher implements ActivityPublisher {
  final published = <UserActivity?>[];

  @override
  String get id => 'fake';

  @override
  Future<void> publish(
    UserActivity? activity,
    ActivitySettings settings,
  ) async {
    published.add(activity);
  }
}
