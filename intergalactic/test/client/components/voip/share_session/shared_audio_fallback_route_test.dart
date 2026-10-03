import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intergalactic/client/bug_report/pending_crash_report.dart';
import 'package:intergalactic/client/bug_report/pending_crash_report_store.dart';
import 'package:intergalactic/client/components/voip/share_session/share_session.dart';
import 'package:intergalactic/client/components/voip/shared_audio/shared_audio_backend.dart';
import 'package:intergalactic/client/components/voip/shared_audio/shared_audio_capability.dart';
import 'package:intergalactic/client/components/voip/shared_audio/shared_audio_coordinator.dart';
import 'package:intergalactic_windows_share/intergalactic_windows_share.dart';

/// The production route for the shared-audio fallback.
///
/// The coordinator's own planning is covered by
/// `shared_audio/shared_audio_coordinator_test.dart`. What is covered here is
/// the thing that was missing: that the route actually *reaches* the
/// coordinator, and that a refusal becomes an offer the caller can act on
/// rather than a dead `unavailable`.
void main() {
  group('shared audio fallback route', () {
    test('a refused capture offers a choice and starts nothing', () async {
      final backend = _FakeBackend(
        report: _report(selectedApplication: false, desktopAudio: true),
      );
      final source = _sourceOver(backend);

      final status = await source.start();

      expect(status.state, SharedAudioState.needsChoice);
      expect(status.reason, 'os_refused_activation');
      expect(
        backend.startCalls,
        isEmpty,
        reason:
            'The refusal must reach the user as a question. Starting anything '
            'here is the silent substitution this route exists to prevent.',
      );
      expect(source.pendingFallbackOptions, isNotEmpty);
    });

    test('the offered options end with a no-shared-audio choice', () async {
      final source = _sourceOver(
        _FakeBackend(
          report: _report(selectedApplication: false, desktopAudio: true),
        ),
      );

      await source.start();

      expect(
        source.pendingFallbackOptions.last.mode,
        SharedAudioCaptureMode.none,
      );
    });

    test(
      'an available capture starts directly, with no choice raised',
      () async {
        final backend = _FakeBackend(
          report: _report(selectedApplication: true, desktopAudio: true),
          statusAfterStart: _activeStatus,
        );
        final source = _sourceOver(backend);

        final status = await source.start();

        expect(status.state, SharedAudioState.active);
        expect(source.pendingFallbackOptions, isEmpty);
        expect(backend.startCalls, hasLength(1));
        expect(
          backend.startCalls.single.mode,
          SharedAudioCaptureMode.selectedApplication,
          reason: 'A ready plan must start the mode that was asked for.',
        );
      },
    );

    test('a chosen option starts that mode and clears the choice', () async {
      final backend = _FakeBackend(
        report: _report(selectedApplication: false, desktopAudio: true),
        statusAfterStart: _activeStatus,
      );
      final source = _sourceOver(backend);
      await source.start();

      final desktop = source.pendingFallbackOptions.firstWhere(
        (option) => option.mode == SharedAudioCaptureMode.desktopAudio,
      );
      final status = await source.applyFallbackOption(desktop);

      expect(status.state, SharedAudioState.active);
      expect(source.pendingFallbackOptions, isEmpty);
      expect(backend.startCalls, hasLength(1));
      expect(
        backend.startCalls.single.mode,
        SharedAudioCaptureMode.desktopAudio,
        reason: 'The started mode must be the one the user picked.',
      );
    });

    test(
      'declining leaves the share video-only and is not re-offered',
      () async {
        final backend = _FakeBackend(
          report: _report(selectedApplication: false, desktopAudio: true),
        );
        final source = _sourceOver(backend);
        await source.start();

        final declined = await source.declineFallback();

        expect(declined.state, SharedAudioState.unavailable);
        expect(declined.reason, 'user_declined');
        expect(source.pendingFallbackOptions, isEmpty);
        expect(backend.stopCalls, 1);

        // A second start must not re-raise what they already turned down, and
        // must not start the mode the platform refused either.
        final again = await source.start();

        expect(again.state, SharedAudioState.unavailable);
        expect(again.reason, 'user_declined');
        expect(backend.startCalls, isEmpty);
      },
    );

    test(
      'applying an option with no choice outstanding starts nothing',
      () async {
        final backend = _FakeBackend(
          report: _report(selectedApplication: true, desktopAudio: true),
          statusAfterStart: _activeStatus,
        );
        final source = _sourceOver(backend);

        await source.applyFallbackOption(
          const SharedAudioFallbackOption(
            mode: SharedAudioCaptureMode.desktopAudio,
            label: 'Desktop audio',
          ),
        );

        expect(
          backend.startCalls,
          isEmpty,
          reason:
              'An option applied out of band is a caller bug; honouring it would '
              'start a capture the user never chose.',
        );
      },
    );

    test(
      'a start refused after a ready plan raises a follow-up choice',
      () async {
        // The plan can be clean and the activation still refused - the refusal
        // is measured, not predicted. That second refusal must reach the user
        // the same way the first would.
        final backend = _FakeBackend(
          report: _report(selectedApplication: true, desktopAudio: true),
          startResult: const SharedAudioStartResult.failed(
            mode: SharedAudioCaptureMode.selectedApplication,
            backend: SharedAudioBackendKind.windowsProcessLoopback,
            reason: SharedAudioUnavailableReason.osRefusedActivation,
          ),
          reportAfterStart: _report(
            selectedApplication: false,
            desktopAudio: true,
          ),
        );
        final source = _sourceOver(backend);

        final status = await source.start();

        expect(status.state, SharedAudioState.needsChoice);
        expect(source.pendingFallbackOptions, isNotEmpty);
        expect(
          backend.startCalls,
          hasLength(1),
          reason: 'The failed attempt is the one start; nothing is retried.',
        );
      },
    );
  });

  group('ShareSession surfaces the choice', () {
    test('exposes the pending options and applies the pick', () async {
      final backend = _FakeBackend(
        report: _report(selectedApplication: false, desktopAudio: true),
        statusAfterStart: _activeStatus,
      );
      final session = ShareSession(
        target: _target,
        videoSource: _NoopVideoSource(),
        sharedAudioSource: _sourceOver(backend),
      );

      final status = await session.startSharedAudio();

      expect(status.state, SharedAudioState.needsChoice);
      expect(session.pendingSharedAudioOptions, isNotEmpty);
      expect(
        session.lifecycle,
        ShareSessionLifecycle.videoOnly,
        reason: 'The share runs video-only while the choice is outstanding.',
      );

      final desktop = session.pendingSharedAudioOptions.firstWhere(
        (option) => option.mode == SharedAudioCaptureMode.desktopAudio,
      );
      final chosen = await session.chooseSharedAudioFallback(desktop);

      expect(chosen.state, SharedAudioState.active);
      expect(session.lifecycle, ShareSessionLifecycle.sharing);
      expect(session.pendingSharedAudioOptions, isEmpty);
    });

    test('a source with nothing to offer exposes no options', () async {
      final session = ShareSession(
        target: _target,
        videoSource: _NoopVideoSource(),
        sharedAudioSource: const DisabledSharedAudioSource(),
      );

      expect(session.pendingSharedAudioOptions, isEmpty);
      expect(session.pendingSharedAudioWarning, isEmpty);

      // Choosing against a source that cannot offer must be inert, not a
      // crash: the UI reads one interface for every platform.
      final status = await session.declineSharedAudioFallback();

      expect(status.state, SharedAudioState.disabled);
    });
  });

  group('ShareSession native crash marker', () {
    test('initial Windows capture is marked before start until stop', () async {
      final store = _RecordingCrashStore();
      final backend = _FakeBackend(
        report: _report(selectedApplication: true, desktopAudio: true),
        statusAfterStart: _activeStatus,
        onStart: () => expect(store.pending, isNotNull),
      );
      final session = ShareSession(
        target: _target,
        videoSource: _NoopVideoSource(),
        sharedAudioSource: _sourceOver(backend),
        crashReportStore: store,
        isWindowsPlatform: true,
      );

      expect((await session.startSharedAudio()).state, SharedAudioState.active);
      expect(store.pending?.shouldOfferCrashPrompt, isTrue);
      expect(store.pending?.details, contains('Windows display-share audio'));
      expect(store.pending?.details, isNot(contains(_target.title)));

      await session.stop();
      expect(store.pending, isNull);
      expect(store.clearCalls, 1);
    });

    test(
      'fallback capture is marked before start through active lifetime',
      () async {
        final store = _RecordingCrashStore();
        final backend = _FakeBackend(
          report: _report(selectedApplication: false, desktopAudio: true),
          statusAfterStart: _activeStatus,
          onStart: () => expect(store.pending, isNotNull),
        );
        final session = ShareSession(
          target: _target,
          videoSource: _NoopVideoSource(),
          sharedAudioSource: _sourceOver(backend),
          crashReportStore: store,
          isWindowsPlatform: true,
        );

        expect(
          (await session.startSharedAudio()).state,
          SharedAudioState.needsChoice,
        );
        expect(store.pending, isNull);
        final option = session.pendingSharedAudioOptions.firstWhere(
          (option) => option.mode == SharedAudioCaptureMode.desktopAudio,
        );
        expect(
          (await session.chooseSharedAudioFallback(option)).state,
          SharedAudioState.active,
        );
        expect(backend.startCalls, hasLength(1));
        expect(store.pending?.shouldOfferCrashPrompt, isTrue);

        await session.stop();
        expect(store.pending, isNull);
      },
    );

    test('reconstructed fallback option still marks native start', () async {
      final store = _RecordingCrashStore();
      final backend = _FakeBackend(
        report: _report(selectedApplication: false, desktopAudio: true),
        statusAfterStart: _activeStatus,
        onStart: () => expect(store.pending, isNotNull),
      );
      final session = ShareSession(
        target: _target,
        videoSource: _NoopVideoSource(),
        sharedAudioSource: _sourceOver(backend),
        crashReportStore: store,
        isWindowsPlatform: true,
      );

      expect(
        (await session.startSharedAudio()).state,
        SharedAudioState.needsChoice,
      );
      final offered = session.pendingSharedAudioOptions.firstWhere(
        (option) => option.mode == SharedAudioCaptureMode.desktopAudio,
      );
      final reconstructed = SharedAudioFallbackOption(
        mode: offered.mode,
        label: offered.label,
        device: offered.device,
        warning: offered.warning,
        excludesOwnCallAudio: offered.excludesOwnCallAudio,
      );
      expect(
        session.pendingSharedAudioOptions.contains(reconstructed),
        isFalse,
      );

      expect(
        (await session.chooseSharedAudioFallback(reconstructed)).state,
        SharedAudioState.active,
      );
      expect(store.pending?.shouldOfferCrashPrompt, isTrue);
      await session.stop();
      expect(store.pending, isNull);
    });

    test('fallback with no pending plan records no marker', () async {
      final store = _RecordingCrashStore();
      final backend = _FakeBackend(
        report: _report(selectedApplication: false, desktopAudio: true),
      );
      final session = ShareSession(
        target: _target,
        videoSource: _NoopVideoSource(),
        sharedAudioSource: _sourceOver(backend),
        crashReportStore: store,
        isWindowsPlatform: true,
      );

      await session.chooseSharedAudioFallback(
        const SharedAudioFallbackOption(
          mode: SharedAudioCaptureMode.desktopAudio,
          label: 'Desktop audio',
        ),
      );
      expect(backend.startCalls, isEmpty);
      expect(store.recordCalls, 0);
    });

    test('handled Windows start failure clears its marker', () async {
      final store = _RecordingCrashStore();
      final backend = _FakeBackend(
        report: _report(selectedApplication: true, desktopAudio: true),
        onStart: () => expect(store.pending, isNotNull),
      );
      final session = ShareSession(
        target: _target,
        videoSource: _NoopVideoSource(),
        sharedAudioSource: _sourceOver(backend),
        crashReportStore: store,
        isWindowsPlatform: true,
      );

      expect(
        (await session.startSharedAudio()).state,
        isNot(SharedAudioState.active),
      );
      expect(store.pending, isNull);
    });

    test('requested non-Windows source does not set Windows marker', () async {
      final store = _RecordingCrashStore();
      final session = ShareSession(
        target: _target,
        videoSource: _NoopVideoSource(),
        sharedAudioSource: _OtherPlatformAudioSource(),
        crashReportStore: store,
        isWindowsPlatform: true,
      );

      expect((await session.startSharedAudio()).state, SharedAudioState.active);
      expect(store.recordCalls, 0);
      await session.stop();
      expect(store.pending, isNull);
    });

    test('Windows source on another platform does not set marker', () async {
      final store = _RecordingCrashStore();
      final backend = _FakeBackend(
        report: _report(selectedApplication: true, desktopAudio: true),
        statusAfterStart: _activeStatus,
        onStart: () => expect(store.pending, isNull),
      );
      final session = ShareSession(
        target: _target,
        videoSource: _NoopVideoSource(),
        sharedAudioSource: _sourceOver(backend),
        crashReportStore: store,
        isWindowsPlatform: false,
      );

      expect((await session.startSharedAudio()).state, SharedAudioState.active);
      expect(store.recordCalls, 0);
      await session.stop();
      expect(store.pending, isNull);
    });
  });
}

