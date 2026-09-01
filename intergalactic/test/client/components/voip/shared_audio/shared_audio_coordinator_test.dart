import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intergalactic/client/components/voip/shared_audio/pending_shared_audio_backends.dart';
import 'package:intergalactic/client/components/voip/shared_audio/shared_audio_backend.dart';
import 'package:intergalactic/client/components/voip/shared_audio/shared_audio_capability.dart';
import 'package:intergalactic/client/components/voip/shared_audio/shared_audio_coordinator.dart';

void main() {
  group('SharedAudioCoordinator planning', () {
    test('starts directly when the requested mode is available', () async {
      final coordinator = SharedAudioCoordinator(
        backend: _FakeBackend(
          report: _report(selectedApplication: true, desktopAudio: true),
        ),
      );

      final plan = await coordinator.plan(_appRequest);

      expect(plan.kind, SharedAudioPlanKind.ready);
      expect(plan.options, isEmpty);
    });

    test('never silently falls back: an unavailable selected-application mode '
        'produces a choice instead of desktop audio', () async {
      final backend = _FakeBackend(
        report: _report(
          selectedApplication: false,
          desktopAudio: true,
          desktopExcludesOwnAudio: false,
          blockedReason: SharedAudioUnavailableReason.osRefusedActivation,
          nativeErrorCode: '0x88890008',
        ),
      );
      final coordinator = SharedAudioCoordinator(backend: backend);

      final plan = await coordinator.plan(_appRequest);

      expect(plan.kind, SharedAudioPlanKind.needsUserChoice);
      expect(
        plan.blockedReason,
        SharedAudioUnavailableReason.osRefusedActivation,
      );
      expect(plan.nativeErrorCode, '0x88890008');
      expect(
        backend.startCalls,
        isEmpty,
        reason: 'Planning must not start any capture on its own.',
      );
    });

    test(
      'offers endpoint fallback, virtual device, and no-audio in order',
      () async {
        final coordinator = SharedAudioCoordinator(
          backend: _FakeBackend(
            report: _report(
              selectedApplication: false,
              desktopAudio: true,
              desktopExcludesOwnAudio: false,
              selectedDevice: true,
              devices: const [
                SharedAudioDevice(
                  id: 'cable-output',
                  name: 'CABLE Output (VB-Audio Virtual Cable)',
                  isCapture: true,
                  isLikelyVirtual: true,
                  virtualFamily: 'vb-cable',
                ),
              ],
            ),
          ),
        );

        final plan = await coordinator.plan(_appRequest);

        expect(plan.options.map((option) => option.mode).toList(), const [
          SharedAudioCaptureMode.desktopAudio,
          SharedAudioCaptureMode.selectedDevice,
          SharedAudioCaptureMode.none,
        ]);
        expect(plan.options[1].device?.id, 'cable-output');
        expect(plan.options[1].label, contains('VB-CABLE'));
        expect(plan.options.last.label, 'Continue without shared audio');
      },
    );

    test(
      'warns before a fallback that can include other apps and this call',
      () async {
        final coordinator = SharedAudioCoordinator(
          backend: _FakeBackend(
            report: _report(
              selectedApplication: false,
              desktopAudio: true,
              desktopExcludesOwnAudio: false,
            ),
          ),
        );

        final plan = await coordinator.plan(_appRequest);
        final desktopOption = plan.options.first;

        expect(desktopOption.mode, SharedAudioCaptureMode.desktopAudio);
        expect(desktopOption.warning, contains('Notifications, other calls'));
        expect(desktopOption.warning, contains('echo'));
        expect(desktopOption.excludesOwnCallAudio, isFalse);
        expect(plan.warning, isNotEmpty);
      },
    );

    test(
      'omits the echo warning when the platform can exclude our own call audio',
      () async {
        final coordinator = SharedAudioCoordinator(
          backend: _FakeBackend(
            report: _report(
              selectedApplication: false,
              desktopAudio: true,
              desktopExcludesOwnAudio: true,
            ),
          ),
        );

        final plan = await coordinator.plan(_appRequest);
        final desktopOption = plan.options.first;

        expect(desktopOption.excludesOwnCallAudio, isTrue);
        expect(desktopOption.warning, contains('Notifications, other calls'));
        expect(desktopOption.warning, isNot(contains('echo')));
      },
    );

    test('reports unavailable when only the no-audio option remains', () async {
      final coordinator = SharedAudioCoordinator(
        backend: _FakeBackend(
          report: _report(selectedApplication: false, desktopAudio: false),
        ),
      );

      final plan = await coordinator.plan(_appRequest);

      expect(plan.kind, SharedAudioPlanKind.unavailable);
      expect(plan.options.single.mode, SharedAudioCaptureMode.none);
    });
  });

  group('SharedAudioCoordinator start', () {
    test('starts exactly the mode it was given', () async {
      final backend = _FakeBackend(
        report: _report(selectedApplication: true, desktopAudio: true),
      );
      final coordinator = SharedAudioCoordinator(backend: backend);

      final outcome = await coordinator.start(_appRequest);

      expect(outcome.started, isTrue);
      expect(
        backend.startCalls.single.mode,
        SharedAudioCaptureMode.selectedApplication,
      );
      expect(outcome.followUpPlan, isNull);
    });

    test('a runtime start failure yields a follow-up choice, not an automatic '
        'switch to system audio', () async {
      final backend = _FakeBackend(
        report: _report(
          selectedApplication: true,
          desktopAudio: true,
          desktopExcludesOwnAudio: false,
        ),
        startResult: const SharedAudioStartResult.failed(
          mode: SharedAudioCaptureMode.selectedApplication,
          backend: SharedAudioBackendKind.windowsProcessLoopback,
          reason: SharedAudioUnavailableReason.osRefusedActivation,
          nativeErrorCode: '0x80070005',
          failureStage: 'activation',
        ),
      );
      final coordinator = SharedAudioCoordinator(backend: backend);

      final outcome = await coordinator.start(_appRequest);

      expect(outcome.started, isFalse);
      expect(backend.startCalls, hasLength(1));
      expect(outcome.followUpPlan?.kind, SharedAudioPlanKind.needsUserChoice);
      expect(
        outcome.followUpPlan?.options.first.mode,
        SharedAudioCaptureMode.desktopAudio,
      );

      // start() carries the failure detail from the start result into the
      // follow-up plan. Asserted field by field because these are three
      // same-shaped strings being copied across a boundary: swapping
      // blockedReason and blockedDetail, or dropping the native code, is
      // exactly the kind of regression that leaves the plan looking well-formed
      // while the user-facing diagnosis is wrong.
      expect(
        outcome.followUpPlan?.blockedReason,
        SharedAudioUnavailableReason.osRefusedActivation,
      );
      expect(outcome.followUpPlan?.nativeErrorCode, '0x80070005');
      expect(outcome.followUpPlan?.failureStage, 'activation');
    });

    test(
      'logs platform, backend, modes, source, reason and native code',
      () async {
        final lines = <String>[];
        final coordinator = SharedAudioCoordinator(
          backend: _FakeBackend(
            report: _report(selectedApplication: true, desktopAudio: true),
            startResult: const SharedAudioStartResult.failed(
              mode: SharedAudioCaptureMode.selectedApplication,
              backend: SharedAudioBackendKind.windowsProcessLoopback,
              reason: SharedAudioUnavailableReason.osRefusedActivation,
              detail: 'refused',
              nativeErrorCode: '0x88890008',
              failureStage: 'activation',
              selectedSourceLabel: 'Some Game',
            ),
          ),
          logSink: lines.add,
        );

        await coordinator.start(_appRequest);

        final line = lines.single;
        expect(line, contains('platform=windows'));
        expect(line, contains('backend=windows.process_loopback'));
        expect(line, contains('requestedMode=selectedApplication'));
        expect(line, contains('selectedMode=none'));
        expect(line, contains('selectedSource="Some Game"'));
        expect(line, contains('fallbackReason=os_refused_activation'));
        expect(line, contains('nativeError=0x88890008'));
        expect(line, contains('failureStage=activation'));
      },
    );
  });

  group('platform capability contracts', () {
    test(
      'macOS reports a structured not-implemented reason, not silence',
      () async {
        const backend = MacosSharedAudioBackend();

        final report = await backend.probe(_appRequest);
        final availability = report.availabilityOf(
          SharedAudioCaptureMode.selectedApplication,
        );

        expect(backend.platform, 'macos');
        expect(backend.kind, SharedAudioBackendKind.macosScreenCaptureKit);
        expect(availability.available, isFalse);
        expect(
          availability.reason,
          SharedAudioUnavailableReason.backendNotImplemented,
        );
        expect(report.isAvailable(SharedAudioCaptureMode.none), isTrue);
      },
    );

    test('Linux reports a structured not-implemented reason', () async {
      const backend = LinuxSharedAudioBackend();

      final report = await backend.probe(_appRequest);

      expect(backend.platform, 'linux');
      expect(backend.kind, SharedAudioBackendKind.linuxPipeWirePortal);
      expect(
        report.availabilityOf(SharedAudioCaptureMode.desktopAudio).reason,
        SharedAudioUnavailableReason.backendNotImplemented,
      );
    });

    test('an unimplemented backend never claims to have started', () async {
      const backend = LinuxSharedAudioBackend();

      final result = await backend.start(_appRequest);

      expect(result.started, isFalse);
      expect(result.reason, SharedAudioUnavailableReason.backendNotImplemented);
    });
  });
}

