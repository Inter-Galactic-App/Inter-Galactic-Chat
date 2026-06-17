import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/activity/sources/local_media/local_media_activity_source.dart';
import 'package:intergalactic/client/components/activity/sources/local_media/local_media_controls_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalMediaActivitySource', () {
    test('exposes iOS local playback with transport controls', () async {
      final bridge = _FakeLocalMediaControlsBridge(
        const LocalMediaPlaybackSnapshot(
          supported: true,
          state: LocalMediaPlaybackState.playing,
          title: 'Song',
          artist: 'Artist',
          album: 'Album',
          authorizationStatus: 'authorized',
        ),
      );
      final source = LocalMediaActivitySource(
        bridge: bridge,
        pollInterval: const Duration(minutes: 1),
      );

      await source.start();

      final activity = source.currentActivity;
      expect(activity?.id, 'local_media');
      expect(activity?.provider, 'local_media');
      expect(activity?.kind, ActivityKind.music);
      expect(activity?.title, 'Song');
      expect(activity?.subtitle, 'Artist');
      expect(activity?.details, 'Album');
      expect(activity?.controls.map((control) => control.id), [
        'previous',
        'play_pause',
        'next',
      ]);
      expect(activity?.controls.every((control) => control.enabled), isTrue);

      await source.executeControl('play_pause');
      expect(bridge.executedActions, [LocalMediaControlAction.togglePlayPause]);

      await source.dispose();
    });

    test('swallows bridge execution failures without refreshing', () async {
      final failures = <Object>[
        MissingPluginException('local media bridge unavailable'),
        PlatformException(code: 'unavailable'),
        Exception('bridge failed'),
      ];

      for (final failure in failures) {
        final bridge = _FakeLocalMediaControlsBridge(
          const LocalMediaPlaybackSnapshot(
            supported: true,
            state: LocalMediaPlaybackState.playing,
            title: 'Song',
          ),
          executeError: failure,
        );
        final source = LocalMediaActivitySource(
          bridge: bridge,
          pollInterval: const Duration(minutes: 1),
        );

        await source.start();
        expect(bridge.snapshotCalls, 1);

        await source.executeControl('next');

        expect(bridge.executedActions, [LocalMediaControlAction.skipNext]);
        expect(bridge.snapshotCalls, 1);

        await source.dispose();
      }
    });

    test('stays hidden when platform snapshot is unsupported', () async {
      final source = LocalMediaActivitySource(
        bridge: _FakeLocalMediaControlsBridge(
          const LocalMediaPlaybackSnapshot.unsupported(),
        ),
        pollInterval: const Duration(minutes: 1),
      );

      await source.start();

      expect(source.currentActivity, isNull);

      await source.dispose();
    });

    test('updates metadata-only local playback changes', () async {
      final bridge = _FakeLocalMediaControlsBridge(
        const LocalMediaPlaybackSnapshot(
          supported: true,
          state: LocalMediaPlaybackState.playing,
          title: 'Song',
          artist: 'Artist',
          durationMs: 1000,
        ),
      );
      final source = LocalMediaActivitySource(
        bridge: bridge,
        pollInterval: const Duration(minutes: 1),
      );

      await source.start();
      expect(source.currentActivity?.metadata['duration_ms'], 1000);

      bridge.snapshot = const LocalMediaPlaybackSnapshot(
        supported: true,
        state: LocalMediaPlaybackState.playing,
        title: 'Song',
        artist: 'Artist',
        durationMs: 2000,
      );
      await source.refresh();

      expect(source.currentActivity?.metadata['duration_ms'], 2000);

      await source.dispose();
    });
  });
}

class _FakeLocalMediaControlsBridge extends LocalMediaControlsBridge {
  _FakeLocalMediaControlsBridge(this.snapshot, {this.executeError})
      : super(isSupportedPlatform: () => true);

  LocalMediaPlaybackSnapshot snapshot;
  final Object? executeError;
  final List<LocalMediaControlAction> executedActions = [];
  int snapshotCalls = 0;

  @override
  Future<String?> requestAuthorization() async => 'authorized';

  @override
  Future<LocalMediaPlaybackSnapshot> getSnapshot() async {
    snapshotCalls++;
    return snapshot;
  }

  @override
  Future<bool> execute(LocalMediaControlAction action) async {
    executedActions.add(action);
    final error = executeError;
    if (error != null) {
      throw error;
    }
    return true;
  }
}