const _target = ShareTarget(
  type: ShareTargetType.window,
  sourceId: 'window:1',
  title: 'Some Game',
  processId: 4242,
);

const _activeStatus = SharedAudioCaptureStatus(
  mode: SharedAudioCaptureMode.desktopAudio,
  backend: SharedAudioBackendKind.windowsEndpointLoopback,
  state: SharedAudioCaptureState.active,
  nativeReason: 'capturing',
);

WindowsSharedAudioSource _sourceOver(_FakeBackend backend) {
  return WindowsSharedAudioSource(
    nativeBinding: _UnusedBinding(),
    target: _target,
    requested: true,
    mode: SharedAudioMode.processTreeLoopback,
    backend: backend,
    coordinator: SharedAudioCoordinator(backend: backend),
  );
}

SharedAudioCapabilityReport _report({
  required bool selectedApplication,
  required bool desktopAudio,
}) {
  return SharedAudioCapabilityReport(
    platform: 'windows',
    backend: SharedAudioBackendKind.windowsProcessLoopback,
    devices: const [],
    modes: [
      if (selectedApplication)
        const SharedAudioModeAvailability(
          mode: SharedAudioCaptureMode.selectedApplication,
          available: true,
          backend: SharedAudioBackendKind.windowsProcessLoopback,
          canExcludeOwnCallAudio: true,
        )
      else
        const SharedAudioModeAvailability.unavailable(
          mode: SharedAudioCaptureMode.selectedApplication,
          reason: SharedAudioUnavailableReason.osRefusedActivation,
          backend: SharedAudioBackendKind.windowsProcessLoopback,
        ),
      if (desktopAudio)
        const SharedAudioModeAvailability(
          mode: SharedAudioCaptureMode.desktopAudio,
          available: true,
          backend: SharedAudioBackendKind.windowsEndpointLoopback,
          canExcludeOwnCallAudio: false,
        )
      else
        const SharedAudioModeAvailability.unavailable(
          mode: SharedAudioCaptureMode.desktopAudio,
          reason: SharedAudioUnavailableReason.noCaptureDevice,
        ),
      const SharedAudioModeAvailability.unavailable(
        mode: SharedAudioCaptureMode.selectedDevice,
        reason: SharedAudioUnavailableReason.noVirtualDeviceDetected,
      ),
      const SharedAudioModeAvailability(
        mode: SharedAudioCaptureMode.none,
        available: true,
        backend: SharedAudioBackendKind.none,
        canExcludeOwnCallAudio: true,
      ),
    ],
  );
}