const _appRequest = SharedAudioRequest(
  mode: SharedAudioCaptureMode.selectedApplication,
  targetProcessId: 4242,
  targetTitle: 'Some Game',
);

SharedAudioCapabilityReport _report({
  required bool selectedApplication,
  required bool desktopAudio,
  bool desktopExcludesOwnAudio = true,
  bool selectedDevice = false,
  List<SharedAudioDevice> devices = const [],
  SharedAudioUnavailableReason blockedReason =
      SharedAudioUnavailableReason.osRefusedActivation,
  String? nativeErrorCode,
}) {
  return SharedAudioCapabilityReport(
    platform: 'windows',
    backend: SharedAudioBackendKind.windowsProcessLoopback,
    devices: devices,
    modes: [
      if (selectedApplication)
        const SharedAudioModeAvailability(
          mode: SharedAudioCaptureMode.selectedApplication,
          available: true,
          backend: SharedAudioBackendKind.windowsProcessLoopback,
          canExcludeOwnCallAudio: true,
        )
      else
        SharedAudioModeAvailability.unavailable(
          mode: SharedAudioCaptureMode.selectedApplication,
          reason: blockedReason,
          backend: SharedAudioBackendKind.windowsProcessLoopback,
          nativeErrorCode: nativeErrorCode,
        ),
      if (desktopAudio)
        SharedAudioModeAvailability(
          mode: SharedAudioCaptureMode.desktopAudio,
          available: true,
          backend: desktopExcludesOwnAudio
              ? SharedAudioBackendKind.windowsProcessLoopback
              : SharedAudioBackendKind.windowsEndpointLoopback,
          canExcludeOwnCallAudio: desktopExcludesOwnAudio,
        )
      else
        const SharedAudioModeAvailability.unavailable(
          mode: SharedAudioCaptureMode.desktopAudio,
          reason: SharedAudioUnavailableReason.noCaptureDevice,
        ),
      if (selectedDevice)
        const SharedAudioModeAvailability(
          mode: SharedAudioCaptureMode.selectedDevice,
          available: true,
          backend: SharedAudioBackendKind.windowsDeviceCapture,
          canExcludeOwnCallAudio: false,
        )
      else
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
  _FakeBackend({required this.report, this.startResult});

  final SharedAudioCapabilityReport report;
  final SharedAudioStartResult? startResult;

  final List<SharedAudioRequest> startCalls = [];

  @override
  SharedAudioBackendKind get kind =>
      SharedAudioBackendKind.windowsProcessLoopback;

  @override
  String get platform => 'windows';

  @override
  Future<SharedAudioCapabilityReport> probe(SharedAudioRequest request) async =>
      report;

  @override
  Future<SharedAudioStartResult> start(SharedAudioRequest request) async {
    startCalls.add(request);
    return startResult ??
        SharedAudioStartResult(
          started: true,
          mode: request.mode,
          backend: SharedAudioBackendKind.windowsProcessLoopback,
          selectedSourceLabel: request.targetTitle,
          excludesOwnCallAudio: true,
        );
  }

  @override
  SharedAudioCaptureStatus get lastStatus =>
      const SharedAudioCaptureStatus.inactive();

  @override
  Future<SharedAudioCaptureStatus> refreshStatus() async => lastStatus;

  @override
  Future<MediaStream?> createPublicationStream() async => null;

  @override
  Future<void> disposePublicationStream() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
