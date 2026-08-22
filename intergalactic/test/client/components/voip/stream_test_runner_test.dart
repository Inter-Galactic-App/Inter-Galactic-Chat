import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/screen_share_quality_profile.dart';
import 'package:intergalactic/client/components/voip/stream_test_automation_command.dart';
import 'package:intergalactic/client/components/voip/stream_test_host_load_sampler.dart';
import 'package:intergalactic/client/components/voip/stream_test_loaded_libwebrtc_artifact.dart';
import 'package:intergalactic/client/components/voip/stream_test_runner.dart';
import 'package:intergalactic/client/components/voip/voip_call_diagnostics.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/components/voip/windows_screen_capture_backend.dart';

void main() {
  group('stream test automation request', () {
    test('preserves receiver probe pipe and redacts diagnostic output', () {
      final request = StreamTestAutomationRequest.fromJson({
        'id': 'receiver-probe-round-trip',
        'receiverProbeExternalControlPipe': 'top-level-pipe',
        'receiverProbeStartBeforeShare': false,
        'receiverProbeStartDelayMs': 42,
        'receiverProbe': {
          'enabled': true,
          'mode': 'render',
          'inProcess': false,
          'externalControlPipe': 'nested-pipe',
          'startBeforeShare': true,
          'startDelayMs': 1000,
        },
      });

      expect(request.receiverProbe.externalControlPipe, 'top-level-pipe');
      expect(request.receiverProbe.startBeforeShare, isFalse);
      expect(
        request.receiverProbe.startDelay,
        const Duration(milliseconds: 42),
      );

      final receiverProbeJson =
          request.toJson()['receiverProbe'] as Map<String, Object?>;
      expect(receiverProbeJson['externalControlPipe'], 'top-level-pipe');
      expect(receiverProbeJson.containsKey('externalControlPipeSet'), isFalse);

      final diagnosticReceiverProbeJson =
          request.toDiagnosticJson()['receiverProbe'] as Map<String, Object?>;
      expect(diagnosticReceiverProbeJson['externalControlPipeSet'], isTrue);
      expect(
        diagnosticReceiverProbeJson.containsKey('externalControlPipe'),
        isFalse,
      );

      final roundTrip = StreamTestAutomationRequest.fromJson(request.toJson());
      expect(roundTrip.receiverProbe.externalControlPipe, 'top-level-pipe');
      expect(roundTrip.receiverProbe.startBeforeShare, isFalse);
      expect(
        roundTrip.receiverProbe.startDelay,
        const Duration(milliseconds: 42),
      );
    });
  });

  group('Windows screen capture backend defaults', () {
    test(
      'prefers the D3D11 game hook path for app-default Windows windows',
      () {
        expect(
          defaultWindowsCaptureBackendMode(
            isWindows: true,
            isWebrtcDesktopSource: true,
            isWindowSource: true,
            requestedMode: null,
            preferGameCaptureForWindowSource: true,
            sourceTitle: "Baldur's Gate 3",
          ),
          WindowsScreenCaptureBackendMode.gameD3d11HookExperimental,
        );
      },
    );

    test('keeps the synthetic D3D11 capture target on the game hook path', () {
      expect(
        defaultWindowsCaptureBackendMode(
          isWindows: true,
          isWebrtcDesktopSource: true,
          isWindowSource: true,
          requestedMode: null,
          preferGameCaptureForWindowSource: true,
          sourceTitle: 'Inter Galactic Capture Target',
        ),
        WindowsScreenCaptureBackendMode.gameD3d11HookExperimental,
      );
    });

    test('uses WGC for app-default Windows window shares by default', () {
      expect(
        defaultWindowsCaptureBackendMode(
          isWindows: true,
          isWebrtcDesktopSource: true,
          isWindowSource: true,
          requestedMode: null,
          preferGameCaptureForWindowSource: false,
        ),
        WindowsScreenCaptureBackendMode.wgcOnly,
      );
    });

    test('routes generic normal app windows to WGC', () {
      const sourceTitles = [
        'Inter Galactic WGC Normal Window Smoke',
        'Untitled - Paint',
        'Calculator',
        'Stream Lab Moving Source',
      ];
      for (final sourceTitle in sourceTitles) {
        expect(
          isLikelyD3d11GameWindowCaptureSource(sourceTitle),
          isFalse,
          reason: sourceTitle,
        );
        expect(
          defaultWindowsCaptureBackendMode(
            isWindows: true,
            isWebrtcDesktopSource: true,
            isWindowSource: true,
            requestedMode: null,
            preferGameCaptureForWindowSource: true,
            sourceTitle: sourceTitle,
          ),
          WindowsScreenCaptureBackendMode.wgcOnly,
          reason: sourceTitle,
        );
      }
    });

    test('routes blank app-default window titles to WGC', () {
      expect(isLikelyNonGameWindowCaptureSource(''), isTrue);
      expect(
        defaultWindowsCaptureBackendMode(
          isWindows: true,
          isWebrtcDesktopSource: true,
          isWindowSource: true,
          requestedMode: null,
          preferGameCaptureForWindowSource: true,
          sourceTitle: '',
        ),
        WindowsScreenCaptureBackendMode.wgcOnly,
      );
      expect(
        defaultWindowsCaptureBackendMode(
          isWindows: true,
          isWebrtcDesktopSource: true,
          isWindowSource: true,
          requestedMode: null,
          preferGameCaptureForWindowSource: true,
          sourceTitle: 'Terminal - nick@minipc - Opera',
        ),
        WindowsScreenCaptureBackendMode.wgcOnly,
      );
    });

    test('routes obvious browser windows to WGC', () {
      expect(
        isLikelyNonGameWindowCaptureSource(
          'opera-fallback-window.html - Opera',
        ),
        isTrue,
      );
      expect(
        defaultWindowsCaptureBackendMode(
          isWindows: true,
          isWebrtcDesktopSource: true,
          isWindowSource: true,
          requestedMode: null,
          preferGameCaptureForWindowSource: true,
          sourceTitle: 'opera-fallback-window.html - Opera',
        ),
        WindowsScreenCaptureBackendMode.wgcOnly,
      );
      expect(
        defaultWindowsCaptureBackendMode(
          isWindows: true,
          isWebrtcDesktopSource: true,
          isWindowSource: true,
          requestedMode: null,
          preferGameCaptureForWindowSource: true,
          sourceTitle: 'Inter Galactic Opera GX Fallback Stream Target - Opera',
        ),
        WindowsScreenCaptureBackendMode.wgcOnly,
      );
    });

    test('routes non-DX11 renderer game windows to WGC', () {
      const sourceTitles = [
        'Baldur\'s Gate 3 - Vulkan',
        'Cyberpunk 2077 (DX12)',
        'Starfield [DirectX 12]',
        'Doom Eternal: Vulkan',
        'Minecraft 1.21.5 - OpenGL',
      ];
      for (final sourceTitle in sourceTitles) {
        expect(
          isLikelyNonD3d11GameWindowCaptureSource(sourceTitle),
          isTrue,
          reason: sourceTitle,
        );
        expect(
          isLikelyD3d11GameWindowCaptureSource(sourceTitle),
          isFalse,
          reason: sourceTitle,
        );
        expect(
          defaultWindowsCaptureBackendMode(
            isWindows: true,
            isWebrtcDesktopSource: true,
            isWindowSource: true,
            requestedMode: null,
            preferGameCaptureForWindowSource: true,
            sourceTitle: sourceTitle,
          ),
          WindowsScreenCaptureBackendMode.wgcOnly,
          reason: sourceTitle,
        );
      }
    });

    test('leaves display shares and non-Windows sources on native default', () {
      expect(
        defaultWindowsCaptureBackendMode(
          isWindows: true,
          isWebrtcDesktopSource: true,
          isWindowSource: false,
          requestedMode: null,
        ),
        isNull,
      );
      expect(
        defaultWindowsCaptureBackendMode(
          isWindows: false,
          isWebrtcDesktopSource: true,
          isWindowSource: true,
          requestedMode: null,
        ),
        isNull,
      );
      expect(
        defaultWindowsCaptureBackendMode(
          isWindows: true,
          isWebrtcDesktopSource: false,
          isWindowSource: true,
          requestedMode: null,
        ),
        isNull,
      );
    });

    test('preserves explicit backend overrides', () {
      expect(
        defaultWindowsCaptureBackendMode(
          isWindows: true,
          isWebrtcDesktopSource: true,
          isWindowSource: true,
          requestedMode: WindowsScreenCaptureBackendMode.wgcOnly,
        ),
        WindowsScreenCaptureBackendMode.wgcOnly,
      );
      expect(
        defaultWindowsCaptureBackendMode(
          isWindows: true,
          isWebrtcDesktopSource: true,
          isWindowSource: true,
          requestedMode: WindowsScreenCaptureBackendMode.platformDefault,
        ),
        WindowsScreenCaptureBackendMode.platformDefault,
      );
      expect(
        defaultWindowsCaptureBackendMode(
          isWindows: true,
          isWebrtcDesktopSource: true,
          isWindowSource: true,
          requestedMode:
              WindowsScreenCaptureBackendMode.gameD3d11HookExperimental,
          preferGameCaptureForWindowSource: true,
          sourceTitle: 'Inter Galactic Opera GX Fallback Stream Target - Opera',
        ),
        WindowsScreenCaptureBackendMode.gameD3d11HookExperimental,
      );
      expect(
        defaultWindowsCaptureBackendMode(
          isWindows: true,
          isWebrtcDesktopSource: true,
          isWindowSource: true,
          requestedMode:
              WindowsScreenCaptureBackendMode.gameD3d11HookExperimental,
          preferGameCaptureForWindowSource: true,
          sourceTitle: 'Baldur\'s Gate 3 - Vulkan',
        ),
        WindowsScreenCaptureBackendMode.gameD3d11HookExperimental,
      );
    });

    test('identifies only null-request app-default D3D11 as automatic', () {
      expect(
        isAutomaticWindowsGameCaptureBackend(
          requestedMode: null,
          effectiveMode:
              WindowsScreenCaptureBackendMode.gameD3d11HookExperimental,
        ),
        isTrue,
      );
      expect(
        isAutomaticWindowsGameCaptureBackend(
          requestedMode:
              WindowsScreenCaptureBackendMode.gameD3d11HookExperimental,
          effectiveMode:
              WindowsScreenCaptureBackendMode.gameD3d11HookExperimental,
        ),
        isFalse,
      );
      expect(
        isAutomaticWindowsGameCaptureBackend(
          requestedMode: null,
          effectiveMode: WindowsScreenCaptureBackendMode.directxOnly,
        ),
        isFalse,
      );
    });
  });

  group('Windows screen capture dirty-region defaults', () {
    test('force full-frame for normal Windows WGC-capable window shares', () {
      expect(
        defaultWindowsCaptureDirtyRegionMode(
          isWindows: true,
          isWebrtcDesktopSource: true,
          isWindowSource: true,
          effectiveBackendMode: null,
        ),
        WindowsScreenCaptureDirtyRegionMode.forceFullFrame,
      );
      expect(
        defaultWindowsCaptureDirtyRegionMode(
          isWindows: true,
          isWebrtcDesktopSource: true,
          isWindowSource: true,
          effectiveBackendMode: WindowsScreenCaptureBackendMode.wgcOnly,
        ),
        WindowsScreenCaptureDirtyRegionMode.forceFullFrame,
      );
    });

    test('does not force full-frame for display, DirectX, or crop paths', () {
      expect(
        defaultWindowsCaptureDirtyRegionMode(
          isWindows: true,
          isWebrtcDesktopSource: true,
          isWindowSource: false,
          effectiveBackendMode: null,
        ),
        WindowsScreenCaptureDirtyRegionMode.auto,
      );
      expect(
        defaultWindowsCaptureDirtyRegionMode(
          isWindows: true,
          isWebrtcDesktopSource: true,
          isWindowSource: true,
          effectiveBackendMode: WindowsScreenCaptureBackendMode.directxOnly,
        ),
        WindowsScreenCaptureDirtyRegionMode.auto,
      );
      expect(
        defaultWindowsCaptureDirtyRegionMode(
          isWindows: true,
          isWebrtcDesktopSource: true,
          isWindowSource: true,
          effectiveBackendMode: WindowsScreenCaptureBackendMode.windowCrop,
        ),
        WindowsScreenCaptureDirtyRegionMode.auto,
      );
    });
  });

  group('StreamTestRunner', () {
    test('runs supplied presets and samples once per second', () async {
      var now = DateTime.utc(2026, 5, 18, 18);
      final target = _FakeStreamTestTarget(
        snapshot: _snapshot(
          width: 1280,
          height: 720,
          fps: 30,
          bitrateBps: 1800000,
          lossPercent: 0,
          rttMs: 30,
        ),
      );
      final runner = StreamTestRunner(
        target: target,
        clock: () => now,
        delay: (duration) async {
          now = now.add(duration);
        },
      );

      final result = await runner.run(
        const StreamTestRunConfig(
          presets: [
            ScreenShareProfileConfig.smooth,
            ScreenShareProfileConfig.balanced,
          ],
          durationPerPreset: Duration(seconds: 2),
        ),
      );

      expect(target.startedProfiles, ['Smooth', 'Balanced']);
      expect(target.startedBackends, [null, null]);
      expect(target.startedDirtyRegionModes, [
        WindowsScreenCaptureDirtyRegionMode.auto,
        WindowsScreenCaptureDirtyRegionMode.auto,
      ]);
      expect(target.startedWindowGdiModes, [null, null]);
      expect(target.startedNativePacers, [false, false]);
      expect(target.startedDummyNv12LiveSenders, [false, false]);
      expect(target.stopCount, 2);
      expect(result.presetResults, hasLength(2));
      expect(result.presetResults.first.samples, hasLength(2));
      expect(result.presetResults.last.samples, hasLength(2));
      expect(
        result.toMarkdown(),
        contains('Windows capture backend: App default'),
      );
      expect(
        result.toMarkdown(),
        contains('Native latest-frame pacer: disabled'),
      );
    });

    test('passes dummy NV12 live sender isolation flag to target', () async {
      var now = DateTime.utc(2026, 6, 15, 21);
      final target = _FakeStreamTestTarget(
        snapshot: _snapshot(
          width: 1280,
          height: 720,
          fps: 30,
          bitrateBps: 1800000,
          lossPercent: 0,
          rttMs: 10,
        ),
      );
      final runner = StreamTestRunner(
        target: target,
        clock: () => now,
        delay: (duration) async {
          now = now.add(duration);
        },
      );

      final result = await runner.run(
        const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 1),
          windowsCaptureBackendMode:
              WindowsScreenCaptureBackendMode.gameD3d11HookExperimental,
          dummyNv12LiveSender: true,
        ),
      );

      expect(target.startedProfiles, ['Smooth']);
      expect(target.startedBackends, [
        WindowsScreenCaptureBackendMode.gameD3d11HookExperimental,
      ]);
      expect(target.startedDummyNv12LiveSenders, [true]);
      expect(result.config.toJson(), containsPair('dummyNv12LiveSender', true));
    });

    test(
      'records in-process receiver probe events as gated evidence',
      () async {
        var now = DateTime.utc(2026, 6, 18, 18);
        final target = _FakeStreamTestTarget(
          snapshot: _snapshot(
            width: 1280,
            height: 720,
            fps: 30,
            bitrateBps: 1800000,
            lossPercent: 0,
            rttMs: 30,
          ),
          receiverProbeEvents: [
            {
              'marker': 'intergalactic_stream_view_probe',
              'run_id': 'receiver-test',
              'in_process': true,
              'lane': 'remote_decode',
              'sample_time_utc': '2026-06-18T18:00:01Z',
              'room_hash': 'sha256:room',
              'publisher_identity_hash': 'sha256:publisher',
              'receiver_identity_hash': 'sha256:receiver',
              'track_sid_hash': 'sha256:track',
              'track_source': 'screenShareVideo',
              'subscription_state': 'subscribed',
              'subscribed_quality': 'high',
              'simulcast_layer': 'single',
              'codec': 'VP8',
              'decoder_implementation': 'unknown',
              'hardware_decode': null,
              'renderer_attached': false,
              'renderer_visible': false,
              'frames_received': 30,
              'frames_decoded': 30,
              'unique_fps': null,
              'status': 'stats_only_frame_hash_tap_pending',
            },
          ],
        );
        final runner = StreamTestRunner(
          target: target,
          clock: () => now,
          delay: (duration) async {
            now = now.add(duration);
          },
        );

        final result = await runner.run(
          const StreamTestRunConfig(
            presets: [ScreenShareProfileConfig.smooth],
            durationPerPreset: Duration(seconds: 1),
            receiverProbe: StreamTestReceiverProbeConfig(enabled: true),
          ),
        );

        final probe = result.presetResults.single.receiverProbeResult!;
        expect(target.startedReceiverProbeModes, [
          StreamTestReceiverProbeMode.decodeOnly,
        ]);
        expect(target.stopReceiverProbeCount, 1);
        expect(probe.remoteDecodeEventCount, 1);
        expect(probe.status, 'inconclusive_frame_hash_tap_pending');
        expect(result.toMarkdown(), contains('## Receiver Probe'));
        expect(
          result.toMarkdown(),
          contains('inconclusive_frame_hash_tap_pending'),
        );
      },
    );

    test(
      'passes external receiver handoff config after active share',
      () async {
        var now = DateTime.utc(2026, 6, 18, 18);
        final target = _FakeStreamTestTarget(
          snapshot: _snapshot(
            width: 1280,
            height: 720,
            fps: 30,
            bitrateBps: 1800000,
            lossPercent: 0,
            rttMs: 30,
          ),
        );
        final runner = StreamTestRunner(
          target: target,
          clock: () => now,
          delay: (duration) async {
            now = now.add(duration);
          },
        );

        final result = await runner.run(
          const StreamTestRunConfig(
            presets: [ScreenShareProfileConfig.smooth],
            durationPerPreset: Duration(seconds: 1),
            receiverProbe: StreamTestReceiverProbeConfig(
              enabled: true,
              inProcess: false,
              externalControlPipe: 'intergalactic.receiver-probe.test',
              startBeforeShare: false,
            ),
          ),
        );

        final config = target.startedReceiverProbeConfigs.single;
        final probe = result.presetResults.single.receiverProbeResult!;
        expect(target.receiverProbeStartedWhileSharing, isTrue);
        expect(config.inProcess, isFalse);
        expect(config.externalControlPipe, 'intergalactic.receiver-probe.test');
        expect(probe.inProcess, isFalse);
        expect(probe.status, 'completed_external_receiver_probe_handoff');

        final receiverProbeJson =
            (result.toJson()['config'] as Map<String, Object?>)['receiverProbe']
                as Map<String, Object?>;
        expect(receiverProbeJson['externalControlPipeSet'], isTrue);
        expect(receiverProbeJson.containsKey('externalControlPipe'), isFalse);
      },
    );

    test(
      'starts local preview probe after active share and accepts freshness',
      () async {
        var now = DateTime.utc(2026, 6, 18, 18);
        final target = _FakeStreamTestTarget(
          snapshot: _snapshot(
            width: 1280,
            height: 720,
            fps: 30,
            bitrateBps: 1800000,
            lossPercent: 0,
            rttMs: 30,
          ),
          receiverProbeEvents: [
            {
              'marker': 'intergalactic_stream_view_probe',
              'run_id': 'local-preview-test',
              'in_process': true,
              'lane': 'local_preview',
              'sample_time_utc': '2026-06-18T18:00:01Z',
              'room_hash': 'sha256:room',
              'publisher_identity_hash': 'sha256:publisher',
              'receiver_identity_hash': 'sha256:local-preview',
              'track_sid_hash': 'sha256:track',
              'track_source': 'screenShareVideo',
              'subscription_state': 'local',
              'subscribed_quality': 'local',
              'simulcast_layer': 'single',
              'renderer_attached': true,
              'renderer_visible': true,
              'frames_rendered': 90,
              'freshness_source': 'frame_hash_tap',
              'frame_hash_sample_count': 90,
              'unique_frames': 89,
              'duplicate_frames': 1,
              'unique_fps': 29.8,
              'status': 'frame_hash_tap_active',
            },
          ],
        );
        final runner = StreamTestRunner(
          target: target,
          clock: () => now,
          delay: (duration) async {
            now = now.add(duration);
          },
        );

        final result = await runner.run(
          const StreamTestRunConfig(
            presets: [ScreenShareProfileConfig.smooth],
            durationPerPreset: Duration(seconds: 1),
            receiverProbe: StreamTestReceiverProbeConfig(
              enabled: true,
              mode: StreamTestReceiverProbeMode.localPreview,
              startBeforeShare: true,
            ),
          ),
        );

        final probe = result.presetResults.single.receiverProbeResult!;
        expect(target.receiverProbeStartedWhileSharing, isTrue);
        expect(target.startedReceiverProbeModes, [
          StreamTestReceiverProbeMode.localPreview,
        ]);
        expect(target.stopReceiverProbeCount, 1);
        expect(probe.status, 'completed_local_preview_probe_events');
        expect(probe.localPreviewEventCount, 1);
        expect(probe.remoteDecodeEventCount, 0);
        expect(probe.remoteRendererCallbackLaneEventCount, 0);
        expect(probe.remoteRendererCallbackEventCount, 0);
        expect(probe.latestUniqueFps, 29.8);
        expect(probe.latestFreshnessSource, 'frame_hash_tap');
        expect(
          result.toMarkdown(),
          contains('local=1; decode=0; rendererCallback=0'),
        );
        expect(
          result.diagnosticCoverage.items,
          contains(
            isA<StreamDiagnosticCoverageItem>()
                .having(
                  (item) => item.category,
                  'category',
                  'receiver quality diagnostics',
                )
                .having(
                  (item) => item.status,
                  'status',
                  StreamDiagnosticCoverageStatus.notApplicable,
                )
                .having(
                  (item) => item.detail,
                  'detail',
                  'local-preview probe is diagnostic-only',
                ),
          ),
        );
      },
    );

    test(
      'records in-process receiver probe start failures as blocked',
      () async {
        var now = DateTime.utc(2026, 6, 18, 18);
        final target = _FakeStreamTestTarget(
          snapshot: _snapshot(
            width: 1280,
            height: 720,
            fps: 30,
            bitrateBps: 1800000,
            lossPercent: 0,
            rttMs: 30,
          ),
          receiverProbeStartError: StateError(
            'In-process receiver probe failed to start: HTTP 503',
          ),
        );
        final runner = StreamTestRunner(
          target: target,
          clock: () => now,
          delay: (duration) async {
            now = now.add(duration);
          },
        );

        final result = await runner.run(
          const StreamTestRunConfig(
            presets: [ScreenShareProfileConfig.smooth],
            durationPerPreset: Duration(seconds: 1),
            receiverProbe: StreamTestReceiverProbeConfig(enabled: true),
          ),
        );

        final probe = result.presetResults.single.receiverProbeResult!;
        expect(target.startedReceiverProbeModes, [
          StreamTestReceiverProbeMode.decodeOnly,
        ]);
        expect(probe.status, 'blocked_in_process_receiver_probe_start_failed');
        expect(probe.blockingReason, contains('HTTP 503'));
        expect(probe.events, isEmpty);
        expect(
          result.toMarkdown(),
          contains('blocked_in_process_receiver_probe_start_failed'),
        );
      },
    );

    test('accepts in-process receiver probe frame-hash freshness evidence', () {
      final probe = StreamTestReceiverProbeResult.fromEvents(
        mode: StreamTestReceiverProbeMode.decodeOnly,
        startedAt: DateTime.utc(2026, 6, 18, 18),
        endedAt: DateTime.utc(2026, 6, 18, 18, 0, 3),
        events: [
          {
            'marker': 'intergalactic_stream_view_probe',
            'run_id': 'receiver-test',
            'in_process': true,
            'lane': 'remote_decode',
            'sample_time_utc': '2026-06-18T18:00:03Z',
            'room_hash': 'sha256:room',
            'publisher_identity_hash': 'sha256:publisher',
            'receiver_identity_hash': 'sha256:receiver',
            'track_sid_hash': 'sha256:track',
            'track_source': 'screenShareVideo',
            'subscription_state': 'subscribed',
            'subscribed_quality': 'high',
            'simulcast_layer': 'single',
            'codec': 'VP8',
            'decoder_implementation': 'unknown',
            'renderer_attached': false,
            'renderer_visible': false,
            'freshness_source': 'frame_hash_tap',
            'frame_hash_algorithm': 'sha256-png-captureframe',
            'frame_hash_sample_count': 90,
            'unique_frames': 88,
            'duplicate_frames': 2,
            'unique_fps': 29.3,
            'p50_gap_ms': 33.3,
            'p95_gap_ms': 40.0,
            'max_gap_ms': 50.0,
            'longest_stale_run_ms': 66.7,
            'status': 'frame_hash_tap_active',
          },
        ],
      );

      expect(probe.status, 'completed_receiver_probe_events');
      expect(probe.latestUniqueFps, 29.3);
      expect(probe.latestFreshnessSource, 'frame_hash_tap');
      expect(
        probe.toJson(),
        containsPair('latestFreshnessSource', 'frame_hash_tap'),
      );
    });

    test('accepts visible remote render frame-hash freshness evidence', () {
      final probe = StreamTestReceiverProbeResult.fromEvents(
        mode: StreamTestReceiverProbeMode.render,
        startedAt: DateTime.utc(2026, 6, 18, 18),
        endedAt: DateTime.utc(2026, 6, 18, 18, 0, 3),
        events: [
          {
            'marker': 'intergalactic_stream_view_probe',
            'run_id': 'receiver-test',
            'in_process': true,
            'lane': 'remote_decode',
            'sample_time_utc': '2026-06-18T18:00:03Z',
            'room_hash': 'sha256:room',
            'publisher_identity_hash': 'sha256:publisher',
            'receiver_identity_hash': 'sha256:receiver',
            'track_sid_hash': 'sha256:track',
            'track_source': 'screenShareVideo',
            'subscription_state': 'subscribed',
            'subscribed_quality': 'high',
            'simulcast_layer': 'single',
            'codec': 'VP8',
            'decoder_implementation': 'unknown',
            'renderer_attached': true,
            'renderer_visible': true,
            'freshness_source': 'frame_hash_tap',
            'frame_hash_algorithm':
                'fnv1a-y64x36-uv32x18-native-renderer-onframe',
            'frame_hash_sample_count': 90,
            'unique_frames': 89,
            'duplicate_frames': 1,
            'unique_fps': 29.7,
            'status': 'frame_hash_tap_active',
          },
          {
            'marker': 'intergalactic_stream_view_probe',
            'run_id': 'receiver-test',
            'in_process': true,
            'lane': 'remote_render',
            'stage': 'remote_renderer_callback',
            'sample_time_utc': '2026-06-18T18:00:03Z',
            'room_hash': 'sha256:room',
            'publisher_identity_hash': 'sha256:publisher',
            'receiver_identity_hash': 'sha256:receiver',
            'track_sid_hash': 'sha256:track',
            'track_source': 'screenShareVideo',
            'subscription_state': 'subscribed',
            'subscribed_quality': 'high',
            'simulcast_layer': 'single',
            'codec': 'VP8',
            'decoder_implementation': 'unknown',
            'renderer_attached': true,
            'renderer_visible': true,
            'renderer_width': 1280,
            'renderer_height': 720,
            'inbound_bitrate_bps': 2800000,
            'received_width': 1280,
            'received_height': 720,
            'decoded_width': 1280,
            'decoded_height': 720,
            'rendered_width': 1280,
            'rendered_height': 720,
            'receiver_fps': 30.0,
            'average_qp': 24.5,
            'key_frames_decoded': 2,
            'keyframe_interval_ms': 1000.0,
            'pli_count': 0,
            'fir_count': 0,
            'nack_count': 0,
            'freshness_source': 'frame_hash_tap',
            'frame_hash_algorithm':
                'fnv1a-y64x36-uv32x18-native-renderer-onframe',
            'frame_hash_sample_count': 90,
            'unique_frames': 89,
            'duplicate_frames': 1,
            'unique_fps': 29.7,
            'p50_gap_ms': 33.3,
            'p95_gap_ms': 40.0,
            'max_gap_ms': 50.0,
            'longest_stale_run_ms': 66.7,
            'frame_presentation_p95_gap_ms': 40.0,
            'frame_presentation_max_gap_ms': 50.0,
            'perceptual_difference_score': 0.99,
            'dropped_or_replaced_texture_updates': 0,
            'upscaling_lower_layer_suspected': false,
            'adaptive_stream_low_layer_suspected': false,
            'status': 'frame_hash_tap_active',
          },
          {
            'marker': 'intergalactic_stream_view_probe',
            'run_id': 'receiver-test',
            'in_process': true,
            'lane': 'remote_render',
            'stage': 'remote_texture_ready',
            'sample_time_utc': '2026-06-18T18:00:03.050Z',
            'room_hash': 'sha256:room',
            'publisher_identity_hash': 'sha256:publisher',
            'receiver_identity_hash': 'sha256:receiver',
            'track_sid_hash': 'sha256:track',
            'track_source': 'screenShareVideo',
            'subscription_state': 'subscribed',
            'subscribed_quality': 'high',
            'simulcast_layer': 'single',
            'codec': 'VP8',
            'decoder_implementation': 'unknown',
            'renderer_attached': true,
            'renderer_visible': true,
            'renderer_width': 1280,
            'renderer_height': 720,
            'inbound_bitrate_bps': 2800000,
            'received_width': 1280,
            'received_height': 720,
            'decoded_width': 1280,
            'decoded_height': 720,
            'rendered_width': 1280,
            'rendered_height': 720,
            'receiver_fps': 30.0,
            'freshness_source': 'frame_hash_tap',
            'frame_hash_algorithm':
                'fnv1a-y64x36-uv32x18-native-renderer-onframe',
            'frame_hash_sample_count': 90,
            'unique_frames': 89,
            'duplicate_frames': 1,
            'unique_fps': 29.7,
            'native_frame_sequence': 120,
            'stage_native_frame_sequence': 120,
            'renderer_texture_id': 42,
            'renderer_callback_to_stage_ms': 5.0,
            'status': 'remote_texture_ready_reported',
          },
          {
            'marker': 'intergalactic_stream_view_probe',
            'run_id': 'receiver-test',
            'in_process': true,
            'lane': 'remote_render',
            'stage': 'remote_ui_paint',
            'sample_time_utc': '2026-06-18T18:00:03.066Z',
            'room_hash': 'sha256:room',
            'publisher_identity_hash': 'sha256:publisher',
            'receiver_identity_hash': 'sha256:receiver',
            'track_sid_hash': 'sha256:track',
            'track_source': 'screenShareVideo',
            'subscription_state': 'subscribed',
            'subscribed_quality': 'high',
            'simulcast_layer': 'single',
            'codec': 'VP8',
            'decoder_implementation': 'unknown',
            'renderer_attached': true,
            'renderer_visible': true,
            'renderer_width': 1280,
            'renderer_height': 720,
            'inbound_bitrate_bps': 2800000,
            'received_width': 1280,
            'received_height': 720,
            'decoded_width': 1280,
            'decoded_height': 720,
            'rendered_width': 1280,
            'rendered_height': 720,
            'receiver_fps': 30.0,
            'freshness_source': 'frame_hash_tap',
            'frame_hash_algorithm':
                'fnv1a-y64x36-uv32x18-native-renderer-onframe',
            'frame_hash_sample_count': 90,
            'unique_frames': 89,
            'duplicate_frames': 1,
            'unique_fps': 29.7,
            'native_frame_sequence': 120,
            'stage_native_frame_sequence': 120,
            'stage_observed_gap_ms': 16.0,
            'renderer_texture_id': 42,
            'renderer_callback_to_stage_ms': 21.0,
            'status': 'remote_ui_paint_reported',
          },
          {
            'marker': 'intergalactic_stream_view_probe',
            'run_id': 'receiver-test',
            'in_process': true,
            'lane': 'remote_render',
            'stage': 'remote_screen_present',
            'sample_time_utc': '2026-06-18T18:00:03.083Z',
            'room_hash': 'sha256:room',
            'publisher_identity_hash': 'sha256:publisher',
            'receiver_identity_hash': 'sha256:receiver',
            'track_sid_hash': 'sha256:track',
            'track_source': 'screenShareVideo',
            'subscription_state': 'subscribed',
            'subscribed_quality': 'high',
            'simulcast_layer': 'single',
            'codec': 'VP8',
            'decoder_implementation': 'unknown',
            'renderer_attached': true,
            'renderer_visible': true,
            'renderer_width': 1280,
            'renderer_height': 720,
            'inbound_bitrate_bps': 2800000,
            'received_width': 1280,
            'received_height': 720,
            'decoded_width': 1280,
            'decoded_height': 720,
            'rendered_width': 1280,
            'rendered_height': 720,
            'receiver_fps': 30.0,
            'freshness_source': 'frame_hash_tap',
            'frame_hash_algorithm':
                'fnv1a-y64x36-uv32x18-native-renderer-onframe',
            'frame_hash_sample_count': 90,
            'unique_frames': 89,
            'duplicate_frames': 1,
            'unique_fps': 29.7,
            'native_frame_sequence': 120,
            'stage_native_frame_sequence': 120,
            'stage_observed_gap_ms': 16.7,
            'renderer_texture_id': 42,
            'renderer_callback_to_stage_ms': 38.0,
            'status': 'remote_screen_present_reported',
          },
        ],
      );

      expect(probe.status, 'completed_receiver_probe_events');
      expect(probe.remoteDecodeEventCount, 1);
      expect(probe.remoteRendererCallbackLaneEventCount, 4);
      expect(probe.remoteRendererCallbackEventCount, 1);
      expect(
        probe.receiverPresentationStageEventCount('remote_texture_ready'),
        1,
      );
      expect(probe.receiverPresentationStageEventCount('remote_ui_paint'), 1);
      expect(
        probe.receiverPresentationStageEventCount('remote_screen_present'),
        1,
      );
      expect(probe.remoteScreenPresentEventCount, 1);
      expect(probe.latestTargetStage, 'remote_screen_present');
      expect(probe.latestUniqueFps, 29.7);
      expect(probe.latestFreshnessSource, 'frame_hash_tap');
      final stageJson = probe.toJson()['receiverPresentationStages'] as List;
      expect(
        stageJson.map((stage) => (stage as Map)['stage']),
        containsAll([
          'remote_decode',
          'remote_renderer_callback',
          'remote_texture_ready',
          'remote_ui_paint',
          'remote_screen_present',
        ]),
      );
      expect(
        stageJson,
        contains(
          isA<Map>()
              .having(
                (stage) => stage['stage'],
                'stage',
                'remote_renderer_callback',
              )
              .having((stage) => stage['status'], 'status', 'reported')
              .having(
                (stage) => stage['lane'],
                'lane',
                'remote_renderer_callback',
              ),
        ),
      );
      expect(
        probe.latestQualityDiagnostics,
        containsPair('decodedSize', '1280x720'),
      );
      expect(probe.latestQualityMarkdownLabel, contains('quality=high/single'));
      expect(probe.latestQualityMarkdownLabel, contains('bitrate=2.8 Mbps'));

      final run = StreamTestRunResult(
        startedAt: DateTime.utc(2026, 6, 18, 18),
        endedAt: DateTime.utc(2026, 6, 18, 18, 0, 3),
        targetLabel: 'Synthetic receiver stage report',
        roomId: '!room:example.org',
        config: const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          receiverProbe: StreamTestReceiverProbeConfig(
            enabled: true,
            mode: StreamTestReceiverProbeMode.render,
          ),
        ),
        presetResults: [
          StreamTestPresetResult(
            profile: ScreenShareProfileConfig.smooth,
            startedAt: DateTime.utc(2026, 6, 18, 18),
            endedAt: DateTime.utc(2026, 6, 18, 18, 0, 3),
            samples: [
              StreamTestSample(
                elapsed: const Duration(seconds: 1),
                snapshot: _snapshot(
                  width: 1280,
                  height: 720,
                  fps: 30,
                  bitrateBps: 1800000,
                  lossPercent: 0,
                  rttMs: 20,
                ),
              ),
            ],
            receiverProbeResult: probe,
          ),
        ],
      );
      final markdown = run.toMarkdown();
      expect(markdown, contains('Renderer Callback'));
      expect(markdown, contains('remote_renderer_callback=reported'));
      expect(markdown, contains('remote_texture_ready=reported'));
      expect(markdown, contains('remote_ui_paint=reported'));
      expect(markdown, contains('remote_screen_present=reported'));
    });

    test('rejects receiver unique FPS that is not from frame hashes', () {
      final probe = StreamTestReceiverProbeResult.fromEvents(
        mode: StreamTestReceiverProbeMode.decodeOnly,
        startedAt: DateTime.utc(2026, 6, 18, 18),
        endedAt: DateTime.utc(2026, 6, 18, 18, 0, 3),
        events: [
          {
            'marker': 'intergalactic_stream_view_probe',
            'run_id': 'receiver-test',
            'in_process': true,
            'lane': 'remote_decode',
            'sample_time_utc': '2026-06-18T18:00:03Z',
            'room_hash': 'sha256:room',
            'publisher_identity_hash': 'sha256:publisher',
            'receiver_identity_hash': 'sha256:receiver',
            'track_sid_hash': 'sha256:track',
            'track_source': 'screenShareVideo',
            'subscription_state': 'subscribed',
            'subscribed_quality': 'high',
            'simulcast_layer': 'single',
            'codec': 'VP8',
            'decoder_implementation': 'unknown',
            'renderer_attached': false,
            'renderer_visible': false,
            'freshness_source': 'receiver_stats_frame_counter',
            'unique_fps': 30.0,
            'status': 'stats_only_frame_counter',
          },
        ],
      );

      expect(probe.status, 'inconclusive_frame_hash_tap_pending');
      expect(
        probe.blockingReason,
        contains('freshness_source was not frame_hash_tap'),
      );
    });

    test(
      'includes parsed host load in report JSON, Markdown, and coverage',
      () {
        final report = StreamTestHostLoadReport(
          sampleIntervalMs: 2000,
          targetProcessLoadRequested: true,
          samples: [
            StreamTestHostLoadSample(
              timestampUtc: DateTime.utc(2026, 6, 13, 18),
              systemCpuPercent: 20,
              memoryUsedPercent: 50,
              memoryAvailableMb: 12000,
              appCpuPercent: 4,
              targetCpuPercent: 12,
              gpu3dPercent: 30,
              gpuVideoEncodePercent: 3,
            ),
            StreamTestHostLoadSample(
              timestampUtc: DateTime.utc(2026, 6, 13, 18, 0, 2),
              systemCpuPercent: 40,
              memoryUsedPercent: 60,
              memoryAvailableMb: 10000,
              appCpuPercent: 6,
              targetCpuPercent: 18,
              gpu3dPercent: 70,
              gpuVideoEncodePercent: 7,
            ),
          ],
        );
        final result = StreamTestRunResult(
          startedAt: DateTime.utc(2026, 6, 13, 18),
          endedAt: DateTime.utc(2026, 6, 13, 18, 0, 2),
          targetLabel: 'Fake stream target',
          roomId: '!fake:example.test',
          config: const StreamTestRunConfig(
            presets: [ScreenShareProfileConfig.smooth],
          ),
          presetResults: const [],
          hostLoadReport: report,
        );

        final json = result.toJson();
        final hostLoad = json['hostLoad'] as Map<String, Object?>?;
        expect(hostLoad, isNotNull);
        expect(hostLoad!['sampleCount'], 2);
        expect(
          result.toMarkdown(),
          allOf(
            contains('## Host/System Load'),
            contains('System CPU'),
            contains('30.0%'),
            contains('70.0%'),
          ),
        );
        expect(
          result.diagnosticCoverage.items,
          contains(
            isA<StreamDiagnosticCoverageItem>()
                .having((item) => item.category, 'category', 'host/system load')
                .having(
                  (item) => item.status,
                  'status',
                  StreamDiagnosticCoverageStatus.available,
                ),
          ),
        );
      },
    );

    test('rejects host load samples with invalid timestamps', () {
      expect(
        () => StreamTestHostLoadSample.fromJson({
          'timestamp': 'not-a-date',
          'systemCpuPercent': 20,
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'starts and stops injected host load sampler for runner batches',
      () async {
        var now = DateTime.utc(2026, 6, 13, 19);
        final hostSampler = _FakeHostLoadSampler(
          report: StreamTestHostLoadReport(
            sampleIntervalMs: 2000,
            targetProcessLoadRequested: false,
            samples: [
              StreamTestHostLoadSample(
                timestampUtc: DateTime.utc(2026, 6, 13, 19),
                systemCpuPercent: 10,
                memoryUsedPercent: 45,
                memoryAvailableMb: 14000,
                gpu3dPercent: 15,
              ),
            ],
          ),
        );
        final target = _FakeStreamTestTarget(
          snapshot: _snapshot(
            width: 1280,
            height: 720,
            fps: 30,
            bitrateBps: 1800000,
            lossPercent: 0,
            rttMs: 30,
          ),
        );
        final runner = StreamTestRunner(
          target: target,
          clock: () => now,
          delay: (duration) async {
            now = now.add(duration);
          },
          hostLoadSamplerFactory: (_) => hostSampler,
        );

        final result = await runner.run(
          const StreamTestRunConfig(
            presets: [ScreenShareProfileConfig.smooth],
            durationPerPreset: Duration(seconds: 1),
            warmupDuration: Duration.zero,
            sampleInterval: Duration(seconds: 1),
          ),
        );

        expect(hostSampler.startCount, 1);
        expect(hostSampler.stopCount, 1);
        expect(result.hostLoadReport?.samples, hasLength(1));
        expect(result.toJson()['hostLoad'], isNotNull);
      },
    );

    test(
      'stops timed-out host load sampler before marking unavailable',
      () async {
        var now = DateTime.utc(2026, 6, 13, 19);
        final startCompleter = Completer<void>();
        final hostSampler = _FakeHostLoadSampler(
          report: StreamTestHostLoadReport.unavailable(reason: 'unused'),
          startFuture: startCompleter.future,
        );
        final runner = StreamTestRunner(
          target: _FakeStreamTestTarget(
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 30,
              bitrateBps: 1800000,
              lossPercent: 0,
              rttMs: 30,
            ),
          ),
          clock: () => now,
          delay: (duration) async {
            now = now.add(duration);
          },
          hostLoadSamplerFactory: (_) => hostSampler,
          hostLoadSamplerStartTimeout: const Duration(milliseconds: 1),
        );

        final result = await runner.run(
          const StreamTestRunConfig(
            presets: [ScreenShareProfileConfig.smooth],
            durationPerPreset: Duration.zero,
            warmupDuration: Duration.zero,
            sampleInterval: Duration(milliseconds: 1),
          ),
        );
        startCompleter.complete();

        expect(hostSampler.startCount, 1);
        expect(hostSampler.stopCount, 1);
        expect(result.hostLoadReport?.available, isFalse);
        expect(
          result.hostLoadReport?.unavailableReason,
          'host load sampler failed to start',
        );
      },
    );

    test('marks host load unavailable when sampler stop times out', () async {
      var now = DateTime.utc(2026, 6, 13, 19);
      final stopCompleter = Completer<StreamTestHostLoadReport>();
      final hostSampler = _FakeHostLoadSampler(
        report: StreamTestHostLoadReport.unavailable(reason: 'unused'),
        stopFuture: stopCompleter.future,
      );
      final runner = StreamTestRunner(
        target: _FakeStreamTestTarget(
          snapshot: _snapshot(
            width: 1280,
            height: 720,
            fps: 30,
            bitrateBps: 1800000,
            lossPercent: 0,
            rttMs: 30,
          ),
        ),
        clock: () => now,
        delay: (duration) async {
          now = now.add(duration);
        },
        hostLoadSamplerFactory: (_) => hostSampler,
        hostLoadSamplerStopTimeout: const Duration(milliseconds: 1),
      );

      final result = await runner.run(
        const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration.zero,
          warmupDuration: Duration.zero,
          sampleInterval: Duration(milliseconds: 1),
        ),
      );
      stopCompleter.complete(
        StreamTestHostLoadReport.unavailable(reason: 'completed after timeout'),
      );

      expect(hostSampler.startCount, 1);
      expect(hostSampler.stopCount, 1);
      expect(result.hostLoadReport?.available, isFalse);
      expect(
        result.hostLoadReport?.unavailableReason,
        'host load sampler failed to stop',
      );
    });

    test(
      'continues when share becomes active before start future completes',
      () async {
        var now = DateTime.utc(2026, 6, 9, 18);
        final pendingStart = Completer<void>();
        final target = _FakeStreamTestTarget(
          snapshot: _snapshot(
            width: 1280,
            height: 720,
            fps: 30,
            bitrateBps: 1800000,
            lossPercent: 0,
            rttMs: 30,
          ),
          startPresetFuture: pendingStart.future,
        );
        final runner = StreamTestRunner(
          target: target,
          clock: () => now,
          delay: (duration) async {
            now = now.add(duration);
          },
          shareStartTimeout: const Duration(seconds: 1),
          shareStopTimeout: const Duration(seconds: 1),
          postActiveStartCompletionTimeout: const Duration(milliseconds: 1),
        );

        final result = await runner.run(
          const StreamTestRunConfig(
            presets: [ScreenShareProfileConfig.smooth],
            durationPerPreset: Duration(seconds: 2),
            warmupDuration: Duration.zero,
            sampleInterval: Duration(seconds: 1),
          ),
        );

        expect(pendingStart.isCompleted, isFalse);
        expect(result.presetResults.single.error, isNull);
        expect(result.presetResults.single.samples, hasLength(2));
        expect(target.stopCount, 1);
        expect(target.sharing, isFalse);
      },
    );

    test(
      'starts receiver probe after active share before start future completes',
      () async {
        var now = DateTime.utc(2026, 6, 18, 19);
        final pendingStart = Completer<void>();
        final target = _FakeStreamTestTarget(
          snapshot: _snapshot(
            width: 1280,
            height: 720,
            fps: 30,
            bitrateBps: 1800000,
            lossPercent: 0,
            rttMs: 30,
          ),
          startPresetFuture: pendingStart.future,
        );
        final runner = StreamTestRunner(
          target: target,
          clock: () => now,
          delay: (duration) async {
            now = now.add(duration);
          },
          shareStartTimeout: const Duration(seconds: 1),
          shareStopTimeout: const Duration(seconds: 1),
          postActiveStartCompletionTimeout: const Duration(milliseconds: 1),
        );

        final result = await runner.run(
          const StreamTestRunConfig(
            presets: [ScreenShareProfileConfig.smooth],
            durationPerPreset: Duration(seconds: 1),
            warmupDuration: Duration.zero,
            sampleInterval: Duration(seconds: 1),
            receiverProbe: StreamTestReceiverProbeConfig(
              enabled: true,
              startBeforeShare: false,
            ),
          ),
        );

        expect(pendingStart.isCompleted, isFalse);
        expect(target.startedReceiverProbeModes, [
          StreamTestReceiverProbeMode.decodeOnly,
        ]);
        expect(target.stopReceiverProbeCount, 1);
        expect(result.presetResults.single.error, isNull);
        expect(result.presetResults.single.receiverProbeResult, isNotNull);
        expect(target.stopCount, 1);
        expect(target.sharing, isFalse);
      },
    );

    test(
      'stops before measurement when post-active sender limits fail',
      () async {
        var now = DateTime.utc(2026, 6, 10, 11);
        final target = _FakeStreamTestTarget(
          snapshot: _snapshot(
            width: 1280,
            height: 720,
            fps: 30,
            bitrateBps: 1800000,
            lossPercent: 0,
            rttMs: 30,
          ),
          startPresetHandler: () async {
            throw TimeoutException(
              'screen-share sender limits timed out after 5s',
            );
          },
        );
        final runner = StreamTestRunner(
          target: target,
          clock: () => now,
          delay: (duration) async {
            now = now.add(duration);
          },
          shareStartTimeout: const Duration(seconds: 1),
          shareStopTimeout: const Duration(seconds: 1),
          postActiveStartCompletionTimeout: const Duration(milliseconds: 50),
        );

        final result = await runner.run(
          const StreamTestRunConfig(
            presets: [ScreenShareProfileConfig.smooth],
            durationPerPreset: Duration(seconds: 2),
            warmupDuration: Duration.zero,
          ),
        );

        final preset = result.presetResults.single;
        expect(preset.samples, isEmpty);
        expect(preset.error, contains('sender limits timed out'));
        expect(preset.score.bottleneck.label, 'runner_error');
        expect(target.stopCount, 1);
        expect(target.sharing, isFalse);
      },
    );

    test('reports start completion without active screen share', () async {
      var now = DateTime.utc(2026, 6, 9, 18, 15);
      final target = _FakeStreamTestTarget(
        snapshot: _snapshot(
          width: 1280,
          height: 720,
          fps: 30,
          bitrateBps: 1800000,
          lossPercent: 0,
          rttMs: 30,
        ),
        startSharingOnStart: false,
      );
      final runner = StreamTestRunner(
        target: target,
        clock: () => now,
        delay: (duration) async {
          now = now.add(duration);
        },
        shareStartTimeout: const Duration(seconds: 1),
        shareStopTimeout: const Duration(seconds: 1),
      );

      final result = await runner.run(
        const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 2),
          warmupDuration: Duration.zero,
        ),
      );

      final preset = result.presetResults.single;
      expect(preset.samples, isEmpty);
      expect(
        preset.error,
        contains(
          'Stream-test preset start completed before screen share became active.',
        ),
      );
      expect(preset.score.bottleneck.label, 'runner_error');
      expect(target.stopCount, 0);
    });

    test('classifies publishVideoTrack pre-publication timeout', () async {
      var now = DateTime.utc(2026, 6, 9, 18, 30);
      final target = _FakeStreamTestTarget(
        snapshot: _snapshot(
          width: 1280,
          height: 720,
          fps: 30,
          bitrateBps: 1800000,
          lossPercent: 0,
          rttMs: 30,
        ),
        startSharingOnStart: false,
        startPresetHandler: () async {
          throw TimeoutException(
            'LiveKit publishVideoTrack timed out before local track '
            'publication after 20s '
            '(stage=publishVideoTrack_pre_event)',
          );
        },
      );
      final runner = StreamTestRunner(
        target: target,
        clock: () => now,
        delay: (duration) async {
          now = now.add(duration);
        },
        shareStartTimeout: const Duration(seconds: 1),
        shareStopTimeout: const Duration(seconds: 1),
      );

      final result = await runner.run(
        const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 2),
          warmupDuration: Duration.zero,
        ),
      );

      final preset = result.presetResults.single;
      expect(preset.samples, isEmpty);
      expect(preset.error, contains('publishVideoTrack timed out'));
      expect(
        preset.score.bottleneck.label,
        'livekit_publish_pre_event_limited',
      );
      expect(
        preset.score.bottleneck.recommendedNextAction,
        'fix game-capture handoff',
      );
      expect(
        result.toMarkdown(),
        contains('livekit_publish_pre_event_limited'),
      );
      expect(target.stopCount, 0);
    });

    test(
      'times out stalled diagnostics sampling and cleans up share',
      () async {
        var now = DateTime.utc(2026, 6, 9, 14);
        final target = _FakeStreamTestTarget(
          snapshot: _snapshot(
            width: 1280,
            height: 720,
            fps: 30,
            bitrateBps: 1800000,
            lossPercent: 0,
            rttMs: 30,
          ),
          collectDiagnosticsFuture:
              Completer<VoipCallDiagnosticsSnapshot>().future,
        );
        final runner = StreamTestRunner(
          target: target,
          clock: () => now,
          delay: (duration) async {
            now = now.add(duration);
          },
          diagnosticSampleTimeout: const Duration(milliseconds: 1),
          shareStartTimeout: const Duration(seconds: 1),
          shareStopTimeout: const Duration(seconds: 1),
        );

        final result = await runner.run(
          const StreamTestRunConfig(
            presets: [ScreenShareProfileConfig.smooth],
            durationPerPreset: Duration(seconds: 2),
            warmupDuration: Duration.zero,
            sampleInterval: Duration(milliseconds: 10),
          ),
        );

        final preset = result.presetResults.single;
        expect(preset.samples, isEmpty);
        expect(
          preset.error,
          contains('collect stream diagnostics timed out after 1ms'),
        );
        expect(preset.score.bottleneck.label, 'runner_error');
        expect(target.stopCount, 1);
        expect(target.sharing, isFalse);
      },
    );

    test(
      'times out the whole batch and stops sharing when progress stalls',
      () async {
        var now = DateTime.utc(2026, 6, 9, 16);
        final presetStarted = Completer<void>();
        final target = _FakeStreamTestTarget(
          snapshot: _snapshot(
            width: 1280,
            height: 720,
            fps: 30,
            bitrateBps: 1800000,
            lossPercent: 0,
            rttMs: 30,
          ),
          startPresetHandler: () {
            if (!presetStarted.isCompleted) {
              presetStarted.complete();
            }
            return Future<void>.value();
          },
        );
        final runner = StreamTestRunner(
          target: target,
          clock: () => now,
          delay: (duration) => Completer<void>().future,
          loadedLibwebrtcArtifactProvider: () =>
              Future<StreamTestLoadedLibwebrtcArtifact?>.value(),
          hostLoadSamplerFactory: (_) => _FakeHostLoadSampler(
            report: StreamTestHostLoadReport.unavailable(reason: 'test'),
          ),
          runTimeout: const Duration(milliseconds: 50),
          shareStopTimeout: const Duration(seconds: 1),
        );

        final runFuture = runner.run(
          const StreamTestRunConfig(
            presets: [ScreenShareProfileConfig.smooth],
            durationPerPreset: Duration(seconds: 30),
          ),
        );
        await presetStarted.future.timeout(const Duration(seconds: 1));

        await expectLater(
          runFuture,
          throwsA(
            isA<TimeoutException>().having(
              (error) => error.message,
              'message',
              contains('stream-test runner batch timed out after 50ms'),
            ),
          ),
        );
        expect(target.stopCount, 1);
        expect(target.sharing, isFalse);
      },
    );

    test(
      'cancels timed out batch before delayed sample resumes target work',
      () async {
        var now = DateTime.utc(2026, 6, 10, 11, 15);
        final firstCollect = Completer<VoipCallDiagnosticsSnapshot>();
        var collectCount = 0;
        final snapshot = _snapshot(
          width: 1280,
          height: 720,
          fps: 30,
          bitrateBps: 1800000,
          lossPercent: 0,
          rttMs: 30,
        );
        final target = _FakeStreamTestTarget(
          snapshot: snapshot,
          collectDiagnosticsHandler: () {
            collectCount++;
            if (collectCount == 1) {
              return firstCollect.future;
            }
            return Future<VoipCallDiagnosticsSnapshot>.value(snapshot);
          },
        );
        final runner = StreamTestRunner(
          target: target,
          clock: () => now,
          delay: (duration) async {
            now = now.add(duration);
          },
          runTimeout: const Duration(milliseconds: 20),
          shareStopTimeout: const Duration(seconds: 1),
          diagnosticSampleTimeout: const Duration(seconds: 10),
        );

        await expectLater(
          runner.run(
            const StreamTestRunConfig(
              presets: [ScreenShareProfileConfig.smooth],
              durationPerPreset: Duration(seconds: 2),
              warmupDuration: Duration.zero,
              sampleInterval: Duration(seconds: 1),
            ),
          ),
          throwsA(isA<TimeoutException>()),
        );
        expect(target.stopCount, 1);
        expect(target.sharing, isFalse);

        firstCollect.complete(snapshot);
        await pumpEventQueue();

        expect(collectCount, 1);
        expect(target.stopCount, 1);
        expect(target.sharing, isFalse);
      },
    );

    test(
      'bounds diagnostic log marker reads so reports still complete',
      () async {
        var now = DateTime.utc(2026, 6, 9, 16, 30);
        final target = _FakeStreamTestTarget(
          snapshot: _snapshot(
            width: 1280,
            height: 720,
            fps: 30,
            bitrateBps: 1800000,
            lossPercent: 0,
            rttMs: 30,
          ),
        );
        final runner = StreamTestRunner(
          target: target,
          clock: () => now,
          delay: (duration) async {
            now = now.add(duration);
          },
          diagnosticLogProvider: () => Completer<String>().future,
          diagnosticLogTimeout: const Duration(milliseconds: 1),
          runTimeout: const Duration(seconds: 2),
        );

        final result = await runner.run(
          const StreamTestRunConfig(
            presets: [ScreenShareProfileConfig.smooth],
            durationPerPreset: Duration(seconds: 1),
            warmupDuration: Duration.zero,
          ),
        );

        expect(result.presetResults, hasLength(1));
        expect(result.presetResults.single.error, isNull);
        expect(
          result.presetResults.single.diagnosticLogMarkers.join('\n'),
          contains(
            'diagnostic log marker read failed: TimeoutException: '
            'collect stream diagnostic logs timed out after 1ms',
          ),
        );
      },
    );

    test('passes dirty-region override through stream-test runs', () async {
      var now = DateTime.utc(2026, 5, 28, 12);
      final progressLabels = <String>[];
      final target = _FakeStreamTestTarget(
        snapshot: _snapshot(
          width: 1280,
          height: 720,
          fps: 30,
          bitrateBps: 1800000,
          lossPercent: 0,
          rttMs: 20,
        ),
      );
      final runner = StreamTestRunner(
        target: target,
        clock: () => now,
        delay: (duration) async {
          now = now.add(duration);
        },
        onProgress: (progress) => progressLabels.add(progress.label),
      );

      final result = await runner.run(
        const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 1),
          windowsCaptureDirtyRegionMode:
              WindowsScreenCaptureDirtyRegionMode.forceFullFrame,
        ),
      );

      expect(target.startedDirtyRegionModes, [
        WindowsScreenCaptureDirtyRegionMode.forceFullFrame,
      ]);
      expect(
        progressLabels.single,
        '1/1 Smooth - App default + full-frame dirty regions',
      );
      expect(
        result.toJsonText(),
        contains('"windowsCaptureDirtyRegionMode": "force-full-frame"'),
      );
      expect(
        result.toMarkdown(),
        contains('Native dirty-region mode: Force full-frame dirty regions'),
      );
    });

    test(
      'applies measured D3D11 game-hook profile before publish and scoring',
      () async {
        var now = DateTime.utc(2026, 6, 7, 21);
        final target = _FakeStreamTestTarget(
          snapshot: _snapshot(
            width: 1280,
            height: 720,
            fps: 30,
            bitrateBps: 6000000,
            lossPercent: 0,
            rttMs: 3,
            requestedWidth: 1280,
            requestedHeight: 720,
            requestedFps: 30,
          ),
        );
        final runner = StreamTestRunner(
          target: target,
          clock: () => now,
          delay: (duration) async {
            now = now.add(duration);
          },
        );

        final result = await runner.run(
          const StreamTestRunConfig(
            presets: [ScreenShareProfileConfig.highQuality],
            durationPerPreset: Duration(seconds: 1),
            warmupDuration: Duration.zero,
            windowsCaptureBackendMode:
                WindowsScreenCaptureBackendMode.gameD3d11HookExperimental,
          ),
        );

        expect(target.startedProfiles, ['High Quality']);
        expect(target.startedMainLayers.single.width, 1280);
        expect(target.startedMainLayers.single.height, 720);
        expect(target.startedMainLayers.single.maxFramerate, 30);
        expect(target.startedMainLayers.single.targetFramerateForScoring, 30);
        expect(
          result.presetResults.single.profile.mainLayer.resolutionLabel,
          '1280x720',
        );
        expect(
          result
              .presetResults
              .single
              .profile
              .mainLayer
              .targetFramerateForScoring,
          30,
        );
        expect(result.presetResults.single.score.targetResolution, 25);
      },
    );

    test('scores app-default window tests with the D3D11 game-hook envelope '
        'without sending an explicit backend override', () async {
      var now = DateTime.utc(2026, 6, 8, 21);
      final target = _FakeStreamTestTarget(
        snapshot: _snapshot(
          width: 1280,
          height: 720,
          fps: 30,
          bitrateBps: 6000000,
          lossPercent: 0,
          rttMs: 3,
          requestedWidth: 1280,
          requestedHeight: 720,
          requestedFps: 30,
        ),
      );
      final runner = StreamTestRunner(
        target: target,
        clock: () => now,
        delay: (duration) async {
          now = now.add(duration);
        },
      );

      final result = await runner.run(
        const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.highQuality],
          durationPerPreset: Duration(seconds: 1),
          warmupDuration: Duration.zero,
          sourceMetadata: StreamTestSourceMetadata(
            sourceType: 'window',
            sourceIdHash: 'abc',
            processId: 42,
            sourceTitle: "Baldur's Gate 3",
          ),
        ),
      );

      expect(target.startedBackends, [null]);
      expect(target.startedProfiles, ['High Quality']);
      expect(target.startedMainLayers.single.width, 1280);
      expect(target.startedMainLayers.single.height, 720);
      expect(target.startedMainLayers.single.maxFramerate, 30);
      expect(target.startedMainLayers.single.targetFramerateForScoring, 30);
      expect(
        result.presetResults.single.profile.mainLayer.resolutionLabel,
        '1280x720',
      );
      expect(
        result.presetResults.single.profile.mainLayer.targetFramerateForScoring,
        30,
      );
    });

    test(
      'keeps browser-like app-default window tests on the legacy envelope',
      () async {
        var now = DateTime.utc(2026, 6, 8, 21);
        final target = _FakeStreamTestTarget(
          snapshot: _snapshot(
            width: 1920,
            height: 1080,
            fps: 60,
            bitrateBps: 6000000,
            lossPercent: 0,
            rttMs: 3,
            requestedWidth: 1920,
            requestedHeight: 1080,
            requestedFps: 60,
          ),
        );
        final runner = StreamTestRunner(
          target: target,
          clock: () => now,
          delay: (duration) async {
            now = now.add(duration);
          },
        );

        final result = await runner.run(
          const StreamTestRunConfig(
            presets: [ScreenShareProfileConfig.highQuality],
            durationPerPreset: Duration(seconds: 1),
            warmupDuration: Duration.zero,
            sourceMetadata: StreamTestSourceMetadata(
              sourceType: 'window',
              sourceIdHash: 'abc',
              processId: 42,
              sourceTitle: 'opera-fallback-window.html - Opera',
            ),
          ),
        );

        expect(target.startedBackends, [null]);
        expect(target.startedProfiles, ['High Quality']);
        expect(target.startedMainLayers.single.width, 1920);
        expect(target.startedMainLayers.single.height, 1080);
        expect(target.startedMainLayers.single.maxFramerate, 60);
        expect(
          result.presetResults.single.profile.mainLayer.resolutionLabel,
          '1920x1080',
        );
        expect(
          result
              .presetResults
              .single
              .profile
              .mainLayer
              .targetFramerateForScoring,
          60,
        );
      },
    );

    test(
      'keeps non-DX11 app-default game window tests on the legacy envelope',
      () async {
        var now = DateTime.utc(2026, 6, 22, 18);
        final target = _FakeStreamTestTarget(
          snapshot: _snapshot(
            width: 1920,
            height: 1080,
            fps: 60,
            bitrateBps: 6000000,
            lossPercent: 0,
            rttMs: 3,
            requestedWidth: 1920,
            requestedHeight: 1080,
            requestedFps: 60,
          ),
        );
        final runner = StreamTestRunner(
          target: target,
          clock: () => now,
          delay: (duration) async {
            now = now.add(duration);
          },
        );

        final result = await runner.run(
          const StreamTestRunConfig(
            presets: [ScreenShareProfileConfig.highQuality],
            durationPerPreset: Duration(seconds: 1),
            warmupDuration: Duration.zero,
            sourceMetadata: StreamTestSourceMetadata(
              sourceType: 'window',
              sourceIdHash: 'abc',
              processId: 42,
              sourceTitle: 'Cyberpunk 2077 (DX12)',
            ),
          ),
        );

        expect(target.startedBackends, [null]);
        expect(target.startedProfiles, ['High Quality']);
        expect(target.startedMainLayers.single.width, 1920);
        expect(target.startedMainLayers.single.height, 1080);
        expect(target.startedMainLayers.single.maxFramerate, 60);
        expect(
          result.presetResults.single.profile.mainLayer.resolutionLabel,
          '1920x1080',
        );
        expect(
          result
              .presetResults
              .single
              .profile
              .mainLayer
              .targetFramerateForScoring,
          60,
        );
      },
    );

    test('cycles requested window-GDI modes for window/directx runs', () async {
      var now = DateTime.utc(2026, 6, 3, 20);
      final progressLabels = <String>[];
      final target = _FakeStreamTestTarget(
        snapshot: _snapshot(
          width: 1280,
          height: 720,
          fps: 30,
          bitrateBps: 1800000,
          lossPercent: 0,
          rttMs: 20,
        ),
      );
      final runner = StreamTestRunner(
        target: target,
        clock: () => now,
        delay: (duration) async {
          now = now.add(duration);
        },
        onProgress: (progress) => progressLabels.add(progress.label),
      );

      final result = await runner.run(
        const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 1),
          sourceMetadata: StreamTestSourceMetadata(
            sourceType: 'window',
            sourceIdHash: 'abc',
          ),
          windowsCaptureBackendMode:
              WindowsScreenCaptureBackendMode.directxOnly,
          windowsWindowGdiCaptureModes: [
            WindowsWindowGdiCaptureMode.defaultMode,
            WindowsWindowGdiCaptureMode.printWindowFirst,
            WindowsWindowGdiCaptureMode.bitBltFirst,
          ],
        ),
      );

      expect(target.startedBackends, [
        WindowsScreenCaptureBackendMode.directxOnly,
        WindowsScreenCaptureBackendMode.directxOnly,
        WindowsScreenCaptureBackendMode.directxOnly,
      ]);
      expect(target.startedWindowGdiModes, [
        WindowsWindowGdiCaptureMode.defaultMode,
        WindowsWindowGdiCaptureMode.printWindowFirst,
        WindowsWindowGdiCaptureMode.bitBltFirst,
      ]);
      expect(progressLabels, [
        '1/3 Smooth - DirectX / Window GDI only + GDI current',
        '2/3 Smooth - DirectX / Window GDI only + GDI plain print',
        '3/3 Smooth - DirectX / Window GDI only + GDI BitBlt first',
      ]);
      expect(result.presetResults, hasLength(3));
      expect(
        result.toJsonText(),
        contains('"windowsWindowGdiCaptureMode": "bitblt-first"'),
      );
      expect(
        result.toMarkdown(),
        contains(
          'Window GDI capture methods: '
          'Current PrintWindow full-content first, '
          'Plain PrintWindow first, BitBlt first',
        ),
      );
    });

    test('does not expand window-GDI modes for display sources', () async {
      var now = DateTime.utc(2026, 6, 3, 20);
      final target = _FakeStreamTestTarget(
        snapshot: _snapshot(
          width: 1280,
          height: 720,
          fps: 30,
          bitrateBps: 1800000,
          lossPercent: 0,
          rttMs: 20,
        ),
      );
      final runner = StreamTestRunner(
        target: target,
        clock: () => now,
        delay: (duration) async {
          now = now.add(duration);
        },
      );

      await runner.run(
        const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 1),
          sourceMetadata: StreamTestSourceMetadata(
            sourceType: 'display',
            sourceIdHash: 'abc',
          ),
          windowsCaptureBackendMode:
              WindowsScreenCaptureBackendMode.directxOnly,
          windowsWindowGdiCaptureModes: [
            WindowsWindowGdiCaptureMode.defaultMode,
            WindowsWindowGdiCaptureMode.bitBltOnly,
          ],
        ),
      );

      expect(target.startedWindowGdiModes, [null]);
    });

    test('passes latest-frame pacer flag through stream-test runs', () async {
      var now = DateTime.utc(2026, 5, 28, 12);
      final progressLabels = <String>[];
      final target = _FakeStreamTestTarget(
        snapshot: _snapshot(
          width: 1280,
          height: 720,
          fps: 30,
          bitrateBps: 1800000,
          lossPercent: 0,
          rttMs: 20,
        ),
      );
      final runner = StreamTestRunner(
        target: target,
        clock: () => now,
        delay: (duration) async {
          now = now.add(duration);
        },
        onProgress: (progress) => progressLabels.add(progress.label),
      );

      final result = await runner.run(
        const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 1),
          nativeFramePacingEnabled: true,
        ),
      );

      expect(target.startedNativePacers, [true]);
      expect(
        progressLabels.single,
        '1/1 Smooth - App default + latest-frame pacer',
      );
      expect(result.toJsonText(), contains('"nativeFramePacingEnabled": true'));
      expect(
        result.toMarkdown(),
        contains('Native latest-frame pacer: enabled'),
      );
    });

    test('waits for warmup before sampling stream-test metrics', () async {
      var now = DateTime.utc(2026, 5, 28, 17);
      final runner = StreamTestRunner(
        target: _FakeStreamTestTarget(
          snapshot: _snapshot(
            width: 1280,
            height: 720,
            fps: 30,
            bitrateBps: 1800000,
            lossPercent: 0,
            rttMs: 20,
          ),
        ),
        clock: () => now,
        delay: (duration) async {
          now = now.add(duration);
        },
      );

      final result = await runner.run(
        const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 1),
          warmupDuration: Duration(seconds: 5),
        ),
      );

      final preset = result.presetResults.single;
      expect(preset.startedAt, DateTime.utc(2026, 5, 28, 17, 0, 5));
      expect(preset.samples.single.elapsed, const Duration(seconds: 1));
      expect(result.toJsonText(), contains('"warmupDurationMs": 5000'));
      expect(result.toMarkdown(), contains('Warmup before sampling: 5s'));
    });

    test('keeps native startup markers emitted during warmup', () async {
      var now = DateTime.utc(2026, 5, 28, 17);
      final runner = StreamTestRunner(
        target: _FakeStreamTestTarget(
          snapshot: _snapshot(
            width: 1280,
            height: 720,
            fps: 30,
            bitrateBps: 1800000,
            lossPercent: 0,
            rttMs: 20,
          ),
        ),
        clock: () => now,
        delay: (duration) async {
          now = now.add(duration);
        },
        diagnosticLogProvider: () async => '''
2026-05-28T17:00:01.000Z native-webrtc Inter Galactic desktop capture options type=window mode=directx-only dirty_region_mode=force-full-frame detect_updated_region=0 directx=1 crop_window=0 wgc_screen=0 wgc_window=0 wgc_fallback=0
2026-05-28T17:00:02.000Z native-webrtc Inter Galactic desktop capture pipeline native_source=1920x1080 requested_max=1280x720 pre_encode=1280x720 target_fps=30 native_fps=30 scale=down crop_region=false capturer=directx capturer_id=1229408334 dirty_region_mode=force-full-frame
''',
      );

      final result = await runner.run(
        const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 1),
          warmupDuration: Duration(seconds: 5),
          sampleInterval: Duration(seconds: 1),
        ),
      );

      final preset = result.presetResults.single;
      expect(preset.startedAt, DateTime.utc(2026, 5, 28, 17, 0, 5));
      expect(preset.diagnosticStartedAt, DateTime.utc(2026, 5, 28, 17));
      expect(preset.nativeDiagnostics.backendLabel, 'directx-only');
      expect(preset.nativeDiagnostics.observedCapturerLabel, 'directx');
      expect(preset.nativeDiagnostics.dirtyRegionModeLabel, 'force-full-frame');
      expect(preset.nativeDiagnostics.preEncodeResolutionLabel, '1280x720');
    });

    test('expands backend comparison against each selected preset', () async {
      var now = DateTime.utc(2026, 5, 19, 20);
      final target = _FakeStreamTestTarget(
        snapshot: _snapshot(
          width: 1280,
          height: 720,
          fps: 30,
          bitrateBps: 1800000,
          lossPercent: 0,
          rttMs: 20,
        ),
      );
      final runner = StreamTestRunner(
        target: target,
        clock: () => now,
        delay: (duration) async {
          now = now.add(duration);
        },
      );

      final result = await runner.run(
        const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 1),
          windowsCaptureBackendModes: [
            null,
            WindowsScreenCaptureBackendMode.wgcOnly,
            WindowsScreenCaptureBackendMode.directxOnly,
          ],
        ),
      );

      expect(target.startedProfiles, ['Smooth', 'Smooth', 'Smooth']);
      expect(target.startedBackends, [
        null,
        WindowsScreenCaptureBackendMode.wgcOnly,
        WindowsScreenCaptureBackendMode.directxOnly,
      ]);
      expect(result.presetResults, hasLength(3));
      expect(result.presetResults.first.backendSelectionLabel, 'App default');
      expect(result.presetResults[1].backendSelectionLabel, 'WGC only');
      expect(result.toJsonText(), contains('"windowsCaptureBackendModes"'));
      expect(
        result.toMarkdown(),
        contains(
          'Windows capture backend: App default, WGC only, DirectX / Window GDI only',
        ),
      );
    });

    test('filters unsafe window crop backend from stream-test runs', () async {
      var now = DateTime.utc(2026, 5, 28, 12);
      final target = _FakeStreamTestTarget(
        snapshot: _snapshot(
          width: 1280,
          height: 720,
          fps: 30,
          bitrateBps: 1800000,
          lossPercent: 0,
          rttMs: 20,
        ),
      );
      final runner = StreamTestRunner(
        target: target,
        clock: () => now,
        delay: (duration) async {
          now = now.add(duration);
        },
      );

      final result = await runner.run(
        const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 1),
          windowsCaptureBackendModes: [
            WindowsScreenCaptureBackendMode.windowCrop,
            WindowsScreenCaptureBackendMode.directxOnly,
          ],
        ),
      );

      expect(target.startedBackends, [
        WindowsScreenCaptureBackendMode.directxOnly,
      ]);
      expect(result.config.effectiveWindowsBackendModes, [
        WindowsScreenCaptureBackendMode.directxOnly,
      ]);
      expect(result.toMarkdown(), contains('DirectX / Window GDI only'));
      expect(result.toMarkdown(), isNot(contains('Window crop fallback')));
    });

    test('reports current preset and backend progress', () async {
      var now = DateTime.utc(2026, 5, 27, 21);
      final progressLabels = <String>[];
      final target = _FakeStreamTestTarget(
        snapshot: _snapshot(
          width: 1280,
          height: 720,
          fps: 30,
          bitrateBps: 1800000,
          lossPercent: 0,
          rttMs: 20,
        ),
      );
      final runner = StreamTestRunner(
        target: target,
        clock: () => now,
        delay: (duration) async {
          now = now.add(duration);
        },
        onProgress: (progress) => progressLabels.add(progress.detailLabel),
      );

      await runner.run(
        const StreamTestRunConfig(
          presets: [
            ScreenShareProfileConfig.smooth,
            ScreenShareProfileConfig.balanced,
          ],
          durationPerPreset: Duration(seconds: 1),
          windowsCaptureBackendModes: [
            null,
            WindowsScreenCaptureBackendMode.wgcOnly,
          ],
        ),
      );

      expect(progressLabels, [
        '1/4 Smooth - App default (1s + 5s warmup, 1280x720@30fps_target/36fps_cap)',
        '2/4 Smooth - WGC only (1s + 5s warmup, 1280x720@30fps_target/36fps_cap)',
        '3/4 Balanced - App default (1s + 5s warmup, 1920x1080@30fps_target/36fps_cap)',
        '4/4 Balanced - WGC only (1s + 5s warmup, 1920x1080@30fps_target/36fps_cap)',
      ]);
    });

    test('scores stable target-quality stream highly', () {
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: DateTime.utc(2026, 5, 18, 18),
        endedAt: DateTime.utc(2026, 5, 18, 18, 0, 3),
        samples: [
          StreamTestSample(
            elapsed: const Duration(seconds: 1),
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 30,
              bitrateBps: 1800000,
              lossPercent: 0.1,
              rttMs: 35,
            ),
          ),
          StreamTestSample(
            elapsed: const Duration(seconds: 2),
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 29,
              bitrateBps: 1750000,
              lossPercent: 0,
              rttMs: 42,
            ),
          ),
        ],
      );

      expect(result.score.stableFps, 25);
      expect(result.score.targetResolution, 25);
      expect(result.score.lowLoss, 25);
      expect(result.score.lowRtt, 15);
      expect(result.score.downgradePenalty, 0);
      expect(result.score.totalScore, 90);
    });

    test('flags game-hook source frame order instability', () {
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: DateTime.utc(2026, 6, 5, 19),
        endedAt: DateTime.utc(2026, 6, 5, 19, 1),
        nativeDiagnostics: const StreamTestNativeDiagnostics(
          observedCapturer: 'game-d3d11-hook',
          gameCaptureSourceWidth: 2560,
          gameCaptureSourceHeight: 1440,
          gameCaptureOutputWidth: 1280,
          gameCaptureOutputHeight: 720,
          averageGameCaptureFps: 34.0,
          gameCaptureSubmittedFrames: 2040,
          gameCaptureGpuScaledFrames: 2040,
          gameCaptureGpuScaleFailures: 0,
          gameCaptureCpuFallbackFrames: 0,
          gameCaptureSourceFrameIndex: 2400,
          gameCaptureLastSubmittedSourceFrameIndex: 2399,
          gameCaptureSourceFrameRegressions: 2,
          gameCaptureSharedSlotMismatches: 3,
          averageGameCaptureReadbackLatencyFrames: 5.8,
          gameCaptureMaxReadbackLatencyFrames: 7,
        ),
        samples: [
          StreamTestSample(
            elapsed: const Duration(seconds: 1),
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 34,
              captureFps: 34,
              encodeFps: 34,
              sendFps: 34,
              bitrateBps: 2900000,
              lossPercent: 0,
              rttMs: 5,
            ),
          ),
        ],
      );

      expect(result.score.bottleneck.label, 'source_frame_order_unstable');
      expect(result.score.bottleneck.confidence, 'high');
      expect(
        result.score.bottleneck.reasons.join(' '),
        contains('source frame index regressed 2 times'),
      );
      expect(
        result.score.bottleneck.reasons.join(' '),
        contains('shared slot frame index mismatched latest frame 3 times'),
      );
      expect(
        result.score.bottleneck.recommendedNextAction,
        'fix game-capture handoff',
      );
      expect(
        result.diagnosticCoverage.toMarkdownTable(),
        contains('game-capture frame order'),
      );
    });

    test('flags stale game-hook readback latency before healthy scoring', () {
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: DateTime.utc(2026, 6, 5, 23),
        endedAt: DateTime.utc(2026, 6, 5, 23, 1),
        nativeDiagnostics: const StreamTestNativeDiagnostics(
          observedCapturer: 'game-d3d11-hook',
          gameCaptureSourceWidth: 2560,
          gameCaptureSourceHeight: 1440,
          gameCaptureOutputWidth: 1280,
          gameCaptureOutputHeight: 720,
          averageGameCaptureFps: 36.0,
          gameCaptureSubmittedFrames: 1259,
          gameCaptureGpuScaledFrames: 1259,
          gameCaptureGpuScaleFailures: 0,
          gameCaptureCpuFallbackFrames: 0,
          gameCaptureSourceFrameIndex: 1865,
          gameCaptureLastSubmittedSourceFrameIndex: 1859,
          gameCaptureSourceFrameRegressions: 0,
          gameCaptureSharedSlotMismatches: 0,
          averageGameCaptureReadbackLatencyFrames: 5.0,
          gameCaptureMaxReadbackLatencyFrames: 7,
          gameCaptureReadbackLatencyDroppedFrames: 42,
        ),
        samples: [
          StreamTestSample(
            elapsed: const Duration(seconds: 1),
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 36,
              captureFps: 36,
              encodeFps: 36,
              sendFps: 36,
              bitrateBps: 3200000,
              lossPercent: 0,
              rttMs: 2,
            ),
          ),
        ],
      );

      expect(result.score.bottleneck.label, 'frame_pacing_unstable');
      expect(result.score.bottleneck.confidence, 'high');
      expect(
        result.score.bottleneck.reasons.join(' '),
        contains('game-capture readback averages 5.0 queued frames'),
      );
      expect(
        result.score.bottleneck.reasons.join(' '),
        contains('dropped 42 stale readbacks'),
      );
      expect(result.score.bottleneck.recommendedNextAction, 'fix frame pacing');
    });

    test('does not over-classify protective readback drops alone', () {
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: DateTime.utc(2026, 6, 5, 23),
        endedAt: DateTime.utc(2026, 6, 5, 23, 1),
        nativeDiagnostics: const StreamTestNativeDiagnostics(
          observedCapturer: 'game-d3d11-hook',
          gameCaptureSourceWidth: 2560,
          gameCaptureSourceHeight: 1440,
          gameCaptureOutputWidth: 1280,
          gameCaptureOutputHeight: 720,
          averageGameCaptureFps: 30.0,
          gameCaptureSubmittedFrames: 900,
          gameCaptureGpuScaledFrames: 900,
          gameCaptureGpuScaleFailures: 0,
          gameCaptureCpuFallbackFrames: 0,
          gameCaptureReadbackQueuedFrames: 1000,
          gameCaptureReadbackLatencyDroppedFrames: 1,
          averageGameCaptureReadbackLatencyFrames: 1.4,
          gameCaptureMaxReadbackLatencyFrames: 2,
          gameCaptureSourceFrameRegressions: 0,
          gameCaptureSharedSlotMismatches: 0,
        ),
        samples: [
          StreamTestSample(
            elapsed: const Duration(seconds: 1),
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 30,
              captureFps: 30,
              encodeFps: 30,
              sendFps: 30,
              bitrateBps: 3000000,
              lossPercent: 0,
              rttMs: 2,
            ),
          ),
        ],
      );

      expect(result.score.bottleneck.label, 'healthy');
      expect(
        result.score.bottleneck.reasons.join(' '),
        isNot(contains('stale readbacks')),
      );
    });

    test('does not treat D3D11 readback polling alone as pressure', () {
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: DateTime.utc(2026, 6, 7, 18),
        endedAt: DateTime.utc(2026, 6, 7, 18, 1),
        nativeDiagnostics: const StreamTestNativeDiagnostics(
          observedCapturer: 'game-d3d11-hook',
          gameCaptureSourceWidth: 2560,
          gameCaptureSourceHeight: 1440,
          gameCaptureOutputWidth: 1280,
          gameCaptureOutputHeight: 720,
          averageGameCaptureFps: 30.0,
          gameCaptureCopiedFrames: 1058,
          gameCaptureSubmittedFrames: 1057,
          gameCaptureGpuScaledFrames: 1057,
          gameCaptureGpuScaleFailures: 0,
          gameCaptureCpuFallbackFrames: 0,
          gameCaptureReadbackQueuedFrames: 1058,
          gameCaptureReadbackReadyFrames: 1057,
          gameCaptureReadbackNotReadyFrames: 3494,
          gameCaptureReadbackLatencyDroppedFrames: 0,
          averageGameCaptureReadbackLatencyFrames: 0.1,
          gameCaptureMaxReadbackLatencyFrames: 2,
          gameCaptureSourceFrameRegressions: 0,
          gameCaptureSharedSlotMismatches: 0,
        ),
        samples: [
          StreamTestSample(
            elapsed: const Duration(seconds: 1),
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 30,
              captureFps: 30,
              encodeFps: 30,
              sendFps: 30,
              bitrateBps: 3000000,
              lossPercent: 0,
              rttMs: 2,
            ),
          ),
        ],
      );

      expect(result.score.bottleneck.label, 'healthy');
      expect(result.score.temporalAnalysis.lateDegradationSignals, isEmpty);
    });

    test('does not treat isolated D3D11 readback queue spikes as pressure', () {
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.balanced,
        startedAt: DateTime.utc(2026, 6, 7, 18),
        endedAt: DateTime.utc(2026, 6, 7, 18, 1),
        nativeDiagnostics: const StreamTestNativeDiagnostics(
          observedCapturer: 'game-d3d11-hook',
          gameCaptureSourceWidth: 2560,
          gameCaptureSourceHeight: 1440,
          gameCaptureOutputWidth: 1600,
          gameCaptureOutputHeight: 900,
          averageGameCaptureFps: 30.0,
          gameCaptureCopiedFrames: 908,
          gameCaptureSubmittedFrames: 903,
          gameCaptureGpuScaledFrames: 903,
          gameCaptureGpuScaleFailures: 0,
          gameCaptureCpuFallbackFrames: 0,
          gameCaptureReadbackQueuedFrames: 908,
          gameCaptureReadbackReadyFrames: 903,
          gameCaptureReadbackNotReadyFrames: 4682,
          gameCaptureReadbackLatencyDroppedFrames: 0,
          averageGameCaptureReadbackLatencyFrames: 1.4,
          gameCaptureMaxReadbackLatencyFrames: 8,
          gameCaptureSourceFrameRegressions: 0,
          gameCaptureSharedSlotMismatches: 0,
        ),
        samples: [
          StreamTestSample(
            elapsed: const Duration(seconds: 1),
            snapshot: _snapshot(
              width: 1600,
              height: 900,
              fps: 30,
              captureFps: 30,
              encodeFps: 30,
              sendFps: 30,
              bitrateBps: 3500000,
              lossPercent: 0,
              rttMs: 2,
              requestedWidth: 1920,
              requestedHeight: 1080,
            ),
          ),
        ],
      );

      expect(result.score.bottleneck.label, 'healthy');
      expect(
        result.score.bottleneck.reasons.join(' '),
        isNot(contains('readback peaked')),
      );
    });

    test('rejects fast window-GDI modes that produce black frames', () {
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: DateTime.utc(2026, 6, 3, 20, 8),
        endedAt: DateTime.utc(2026, 6, 3, 20, 9),
        nativeDiagnostics: StreamTestNativeDiagnostics.fromMarkers(const [
          '2026-06-03T20:08:40.000Z native-webrtc Inter Galactic desktop capture pipeline native_source=2560x1440 native_window_rect=2560x1440 requested_max=1280x720 content=1280x720 pre_encode=1280x720 target_fps=30 native_fps=24 scale=down canvas=fixed crop_region=false capturer=window-gdi capturer_id=3 dirty_region_mode=auto',
          '2026-06-03T20:08:40.100Z native-webrtc Inter Galactic desktop capture cadence target_delay_ms=33 avg_capture_call_ms=40 max_capture_call_ms=120 scheduled_delay_ms=0 calls=50 submitted_fps=24 temp_errors=0 permanent_errors=0 avg_source_capture_ms=35 max_source_capture_ms=110 source_capture_count=50 avg_callback_entry_delay_ms=35 max_callback_entry_delay_ms=110 avg_result_callback_ms=4 max_result_callback_ms=9 avg_acquire_wait_ms=36 max_acquire_wait_ms=112 avg_post_callback_wait_ms=1 max_post_callback_wait_ms=8 avg_unaccounted_wait_ms=0 max_unaccounted_wait_ms=1 callback_count=50',
          '2026-06-03T20:08:40.200Z native-webrtc Inter Galactic window GDI frame timing source_type=window source_id=123 capture_mode=bitblt-only calls=50 successes=50 temp_errors=0 permanent_errors=0 hidden_or_minimized=0 rect_fail=0 dc_fail=0 frame_create_fail=0 original_size=2560x1440 cropped_size=2560x1440 frame_size=2560x1440 print_full_calls=0 print_full_successes=0 print_fallback_calls=0 print_fallback_successes=0 bitblt_calls=50 bitblt_successes=50 final_print_full=0 final_print_fallback=0 final_bitblt=50 final_none=0 black_frame_count=50 low_variance_frame_count=50 owned_window_frames=0 owned_capture_calls=0 owned_capture_successes=0 avg_total_ms=25 max_total_ms=100 avg_rect_ms=0.2 max_rect_ms=1 avg_visibility_ms=0.1 max_visibility_ms=1 avg_get_dc_ms=0.1 max_get_dc_ms=1 avg_get_dc_size_ms=0.1 max_get_dc_size_ms=1 avg_create_frame_ms=0.2 max_create_frame_ms=1 avg_mem_dc_ms=0.1 max_mem_dc_ms=1 avg_print_full_ms=0 max_print_full_ms=0 avg_print_fallback_ms=0 max_print_fallback_ms=0 avg_bitblt_ms=22 max_bitblt_ms=95 avg_cleanup_ms=0.1 max_cleanup_ms=1 avg_crop_ms=0 max_crop_ms=0 avg_owned_enum_ms=1 max_owned_enum_ms=3 avg_owned_capture_ms=0 max_owned_capture_ms=0 avg_owned_composite_ms=0 max_owned_composite_ms=0',
        ]),
        samples: [
          StreamTestSample(
            elapsed: const Duration(seconds: 1),
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 24,
              captureFps: 24,
              encodeFps: 24,
              sendFps: 24,
              bitrateBps: 13000,
              lossPercent: 0,
              rttMs: 3,
            ),
          ),
        ],
      );

      expect(result.score.bottleneck.label, 'invalid_capture_output');
      expect(result.score.bottleneck.confidence, 'high');
      expect(
        result.score.bottleneck.recommendedNextAction,
        'fix window-GDI substage',
      );
      expect(result.score.stableFps, 0);
      expect(result.score.targetResolution, 0);
      expect(result.score.lowLoss, 25);
      expect(result.score.lowRtt, 15);
      expect(result.score.downgradePenalty, 30);
      expect(result.score.totalScore, 10);
      expect(result.nativeDiagnostics.gdiOutputProbablyInvalid, isTrue);
      expect(
        result.nativeDiagnostics.gdiOutputValidityLabel,
        contains('invalid_black_low_variance'),
      );
      expect(
        result.nativeDiagnostics.toJson(),
        containsPair('gdiOutputProbablyInvalid', true),
      );
      expect(
        result.diagnosticCoverage.toMarkdownTable(),
        contains('capture output validity'),
      );
      final run = StreamTestRunResult(
        startedAt: DateTime.utc(2026, 6, 3, 20, 8),
        endedAt: DateTime.utc(2026, 6, 3, 20, 9),
        targetLabel: 'Test room',
        roomId: '!test:ourgalaxy.space',
        config: const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 1),
        ),
        presetResults: [result],
      );
      expect(
        run.toMarkdown(),
        contains('Capture output validity: invalid_black_low_variance'),
      );
    });

    test('labels encoded frames above requested cap distinctly', () {
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: DateTime.utc(2026, 5, 19, 20),
        endedAt: DateTime.utc(2026, 5, 19, 20, 0, 3),
        samples: [
          StreamTestSample(
            elapsed: const Duration(seconds: 1),
            snapshot: _snapshot(
              width: 1920,
              height: 1080,
              fps: 16,
              captureFps: 16,
              encodeFps: 16,
              sendFps: 16,
              averageEncodeTimeMs: 65,
              bitrateBps: 4200000,
              lossPercent: 0,
              rttMs: 3,
            ),
          ),
        ],
      );

      expect(result.score.bottleneck.label, 'resolution_limit_not_applied');
      expect(
        result.score.bottleneck.reasons.join(' '),
        contains('requested 1280x720@30.0fps but encoded 1920x1080'),
      );
    });

    test('penalizes low layer and WebRTC downgrade evidence', () {
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: DateTime.utc(2026, 5, 18, 18),
        endedAt: DateTime.utc(2026, 5, 18, 18, 0, 3),
        samples: [
          StreamTestSample(
            elapsed: const Duration(seconds: 1),
            snapshot: _snapshot(
              width: 426,
              height: 240,
              fps: 9,
              bitrateBps: 350000,
              lossPercent: 4,
              rttMs: 320,
              activeLayer: 'q',
              qualityLimitationReason: 'cpu',
            ),
          ),
        ],
      );

      expect(result.score.stableFps, 8);
      expect(result.score.targetResolution, 4);
      expect(result.score.lowLoss, 0);
      expect(result.score.lowRtt, 0);
      expect(result.score.downgradePenalty, 30);
      expect(result.score.totalScore, lessThan(0));
    });

    test('exports structured JSON and markdown summary', () {
      final run = StreamTestRunResult(
        startedAt: DateTime.utc(2026, 5, 18, 18),
        endedAt: DateTime.utc(2026, 5, 18, 18, 0, 2),
        targetLabel: 'Test room',
        roomId: '!test:ourgalaxy.space',
        config: const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 2),
        ),
        presetResults: [
          StreamTestPresetResult(
            profile: ScreenShareProfileConfig.smooth,
            startedAt: DateTime.utc(2026, 5, 18, 18),
            endedAt: DateTime.utc(2026, 5, 18, 18, 0, 2),
            samples: [
              StreamTestSample(
                elapsed: const Duration(seconds: 1),
                snapshot: _snapshot(
                  width: 1280,
                  height: 720,
                  fps: 30,
                  bitrateBps: 1800000,
                  lossPercent: 0,
                  rttMs: 40,
                ),
              ),
            ],
          ),
        ],
      );

      final json = run.toJson();
      expect(json['schema'], 'intergalactic.streamTestRun.v1');
      expect(json['presetResults'], isA<List>());
      expect(run.toJsonText(), contains('"stable_fps"'));
      expect(
        run.toMarkdown(),
        contains(
          '| Smooth | App default | Default window GDI | unknown | healthy | 90 |',
        ),
      );
      expect(run.toMarkdown(), contains('stable_fps + target_resolution'));
    });

    test('exports failure report with redacted diagnostic marker tail', () {
      final run = StreamTestRunResult.failure(
        startedAt: DateTime.utc(2026, 6, 10, 18),
        endedAt: DateTime.utc(2026, 6, 10, 18, 0, 1),
        targetLabel: 'Private room',
        roomId: '!private:ourgalaxy.space',
        config: const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 30),
          warmupDuration: Duration(seconds: 5),
          windowsCaptureBackendMode:
              WindowsScreenCaptureBackendMode.gameD3d11HookExperimental,
        ),
        error: 'TimeoutException: stream-test runner batch timed out',
        diagnosticLogText: '''
ordinary unrelated line
2026-06-10T18:00:00.100Z native-webrtc game_capture_webrtc_source stats source=2560x1440 output=1280x720 format=24 submitted=1055 repeated=163 readbackNotReady=3847 path="repo-fixtures/proof.bmp" source_title="Private Game" pid=42
2026-06-10T18:00:00.200Z native-webrtc Inter Galactic Media Foundation H.264 encoder timing frame=9 total_ms=2.4 slow=no
''',
      );

      expect(run.error, contains('TimeoutException'));
      expect(run.presetResults, isEmpty);
      expect(run.diagnosticLogMarkers, hasLength(2));
      expect(run.toJsonText(), contains('"error": "TimeoutException'));
      expect(run.toJsonText(), contains('game_capture_webrtc_source stats'));
      expect(run.toJsonText(), isNot(contains('Private Game')));
      expect(run.toJsonText(), isNot(contains('source_title')));
      expect(run.toJsonText(), isNot(contains('pid=42')));
      expect(run.toJsonText(), isNot(contains('repo-fixtures/proof.bmp')));
      expect(run.toMarkdown(), contains('- Run status: failed'));
      expect(run.toMarkdown(), contains('- Run error: TimeoutException'));
      expect(run.toMarkdown(), contains('Media Foundation H.264 encoder'));
      expect(run.toMarkdown(), isNot(contains('Private Game')));
      expect(run.toMarkdown(), isNot(contains('pid=42')));
      expect(run.toMarkdown(), isNot(contains('repo-fixtures/proof.bmp')));
    });

    test('parses D3D11 game-capture metadata into JSON and Markdown', () {
      final probe = GameCaptureProbeResult.fromMetadata(
        config: const GameCaptureProbeConfig(
          enabled: true,
          maxSavedFrames: 0,
          sourceMetadata: StreamTestSourceMetadata(
            sourceType: 'window',
            sourceIdHash: 'abc12345',
            processId: 1234,
          ),
        ),
        resultDirectoryPath: r'runtime\game-capture-poc\results\x',
        helperPath: r'tools\game-capture\helper.exe',
        helperExitCode: 0,
        metadata: const {
          'schema': 'intergalactic.gameCapturePoc.v1',
          'requestedBackend': 'd3d11-present-hook',
          'attachStatus': 'attached',
          'detectedGraphicsApi': 'd3d11',
          'presentFrameCount': 902,
          'presentFps': 30.001,
          'presentGapP50Ms': 33.317,
          'presentGapP95Ms': 34.191,
          'presentGapMaxMs': 35.177,
          'backbufferWidth': 2560,
          'backbufferHeight': 1440,
          'backbufferFormat': 'R10G10B10A2_UNORM',
          'sharedTextureRingDepth': 3,
          'sharedTextureSupported': true,
          'copyAvgMs': 0.001,
          'copyMaxMs': 0.002,
          'resolveAvgMs': 0.0,
          'resolveMaxMs': 0.0,
          'copiedFrames': 902,
          'droppedFrames': 0,
          'overwrittenFrames': 899,
          'cpuReadbackCount': 0,
          'savedFrames': 0,
          'visibleFrames': 0,
          'hostConsumer': {
            'enabled': true,
            'sharedStateAvailable': true,
            'd3dDeviceCreated': true,
            'openedSharedTexture': true,
            'openedTextureSlots': 3,
            'sharedTextureOpenFailures': 0,
            'observedFrameSignals': 900,
            'consumedFrames': 900,
            'duplicateSignals': 0,
            'missedFrames': 2,
            'invalidStateReads': 0,
            'frameAgeAvgMs': 2.0,
            'frameAgeP95Ms': 5.0,
            'frameAgeMaxMs': 9.0,
            'consumerGapP50Ms': 33.3,
            'consumerGapP95Ms': 34.2,
            'consumerGapMaxMs': 35.2,
            'proofReadbackCount': 0,
            'visibleProofFrames': 0,
            'lastError': 'none',
          },
          'publicationHandoff': {
            'enabled': true,
            'mode': 'cpu_readback_scaled_bgra',
            'scaleMode': 'contain_fit_cpu_after_readback',
            'sharedStateAvailable': true,
            'd3dDeviceCreated': true,
            'openedSharedTexture': true,
            'openedTextureSlots': 3,
            'sharedTextureOpenFailures': 0,
            'unsupportedFormat': false,
            'requestedMaxWidth': 1280,
            'requestedMaxHeight': 720,
            'requestedTargetFps': 30,
            'sourceWidth': 2560,
            'sourceHeight': 1440,
            'outputWidth': 1280,
            'outputHeight': 720,
            'observedFrameSignals': 900,
            'inputFramesSeen': 900,
            'duplicateSignals': 0,
            'missedInputFrames': 2,
            'pacedDropFrames': 450,
            'readbackFrames': 450,
            'outputFrames': 450,
            'visibleOutputFrames': 450,
            'invalidStateReads': 0,
            'frameAgeAvgMs': 2.0,
            'frameAgeP95Ms': 5.0,
            'frameAgeMaxMs': 9.0,
            'outputFps': 30.0,
            'outputGapP50Ms': 33.3,
            'outputGapP95Ms': 34.2,
            'outputGapMaxMs': 35.2,
            'readbackAvgMs': 1.2,
            'readbackP95Ms': 1.8,
            'readbackMaxMs': 2.0,
            'scaleAvgMs': 2.5,
            'scaleP95Ms': 3.8,
            'scaleMaxMs': 4.0,
            'totalFrameAvgMs': 3.7,
            'totalFrameP95Ms': 5.5,
            'totalFrameMaxMs': 6.0,
            'lastError': 'none',
          },
          'fallbackReason': 'none',
          'hookStopReason': 'duration_elapsed',
          'lastError': 'none',
        },
      );

      expect(probe.status, StreamDiagnosticCoverageStatus.available);
      expect(probe.isHealthyCadence, isTrue);
      expect(probe.hasHealthyHostTextureConsumer, isTrue);
      expect(probe.hasHealthyPublicationHandoff, isTrue);
      expect(probe.summaryLabel, contains('present=30.0fps'));
      expect(probe.summaryLabel, contains('hostConsumer=healthy/900frames'));
      expect(probe.summaryLabel, contains('handoff=healthy/30.0fps'));
      expect(probe.toJson()['healthyPresentCadence'], isTrue);
      expect(
        (probe.toJson()['hostTextureConsumer']
            as Map<String, Object?>)['healthy'],
        isTrue,
      );
      expect(
        (probe.toJson()['publicationHandoff']
            as Map<String, Object?>)['healthy'],
        isTrue,
      );
      expect(probe.toMarkdown(), contains('Detected graphics API: d3d11'));
      expect(probe.toMarkdown(), contains('Host texture consumer'));
      expect(probe.toMarkdown(), contains('Publication handoff'));
      expect(probe.toMarkdown(), contains('Frames copied/dropped/overwritten'));
      expect(
        probe.toJson().toString(),
        isNot(contains(r'runtime\game-capture-poc')),
      );
      expect(
        probe.toJson().toString(),
        isNot(contains(r'tools\game-capture\helper.exe')),
      );
      expect(probe.toMarkdown(), isNot(contains(r'runtime\game-capture-poc')));
      expect(
        probe.toMarkdown(),
        isNot(contains(r'tools\game-capture\helper.exe')),
      );
    });

    test('adds deterministic capture target diagnostics to reports', () {
      const targetConfig = GameCaptureTestTargetConfig(
        enabled: true,
        width: 1920,
        height: 1080,
        windowMode: 'windowed',
        scene: 'gameplay',
        fps: '60',
        title: 'Inter Galactic Capture Target',
      );
      final targetResult =
          GameCaptureTestTargetResult.launched(
            config: targetConfig,
            processId: 1234,
            executablePath: r'tools\InterGalacticCaptureTarget.exe',
            outputDirectoryPath: r'runtime\capture-targets\x',
          ).withSelection(automatic: true).withDiagnostics(const {
            'presentFps': 59.9,
            'presentGapP95Ms': 17.2,
            'presentGapMaxMs': 24.8,
            'framesPresented': 1800,
          }, status: 'stopped');
      final run = StreamTestRunResult(
        startedAt: DateTime.utc(2026, 6, 4, 18),
        endedAt: DateTime.utc(2026, 6, 4, 18, 0, 30),
        targetLabel: 'room',
        roomId: '!room:example.org',
        config: const StreamTestRunConfig(
          presets: [],
          gameCaptureTestTarget: targetConfig,
        ),
        presetResults: const [],
        gameCaptureTestTargetResult: targetResult,
      );

      final json = run.toJson();
      expect(json['schema'], 'intergalactic.streamTestRun.v1');
      expect(json['gameCaptureTestTarget'].toString(), contains('59.9'));
      expect(
        json['gameCaptureTestTarget'].toString(),
        isNot(contains(r'tools\InterGalacticCaptureTarget.exe')),
      );
      expect(
        json['gameCaptureTestTarget'].toString(),
        isNot(contains(r'runtime\capture-targets')),
      );
      expect(
        json['gameCaptureTestTarget'].toString(),
        isNot(contains('processId: 1234')),
      );
      expect(run.toMarkdown(), contains('## Game Capture Test Target'));
      expect(run.toMarkdown(), contains('Present FPS'));
      expect(run.toMarkdown(), contains('Output directory: configured'));
      expect(
        run.toMarkdown(),
        isNot(contains(r'tools\InterGalacticCaptureTarget.exe')),
      );
      expect(run.toMarkdown(), isNot(contains(r'runtime\capture-targets')));
      expect(
        run.diagnosticCoverage.toMarkdownTable(),
        contains('game-capture test target'),
      );
      expect(run.diagnosticCoverage.toMarkdownTable(), contains('available'));
    });

    test('visible game-capture handoff below target cadence is slow', () {
      final probe = GameCaptureProbeResult.fromMetadata(
        config: const GameCaptureProbeConfig(
          enabled: true,
          maxSavedFrames: 0,
          sourceMetadata: StreamTestSourceMetadata(
            sourceType: 'window',
            sourceIdHash: 'abc12345',
            processId: 1234,
          ),
        ),
        metadata: const {
          'schema': 'intergalactic.gameCapturePoc.v1',
          'requestedBackend': 'd3d11-present-hook',
          'attachStatus': 'attached',
          'detectedGraphicsApi': 'd3d11',
          'presentFrameCount': 1341,
          'presentFps': 44.7,
          'presentGapP50Ms': 21.4,
          'presentGapP95Ms': 31.0,
          'presentGapMaxMs': 105.4,
          'backbufferWidth': 2560,
          'backbufferHeight': 1440,
          'backbufferFormat': 'R10G10B10A2_UNORM',
          'sharedTextureRingDepth': 3,
          'sharedTextureSupported': true,
          'copyAvgMs': 0.001,
          'copyMaxMs': 0.059,
          'resolveAvgMs': 0.0,
          'resolveMaxMs': 0.0,
          'copiedFrames': 1341,
          'droppedFrames': 0,
          'overwrittenFrames': 1338,
          'cpuReadbackCount': 0,
          'savedFrames': 0,
          'visibleFrames': 0,
          'hostConsumer': {
            'enabled': true,
            'sharedStateAvailable': true,
            'd3dDeviceCreated': true,
            'openedSharedTexture': true,
            'openedTextureSlots': 3,
            'sharedTextureOpenFailures': 0,
            'observedFrameSignals': 1104,
            'consumedFrames': 1103,
            'duplicateSignals': 1,
            'missedFrames': 205,
            'invalidStateReads': 0,
            'frameAgeAvgMs': 4.8,
            'frameAgeP95Ms': 19.2,
            'frameAgeMaxMs': 38.6,
            'consumerGapP50Ms': 21.7,
            'consumerGapP95Ms': 32.1,
            'consumerGapMaxMs': 105.4,
            'proofReadbackCount': 0,
            'visibleProofFrames': 0,
            'lastError': 'none',
          },
          'publicationHandoff': {
            'enabled': true,
            'mode': 'cpu_readback_scaled_bgra',
            'scaleMode': 'contain_fit_cpu_after_readback',
            'sharedStateAvailable': true,
            'd3dDeviceCreated': true,
            'openedSharedTexture': true,
            'openedTextureSlots': 3,
            'sharedTextureOpenFailures': 0,
            'unsupportedFormat': false,
            'requestedMaxWidth': 1280,
            'requestedMaxHeight': 720,
            'requestedTargetFps': 30,
            'sourceWidth': 2560,
            'sourceHeight': 1440,
            'outputWidth': 1280,
            'outputHeight': 720,
            'observedFrameSignals': 1104,
            'inputFramesSeen': 1103,
            'duplicateSignals': 1,
            'missedInputFrames': 205,
            'pacedDropFrames': 789,
            'readbackFrames': 314,
            'outputFrames': 314,
            'visibleOutputFrames': 314,
            'invalidStateReads': 0,
            'frameAgeAvgMs': 4.8,
            'frameAgeP95Ms': 19.2,
            'frameAgeMaxMs': 38.6,
            'outputFps': 10.7,
            'outputGapP50Ms': 89.3,
            'outputGapP95Ms': 125.4,
            'outputGapMaxMs': 171.9,
            'readbackAvgMs': 22.8,
            'readbackP95Ms': 53.7,
            'readbackMaxMs': 107.2,
            'scaleAvgMs': 25.5,
            'scaleP95Ms': 26.3,
            'scaleMaxMs': 28.6,
            'totalFrameAvgMs': 48.4,
            'totalFrameP95Ms': 79.3,
            'totalFrameMaxMs': 134.4,
            'lastError': 'none',
          },
          'fallbackReason': 'none',
          'hookStopReason': 'duration_elapsed',
          'lastError': 'none',
        },
      );

      expect(probe.isHealthyCadence, isTrue);
      expect(probe.hasVisiblePublicationHandoff, isTrue);
      expect(probe.hasHealthyPublicationHandoff, isFalse);
      expect(probe.hasSlowPublicationHandoff, isTrue);
      expect(probe.summaryLabel, contains('handoff=slow/10.7fps'));
      expect(
        (probe.toJson()['publicationHandoff']
            as Map<String, Object?>)['healthLabel'],
        'slow',
      );
      expect(
        probe.classificationEvidenceLabel,
        contains('publication handoff is below target cadence'),
      );
    });

    test('probe-only run does not publish to LiveKit target', () async {
      var now = DateTime.utc(2026, 6, 4, 1);
      final target = _FakeStreamTestTarget(
        snapshot: _snapshot(
          width: 1280,
          height: 720,
          fps: 30,
          bitrateBps: 1800000,
          lossPercent: 0,
          rttMs: 20,
        ),
      );
      final probeRunner = _FakeGameCaptureProbeRunner(
        resultFactory: (config) => GameCaptureProbeResult.fromMetadata(
          config: config,
          metadata: const {
            'schema': 'intergalactic.gameCapturePoc.v1',
            'requestedBackend': 'd3d11-present-hook',
            'attachStatus': 'attached',
            'detectedGraphicsApi': 'd3d11',
            'presentFps': 30.0,
            'presentGapP95Ms': 34.0,
            'presentGapMaxMs': 36.0,
            'droppedFrames': 0,
            'cpuReadbackCount': 0,
            'hostConsumer': {
              'enabled': true,
              'sharedStateAvailable': true,
              'd3dDeviceCreated': true,
              'openedSharedTexture': true,
              'openedTextureSlots': 3,
              'sharedTextureOpenFailures': 0,
              'observedFrameSignals': 30,
              'consumedFrames': 30,
              'duplicateSignals': 0,
              'missedFrames': 0,
              'invalidStateReads': 0,
              'frameAgeAvgMs': 1.0,
              'frameAgeP95Ms': 2.0,
              'frameAgeMaxMs': 3.0,
              'consumerGapP50Ms': 33.0,
              'consumerGapP95Ms': 34.0,
              'consumerGapMaxMs': 36.0,
              'proofReadbackCount': 0,
              'visibleProofFrames': 0,
              'lastError': 'none',
            },
            'fallbackReason': 'none',
          },
        ),
      );
      final progressLabels = <String>[];
      final runner = StreamTestRunner(
        target: target,
        gameCaptureProbeRunner: probeRunner,
        clock: () => now,
        delay: (duration) async {
          now = now.add(duration);
        },
        onProgress: (progress) => progressLabels.add(progress.detailLabel),
      );

      final result = await runner.run(
        const StreamTestRunConfig(
          presets: [],
          sourceMetadata: StreamTestSourceMetadata(
            sourceType: 'window',
            sourceIdHash: 'abc12345',
            processId: 4242,
          ),
          gameCaptureProbe: GameCaptureProbeConfig(enabled: true),
        ),
      );

      expect(target.startedProfiles, isEmpty);
      expect(target.stopCount, 0);
      expect(
        progressLabels.single,
        'D3D11 game probe (10s, local diagnostics only)',
      );
      expect(probeRunner.configs.single.effectiveTargetProcessId, 4242);
      expect(result.presetResults, isEmpty);
      expect(
        result.gameCaptureProbeResult?.status,
        StreamDiagnosticCoverageStatus.available,
      );
      expect(result.toJson()['schema'], 'intergalactic.streamTestRun.v1');
      expect(result.toJsonText(), contains('"gameCaptureProbe"'));
      expect(result.toMarkdown(), contains('## Game Capture Probe'));
      expect(result.toMarkdown(), contains('D3D11 Present hook'));
      expect(
        result.diagnosticCoverage.toMarkdownTable(),
        contains('game-capture probe'),
      );
    });

    test('game-capture probe runs concurrently with initial preset', () async {
      var now = DateTime.utc(2026, 6, 4, 2);
      final presetStarted = Completer<void>();
      final hostSampler = _FakeHostLoadSampler(
        report: StreamTestHostLoadReport.unavailable(reason: 'test'),
      );
      final target = _FakeStreamTestTarget(
        snapshot: _snapshot(
          width: 1280,
          height: 720,
          fps: 30,
          bitrateBps: 1800000,
          lossPercent: 0,
          rttMs: 20,
          framesCaptured: 0,
          framesEncoded: 0,
          framesSent: 0,
        ),
        startPresetHandler: () {
          if (!presetStarted.isCompleted) {
            presetStarted.complete();
          }
          return Future<void>.value();
        },
      );
      final probeCompleter = Completer<GameCaptureProbeResult>();
      final probeRunner = _FakeGameCaptureProbeRunner(
        resultFactory: (config) => probeCompleter.future,
      );
      final progressLabels = <String>[];
      final runner = StreamTestRunner(
        target: target,
        gameCaptureProbeRunner: probeRunner,
        loadedLibwebrtcArtifactProvider: () =>
            Future<StreamTestLoadedLibwebrtcArtifact?>.value(),
        hostLoadSamplerFactory: (_) => hostSampler,
        clock: () => now,
        delay: (duration) async {
          now = now.add(duration);
        },
        onProgress: (progress) => progressLabels.add(progress.detailLabel),
      );

      final runFuture = runner.run(
        const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 2),
          warmupDuration: Duration(seconds: 1),
          sampleInterval: Duration(seconds: 1),
          sourceMetadata: StreamTestSourceMetadata(
            sourceType: 'window',
            sourceIdHash: 'abc12345',
            processId: 4242,
          ),
          gameCaptureProbe: GameCaptureProbeConfig(
            enabled: true,
            duration: Duration(seconds: 1),
          ),
        ),
      );
      await presetStarted.future.timeout(const Duration(seconds: 1));

      expect(target.startedProfiles, ['Smooth']);
      expect(probeRunner.configs, hasLength(1));
      expect(
        probeRunner.configs.single.timing,
        GameCaptureProbeTiming.concurrentWithInitialPreset,
      );
      expect(probeRunner.configs.single.publicationHandoffMaxWidth, 1280);
      expect(probeRunner.configs.single.publicationHandoffMaxHeight, 720);
      expect(probeRunner.configs.single.publicationHandoffTargetFps, 30);
      expect(
        probeRunner.configs.single.duration.inMilliseconds,
        greaterThanOrEqualTo(5000),
      );
      expect(
        progressLabels.first,
        'D3D11 game probe (5s, running with first stream-test preset)',
      );
      expect(progressLabels.last, contains('Smooth - App default'));

      probeCompleter.complete(
        GameCaptureProbeResult.fromMetadata(
          config: probeRunner.configs.single,
          metadata: const {
            'schema': 'intergalactic.gameCapturePoc.v1',
            'requestedBackend': 'd3d11-present-hook',
            'attachStatus': 'attached',
            'detectedGraphicsApi': 'd3d11',
            'presentFps': 30.0,
            'presentGapP95Ms': 34.0,
            'presentGapMaxMs': 36.0,
            'droppedFrames': 0,
            'cpuReadbackCount': 0,
            'hostConsumer': {
              'enabled': true,
              'sharedStateAvailable': true,
              'd3dDeviceCreated': true,
              'openedSharedTexture': true,
              'openedTextureSlots': 3,
              'sharedTextureOpenFailures': 0,
              'observedFrameSignals': 30,
              'consumedFrames': 30,
              'duplicateSignals': 0,
              'missedFrames': 0,
              'invalidStateReads': 0,
              'frameAgeAvgMs': 1.0,
              'frameAgeP95Ms': 2.0,
              'frameAgeMaxMs': 3.0,
              'consumerGapP50Ms': 33.0,
              'consumerGapP95Ms': 34.0,
              'consumerGapMaxMs': 36.0,
              'proofReadbackCount': 0,
              'visibleProofFrames': 0,
              'lastError': 'none',
            },
            'fallbackReason': 'none',
          },
        ),
      );

      final result = await runFuture;

      expect(result.presetResults, hasLength(1));
      expect(
        result.gameCaptureProbeResult?.config.timing,
        GameCaptureProbeTiming.concurrentWithInitialPreset,
      );
      expect(
        result.toJsonText(),
        contains('"timing": "concurrentWithInitialPreset"'),
      );
      expect(
        result.toMarkdown(),
        contains('Timing: concurrent with initial stream-test preset'),
      );
    });

    test('game-capture probe unavailable result is explicit in coverage', () {
      final run = StreamTestRunResult(
        startedAt: DateTime.utc(2026, 6, 4, 1),
        endedAt: DateTime.utc(2026, 6, 4, 1, 0, 1),
        targetLabel: 'Test room',
        roomId: '!test:ourgalaxy.space',
        config: const StreamTestRunConfig(
          presets: [],
          sourceMetadata: StreamTestSourceMetadata(
            sourceType: 'window',
            sourceIdHash: 'abc12345',
          ),
          gameCaptureProbe: GameCaptureProbeConfig(enabled: true),
        ),
        presetResults: const [],
        gameCaptureProbeResult: GameCaptureProbeResult.notApplicable(
          config: GameCaptureProbeConfig(enabled: true),
          reason: 'selected source did not expose a target process id',
        ),
      );

      final coverageJson = run.diagnosticCoverage.toJson();
      expect(coverageJson.toString(), contains('game-capture probe'));
      expect(coverageJson.toString(), contains('notApplicable'));
      expect(
        run.toMarkdown(),
        contains('selected source did not expose a target process id'),
      );
    });

    test('exports sampled frame pacing from cumulative frame counters', () {
      final startedAt = DateTime.utc(2026, 5, 20, 20);
      StreamTestSample sample(int second) {
        final frameCount = second * 30;
        return StreamTestSample(
          elapsed: Duration(seconds: second),
          snapshot: _snapshot(
            collectedAt: startedAt.add(Duration(seconds: second)),
            width: 1280,
            height: 720,
            fps: 30,
            bitrateBps: 1800000,
            lossPercent: 0,
            rttMs: 20,
            framesCaptured: frameCount,
            framesEncoded: frameCount,
            framesSent: frameCount,
            includeReceiver: true,
            framesReceived: frameCount,
            framesDecoded: frameCount,
            framesRendered: frameCount,
          ),
        );
      }

      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 3)),
        nativeDiagnostics: StreamTestNativeDiagnostics.fromMarkers(const [
          '2026-05-20T20:00:02.000Z native-webrtc Inter Galactic desktop capture frame cadence new_fps=29.6 submitted_fps=29.4 max_interval_ms=48.0 p95_interval_ms=38.0 duplicated_frames=1 stale_reuse=1 wait_timeouts=0 permanent_errors=0 frames=90',
        ]),
        samples: [sample(0), sample(1), sample(2), sample(3)],
      );
      final run = StreamTestRunResult(
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 3)),
        targetLabel: 'Test room',
        roomId: '!test:ourgalaxy.space',
        config: const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 3),
        ),
        presetResults: [result],
      );

      final pacing = result.score.summary.framePacing;
      expect(pacing.capture.p50IntervalMs, closeTo(33.3, 0.2));
      expect(pacing.preEncode.p95IntervalMs, closeTo(33.3, 0.2));
      expect(pacing.encoded.maxIntervalMs, closeTo(33.3, 0.2));
      expect(pacing.sent.lastFrameCount, 90);
      expect(pacing.rendered.p50IntervalMs, closeTo(33.3, 0.2));
      expect(pacing.nativeCapture.p95IntervalMs, 38);
      expect(pacing.nativeCapture.staleFrameReuseCount, 1);

      final summaryJson = result.score.summary.toJson();
      final framePacing = summaryJson['framePacing'] as Map<String, Object?>;
      final sentJson = framePacing['sent'] as Map<String, Object?>;
      expect(sentJson['sampleCount'], 3);
      expect(sentJson['evidence'], 'sampled framesSent counter');
      expect(run.toJsonText(), contains('"framePacing"'));
      expect(run.toMarkdown(), contains('## Frame Pacing'));
      expect(run.toMarkdown(), contains('33ms p50 / 33ms p95 / 33ms max'));
      expect(run.toMarkdown(), contains('38ms p95 / 48ms max'));
    });

    test('exports early middle late and tail degradation windows', () {
      final startedAt = DateTime.utc(2026, 6, 7, 16);
      StreamTestSample sample(int second) {
        final frameCount = second <= 20
            ? second * 30
            : 600 + (second - 20) * 15;
        return StreamTestSample(
          elapsed: Duration(seconds: second),
          snapshot: _snapshot(
            collectedAt: startedAt.add(Duration(seconds: second)),
            width: 1280,
            height: 720,
            fps: second <= 20 ? 30 : 15,
            bitrateBps: 2500000,
            lossPercent: 0,
            rttMs: 20,
            framesCaptured: frameCount,
            framesEncoded: frameCount,
            framesSent: frameCount,
          ),
        );
      }

      const markers = [
        '2026-06-07T16:00:05.000Z native-webrtc game_capture_webrtc_source stats source=2560x1440 output=1280x720 format=24 fps=30.0 submitted=150 copied=160 gpuScaled=150 gpuScaleFailures=0 cpuFallback=0 readbackQueued=151 readbackReady=150 readbackNotReady=10 readbackStaleDropped=1 readbackLatencyDropped=0 readbackLatencyFramesMax=1 readbackLatencyFramesAvg=0.5 sourceFrameRegressions=0 sourceFrameGaps=10 sharedSlotMismatches=0',
        '2026-06-07T16:00:15.000Z native-webrtc game_capture_webrtc_source stats source=2560x1440 output=1280x720 format=24 fps=30.0 submitted=450 copied=470 gpuScaled=450 gpuScaleFailures=0 cpuFallback=0 readbackQueued=451 readbackReady=450 readbackNotReady=20 readbackStaleDropped=2 readbackLatencyDropped=0 readbackLatencyFramesMax=1 readbackLatencyFramesAvg=0.5 sourceFrameRegressions=0 sourceFrameGaps=20 sharedSlotMismatches=0',
        '[2026-06-07T16:00:25.000Z] INFO webrtc/native-encoder game_capture_webrtc_source stats source=2560x1440 output=1280x720 format=24 fps=20.0 submitted=600 copied=900 gpuScaled=600 gpuScaleFailures=0 cpuFallback=0 readbackQueued=650 readbackReady=600 readbackNotReady=400 readbackStaleDropped=20 readbackLatencyDropped=10 readbackLatencyFramesMax=4 readbackLatencyFramesAvg=1.8 sourceFrameRegressions=0 sourceFrameGaps=300 sharedSlotMismatches=0',
        '[2026-06-07T16:00:30.000Z] INFO webrtc/native-encoder game_capture_webrtc_source stats source=2560x1440 output=1280x720 format=24 fps=16.0 submitted=660 copied=1200 gpuScaled=660 gpuScaleFailures=0 cpuFallback=0 readbackQueued=750 readbackReady=660 readbackNotReady=800 readbackStaleDropped=45 readbackLatencyDropped=25 readbackLatencyFramesMax=4 readbackLatencyFramesAvg=2.1 sourceFrameRegressions=0 sourceFrameGaps=540 sharedSlotMismatches=0',
      ];
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 30)),
        nativeDiagnostics: StreamTestNativeDiagnostics.fromMarkers(markers),
        diagnosticLogMarkers: markers,
        samples: [for (var second = 0; second <= 30; second++) sample(second)],
      );
      final run = StreamTestRunResult(
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 30)),
        targetLabel: 'Test room',
        roomId: '!test:ourgalaxy.space',
        config: const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 30),
        ),
        presetResults: [result],
      );

      final temporalJson =
          result.toJson()['timeWindows'] as Map<String, Object?>;
      final windows = temporalJson['windows'] as List<Object?>;
      expect(windows.toString(), contains('tail_10s'));
      expect(temporalJson['lateDegradationDetected'], isTrue);
      expect(
        result.score.temporalAnalysis.lateDegradationSignals.join(' '),
        contains('D3D11 readback pressure'),
      );
      expect(
        result
            .score
            .temporalAnalysis
            .windows
            .last
            .gameCapture
            ?.readbackLatencyDroppedDelta,
        greaterThan(0),
      );
      expect(result.score.bottleneck.label, 'frame_pacing_unstable');
      expect(run.toMarkdown(), contains('## Time-Window Degradation'));
      expect(run.toMarkdown(), contains('tail_10s'));
      expect(run.toMarkdown(), contains('D3D11 readback pressure'));
    });

    test(
      'uses uncapped game-hook markers for tail time-window analysis',
      () async {
        var now = DateTime.utc(2026, 6, 7, 16);
        final startedAt = now;
        String marker(int second) {
          final timestamp = startedAt.add(Duration(seconds: second));
          final submitted = second * 30;
          final readbackPressure = second < 50 ? 0 : (second - 45) * 4;
          final maxLatency = second < 50 ? 1 : 4;
          return '${timestamp.toIso8601String()} native-webrtc '
              'game_capture_webrtc_source stats source=2560x1440 '
              'output=1280x720 format=24 fps=30.0 submitted=$submitted '
              'copied=${submitted + readbackPressure} gpuScaled=$submitted '
              'gpuScaleFailures=0 cpuFallback=0 '
              'readbackQueued=${submitted + 1} readbackReady=$submitted '
              'readbackNotReady=${second * 8 + readbackPressure} '
              'readbackStaleDropped=0 '
              'readbackLatencyDropped=$readbackPressure '
              'readbackLatencyFramesMax=$maxLatency '
              'readbackLatencyFramesAvg=${maxLatency == 1 ? 0.4 : 2.0} '
              'sourceFrameRegressions=0 sourceFrameGaps=$readbackPressure '
              'sharedSlotMismatches=0';
        }

        final markerLog = [
          for (var second = 0; second <= 60; second += 5) marker(second),
        ].join('\n');
        final runner = StreamTestRunner(
          target: _FakeStreamTestTarget(
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 30,
              captureFps: 30,
              encodeFps: 30,
              sendFps: 30,
              bitrateBps: 3000000,
              lossPercent: 0,
              rttMs: 3,
            ),
          ),
          clock: () => now,
          delay: (duration) async {
            now = now.add(duration);
          },
          diagnosticLogMarkerLimit: 4,
          diagnosticLogProvider: () async => markerLog,
        );

        final run = await runner.run(
          const StreamTestRunConfig(
            presets: [ScreenShareProfileConfig.smooth],
            durationPerPreset: Duration(seconds: 60),
            warmupDuration: Duration.zero,
            sampleInterval: Duration(seconds: 5),
            windowsCaptureBackendMode:
                WindowsScreenCaptureBackendMode.gameD3d11HookExperimental,
          ),
        );

        final result = run.presetResults.single;
        final tailWindow = result.score.temporalAnalysis.windows.firstWhere(
          (window) => window.label == 'tail_10s',
        );
        expect(result.diagnosticLogMarkers, hasLength(4));
        expect(
          tailWindow.gameCapture?.readbackLatencyDroppedDelta,
          greaterThan(0),
        );
        expect(
          result.score.temporalAnalysis.lateDegradationSignals.join(' '),
          contains('D3D11 readback pressure'),
        );
        expect(result.score.bottleneck.label, 'frame_pacing_unstable');
        expect(run.toMarkdown(), contains('D3D11 readback pressure'));
      },
    );

    test('includes stalled frame-counter windows in frame pacing', () {
      final startedAt = DateTime.utc(2026, 5, 20, 21);
      StreamTestSample sample(int second, int frameCount) {
        return StreamTestSample(
          elapsed: Duration(seconds: second),
          snapshot: _snapshot(
            collectedAt: startedAt.add(Duration(seconds: second)),
            width: 1280,
            height: 720,
            fps: frameCount == 0 ? 0 : 30,
            bitrateBps: 1800000,
            lossPercent: 0,
            rttMs: 20,
            framesCaptured: frameCount,
            framesEncoded: frameCount,
            framesSent: frameCount,
          ),
        );
      }

      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 3)),
        samples: [sample(0, 0), sample(1, 0), sample(2, 0), sample(3, 30)],
      );

      final pacing = result.score.summary.framePacing;
      expect(pacing.sent.maxIntervalMs, closeTo(1000, 0.1));
      expect(pacing.sent.p95IntervalMs, closeTo(1000, 0.1));
      expect(pacing.sent.averageFps, closeTo(10, 0.1));
      expect(pacing.sent.staleFrameReuseCount, 2);
      expect(result.score.summary.framePacing.compactLabel, contains('sent='));
    });

    test('caps stable FPS score when average FPS hides pacing stalls', () {
      final startedAt = DateTime.utc(2026, 5, 28, 1);
      StreamTestSample sample(int second, int frameCount) {
        return StreamTestSample(
          elapsed: Duration(seconds: second),
          snapshot: _snapshot(
            collectedAt: startedAt.add(Duration(seconds: second)),
            width: 1280,
            height: 720,
            fps: 30,
            bitrateBps: 1800000,
            lossPercent: 0,
            rttMs: 20,
            framesCaptured: frameCount,
            framesEncoded: frameCount,
            framesSent: frameCount,
          ),
        );
      }

      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 4)),
        samples: [
          sample(0, 0),
          sample(1, 30),
          sample(2, 30),
          sample(3, 90),
          sample(4, 120),
        ],
      );

      expect(result.score.summary.averageSendFps, 30);
      expect(result.score.summary.framePacing.sent.staleFrameReuseCount, 1);
      expect(
        result.score.summary.framePacing.sent.p95IntervalMs,
        closeTo(855, 1),
      );
      expect(result.score.stableFps, 1);
      expect(result.score.bottleneck.label, 'frame_pacing_unstable');
      expect(
        result.score.bottleneck.reasons.join(' '),
        contains('sent p95 frame interval'),
      );
    });

    test('treats native p95 and max gaps as visible stutter evidence', () {
      final startedAt = DateTime.utc(2026, 5, 31, 18, 27);
      StreamTestSample sample(int second, int frameCount) {
        return StreamTestSample(
          elapsed: Duration(seconds: second),
          snapshot: _snapshot(
            collectedAt: startedAt.add(Duration(seconds: second)),
            width: 1280,
            height: 720,
            fps: 30,
            bitrateBps: 2600000,
            lossPercent: 0,
            rttMs: 4,
            framesCaptured: frameCount,
            framesEncoded: frameCount,
            framesSent: frameCount,
          ),
        );
      }

      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 4)),
        nativeDiagnostics: StreamTestNativeDiagnostics.fromMarkers(const [
          '2026-05-31T18:27:35.000Z native-webrtc Inter Galactic desktop capture frame cadence new_fps=31.4 submitted_fps=31.3 max_interval_ms=122.0 p95_interval_ms=54.0 duplicated_frames=0 stale_reuse=0 wait_timeouts=0 permanent_errors=0 frames=63',
        ]),
        samples: [
          sample(0, 0),
          sample(1, 30),
          sample(2, 60),
          sample(3, 90),
          sample(4, 120),
        ],
      );

      expect(result.score.summary.averageSendFps, 30);
      expect(result.score.stableFps, allOf(greaterThan(4), lessThan(25)));
      expect(result.score.bottleneck.label, 'native_capture_limited');
      expect(
        result.score.bottleneck.reasons.join(' '),
        contains('native max frame gap'),
      );
    });

    test('exports applied profile details from diagnostics snapshots', () {
      final run = StreamTestRunResult(
        startedAt: DateTime.utc(2026, 5, 18, 18),
        endedAt: DateTime.utc(2026, 5, 18, 18, 0, 2),
        targetLabel: 'Test room',
        roomId: '!test:ourgalaxy.space',
        config: const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 2),
        ),
        presetResults: [
          StreamTestPresetResult(
            profile: ScreenShareProfileConfig.smooth,
            startedAt: DateTime.utc(2026, 5, 18, 18),
            endedAt: DateTime.utc(2026, 5, 18, 18, 0, 2),
            samples: [
              StreamTestSample(
                elapsed: const Duration(seconds: 1),
                snapshot: _snapshot(
                  width: 1280,
                  height: 720,
                  fps: 30,
                  bitrateBps: 1800000,
                  lossPercent: 0,
                  rttMs: 40,
                  profileDetails:
                      'advanced=true requested=1280x720@30fps/18.0Mbps codec=vp8 hardwarePreference=off',
                  codec: 'vp8',
                  encoderImplementation: 'libvpx',
                  hardwareEncodeActive: false,
                ),
              ),
            ],
          ),
        ],
      );

      final json = run.toJson();
      final resultJson =
          (json['presetResults'] as List<Object?>).single
              as Map<String, Object?>;
      final summaryJson = resultJson['summary'] as Map<String, Object?>;
      expect(summaryJson['hardwareEncodeStates'], [false]);

      expect(
        run.toJsonText(),
        contains(
          '"screenShareProfileDetails": '
          '"advanced=true requested=1280x720@30fps/18.0Mbps codec=vp8 hardwarePreference=off"',
        ),
      );
      expect(
        run.toMarkdown(),
        contains('Applied profile details: advanced=true requested=1280x720'),
      );
      expect(run.toMarkdown(), contains('codec=vp8 engine=libvpx hw=no'));
    });

    test(
      'classifies tracked low cadence with slow encode as encoder pipeline',
      () {
        final result = StreamTestPresetResult(
          profile: ScreenShareProfileConfig.smooth,
          startedAt: DateTime.utc(2026, 5, 18, 18),
          endedAt: DateTime.utc(2026, 5, 18, 18, 0, 3),
          samples: [
            StreamTestSample(
              elapsed: const Duration(seconds: 1),
              snapshot: _snapshot(
                width: 1280,
                height: 720,
                fps: 12,
                captureFps: 12,
                encodeFps: 12,
                sendFps: 12,
                averageEncodeTimeMs: 82,
                averagePacketSendDelayMs: 92,
                bitrateBps: 2000000,
                lossPercent: 0,
                rttMs: 3,
              ),
            ),
          ],
        );

        expect(result.score.bottleneck.label, 'encoder_pipeline_limited');
        expect(
          result.score.bottleneck.reasons.join(' '),
          contains('capture/encode/send FPS all track'),
        );
        expect(
          result.score.bottleneck.reasons.join(' '),
          contains('encode time 82ms exceeds'),
        );
      },
    );

    test('game hook delivery backpressure outranks generic encoder pipeline', () {
      final startedAt = DateTime.utc(2026, 6, 13, 20, 12, 7);
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 30)),
        nativeDiagnostics: StreamTestNativeDiagnostics.fromMarkers(const [
          '2026-06-13T20:12:40.000Z native-webrtc game_capture_webrtc_source stats source=2560x1440 output=1280x720 format=24 fps=19.8 submitted=695 repeated=22 duplicateSkipped=39 deliveryQueued=883 deliverySubmitted=695 deliveryOverwritten=208 deliveryPacerResyncs=204 deliveryPacerLagMaxMs=172 deliveryRepeatNoQueued=22 deliveryRepeatSourceAgeMs=120.0 deliveryRepeatSourceAgeMaxMs=240.0 deliveryRepeatSourceAgeSamples=22 deliveryOnFrameMs=37.0 deliveryOnFrameMaxMs=179.0 readyToQueueMs=0.4 readyToQueueMaxMs=4.0 readyToQueueSamples=695 deliveryQueueWaitMs=36.0 deliveryQueueWaitMaxMs=133.0 deliveryQueueWaitSamples=690 deliveryOverwriteAgeMs=91.0 deliveryOverwriteAgeMaxMs=180.0 deliveryOverwriteAgeSamples=208 deliveryOverwrittenFresh=207 readyToSubmitMs=36.0 readyToSubmitMaxMs=133.0 readyToSubmitSamples=690 sourceToSubmitMs=82.0 sourceToSubmitMaxMs=218.0 sourceToSubmitSamples=690 sourceToReadbackReadyMs=49.0 sourceToReadbackReadyMaxMs=62.0 sourceToReadbackReadySamples=690 readbackQueueToMapMs=19.0 readbackQueueToMapMaxMs=20.0 readbackQueueToMapSamples=690 mapToI420Ms=12.0 mapToI420MaxMs=14.0 mapToI420Samples=690 sourceToI420ReadyMs=62.0 sourceToI420ReadyMaxMs=73.0 sourceToI420ReadySamples=690 sourceToQueueMs=47.0 sourceToQueueMaxMs=210.0 sourceToQueueSamples=883 sourceDuplicateSkipAgeMs=160.0 sourceDuplicateSkipAgeMaxMs=260.0 sourceDuplicateSkipAgeSamples=39 copied=2085 dropped=0 overwritten=2082 gpuScaled=695 gpuScaleFailures=0 cpuFallback=0 nativeNv12Submitted=688 nativeNv12Failures=0 nativeNv12Queued=882 nativeNv12Ready=881 nativeNv12NotReadyPolls=30 nativeNv12Overwritten=0 nativeNv12OverwriteAgeMs=0 nativeNv12OverwriteAgeMaxMs=0 nativeNv12OverwriteAgeSamples=0 nativeNv12OverwrittenFresh=0 nativeNv12ReadyDropped=0 nativeNv12ReadyDropAgeMs=0 nativeNv12ReadyDropAgeMaxMs=0 nativeNv12ReadyDropAgeSamples=0 nativeNv12ReadyDroppedFresh=0 nativeNv12ConvertMs=4.0 nativeNv12ConvertMaxMs=8.0 nativeNv12ConvertSamples=52 readbackQueued=3 readbackReady=2 readbackNotReady=7 readbackOverwritten=0 readbackStaleDropped=1 readbackLatencyDropped=0 readbackMapAttempts=9 gpuScaleMs=35.0 copyMs=0.0 mapMs=0.0 readbackLatencyMs=0.0 readbackLatencyFramesAvg=0.0 readbackLatencyFramesMax=0 sourceFrameIndex=2063 lastSubmittedSourceFrameIndex=2056 sourceFrameRegressions=0 sourceFrameDuplicates=22 sourceFrameGaps=1368 sharedSlotMismatches=0 timestampMode=paced timestampDeltaMs=33.3 timestampDeltaMaxMs=33.3 timestampSamples=52 timestampAdjustments=0 deliveryWallDeltaMs=52.0 deliveryWallDeltaMaxMs=179.0 deliveryWallSamples=52 deliveryWallOver2x=28 deliveryWallOver3x=9 deliveryWallUnderHalf=0 sourceQpcDeltaMs=48.0 sourceQpcDeltaMaxMs=201.0 sourceQpcSamples=688 sourceQpcRegressions=0 convertMs=0.0 mapFailures=0 convertFailures=0 proofFrames=2 visibleProofFrames=2 i420ProofFrames=1 visibleI420ProofFrames=1 initialBlackSkipped=0 visibleSourceSeen=true',
          '2026-06-13T20:12:40.000Z native-webrtc Inter Galactic Media Foundation H.264 encoder timing frame=695 stage=ok_native_nv12 size=1280x720 target_fps=30 input_path=native_nv12 native_input=yes native_sample_failed=no native_suspended=no native_ready_fence=yes native_ready_fence_timeout=no native_ready_fence_wait_ms=0.2 budget_ms=33.3 total_ms=60.0 to_i420_ms=0 nv12_ms=0 create_sample_ms=1.0 input_copy_ms=0.2 process_input_ms=0.2 pre_drain_ms=0 retry_drain_ms=0 post_drain_ms=58.0 process_output_ms=55.0 output_copy_ms=0.2 outputs=1 output_bytes=25000 queue=1 retained_samples=1 encoded_outputs=50 async=yes slow=yes very_slow=no',
        ]),
        samples: [
          StreamTestSample(
            elapsed: const Duration(seconds: 1),
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 18.6,
              captureFps: 22.2,
              encodeFps: 21.5,
              sendFps: 18.6,
              averageEncodeTimeMs: 56,
              bitrateBps: 1900000,
              lossPercent: 0,
              rttMs: 75,
              requestedWidth: 1280,
              requestedHeight: 720,
              requestedFps: 30,
              framesCaptured: 22,
              framesEncoded: 21,
              framesSent: 18,
            ),
          ),
        ],
      );

      expect(result.score.bottleneck.label, 'delivery_queue_limited');
      expect(
        result.score.bottleneck.reasons.join(' '),
        contains('source-to-submit latency averaged 82.0ms'),
      );
      expect(
        result.score.bottleneck.reasons.join(' '),
        contains('delivery/source-to-submit pressure'),
      );
      expect(
        result.score.bottleneck.evidenceFor.join(' '),
        contains('delivery pacer resynced 204 times'),
      );
      expect(
        result.score.bottleneck.evidenceFor.join(' '),
        contains(
          'delivery pacer repeated 22 frames with no fresh queued frame',
        ),
      );
      expect(
        result.score.bottleneck.evidenceFor.join(' '),
        contains(
          'capture loop skipped unchanged source frames with max source age 260.0ms',
        ),
      );
      expect(
        result.score.bottleneck.evidenceFor.join(' '),
        contains('delivery queue overwrote 207 fresh frames'),
      );
      expect(
        result.score.bottleneck.evidenceFor.join(' '),
        contains('native MediaFoundation encoder timing averaged 60.0ms'),
      );
      expect(
        result.nativeDiagnostics.gameCaptureFrameSummaryLabel,
        contains('delivery_repeat_no_queue=22'),
      );
      expect(
        result.nativeDiagnostics.toJson(),
        containsPair('maxGameCaptureSourceDuplicateSkipAgeMs', 260.0),
      );
      expect(
        result.score.bottleneck.evidenceAgainstFalseCauses.join(' '),
        contains('native NV12 WebRTC source submitted 688 frames'),
      );
    });

    test('native NV12 delivery pacing outranks proof-readback repeats', () {
      final startedAt = DateTime.utc(2026, 6, 13, 23, 51, 43);
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 61)),
        nativeDiagnostics: StreamTestNativeDiagnostics.fromMarkers(const [
          '2026-06-13T23:52:50.557Z native-webrtc game_capture_webrtc_source stats source=2560x1440 output=1280x720 format=24 fps=27.187167 backendContractVersion=2 sourceApi=d3d11 sourceApiId=1 sourceFormat=r10g10b10a2 sourceFormatId=3 syncKind=event readyState=ready failureReason=none nativeAdmissionStrictDeadlineEnabled=true nativeAdmissionSourceDrivenFreshDue=8 nativeAdmissionSourceQpcDue=3 nativeAdmissionEarlySourceDueSuppressed=21 nativeAdmissionDeadlineDue=1775 nativeAdmissionDeadlineLatenessMs=2.5 nativeAdmissionDeadlineLatenessMaxMs=94.0 nativeAdmissionDeadlineLatenessSamples=1775 nativeAdmissionDeadlineOver1x=12 nativeAdmissionDeadlineOver2x=4 nativeAdmissionDeadlineOver3x=1 nativeAdmissionNoSourceOnDeadline=2 nativeAdmissionRepeatedOnDeadline=38 nativeAdmissionSubmitOnDeadline=1737 nativeAdmissionSubmitOnEarlySource=3 nativeNv12PendingOnDeadline=121 nativeNv12NoPendingOnDeadline=1654 nativeNv12ReadyOnDeadline=49 nativeNv12NoReadyOnDeadline=72 submitted=1775 repeated=121 duplicateSkipped=38 deliveryQueued=1721 deliverySubmitted=1775 deliveryOverwritten=65 deliveryPacerResyncs=110 deliveryPacerLagMaxMs=141 deliveryOnFrameMs=21.088450 deliveryOnFrameMaxMs=175.103400 readyToQueueMs=0.011614 readyToQueueMaxMs=14.813600 readyToQueueSamples=1721 deliveryQueueWaitMs=29.269322 deliveryQueueWaitMaxMs=194.175300 deliveryQueueWaitSamples=1654 readyToSubmitMs=29.281275 readyToSubmitMaxMs=194.178900 readyToSubmitSamples=1654 sourceToSubmitMs=64.853398 sourceToSubmitMaxMs=280.773700 sourceToSubmitSamples=1654 sourceToReadbackReadyMs=49.928100 sourceToReadbackReadyMaxMs=62.974600 sourceToReadbackReadySamples=2 readbackQueueToMapMs=19.089800 readbackQueueToMapMaxMs=20.615800 readbackQueueToMapSamples=2 mapToI420Ms=13.096150 mapToI420MaxMs=13.755500 mapToI420Samples=2 sourceToQueueMs=36.230016 sourceToQueueMaxMs=280.751300 sourceToQueueSamples=1721 copied=3703 dropped=0 overwritten=3700 gpuScaled=1775 gpuScaleFailures=0 nativeNv12Submitted=1766 nativeNv12Failures=0 nativeNv12Queued=1813 nativeNv12Ready=1719 nativeNv12NotReadyPolls=3782 nativeNv12Overwritten=0 nativeNv12OverwriteAgeMs=0 nativeNv12OverwriteAgeMaxMs=0 nativeNv12OverwriteAgeSamples=0 nativeNv12OverwrittenFresh=0 nativeNv12ReadyDropped=93 nativeNv12ReadyDropAgeMs=44.0 nativeNv12ReadyDropAgeMaxMs=108.0 nativeNv12ReadyDropAgeSamples=93 nativeNv12ReadyDroppedFresh=93 nativeNv12LateReadyDropEnabled=true nativeNv12LateReadyDropThresholdMs=34 nativeNv12WarmupI420Frames=0 nativeNv12LateReadyDropped=3 nativeNv12LateReadyDropAgeMs=40.0 nativeNv12LateReadyDropAgeMaxMs=72.0 nativeNv12LateReadyDropAgeSamples=3 nativeNv12LateReadyDroppedFresh=2 nativeNv12LateReadyDropBltToReadyMs=41.0 nativeNv12LateReadyDropBltToReadyMaxMs=73.0 nativeNv12LateReadyDropBltToReadySamples=3 nativeNv12ConvertMs=23.646940 nativeNv12ConvertMaxMs=82.829200 nativeNv12ConvertSamples=138 cpuFallback=0 readbackQueued=3 readbackReady=2 readbackNotReady=6 readbackOverwritten=0 readbackStaleDropped=1 readbackLatencyDropped=0 readbackMapAttempts=8 readbackLatencyFramesAvg=0.000000 readbackLatencyFramesMax=0 sourceFrameIndex=3703 lastSubmittedSourceFrameIndex=3692 sourceFrameRegressions=0 sourceFrameDuplicates=121 sourceFrameGaps=2038 sharedSlotMismatches=0 timestampMode=paced timestampDeltaMs=33.333000 timestampDeltaMaxMs=33.333000 timestampSamples=139 timestampTotalDeltaMs=33.333000 timestampTotalDeltaMaxMs=33.333000 timestampTotalSamples=1774 timestampAdjustments=0 deliveryWallDeltaMs=36.000000 deliveryWallDeltaMaxMs=138.000000 deliveryWallSamples=139 deliveryWallOver2x=4 deliveryWallOver3x=1 deliveryWallUnderHalf=4 sourceQpcDeltaMs=39.518765 sourceQpcDeltaMaxMs=228.821000 sourceQpcSamples=1653 sourceQpcRegressions=0 sourceQpcOver2x=5 sourceQpcOver3x=2 sourceQpcUnderHalf=7 sourceLatestObservedFrames=1688 sourceLatestFrameGaps=2100 sourceLatestFrameRegressions=0 sourceLatestQpcDeltaMs=35.000000 sourceLatestQpcDeltaMaxMs=110.000000 sourceLatestQpcSamples=1687 sourceLatestQpcRegressions=0 sourceLatestQpcOver2x=4 sourceLatestQpcOver3x=1 sourceLatestQpcUnderHalf=5 sourceLatestObservationDeltaMs=36.500000 sourceLatestObservationDeltaMaxMs=120.000000 sourceLatestObservationSamples=1687 sourceLatestObservationOver2x=3 sourceLatestObservationOver3x=1 sourceLatestEventAgeMs=12.000000 sourceLatestEventAgeMaxMs=45.000000 sourceLatestEventAgeSamples=1688 sourceLatestEventAgeOver1x=2 sourceLatestEventAgeOver2x=1 sourceLatestEventAgeOver3x=0 sourcePublishObservationAgeMs=0.900000 sourcePublishObservationAgeMaxMs=6.000000 sourcePublishObservationAgeSamples=1688 sourcePublishObservationAgeOver1x=0 sourcePublishObservationAgeOver2x=0 sourcePublishObservationAgeOver3x=0 producerPresentGapMs=16.700000 producerPresentGapMaxMs=43.000000 producerPresentGapSamples=3702 producerCaptureGapMs=16.800000 producerCaptureGapMaxMs=45.000000 producerCaptureGapSamples=3702 producerPresentToPublishMs=1.200000 producerPresentToPublishMaxMs=14.000000 producerPresentToPublishSamples=3703 producerCopyMs=0.300000 producerCopyMaxMs=3.200000 producerCopySamples=3703 producerResolveMs=0.000000 producerResolveMaxMs=0.000000 producerResolveSamples=0 producerThrottledFrames=0 convertMs=0.000000 mapFailures=0 convertFailures=0 proofFrames=2 visibleProofFrames=2 i420ProofFrames=1 visibleI420ProofFrames=1 initialBlackSkipped=0 visibleSourceSeen=true',
          '2026-06-13T23:52:50.558Z native-webrtc Inter Galactic Media Foundation H.264 encoder timing frame=1775 stage=ok_native_nv12 size=1280x720 target_fps=30 input_path=native_nv12 native_input=yes native_sample_failed=no native_suspended=no native_ready_fence=yes native_ready_fence_timeout=no native_ready_fence_wait_ms=0.1 budget_ms=33.3 total_ms=16.9 process_input_ms=0.2 process_output_ms=14.0 outputs=1 encoded_outputs=56 async=yes slow=no',
        ]),
        samples: [
          StreamTestSample(
            elapsed: const Duration(seconds: 61),
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 23.4,
              captureFps: 27.2,
              encodeFps: 22.3,
              sendFps: 23.4,
              averageEncodeTimeMs: 49.5,
              bitrateBps: 1300000,
              lossPercent: 0,
              rttMs: 62,
              requestedWidth: 1280,
              requestedHeight: 720,
              requestedFps: 30,
              framesCaptured: 1658,
              framesEncoded: 1363,
              framesSent: 1427,
            ),
          ),
        ],
      );

      expect(result.score.bottleneck.label, 'native_nv12_ready_limited');
      expect(
        result.score.bottleneck.reasons.join(' '),
        contains('native NV12 ready queue dropped 93 frames'),
      );
      expect(
        result.score.bottleneck.reasons.join(' '),
        isNot(contains('game hook repeated')),
      );
      expect(
        result.score.bottleneck.evidenceFor.join(' '),
        allOf(
          contains('delivery pacer resynced 110 times'),
          contains('native NV12 ready queue dropped 93 frames'),
          contains('native NV12 ready drain dropped 93 fresh frames'),
          contains('native NV12 readiness averaged 23.6ms'),
        ),
      );
      expect(
        result.nativeDiagnostics.toJson(),
        containsPair('maxGameCaptureNativeNv12ReadyDropAgeMs', 108.0),
      );
      expect(
        result.nativeDiagnostics.gameCaptureNativeNv12LateReadyDropEnabled,
        isTrue,
      );
      expect(
        result.nativeDiagnostics.toJson(),
        allOf(
          containsPair(
            'gameCaptureNativeAdmissionStrictDeadlineEnabled',
            isTrue,
          ),
          containsPair('gameCaptureNativeAdmissionDeadlineDueFrames', 1775),
          containsPair('maxGameCaptureNativeAdmissionDeadlineLatenessMs', 94.0),
          containsPair('gameCaptureNativeAdmissionDeadlineOver2xFrames', 4),
          containsPair('gameCaptureNativeNv12NoReadyOnDeadlineFrames', 72),
          containsPair('gameCaptureSourceQpcOver2xFrames', 5),
          containsPair('gameCaptureSourceQpcUnderHalfFrames', 7),
        ),
      );
      expect(
        result.nativeDiagnostics.toJson(),
        allOf(
          containsPair('gameCaptureSourceLatestObservedFrames', 1688),
          containsPair('maxGameCaptureSourceLatestQpcDeltaMs', 110.0),
          containsPair('maxGameCaptureSourceLatestObservationDeltaMs', 120.0),
          containsPair('maxGameCaptureSourceLatestEventAgeMs', 45.0),
          containsPair('gameCaptureSourceLatestEventAgeOver2xFrames', 1),
        ),
      );
      expect(
        result.nativeDiagnostics.toJson(),
        allOf(
          containsPair('maxGameCaptureSourcePublishObservationAgeMs', 6.0),
          containsPair('maxGameCaptureProducerPresentGapMs', 43.0),
          containsPair('gameCaptureProducerCaptureGapSamples', 3702),
          containsPair('maxGameCaptureProducerPresentToPublishMs', 14.0),
          containsPair('gameCaptureProducerThrottledFrames', 0),
        ),
      );
      expect(
        result.nativeDiagnostics.toJson(),
        allOf(
          containsPair('gameCaptureNativeNv12LateReadyDropThresholdMs', 34),
          containsPair('gameCaptureNativeNv12WarmupI420Frames', 0),
          containsPair('gameCaptureNativeNv12LateReadyDroppedFrames', 3),
          containsPair('maxGameCaptureNativeNv12LateReadyDropAgeMs', 72.0),
          containsPair(
            'maxGameCaptureNativeNv12LateReadyDropBltToReadyMs',
            73.0,
          ),
        ),
      );
      expect(
        result.nativeDiagnostics.gameCaptureFrameSummaryLabel,
        contains(
          'native_nv12_late_ready_drop=enabled:true threshold:34 dropped:3',
        ),
      );
      expect(
        result.nativeDiagnostics.gameCaptureFrameSummaryLabel,
        contains('native_nv12_warmup_i420_frames=0'),
      );
      expect(
        result.nativeDiagnostics.gameCaptureFrameSummaryLabel,
        contains(
          'source_latest=observed:1688 gaps:2100 regressions:0 qpc:35ms/110ms',
        ),
      );
      expect(
        result.nativeDiagnostics.gameCaptureFrameSummaryLabel,
        contains(
          'source_publish_age:1ms/6ms publish_age_over:0/0/0 '
          'producer=present:17ms/43ms',
        ),
      );
      expect(
        result.score.summary.senderHandoffDiagnosticsLabel,
        contains(
          'source_latest=observed:1688 gaps:2100 regressions:0 qpc:35ms/110ms',
        ),
      );
      expect(
        result.score.summary.senderHandoffDiagnosticsLabel,
        contains(
          'source_publish_age:1ms/6ms publish_over:0/0/0 '
          'producer=present:17ms/43ms',
        ),
      );
      expect(
        result.score.summary.senderHandoffDiagnosticsJson['sourceLatest'],
        isA<Map<String, Object?>>()
            .having((value) => value['observedFrames'], 'observedFrames', 1688)
            .having((value) => value['frameGaps'], 'frameGaps', 2100),
      );
      expect(
        result.score.summary.senderHandoffDiagnosticsJson['sourceProducer'],
        isA<Map<String, Object?>>()
            .having(
              (value) => (value['presentGap'] as Map<String, Object?>)['maxMs'],
              'presentGap.maxMs',
              43.0,
            )
            .having(
              (value) =>
                  (value['presentToPublish'] as Map<String, Object?>)['maxMs'],
              'presentToPublish.maxMs',
              14.0,
            ),
      );
      expect(
        result.score.bottleneck.evidenceFor.join(' '),
        isNot(contains('readback queue-to-map')),
      );
    });

    test('classifies native NV12 GPU queue delay separately from execution', () {
      final startedAt = DateTime.utc(2026, 7, 4, 1, 21);
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 61)),
        nativeDiagnostics: StreamTestNativeDiagnostics.fromMarkers(const [
          '2026-07-04T01:22:06.000Z native-webrtc game_capture_webrtc_source stats sourceMode=helper-d3d11 source=2560x1440 output=1280x720 format=24 fps=28.2 submitted=1701 copied=2265 gpuScaled=1701 gpuScaleFailures=0 cpuFallback=0 deliveryQueued=1701 deliverySubmitted=1701 deliverySkipNoQueued=106 deliveryFreshWakeAfterSkip=63 deliveryFreshImmediate=1301 deliveryOnFrameCallMs=0.6 deliveryOnFrameCallMaxMs=2.0 deliveryOnFrameCallSamples=1701 sourceToSubmitMs=24.27 sourceToSubmitMaxMs=238.85 sourceToSubmitSamples=2265 nativeNv12Submitted=1701 nativeNv12Failures=0 nativeNv12Queued=1701 nativeNv12Ready=1464 nativeNv12NotReadyPolls=3899 nativeNv12ReadyPolicy=fence nativeNv12FenceAvailable=true nativeNv12FenceSignaled=1701 nativeNv12FenceReady=1464 nativeNv12FenceSignalFailures=0 nativeNv12ConvertMs=19.17 nativeNv12ConvertMaxMs=94.36 nativeNv12ConvertSamples=145 nativeNv12VideoProcessorBltToReadyMs=14.27 nativeNv12VideoProcessorBltToReadyMaxMs=94.36 nativeNv12VideoProcessorBltToReadySamples=145 nativeNv12VideoProcessorBltSubmitToFenceMs=14.27 nativeNv12VideoProcessorBltSubmitToFenceMaxMs=94.36 nativeNv12VideoProcessorBltSubmitToFenceSamples=145 nativeNv12VideoProcessorBltGpuExecutionMs=2.16 nativeNv12VideoProcessorBltGpuExecutionMaxMs=32.39 nativeNv12VideoProcessorBltGpuExecutionSamples=145 nativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs=12.11 nativeNv12VideoProcessorBltEstimatedGpuQueueDelayMaxMs=62.16 nativeNv12VideoProcessorBltEstimatedGpuQueueDelaySamples=145 nativeNv12BltToReadyOver1x=184 nativeNv12BltToReadyOver2x=18 nativeNv12BltToReadyOver3x=1 nativeNv12SingleInFlightEnabled=true nativeNv12SingleInFlightDeferred=243 nativeNv12SingleInFlightDeferredFresh=243 nativeNv12SingleInFlightPendingMax=1 nativeNv12SingleInFlightDeferredSourceAgeMs=3.11 nativeNv12SingleInFlightDeferredSourceAgeMaxMs=28.89 nativeNv12SingleInFlightDeferredSourceAgeSamples=243 nativeNv12GpuQueueBackoffEnabled=true nativeNv12GpuQueueBackoffThresholdFrames=2 nativeNv12GpuQueueBackoffDurationFrames=1 nativeNv12GpuQueueBackoffTriggered=11 nativeNv12GpuQueueBackoffSuppressed=30 nativeNv12GpuQueueBackoffSuppressedFresh=30 nativeNv12GpuQueueBackoffTriggerBltToReadyMs=81.85 nativeNv12GpuQueueBackoffTriggerBltToReadyMaxMs=106.51 nativeNv12GpuQueueBackoffTriggerBltToReadySamples=11 sourceQpcDeltaMs=35.35 sourceQpcDeltaMaxMs=296.237 sourceQpcSamples=2265 sourceQpcOver2x=47 sourceQpcOver3x=39 sourceFrameRegressions=0 sharedSlotMismatches=0 visibleSourceSeen=true',
          '2026-07-04T01:22:06.100Z native-webrtc Inter Galactic Media Foundation H.264 encoder timing frame=1701 stage=ok_native_nv12 size=1280x720 target_fps=30 input_path=native_nv12 native_input=yes native_sample_failed=no native_suspended=no native_ready_fence=yes native_ready_fence_timeout=no native_ready_fence_wait_ms=0.1 budget_ms=33.3 total_ms=16.0 process_input_ms=0.2 process_output_ms=0.5 encoded_callback_ms=0.2 outputs=1 output_bytes=18000 queue=1 retained_samples=1 encoded_outputs=1580 async=yes slow=no',
        ]),
        samples: [
          StreamTestSample(
            elapsed: const Duration(seconds: 61),
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 25.55,
              captureFps: 28.27,
              encodeFps: 25.53,
              sendFps: 25.55,
              averageEncodeTimeMs: 17,
              bitrateBps: 10000000,
              lossPercent: 0,
              rttMs: 3,
              requestedWidth: 1280,
              requestedHeight: 720,
              requestedFps: 30,
              framesCaptured: 1724,
              framesEncoded: 1557,
              framesSent: 1558,
              codec: 'H264',
              encoderImplementation: 'Media Foundation H.264',
              hardwareEncodeActive: true,
            ),
          ),
        ],
      );

      expect(
        result.score.bottleneck.label,
        'native_nv12_gpu_queue_delay_limited',
      );
      expect(result.score.stableFps, 10);
      expect(
        result.score.bottleneck.reasons.join(' '),
        allOf(
          contains('estimated GPU queue delay averaged 12.1ms'),
          contains('GPU execution averaged 2.2ms'),
          contains('VideoProcessorBlt-to-ready peaked at 94.4ms'),
        ),
      );
      expect(
        result.score.bottleneck.evidenceFor.join(' '),
        allOf(
          contains('estimated GPU queue delay averaged 5.6x'),
          contains('BLT-to-ready over-budget counts 184/18/1'),
          contains('native NV12 readiness polled not-ready 3899 times'),
          contains('GPU queue backoff triggered 11 times'),
          contains('single-in-flight admission deferred 243 frames'),
          contains('source-to-submit averaged 24.3ms'),
        ),
      );
      expect(
        result.score.bottleneck.evidenceAgainstFalseCauses.join(' '),
        allOf(
          contains('VideoProcessorBlt GPU execution was 2.2ms avg'),
          contains('native NV12 WebRTC source submitted 1701 frames'),
          contains('network evidence is clean'),
        ),
      );
      expect(
        result.score.bottleneck.recommendedNextAction,
        'inspect GPU scheduling and conversion admission',
      );
    });

    test('falls through native NV12 queue delay to ready limited', () {
      final startedAt = DateTime.utc(2026, 7, 4, 1, 22);
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 61)),
        nativeDiagnostics: StreamTestNativeDiagnostics.fromMarkers(const [
          '2026-07-04T01:23:06.000Z native-webrtc game_capture_webrtc_source stats source=2560x1440 output=1280x720 format=24 fps=24.0 submitted=1440 copied=1440 gpuScaled=1440 gpuScaleFailures=0 cpuFallback=0 deliveryQueued=1440 deliverySubmitted=1440 nativeNv12Submitted=1440 nativeNv12Failures=0 nativeNv12Queued=1440 nativeNv12Ready=1300 nativeNv12NotReadyPolls=200 nativeNv12ReadyPolicy=fence nativeNv12FenceAvailable=true nativeNv12FenceSignaled=1440 nativeNv12FenceReady=1300 nativeNv12ConvertMs=31.0 nativeNv12ConvertMaxMs=90.0 nativeNv12ConvertSamples=120 nativeNv12ReadyDropped=84 nativeNv12ReadyDroppedFresh=84 nativeNv12ReadyDropAgeMaxMs=96 nativeNv12ReadyDropAgeSamples=84 nativeNv12VideoProcessorBltToReadyMs=31.0 nativeNv12VideoProcessorBltToReadyMaxMs=90.0 nativeNv12VideoProcessorBltToReadySamples=120 nativeNv12VideoProcessorBltGpuExecutionMs=4.0 nativeNv12VideoProcessorBltGpuExecutionMaxMs=10.0 nativeNv12VideoProcessorBltGpuExecutionSamples=120 nativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs=4.0 nativeNv12VideoProcessorBltEstimatedGpuQueueDelayMaxMs=20.0 nativeNv12VideoProcessorBltEstimatedGpuQueueDelaySamples=120 sourceFrameRegressions=0 sharedSlotMismatches=0 visibleSourceSeen=true',
          '2026-07-04T01:23:06.100Z native-webrtc Inter Galactic Media Foundation H.264 encoder timing frame=1440 stage=ok_native_nv12 size=1280x720 target_fps=30 input_path=native_nv12 native_input=yes native_sample_failed=no native_suspended=no native_ready_fence=yes native_ready_fence_timeout=no native_ready_fence_wait_ms=0.1 budget_ms=33.3 total_ms=16.0 process_input_ms=0.2 process_output_ms=0.5 encoded_callback_ms=0.2 outputs=1 output_bytes=18000 queue=1 retained_samples=1 encoded_outputs=1300 async=yes slow=no',
        ]),
        samples: [
          StreamTestSample(
            elapsed: const Duration(seconds: 61),
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 24.0,
              captureFps: 24.0,
              encodeFps: 24.0,
              sendFps: 24.0,
              averageEncodeTimeMs: 16,
              bitrateBps: 10000000,
              lossPercent: 0,
              rttMs: 3,
              requestedWidth: 1280,
              requestedHeight: 720,
              requestedFps: 30,
            ),
          ),
        ],
      );

      expect(result.score.bottleneck.label, 'native_nv12_ready_limited');
      expect(
        result.score.bottleneck.reasons.join(' '),
        contains('native NV12 ready queue dropped 84 frames'),
      );
      expect(
        result.score.bottleneck.reasons.join(' '),
        isNot(contains('estimated GPU queue delay')),
      );
    });

    test('does not classify clean average-pass native tails as ready limited', () {
      final startedAt = DateTime.utc(2026, 6, 16, 2, 32);
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 60)),
        nativeDiagnostics: StreamTestNativeDiagnostics.fromMarkers(const [
          '2026-06-16T02:33:02.000Z native-webrtc game_capture_webrtc_source stats source=2560x1440 output=1280x720 format=24 fps=31.0 submitted=1810 repeated=0 copied=1860 gpuScaled=1810 gpuScaleFailures=0 cpuFallback=0 deliveryQueued=1810 deliverySubmitted=1810 deliveryOverwritten=0 deliveryPacerResyncs=0 deliveryOnFrameCallMs=0.4 deliveryOnFrameCallMaxMs=1.6 deliveryOnFrameCallSamples=1810 deliveryQueueWaitMs=0.6 deliveryQueueWaitMaxMs=9.0 deliveryQueueWaitSamples=1810 sourceToSubmitMs=12.0 sourceToSubmitMaxMs=128.0 sourceToSubmitSamples=1810 nativeNv12Submitted=1808 nativeNv12Failures=0 nativeNv12Queued=1810 nativeNv12Ready=1810 nativeNv12NotReadyPolls=0 nativeNv12ReadyDropped=0 nativeNv12ReadyPolicy=fence nativeNv12FenceAvailable=true nativeNv12FenceSignaled=1810 nativeNv12FenceReady=1810 nativeNv12FenceSignalFailures=0 nativeNv12ConvertMs=2.0 nativeNv12ConvertMaxMs=48.0 nativeNv12ConvertSamples=1808 nativeNv12BgraScaleDrawMs=5.0 nativeNv12BgraScaleDrawMaxMs=103.0 nativeNv12BgraScaleDrawSamples=1808 nativeNv12VideoProcessorBltSubmitMs=1.0 nativeNv12VideoProcessorBltSubmitMaxMs=79.0 nativeNv12VideoProcessorBltSubmitSamples=1808 nativeNv12VideoProcessorBltToReadyMs=1.0 nativeNv12VideoProcessorBltToReadyMaxMs=68.0 nativeNv12VideoProcessorBltToReadySamples=1808 nativeNv12ConversionStartAgeMs=4.0 nativeNv12ConversionStartAgeMaxMs=20.0 nativeNv12ConversionStartAgeSamples=1808 nativeNv12StaleBeforeQueue=4 sourceFrameRegressions=0 sharedSlotMismatches=0 visibleSourceSeen=true',
          '2026-06-16T02:33:02.050Z native-webrtc Inter Galactic WebRTC sender handoff source_on_frame stats calls=1810 adapter_drops=0 scaled=0 avg_ms=0.3 max_ms=1.4 adapt_ms=0.0 adapt_max_ms=0.1 scale_ms=0 scale_max_ms=0 broadcast_ms=0.2 broadcast_max_ms=1.2',
          '2026-06-16T02:33:02.100Z native-webrtc Inter Galactic Media Foundation H.264 encoder timing frame=1810 stage=ok_native_nv12 size=1280x720 target_fps=30 input_path=native_nv12 native_input=yes native_sample_failed=no native_suspended=no native_ready_fence=yes native_ready_fence_timeout=no native_ready_fence_wait_ms=0.0 budget_ms=33.3 total_ms=1.2 process_input_ms=0.3 process_output_ms=0.2 output_copy_ms=0.1 encoded_callback_ms=0.2 encoded_callback_invocations=1 encoded_callback_async=no encoded_callback_queue_depth=0 encoded_callback_drops=0 outputs=1 output_bytes=18000 queue=1 retained_samples=1 encoded_outputs=1810 async=yes slow=no',
        ]),
        samples: [
          StreamTestSample(
            elapsed: const Duration(seconds: 60),
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 30.2,
              captureFps: 31.6,
              encodeFps: 29.9,
              sendFps: 30.2,
              averageEncodeTimeMs: 12,
              bitrateBps: 1500000,
              lossPercent: 0,
              rttMs: 3,
              requestedWidth: 1280,
              requestedHeight: 720,
              requestedFps: 30,
              framesCaptured: 1896,
              framesEncoded: 1794,
              framesSent: 1812,
              codec: 'H264',
              encoderImplementation: 'Media Foundation H.264',
              hardwareEncodeActive: true,
            ),
          ),
        ],
      );

      expect(result.score.bottleneck.label, 'healthy');
      expect(
        result.score.bottleneck.reasons.join(' '),
        contains('native_tail_spike_review'),
      );
      expect(
        result.score.bottleneck.evidenceFor.join(' '),
        allOf(
          contains('source adapter drops 0'),
          contains('BGRA scale 5ms/103ms'),
          contains('source-to-submit 12ms/128ms'),
        ),
      );
      expect(
        result.score.bottleneck.evidenceFor.join(' '),
        isNot(contains('native NV12 ready queue dropped')),
      );
      expect(
        result.score.bottleneck.recommendedNextAction,
        'no stream change recommended',
      );
    });

    test('classifies slow native capture with fast encoder separately', () {
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: DateTime.utc(2026, 5, 19, 14, 37, 30),
        endedAt: DateTime.utc(2026, 5, 19, 14, 38),
        nativeDiagnostics: StreamTestNativeDiagnostics.fromMarkers(const [
          '2026-05-19T14:37:40.000Z native-webrtc Inter Galactic desktop capture options type=window mode=wgc-only detect_updated_region=1 directx=0 crop_window=0 wgc_screen=1 wgc_window=1 wgc_fallback=0',
          '2026-05-19T14:37:42.000Z native-webrtc Inter Galactic desktop capture cadence target_delay_ms=33 avg_capture_call_ms=82.0 max_capture_call_ms=240 scheduled_delay_ms=0 calls=24',
          '2026-05-19T14:37:42.000Z native-webrtc Inter Galactic desktop capture pipeline native_source=2560x1440 requested_max=1280x720 pre_encode=1280x720 target_fps=30 native_fps=13.4 scale=down crop_region=false',
          '2026-05-19T14:37:43.000Z native-webrtc Inter Galactic Media Foundation H.264 encoder timing frame=120 total_ms=2.4 process_output_ms=0.1 slow=no',
        ]),
        samples: [
          StreamTestSample(
            elapsed: const Duration(seconds: 1),
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 13,
              captureFps: 13,
              encodeFps: 13,
              sendFps: 13,
              averageEncodeTimeMs: 82,
              bitrateBps: 900000,
              lossPercent: 0,
              rttMs: 2,
            ),
          ),
        ],
      );

      expect(result.score.bottleneck.label, 'native_capture_limited');
      expect(result.score.summary.nativeDiagnostics.backendLabel, 'wgc-only');
      expect(
        result.score.bottleneck.reasons.join(' '),
        contains('native capture calls average 82ms'),
      );
      expect(
        result.score.bottleneck.reasons.join(' '),
        contains('native MediaFoundation encoder averages 2.4ms'),
      );
    });

    test(
      'native p95 gaps outrank aggregate WebRTC encode time when native encoder is fast',
      () {
        final result = StreamTestPresetResult(
          profile: ScreenShareProfileConfig.balanced,
          startedAt: DateTime.utc(2026, 6, 2, 19, 44, 24),
          endedAt: DateTime.utc(2026, 6, 2, 19, 45, 24),
          nativeDiagnostics: StreamTestNativeDiagnostics.fromMarkers(const [
            '2026-06-02T19:44:40.000Z native-webrtc Inter Galactic desktop capture options type=window mode=default dirty_region_mode=force-full-frame detect_updated_region=0 directx=1 crop_window=0 wgc_screen=1 wgc_window=1 wgc_fallback=1',
            '2026-06-02T19:44:42.000Z native-webrtc Inter Galactic desktop capture pipeline native_source=2560x1440 native_window_rect=2560x1440 requested_max=1920x1080 content=1920x1080 pre_encode=1920x1080 target_fps=30 native_fps=27.3 scale=down canvas=fixed crop_region=false capturer=WgcCapturerWin capturer_id=4 dirty_region_mode=force-full-frame',
            '2026-06-02T19:44:42.000Z native-webrtc Inter Galactic desktop capture cadence target_delay_ms=33 avg_capture_call_ms=24.0 max_capture_call_ms=154 scheduled_delay_ms=0 calls=30 submitted_fps=27.2 temp_errors=0 permanent_errors=0 avg_source_capture_ms=23.8 max_source_capture_ms=153 source_capture_count=30 avg_callback_entry_delay_ms=23.0 max_callback_entry_delay_ms=151 avg_result_callback_ms=1.0 max_result_callback_ms=3.0 avg_acquire_wait_ms=23.5 max_acquire_wait_ms=153 avg_post_callback_wait_ms=0.0 max_post_callback_wait_ms=0.0 avg_unaccounted_wait_ms=0.5 max_unaccounted_wait_ms=2.0 callback_count=30',
            '2026-06-02T19:44:42.000Z native-webrtc Inter Galactic desktop capture frame cadence new_fps=27.3 submitted_fps=27.3 max_interval_ms=195.9 p95_interval_ms=74.1 duplicated_frames=0 stale_reuse=0 wait_timeouts=0 permanent_errors=0 frames=30',
            '2026-06-02T19:44:42.000Z native-webrtc Inter Galactic desktop capture frame timing avg_convert_ms=0.9 avg_scale_ms=0.8 avg_on_frame_ms=0.2 avg_callback_ms=1.9 max_callback_ms=4.2 updated_region_empty=0 updated_region_nonempty=120 updated_region_rects=120 updated_region_max_rects=1 avg_updated_region_area_ratio=1 max_updated_region_area_ratio=1 updated_region_full_frames=120 updated_region_tiny_frames=0 frames=120',
            '2026-06-02T19:44:43.000Z native-webrtc Inter Galactic Media Foundation H.264 encoder timing frame=120 total_ms=5.6 process_output_ms=0.1 slow=no',
          ]),
          samples: [
            StreamTestSample(
              elapsed: const Duration(seconds: 1),
              snapshot: _snapshot(
                width: 1920,
                height: 1080,
                fps: 26.7,
                captureFps: 26.7,
                encodeFps: 26.7,
                sendFps: 26.7,
                averageEncodeTimeMs: 45,
                requestedWidth: 1920,
                requestedHeight: 1080,
                requestedBitrateBps: 4000000,
                bitrateBps: 4000000,
                lossPercent: 0,
                rttMs: 3,
              ),
            ),
          ],
        );

        expect(result.score.bottleneck.label, 'native_capture_limited');
        expect(
          result.score.bottleneck.reasons.join(' '),
          contains('native p95 frame interval 74ms'),
        );
        expect(
          result.score.bottleneck.reasons.join(' '),
          contains('native MediaFoundation encoder averages 5.6ms'),
        );
      },
    );

    test('parses native capture frame timing breakdown', () {
      final diagnostics = StreamTestNativeDiagnostics.fromMarkers(const [
        '2026-05-19T14:37:42.000Z native-webrtc Inter Galactic desktop capture frame timing avg_convert_ms=1.2 avg_scale_ms=0.8 avg_on_frame_ms=0.4 avg_callback_ms=2.9 max_callback_ms=5.1 updated_region_empty=3 updated_region_nonempty=49 updated_region_rects=60 updated_region_max_rects=4 avg_updated_region_area_ratio=0.125 max_updated_region_area_ratio=1 updated_region_full_frames=2 updated_region_tiny_frames=7 frames=52',
      ]);

      expect(diagnostics.averageFrameConvertMs, 1.2);
      expect(diagnostics.averageFrameScaleMs, 0.8);
      expect(diagnostics.averageFrameOnFrameMs, 0.4);
      expect(diagnostics.averageFrameCallbackMs, 2.9);
      expect(diagnostics.maxFrameCallbackMs, 5.1);
      expect(diagnostics.updatedRegionEmptyCount, 3);
      expect(diagnostics.updatedRegionNonEmptyCount, 49);
      expect(diagnostics.updatedRegionRectCount, 60);
      expect(diagnostics.updatedRegionMaxRectCount, 4);
      expect(diagnostics.averageUpdatedRegionAreaRatio, 0.125);
      expect(diagnostics.maxUpdatedRegionAreaRatio, 1);
      expect(diagnostics.updatedRegionFullFrameCount, 2);
      expect(diagnostics.updatedRegionTinyFrameCount, 7);
      expect(
        diagnostics.summaryLabel,
        contains('frame_callback=3ms avg / 5ms max'),
      );
      expect(
        diagnostics.summaryLabel,
        contains('updated_region=49 dirty / 3 empty'),
      );
      expect(
        diagnostics.summaryLabel,
        contains('updated_region_shape=rects=60 max=4'),
      );
      expect(
        diagnostics.toJson(),
        allOf(
          containsPair('averageFrameScaleMs', 0.8),
          containsPair('updatedRegionRectCount', 60),
          containsPair('averageUpdatedRegionAreaRatio', 0.125),
        ),
      );
    });

    test('distinguishes backends by native p95 frame gaps in the score', () {
      StreamTestPresetResult resultFor({
        required String backend,
        required double nativeFps,
        required double captureCallMs,
        required double sourceCaptureMs,
        required double p95Ms,
        required double maxMs,
      }) {
        final startedAt = DateTime.utc(2026, 6, 2, 15, 39);
        return StreamTestPresetResult(
          profile: ScreenShareProfileConfig.smooth,
          windowsCaptureBackendMode:
              WindowsScreenCaptureBackendModeDetails.fromConstraintValue(
                backend,
              ),
          startedAt: startedAt,
          endedAt: startedAt.add(const Duration(seconds: 30)),
          nativeDiagnostics: StreamTestNativeDiagnostics.fromMarkers([
            '2026-06-02T15:39:40.000Z native-webrtc Inter Galactic desktop capture options type=window mode=$backend detect_updated_region=1 directx=1 crop_window=0 wgc_screen=0 wgc_window=0 wgc_fallback=0',
            '2026-06-02T15:39:41.000Z native-webrtc Inter Galactic desktop capture pipeline native_source=2560x1440 native_window_rect=2560x1440 requested_max=1280x720 content=1280x720 pre_encode=1280x720 target_fps=37.037 native_fps=$nativeFps scale=down canvas=fixed crop_region=false',
            '2026-06-02T15:39:41.000Z native-webrtc Inter Galactic desktop capture cadence target_delay_ms=27 avg_capture_call_ms=$captureCallMs max_capture_call_ms=$maxMs scheduled_delay_ms=0 calls=30 submitted_fps=$nativeFps temp_errors=0 permanent_errors=0 avg_source_capture_ms=$sourceCaptureMs max_source_capture_ms=$maxMs source_capture_count=30',
            '2026-06-02T15:39:41.000Z native-webrtc Inter Galactic desktop capture frame cadence new_fps=$nativeFps submitted_fps=0 max_interval_ms=$maxMs p95_interval_ms=$p95Ms duplicated_frames=0 stale_reuse=0 wait_timeouts=0 permanent_errors=0 frames=30',
            '2026-06-02T15:39:41.000Z native-webrtc Inter Galactic Media Foundation H.264 encoder timing frame=120 total_ms=2.4 process_output_ms=0.1 slow=no',
          ]),
          samples: [
            StreamTestSample(
              elapsed: const Duration(seconds: 1),
              snapshot: _snapshot(
                width: 1280,
                height: 720,
                fps: 18,
                captureFps: 18,
                encodeFps: 18,
                sendFps: 18,
                bitrateBps: 1500000,
                lossPercent: 0,
                rttMs: 3,
              ),
            ),
          ],
        );
      }

      final appDefault = resultFor(
        backend: 'default',
        nativeFps: 16,
        captureCallMs: 62,
        sourceCaptureMs: 54,
        p95Ms: 123,
        maxMs: 220,
      );
      final directX = resultFor(
        backend: 'directx-only',
        nativeFps: 18,
        captureCallMs: 55,
        sourceCaptureMs: 49,
        p95Ms: 67,
        maxMs: 155,
      );

      expect(appDefault.score.bottleneck.label, 'native_capture_limited');
      expect(directX.score.bottleneck.label, 'native_capture_limited');
      expect(directX.score.stableFps, greaterThan(appDefault.score.stableFps));
      expect(
        directX.score.totalScore,
        greaterThan(appDefault.score.totalScore),
      );
    });

    test('parses native capture cadence and crop state', () {
      final diagnostics = StreamTestNativeDiagnostics.fromMarkers(const [
        '2026-05-19T14:37:41.000Z native-webrtc Inter Galactic desktop capture frame size source=2560x1440 max=1280x720 output=1280x720 crop_region=false',
        '2026-05-19T14:37:42.000Z native-webrtc Inter Galactic desktop capture cadence target_delay_ms=33 avg_capture_call_ms=18.0 max_capture_call_ms=44 scheduled_delay_ms=15 calls=60 submitted_fps=29.8 temp_errors=2 permanent_errors=0 avg_source_capture_ms=12.0 max_source_capture_ms=30 source_capture_count=60 avg_callback_entry_delay_ms=14.0 max_callback_entry_delay_ms=35.0 avg_result_callback_ms=3.0 max_result_callback_ms=7.0 avg_acquire_wait_ms=15.0 max_acquire_wait_ms=39.0 avg_post_callback_wait_ms=0.5 max_post_callback_wait_ms=3.0 avg_unaccounted_wait_ms=2.5 max_unaccounted_wait_ms=6.0 callback_count=60',
        '2026-05-19T14:37:43.000Z native-webrtc Inter Galactic desktop capture frame cadence new_fps=28.5 submitted_fps=29.0 max_interval_ms=60.0 p95_interval_ms=44.0 duplicated_frames=1 stale_reuse=1 wait_timeouts=2 permanent_errors=0 frames=58',
      ]);

      expect(diagnostics.cropRegion, isFalse);
      expect(diagnostics.averageSubmittedFps, closeTo(29.4, 0.1));
      expect(diagnostics.maxFrameIntervalMs, 60);
      expect(diagnostics.p95FrameIntervalMs, 44);
      expect(diagnostics.captureWaitTimeoutCount, 2);
      expect(diagnostics.averageCaptureResultCallbackMs, 3);
      expect(diagnostics.maxCaptureResultCallbackMs, 7);
      expect(diagnostics.averageCaptureAcquireWaitMs, 15);
      expect(diagnostics.maxCaptureAcquireWaitMs, 39);
      expect(diagnostics.averageSourceCaptureMs, 12);
      expect(diagnostics.maxSourceCaptureMs, 30);
      expect(diagnostics.averageCallbackEntryDelayMs, 14);
      expect(diagnostics.maxCallbackEntryDelayMs, 35);
      expect(diagnostics.averagePostCallbackWaitMs, 0.5);
      expect(diagnostics.maxPostCallbackWaitMs, 3);
      expect(diagnostics.averageUnaccountedWaitMs, 2.5);
      expect(diagnostics.maxUnaccountedWaitMs, 6);
      expect(diagnostics.dominantCaptureDelayStageLabel, 'callback_entry');
      expect(
        diagnostics.capturePhaseSummaryLabel,
        contains('dominant=callback_entry'),
      );
      expect(diagnostics.sourceCaptureSampleCount, 60);
      expect(diagnostics.captureResultCallbackCount, 60);
      expect(diagnostics.duplicatedFrameCount, 1);
      expect(diagnostics.staleFrameReuseCount, 1);
      expect(
        diagnostics.summaryLabel,
        contains('frame_interval=44ms p95 / 60ms max'),
      );
      expect(
        diagnostics.summaryLabel,
        contains('acquire_wait=15ms avg / 39ms max'),
      );
      expect(
        diagnostics.summaryLabel,
        contains('source_capture=12ms avg / 30ms max'),
      );
      expect(
        diagnostics.summaryLabel,
        contains('capture_phase=dominant=callback_entry'),
      );
      expect(
        diagnostics.summaryLabel,
        contains('callback_entry=14ms avg / 35ms max'),
      );
      expect(
        diagnostics.summaryLabel,
        contains('unaccounted_wait=3ms avg / 6ms max'),
      );
      expect(
        diagnostics.toJson(),
        allOf(
          containsPair('cropRegion', false),
          containsPair('averageUnaccountedWaitMs', 2.5),
          containsPair('dominantCaptureDelayStage', 'callback_entry'),
        ),
      );
    });

    test('weights native source capture averages by sample count', () {
      final diagnostics = StreamTestNativeDiagnostics.fromMarkers(const [
        '2026-05-19T14:37:42.000Z native-webrtc Inter Galactic desktop capture cadence target_delay_ms=33 avg_capture_call_ms=10 max_capture_call_ms=12 scheduled_delay_ms=15 calls=60 submitted_fps=30 temp_errors=0 permanent_errors=0 avg_source_capture_ms=12.0 max_source_capture_ms=30 source_capture_count=60',
        '2026-05-19T14:37:43.000Z native-webrtc Inter Galactic desktop capture cadence target_delay_ms=33 avg_capture_call_ms=10 max_capture_call_ms=12 scheduled_delay_ms=15 calls=20 submitted_fps=30 temp_errors=0 permanent_errors=0 avg_source_capture_ms=30.0 max_source_capture_ms=40 source_capture_count=20',
      ]);

      expect(diagnostics.averageSourceCaptureMs, 16.5);
      expect(diagnostics.sourceCaptureSampleCount, 80);
      expect(diagnostics.maxSourceCaptureMs, 40);
    });

    test('parses WGC substage timing diagnostics', () {
      final diagnostics = StreamTestNativeDiagnostics.fromMarkers(const [
        '2026-06-02T22:05:00.000Z native-webrtc Inter Galactic desktop capture cadence target_delay_ms=33 avg_capture_call_ms=48.0 max_capture_call_ms=142 scheduled_delay_ms=0 calls=30 submitted_fps=22 temp_errors=0 permanent_errors=0 avg_source_capture_ms=46.0 max_source_capture_ms=140 source_capture_count=30',
        '2026-06-02T22:05:00.100Z native-webrtc Inter Galactic WGC frame timing source_type=window source_id=123 size=2560x1440 allow_zero_hertz=true calls=30 successes=30 source_not_capturable=0 ensure_calls=30 ensure_sleeps=0 process_calls=30 process_successes=30 frame_pool_empty=0 frame_pool_reuse=0 capture_frame_null=0 mapped_texture_creates=1 resizes=0 frame_pool_recreates=0 avg_get_frame_ms=46 max_get_frame_ms=140 avg_ensure_frame_ms=45 max_ensure_frame_ms=139 avg_process_frame_ms=44 max_process_frame_ms=138 avg_try_get_frame_ms=0.2 max_try_get_frame_ms=1 avg_surface_ms=0.1 max_surface_ms=1 avg_texture_ms=0.1 max_texture_ms=1 avg_content_size_ms=0.1 max_content_size_ms=1 avg_copy_texture_ms=0.2 max_copy_texture_ms=1 avg_map_texture_ms=36 max_map_texture_ms=130 avg_copy_rows_ms=5 max_copy_rows_ms=12 avg_monitor_scale_ms=0.1 max_monitor_scale_ms=1 avg_zero_hertz_ms=3 max_zero_hertz_ms=8',
      ]);

      expect(diagnostics.observedCapturerLabel, 'wgc');
      expect(diagnostics.wgcCaptureCalls, 30);
      expect(diagnostics.wgcCaptureSuccessCount, 30);
      expect(diagnostics.averageWgcMapTextureMs, 36);
      expect(diagnostics.maxWgcMapTextureMs, 130);
      expect(diagnostics.averageWgcCopyRowsMs, 5);
      expect(diagnostics.dominantWgcFrameStageLabel, 'map_texture');
      expect(
        diagnostics.dominantCaptureDelayStageLabel,
        'source_capture/map_texture',
      );
      expect(
        diagnostics.wgcFrameSummaryLabel,
        contains('dominant=map_texture'),
      );
      expect(
        diagnostics.toJson(),
        allOf(
          containsPair('wgcCaptureCalls', 30),
          containsPair('dominantWgcFrameStage', 'map_texture'),
        ),
      );

      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: DateTime.utc(2026, 6, 2, 22, 5),
        endedAt: DateTime.utc(2026, 6, 2, 22, 5, 2),
        nativeDiagnostics: diagnostics,
        samples: [
          StreamTestSample(
            elapsed: const Duration(seconds: 1),
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 22,
              captureFps: 22,
              encodeFps: 22,
              sendFps: 22,
              bitrateBps: 1800000,
              lossPercent: 0,
              rttMs: 20,
            ),
          ),
        ],
      );
      expect(
        result.score.bottleneck.reasons.join(' '),
        contains('WGC substage dominant=map_texture'),
      );
    });

    test('keeps rare WGC frame-pool misses from masking map timing', () {
      final diagnostics = StreamTestNativeDiagnostics.fromMarkers(const [
        '2026-06-03T13:38:41.000Z native-webrtc Inter Galactic WGC frame timing source_type=window source_id=bg3 size=2560x1440 allow_zero_hertz=true calls=886 successes=884 source_not_capturable=0 ensure_calls=886 ensure_sleeps=0 process_calls=886 process_successes=884 frame_pool_empty=1 frame_pool_reuse=1 capture_frame_null=2 mapped_texture_creates=1 resizes=0 frame_pool_recreates=0 avg_get_frame_ms=68 max_get_frame_ms=239 avg_ensure_frame_ms=67 max_ensure_frame_ms=238 avg_process_frame_ms=66 max_process_frame_ms=237 avg_try_get_frame_ms=0.2 max_try_get_frame_ms=1 avg_surface_ms=0.1 max_surface_ms=1 avg_texture_ms=0.1 max_texture_ms=1 avg_content_size_ms=0.1 max_content_size_ms=1 avg_copy_texture_ms=0.2 max_copy_texture_ms=1 avg_map_texture_ms=64 max_map_texture_ms=230 avg_copy_rows_ms=3 max_copy_rows_ms=10 avg_monitor_scale_ms=0.1 max_monitor_scale_ms=1 avg_zero_hertz_ms=0 max_zero_hertz_ms=0',
      ]);

      expect(diagnostics.dominantWgcFrameStageLabel, 'map_texture');
      expect(
        diagnostics.wgcFrameSummaryLabel,
        contains('dominant=map_texture'),
      );
    });

    test('reports substantial WGC frame-pool misses when timing is absent', () {
      final diagnostics = StreamTestNativeDiagnostics.fromMarkers(const [
        '2026-06-03T13:38:41.000Z native-webrtc Inter Galactic WGC frame timing source_type=window source_id=bg3 size=2560x1440 allow_zero_hertz=true calls=20 successes=12 source_not_capturable=0 ensure_calls=20 ensure_sleeps=0 process_calls=20 process_successes=12 frame_pool_empty=6 frame_pool_reuse=2 capture_frame_null=0 mapped_texture_creates=1 resizes=0 frame_pool_recreates=0',
      ]);

      expect(diagnostics.dominantWgcFrameStageLabel, 'frame_pool_empty');
      expect(
        diagnostics.wgcFrameSummaryLabel,
        contains('dominant=frame_pool_empty'),
      );
    });

    test('parses window-GDI substage timing diagnostics', () {
      final diagnostics = StreamTestNativeDiagnostics.fromMarkers(const [
        '2026-06-03T16:19:30.000Z native-webrtc Inter Galactic desktop capture pipeline native_source=2560x1440 native_window_rect=2560x1440 requested_max=1280x720 content=1280x720 pre_encode=1280x720 target_fps=30 native_fps=17 scale=down canvas=fixed crop_region=false capturer=window-gdi capturer_id=3 dirty_region_mode=auto',
        '2026-06-03T16:19:31.000Z native-webrtc Inter Galactic desktop capture cadence target_delay_ms=33 avg_capture_call_ms=58.0 max_capture_call_ms=160 scheduled_delay_ms=0 calls=34 submitted_fps=17 temp_errors=0 permanent_errors=0 avg_source_capture_ms=53.0 max_source_capture_ms=158 source_capture_count=34',
        '2026-06-03T16:19:31.100Z native-webrtc Inter Galactic window GDI frame timing source_type=window source_id=123 capture_mode=default calls=34 successes=34 temp_errors=0 permanent_errors=0 hidden_or_minimized=0 rect_fail=0 dc_fail=0 frame_create_fail=0 original_size=2560x1440 cropped_size=2560x1392 frame_size=2560x1392 print_full_calls=34 print_full_successes=34 print_fallback_calls=0 print_fallback_successes=0 bitblt_calls=0 bitblt_successes=0 final_print_full=34 final_print_fallback=0 final_bitblt=0 final_none=0 black_frame_count=1 low_variance_frame_count=2 owned_window_frames=0 owned_capture_calls=0 owned_capture_successes=0 avg_total_ms=53 max_total_ms=158 avg_rect_ms=0.2 max_rect_ms=1 avg_visibility_ms=0.1 max_visibility_ms=1 avg_get_dc_ms=0.1 max_get_dc_ms=1 avg_get_dc_size_ms=0.1 max_get_dc_size_ms=1 avg_create_frame_ms=1.5 max_create_frame_ms=6 avg_mem_dc_ms=0.2 max_mem_dc_ms=1 avg_print_full_ms=48 max_print_full_ms=150 avg_print_fallback_ms=0 max_print_fallback_ms=0 avg_bitblt_ms=0 max_bitblt_ms=0 avg_cleanup_ms=0.2 max_cleanup_ms=1 avg_crop_ms=2 max_crop_ms=8 avg_owned_enum_ms=0 max_owned_enum_ms=0 avg_owned_capture_ms=0 max_owned_capture_ms=0 avg_owned_composite_ms=0 max_owned_composite_ms=0',
      ]);

      expect(diagnostics.observedCapturerLabel, 'window-gdi');
      expect(diagnostics.gdiCaptureCalls, 34);
      expect(diagnostics.gdiCaptureSuccessCount, 34);
      expect(diagnostics.averageGdiPrintFullMs, 48);
      expect(diagnostics.maxGdiPrintFullMs, 150);
      expect(diagnostics.gdiCroppedResolutionLabel, '2560x1392');
      expect(diagnostics.windowGdiCaptureModeLabel, 'default');
      expect(diagnostics.dominantGdiFrameStageLabel, 'print_full');
      expect(diagnostics.gdiFinalPrintFullCount, 34);
      expect(diagnostics.gdiBlackFrameCount, 1);
      expect(diagnostics.gdiLowVarianceFrameCount, 2);
      expect(
        diagnostics.dominantCaptureDelayStageLabel,
        'source_capture/print_full',
      );
      expect(diagnostics.gdiFrameSummaryLabel, contains('dominant=print_full'));
      expect(
        diagnostics.gdiFrameSummaryLabel,
        contains('final_methods=[print_full=34'),
      );
      expect(
        diagnostics.toJson(),
        allOf(
          containsPair('gdiCaptureCalls', 34),
          containsPair('windowGdiCaptureMode', 'default'),
          containsPair('gdiFinalPrintFullCount', 34),
          containsPair('gdiBlackFrameCount', 1),
          containsPair('dominantGdiFrameStage', 'print_full'),
        ),
      );

      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: DateTime.utc(2026, 6, 3, 16, 19),
        endedAt: DateTime.utc(2026, 6, 3, 16, 20),
        nativeDiagnostics: diagnostics,
        samples: [
          StreamTestSample(
            elapsed: const Duration(seconds: 1),
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 17,
              captureFps: 17,
              encodeFps: 17,
              sendFps: 17,
              bitrateBps: 1800000,
              lossPercent: 0,
              rttMs: 4,
            ),
          ),
        ],
      );
      expect(result.score.bottleneck.label, 'native_capture_limited');
      expect(
        result.score.bottleneck.reasons.join(' '),
        contains('window-GDI substage dominant=print_full'),
      );
      expect(
        result.score.bottleneck.recommendedNextAction,
        'fix window-GDI substage',
      );
      expect(
        streamTestRecommendedNextActions,
        contains(result.score.bottleneck.recommendedNextAction),
      );
      final coverageItems =
          result.diagnosticCoverage.toJson()['items'] as List<Object?>;
      expect(
        coverageItems,
        contains(
          isA<Map<String, Object?>>()
              .having(
                (item) => item['category'],
                'category',
                'window-GDI substage markers',
              )
              .having((item) => item['status'], 'status', 'available'),
        ),
      );
      final run = StreamTestRunResult(
        startedAt: DateTime.utc(2026, 6, 3, 16, 19),
        endedAt: DateTime.utc(2026, 6, 3, 16, 20),
        targetLabel: 'Test room',
        roomId: '!test:ourgalaxy.space',
        config: const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 1),
        ),
        presetResults: [result],
      );
      expect(run.toMarkdown(), contains('GDI Substage'));
    });

    test('game capture markers override stale window-GDI diagnostics', () {
      final diagnostics = StreamTestNativeDiagnostics.fromMarkers(const [
        '2026-06-05T02:33:54.368Z native-webrtc Inter Galactic window GDI frame timing source_type=window source_id=263012 capture_mode=default calls=16 successes=16 temp_errors=0 permanent_errors=0 hidden_or_minimized=3 rect_fail=0 dc_fail=0 frame_create_fail=0 original_size=2559x1440 cropped_size=2559x1440 frame_size=1x1 print_full_calls=13 print_full_successes=13 print_fallback_calls=0 print_fallback_successes=0 bitblt_calls=0 bitblt_successes=0 final_print_full=13 final_print_fallback=0 final_bitblt=0 final_none=3 black_frame_count=4 low_variance_frame_count=4 avg_total_ms=49 max_total_ms=85 avg_print_full_ms=46 max_print_full_ms=80',
        '2026-06-05T02:33:55.338Z native-webrtc game_capture_webrtc_source shared_textures_opened generation=1 count=3 source=2560x1440 format=24',
        '2026-06-05T02:33:56.010Z native-webrtc game_capture_webrtc_source proof frame=1 source=2560x1440 output=1280x720 format=24 visible=true minLuma=3 maxLuma=211 nonzeroSamples=930 samples=1024 wrote=true path="repo-fixtures/proof.bmp"',
        '2026-06-05T02:33:56.020Z native-webrtc game_capture_webrtc_source i420_proof frame=1 source=2560x1440 output=1280x720 format=24 visible=false minLuma=0 maxLuma=4 nonzeroSamples=2 samples=1024 wrote=true conversionFailed=false path="repo-fixtures/proof-i420.bmp"',
        '2026-06-05T02:34:00.382Z native-webrtc game_capture_webrtc_source stats source=2560x1440 output=1280x720 format=24 fps=30.5 submitted=142 repeated=5 copied=240 dropped=0 overwritten=237 gpuScaled=140 gpuScaleFailures=0 cpuFallback=2 gpuScaleMs=0.3 copyMs=0.4 mapMs=13.2 convertMs=19.4 sourceFrameIndex=240 lastSubmittedSourceFrameIndex=239 sourceFrameRegressions=0 sharedSlotMismatches=0 timestampMode=paced timestampDeltaMs=33.3 timestampDeltaMaxMs=33.3 timestampSamples=141 timestampTotalDeltaMs=33.4 timestampTotalDeltaMaxMs=36.2 timestampTotalSamples=141 timestampAdjustments=0 deliveryWallDeltaMs=33.4 deliveryWallDeltaMaxMs=36.2 deliveryWallSamples=141 sourceQpcDeltaMs=16.7 sourceQpcDeltaMaxMs=19.0 sourceQpcSamples=141 sourceQpcRegressions=0 mapFailures=0 convertFailures=0 proofFrames=1 visibleProofFrames=1 i420ProofFrames=1 visibleI420ProofFrames=0',
      ]);

      expect(diagnostics.observedCapturerLabel, 'game-d3d11-hook');
      expect(diagnostics.nativeSourceResolutionLabel, '2560x1440');
      expect(diagnostics.preEncodeResolutionLabel, '1280x720');
      expect(diagnostics.averageGameCaptureFps, 30.5);
      expect(diagnostics.gameCaptureSubmittedFrames, 142);
      expect(diagnostics.gameCaptureGpuScaledFrames, 140);
      expect(diagnostics.gameCaptureGpuScaleFailures, 0);
      expect(diagnostics.gameCaptureCpuFallbackFrames, 2);
      expect(diagnostics.averageGameCaptureGpuScaleMs, 0.3);
      expect(diagnostics.gameCaptureTimestampMode, 'paced');
      expect(diagnostics.averageGameCaptureTimestampDeltaMs, 33.3);
      expect(diagnostics.maxGameCaptureTimestampDeltaMs, 33.3);
      expect(diagnostics.gameCaptureTimestampSamples, 141);
      expect(diagnostics.gameCaptureTimestampAdjustments, 0);
      expect(diagnostics.averageGameCaptureDeliveryWallDeltaMs, 33.4);
      expect(diagnostics.maxGameCaptureDeliveryWallDeltaMs, 36.2);
      expect(diagnostics.gameCaptureDeliveryWallSamples, 141);
      expect(diagnostics.averageGameCaptureSourceQpcDeltaMs, 16.7);
      expect(diagnostics.maxGameCaptureSourceQpcDeltaMs, 19.0);
      expect(diagnostics.gameCaptureSourceQpcSamples, 141);
      expect(diagnostics.gameCaptureSourceQpcRegressions, 0);
      expect(diagnostics.gameCaptureProofVisible, isTrue);
      expect(diagnostics.gameCaptureProofPath, 'repo-fixtures/proof.bmp');
      expect(diagnostics.gameCaptureI420ProofVisible, isFalse);
      expect(
        diagnostics.gameCaptureI420ProofPath,
        'repo-fixtures/proof-i420.bmp',
      );
      expect(
        diagnostics.gameCaptureFrameSummaryLabel,
        allOf(
          contains('proof=1/1 visible'),
          contains('i420_proof=1/0 not_visible'),
          contains('gpu_scaled=140'),
          contains('cpu_fallback=2'),
          contains('timestamp=paced'),
          contains('timestamp_delta=33ms/33ms'),
          contains('delivery_wall_delta=33ms/36ms'),
        ),
      );
      expect(
        diagnostics.cpuReadbackAttributionLabel,
        contains('game_capture=[source=2560x1440'),
      );
      expect(
        diagnostics.summaryLabel,
        allOf(
          contains('wgc_frame=[not_applicable_game_hook]'),
          contains('gdi_frame=[not_applicable_game_hook]'),
          isNot(contains('gdi_frame=[dominant=print_full')),
        ),
      );
      expect(
        diagnostics.toJson(),
        allOf(
          containsPair('observedCapturer', 'game-d3d11-hook'),
          containsPair('gameCaptureOutputWidth', 1280),
          containsPair('gameCaptureGpuScaledFrames', 140),
          containsPair('gameCaptureCpuFallbackFrames', 2),
          containsPair('gameCaptureTimestampMode', 'paced'),
          containsPair('maxGameCaptureTimestampDeltaMs', 33.3),
          containsPair('maxGameCaptureDeliveryWallDeltaMs', 36.2),
        ),
      );
      expect(
        diagnostics.toJson(),
        allOf(
          containsPair('gameCaptureProofVisible', true),
          containsPair('gameCaptureI420ProofVisible', false),
        ),
      );
    });

    test('parses game-capture backend contract markers', () {
      final diagnostics = StreamTestNativeDiagnostics.fromMarkers(const [
        '2026-06-13T16:00:00.000Z native-webrtc game_capture_webrtc_source stats source=2560x1440 output=1280x720 format=24 backendContractVersion=2 sourceApi=d3d11 sourceApiId=1 sourceFormat=r10g10b10a2 sourceFormatId=3 colorSpace=unknown syncKind=event readyState=ready failureReason=none fps=30.0 submitted=300 copied=301 gpuScaled=300 gpuScaleFailures=0 cpuFallback=0 nativeNv12Submitted=300 nativeNv12Failures=0 readbackQueued=0 readbackReady=0 readbackNotReady=0 sourceFrameIndex=301 lastSubmittedSourceFrameIndex=300 sourceFrameRegressions=0 sourceFrameGaps=1 sharedSlotMismatches=0 visibleSourceSeen=true',
      ]);

      expect(diagnostics.gameCaptureBackendContractVersion, 2);
      expect(diagnostics.gameCaptureSourceApi, 'd3d11');
      expect(diagnostics.gameCaptureSourceApiId, 1);
      expect(diagnostics.gameCaptureSourceFormat, 'r10g10b10a2');
      expect(diagnostics.gameCaptureSourceFormatId, 3);
      expect(diagnostics.gameCaptureColorSpace, 'unknown');
      expect(diagnostics.gameCaptureSyncKind, 'event');
      expect(diagnostics.gameCaptureReadyState, 'ready');
      expect(diagnostics.gameCaptureFailureReason, 'none');
      expect(
        diagnostics.gameCaptureFrameSummaryLabel,
        allOf(
          contains('backend_contract=2'),
          contains('source_api=d3d11'),
          contains('source_format=r10g10b10a2'),
          contains('sync=event'),
          contains('ready=ready'),
          contains('failure=none'),
        ),
      );
      expect(
        diagnostics.toJson(),
        allOf(
          containsPair('gameCaptureBackendContractVersion', 2),
          containsPair('gameCaptureSourceApi', 'd3d11'),
          containsPair('gameCaptureSourceFormat', 'r10g10b10a2'),
          containsPair('gameCaptureSyncKind', 'event'),
          containsPair('gameCaptureReadyState', 'ready'),
          containsPair('gameCaptureFailureReason', 'none'),
        ),
      );

      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: DateTime.utc(2026, 6, 13, 16),
        endedAt: DateTime.utc(2026, 6, 13, 16, 0, 30),
        nativeDiagnostics: diagnostics,
        samples: [
          StreamTestSample(
            elapsed: const Duration(seconds: 1),
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 30,
              captureFps: 30,
              encodeFps: 30,
              sendFps: 30,
              bitrateBps: 1800000,
              lossPercent: 0,
              rttMs: 5,
            ),
          ),
        ],
      );
      final coverageItems =
          result.diagnosticCoverage.toJson()['items'] as List<Object?>;
      expect(
        coverageItems,
        contains(
          isA<Map<String, Object?>>()
              .having(
                (item) => item['category'],
                'category',
                'game-capture backend contract',
              )
              .having((item) => item['status'], 'status', 'available')
              .having(
                (item) => item['detail'],
                'detail',
                contains('api=d3d11'),
              ),
        ),
      );
    });

    test('surfaces visual freshness cadence diagnostics', () {
      final diagnostics = StreamTestNativeDiagnostics.fromMarkers(const [
        '2026-06-17T20:10:00.000Z native-webrtc game_capture_webrtc_source stats source=2560x1440 output=1280x720 format=24 fps=30.0 submitted=900 copied=901 gpuScaled=900 gpuScaleFailures=0 cpuFallback=0 nativeNv12Submitted=900 nativeNv12Failures=0 sourceFrameIndex=901 lastSubmittedSourceFrameIndex=900 sourceFrameRegressions=0 sharedSlotMismatches=0 visibleSourceSeen=true',
        '2026-06-17T20:10:10.000Z native-webrtc game_capture_visual_freshness stats sampleMode=receiver-recording sampleFrames=248 uniqueFrames=45 uniqueFps=5.4 longestStaleMs=667 longestStaleFrames=20 lowChangeFrames=203 artifactSet=true',
      ]);

      expect(diagnostics.hasGameCaptureVisualFreshnessEvidence, isTrue);
      expect(
        diagnostics.gameCaptureVisualFreshnessSampleMode,
        'receiver-recording',
      );
      expect(diagnostics.gameCaptureVisualFreshnessSampleFrames, 248);
      expect(diagnostics.gameCaptureVisualFreshnessUniqueFrames, 45);
      expect(diagnostics.averageGameCaptureVisualFreshnessUniqueFps, 5.4);
      expect(diagnostics.gameCaptureVisualFreshnessLongestStaleMs, 667);
      expect(diagnostics.gameCaptureVisualFreshnessLongestStaleFrames, 20);
      expect(diagnostics.gameCaptureVisualFreshnessLowChangeFrames, 203);
      expect(diagnostics.gameCaptureVisualFreshnessArtifactSet, isTrue);
      expect(
        diagnostics.gameCaptureFrameSummaryLabel,
        contains('visual_freshness=[mode=receiver-recording'),
      );
      expect(
        diagnostics.toJson(),
        containsPair('gameCaptureVisualFreshnessUniqueFrames', 45),
      );

      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: DateTime.utc(2026, 6, 17, 20, 10),
        endedAt: DateTime.utc(2026, 6, 17, 20, 11),
        nativeDiagnostics: diagnostics,
        samples: const [],
      );
      final coverageItems =
          result.diagnosticCoverage.toJson()['items'] as List<Object?>;
      expect(
        coverageItems,
        contains(
          isA<Map<String, Object?>>()
              .having(
                (item) => item['category'],
                'category',
                'visual freshness cadence',
              )
              .having((item) => item['status'], 'status', 'available'),
        ),
      );
    });

    test('marks D3D11 visual freshness cadence missing when absent', () {
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: DateTime.utc(2026, 6, 17, 20, 20),
        endedAt: DateTime.utc(2026, 6, 17, 20, 21),
        nativeDiagnostics: StreamTestNativeDiagnostics.fromMarkers(const [
          '2026-06-17T20:20:00.000Z native-webrtc game_capture_webrtc_source stats source=2560x1440 output=1280x720 format=24 fps=30.0 submitted=900 copied=901 gpuScaled=900 gpuScaleFailures=0 cpuFallback=0 nativeNv12Submitted=900 nativeNv12Failures=0 sourceFrameIndex=901 lastSubmittedSourceFrameIndex=900 sourceFrameRegressions=0 sharedSlotMismatches=0 visibleSourceSeen=true',
        ]),
        samples: const [],
      );

      final coverageItems =
          result.diagnosticCoverage.toJson()['items'] as List<Object?>;
      expect(
        coverageItems,
        contains(
          isA<Map<String, Object?>>()
              .having(
                (item) => item['category'],
                'category',
                'visual freshness cadence',
              )
              .having((item) => item['status'], 'status', 'missing'),
        ),
      );
      expect(
        result.diagnosticCoverage.missingFields,
        contains('visual unique FPS'),
      );
      final run = StreamTestRunResult(
        startedAt: DateTime.utc(2026, 6, 17, 20, 20),
        endedAt: DateTime.utc(2026, 6, 17, 20, 21),
        targetLabel: 'Test room',
        roomId: '!test:ourgalaxy.space',
        config: const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 60),
        ),
        presetResults: [result],
      );
      expect(run.toMarkdown(), contains('## Visual Freshness Diagnostics'));
      expect(run.toMarkdown(), contains('cannot prove'));
    });

    test('parses native NV12 source and encoder handoff markers', () {
      final diagnostics = StreamTestNativeDiagnostics.fromMarkers(const [
        '2026-06-08T19:37:30.000Z native-webrtc game_capture_webrtc_source stats sourceMode=dummy-nv12-live-sender source=1920x1080 output=1280x720 format=24 consumerAdapterLuid=0:123 consumerAdapterVendorId=4318 consumerAdapterDeviceId=8704 sourceAdapterLuid=unknown crossAdapterSuspected=unknown fps=30.0 submitted=292 repeated=0 copied=292 dropped=0 overwritten=0 gpuScaled=292 gpuScaleFailures=0 cpuFallback=0 deliverySkipNoQueued=3 deliveryFreshWakeAfterSkip=4 deliveryFreshImmediate=5 deliveryQueueDepth=2 deliverySubmitPrepMs=0.2 deliverySubmitPrepMaxMs=0.5 deliverySubmitPrepSamples=292 deliveryOnFrameCallMs=1.3 deliveryOnFrameCallMaxMs=2.4 deliveryOnFrameCallSamples=292 deliveryPostOnFrameMs=0.1 deliveryPostOnFrameMaxMs=0.3 deliveryPostOnFrameSamples=292 nativeBufferReleaseMs=0.04 nativeBufferReleaseMaxMs=0.08 nativeBufferReleaseSamples=292 nativeNv12Submitted=292 nativeNv12Failures=0 nativeNv12ReadyPolicy=fence nativeNv12FenceAvailable=true nativeNv12PendingPollMs=8 nativeNv12MaxPendingSlots=2 nativeNv12ReadyDrainDepth=2 nativeNv12FrameOwnership=owned_texture_copy nativeNv12OwnedCopies=140 nativeNv12OwnedCopyMs=0.04 nativeNv12OwnedCopyMaxMs=0.08 nativeNv12OwnedCopySamples=140 nativeNv12FenceSignaled=140 nativeNv12FenceReady=140 nativeNv12FenceSignalFailures=0 nativeNv12ConvertMs=0.015 nativeNv12ConvertMaxMs=0.031 nativeNv12ConvertSamples=140 nativeNv12BgraScaleDrawMs=0.2 nativeNv12BgraScaleDrawMaxMs=0.4 nativeNv12BgraScaleDrawSamples=140 nativeNv12VideoProcessorBltSubmitMs=0.1 nativeNv12VideoProcessorBltSubmitMaxMs=0.3 nativeNv12VideoProcessorBltSubmitSamples=140 nativeNv12VideoProcessorBltCpuSubmitMs=0.1 nativeNv12VideoProcessorBltCpuSubmitMaxMs=0.3 nativeNv12VideoProcessorBltCpuSubmitSamples=140 nativeNv12VideoProcessorBltToReadyMs=0.6 nativeNv12VideoProcessorBltToReadyMaxMs=1.2 nativeNv12VideoProcessorBltToReadySamples=140 nativeNv12VideoProcessorBltSubmitToFenceMs=0.6 nativeNv12VideoProcessorBltSubmitToFenceMaxMs=1.2 nativeNv12VideoProcessorBltSubmitToFenceSamples=140 nativeNv12VideoProcessorBltGpuExecutionMs=0.17 nativeNv12VideoProcessorBltGpuExecutionMaxMs=0.45 nativeNv12VideoProcessorBltGpuExecutionSamples=140 nativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs=0.43 nativeNv12VideoProcessorBltEstimatedGpuQueueDelayMaxMs=0.75 nativeNv12VideoProcessorBltEstimatedGpuQueueDelaySamples=140 nativeNv12VideoProcessorBltGpuTimestampFailures=1 nativeNv12VideoProcessorBltGpuTimestampNotReady=2 nativeNv12VideoProcessorBltGpuTimestampDisjoint=3 nativeNv12ReadyObservedImmediate=4 nativeNv12ReadyObservedPostFenceRegistration=7 nativeNv12ReadyObservedFenceEvent=90 nativeNv12ReadyObservedSourceEvent=11 nativeNv12ReadyObservedWaitOther=2 nativeNv12ReadyObservedLoopIdle=18 nativeNv12ReadyObservedDuplicateSkip=3 nativeNv12ReadyObservedPreSubmit=5 nativeNv12ReadyObservedWriteSlotScan=1 nativeNv12ReadyObservedUnknown=0 nativeNv12BltToReadyOver1x=6 nativeNv12BltToReadyOver2x=2 nativeNv12BltToReadyOver3x=1 nativeNv12BufferCreateMs=0.05 nativeNv12BufferCreateMaxMs=0.09 nativeNv12BufferCreateSamples=140 nativeNv12FrameReadyToQueueMs=0.8 nativeNv12FrameReadyToQueueMaxMs=1.5 nativeNv12FrameReadyToQueueSamples=140 nativeNv12ConversionStartAgeMs=0.3 nativeNv12ConversionStartAgeMaxMs=0.7 nativeNv12ConversionStartAgeSamples=140 nativeNv12GpuQueueBackoffEnabled=true nativeNv12GpuQueueBackoffThresholdFrames=2 nativeNv12GpuQueueBackoffDurationFrames=1 nativeNv12GpuQueueBackoffTriggered=4 nativeNv12GpuQueueBackoffSuppressed=9 nativeNv12GpuQueueBackoffSuppressedFresh=7 nativeNv12GpuQueueBackoffMs=33.3 nativeNv12GpuQueueBackoffMaxMs=34.1 nativeNv12GpuQueueBackoffSamples=4 nativeNv12GpuQueueBackoffTriggerBltToReadyMs=78.5 nativeNv12GpuQueueBackoffTriggerBltToReadyMaxMs=122.0 nativeNv12GpuQueueBackoffTriggerBltToReadySamples=4 nativeNv12GpuQueueBackoffSuppressedSourceAgeMs=18.2 nativeNv12GpuQueueBackoffSuppressedSourceAgeMaxMs=28.4 nativeNv12GpuQueueBackoffSuppressedSourceAgeSamples=9 nativeNv12StaleBeforeQueue=2 readbackQueued=0 readbackReady=0 readbackNotReady=0 readbackLatencyDropped=0 readbackMapAttempts=0 sourceFrameIndex=292 lastSubmittedSourceFrameIndex=292 sourceFrameRegressions=0 sourceFrameDuplicates=0 sourceFrameGaps=0 sharedSlotMismatches=0 sourceToSubmitMs=0.32 sourceToSubmitMaxMs=16.55 sourceToSubmitSamples=292 timestampMode=source-qpc timestampSourceQpcFrames=291 timestampPacedFallbackFrames=1 timestampRepeatedFrames=0 timestampDeltaMs=33.3 timestampDeltaMaxMs=48.0 timestampSamples=291 deliveryWallDeltaMs=33.3 deliveryWallDeltaMaxMs=48.0 deliveryWallSamples=292 visibleSourceSeen=true',
        '2026-06-08T19:37:30.100Z native-webrtc Inter Galactic Media Foundation H.264 encoder timing frame=292 total_ms=0.8 process_input_ms=0.1 process_output_ms=0.1 slow=no target_bitrate_bps=3000000 rate_control_mode=cbr input_path=native_nv12 native_input=yes native_sample_failed=no native_suspended=no native_ready_fence=yes native_ready_fence_timeout=no native_ready_fence_wait_ms=0.1 native_source_mode=dummy-nv12-live-sender native_source_format=103 native_source_frame=292 native_source_age_ms=0.4 native_source_age_at_create_ms=0.3 native_buffer_age_ms=0.2 native_sample_lifetime_ms=1.1 native_sample_lifetime_max_ms=1.1 native_sample_lifetime_samples=1 native_adapter_luid=0:123 native_adapter_vendor_id=4318 native_adapter_device_id=8704 outputs=0 output_bytes=0 queue=1 retained_samples=1 encoded_outputs=0 stage=ok_native_nv12',
      ]);

      expect(diagnostics.gameCaptureSourceMode, 'dummy-nv12-live-sender');
      expect(diagnostics.gameCaptureConsumerAdapterLuid, '0:123');
      expect(diagnostics.gameCaptureConsumerAdapterVendorId, 4318);
      expect(diagnostics.gameCaptureConsumerAdapterDeviceId, 8704);
      expect(diagnostics.gameCaptureSourceAdapterLuid, 'unknown');
      expect(diagnostics.gameCaptureCrossAdapterSuspected, 'unknown');
      expect(diagnostics.gameCaptureNativeNv12SubmittedFrames, 292);
      expect(diagnostics.gameCaptureDeliverySkipNoQueuedFrames, 3);
      expect(diagnostics.gameCaptureDeliveryFreshWakeAfterSkipFrames, 4);
      expect(diagnostics.gameCaptureDeliveryFreshImmediateFrames, 5);
      expect(diagnostics.gameCaptureDeliveryQueueDepth, 2);
      expect(diagnostics.averageGameCaptureDeliverySubmitPrepMs, 0.2);
      expect(diagnostics.maxGameCaptureDeliveryOnFrameCallMs, 2.4);
      expect(diagnostics.averageGameCaptureDeliveryPostOnFrameMs, 0.1);
      expect(diagnostics.maxGameCaptureNativeBufferReleaseMs, 0.08);
      expect(diagnostics.gameCaptureNativeNv12Failures, 0);
      expect(diagnostics.averageGameCaptureNativeNv12ConvertMs, 0.015);
      expect(diagnostics.maxGameCaptureNativeNv12ConvertMs, 0.031);
      expect(diagnostics.gameCaptureNativeNv12ConvertSamples, 140);
      expect(diagnostics.gameCaptureNativeNv12ReadyPolicy, 'fence');
      expect(diagnostics.gameCaptureNativeNv12FenceAvailable, isTrue);
      expect(diagnostics.gameCaptureNativeNv12PendingPollMs, 8);
      expect(diagnostics.gameCaptureNativeNv12MaxPendingSlots, 2);
      expect(diagnostics.gameCaptureNativeNv12ReadyDrainDepth, 2);
      expect(
        diagnostics.gameCaptureNativeNv12FrameOwnership,
        'owned_texture_copy',
      );
      expect(diagnostics.gameCaptureNativeNv12FenceSignaledFrames, 140);
      expect(diagnostics.gameCaptureNativeNv12FenceReadyFrames, 140);
      expect(diagnostics.gameCaptureNativeNv12FenceSignalFailures, 0);
      expect(diagnostics.gameCaptureNativeNv12OwnedCopies, 140);
      expect(diagnostics.averageGameCaptureNativeNv12OwnedCopyMs, 0.04);
      expect(diagnostics.maxGameCaptureNativeNv12OwnedCopyMs, 0.08);
      expect(diagnostics.gameCaptureNativeNv12OwnedCopySamples, 140);
      expect(diagnostics.averageGameCaptureNativeNv12BgraScaleDrawMs, 0.2);
      expect(
        diagnostics.averageGameCaptureNativeNv12VideoProcessorBltCpuSubmitMs,
        0.1,
      );
      expect(
        diagnostics
            .averageGameCaptureNativeNv12VideoProcessorBltSubmitToFenceMs,
        0.6,
      );
      expect(
        diagnostics.averageGameCaptureNativeNv12VideoProcessorBltGpuExecutionMs,
        0.17,
      );
      expect(
        diagnostics
            .maxGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs,
        0.75,
      );
      expect(
        diagnostics.gameCaptureNativeNv12VideoProcessorBltGpuTimestampFailures,
        1,
      );
      expect(
        diagnostics.gameCaptureNativeNv12VideoProcessorBltGpuTimestampNotReady,
        2,
      );
      expect(
        diagnostics.gameCaptureNativeNv12VideoProcessorBltGpuTimestampDisjoint,
        3,
      );
      expect(
        diagnostics.maxGameCaptureNativeNv12VideoProcessorBltToReadyMs,
        1.2,
      );
      expect(diagnostics.gameCaptureNativeNv12ReadyObservedImmediateFrames, 4);
      expect(
        diagnostics
            .gameCaptureNativeNv12ReadyObservedPostFenceRegistrationFrames,
        7,
      );
      expect(
        diagnostics.gameCaptureNativeNv12ReadyObservedFenceEventFrames,
        90,
      );
      expect(
        diagnostics.gameCaptureNativeNv12ReadyObservedSourceEventFrames,
        11,
      );
      expect(diagnostics.gameCaptureNativeNv12ReadyObservedWaitOtherFrames, 2);
      expect(diagnostics.gameCaptureNativeNv12ReadyObservedLoopIdleFrames, 18);
      expect(
        diagnostics.gameCaptureNativeNv12ReadyObservedDuplicateSkipFrames,
        3,
      );
      expect(diagnostics.gameCaptureNativeNv12ReadyObservedPreSubmitFrames, 5);
      expect(
        diagnostics.gameCaptureNativeNv12ReadyObservedWriteSlotScanFrames,
        1,
      );
      expect(diagnostics.gameCaptureNativeNv12ReadyObservedUnknownFrames, 0);
      expect(diagnostics.gameCaptureNativeNv12ReadyObservedFrames, 141);
      expect(diagnostics.gameCaptureNativeNv12BltToReadyOver1xFrames, 6);
      expect(diagnostics.gameCaptureNativeNv12BltToReadyOver2xFrames, 2);
      expect(diagnostics.gameCaptureNativeNv12BltToReadyOver3xFrames, 1);
      expect(diagnostics.averageGameCaptureNativeNv12ConversionStartAgeMs, 0.3);
      expect(diagnostics.maxGameCaptureNativeNv12ConversionStartAgeMs, 0.7);
      expect(diagnostics.gameCaptureNativeNv12GpuQueueBackoffEnabled, isTrue);
      expect(
        diagnostics.gameCaptureNativeNv12GpuQueueBackoffThresholdFrames,
        2,
      );
      expect(diagnostics.gameCaptureNativeNv12GpuQueueBackoffDurationFrames, 1);
      expect(
        diagnostics.gameCaptureNativeNv12GpuQueueBackoffTriggeredFrames,
        4,
      );
      expect(
        diagnostics.gameCaptureNativeNv12GpuQueueBackoffSuppressedFrames,
        9,
      );
      expect(
        diagnostics.gameCaptureNativeNv12GpuQueueBackoffSuppressedFreshFrames,
        7,
      );
      expect(diagnostics.averageGameCaptureNativeNv12GpuQueueBackoffMs, 33.3);
      expect(diagnostics.maxGameCaptureNativeNv12GpuQueueBackoffMs, 34.1);
      expect(diagnostics.gameCaptureNativeNv12GpuQueueBackoffSamples, 4);
      expect(
        diagnostics
            .averageGameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMs,
        78.5,
      );
      expect(
        diagnostics.maxGameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMs,
        122.0,
      );
      expect(
        diagnostics
            .gameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadySamples,
        4,
      );
      expect(
        diagnostics
            .averageGameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMs,
        18.2,
      );
      expect(
        diagnostics
            .maxGameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMs,
        28.4,
      );
      expect(
        diagnostics
            .gameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeSamples,
        9,
      );
      expect(diagnostics.gameCaptureNativeNv12StaleBeforeQueueFrames, 2);
      expect(diagnostics.gameCaptureReadbackQueuedFrames, 0);
      expect(diagnostics.encoderRateControlMode, 'cbr');
      expect(diagnostics.encoderTargetBitrateBps, 3000000);
      expect(diagnostics.encoderInputPaths, contains('native_nv12'));
      expect(diagnostics.encoderInputPathLabel, 'native_nv12');
      expect(diagnostics.encoderNativeInputFrames, 1);
      expect(diagnostics.encoderCpuI420InputFrames, 0);
      expect(diagnostics.encoderNativeSampleFailures, 0);
      expect(diagnostics.encoderNativeSuspendedFrames, 0);
      expect(diagnostics.encoderNativeReadyFenceFrames, 1);
      expect(diagnostics.encoderNativeReadyFenceTimeoutFrames, 0);
      expect(diagnostics.averageEncoderNativeReadyFenceWaitMs, 0.1);
      expect(diagnostics.maxEncoderNativeReadyFenceWaitMs, 0.1);
      expect(diagnostics.encoderNativeReadyFenceWaitSamples, 1);
      expect(diagnostics.encoderNativeSourceMode, 'dummy-nv12-live-sender');
      expect(diagnostics.encoderNativeSourceFormat, 103);
      expect(diagnostics.encoderNativeSourceFrameIndex, 292);
      expect(diagnostics.averageEncoderNativeSourceAgeMs, 0.4);
      expect(diagnostics.maxEncoderNativeSourceAgeMs, 0.4);
      expect(diagnostics.averageEncoderNativeSourceAgeAtCreateMs, 0.3);
      expect(diagnostics.averageEncoderNativeBufferAgeMs, 0.2);
      expect(diagnostics.averageEncoderNativeSampleLifetimeMs, 1.1);
      expect(diagnostics.maxEncoderNativeSampleLifetimeMs, 1.1);
      expect(diagnostics.encoderNativeSampleLifetimeSamples, 1);
      expect(diagnostics.encoderNativeAdapterLuid, '0:123');
      expect(diagnostics.encoderNativeAdapterVendorId, 4318);
      expect(diagnostics.encoderNativeAdapterDeviceId, 8704);
      expect(diagnostics.averageEncoderProcessInputMs, 0.1);
      expect(diagnostics.maxEncoderProcessOutputMs, 0.1);
      expect(diagnostics.encoderStages, contains('ok_native_nv12'));
      expect(diagnostics.encoderOutputFrames, 0);
      expect(diagnostics.encoderOutputBytes, 0);
      expect(diagnostics.encoderMaxQueueDepth, 1);
      expect(diagnostics.encoderMaxRetainedSamples, 1);
      expect(diagnostics.encoderMaxEncodedOutputs, 0);
      expect(diagnostics.gameCaptureTimestampMode, 'source-qpc');
      expect(diagnostics.gameCaptureTimestampSourceQpcFrames, 291);
      expect(diagnostics.gameCaptureTimestampPacedFallbackFrames, 1);
      expect(diagnostics.gameCaptureTimestampRepeatedFrames, 0);
      expect(diagnostics.nativeEncoderHandoffNoOutput, isTrue);
      final gameCaptureSummary = diagnostics.gameCaptureFrameSummaryLabel;
      expect(
        gameCaptureSummary,
        contains('source_mode=dummy-nv12-live-sender'),
      );
      expect(gameCaptureSummary, contains('consumer_adapter=0:123'));
      expect(gameCaptureSummary, contains('source_adapter=unknown'));
      expect(gameCaptureSummary, contains('cross_adapter=unknown'));
      expect(gameCaptureSummary, contains('delivery_fresh_wake_after_skip=4'));
      expect(gameCaptureSummary, contains('delivery_fresh_immediate=5'));
      expect(gameCaptureSummary, contains('delivery_queue_depth=2'));
      expect(gameCaptureSummary, contains('delivery_on_frame_call=1ms/2ms'));
      expect(gameCaptureSummary, contains('native_buffer_release=0ms/0ms'));
      expect(gameCaptureSummary, contains('native_nv12=292'));
      expect(gameCaptureSummary, contains('native_nv12_ready_policy=fence'));
      expect(gameCaptureSummary, contains('native_nv12_fence_available=true'));
      expect(gameCaptureSummary, contains('native_nv12_ready_drain_depth=2'));
      expect(
        gameCaptureSummary,
        contains('native_nv12_frame_ownership=owned_texture_copy'),
      );
      expect(gameCaptureSummary, contains('native_nv12_owned_copy=140'));
      expect(gameCaptureSummary, contains('native_nv12_fence=140/140/0'));
      expect(gameCaptureSummary, contains('native_nv12_failures=0'));
      expect(gameCaptureSummary, contains('native_nv12_convert=0ms/0ms'));
      expect(
        gameCaptureSummary,
        contains('native_nv12_bgra_scale_draw=0ms/0ms'),
      );
      expect(gameCaptureSummary, contains('native_nv12_blt_to_ready=1ms/1ms'));
      expect(
        gameCaptureSummary,
        contains('native_nv12_blt_gpu_execution=0ms/0ms'),
      );
      expect(
        gameCaptureSummary,
        contains('native_nv12_blt_estimated_gpu_queue_delay=0ms/1ms'),
      );
      expect(
        gameCaptureSummary,
        contains(
          'native_nv12_ready_observed=immediate:4 post:7 event:90 source:11',
        ),
      );
      expect(
        gameCaptureSummary,
        contains('native_nv12_blt_to_ready_over=6/2/1'),
      );
      expect(gameCaptureSummary, contains('native_nv12_stale_before_queue=2'));
      expect(
        gameCaptureSummary,
        contains(
          'native_nv12_gpu_queue_backoff=enabled:true '
          'threshold_frames:2 duration_frames:1 triggered:4 '
          'suppressed:9 fresh:7',
        ),
      );
      expect(
        gameCaptureSummary,
        contains('native_nv12_conversion_start_age=0ms/1ms'),
      );
      expect(gameCaptureSummary, contains('timestamp=source-qpc'));
      expect(gameCaptureSummary, contains('timestamp_source_qpc=291'));
      expect(gameCaptureSummary, contains('readback=0/0'));
      expect(
        diagnostics.summaryLabel,
        allOf(
          contains('encoder_rate_control=cbr'),
          contains('encoder_target_bitrate=3000000'),
          contains('encoder_input=native_nv12'),
          contains('encoder_native_input=1'),
          contains('encoder_cpu_i420_input=0'),
          contains('encoder_native_ready_fence=1'),
          contains('encoder_native_ready_fence_timeout=0'),
        ),
      );
      expect(
        diagnostics.summaryLabel,
        allOf(
          contains('encoder_native_source=dummy-nv12-live-sender/103'),
          contains('encoder_native_source_age=0ms avg / 0ms max'),
          contains('encoder_native_buffer_age=0ms avg / 0ms max'),
          contains('encoder_native_sample_lifetime=1ms avg / 1ms max'),
          contains('encoder_native_adapter=0:123'),
        ),
      );
      expect(
        diagnostics.summaryLabel,
        allOf(
          contains('encoder_native_ready_fence_wait=0ms avg / 0ms max'),
          contains('encoder_process_input=0ms avg / 0ms max'),
          contains('encoder_process_output=0ms avg / 0ms max'),
          contains('encoder_stages=ok_native_nv12'),
          contains('encoder_outputs=0'),
          contains('encoder_queue_max=1'),
        ),
      );
      final diagnosticsJson = diagnostics.toJson();
      expect(
        diagnosticsJson,
        containsPair('gameCaptureSourceMode', 'dummy-nv12-live-sender'),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureConsumerAdapterLuid', '0:123'),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureConsumerAdapterVendorId', 4318),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureSourceAdapterLuid', 'unknown'),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureNativeNv12SubmittedFrames', 292),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureDeliveryFreshWakeAfterSkipFrames', 4),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureDeliveryFreshImmediateFrames', 5),
      );
      expect(diagnosticsJson, containsPair('gameCaptureDeliveryQueueDepth', 2));
      expect(
        diagnosticsJson,
        containsPair('gameCaptureDeliveryOnFrameCallSamples', 292),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureTimestampSourceQpcFrames', 291),
      );
      expect(diagnosticsJson, containsPair('gameCaptureNativeNv12Failures', 0));
      expect(
        diagnosticsJson,
        containsPair('gameCaptureNativeNv12ConvertSamples', 140),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureNativeNv12ReadyPolicy', 'fence'),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureNativeNv12FenceAvailable', true),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureNativeNv12MaxPendingSlots', 2),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureNativeNv12ReadyDrainDepth', 2),
      );
      expect(
        diagnosticsJson,
        containsPair(
          'gameCaptureNativeNv12FrameOwnership',
          'owned_texture_copy',
        ),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureNativeNv12FenceSignaledFrames', 140),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureNativeNv12OwnedCopies', 140),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureNativeNv12OwnedCopySamples', 140),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureNativeNv12BgraScaleDrawSamples', 140),
      );
      expect(
        diagnosticsJson,
        containsPair(
          'gameCaptureNativeNv12VideoProcessorBltToReadySamples',
          140,
        ),
      );
      expect(
        diagnosticsJson,
        containsPair(
          'gameCaptureNativeNv12VideoProcessorBltGpuExecutionSamples',
          140,
        ),
      );
      expect(
        diagnosticsJson,
        containsPair(
          'maxGameCaptureNativeNv12VideoProcessorBltEstimatedGpuQueueDelayMs',
          0.75,
        ),
      );
      expect(
        diagnosticsJson,
        containsPair(
          'gameCaptureNativeNv12VideoProcessorBltGpuTimestampDisjoint',
          3,
        ),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureNativeNv12ReadyObservedFenceEventFrames', 90),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureNativeNv12ReadyObservedLoopIdleFrames', 18),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureNativeNv12BltToReadyOver1xFrames', 6),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureNativeNv12BltToReadyOver3xFrames', 1),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureNativeNv12StaleBeforeQueueFrames', 2),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureNativeNv12ConversionStartAgeSamples', 140),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureNativeNv12GpuQueueBackoffEnabled', true),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureNativeNv12GpuQueueBackoffThresholdFrames', 2),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureNativeNv12GpuQueueBackoffDurationFrames', 1),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureNativeNv12GpuQueueBackoffTriggeredFrames', 4),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureNativeNv12GpuQueueBackoffSuppressedFrames', 9),
      );
      expect(
        diagnosticsJson,
        containsPair(
          'gameCaptureNativeNv12GpuQueueBackoffSuppressedFreshFrames',
          7,
        ),
      );
      expect(
        diagnosticsJson,
        containsPair('averageGameCaptureNativeNv12GpuQueueBackoffMs', 33.3),
      );
      expect(
        diagnosticsJson,
        containsPair('maxGameCaptureNativeNv12GpuQueueBackoffMs', 34.1),
      );
      expect(
        diagnosticsJson,
        containsPair('gameCaptureNativeNv12GpuQueueBackoffSamples', 4),
      );
      expect(
        diagnosticsJson,
        containsPair(
          'averageGameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMs',
          78.5,
        ),
      );
      expect(
        diagnosticsJson,
        containsPair(
          'maxGameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadyMs',
          122.0,
        ),
      );
      expect(
        diagnosticsJson,
        containsPair(
          'gameCaptureNativeNv12GpuQueueBackoffTriggerBltToReadySamples',
          4,
        ),
      );
      expect(
        diagnosticsJson,
        containsPair(
          'averageGameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMs',
          18.2,
        ),
      );
      expect(
        diagnosticsJson,
        containsPair(
          'maxGameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeMs',
          28.4,
        ),
      );
      expect(
        diagnosticsJson,
        containsPair(
          'gameCaptureNativeNv12GpuQueueBackoffSuppressedSourceAgeSamples',
          9,
        ),
      );
      expect(
        diagnosticsJson,
        containsPair('encoderInputPathLabel', 'native_nv12'),
      );
      expect(diagnosticsJson, containsPair('encoderRateControlMode', 'cbr'));
      expect(diagnosticsJson, containsPair('encoderTargetBitrateBps', 3000000));
      expect(diagnosticsJson, containsPair('encoderNativeInputFrames', 1));
      expect(diagnosticsJson, containsPair('encoderNativeReadyFenceFrames', 1));
      expect(
        diagnosticsJson,
        containsPair('encoderNativeReadyFenceWaitSamples', 1),
      );
      expect(
        diagnosticsJson,
        containsPair('averageEncoderNativeReadyFenceWaitMs', 0.1),
      );
      expect(
        diagnosticsJson,
        containsPair('encoderNativeSourceMode', 'dummy-nv12-live-sender'),
      );
      expect(diagnosticsJson, containsPair('encoderNativeSourceFormat', 103));
      expect(
        diagnosticsJson,
        containsPair('encoderNativeSampleLifetimeSamples', 1),
      );
      expect(
        diagnosticsJson,
        containsPair('encoderNativeAdapterLuid', '0:123'),
      );
      expect(diagnosticsJson, containsPair('encoderProcessInputSamples', 1));
      expect(diagnosticsJson, containsPair('encoderProcessOutputSamples', 1));
      expect(diagnosticsJson, containsPair('encoderOutputFrames', 0));
      expect(diagnosticsJson, containsPair('encoderMaxQueueDepth', 1));
      expect(
        diagnosticsJson,
        allOf(containsPair('nativeEncoderHandoffNoOutput', true)),
      );
      final startedAt = DateTime.utc(2026, 6, 8, 19, 37);
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 30)),
        nativeDiagnostics: diagnostics,
        samples: const [],
      );
      expect(
        result.score.summary.senderHandoffDiagnosticsLabel,
        contains('observed=immediate:4 post:7 event:90 source:11'),
      );
      expect(
        result.score.summary.senderHandoffDiagnosticsLabel,
        contains('gpu_backoff:true threshold:2/1 trigger:4 suppress:9/7'),
      );
      final senderHandoffJson =
          result.score.summary.senderHandoffDiagnosticsJson;
      final nativeNv12ReadyJson =
          senderHandoffJson['nativeNv12Ready']! as Map<String, Object?>;
      final gpuQueueBackoffJson =
          nativeNv12ReadyJson['gpuQueueBackoff']! as Map<String, Object?>;
      expect(
        gpuQueueBackoffJson,
        allOf(
          containsPair('enabled', true),
          containsPair('thresholdFrames', 2),
          containsPair('durationFrames', 1),
          containsPair('triggered', 4),
          containsPair('suppressed', 9),
          containsPair('suppressedFresh', 7),
          containsPair('averageTriggerBltToReadyMs', 78.5),
        ),
      );
      expect(
        gpuQueueBackoffJson,
        allOf(containsPair('maxSuppressedSourceAgeMs', 28.4)),
      );
      final run = StreamTestRunResult(
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 30)),
        targetLabel: 'Test room',
        roomId: '!test:ourgalaxy.space',
        config: const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 30),
        ),
        presetResults: [result],
      );
      expect(run.toMarkdown(), contains('observed=immediate:4'));
      expect(run.toMarkdown(), contains('late>6/2/1'));
    });

    test('parses multiline native marker continuation blocks', () {
      final diagnostics = StreamTestNativeDiagnostics.fromMarkers([
        [
          '2026-06-15T22:23:46.331Z native-webrtc Inter Galactic: Media Foundation H.264 encoder timing frame=1560 stage=ok_native_nv12 size=1280x720 target_fps=30 input_path=native_nv12 native_input=yes native_sample_failed=no native_suspended=no native_ready_fence=yes native_ready_fence_timeout=no native_source_mode=helper-d3d11 native_source_format=24 native_source_frame=3542 native_source_age_ms=42.7603 native_source_age_at_create_ms=6.2999 native_buffer_age_ms=36.4604 native_sample_lifetime_ms=61.4728 native_sample_lifetime_max_ms=61.4728 native_sample_lifetime_samples=1 native_adapter_luid=0:81527 native_adapter_vendor_id=4318 native_adapter_device_id=7943 total_ms=0.6854 native_ready_fence_wait_ms=0.0007 process_input_ms=0.5388 process_output_ms=0.0082 encoded_callback_ms=0.0821 outputs=1 queue=1 retained_samples=1 encoded_outputs=1546 async=yes slow=no very_slow=no',
          '[Inter Galactic (main)] WebRTC native stream log: webrtc: (intergalactic_game_capture_video_capturer.cc:783): Inter Galactic game_capture_webrtc_source stats source=2560x1440 output=1280x720 format=24 sourceMode=helper-d3d11 fps=26.219647 backendContractVersion=2 sourceApi=d3d11 sourceApiId=1 sourceFormat=r10g10b10a2 sourceFormatId=3 colorSpace=unknown syncKind=event readyState=ready failureReason=none consumerAdapterLuid=0:81527 consumerAdapterVendorId=4318 consumerAdapterDeviceId=7943 sourceAdapterLuid=unknown crossAdapterSuspected=unknown submitted=800 repeated=0 duplicateSkipped=153 deliveryQueued=888 deliverySubmitted=800 deliveryOverwritten=87 deliveryPacerResyncs=36 deliveryPacerLagMaxMs=69 deliverySkipNoQueued=22 deliveryFreshWakeAfterSkip=12 deliveryFreshImmediate=563 deliveryRepeatPolicy=skip-on-miss deliveryQueueDepth=1 nativeNv12ReadyPolicy=fence nativeNv12FenceAvailable=true nativeNv12ReadyDrainDepth=1 deliveryOnFrameCallMs=24.114347 deliveryOnFrameCallMaxMs=111.657200 deliveryOnFrameCallSamples=800 deliveryQueueWaitMs=2.509740 deliveryQueueWaitMaxMs=41.244000 deliveryQueueWaitSamples=800 sourceToSubmitMs=16.713355 sourceToSubmitMaxMs=120.653300 sourceToSubmitSamples=800 gpuScaled=800 gpuScaleFailures=0 nativeNv12Submitted=798 nativeNv12Failures=0 nativeNv12Queued=886 nativeNv12Ready=886 nativeNv12NotReadyPolls=0 nativeNv12FenceSignaled=886 nativeNv12FenceSignalFailures=0 nativeNv12ReadyDropped=0 nativeNv12ConversionStartAgeMs=11.585553 nativeNv12ConversionStartAgeMaxMs=23.369000 nativeNv12ConversionStartAgeSamples=150 nativeNv12BgraScaleDrawMs=5.688443 nativeNv12BgraScaleDrawMaxMs=47.560100 nativeNv12BgraScaleDrawSamples=149 nativeNv12VideoProcessorBltToReadyMs=1.085924 nativeNv12VideoProcessorBltToReadyMaxMs=35.451700 nativeNv12VideoProcessorBltToReadySamples=149 nativeNv12StaleBeforeQueue=5 cpuFallback=0 sourceFrameIndex=1630 lastSubmittedSourceFrameIndex=1626 sourceFrameRegressions=0 sourceFrameGaps=826 timestampMode=source-qpc sourceQpcDeltaMs=37.818955 sourceQpcDeltaMaxMs=135.279000 sourceQpcSamples=799 visibleSourceSeen=true',
        ].join('\n'),
      ]);

      expect(diagnostics.gameCaptureSourceMode, 'helper-d3d11');
      expect(diagnostics.gameCaptureNativeNv12SubmittedFrames, 798);
      expect(diagnostics.gameCaptureNativeNv12Failures, 0);
      expect(diagnostics.gameCaptureCpuFallbackFrames, 0);
      expect(diagnostics.gameCaptureNativeNv12FenceAvailable, isTrue);
      expect(diagnostics.gameCaptureNativeNv12FenceSignaledFrames, 886);
      expect(diagnostics.averageGameCaptureDeliveryOnFrameCallMs, 24.114347);
      expect(diagnostics.maxGameCaptureDeliveryOnFrameCallMs, 111.6572);
      expect(diagnostics.averageGameCaptureSourceToSubmitMs, 16.713355);
      expect(diagnostics.averageGameCaptureNativeNv12BgraScaleDrawMs, 5.688443);
      expect(
        diagnostics.maxGameCaptureNativeNv12VideoProcessorBltToReadyMs,
        35.4517,
      );
      expect(diagnostics.gameCaptureConsumerAdapterLuid, '0:81527');
      expect(diagnostics.encoderNativeSourceMode, 'helper-d3d11');
      expect(diagnostics.encoderNativeSourceFormat, 24);
      expect(diagnostics.averageEncoderNativeSourceAgeMs, 42.7603);
      expect(diagnostics.averageEncoderNativeSourceAgeAtCreateMs, 6.2999);
      expect(diagnostics.averageEncoderNativeBufferAgeMs, 36.4604);
      expect(diagnostics.averageEncoderNativeSampleLifetimeMs, 61.4728);
      expect(diagnostics.encoderNativeSampleLifetimeSamples, 1);
      expect(diagnostics.encoderNativeAdapterLuid, '0:81527');
    });

    test('requires native encoder fence wait for native NV12 classification', () {
      final startedAt = DateTime.utc(2026, 6, 15, 13);
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 60)),
        nativeDiagnostics: StreamTestNativeDiagnostics.fromMarkers(const [
          '2026-06-15T13:00:40.000Z native-webrtc game_capture_webrtc_source stats source=2560x1440 output=1280x720 format=24 fps=12.4 submitted=825 repeated=0 copied=1721 gpuScaled=825 gpuScaleFailures=0 cpuFallback=0 deliveryQueued=825 deliverySubmitted=825 deliveryOverwritten=0 deliveryPacerResyncs=360 deliveryOnFrameCallMs=53.0 deliveryOnFrameCallMaxMs=199.0 deliveryOnFrameCallSamples=825 deliveryQueueWaitMs=12.0 deliveryQueueWaitMaxMs=110.0 deliveryQueueWaitSamples=825 sourceToSubmitMs=31.0 sourceToSubmitMaxMs=140.0 sourceToSubmitSamples=825 nativeNv12Submitted=825 nativeNv12Failures=0 nativeNv12Queued=1721 nativeNv12Ready=825 nativeNv12NotReadyPolls=0 nativeNv12ReadyPolicy=fence nativeNv12FenceAvailable=true nativeNv12FenceSignaled=1721 nativeNv12FenceReady=0 nativeNv12FenceSignalFailures=0 nativeNv12BgraScaleDrawMs=8.0 nativeNv12BgraScaleDrawMaxMs=103.0 nativeNv12BgraScaleDrawSamples=825 nativeNv12VideoProcessorBltToReadyMs=1.0 nativeNv12VideoProcessorBltToReadyMaxMs=61.0 nativeNv12VideoProcessorBltToReadySamples=825 nativeNv12ConversionStartAgeMs=1.0 nativeNv12ConversionStartAgeMaxMs=12.0 nativeNv12ConversionStartAgeSamples=825 visibleSourceSeen=true',
          '2026-06-15T13:00:40.100Z native-webrtc Inter Galactic Media Foundation H.264 encoder timing frame=825 stage=ok_native_nv12 size=1280x720 target_fps=30 input_path=native_nv12 native_input=yes native_sample_failed=no native_suspended=no budget_ms=33.3 total_ms=11.0 process_input_ms=1.0 process_output_ms=9.0 outputs=1 output_bytes=16000 queue=1 retained_samples=1 encoded_outputs=30 async=yes slow=no',
        ]),
        samples: [
          StreamTestSample(
            elapsed: const Duration(seconds: 60),
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 12.4,
              captureFps: 12.4,
              encodeFps: 12.6,
              sendFps: 12.3,
              averageEncodeTimeMs: 12,
              bitrateBps: 1500000,
              lossPercent: 0,
              rttMs: 3,
              requestedWidth: 1280,
              requestedHeight: 720,
              requestedFps: 30,
            ),
          ),
        ],
      );

      expect(result.score.bottleneck.label, 'insufficient_evidence');
      expect(
        result.score.bottleneck.missingFields,
        contains('native_ready_fence_wait_ms'),
      );
      expect(
        result.score.bottleneck.evidenceFor.join(' '),
        allOf(
          contains('candidate webrtc_onframe_limited'),
          contains('candidate delivery_queue_limited'),
          contains('candidate native_nv12_ready_limited'),
        ),
      );
      expect(
        result.diagnosticCoverage.missingFields,
        contains('native_ready_fence_wait_ms'),
      );
    });

    test('classifies native NV12 encoder handoff accepted without output', () {
      final startedAt = DateTime.utc(2026, 6, 9, 14, 40);
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 5)),
        error: 'TimeoutException: collect stream diagnostics timed out',
        nativeDiagnostics: StreamTestNativeDiagnostics.fromMarkers(const [
          '2026-06-09T18:40:00.000Z native-webrtc game_capture_webrtc_source stats source=2560x1440 output=1280x720 format=24 fps=30.0 submitted=32 copied=32 gpuScaled=32 gpuScaleFailures=0 cpuFallback=0 nativeNv12Submitted=32 nativeNv12Failures=0 readbackQueued=0 readbackReady=0 readbackNotReady=0 sourceFrameRegressions=0 sourceFrameGaps=0 sharedSlotMismatches=0 visibleSourceSeen=true',
          '2026-06-09T18:40:00.050Z native-webrtc Inter Galactic Media Foundation H.264 encoder timing frame=1 stage=ok_native_nv12 size=1280x720 target_fps=30 input_path=native_nv12 native_input=yes native_sample_failed=no native_suspended=no native_ready_fence=yes native_ready_fence_timeout=no native_ready_fence_wait_ms=0.2 budget_ms=33.3 total_ms=118.0 to_i420_ms=0 nv12_ms=0 create_sample_ms=99.0 input_copy_ms=99.0 process_input_ms=13.0 pre_drain_ms=0 retry_drain_ms=0 post_drain_ms=0.1 process_output_ms=0 output_copy_ms=0 outputs=0 output_bytes=0 queue=1 retained_samples=1 encoded_outputs=0 async=yes slow=yes',
        ]),
        samples: const [],
      );

      expect(result.score.bottleneck.label, 'encoder_handoff_limited');
      expect(
        result.score.bottleneck.reasons.join(' '),
        allOf(
          contains('native NV12 input reached Media Foundation'),
          contains('output stayed at 0 frames'),
          contains('encoder queue reached 1'),
        ),
      );
      expect(
        result.score.bottleneck.evidenceAgainstFalseCauses.join(' '),
        allOf(
          contains('native sample creation failures: 0'),
          contains('game-capture GPU scale succeeded 32 frames'),
          contains('native NV12 WebRTC source submitted 32 frames'),
        ),
      );
    });

    test('classifies over-budget native Media Foundation timing', () {
      final startedAt = DateTime.utc(2026, 6, 14, 19, 13);
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 60)),
        nativeDiagnostics: StreamTestNativeDiagnostics.fromMarkers(const [
          '2026-06-14T19:14:40.000Z native-webrtc game_capture_webrtc_source stats source=2560x1440 output=1280x720 format=24 fps=30.0 submitted=900 copied=901 gpuScaled=900 gpuScaleFailures=0 cpuFallback=0 nativeNv12Submitted=900 nativeNv12Failures=0 nativeNv12Queued=900 nativeNv12Ready=900 nativeNv12NotReadyPolls=10 nativeNv12ReadyDropped=0 nativeNv12ConvertMs=4.0 nativeNv12ConvertMaxMs=8.0 nativeNv12ConvertSamples=120 sourceToSubmitMs=8.0 sourceToSubmitMaxMs=14.0 sourceToSubmitSamples=900 deliveryQueueWaitMs=1.0 deliveryQueueWaitMaxMs=4.0 deliveryQueueWaitSamples=900 sourceFrameRegressions=0 sharedSlotMismatches=0 visibleSourceSeen=true',
          '2026-06-14T19:14:40.100Z native-webrtc Inter Galactic Media Foundation H.264 encoder timing frame=900 stage=ok_native_nv12 size=1280x720 target_fps=30 input_path=native_nv12 native_input=yes native_sample_failed=no native_suspended=no native_ready_fence=yes native_ready_fence_timeout=no native_ready_fence_wait_ms=0.3 budget_ms=33.3 total_ms=48.0 process_input_ms=1.0 process_output_ms=45.0 outputs=1 output_bytes=18000 queue=1 retained_samples=1 encoded_outputs=40 async=yes slow=yes',
        ]),
        samples: [
          StreamTestSample(
            elapsed: const Duration(seconds: 60),
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 23,
              captureFps: 30,
              encodeFps: 22,
              sendFps: 22,
              averageEncodeTimeMs: 88,
              bitrateBps: 1500000,
              lossPercent: 0,
              rttMs: 3,
              requestedWidth: 1280,
              requestedHeight: 720,
              requestedFps: 30,
            ),
          ),
        ],
      );

      expect(result.score.bottleneck.label, 'media_foundation_encoder_limited');
      expect(
        result.score.bottleneck.reasons.join(' '),
        contains('native MediaFoundation encoder averaged 48.0ms'),
      );
      expect(
        result.score.bottleneck.evidenceAgainstFalseCauses.join(' '),
        isNot(contains('native MediaFoundation encoder timing is')),
      );
    });

    test(
      'classifies paced timestamp divergence as timestamp policy mismatch',
      () {
        final startedAt = DateTime.utc(2026, 6, 14, 20, 40);
        final result = StreamTestPresetResult(
          profile: ScreenShareProfileConfig.smooth,
          startedAt: startedAt,
          endedAt: startedAt.add(const Duration(seconds: 60)),
          nativeDiagnostics: StreamTestNativeDiagnostics.fromMarkers(const [
            '2026-06-14T20:40:00.000Z native-webrtc game_capture_webrtc_source stats source=2560x1440 output=1280x720 format=24 fps=30.0 submitted=660 repeated=0 copied=900 gpuScaled=660 gpuScaleFailures=0 cpuFallback=0 deliveryQueued=660 deliverySubmitted=660 deliveryOverwritten=0 deliveryPacerResyncs=0 deliverySkipNoQueued=80 deliveryFreshWakeAfterSkip=80 deliveryOnFrameCallMs=2.0 deliveryOnFrameCallMaxMs=5.0 deliveryOnFrameCallSamples=660 deliveryQueueWaitMs=2.0 deliveryQueueWaitMaxMs=5.0 deliveryQueueWaitSamples=660 sourceToSubmitMs=10.0 sourceToSubmitMaxMs=25.0 sourceToSubmitSamples=660 nativeNv12Submitted=660 nativeNv12Failures=0 nativeNv12Queued=660 nativeNv12Ready=660 nativeNv12ReadyDropped=0 nativeNv12NotReadyPolls=4 nativeNv12ConvertMs=4.0 nativeNv12ConvertMaxMs=8.0 nativeNv12ConvertSamples=120 sourceFrameRegressions=0 sharedSlotMismatches=0 timestampMode=paced timestampSourceQpcFrames=0 timestampPacedFallbackFrames=660 timestampRepeatedFrames=0 timestampDeltaMs=33.3 timestampDeltaMaxMs=33.3 timestampSamples=659 timestampAdjustments=0 deliveryWallDeltaMs=45.0 deliveryWallDeltaMaxMs=80.0 deliveryWallSamples=659 deliveryWallOver2x=6 deliveryWallOver3x=0 deliveryWallUnderHalf=0 sourceQpcDeltaMs=45.0 sourceQpcDeltaMaxMs=80.0 sourceQpcSamples=659 sourceQpcRegressions=0 visibleSourceSeen=true',
          ]),
          samples: [
            StreamTestSample(
              elapsed: const Duration(seconds: 60),
              snapshot: _snapshot(
                width: 1280,
                height: 720,
                fps: 30,
                captureFps: 30,
                encodeFps: 30,
                sendFps: 30,
                averageEncodeTimeMs: 18,
                bitrateBps: 1500000,
                lossPercent: 0,
                rttMs: 3,
                requestedWidth: 1280,
                requestedHeight: 720,
                requestedFps: 30,
              ),
            ),
          ],
        );

        expect(result.score.bottleneck.label, 'timestamp_policy_mismatch');
        expect(
          result.score.bottleneck.reasons.join(' '),
          allOf(
            contains('paced timestamps stayed near 33.3ms'),
            contains('delivery wall-clock gap peaked at 80.0ms'),
            contains('source QPC gap peaked at 80.0ms'),
          ),
        );
        expect(
          result.score.bottleneck.evidenceFor.join(' '),
          contains('timestamp source-QPC frames 0, paced fallback 660'),
        );
        expect(
          result.score.bottleneck.recommendedNextAction,
          'fix frame pacing',
        );
      },
    );

    test('classifies split OnFrame call pressure separately', () {
      final startedAt = DateTime.utc(2026, 6, 14, 20, 45);
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 60)),
        nativeDiagnostics: StreamTestNativeDiagnostics.fromMarkers(const [
          '2026-06-14T20:45:00.000Z native-webrtc game_capture_webrtc_source stats source=2560x1440 output=1280x720 format=24 fps=21.0 submitted=630 repeated=0 copied=900 gpuScaled=630 gpuScaleFailures=0 cpuFallback=0 deliveryQueued=630 deliverySubmitted=630 deliveryOverwritten=0 deliveryPacerResyncs=0 deliverySubmitPrepMs=0.4 deliverySubmitPrepMaxMs=0.9 deliverySubmitPrepSamples=630 deliveryOnFrameCallMs=38.0 deliveryOnFrameCallMaxMs=120.0 deliveryOnFrameCallSamples=630 deliveryPostOnFrameMs=0.5 deliveryPostOnFrameMaxMs=1.0 deliveryPostOnFrameSamples=630 nativeBufferReleaseMs=0.2 nativeBufferReleaseMaxMs=0.4 nativeBufferReleaseSamples=630 deliveryQueueWaitMs=2.0 deliveryQueueWaitMaxMs=5.0 deliveryQueueWaitSamples=630 sourceToSubmitMs=45.0 sourceToSubmitMaxMs=125.0 sourceToSubmitSamples=630 nativeNv12Submitted=630 nativeNv12Failures=0 nativeNv12Queued=630 nativeNv12Ready=630 nativeNv12ReadyDropped=0 nativeNv12NotReadyPolls=2 nativeNv12ConvertMs=4.0 nativeNv12ConvertMaxMs=8.0 nativeNv12ConvertSamples=120 sourceFrameRegressions=0 sharedSlotMismatches=0 timestampMode=source-qpc timestampSourceQpcFrames=630 timestampPacedFallbackFrames=0 timestampRepeatedFrames=0 timestampDeltaMs=47.0 timestampDeltaMaxMs=96.0 timestampSamples=629 deliveryWallDeltaMs=47.0 deliveryWallDeltaMaxMs=96.0 deliveryWallSamples=629 deliveryWallOver2x=4 sourceQpcDeltaMs=47.0 sourceQpcDeltaMaxMs=96.0 sourceQpcSamples=629 visibleSourceSeen=true',
          '2026-06-14T20:45:00.100Z native-webrtc Inter Galactic Media Foundation H.264 encoder timing frame=630 stage=ok_native_nv12 size=1280x720 target_fps=30 input_path=native_nv12 native_input=yes native_sample_failed=no native_suspended=no native_ready_fence=yes native_ready_fence_timeout=no native_ready_fence_wait_ms=0.2 budget_ms=33.3 total_ms=40.0 process_input_ms=1.0 process_output_ms=36.0 outputs=1 output_bytes=18000 queue=1 retained_samples=1 encoded_outputs=30 async=yes slow=yes',
        ]),
        samples: [
          StreamTestSample(
            elapsed: const Duration(seconds: 60),
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 21,
              captureFps: 21,
              encodeFps: 21,
              sendFps: 21,
              averageEncodeTimeMs: 40,
              bitrateBps: 1500000,
              lossPercent: 0,
              rttMs: 3,
              requestedWidth: 1280,
              requestedHeight: 720,
              requestedFps: 30,
            ),
          ),
        ],
      );

      expect(result.score.bottleneck.label, 'webrtc_onframe_limited');
      expect(
        result.score.bottleneck.reasons.join(' '),
        contains('WebRTC OnFrame call averaged 38.0ms'),
      );
      expect(
        result.score.bottleneck.evidenceFor.join(' '),
        allOf(
          contains('submit prep averaged 0.4ms'),
          contains('post-OnFrame cleanup averaged 0.5ms'),
          contains('native buffer release averaged 0.2ms'),
        ),
      );
      expect(result.score.bottleneck.recommendedNextAction, 'fix encoder path');
    });

    test(
      'classifies healthy native readiness plus slow live OnFrame as sender handoff',
      () {
        final startedAt = DateTime.utc(2026, 6, 15, 15, 50);
        final result = StreamTestPresetResult(
          profile: ScreenShareProfileConfig.smooth,
          startedAt: startedAt,
          endedAt: startedAt.add(const Duration(seconds: 60)),
          nativeDiagnostics: StreamTestNativeDiagnostics.fromMarkers(const [
            '2026-06-15T15:50:40.000Z native-webrtc game_capture_webrtc_source stats source=2560x1440 output=1280x720 format=24 fps=17.7 submitted=1159 repeated=0 copied=1874 gpuScaled=1159 gpuScaleFailures=0 cpuFallback=0 deliveryQueued=1159 deliverySubmitted=1159 deliveryOverwritten=0 deliveryPacerResyncs=322 deliveryOnFrameCallMs=48.0 deliveryOnFrameCallMaxMs=276.0 deliveryOnFrameCallSamples=1159 deliveryQueueWaitMs=4.0 deliveryQueueWaitMaxMs=101.0 deliveryQueueWaitSamples=1159 sourceToSubmitMs=30.0 sourceToSubmitMaxMs=194.0 sourceToSubmitSamples=1159 nativeNv12Submitted=1157 nativeNv12Failures=0 nativeNv12Queued=1874 nativeNv12Ready=1873 nativeNv12NotReadyPolls=0 nativeNv12ReadyDropped=0 nativeNv12ReadyPolicy=fence nativeNv12FenceAvailable=true nativeNv12FenceSignaled=1873 nativeNv12FenceReady=0 nativeNv12FenceSignalFailures=0 nativeNv12ConvertMs=2.0 nativeNv12ConvertMaxMs=88.0 nativeNv12ConvertSamples=1157 nativeNv12BgraScaleDrawMs=14.0 nativeNv12BgraScaleDrawMaxMs=158.0 nativeNv12BgraScaleDrawSamples=1157 nativeNv12VideoProcessorBltSubmitMs=1.0 nativeNv12VideoProcessorBltSubmitMaxMs=78.0 nativeNv12VideoProcessorBltSubmitSamples=1157 nativeNv12VideoProcessorBltToReadyMs=1.0 nativeNv12VideoProcessorBltToReadyMaxMs=66.0 nativeNv12VideoProcessorBltToReadySamples=1157 nativeNv12ConversionStartAgeMs=10.0 nativeNv12ConversionStartAgeMaxMs=31.0 nativeNv12ConversionStartAgeSamples=1157 nativeNv12StaleBeforeQueue=11 visibleSourceSeen=true',
            '2026-06-15T15:50:40.100Z native-webrtc Inter Galactic Media Foundation H.264 encoder timing frame=1157 stage=ok_native_nv12 size=1280x720 target_fps=30 input_path=native_nv12 native_input=yes native_sample_failed=no native_suspended=no native_ready_fence=yes native_ready_fence_timeout=no native_ready_fence_wait_ms=0.3 budget_ms=33.3 total_ms=38.0 process_input_ms=1.0 process_output_ms=8.0 output_copy_ms=0.2 encoded_callback_ms=22.0 encoded_callback_invocations=1 encoded_callback_async=no encoded_callback_queue_depth=0 encoded_callback_drops=0 outputs=1 output_bytes=18000 queue=1 retained_samples=1 encoded_outputs=40 async=yes slow=yes',
          ]),
          samples: [
            StreamTestSample(
              elapsed: const Duration(seconds: 60),
              snapshot: _snapshot(
                width: 1280,
                height: 720,
                fps: 11.8,
                captureFps: 11.9,
                encodeFps: 10.9,
                sendFps: 11.2,
                averageEncodeTimeMs: 53,
                bitrateBps: 1500000,
                lossPercent: 0,
                rttMs: 159,
                requestedWidth: 1280,
                requestedHeight: 720,
                requestedFps: 30,
                framesCaptured: 715,
                framesEncoded: 654,
                framesSent: 672,
                codec: 'H264',
                encoderImplementation: 'Media Foundation H.264',
                hardwareEncodeActive: true,
              ),
            ),
          ],
        );

        expect(result.score.bottleneck.label, 'encoder_handoff_limited');
        expect(
          result.score.bottleneck.reasons.join(' '),
          contains('live_sender_handoff_backpressure'),
        );
        expect(
          result.score.bottleneck.evidenceAgainstFalseCauses.join(' '),
          allOf(
            contains('native NV12 readiness was healthy'),
            contains('native fence handoff was available/signaled'),
          ),
        );
        expect(
          result.score.bottleneck.evidenceFor.join(' '),
          allOf(
            contains('delivery queue wait 4ms/101ms'),
            contains('processOutput 8ms'),
            contains('encodedCallback 22ms'),
          ),
        );

        final summaryJson = result.score.summary.toJson();
        final handoff =
            summaryJson['senderHandoffDiagnostics'] as Map<String, Object?>;
        final nativeDiagnostics =
            summaryJson['nativeDiagnostics'] as Map<String, Object?>;
        expect(handoff['available'], isTrue);
        expect(
          handoff['label'] as String,
          allOf(
            contains('on_frame_call=48ms/276ms'),
            contains('native_ready=policy:fence'),
            contains('encoded_callback:22ms/22ms'),
          ),
        );
        expect(
          nativeDiagnostics,
          containsPair('averageEncoderEncodedCallbackMs', 22.0),
        );
        final mediaFoundation =
            handoff['mediaFoundation'] as Map<String, Object?>;
        expect(mediaFoundation, containsPair('averageEncodedCallbackMs', 22.0));
        expect(
          result.diagnosticCoverage.items,
          contains(
            isA<StreamDiagnosticCoverageItem>()
                .having(
                  (item) => item.category,
                  'category',
                  'sender handoff diagnostics',
                )
                .having(
                  (item) => item.status,
                  'status',
                  StreamDiagnosticCoverageStatus.available,
                ),
          ),
        );

        final run = StreamTestRunResult(
          startedAt: startedAt,
          endedAt: startedAt.add(const Duration(seconds: 60)),
          targetLabel: 'BG3 test',
          roomId: '!fake:example.test',
          config: const StreamTestRunConfig(
            presets: [ScreenShareProfileConfig.smooth],
          ),
          presetResults: [result],
        );
        final markdown = run.toMarkdown();
        expect(markdown, contains('## Sender Handoff Diagnostics'));
        expect(markdown, contains('48ms avg / 276ms max'));
        expect(markdown, contains('callback 22ms/22ms'));
        expect(markdown, contains('not_applicable_game_hook'));
      },
    );

    test('parses native encoded callback worker timing', () {
      final diagnostics = StreamTestNativeDiagnostics.fromMarkers(const [
        '2026-06-15T16:00:00.100Z native-webrtc Inter Galactic Media Foundation H.264 encoded callback timing frame=42 async=yes callback_ms=19.5 queue_wait_ms=4.2 queue_depth=1 callback_outputs=37 callback_drops=2 result=ok drop_next=no slow=yes very_slow=no',
      ]);

      expect(diagnostics.averageEncoderEncodedCallbackMs, 19.5);
      expect(diagnostics.maxEncoderEncodedCallbackMs, 19.5);
      expect(diagnostics.encoderEncodedCallbackSamples, 1);
      expect(diagnostics.averageEncoderEncodedCallbackQueueWaitMs, 4.2);
      expect(diagnostics.maxEncoderEncodedCallbackQueueWaitMs, 4.2);
      expect(diagnostics.encoderEncodedCallbackQueueWaitSamples, 1);
      expect(diagnostics.encoderEncodedCallbackAsyncFrames, 1);
      expect(diagnostics.encoderMaxEncodedCallbackQueueDepth, 1);
      expect(diagnostics.encoderMaxEncodedCallbackDrops, 2);
      expect(diagnostics.encoderMaxEncodedCallbackOutputs, 37);
      expect(
        diagnostics.toJson(),
        containsPair('averageEncoderEncodedCallbackMs', 19.5),
      );
    });

    test('parses WebRTC raw sender handoff boundary timing', () {
      final markers = streamTestDiagnosticMarkersFromText(
        [
          '2026-06-15T16:05:00.000Z native-webrtc Inter Galactic WebRTC sender handoff source_on_frame stats calls=90 adapter_drops=1 scaled=0 avg_ms=4.2 max_ms=19.4 adapt_ms=0.1 adapt_max_ms=0.4 scale_ms=0 scale_max_ms=0 broadcast_ms=4.0 broadcast_max_ms=19.0',
          '2026-06-15T16:05:00.050Z native-webrtc Inter Galactic WebRTC sender handoff video_broadcaster stats frames=90 sink_count=2 max_sink_count=2 avg_ms=3.8 max_ms=18.5 lock_wait_ms=0.2 lock_wait_max_ms=1.4 sink_dispatch_ms=3.5 sink_dispatch_max_ms=17.8 max_single_sink_ms=17.6 slow_sink_id=2 slow_sink_ms=17.6 slow_sink_label=active+requested_1280x720+fps_30 slowest_sink_id=2 slowest_sink_ms=17.6 slowest_sink_avg_ms=3.4 slowest_sink_frames=90 slowest_sink_label=active+requested_1280x720+fps_30 active_sinks=1 inactive_sinks=1 requested_sinks=1 black_frame_sinks=0 rotation_applied_sinks=0 inactive_native_sinks_bypassed=90 inactive_native_sinks_bypassed_last=1 sink_roster=1:inactive+bypassed,2:active+requested_1280x720+fps_30 black_sinks=0 rotation_discards=0 update_rect_cleared=1 discarded_frames=0',
          '2026-06-15T16:05:00.100Z native-webrtc Inter Galactic WebRTC sender handoff video_stream_encoder stats onframe_calls=90 post_to_onframe_ms=2.1 post_to_onframe_max_ms=12.5 onframe_ms=6.5 onframe_max_ms=31.0 queue_overload_drops=2 encoder_queue_drops=2 cwnd_drops=0 bad_timestamp_drops=0 maybe_encode_calls=88 maybe_encode_ms=6.0 maybe_encode_max_ms=29.0 maybe_pre_encode_ms=1.1 maybe_pre_encode_max_ms=8.0 maybe_encode_call_ms=4.9 maybe_encode_call_max_ms=21.0 maybe_frame_size_ms=0.1 maybe_frame_size_max_ms=0.3 maybe_parameter_update_ms=0.6 maybe_parameter_update_max_ms=6.2 maybe_reconfigure_ms=0.4 maybe_reconfigure_max_ms=5.5 maybe_rate_update_ms=0.2 maybe_rate_update_max_ms=3.1 maybe_drop_checks_ms=0.4 maybe_drop_checks_max_ms=1.8 pending_replaced_drops=0 size_drops=0 paused_drops=0 media_optimization_drops=1 encode_frame_calls=87 encode_frame_ms=5.5 encode_frame_max_ms=27.0 encode_pre_encoder_ms=0.7 encode_pre_encoder_max_ms=4.4 encode_info_ms=0.2 encode_info_max_ms=1.1 encode_crop_scale_ms=0.0 encode_crop_scale_max_ms=0.0 encode_update_rect_ms=0.1 encode_update_rect_max_ms=0.4 encode_resource_ms=0.3 encode_resource_max_ms=2.2 encode_metadata_ms=0.1 encode_metadata_max_ms=0.5 video_encoder_encode_calls=87 video_encoder_encode_ms=4.8 video_encoder_encode_max_ms=25.0 encode_failures=0 encode_skipped_before_encoder=0 lineage_stage=video_encoder_encode_entry frame_id=120 source_qpc=100000 stage_qpc=100900 frame_age_ms=9.0 previous_frame_id=119',
          '2026-06-15T16:05:00.125Z native-webrtc Inter Galactic WebRTC sender handoff frame_cadence_queue stats frames=90 overload_frames=3 post_delay_samples=90 post_delay_ms=2.4 post_delay_max_ms=24.5 max_scheduled_for_processing=4 last_scheduled_for_processing=1 passthrough_frames=90 zero_hertz_frames=0 vsync_frames=0 unknown_frames=0 last_mode=passthrough coalesce_enabled_seen=yes coalesce_disabled_seen=no coalesce_threshold=1 coalesced_drops=7 prepost_coalesce_enabled_seen=yes prepost_coalesce_disabled_seen=no prepost_coalesced_drops=5 prepost_processing_drops=3 prepost_max_scheduled_for_processing=2 mailbox_enabled_seen=yes mailbox_frames=97 mailbox_processed_frames=90 mailbox_replacements=5 mailbox_stale_drops=2 mailbox_processing_active=no mailbox_processing_active_seen=yes mailbox_pending_depth_max=1 mailbox_pending_depth_last=0 pending_frame_age_ms=4.4 pending_frame_age_max_ms=18.0 pending_frame_age_samples=95 processing_frame_age_ms=6.8 processing_frame_age_max_ms=29.0 processing_frame_age_samples=90 admission_deadline_misses=3 enqueue_to_processing_start_ms=4.4 enqueue_to_processing_start_max_ms=18.0 enqueue_to_processing_start_samples=90 processing_start_to_vse_ms=0.1 processing_start_to_vse_max_ms=0.6 processing_start_to_vse_samples=90 vse_call_ms=5.2 vse_call_max_ms=17.2 vse_call_samples=90 mailbox_stale_drop_threshold_ms=67 lineage_stage=on_frame_on_main_queue_start frame_id=121 source_qpc=101000 stage_qpc=102100 frame_age_ms=11.0 previous_frame_id=120',
          '2026-06-15T16:05:00.150Z native-webrtc Inter Galactic WebRTC sender handoff frame_cadence_adapter stats sends=90 repeated_sends=2 overload_enabled_seen=yes overload_disabled_seen=no post_delay_samples=88 post_delay_ms=3.2 post_delay_max_ms=28.5 callback_ms=6.7 callback_max_ms=37.2 frame_duration_ms=33.3 frame_duration_max_ms=33.3 over_frame_duration_sends=3 overload_trigger_sends=2 overload_active_sends=4 overload_decay_sends=4 max_scheduled_for_processing=3 last_scheduled_for_processing=1 max_queue_overload_before=2 max_queue_overload_after=3 last_queue_overload_before=1 last_queue_overload_after=0',
        ].join('\n'),
        limit: null,
      );
      final diagnostics = StreamTestNativeDiagnostics.fromMarkers(markers);

      expect(markers, hasLength(5));
      expect(diagnostics.hasWebrtcRawSenderBoundaryDiagnostics, isTrue);
      expect(diagnostics.averageWebrtcSourceOnFrameMs, 4.2);
      expect(diagnostics.maxWebrtcSourceBroadcastMs, 19.0);
      expect(diagnostics.webrtcSourceAdapterDrops, 1);
      expect(diagnostics.averageWebrtcVideoBroadcasterMs, 3.8);
      expect(diagnostics.maxWebrtcVideoBroadcasterMs, 18.5);
      expect(diagnostics.webrtcVideoBroadcasterSamples, 90);
      expect(diagnostics.averageWebrtcVideoBroadcasterLockWaitMs, 0.2);
      expect(diagnostics.maxWebrtcVideoBroadcasterSinkDispatchMs, 17.8);
      expect(diagnostics.maxWebrtcVideoBroadcasterSingleSinkMs, 17.6);
      expect(diagnostics.webrtcVideoBroadcasterSlowSinkId, 2);
      expect(diagnostics.webrtcVideoBroadcasterSlowSinkMs, 17.6);
      expect(
        diagnostics.webrtcVideoBroadcasterSlowSinkLabel,
        'active+requested_1280x720+fps_30',
      );
      expect(diagnostics.webrtcVideoBroadcasterSlowestSinkId, 2);
      expect(diagnostics.webrtcVideoBroadcasterSlowestSinkAverageMs, 3.4);
      expect(diagnostics.webrtcVideoBroadcasterSlowestSinkFrames, 90);
      expect(diagnostics.webrtcVideoBroadcasterSinkCount, 2);
      expect(diagnostics.webrtcVideoBroadcasterMaxSinkCount, 2);
      expect(diagnostics.webrtcVideoBroadcasterActiveSinks, 1);
      expect(diagnostics.webrtcVideoBroadcasterInactiveSinks, 1);
      expect(diagnostics.webrtcVideoBroadcasterRequestedSinks, 1);
      expect(
        diagnostics.webrtcVideoBroadcasterInactiveNativeSinkBypassReported,
        isTrue,
      );
      expect(diagnostics.webrtcVideoBroadcasterInactiveNativeSinksBypassed, 90);
      expect(
        diagnostics.webrtcVideoBroadcasterInactiveNativeSinksBypassedLast,
        1,
      );
      expect(
        diagnostics.webrtcVideoBroadcasterSinkRoster,
        '1:inactive+bypassed,2:active+requested_1280x720+fps_30',
      );
      expect(diagnostics.webrtcVideoBroadcasterUpdateRectCleared, 1);
      expect(diagnostics.averageWebrtcVsePostToOnFrameMs, 2.1);
      expect(diagnostics.maxWebrtcVseOnFrameMs, 31.0);
      expect(diagnostics.webrtcVseEncoderQueueDrops, 2);
      expect(diagnostics.webrtcVseMediaOptimizationDrops, 1);
      expect(diagnostics.averageWebrtcVseMaybePreEncodeMs, 1.1);
      expect(diagnostics.maxWebrtcVseMaybePreEncodeMs, 8.0);
      expect(diagnostics.averageWebrtcVseMaybeEncodeCallMs, 4.9);
      expect(diagnostics.maxWebrtcVseMaybeEncodeCallMs, 21.0);
      expect(diagnostics.maxWebrtcVseMaybeParameterUpdateMs, 6.2);
      expect(diagnostics.maxWebrtcVseMaybeReconfigureMs, 5.5);
      expect(diagnostics.maxWebrtcVseMaybeRateUpdateMs, 3.1);
      expect(diagnostics.maxWebrtcVseEncodePreEncoderMs, 4.4);
      expect(diagnostics.averageWebrtcVseEncodeResourceMs, 0.3);
      expect(diagnostics.maxWebrtcVseEncodeResourceMs, 2.2);
      expect(diagnostics.averageWebrtcVideoEncoderEncodeMs, 4.8);
      expect(diagnostics.maxWebrtcVideoEncoderEncodeMs, 25.0);
      expect(
        diagnostics.webrtcFrameLineageStage,
        'on_frame_on_main_queue_start',
      );
      expect(diagnostics.webrtcFrameLineageFrameId, 121);
      expect(diagnostics.webrtcFrameLineageSourceQpc, 101000);
      expect(diagnostics.webrtcFrameLineageStageQpc, 102100);
      expect(diagnostics.webrtcFrameLineageFrameAgeMs, 11.0);
      expect(diagnostics.webrtcFrameLineagePreviousFrameId, 120);
      expect(diagnostics.averageWebrtcFrameCadenceCallbackMs, 6.7);
      expect(diagnostics.maxWebrtcFrameCadenceCallbackMs, 37.2);
      expect(diagnostics.averageWebrtcFrameCadenceQueuePostDelayMs, 2.4);
      expect(diagnostics.maxWebrtcFrameCadenceQueuePostDelayMs, 24.5);
      expect(diagnostics.webrtcFrameCadenceQueueFrames, 90);
      expect(diagnostics.webrtcFrameCadenceQueueOverloadFrames, 3);
      expect(diagnostics.webrtcFrameCadenceQueueMaxScheduledForProcessing, 4);
      expect(diagnostics.webrtcFrameCadenceQueuePassthroughFrames, 90);
      expect(diagnostics.webrtcFrameCadenceQueueCoalesceEnabledSeen, isTrue);
      expect(diagnostics.webrtcFrameCadenceQueueCoalesceDisabledSeen, isFalse);
      expect(diagnostics.webrtcFrameCadenceQueueCoalesceThreshold, 1);
      expect(diagnostics.webrtcFrameCadenceQueueCoalescedDrops, 7);
      expect(
        diagnostics.webrtcFrameCadenceQueuePrepostCoalesceEnabledSeen,
        isTrue,
      );
      expect(
        diagnostics.webrtcFrameCadenceQueuePrepostCoalesceDisabledSeen,
        isFalse,
      );
      expect(diagnostics.webrtcFrameCadenceQueuePrepostCoalescedDrops, 5);
      expect(diagnostics.webrtcFrameCadenceQueuePrepostProcessingDrops, 3);
      expect(
        diagnostics.webrtcFrameCadenceQueuePrepostMaxScheduledForProcessing,
        2,
      );
      expect(diagnostics.webrtcFrameCadenceQueueLastMode, 'passthrough');
      expect(diagnostics.webrtcFrameCadenceQueueMailboxEnabledSeen, isTrue);
      expect(diagnostics.webrtcFrameCadenceQueueMailboxFrames, 97);
      expect(diagnostics.webrtcFrameCadenceQueueMailboxProcessedFrames, 90);
      expect(diagnostics.webrtcFrameCadenceQueueMailboxReplacements, 5);
      expect(diagnostics.webrtcFrameCadenceQueueMailboxStaleDrops, 2);
      expect(
        diagnostics.webrtcFrameCadenceQueueMailboxProcessingActive,
        isFalse,
      );
      expect(
        diagnostics.webrtcFrameCadenceQueueMailboxProcessingActiveSeen,
        isTrue,
      );
      expect(diagnostics.webrtcFrameCadenceQueueMailboxPendingDepthMax, 1);
      expect(diagnostics.webrtcFrameCadenceQueueMailboxPendingDepthLast, 0);
      expect(
        diagnostics.averageWebrtcFrameCadenceQueueMailboxPendingFrameAgeMs,
        4.4,
      );
      expect(
        diagnostics.maxWebrtcFrameCadenceQueueMailboxPendingFrameAgeMs,
        18.0,
      );
      expect(
        diagnostics.webrtcFrameCadenceQueueMailboxPendingFrameAgeSamples,
        95,
      );
      expect(
        diagnostics.averageWebrtcFrameCadenceQueueMailboxProcessingFrameAgeMs,
        6.8,
      );
      expect(
        diagnostics.maxWebrtcFrameCadenceQueueMailboxProcessingFrameAgeMs,
        29.0,
      );
      expect(
        diagnostics.webrtcFrameCadenceQueueMailboxAdmissionDeadlineMisses,
        3,
      );
      expect(
        diagnostics
            .averageWebrtcFrameCadenceQueueMailboxEnqueueToProcessingStartMs,
        4.4,
      );
      expect(
        diagnostics.maxWebrtcFrameCadenceQueueMailboxEnqueueToProcessingStartMs,
        18.0,
      );
      expect(
        diagnostics.averageWebrtcFrameCadenceQueueMailboxProcessingStartToVseMs,
        0.1,
      );
      expect(diagnostics.maxWebrtcFrameCadenceQueueMailboxVseCallMs, 17.2);
      expect(
        diagnostics.webrtcFrameCadenceQueueMailboxStaleDropThresholdMs,
        67,
      );
      expect(diagnostics.webrtcFrameCadenceSends, 90);
      expect(diagnostics.webrtcFrameCadenceOverloadTriggerSends, 2);
      expect(diagnostics.webrtcFrameCadenceMaxScheduledForProcessing, 3);
      expect(
        diagnostics.webrtcRawSenderBoundaryLabel,
        allOf(
          contains('source_on_frame=4ms/19ms'),
          contains('broadcaster=4ms/19ms'),
          contains('broadcaster_sink=4ms/18ms'),
          contains(
            'broadcaster_slow_sink=2:active+requested_1280x720+fps_30/18ms',
          ),
          contains(
            'broadcaster_roster='
            '1:inactive+bypassed,2:active+requested_1280x720+fps_30',
          ),
          contains('vse_onframe=7ms/31ms'),
        ),
      );
      expect(
        diagnostics.webrtcRawSenderBoundaryLabel,
        allOf(
          contains('vse_maybe_pre_encode=1ms/8ms'),
          contains('vse_maybe_encode_call=5ms/21ms'),
          contains('vse_maybe_parameter_update=1ms/6ms'),
          contains('vse_maybe_reconfigure=0ms/6ms'),
          contains('vse_maybe_rate_update=0ms/3ms'),
          contains('vse_encode_pre_encoder=1ms/4ms'),
          contains('vse_encode_resource=0ms/2ms'),
        ),
      );
      expect(
        diagnostics.webrtcRawSenderBoundaryLabel,
        contains('video_encoder_encode=5ms/25ms'),
      );
      expect(
        diagnostics.webrtcRawSenderBoundaryLabel,
        allOf(
          contains(
            'lineage=stage:on_frame_on_main_queue_start frame:121 prev:120',
          ),
          contains('active_split=task_posted_start:4ms/18ms'),
          contains('encoder_post_start:2ms/13ms'),
          contains('encode_entry_return:5ms/25ms'),
        ),
      );
      expect(
        diagnostics.webrtcRawSenderBoundaryLabel,
        allOf(
          contains('frame_cadence_callback=7ms/37ms'),
          contains('frame_cadence_queue=frames:90 overload:3'),
          contains('coalesce:enabled:true threshold:1 drops:7'),
          contains(
            'prepost:enabled:true drops:5 processing_drops:3 scheduled_max:2',
          ),
          contains(
            'mailbox=enabled:true frames:97 processed:90 replacements:5 '
            'stale:2',
          ),
          contains('deadline_misses:3 stale_threshold:67'),
          contains('frame_cadence_overload=trigger:2 active:4'),
        ),
      );
      expect(
        diagnostics.webrtcRawSenderBoundaryLabel,
        allOf(
          contains('inactive_native_bypass:90 last:1'),
          contains('inactive_native_refresh:0 last:0'),
          contains('reported:true'),
        ),
      );
      expect(
        diagnostics.toJson()['webrtcRawSenderBoundary'],
        isA<Map<String, Object?>>().having(
          (json) => json['available'],
          'available',
          isTrue,
        ),
      );
      final boundary =
          diagnostics.toJson()['webrtcRawSenderBoundary']
              as Map<String, Object?>;
      expect(
        boundary['videoBroadcaster'],
        isA<Map<String, Object?>>()
            .having((json) => json['samples'], 'samples', 90)
            .having((json) => json['maxSingleSinkMs'], 'single sink', 17.6)
            .having((json) => json['slowSinkId'], 'slow sink id', 2)
            .having(
              (json) => json['slowSinkLabel'],
              'slow sink label',
              'active+requested_1280x720+fps_30',
            )
            .having(
              (json) => json['sinkRoster'],
              'sink roster',
              '1:inactive+bypassed,2:active+requested_1280x720+fps_30',
            )
            .having(
              (json) => json['inactiveNativeSinksBypassed'],
              'inactive native bypassed',
              90,
            ),
      );
      expect(
        boundary['videoStreamEncoder'],
        isA<Map<String, Object?>>()
            .having(
              (json) => json['maxMaybePreEncodeMs'],
              'maybe pre-encode max',
              8.0,
            )
            .having(
              (json) => json['maxMaybeEncodeCallMs'],
              'maybe encode call max',
              21.0,
            )
            .having(
              (json) => json['maxMaybeReconfigureMs'],
              'maybe reconfigure max',
              5.5,
            )
            .having(
              (json) => json['maxMaybeRateUpdateMs'],
              'maybe rate update max',
              3.1,
            )
            .having(
              (json) => json['maxEncodePreEncoderMs'],
              'encode pre-encoder max',
              4.4,
            )
            .having(
              (json) => json['maxEncodeResourceMs'],
              'encode resource max',
              2.2,
            ),
      );
      final vseBoundary =
          boundary['videoStreamEncoder'] as Map<String, Object?>;
      expect(
        vseBoundary['lineage'],
        isA<Map<String, Object?>>()
            .having(
              (json) => json['lineage_stage'],
              'lineage stage',
              'on_frame_on_main_queue_start',
            )
            .having((json) => json['frame_id'], 'frame id', 121)
            .having((json) => json['previous_frame_id'], 'previous id', 120),
      );
      expect(
        vseBoundary['activeProcessingSplit'],
        isA<Map<String, Object?>>()
            .having(
              (json) => json['task_posted_to_task_starts_ms'],
              'task posted to start',
              4.4,
            )
            .having(
              (json) => json['encoder_task_posted_to_started_ms'],
              'encoder posted to started',
              2.1,
            )
            .having(
              (json) => json['encode_entry_to_encode_return_ms'],
              'encode entry to return',
              4.8,
            ),
      );
      expect(
        boundary['frameCadenceQueue'],
        isA<Map<String, Object?>>()
            .having((json) => json['frames'], 'frames', 90)
            .having((json) => json['overloadFrames'], 'overload frames', 3)
            .having((json) => json['coalesceEnabledSeen'], 'coalesce on', true)
            .having((json) => json['coalescedDrops'], 'coalesced drops', 7)
            .having(
              (json) => json['prepostCoalesceEnabledSeen'],
              'prepost coalesce on',
              true,
            )
            .having(
              (json) => json['prepostCoalescedDrops'],
              'prepost coalesced drops',
              5,
            )
            .having(
              (json) => json['prepostProcessingDrops'],
              'prepost processing drops',
              3,
            )
            .having(
              (json) => json['prepostMaxScheduledForProcessing'],
              'prepost scheduled max',
              2,
            )
            .having((json) => json['lastMode'], 'last mode', 'passthrough'),
      );
      expect(
        boundary['frameCadenceQueue'],
        isA<Map<String, Object?>>()
            .having(
              (json) => json['mailboxEnabledSeen'],
              'mailbox enabled',
              true,
            )
            .having((json) => json['mailboxFrames'], 'mailbox frames', 97)
            .having(
              (json) => json['mailboxProcessedFrames'],
              'mailbox processed',
              90,
            )
            .having(
              (json) => json['mailboxReplacements'],
              'mailbox replacements',
              5,
            )
            .having(
              (json) => json['mailboxStaleDrops'],
              'mailbox stale drops',
              2,
            )
            .having(
              (json) => json['mailboxAdmissionDeadlineMisses'],
              'mailbox deadline misses',
              3,
            )
            .having(
              (json) => json['maxMailboxVseCallMs'],
              'mailbox vse max',
              17.2,
            ),
      );
      expect(
        boundary['frameCadenceQueue'],
        isA<Map<String, Object?>>()
            .having(
              (json) => json['active_processing'],
              'active processing',
              false,
            )
            .having((json) => json['pending_replaced'], 'pending replaced', 5)
            .having((json) => json['pending_age_ms'], 'pending age', 4.4)
            .having(
              (json) => json['stale_before_processing'],
              'stale before processing',
              2,
            )
            .having(
              (json) => json['processing_duration_ms'],
              'processing duration',
              0.1,
            )
            .having(
              (json) => json['active_frame_source_age_ms'],
              'active frame source age',
              6.8,
            ),
      );
      expect(
        boundary['frameCadenceAdapter'],
        isA<Map<String, Object?>>()
            .having((json) => json['sends'], 'sends', 90)
            .having(
              (json) => json['overloadTriggerSends'],
              'overload trigger sends',
              2,
            )
            .having(
              (json) => json['maxScheduledForProcessing'],
              'max scheduled',
              3,
            ),
      );
    });

    test('classifies disabled native NV12 path as GPU handoff unproven', () {
      final startedAt = DateTime.utc(2026, 6, 10, 14, 29);
      final nativeDiagnostics = StreamTestNativeDiagnostics.fromMarkers(const [
        '2026-06-10T14:29:27.000Z native-webrtc native_nv12_encoder_handoff_disabled reason=r10g10b10a2_source_format source=2560x1440 output=1280x720 format=24',
        '2026-06-10T14:29:57.000Z native-webrtc game_capture_webrtc_source stats source=2560x1440 output=1280x720 format=24 fps=30.0 submitted=1055 repeated=163 copied=1055 dropped=0 overwritten=0 gpuScaled=1055 gpuScaleFailures=0 cpuFallback=0 nativeNv12Submitted=0 nativeNv12Failures=0 readbackQueued=1055 readbackReady=1055 readbackNotReady=3847 readbackLatencyDropped=0 readbackMapAttempts=4902 sourceFrameIndex=1055 lastSubmittedSourceFrameIndex=1055 sourceFrameRegressions=0 sourceFrameGaps=0 sharedSlotMismatches=0 visibleSourceSeen=true',
        '2026-06-10T14:29:57.100Z native-webrtc Inter Galactic Media Foundation H.264 encoder timing frame=1055 total_ms=3.1 process_output_ms=0.1 slow=no input_path=cpu_i420 native_input=no native_sample_failed=no native_suspended=no outputs=1 output_bytes=2048 queue=0 retained_samples=0 encoded_outputs=1 stage=ok_i420',
      ]);
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 30)),
        nativeDiagnostics: nativeDiagnostics,
        samples: [
          StreamTestSample(
            elapsed: Duration.zero,
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 30,
              captureFps: 30,
              encodeFps: 30,
              sendFps: 30,
              averageEncodeTimeMs: 3,
              bitrateBps: 1800000,
              lossPercent: 0,
              rttMs: 4,
              framesCaptured: 0,
              framesEncoded: 0,
              framesSent: 0,
            ),
          ),
          StreamTestSample(
            elapsed: const Duration(seconds: 1),
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 30,
              captureFps: 30,
              encodeFps: 30,
              sendFps: 30,
              averageEncodeTimeMs: 3,
              bitrateBps: 1800000,
              lossPercent: 0,
              rttMs: 4,
              framesCaptured: 30,
              framesEncoded: 30,
              framesSent: 30,
            ),
          ),
        ],
      );

      expect(
        nativeDiagnostics.gameCaptureNativeNv12HandoffDisabledReason,
        'r10g10b10a2_source_format',
      );
      expect(nativeDiagnostics.gameCaptureGpuHandoffUnproven, isTrue);
      expect(
        nativeDiagnostics.gameCaptureFrameSummaryLabel,
        contains('native_nv12_disabled=r10g10b10a2_source_format'),
      );
      expect(result.score.bottleneck.label, 'gpu_handoff_unproven');
      expect(result.score.bottleneck.confidence, 'high');
      expect(
        result.score.bottleneck.reasons.join(' '),
        allOf(
          contains('native NV12 encoder handoff disabled'),
          contains('native NV12 source submitted 0'),
          contains('CPU I420 input'),
        ),
      );
      expect(
        result.score.bottleneck.evidenceAgainstFalseCauses.join(' '),
        allOf(
          contains('network evidence is clean'),
          contains('game-capture GPU scale failures 0'),
        ),
      );
      expect(
        result.score.bottleneck.recommendedNextAction,
        'fix game-capture handoff',
      );
      expect(
        nativeDiagnostics.toJson(),
        allOf(
          containsPair(
            'gameCaptureNativeNv12HandoffDisabledReason',
            'r10g10b10a2_source_format',
          ),
          containsPair('gameCaptureGpuHandoffUnproven', true),
        ),
      );
    });

    test('parses native NV12 live OnFrame backpressure suspension', () {
      final nativeDiagnostics = StreamTestNativeDiagnostics.fromMarkers(const [
        '2026-06-19T18:45:00.000Z native-webrtc native_nv12_encoder_handoff_suspended reason=live_onframe_backpressure onFrameCallMs=24.5 thresholdMs=20 streak=3 frameLimit=3 slowFrames=3 maxMs=135.2 nativeNv12Submitted=87 using_gpu_scale_i420_readback=true',
        '2026-06-19T18:45:05.000Z native-webrtc game_capture_webrtc_source stats source=2560x1440 output=1280x720 format=24 fps=8.75 submitted=90 deliveryOnFrameCallMs=24.5 deliveryOnFrameCallMaxMs=135.2 deliveryOnFrameCallSamples=90 gpuScaled=90 gpuScaleFailures=0 cpuFallback=12 nativeNv12Submitted=87 nativeNv12Failures=0 nativeNv12OnFrameBackpressureEnabled=true nativeNv12OnFrameBackpressureThresholdMs=20 nativeNv12OnFrameBackpressureFrameLimit=3 nativeNv12SuspendedAfterOnFrameBackpressure=true nativeNv12OnFrameBackpressureFrames=5 nativeNv12OnFrameBackpressureStreak=3 nativeNv12OnFrameBackpressureMaxMs=135.2045 readbackQueued=12 readbackReady=12 readbackNotReady=0 visibleSourceSeen=true',
      ]);

      expect(
        nativeDiagnostics.gameCaptureNativeNv12HandoffDisabledReason,
        'live_onframe_backpressure',
      );
      expect(
        nativeDiagnostics.gameCaptureNativeNv12OnFrameBackpressureEnabled,
        isTrue,
      );
      expect(
        nativeDiagnostics.gameCaptureNativeNv12OnFrameBackpressureThresholdMs,
        20,
      );
      expect(
        nativeDiagnostics.gameCaptureNativeNv12OnFrameBackpressureFrameLimit,
        3,
      );
      expect(
        nativeDiagnostics.gameCaptureNativeNv12OnFrameBackpressureFrames,
        5,
      );
      expect(
        nativeDiagnostics.gameCaptureNativeNv12OnFrameBackpressureStreak,
        3,
      );
      expect(
        nativeDiagnostics.gameCaptureNativeNv12OnFrameBackpressureMaxMs,
        135.2045,
      );
      expect(
        nativeDiagnostics
            .gameCaptureNativeNv12SuspendedAfterOnFrameBackpressure,
        isTrue,
      );
      expect(
        nativeDiagnostics.gameCaptureFrameSummaryLabel,
        allOf(
          contains('native_nv12_onframe_backpressure=enabled:true'),
          contains('suspended:true'),
        ),
      );
      expect(
        nativeDiagnostics.toJson(),
        containsPair(
          'gameCaptureNativeNv12SuspendedAfterOnFrameBackpressure',
          true,
        ),
      );
    });

    test(
      'time-window counters report native NV12 without readback pressure',
      () {
        final startedAt = DateTime.utc(2026, 6, 8, 19, 37);
        final temporal = StreamTestTemporalAnalysis.fromSamplesAndMarkers(
          samples: const [],
          nativeDiagnosticMarkers: [
            '${startedAt.toIso8601String()} native-webrtc '
                'game_capture_webrtc_source stats source=1920x1080 '
                'output=1280x720 format=24 fps=30.0 submitted=0 copied=0 '
                'gpuScaled=0 gpuScaleFailures=0 cpuFallback=0 '
                'nativeNv12Submitted=0 nativeNv12Failures=0 '
                'readbackQueued=0 readbackReady=0 readbackNotReady=0 '
                'readbackLatencyDropped=0 readbackLatencyFramesMax=0 '
                'sourceFrameRegressions=0 sourceFrameGaps=0 '
                'sharedSlotMismatches=0',
            '${startedAt.add(const Duration(seconds: 10)).toIso8601String()} '
                'native-webrtc game_capture_webrtc_source stats '
                'source=1920x1080 output=1280x720 format=24 fps=30.0 '
                'submitted=300 copied=300 gpuScaled=300 '
                'gpuScaleFailures=0 cpuFallback=0 nativeNv12Submitted=300 '
                'nativeNv12Failures=0 readbackQueued=0 readbackReady=0 '
                'readbackNotReady=0 readbackLatencyDropped=0 '
                'readbackLatencyFramesMax=0 sourceFrameRegressions=0 '
                'sourceFrameGaps=0 sharedSlotMismatches=0 '
                'deliveryWallDeltaMaxMs=34.0',
          ],
          targetFps: 30,
          measurementStartedAt: startedAt,
          measurementEndedAt: startedAt.add(const Duration(seconds: 10)),
        );

        final late = temporal.windows.firstWhere(
          (window) => window.label == 'late',
        );
        expect(late.gameCapture?.nativeNv12SubmittedDelta, 300);
        expect(late.gameCapture?.nativeNv12FailuresDelta, 0);
        expect(late.gameCapture?.readbackQueuedDelta, 0);
        expect(late.gameCapture?.compactLabel, contains('native-nv12 +300'));
        expect(
          temporal.lateDegradationSignals.join(' '),
          isNot(contains('readback pressure')),
        );
      },
    );

    test('weights updated-region area ratios by frame count', () {
      final diagnostics = StreamTestNativeDiagnostics.fromMarkers(const [
        '2026-06-02T15:39:41.000Z native-webrtc Inter Galactic desktop capture frame timing avg_convert_ms=3 avg_scale_ms=1 avg_on_frame_ms=0 avg_callback_ms=4 max_callback_ms=6 updated_region_empty=8 updated_region_nonempty=2 updated_region_rects=2 updated_region_max_rects=1 avg_updated_region_area_ratio=0.1 max_updated_region_area_ratio=0.2 avg_updated_region_ms=0.5 max_updated_region_ms=1 updated_region_full_frames=0 updated_region_tiny_frames=1 frames=10',
        '2026-06-02T15:39:43.000Z native-webrtc Inter Galactic desktop capture frame timing avg_convert_ms=3 avg_scale_ms=1 avg_on_frame_ms=0 avg_callback_ms=4 max_callback_ms=6 updated_region_empty=0 updated_region_nonempty=30 updated_region_rects=90 updated_region_max_rects=5 avg_updated_region_area_ratio=0.3 max_updated_region_area_ratio=1 avg_updated_region_ms=1.5 max_updated_region_ms=4 updated_region_full_frames=2 updated_region_tiny_frames=0 frames=30',
      ]);

      expect(diagnostics.updatedRegionEmptyCount, 8);
      expect(diagnostics.updatedRegionNonEmptyCount, 32);
      expect(diagnostics.updatedRegionRectCount, 92);
      expect(diagnostics.updatedRegionMaxRectCount, 5);
      expect(diagnostics.averageUpdatedRegionAreaRatio, closeTo(0.25, 0.001));
      expect(diagnostics.maxUpdatedRegionAreaRatio, 1);
      expect(diagnostics.averageUpdatedRegionAnalysisMs, closeTo(1.25, 0.001));
      expect(diagnostics.maxUpdatedRegionAnalysisMs, 4);
      expect(diagnostics.updatedRegionFullFrameCount, 2);
      expect(diagnostics.updatedRegionTinyFrameCount, 1);
      expect(
        diagnostics.updatedRegionShapeLabel,
        contains('area=25.0% avg / 100.0% max'),
      );
      expect(
        diagnostics.dirtyRegionProcessingAttributionLabel,
        contains('analysis=1ms avg / 4ms max'),
      );
      expect(
        diagnostics.toJson()['averageUpdatedRegionAnalysisMs'],
        closeTo(1.25, 0.001),
      );
    });

    test('exports capture cause attribution for native capture-call causes', () {
      final diagnostics = StreamTestNativeDiagnostics.fromMarkers(const [
        '2026-06-03T16:19:30.000Z native-webrtc Inter Galactic desktop capture pipeline native_source=2560x1440 native_window_rect=2560x1440 requested_max=1280x720 content=1280x720 pre_encode=1280x720 target_fps=30 native_fps=17 scale=down canvas=fixed crop_region=false capturer=window-gdi capturer_id=3 dirty_region_mode=auto',
        '2026-06-03T16:19:31.000Z native-webrtc Inter Galactic desktop capture cadence target_delay_ms=33 avg_capture_call_ms=58.0 max_capture_call_ms=160 scheduled_delay_ms=0 calls=34 submitted_fps=17 temp_errors=0 permanent_errors=0 avg_source_capture_ms=53.0 max_source_capture_ms=158 source_capture_count=34 avg_callback_entry_delay_ms=52.0 max_callback_entry_delay_ms=155 avg_result_callback_ms=5.0 max_result_callback_ms=9.0 avg_acquire_wait_ms=53.0 max_acquire_wait_ms=158 avg_post_callback_wait_ms=1.0 max_post_callback_wait_ms=3.0 avg_unaccounted_wait_ms=0.5 max_unaccounted_wait_ms=2.0 callback_count=34',
        '2026-06-03T16:19:31.100Z native-webrtc Inter Galactic window GDI frame timing source_type=window source_id=123 capture_mode=default calls=34 successes=34 temp_errors=0 permanent_errors=0 hidden_or_minimized=0 rect_fail=0 dc_fail=0 frame_create_fail=0 original_size=2560x1440 cropped_size=2560x1440 frame_size=2560x1440 print_full_calls=34 print_full_successes=34 print_fallback_calls=0 print_fallback_successes=0 bitblt_calls=0 bitblt_successes=0 final_print_full=34 final_print_fallback=0 final_bitblt=0 final_none=0 black_frame_count=0 low_variance_frame_count=0 owned_window_frames=0 owned_capture_calls=0 owned_capture_successes=0 avg_total_ms=53 max_total_ms=158 avg_rect_ms=0.2 max_rect_ms=1 avg_visibility_ms=0.1 max_visibility_ms=1 avg_get_dc_ms=0.1 max_get_dc_ms=1 avg_get_dc_size_ms=0.1 max_get_dc_size_ms=1 avg_create_frame_ms=1.5 max_create_frame_ms=6 avg_mem_dc_ms=0.2 max_mem_dc_ms=1 avg_print_full_ms=48 max_print_full_ms=150 avg_print_fallback_ms=0 max_print_fallback_ms=0 avg_bitblt_ms=0 max_bitblt_ms=0 avg_cleanup_ms=0.2 max_cleanup_ms=1 avg_crop_ms=0 max_crop_ms=0 avg_owned_enum_ms=0 max_owned_enum_ms=0 avg_owned_capture_ms=0 max_owned_capture_ms=0 avg_owned_composite_ms=0 max_owned_composite_ms=0',
        '2026-06-03T16:19:31.200Z native-webrtc Inter Galactic desktop capture frame timing avg_convert_ms=5 avg_scale_ms=2 avg_on_frame_ms=0.5 avg_callback_ms=8 max_callback_ms=16 updated_region_empty=0 updated_region_nonempty=34 updated_region_rects=340 updated_region_max_rects=20 avg_updated_region_area_ratio=0.98 max_updated_region_area_ratio=1 avg_updated_region_ms=1.2 max_updated_region_ms=3 updated_region_full_frames=30 updated_region_tiny_frames=0 capturer=window-gdi capturer_id=3 dirty_region_mode=auto frames=34',
      ]);

      expect(
        diagnostics.fullSourceAcquisitionAttributionLabel,
        allOf(
          contains('source=2560x1440'),
          contains('source_to_content=4.00x'),
        ),
      );
      expect(
        diagnostics.blockingAcquireAttributionLabel,
        contains('acquire_wait=53ms avg / 158ms max'),
      );
      expect(
        diagnostics.cpuReadbackAttributionLabel,
        contains('print_full=48ms avg / 150ms max'),
      );
      expect(
        diagnostics.dirtyRegionProcessingAttributionLabel,
        contains('analysis=1ms avg / 3ms max'),
      );
      expect(
        diagnostics.frameLifetimeSyncAttributionLabel,
        contains('callback_entry=52ms avg / 155ms max'),
      );
      expect(
        diagnostics.fullFrameCopyBeforeDownscaleAttributionLabel,
        contains('pre_scale_full_frame_copy=likely'),
      );
      final attribution =
          diagnostics.toJson()['captureCauseAttribution']
              as Map<String, Object?>;
      expect(
        attribution['fullFrameCopyBeforeDownscale'],
        contains('pre_scale_full_frame_copy=likely'),
      );

      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: DateTime.utc(2026, 6, 3, 16, 19),
        endedAt: DateTime.utc(2026, 6, 3, 16, 20),
        nativeDiagnostics: diagnostics,
        samples: [
          StreamTestSample(
            elapsed: const Duration(seconds: 1),
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 17,
              captureFps: 17,
              encodeFps: 17,
              sendFps: 17,
              bitrateBps: 1800000,
              lossPercent: 0,
              rttMs: 4,
            ),
          ),
        ],
      );
      final coverageItems =
          result.diagnosticCoverage.toJson()['items'] as List<Object?>;
      expect(
        coverageItems,
        contains(
          isA<Map<String, Object?>>()
              .having(
                (item) => item['category'],
                'category',
                'capture cause attribution',
              )
              .having((item) => item['status'], 'status', 'available'),
        ),
      );
      expect(
        coverageItems,
        contains(
          isA<Map<String, Object?>>()
              .having(
                (item) => item['category'],
                'category',
                'dirty-region processing timing',
              )
              .having((item) => item['status'], 'status', 'available'),
        ),
      );

      final run = StreamTestRunResult(
        startedAt: DateTime.utc(2026, 6, 3, 16, 19),
        endedAt: DateTime.utc(2026, 6, 3, 16, 20),
        targetLabel: 'Test room',
        roomId: '!test:ourgalaxy.space',
        config: const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 1),
        ),
        presetResults: [result],
      );
      final markdown = run.toMarkdown();
      expect(markdown, contains('## Capture Cause Attribution'));
      expect(markdown, contains('Full-Frame Copy Before Downscale'));
      expect(markdown, contains('pre_scale_full_frame_copy=likely'));
    });

    test('parses native latest-frame pacer diagnostics', () {
      final diagnostics = StreamTestNativeDiagnostics.fromMarkers(const [
        '2026-05-28T04:00:00.000Z native-webrtc Inter Galactic desktop capture bridge start source_type=window requested_max=1280x720 fps=36 capture_backend=directx-only frame_pacing=latest',
        '2026-05-28T04:00:02.000Z native-webrtc Inter Galactic desktop capture latest-frame pacer cadence enabled=true target_fps=36 submitted_fps=35.7 unique_fps=27.4 p95_interval_ms=33.0 max_interval_ms=50.0 avg_frame_age_ms=12.0 max_frame_age_ms=45.0 avg_on_frame_ms=0.8 max_on_frame_ms=2.4 duplicate_submits=17 overwritten_frames=8 skipped_ticks=1 ticks=72',
      ]);

      expect(diagnostics.backendLabel, 'directx-only');
      expect(diagnostics.latestFramePacerEnabled, isTrue);
      expect(diagnostics.averageSubmittedFps, 35.7);
      expect(diagnostics.averagePacerUniqueFps, 27.4);
      expect(diagnostics.p95PacerIntervalMs, 33);
      expect(diagnostics.maxPacerFrameAgeMs, 45);
      expect(diagnostics.pacerDuplicateSubmitCount, 17);
      expect(diagnostics.pacerOverwrittenFrameCount, 8);
      expect(diagnostics.pacerSkippedTickCount, 1);
      expect(diagnostics.summaryLabel, contains('pacer=on'));
      expect(
        diagnostics.toJson(),
        containsPair('averagePacerSubmittedFps', 35.7),
      );
    });

    test('parses native window geometry pipeline markers', () {
      final diagnostics = StreamTestNativeDiagnostics.fromMarkers(const [
        '2026-05-19T14:37:42.000Z native-webrtc Inter Galactic desktop capture pipeline native_source=1920x1032 native_window_rect=1936x1048 requested_max=1280x720 content=1280x688 pre_encode=1280x720 target_fps=30 native_fps=27.7 scale=down canvas=letterbox crop_region=false',
      ]);

      expect(diagnostics.nativeSourceResolutionLabel, '1920x1032');
      expect(diagnostics.nativeWindowRectResolutionLabel, '1936x1048');
      expect(diagnostics.requestedMaxResolutionLabel, '1280x720');
      expect(diagnostics.contentResolutionLabel, '1280x688');
      expect(diagnostics.preEncodeResolutionLabel, '1280x720');
      expect(diagnostics.canvasLabel, 'letterbox');
      expect(diagnostics.cropRegion, isFalse);
      expect(diagnostics.averageNativeFps, 27.7);
      expect(
        diagnostics.summaryLabel,
        contains('window_rect=1936x1048 content=1280x688'),
      );
      expect(diagnostics.toJson(), containsPair('canvas', 'letterbox'));

      final run = StreamTestRunResult(
        startedAt: DateTime.utc(2026, 5, 19, 14, 37),
        endedAt: DateTime.utc(2026, 5, 19, 14, 37, 2),
        targetLabel: 'Test room',
        roomId: '!test:ourgalaxy.space',
        config: const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 2),
        ),
        presetResults: [
          StreamTestPresetResult(
            profile: ScreenShareProfileConfig.smooth,
            startedAt: DateTime.utc(2026, 5, 19, 14, 37),
            endedAt: DateTime.utc(2026, 5, 19, 14, 37, 2),
            nativeDiagnostics: diagnostics,
            samples: [
              StreamTestSample(
                elapsed: const Duration(seconds: 1),
                snapshot: _snapshot(
                  width: 1280,
                  height: 720,
                  fps: 28,
                  captureFps: 28,
                  encodeFps: 28,
                  sendFps: 28,
                  bitrateBps: 1800000,
                  lossPercent: 0,
                  rttMs: 20,
                ),
              ),
            ],
          ),
        ],
      );
      final markdown = run.toMarkdown();
      expect(
        markdown,
        contains(
          '| Preset | Backend | Observed Capturer | Dirty Mode | Native Source | Window Rect | Content | Pre-encode | Canvas |',
        ),
      );
      expect(
        markdown,
        contains(
          '| Smooth | App default | unknown | unknown | 1920x1032 | 1936x1048 | 1280x688 | 1280x720 | letterbox |',
        ),
      );
    });

    test('keeps native markers inside their owning preset window', () async {
      var now = DateTime.utc(2026, 5, 19, 18);
      final runner = StreamTestRunner(
        target: _FakeStreamTestTarget(
          snapshot: _snapshot(
            width: 1280,
            height: 720,
            fps: 30,
            bitrateBps: 1800000,
            lossPercent: 0,
            rttMs: 20,
          ),
        ),
        clock: () => now,
        delay: (duration) async {
          now = now.add(duration);
        },
        diagnosticLogProvider: () async => '''
2026-05-19T18:00:00.100Z native-webrtc Inter Galactic desktop capture options type=window mode=directx-only detect_updated_region=1 directx=1 crop_window=0 wgc_screen=0 wgc_window=0 wgc_fallback=0
2026-05-19T18:00:01.500Z native-webrtc Inter Galactic desktop capture pipeline native_source=1920x1080 requested_max=1280x720 pre_encode=1280x720 target_fps=30 native_fps=30 scale=down crop_region=false
2026-05-19T18:00:02.100Z native-webrtc Inter Galactic desktop capture options type=window mode=wgc-only detect_updated_region=1 directx=0 crop_window=0 wgc_screen=1 wgc_window=1 wgc_fallback=0
2026-05-19T18:00:03.500Z native-webrtc Inter Galactic desktop capture pipeline native_source=1920x1080 requested_max=1920x1080 pre_encode=1920x1080 target_fps=30 native_fps=30 scale=none crop_region=false
''',
      );

      final result = await runner.run(
        const StreamTestRunConfig(
          presets: [
            ScreenShareProfileConfig.smooth,
            ScreenShareProfileConfig.balanced,
          ],
          durationPerPreset: Duration(seconds: 2),
          warmupDuration: Duration.zero,
          sampleInterval: Duration(seconds: 1),
        ),
      );

      expect(
        result.presetResults.first.nativeDiagnostics.backendLabel,
        'directx-only',
      );
      expect(
        result.presetResults.first.nativeDiagnostics.preEncodeResolutionLabel,
        '1280x720',
      );
      expect(
        result.presetResults.last.nativeDiagnostics.backendLabel,
        'wgc-only',
      );
      expect(
        result.presetResults.last.nativeDiagnostics.preEncodeResolutionLabel,
        '1920x1080',
      );
    });

    test(
      'captures per-preset native markers before final log tail drops them',
      () async {
        var now = DateTime.utc(2026, 5, 19, 18);
        var markerReadCount = 0;
        final runner = StreamTestRunner(
          target: _FakeStreamTestTarget(
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 30,
              bitrateBps: 1800000,
              lossPercent: 0,
              rttMs: 20,
            ),
          ),
          clock: () => now,
          delay: (duration) async {
            now = now.add(duration);
          },
          diagnosticLogProvider: () async {
            markerReadCount++;
            return switch (markerReadCount) {
              1 =>
                '''
2026-05-19T18:00:00.100Z native-webrtc Inter Galactic desktop capture options type=window mode=directx-only detect_updated_region=1 directx=1 crop_window=0 wgc_screen=0 wgc_window=0 wgc_fallback=0
2026-05-19T18:00:00.500Z native-webrtc Inter Galactic desktop capture pipeline native_source=1920x1080 requested_max=1280x720 pre_encode=1280x720 target_fps=30 native_fps=30 scale=down crop_region=false
''',
              _ =>
                '''
2026-05-19T18:00:01.100Z native-webrtc Inter Galactic desktop capture options type=window mode=wgc-only detect_updated_region=1 directx=0 crop_window=0 wgc_screen=1 wgc_window=1 wgc_fallback=0
2026-05-19T18:00:01.500Z native-webrtc Inter Galactic desktop capture pipeline native_source=1920x1080 requested_max=1920x1080 pre_encode=1920x1080 target_fps=30 native_fps=30 scale=none crop_region=false
''',
            };
          },
        );

        final result = await runner.run(
          const StreamTestRunConfig(
            presets: [
              ScreenShareProfileConfig.smooth,
              ScreenShareProfileConfig.balanced,
            ],
            durationPerPreset: Duration(seconds: 1),
            warmupDuration: Duration.zero,
            sampleInterval: Duration(seconds: 1),
          ),
        );

        expect(
          result.presetResults.first.nativeDiagnostics.backendLabel,
          'directx-only',
        );
        expect(
          result.presetResults.first.nativeDiagnostics.preEncodeResolutionLabel,
          '1280x720',
        );
        expect(
          result.presetResults.last.nativeDiagnostics.backendLabel,
          'wgc-only',
        );
        expect(
          result.presetResults.last.nativeDiagnostics.preEncodeResolutionLabel,
          '1920x1080',
        );
        expect(
          result.diagnosticLogMarkers.join('\n'),
          contains('directx-only'),
        );
        expect(result.diagnosticLogMarkers.join('\n'), contains('wgc-only'));
      },
    );

    test('exports native diagnostic marker tail when provided', () async {
      var now = DateTime.utc(2026, 5, 18, 18);
      final runner = StreamTestRunner(
        target: _FakeStreamTestTarget(
          snapshot: _snapshot(
            width: 1280,
            height: 720,
            fps: 30,
            bitrateBps: 1800000,
            lossPercent: 0,
            rttMs: 20,
          ),
        ),
        clock: () => now,
        delay: (duration) async {
          now = now.add(duration);
        },
        diagnosticLogProvider: () async => '''
ordinary unrelated line
[2026-05-19T01:53:10Z] INFO webrtc Inter Galactic: desktop capture cadence target_ms=33 capture_ms=11 delay_ms=22 source_title="Private Game" pid=42
[2026-05-19T01:53:11Z] INFO webrtc Inter Galactic: Media Foundation H.264 encoder timing frame=30 total=78ms process_output=70ms
''',
      );

      final result = await runner.run(
        const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 1),
          windowsCaptureBackendMode: WindowsScreenCaptureBackendMode.wgcOnly,
        ),
      );

      expect(result.diagnosticLogMarkers, hasLength(2));
      expect(
        result.toJsonText(),
        contains('Media Foundation H.264 encoder timing'),
      );
      expect(result.toMarkdown(), contains('## Native Diagnostic Markers'));
      expect(
        result.toMarkdown(),
        contains('Windows capture backend: WGC only'),
      );
      expect(
        result.toMarkdown(),
        contains('desktop capture cadence target_ms=33'),
      );
      expect(result.toJsonText(), isNot(contains('Private Game')));
      expect(result.toMarkdown(), isNot(contains('Private Game')));
      expect(result.toJsonText(), isNot(contains('pid=42')));
      expect(result.toMarkdown(), isNot(contains('pid=42')));
    });

    test('preserves game-hook markers when diagnostic tail is noisy', () async {
      var now = DateTime.utc(2026, 6, 5, 12, 16);
      final runner = StreamTestRunner(
        target: _FakeStreamTestTarget(
          snapshot: _snapshot(
            width: 1280,
            height: 720,
            fps: 8,
            captureFps: 34,
            encodeFps: 8,
            sendFps: 8,
            bitrateBps: 600000,
            lossPercent: 0,
            rttMs: 3,
          ),
        ),
        clock: () => now,
        delay: (duration) async {
          now = now.add(duration);
        },
        diagnosticLogMarkerLimit: 6,
        diagnosticLogProvider: () async => '''
2026-06-05T12:16:00.100Z native-webrtc Inter Galactic window GDI frame timing source_type=window source_id=68658 capture_mode=default calls=8 successes=8 frame_size=1x1 black_frame_count=8 low_variance_frame_count=8 avg_total_ms=40 max_total_ms=90
2026-06-05T12:16:00.200Z native-webrtc game_capture_webrtc_source skip_initial_black frame=1 source=2560x1440 output=1280x720 format=24 visible=false minLuma=0 maxLuma=0 nonzeroSamples=0 samples=1056 initialBlackSkipped=1
2026-06-05T12:16:00.300Z native-webrtc game_capture_webrtc_source proof frame=1 source=2560x1440 output=1280x720 format=24 visible=true minLuma=1 maxLuma=209 nonzeroSamples=1055 samples=1056 wrote=true path="repo-fixtures/visible.bmp"
2026-06-05T12:16:00.400Z native-webrtc game_capture_webrtc_source i420_proof frame=1 source=2560x1440 output=1280x720 format=24 visible=true minLuma=1 maxLuma=205 nonzeroSamples=1048 samples=1056 wrote=true conversionFailed=false path="repo-fixtures/visible-i420.bmp"
2026-06-05T12:16:00.500Z native-webrtc game_capture_webrtc_source stats source=2560x1440 output=1280x720 format=24 fps=34.2 submitted=177 repeated=25 copied=152 dropped=0 overwritten=149 gpuScaled=177 gpuScaleFailures=0 cpuFallback=0 readbackQueued=180 readbackReady=177 readbackNotReady=3 readbackOverwritten=1 readbackLatencyDropped=4 readbackMapAttempts=180 readbackLatencyMs=35.0 readbackLatencyFramesAvg=1.2 readbackLatencyFramesMax=2 sourceFrameIndex=422 lastSubmittedSourceFrameIndex=421 sourceFrameRegressions=0 sourceFrameDuplicates=25 sourceFrameGaps=220 sharedSlotMismatches=0 copyMs=0.2 mapMs=3.9 convertMs=15.3 gpuScaleMs=0.4 mapFailures=0 convertFailures=0 proofFrames=1 visibleProofFrames=1 i420ProofFrames=1 visibleI420ProofFrames=1 initialBlackSkipped=1 visibleSourceSeen=true
2026-06-05T12:16:00.600Z native-webrtc Inter Galactic Media Foundation H.264 encoder timing frame=1 total_ms=2.0 slow=no
2026-06-05T12:16:00.700Z native-webrtc Inter Galactic Media Foundation H.264 encoder timing frame=2 total_ms=2.0 slow=no
2026-06-05T12:16:00.800Z native-webrtc Inter Galactic Media Foundation H.264 encoder timing frame=3 total_ms=2.0 slow=no
2026-06-05T12:16:00.900Z native-webrtc Inter Galactic Media Foundation H.264 encoder timing frame=4 total_ms=2.0 slow=no
''',
      );

      final result = await runner.run(
        const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 1),
          warmupDuration: Duration.zero,
          sampleInterval: Duration(seconds: 1),
          windowsCaptureBackendMode:
              WindowsScreenCaptureBackendMode.gameD3d11HookExperimental,
        ),
      );

      final diagnostics = result.presetResults.single.nativeDiagnostics;
      expect(diagnostics.observedCapturerLabel, 'game-d3d11-hook');
      expect(diagnostics.gameCaptureInitialBlackSkippedFrames, 1);
      expect(diagnostics.gameCaptureVisibleSourceSeen, isTrue);
      expect(diagnostics.gameCaptureProofVisible, isTrue);
      expect(diagnostics.gameCaptureI420ProofVisible, isTrue);
      expect(diagnostics.gameCaptureSubmittedFrames, 177);
      expect(diagnostics.gameCaptureGpuScaledFrames, 177);
      expect(diagnostics.gameCaptureCpuFallbackFrames, 0);
      expect(diagnostics.gameCaptureReadbackQueuedFrames, 180);
      expect(diagnostics.gameCaptureReadbackReadyFrames, 177);
      expect(diagnostics.gameCaptureReadbackNotReadyFrames, 3);
      expect(diagnostics.gameCaptureReadbackOverwrittenFrames, 1);
      expect(diagnostics.gameCaptureReadbackLatencyDroppedFrames, 4);
      expect(diagnostics.gameCaptureReadbackMapAttempts, 180);
      expect(diagnostics.gameCaptureSourceFrameIndex, 422);
      expect(diagnostics.gameCaptureLastSubmittedSourceFrameIndex, 421);
      expect(diagnostics.gameCaptureSourceFrameRegressions, 0);
      expect(diagnostics.gameCaptureSourceFrameDuplicates, 25);
      expect(diagnostics.gameCaptureSourceFrameGaps, 220);
      expect(diagnostics.gameCaptureSharedSlotMismatches, 0);
      expect(diagnostics.averageGameCaptureReadbackLatencyMs, 35.0);
      expect(diagnostics.averageGameCaptureReadbackLatencyFrames, 1.2);
      expect(diagnostics.gameCaptureMaxReadbackLatencyFrames, 2);
      expect(
        result.diagnosticLogMarkers.join('\n'),
        contains('game_capture_webrtc_source stats'),
      );
      expect(result.toMarkdown(), contains('initial_black_skipped=1'));
      expect(result.toMarkdown(), contains('source_regressions=0'));
      expect(result.toMarkdown(), contains('readback=180/177'));
      expect(result.toMarkdown(), contains('readback_latency_dropped=4'));
      expect(
        result.diagnosticCoverage.toMarkdownTable(),
        contains('game-capture frame order'),
      );
      expect(
        result.toJsonText(),
        contains('"gameCaptureSourceFrameRegressions"'),
      );
    });

    test('exports source metadata and bottleneck diagnostics', () {
      final run = StreamTestRunResult(
        startedAt: DateTime.utc(2026, 5, 18, 18),
        endedAt: DateTime.utc(2026, 5, 18, 18, 0, 2),
        targetLabel: 'Test room',
        roomId: '!test:ourgalaxy.space',
        config: const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 2),
          scenarioLabel: 'Private Room Name:share',
          sourceMetadata: StreamTestSourceMetadata(
            sourceType: 'window',
            sourceIdHash: 'abc12345',
            processId: 42,
            audioRequested: true,
            audioMode: 'processTreeLoopback',
            audioState: 'active',
            audioReason: 'ok',
            sourceTitle: 'Test Game',
            sourceRuntimeType: 'WebrtcScreencaptureSource',
          ),
        ),
        presetResults: [
          StreamTestPresetResult(
            profile: ScreenShareProfileConfig.smooth,
            startedAt: DateTime.utc(2026, 5, 18, 18),
            endedAt: DateTime.utc(2026, 5, 18, 18, 0, 2),
            samples: [
              StreamTestSample(
                elapsed: const Duration(seconds: 1),
                snapshot: _snapshot(
                  width: 1280,
                  height: 720,
                  fps: 3,
                  captureFps: 12,
                  encodeFps: 3,
                  sendFps: 3,
                  averageEncodeTimeMs: 500,
                  bitrateBps: 800000,
                  lossPercent: 0,
                  rttMs: 20,
                ),
              ),
            ],
          ),
        ],
      );

      final jsonText = run.toJsonText();
      final markdown = run.toMarkdown();
      expect(jsonText, contains('"sourceIdHash": "abc12345"'));
      expect(jsonText, contains('"bottleneck"'));
      expect(jsonText, contains('"label": "encode_limited"'));
      expect(jsonText, contains('"averageCaptureFps": 12.0'));
      expect(jsonText, contains('"processIdAvailable": true'));
      expect(jsonText, contains('"sourceTitleAvailable": true'));
      expect(jsonText, contains('"roomId": "[MATRIX_ROOM_ID]"'));
      expect(jsonText, isNot(contains('!test:ourgalaxy.space')));
      expect(jsonText, isNot(contains('Test room')));
      expect(jsonText, isNot(contains('Private Room Name')));
      expect(jsonText, isNot(contains('"processId": 42')));
      expect(jsonText, isNot(contains('Test Game')));
      expect(markdown, contains('Windows capture backend: App default'));
      expect(
        markdown,
        contains(
          'Source: type=window sourceIdHash=abc12345 '
          'pidAvailable=yes titleAvailable=yes',
        ),
      );
      expect(markdown, contains('Room: [MATRIX_ROOM_ID]'));
      expect(markdown, isNot(contains('!test:ourgalaxy.space')));
      expect(markdown, isNot(contains('Test room')));
      expect(markdown, isNot(contains('Private Room Name')));
      expect(markdown, isNot(contains('pid=42')));
      expect(markdown, isNot(contains('Test Game')));
      expect(
        markdown,
        contains(
          '| Smooth | App default | Default window GDI | unknown | encode_limited |',
        ),
      );
      expect(markdown, contains('Average capture FPS: 12.0'));
      expect(markdown, contains('Average encode FPS: 3.0'));
      expect(
        markdown,
        contains('Capture pipeline: requested=1280x720@30.0fps'),
      );
    });

    test('exports diagnostic coverage matrix in JSON and Markdown', () {
      final run = StreamTestRunResult(
        startedAt: DateTime.utc(2026, 6, 2, 22),
        endedAt: DateTime.utc(2026, 6, 2, 22, 0, 2),
        targetLabel: 'Test room',
        roomId: '!test:ourgalaxy.space',
        config: const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
          durationPerPreset: Duration(seconds: 2),
          sourceMetadata: StreamTestSourceMetadata(
            sourceType: 'window',
            sourceIdHash: 'abc12345',
          ),
        ),
        presetResults: [
          StreamTestPresetResult(
            profile: ScreenShareProfileConfig.smooth,
            startedAt: DateTime.utc(2026, 6, 2, 22),
            endedAt: DateTime.utc(2026, 6, 2, 22, 0, 2),
            nativeDiagnostics: StreamTestNativeDiagnostics.fromMarkers(const [
              '2026-06-02T22:00:00.000Z native-webrtc Inter Galactic desktop capture options type=window mode=directx-only dirty_region_mode=force-full-frame directx=1 crop_window=0 wgc_screen=0 wgc_window=0 wgc_fallback=0',
              '2026-06-02T22:00:01.000Z native-webrtc Inter Galactic desktop capture pipeline native_source=1920x1080 requested_max=1280x720 content=1280x720 pre_encode=1280x720 target_fps=30 native_fps=30 scale=down canvas=fixed crop_region=false capturer=directx',
              '2026-06-02T22:00:02.000Z native-webrtc Inter Galactic desktop capture frame timing avg_convert_ms=0.3 avg_scale_ms=0.2 avg_on_frame_ms=0.1 avg_callback_ms=0.7 max_callback_ms=1.1 updated_region_empty=0 updated_region_nonempty=30 updated_region_rects=30 updated_region_max_rects=1 avg_updated_region_area_ratio=1 max_updated_region_area_ratio=1 updated_region_full_frames=30 updated_region_tiny_frames=0 frames=30',
            ]),
            samples: [
              StreamTestSample(
                elapsed: const Duration(seconds: 1),
                snapshot: _snapshot(
                  width: 1280,
                  height: 720,
                  fps: 30,
                  bitrateBps: 1800000,
                  lossPercent: 0,
                  rttMs: 20,
                  encoderImplementation: 'libvpx',
                  hardwareEncodeActive: false,
                ),
              ),
            ],
          ),
        ],
      );

      final json = run.toJson();
      final coverage = json['diagnosticCoverage'] as Map<String, Object?>;
      final coverageItems = coverage['items'] as List<Object?>;
      expect(
        coverageItems,
        contains(
          isA<Map<String, Object?>>()
              .having((item) => item['category'], 'category', 'sender stats')
              .having((item) => item['status'], 'status', 'available'),
        ),
      );
      expect(
        coverageItems,
        contains(
          isA<Map<String, Object?>>()
              .having((item) => item['category'], 'category', 'receiver stats')
              .having((item) => item['status'], 'status', 'missing'),
        ),
      );
      expect(
        coverageItems,
        contains(
          isA<Map<String, Object?>>()
              .having(
                (item) => item['category'],
                'category',
                'loaded libwebrtc hash',
              )
              .having((item) => item['status'], 'status', 'unavailable'),
        ),
      );
      expect(run.toJsonText(), contains('"diagnosticCoverage"'));

      final markdown = run.toMarkdown();
      expect(markdown, contains('## Executive Summary'));
      expect(markdown, contains('## Diagnostic Coverage'));
      expect(markdown, contains('[PASS] available'));
      expect(markdown, contains('receiver render FPS'));
      expect(markdown, contains('loaded libwebrtc artifact identity'));
      expect(markdown, contains('Recommended next action:'));
    });

    test('native capture limited includes confidence and next action', () {
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: DateTime.utc(2026, 6, 2, 19, 44, 24),
        endedAt: DateTime.utc(2026, 6, 2, 19, 45, 24),
        nativeDiagnostics: StreamTestNativeDiagnostics.fromMarkers(const [
          '2026-06-02T19:44:40.000Z native-webrtc Inter Galactic desktop capture options type=window mode=wgc-only dirty_region_mode=force-full-frame detect_updated_region=0 directx=0 crop_window=0 wgc_screen=1 wgc_window=1 wgc_fallback=0',
          '2026-06-02T19:44:42.000Z native-webrtc Inter Galactic desktop capture pipeline native_source=2560x1440 native_window_rect=2560x1440 requested_max=1280x720 content=1280x720 pre_encode=1280x720 target_fps=30 native_fps=13.4 scale=down canvas=fixed crop_region=false capturer=WgcCapturerWin capturer_id=4 dirty_region_mode=force-full-frame',
          '2026-06-02T19:44:42.000Z native-webrtc Inter Galactic desktop capture cadence target_delay_ms=33 avg_capture_call_ms=82.0 max_capture_call_ms=240 scheduled_delay_ms=0 calls=24 submitted_fps=13.4 temp_errors=0 permanent_errors=0 avg_source_capture_ms=80.0 max_source_capture_ms=238 source_capture_count=24 avg_callback_entry_delay_ms=79.0 max_callback_entry_delay_ms=236 avg_result_callback_ms=1.0 max_result_callback_ms=3.0 avg_acquire_wait_ms=78.0 max_acquire_wait_ms=230 avg_post_callback_wait_ms=0.0 max_post_callback_wait_ms=0.0 avg_unaccounted_wait_ms=1.0 max_unaccounted_wait_ms=2.0 callback_count=24',
          '2026-06-02T19:44:42.000Z native-webrtc Inter Galactic wgc frame timing calls=24 successes=24 source_not_capturable=0 ensure_calls=24 ensure_sleeps=0 process_calls=24 process_successes=24 frame_pool_empty=0 frame_pool_reuse=0 capture_frame_null=0 mapped_texture_creates=1 resizes=0 frame_pool_recreates=0 avg_try_get_frame_ms=64.0 max_try_get_frame_ms=220 avg_map_texture_ms=2.0 max_map_texture_ms=4.0 avg_copy_rows_ms=1.0 max_copy_rows_ms=2.0',
          '2026-06-02T19:44:43.000Z native-webrtc Inter Galactic Media Foundation H.264 encoder timing frame=120 total_ms=3.0 process_output_ms=0.1 slow=no',
        ]),
        samples: [
          StreamTestSample(
            elapsed: const Duration(seconds: 1),
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 13,
              captureFps: 13,
              encodeFps: 13,
              sendFps: 13,
              averageEncodeTimeMs: 80,
              bitrateBps: 900000,
              lossPercent: 0,
              rttMs: 2,
            ),
          ),
        ],
      );

      expect(result.score.bottleneck.label, 'native_capture_limited');
      expect(result.score.bottleneck.confidence, 'high');
      expect(result.score.bottleneck.recommendedNextAction, 'fix WGC substage');
      expect(
        result.score.bottleneck.evidenceAgainstFalseCauses.join(' '),
        contains('native encoder timing'),
      );
      expect(
        streamTestRecommendedNextActions,
        contains(result.score.bottleneck.recommendedNextAction),
      );
    });

    test('duplicate-skipped game hook ticks are source-present limited', () {
      final startedAt = DateTime.utc(2026, 6, 7, 14, 10, 48);
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.highQuality,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 30)),
        nativeDiagnostics: StreamTestNativeDiagnostics.fromMarkers(const [
          '2026-06-07T14:11:09.385Z native-webrtc game_capture_webrtc_source stats source=2560x1440 output=1920x1080 format=24 fps=30.001104 submitted=605 repeated=0 duplicateSkipped=604 deliveryQueued=605 deliverySubmitted=605 deliveryOverwritten=0 deliveryOnFrameMs=0.279733 deliveryOnFrameMaxMs=1.840200 copied=606 dropped=0 overwritten=603 gpuScaled=605 gpuScaleFailures=0 cpuFallback=0 readbackQueued=606 readbackReady=605 readbackNotReady=606 readbackOverwritten=0 readbackStaleDropped=0 readbackLatencyDropped=0 readbackMapAttempts=1211 gpuScaleMs=0.012216 copyMs=0.181756 mapMs=0.009084 convertMs=1.409863 readbackLatencyMs=31.372774 readbackLatencyFramesAvg=0.026490 readbackLatencyFramesMax=1 sourceFrameIndex=606 lastSubmittedSourceFrameIndex=605 sourceFrameRegressions=0 sourceFrameDuplicates=0 sourceFrameGaps=0 sharedSlotMismatches=0 mapFailures=0 convertFailures=0 proofFrames=1 visibleProofFrames=1 i420ProofFrames=1 visibleI420ProofFrames=1 initialBlackSkipped=0 visibleSourceSeen=true',
          '2026-06-07T14:11:09.385Z native-webrtc Inter Galactic Media Foundation H.264 encoder timing frame=600 total_ms=3.0 process_output_ms=0.1 slow=no',
        ]),
        samples: [
          StreamTestSample(
            elapsed: Duration.zero,
            snapshot: _snapshot(
              width: 1920,
              height: 1080,
              fps: 60,
              captureFps: 30,
              encodeFps: 30,
              sendFps: 30,
              averageEncodeTimeMs: 33,
              bitrateBps: 5000000,
              lossPercent: 0,
              rttMs: 3,
              requestedWidth: 1920,
              requestedHeight: 1080,
              requestedFps: 60,
              framesCaptured: 0,
              framesEncoded: 0,
              framesSent: 0,
            ),
          ),
          StreamTestSample(
            elapsed: const Duration(seconds: 1),
            snapshot: _snapshot(
              width: 1920,
              height: 1080,
              fps: 60,
              captureFps: 30,
              encodeFps: 30,
              sendFps: 30,
              averageEncodeTimeMs: 33,
              bitrateBps: 5000000,
              lossPercent: 0,
              rttMs: 3,
              requestedWidth: 1920,
              requestedHeight: 1080,
              requestedFps: 60,
              framesCaptured: 30,
              framesEncoded: 30,
              framesSent: 30,
            ),
          ),
        ],
      );

      expect(result.nativeDiagnostics.gameCaptureDuplicateSkippedFrames, 604);
      expect(
        result.nativeDiagnostics.gameCaptureFrameSummaryLabel,
        contains('duplicate_skipped=604'),
      );
      expect(result.score.bottleneck.label, 'source_present_limited');
      expect(
        result.score.bottleneck.reasons.join(' '),
        contains('skipped 604 duplicate source ticks'),
      );
      expect(
        result.score.bottleneck.recommendedNextAction,
        'no stream change recommended',
      );
    });

    test('game hook delivery timestamp spikes are frame pacing evidence', () {
      final startedAt = DateTime.utc(2026, 6, 7, 19, 10, 43);
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.balanced,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 30)),
        nativeDiagnostics: StreamTestNativeDiagnostics.fromMarkers(const [
          '2026-06-07T19:11:16.000Z native-webrtc game_capture_webrtc_source stats source=2560x1440 output=1440x810 format=24 fps=30.0 submitted=900 repeated=0 duplicateSkipped=0 deliveryQueued=900 deliverySubmitted=900 deliveryOverwritten=0 deliveryOnFrameMs=0.22 deliveryOnFrameMaxMs=1.2 copied=901 dropped=0 overwritten=898 gpuScaled=900 gpuScaleFailures=0 cpuFallback=0 readbackQueued=901 readbackReady=900 readbackNotReady=40 readbackOverwritten=0 readbackStaleDropped=0 readbackLatencyDropped=0 readbackMapAttempts=941 gpuScaleMs=0.012 copyMs=0.18 mapMs=0.004 readbackLatencyMs=31.1 readbackLatencyFramesAvg=0.1 readbackLatencyFramesMax=1 sourceFrameIndex=901 lastSubmittedSourceFrameIndex=900 sourceFrameRegressions=0 sourceFrameDuplicates=0 sourceFrameGaps=0 sharedSlotMismatches=0 timestampMode=delivery timestampDeltaMs=33.3 timestampDeltaMaxMs=58.0 timestampSamples=899 timestampAdjustments=0 sourceQpcDeltaMs=16.7 sourceQpcDeltaMaxMs=24.0 sourceQpcSamples=899 sourceQpcRegressions=0 convertMs=1.4 mapFailures=0 convertFailures=0 proofFrames=1 visibleProofFrames=1 i420ProofFrames=1 visibleI420ProofFrames=1 initialBlackSkipped=0 visibleSourceSeen=true',
          '2026-06-07T19:11:16.000Z native-webrtc Inter Galactic Media Foundation H.264 encoder timing frame=900 total_ms=3.0 process_output_ms=0.1 slow=no',
        ]),
        samples: [
          StreamTestSample(
            elapsed: Duration.zero,
            snapshot: _snapshot(
              width: 1440,
              height: 810,
              fps: 30,
              captureFps: 30,
              encodeFps: 30,
              sendFps: 30,
              averageEncodeTimeMs: 33,
              bitrateBps: 6500000,
              lossPercent: 0,
              rttMs: 4,
              requestedWidth: 1440,
              requestedHeight: 810,
              requestedFps: 30,
              framesCaptured: 0,
              framesEncoded: 0,
              framesSent: 0,
            ),
          ),
          StreamTestSample(
            elapsed: const Duration(seconds: 1),
            snapshot: _snapshot(
              width: 1440,
              height: 810,
              fps: 30,
              captureFps: 30,
              encodeFps: 30,
              sendFps: 30,
              averageEncodeTimeMs: 33,
              bitrateBps: 6500000,
              lossPercent: 0,
              rttMs: 4,
              requestedWidth: 1440,
              requestedHeight: 810,
              requestedFps: 30,
              framesCaptured: 30,
              framesEncoded: 30,
              framesSent: 30,
            ),
          ),
        ],
      );

      expect(result.score.bottleneck.label, 'frame_pacing_unstable');
      expect(
        result.score.bottleneck.reasons.join(' '),
        contains('delivery timestamp delta peaked at 58.0ms'),
      );
      expect(
        result.score.bottleneck.evidenceFor.join(' '),
        contains('timestamp mode delivery'),
      );
      expect(
        result.diagnosticCoverage.toMarkdownTable(),
        allOf(
          contains('game-capture frame order'),
          contains('timestamp=delivery'),
          contains('timestampMax=58ms'),
        ),
      );
    });

    test('game hook repeated frames are visual frame pacing evidence', () {
      final startedAt = DateTime.utc(2026, 6, 7, 21, 10, 5);
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.balanced,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 30)),
        nativeDiagnostics: StreamTestNativeDiagnostics.fromMarkers(const [
          '2026-06-07T21:11:20.000Z native-webrtc game_capture_webrtc_source stats source=2560x1440 output=1440x810 format=24 fps=30.0 submitted=900 repeated=260 duplicateSkipped=0 deliveryQueued=900 deliverySubmitted=900 deliveryOverwritten=260 deliveryOnFrameMs=0.2 deliveryOnFrameMaxMs=2.0 readyToQueueMs=0.01 readyToQueueMaxMs=10.0 deliveryQueueWaitMs=13.0 deliveryQueueWaitMaxMs=34.0 readyToSubmitMs=13.0 readyToSubmitMaxMs=34.0 sourceToSubmitMs=60.0 sourceToSubmitMaxMs=236.0 copied=901 dropped=0 overwritten=898 gpuScaled=900 gpuScaleFailures=0 cpuFallback=0 readbackQueued=901 readbackReady=900 readbackNotReady=5000 readbackOverwritten=0 readbackStaleDropped=0 readbackLatencyDropped=0 readbackMapAttempts=5901 gpuScaleMs=0.012 copyMs=0.14 mapMs=0.008 readbackLatencyMs=57.0 readbackLatencyFramesAvg=1.4 readbackLatencyFramesMax=7 sourceFrameIndex=1800 lastSubmittedSourceFrameIndex=1799 sourceFrameRegressions=0 sourceFrameDuplicates=260 sourceFrameGaps=1000 sharedSlotMismatches=0 timestampMode=paced timestampDeltaMs=33.3 timestampDeltaMaxMs=33.3 timestampSamples=899 timestampAdjustments=0 deliveryWallDeltaMs=33.3 deliveryWallDeltaMaxMs=35.0 deliveryWallOver2x=0 deliveryWallOver3x=0 deliveryWallUnderHalf=0 sourceQpcDeltaMs=50.0 sourceQpcDeltaMaxMs=165.0 sourceQpcSamples=640 sourceQpcRegressions=0 convertMs=1.0 mapFailures=0 convertFailures=0 proofFrames=1 visibleProofFrames=1 i420ProofFrames=1 visibleI420ProofFrames=1 initialBlackSkipped=0 visibleSourceSeen=true',
          '2026-06-07T21:11:20.000Z native-webrtc Inter Galactic Media Foundation H.264 encoder timing frame=900 total_ms=4.0 process_output_ms=0.1 slow=no',
        ]),
        samples: [
          StreamTestSample(
            elapsed: Duration.zero,
            snapshot: _snapshot(
              width: 1440,
              height: 810,
              fps: 30,
              captureFps: 30,
              encodeFps: 30,
              sendFps: 30,
              averageEncodeTimeMs: 33,
              bitrateBps: 6500000,
              lossPercent: 0,
              rttMs: 4,
              requestedWidth: 1440,
              requestedHeight: 810,
              requestedFps: 30,
              framesCaptured: 0,
              framesEncoded: 0,
              framesSent: 0,
            ),
          ),
          StreamTestSample(
            elapsed: const Duration(seconds: 1),
            snapshot: _snapshot(
              width: 1440,
              height: 810,
              fps: 30,
              captureFps: 30,
              encodeFps: 30,
              sendFps: 30,
              averageEncodeTimeMs: 33,
              bitrateBps: 6500000,
              lossPercent: 0,
              rttMs: 4,
              requestedWidth: 1440,
              requestedHeight: 810,
              requestedFps: 30,
              framesCaptured: 30,
              framesEncoded: 30,
              framesSent: 30,
            ),
          ),
        ],
      );

      expect(result.score.bottleneck.label, 'frame_pacing_unstable');
      expect(
        result.score.bottleneck.reasons.join(' '),
        contains('repeated 260 of 900 submitted frames'),
      );
      expect(
        result.score.bottleneck.reasons.join(' '),
        contains('encoded/sent FPS can remain near target'),
      );
      expect(result.score.bottleneck.recommendedNextAction, 'fix frame pacing');
    });

    test('game hook source-to-submit latency is visual pacing evidence', () {
      final startedAt = DateTime.utc(2026, 6, 7, 21, 42, 30);
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 60)),
        nativeDiagnostics: StreamTestNativeDiagnostics.fromMarkers(const [
          '2026-06-07T21:43:41.000Z native-webrtc game_capture_webrtc_source stats source=2560x1440 output=1280x720 format=24 fps=30.0 submitted=1960 repeated=8 duplicateSkipped=0 deliveryQueued=1961 deliverySubmitted=1960 deliveryOverwritten=6 deliveryOnFrameMs=0.2 deliveryOnFrameMaxMs=2.2 readyToQueueMs=0.02 readyToQueueMaxMs=10.7 readyToQueueSamples=1961 deliveryQueueWaitMs=88.8 deliveryQueueWaitMaxMs=133.2 deliveryQueueWaitSamples=1952 readyToSubmitMs=88.9 readyToSubmitMaxMs=133.2 readyToSubmitSamples=1952 sourceToSubmitMs=123.5 sourceToSubmitMaxMs=177.7 sourceToSubmitSamples=1952 sourceToReadbackReadyMs=34.0 sourceToReadbackReadyMaxMs=78.0 sourceToReadbackReadySamples=1952 readbackQueueToMapMs=31.6 readbackQueueToMapMaxMs=66.0 readbackQueueToMapSamples=1961 mapToI420Ms=0.9 mapToI420MaxMs=4.0 mapToI420Samples=1961 sourceToI420ReadyMs=35.0 sourceToI420ReadyMaxMs=82.0 sourceToI420ReadySamples=1961 sourceToQueueMs=35.1 sourceToQueueMaxMs=92.0 sourceToQueueSamples=1961 copied=1962 dropped=0 overwritten=1959 gpuScaled=1960 gpuScaleFailures=0 cpuFallback=0 readbackQueued=1962 readbackReady=1961 readbackNotReady=8241 readbackOverwritten=0 readbackStaleDropped=0 readbackLatencyDropped=0 readbackMapAttempts=10202 gpuScaleMs=0.018 copyMs=0.148 mapMs=0.008 readbackLatencyMs=31.6 readbackLatencyFramesAvg=0.4 readbackLatencyFramesMax=4 sourceFrameIndex=4297 lastSubmittedSourceFrameIndex=4289 sourceFrameRegressions=0 sourceFrameDuplicates=8 sourceFrameGaps=2337 sharedSlotMismatches=0 timestampMode=paced timestampDeltaMs=33.3 timestampDeltaMaxMs=33.3 timestampSamples=151 timestampAdjustments=0 deliveryWallDeltaMs=33.3 deliveryWallDeltaMaxMs=35.0 deliveryWallOver2x=0 deliveryWallOver3x=0 deliveryWallUnderHalf=0 sourceQpcDeltaMs=33.4 sourceQpcDeltaMaxMs=76.3 sourceQpcSamples=1951 sourceQpcRegressions=0 convertMs=0.9 mapFailures=0 convertFailures=0 proofFrames=2 visibleProofFrames=2 i420ProofFrames=1 visibleI420ProofFrames=1 initialBlackSkipped=0 visibleSourceSeen=true',
          '2026-06-07T21:43:41.000Z native-webrtc Inter Galactic Media Foundation H.264 encoder timing frame=1960 total_ms=2.0 process_output_ms=0.1 slow=no',
        ]),
        samples: [
          StreamTestSample(
            elapsed: Duration.zero,
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 30,
              captureFps: 30,
              encodeFps: 30,
              sendFps: 30,
              averageEncodeTimeMs: 33,
              bitrateBps: 3000000,
              lossPercent: 0,
              rttMs: 3,
              requestedWidth: 1280,
              requestedHeight: 720,
              requestedFps: 30,
              framesCaptured: 0,
              framesEncoded: 0,
              framesSent: 0,
            ),
          ),
          StreamTestSample(
            elapsed: const Duration(seconds: 1),
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 30,
              captureFps: 30,
              encodeFps: 30,
              sendFps: 30,
              averageEncodeTimeMs: 33,
              bitrateBps: 3000000,
              lossPercent: 0,
              rttMs: 3,
              requestedWidth: 1280,
              requestedHeight: 720,
              requestedFps: 30,
              framesCaptured: 30,
              framesEncoded: 30,
              framesSent: 30,
            ),
          ),
        ],
      );

      expect(result.score.bottleneck.label, 'delivery_queue_limited');
      expect(
        result.score.bottleneck.reasons.join(' '),
        contains('source-to-submit latency averaged 123.5ms'),
      );
      expect(
        result.score.bottleneck.reasons.join(' '),
        contains('several frame budgets behind the game source'),
      );
      expect(
        result.score.bottleneck.evidenceFor.join(' '),
        contains('delivery queue wait averaged 88.8ms'),
      );
      expect(
        result.score.bottleneck.evidenceFor.join(' '),
        contains('source-to-readback-ready averaged 34.0ms'),
      );
      expect(
        result.score.bottleneck.evidenceFor.join(' '),
        contains('readback queue-to-map averaged 31.6ms'),
      );
      expect(
        result.nativeDiagnostics.gameCaptureFrameSummaryLabel,
        contains('source_to_i420_ready=35ms/82ms'),
      );
      expect(
        result.nativeDiagnostics.toJson(),
        containsPair('maxGameCaptureSourceToQueueMs', 92.0),
      );
      expect(
        result.diagnosticCoverage.toJson().toString(),
        contains('game-capture stage timing'),
      );
      expect(
        result.nativeDiagnostics.gameCaptureFrameSummaryLabel,
        contains('source_to_readback_ready=34ms'),
      );
      expect(result.score.stableFps, 10);
      expect(result.score.bottleneck.recommendedNextAction, 'fix frame pacing');
    });

    test('game hook readback delivery pressure is frame pacing', () {
      final startedAt = DateTime.utc(2026, 6, 7, 14, 49, 40);
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.balanced,
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 30)),
        nativeDiagnostics: StreamTestNativeDiagnostics.fromMarkers(const [
          '2026-06-07T14:50:16.194Z native-webrtc game_capture_webrtc_source stats source=2560x1440 output=1920x1080 format=24 fps=16.3 submitted=226 repeated=0 duplicateSkipped=49 deliveryQueued=226 deliverySubmitted=226 deliveryOverwritten=0 deliveryOnFrameMs=0.367012 deliveryOnFrameMaxMs=2.405800 copied=1793 dropped=0 overwritten=1790 gpuScaled=226 gpuScaleFailures=0 cpuFallback=0 readbackQueued=966 readbackReady=226 readbackNotReady=1664 readbackOverwritten=0 readbackStaleDropped=0 readbackLatencyDropped=739 readbackMapAttempts=1890 gpuScaleMs=0.012343 copyMs=0.212325 mapMs=0.003681 readbackLatencyMs=37.726452 readbackLatencyFramesAvg=0.838926 readbackLatencyFramesMax=2 sourceFrameIndex=1793 lastSubmittedSourceFrameIndex=1792 sourceFrameRegressions=0 sourceFrameDuplicates=0 sourceFrameGaps=1566 sharedSlotMismatches=0 convertMs=2.118411 mapFailures=0 convertFailures=0 proofFrames=2 visibleProofFrames=1 i420ProofFrames=1 visibleI420ProofFrames=1 initialBlackSkipped=0 visibleSourceSeen=true',
          '2026-06-07T14:50:16.194Z native-webrtc Inter Galactic Media Foundation H.264 encoder timing frame=216 total_ms=3.3 process_output_ms=0.1 slow=no',
        ]),
        samples: [
          StreamTestSample(
            elapsed: Duration.zero,
            snapshot: _snapshot(
              width: 1920,
              height: 1080,
              fps: 30,
              captureFps: 30,
              encodeFps: 30,
              sendFps: 30,
              averageEncodeTimeMs: 33,
              bitrateBps: 6500000,
              lossPercent: 0,
              rttMs: 4,
              requestedWidth: 1920,
              requestedHeight: 1080,
              requestedFps: 30,
              framesCaptured: 0,
              framesEncoded: 0,
              framesSent: 0,
            ),
          ),
          StreamTestSample(
            elapsed: const Duration(seconds: 1),
            snapshot: _snapshot(
              width: 1920,
              height: 1080,
              fps: 30,
              captureFps: 30,
              encodeFps: 30,
              sendFps: 30,
              averageEncodeTimeMs: 33,
              bitrateBps: 6500000,
              lossPercent: 0,
              rttMs: 4,
              requestedWidth: 1920,
              requestedHeight: 1080,
              requestedFps: 30,
              framesCaptured: 30,
              framesEncoded: 30,
              framesSent: 30,
            ),
          ),
        ],
      );

      expect(result.score.bottleneck.label, 'frame_pacing_unstable');
      expect(
        result.score.bottleneck.reasons.join(' '),
        contains('copied 1793 source frames but submitted 226'),
      );
      expect(
        result.score.bottleneck.reasons.join(' '),
        contains('readback latency dropped 739 frames'),
      );
      expect(result.score.bottleneck.recommendedNextAction, 'fix frame pacing');
    });

    test('missing receiver render FPS is explicit coverage evidence', () {
      final result = StreamTestPresetResult(
        profile: ScreenShareProfileConfig.smooth,
        startedAt: DateTime.utc(2026, 6, 2, 22),
        endedAt: DateTime.utc(2026, 6, 2, 22, 0, 2),
        samples: [
          StreamTestSample(
            elapsed: const Duration(seconds: 1),
            snapshot: _snapshot(
              width: 1280,
              height: 720,
              fps: 30,
              bitrateBps: 1800000,
              lossPercent: 0,
              rttMs: 20,
            ),
          ),
        ],
      );

      final coverage = result.diagnosticCoverage.toJson();
      expect(coverage['missingFields'], contains('receiver render FPS'));
      expect(
        result.diagnosticCoverage.toMarkdownTable(),
        contains('receiver render FPS'),
      );
    });

    test('run coverage includes loaded libwebrtc artifact identity', () {
      final artifact = StreamTestLoadedLibwebrtcArtifact(
        fileName: 'libwebrtc.dll',
        location: 'executable_directory/libwebrtc.dll',
        sha256:
            '2B9411BD8D6374EA3287F41B60E3C93B4893A197125BF7B281D9EDC8A37DAC40',
        sizeBytes: 123456789,
        modifiedAtUtc: DateTime.utc(2026, 6, 10, 19, 52),
      );
      final result = StreamTestRunResult(
        startedAt: DateTime.utc(2026, 6, 10, 19, 52),
        endedAt: DateTime.utc(2026, 6, 10, 19, 53),
        targetLabel: 'Test Voice',
        roomId: '!room:example.org',
        config: const StreamTestRunConfig(
          presets: [ScreenShareProfileConfig.smooth],
        ),
        presetResults: const [],
        loadedLibwebrtcArtifact: artifact,
      );

      final json = result.toJson();
      final loadedLibwebrtc = json['loadedLibwebrtc'] as Map<String, Object?>?;
      expect(loadedLibwebrtc, containsPair('sha256', artifact.sha256));
      expect(
        result.diagnosticCoverage.toMarkdownTable(),
        contains('2B9411BD8D63'),
      );
      expect(
        result.diagnosticCoverage.missingFields,
        isNot(contains('loaded libwebrtc artifact identity')),
      );
      expect(result.toMarkdown(), contains('Loaded libwebrtc: libwebrtc.dll'));
    });

    test(
      'uses insufficient evidence instead of unknown for unproven causes',
      () {
        final result = StreamTestPresetResult(
          profile: ScreenShareProfileConfig.smooth,
          startedAt: DateTime.utc(2026, 6, 2, 22),
          endedAt: DateTime.utc(2026, 6, 2, 22, 0, 2),
          samples: [
            StreamTestSample(
              elapsed: const Duration(seconds: 1),
              snapshot: VoipCallDiagnosticsSnapshot(
                collectedAt: DateTime.utc(2026, 6, 2, 22),
                screenShareProfileLabel: 'Smooth',
                adaptiveStreamEnabled: true,
                dynacastEnabled: true,
                screenShareSimulcastEnabled: false,
                adaptiveFallbackEnabled: false,
                participants: const [],
                tracks: const [
                  VoipTrackDiagnostics(
                    streamId: 'stream',
                    label: 'Screen share',
                    type: VoipStreamType.screenshare,
                    direction: VoipDiagnosticsTrackDirection.sender,
                    requestedWidth: 1280,
                    requestedHeight: 720,
                    requestedFps: 30,
                    requestedBitrateBps: 1800000,
                    preEncodeWidth: 1280,
                    preEncodeHeight: 720,
                    width: 1280,
                    height: 720,
                    fps: 10,
                    bitrateBps: 900000,
                  ),
                ],
              ),
            ),
          ],
        );

        expect(result.score.bottleneck.label, 'insufficient_evidence');
        expect(result.score.bottleneck.confidence, 'insufficient');
        expect(result.score.bottleneck.missingFields, contains('capture FPS'));
        expect(
          result.score.bottleneck.missingFields,
          contains('receiver render FPS'),
        );
        expect(
          result.score.bottleneck.recommendedNextAction,
          'collect one specific missing field',
        );
        expect(
          streamTestRecommendedNextActions,
          contains(result.score.bottleneck.recommendedNextAction),
        );
      },
    );
  });
}

class _FakeStreamTestTarget implements StreamTestTarget {
  _FakeStreamTestTarget({
    required this.snapshot,
    this.collectDiagnosticsFuture,
    this.collectDiagnosticsHandler,
    this.startPresetHandler,
    this.startPresetFuture,
    this.startSharingOnStart = true,
    this.receiverProbeEvents = const [],
    this.receiverProbeStartError,
  });

  final VoipCallDiagnosticsSnapshot snapshot;
  final Future<VoipCallDiagnosticsSnapshot>? collectDiagnosticsFuture;
  final Future<VoipCallDiagnosticsSnapshot> Function()?
  collectDiagnosticsHandler;
  final Future<void> Function()? startPresetHandler;
  final Future<void>? startPresetFuture;
  final bool startSharingOnStart;
  final List<Map<String, Object?>> receiverProbeEvents;
  final Object? receiverProbeStartError;
  final List<String> startedProfiles = [];
  final List<ScreenShareVideoLayer> startedMainLayers = [];
  final List<WindowsScreenCaptureBackendMode?> startedBackends = [];
  final List<WindowsScreenCaptureDirtyRegionMode> startedDirtyRegionModes = [];
  final List<WindowsWindowGdiCaptureMode?> startedWindowGdiModes = [];
  final List<bool> startedNativePacers = [];
  final List<bool> startedDummyNv12LiveSenders = [];
  final List<StreamTestReceiverProbeMode> startedReceiverProbeModes = [];
  final List<StreamTestReceiverProbeConfig> startedReceiverProbeConfigs = [];
  var sharing = false;
  var stopCount = 0;
  var stopReceiverProbeCount = 0;
  var receiverProbeStartedWhileSharing = false;
  DateTime? receiverProbeStartedAt;

  @override
  String get label => 'Fake stream target';

  @override
  String get roomId => '!fake:example.test';

  @override
  bool get isSharingScreen => sharing;

  @override
  Future<void> startPreset(
    ScreenShareProfileConfig profile, {
    WindowsScreenCaptureBackendMode? windowsCaptureBackendMode,
    WindowsScreenCaptureDirtyRegionMode windowsCaptureDirtyRegionMode =
        WindowsScreenCaptureDirtyRegionMode.auto,
    WindowsWindowGdiCaptureMode? windowsWindowGdiCaptureMode,
    bool nativeFramePacingEnabled = false,
    bool dummyNv12LiveSender = false,
  }) async {
    startedProfiles.add(profile.label);
    startedMainLayers.add(profile.mainLayer);
    startedBackends.add(windowsCaptureBackendMode);
    startedDirtyRegionModes.add(windowsCaptureDirtyRegionMode);
    startedWindowGdiModes.add(windowsWindowGdiCaptureMode);
    startedNativePacers.add(nativeFramePacingEnabled);
    startedDummyNv12LiveSenders.add(dummyNv12LiveSender);
    if (startSharingOnStart) {
      sharing = true;
    }
    final handler = startPresetHandler;
    if (handler != null) {
      await handler();
      return;
    }
    final pending = startPresetFuture;
    if (pending != null) {
      await pending;
    }
  }

  @override
  Future<void> stopShare() async {
    sharing = false;
    stopCount++;
  }

  @override
  Future<VoipCallDiagnosticsSnapshot> collectDiagnostics() async {
    final handler = collectDiagnosticsHandler;
    if (handler != null) {
      return await handler();
    }
    final pending = collectDiagnosticsFuture;
    if (pending != null) {
      return await pending;
    }
    return snapshot;
  }

  @override
  Future<void> startReceiverProbe(StreamTestReceiverProbeConfig config) async {
    startedReceiverProbeModes.add(config.mode);
    startedReceiverProbeConfigs.add(config);
    receiverProbeStartedWhileSharing = sharing;
    receiverProbeStartedAt = DateTime.utc(2026, 6, 18, 18);
    final error = receiverProbeStartError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<StreamTestReceiverProbeResult> stopReceiverProbe() async {
    stopReceiverProbeCount++;
    final config = startedReceiverProbeConfigs.isEmpty
        ? const StreamTestReceiverProbeConfig()
        : startedReceiverProbeConfigs.last;
    if (!config.inProcess) {
      return StreamTestReceiverProbeResult.externalHandoff(
        mode: config.mode,
        startedAt: receiverProbeStartedAt ?? DateTime.utc(2026, 6, 18, 18),
        endedAt: DateTime.utc(2026, 6, 18, 18, 0, 2),
      );
    }
    final mode = startedReceiverProbeModes.isEmpty
        ? StreamTestReceiverProbeMode.decodeOnly
        : startedReceiverProbeModes.last;
    return StreamTestReceiverProbeResult.fromEvents(
      mode: mode,
      startedAt: receiverProbeStartedAt ?? DateTime.utc(2026, 6, 18, 18),
      endedAt: DateTime.utc(2026, 6, 18, 18, 0, 2),
      events: receiverProbeEvents,
    );
  }
}

class _FakeGameCaptureProbeRunner implements GameCaptureProbeRunner {
  _FakeGameCaptureProbeRunner({required this.resultFactory});

  final FutureOr<GameCaptureProbeResult> Function(GameCaptureProbeConfig config)
  resultFactory;
  final List<GameCaptureProbeConfig> configs = [];

  @override
  Future<GameCaptureProbeResult> run(GameCaptureProbeConfig config) async {
    configs.add(config);
    return await resultFactory(config);
  }
}

class _FakeHostLoadSampler implements StreamTestHostLoadSampler {
  _FakeHostLoadSampler({
    required this.report,
    Future<void>? startFuture,
    Future<StreamTestHostLoadReport>? stopFuture,
  }) : _startFuture = startFuture,
       _stopFuture = stopFuture;

  final StreamTestHostLoadReport report;
  final Future<void>? _startFuture;
  final Future<StreamTestHostLoadReport>? _stopFuture;
  var startCount = 0;
  var stopCount = 0;

  @override
  Future<void> start() async {
    startCount++;
    final startFuture = _startFuture;
    if (startFuture != null) {
      await startFuture;
    }
  }

  @override
  Future<StreamTestHostLoadReport> stop() async {
    stopCount++;
    final stopFuture = _stopFuture;
    if (stopFuture != null) {
      return stopFuture;
    }
    return report;
  }
}

VoipCallDiagnosticsSnapshot _snapshot({
  required int width,
  required int height,
  required double fps,
  DateTime? collectedAt,
  double? captureFps,
  double? encodeFps,
  double? sendFps,
  double? decodeFps,
  double? renderFps,
  double? averageEncodeTimeMs,
  required int bitrateBps,
  required double lossPercent,
  required double rttMs,
  double? averagePacketSendDelayMs,
  int requestedWidth = 1280,
  int requestedHeight = 720,
  double requestedFps = 30,
  int requestedBitrateBps = 1800000,
  int? framesCaptured,
  int? framesEncoded,
  int? framesSent,
  int? framesReceived,
  int? framesDecoded,
  int? framesRendered,
  bool includeReceiver = false,
  String? profileDetails,
  String codec = 'VP8',
  String? encoderImplementation,
  bool? hardwareEncodeActive,
  String activeLayer = 'single',
  String qualityLimitationReason = 'none',
}) {
  return VoipCallDiagnosticsSnapshot(
    collectedAt: collectedAt ?? DateTime.utc(2026, 5, 18, 18),
    screenShareProfileLabel: 'Smooth',
    screenShareProfileDetails: profileDetails,
    adaptiveStreamEnabled: true,
    dynacastEnabled: true,
    screenShareSimulcastEnabled: true,
    adaptiveFallbackEnabled: false,
    participants: const [],
    tracks: [
      VoipTrackDiagnostics(
        streamId: 'stream',
        label: 'Screen share',
        type: VoipStreamType.screenshare,
        direction: VoipDiagnosticsTrackDirection.sender,
        requestedWidth: requestedWidth,
        requestedHeight: requestedHeight,
        requestedFps: requestedFps,
        requestedBitrateBps: requestedBitrateBps,
        preEncodeWidth: width,
        preEncodeHeight: height,
        width: width,
        height: height,
        fps: fps,
        captureFps: captureFps ?? fps,
        encodeFps: encodeFps ?? fps,
        sendFps: sendFps ?? fps,
        bitrateBps: bitrateBps,
        packetLossPercent: lossPercent,
        roundTripTimeMs: rttMs,
        nackCount: 0,
        framesCaptured: framesCaptured,
        framesEncoded: framesEncoded,
        framesSent: framesSent,
        averageEncodeTimeMs: averageEncodeTimeMs,
        averagePacketSendDelayMs: averagePacketSendDelayMs,
        activeLayer: activeLayer,
        qualityLimitationReason: qualityLimitationReason,
        codec: codec,
        encoderImplementation: encoderImplementation,
        hardwareEncodeActive: hardwareEncodeActive,
      ),
      if (includeReceiver)
        VoipTrackDiagnostics(
          streamId: 'remote-stream',
          label: 'Remote screen share',
          type: VoipStreamType.screenshare,
          direction: VoipDiagnosticsTrackDirection.receiver,
          receivePriority: VoipStreamReceivePriority.high,
          width: width,
          height: height,
          fps: fps,
          decodeFps: decodeFps ?? fps,
          renderFps: renderFps ?? fps,
          framesReceived: framesReceived,
          framesDecoded: framesDecoded,
          framesRendered: framesRendered,
        ),
    ],
  );
}