class _FakeBackend implements SharedAudioBackend {
  _FakeBackend({
    required this.report,
    this.reportAfterStart,
    this.startResult,
    this.statusAfterStart,
    this.onStart,
  });

  final SharedAudioCapabilityReport report;

  /// Probe answer once a start has been attempted, for the case where the
  /// activation refusal is only visible after the attempt.
  final SharedAudioCapabilityReport? reportAfterStart;

  final SharedAudioStartResult? startResult;
  final SharedAudioCaptureStatus? statusAfterStart;
  final void Function()? onStart;

  final List<SharedAudioRequest> startCalls = [];
  int stopCalls = 0;

  @override
  SharedAudioBackendKind get kind =>
      SharedAudioBackendKind.windowsProcessLoopback;

  @override
  String get platform => 'windows';

  @override
  Future<SharedAudioCapabilityReport> probe(SharedAudioRequest request) async {
    return startCalls.isEmpty ? report : (reportAfterStart ?? report);
  }

  @override
  Future<SharedAudioStartResult> start(SharedAudioRequest request) async {
    onStart?.call();
    startCalls.add(request);
    return startResult ??
        SharedAudioStartResult(
          started: true,
          mode: request.mode,
          backend: SharedAudioBackendKind.windowsEndpointLoopback,
          selectedSourceLabel: request.targetTitle,
        );
  }

  @override
  SharedAudioCaptureStatus get lastStatus =>
      startCalls.isEmpty || statusAfterStart == null
      ? const SharedAudioCaptureStatus.inactive()
      : statusAfterStart!;

  @override
  Future<SharedAudioCaptureStatus> refreshStatus() async => lastStatus;

  @override
  Future<MediaStream?> createPublicationStream() async => null;

  @override
  Future<void> disposePublicationStream() async {}

  @override
  Future<void> stop() async {
    stopCalls += 1;
  }

  @override
  Future<void> dispose() async {}
}

class _RecordingCrashStore extends PendingCrashReportStore {
  PendingCrashReport? pending;
  int recordCalls = 0;
  int clearCalls = 0;

  @override
  Future<void> record(
    PendingCrashReport report, {
    String? directoryPath,
  }) async {
    recordCalls += 1;
    pending = report;
  }

  @override
  Future<void> clearPendingFromSource(
    String source, {
    String? directoryPath,
  }) async {
    clearCalls += 1;
    if (pending?.source == source) {
      pending = null;
    }
  }
}

class _OtherPlatformAudioSource implements SharedAudioSource {
  SharedAudioStatus _status = const SharedAudioStatus(
    state: SharedAudioState.stopped,
    mode: SharedAudioMode.systemLoopback,
    reason: 'not_started',
  );

  @override
  bool get requested => true;

  @override
  SharedAudioMode get mode => SharedAudioMode.systemLoopback;

  @override
  SharedAudioState get state => _status.state;

  @override
  SharedAudioStatus get status => _status;

  @override
  Future<SharedAudioStatus> start() async => _status = const SharedAudioStatus(
    state: SharedAudioState.active,
    mode: SharedAudioMode.systemLoopback,
    reason: 'capturing',
  );

  @override
  Future<SharedAudioStatus> stop() async => _status = const SharedAudioStatus(
    state: SharedAudioState.stopped,
    mode: SharedAudioMode.systemLoopback,
    reason: 'stopped',
  );

  @override
  Future<void> dispose() async {}
}

class _NoopVideoSource implements ScreenVideoSource {
  @override
  ShareTarget get target => _target;
}

/// The source takes a binding only to build its own backend when one is not
/// injected. Every test here injects one, so nothing on this is ever called.
class _UnusedBinding implements WindowsShareNativeBinding {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnsupportedError(
      'The injected backend serves every call; the binding must not be used.',
    );
  }
}
