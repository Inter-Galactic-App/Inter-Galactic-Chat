import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/shared_audio/shared_audio_backend.dart';
import 'package:intergalactic/client/components/voip/shared_audio/shared_audio_capability.dart';
import 'package:intergalactic/client/components/voip/shared_audio/windows_shared_audio_backend.dart';
import 'package:intergalactic_windows_share/intergalactic_windows_share.dart';

/// Windows 10 22H2. Below Microsoft's documented 20348 minimum for process
/// loopback, and the build the audit calls out: it must never by itself decide
/// that per-application capture is impossible.
const int kBuild19045 = 19045;

void main() {
  group('WindowsSharedAudioBackend capability probe', () {
    test('offers selected-application audio on build 19045 when the runtime '
        'activation succeeds', () async {
      final backend = WindowsSharedAudioBackend(
        binding: _FakeBinding(
          capabilities: _capabilities(
            osBuild: kBuild19045,
            processLoopbackActivates: true,
          ),
        ),
      );

      final report = await backend.probe(
        const SharedAudioRequest(
          mode: SharedAudioCaptureMode.selectedApplication,
          targetProcessId: 4242,
          targetTitle: 'Some Game',
        ),
      );

      final availability = report.availabilityOf(
        SharedAudioCaptureMode.selectedApplication,
      );
      expect(
        availability.available,
        isTrue,
        reason:
            'Build 19045 activating process loopback must be believed over '
            'the documented minimum build.',
      );
      expect(availability.canExcludeOwnCallAudio, isTrue);
      expect(report.osBuildLabel, '19045');
    });

    test('withholds selected-application audio on build 19045 when the runtime '
        'activation fails, and reports the HRESULT and stage', () async {
      final backend = WindowsSharedAudioBackend(
        binding: _FakeBinding(
          capabilities: _capabilities(
            osBuild: kBuild19045,
            processLoopbackActivates: false,
            processLoopbackHresult: '0x88890008',
            processLoopbackStage: WindowsSharedAudioFailureStage.activation,
          ),
        ),
      );

      final report = await backend.probe(
        const SharedAudioRequest(
          mode: SharedAudioCaptureMode.selectedApplication,
          targetProcessId: 4242,
        ),
      );

      final availability = report.availabilityOf(
        SharedAudioCaptureMode.selectedApplication,
      );
      expect(availability.available, isFalse);
      expect(
        availability.reason,
        SharedAudioUnavailableReason.osRefusedActivation,
      );
      expect(availability.nativeErrorCode, '0x88890008');
      expect(availability.failureStage, 'activation');
    });

    test('still offers desktop audio through endpoint loopback when process '
        'loopback is refused', () async {
      final backend = WindowsSharedAudioBackend(
        binding: _FakeBinding(
          capabilities: _capabilities(
            osBuild: kBuild19045,
            processLoopbackActivates: false,
          ),
        ),
      );

      final report = await backend.probe(
        const SharedAudioRequest(
          mode: SharedAudioCaptureMode.selectedApplication,
          targetProcessId: 4242,
        ),
      );

      final desktop = report.availabilityOf(
        SharedAudioCaptureMode.desktopAudio,
      );
      expect(desktop.available, isTrue);
      expect(desktop.backend, SharedAudioBackendKind.windowsEndpointLoopback);
      expect(
        desktop.canExcludeOwnCallAudio,
        isFalse,
        reason:
            'Endpoint loopback reads the whole render mix, so our own call '
            'audio cannot be excluded and the limitation must be surfaced.',
      );
      expect(desktop.mayIncludeOtherApplications, isTrue);
    });

    test(
      'prefers process loopback for desktop audio so our own call audio stays '
      'out of the capture',
      () async {
        final backend = WindowsSharedAudioBackend(
          binding: _FakeBinding(
            capabilities: _capabilities(
              osBuild: 22631,
              processLoopbackActivates: true,
            ),
          ),
        );

        final report = await backend.probe(
          const SharedAudioRequest(
            mode: SharedAudioCaptureMode.desktopAudio,
            sharingWholeScreen: true,
          ),
        );

        final desktop = report.availabilityOf(
          SharedAudioCaptureMode.desktopAudio,
        );
        expect(desktop.backend, SharedAudioBackendKind.windowsProcessLoopback);
        expect(desktop.canExcludeOwnCallAudio, isTrue);
      },
    );

    test('surfaces detected virtual devices as selectable endpoints', () async {
      final backend = WindowsSharedAudioBackend(
        binding: _FakeBinding(
          capabilities: _capabilities(
            osBuild: kBuild19045,
            processLoopbackActivates: false,
            hasVirtualAudioDevice: true,
          ),
          endpoints: const [
            WindowsAudioEndpointInfo(
              id: 'render-default',
              name: 'Speakers (Realtek)',
              isCapture: false,
              isDefault: true,
              isLikelyVirtual: false,
              virtualFamily: '',
            ),
            WindowsAudioEndpointInfo(
              id: 'cable-output',
              name: 'CABLE Output (VB-Audio Virtual Cable)',
              isCapture: true,
              isDefault: false,
              isLikelyVirtual: true,
              virtualFamily: 'vb-cable',
            ),
          ],
        ),
      );

      final report = await backend.probe(
        const SharedAudioRequest(mode: SharedAudioCaptureMode.desktopAudio),
      );

      expect(report.isAvailable(SharedAudioCaptureMode.selectedDevice), isTrue);
      expect(report.virtualDevices, hasLength(1));
      expect(report.virtualDevices.single.virtualFamilyLabel, 'VB-CABLE');
    });

    test('reports selected-application audio as unresolved for a whole-screen '
        'share rather than blaming the OS', () async {
      final backend = WindowsSharedAudioBackend(
        binding: _FakeBinding(
          capabilities: _capabilities(
            osBuild: 22631,
            processLoopbackActivates: true,
          ),
        ),
      );

      final report = await backend.probe(
        const SharedAudioRequest(
          mode: SharedAudioCaptureMode.selectedApplication,
          sharingWholeScreen: true,
        ),
      );

      final availability = report.availabilityOf(
        SharedAudioCaptureMode.selectedApplication,
      );
      expect(availability.available, isFalse);
      expect(
        availability.reason,
        SharedAudioUnavailableReason.targetProcessUnresolved,
      );
    });
  });

  group('WindowsSharedAudioBackend status surface', () {
    test('reports inactive before anything has been started', () {
      final backend = WindowsSharedAudioBackend(
        binding: _FakeBinding(
          capabilities: _capabilities(
            osBuild: kBuild19045,
            processLoopbackActivates: true,
          ),
        ),
      );

      expect(backend.lastStatus.capturing, isFalse);
      expect(backend.lastStatus.reason, isNull);
    });

    test('records a running capture after a successful start', () async {
      final backend = WindowsSharedAudioBackend(
        binding: _FakeBinding(
          capabilities: _capabilities(
            osBuild: kBuild19045,
            processLoopbackActivates: true,
          ),
        ),
      );
      await backend.start(
        const SharedAudioRequest(
          mode: SharedAudioCaptureMode.selectedApplication,
          targetProcessId: 4242,
        ),
      );

      final status = backend.lastStatus;
      expect(status.capturing, isTrue);
      expect(status.mode, SharedAudioCaptureMode.selectedApplication);
      expect(status.backend, SharedAudioBackendKind.windowsProcessLoopback);
      expect(status.canPublish, isTrue);
    });

    test(
      'keeps the elevated-target diagnosis but does not claim a live capture',
      () async {
        final backend = WindowsSharedAudioBackend(
          binding: _FakeBinding(
            capabilities: _capabilities(
              osBuild: 22631,
              processLoopbackActivates: true,
            ),
            targetElevated: true,
          ),
        );

        final result = await backend.start(
          const SharedAudioRequest(
            mode: SharedAudioCaptureMode.selectedApplication,
            targetProcessId: 4242,
          ),
        );
        expect(result.started, isFalse);

        final status = backend.lastStatus;
        expect(
          status.targetNotCapturable,
          isTrue,
          reason: 'This is what the elevated-target advisory keys on.',
        );
        expect(
          status.capturing,
          isFalse,
          reason:
              'The session was released, so the snapshot must not report a '
              'capture that no longer exists.',
        );
      },
    );

    test('records a failure that never reached a native status', () async {
      final backend = WindowsSharedAudioBackend(
        binding: _FakeBinding(
          capabilities: _capabilities(
            osBuild: kBuild19045,
            processLoopbackActivates: true,
          ),
        ),
      );

      await backend.start(
        const SharedAudioRequest(
          mode: SharedAudioCaptureMode.selectedApplication,
          sharingWholeScreen: true,
        ),
      );

      expect(backend.lastStatus.capturing, isFalse);
      expect(
        backend.lastStatus.reason,
        SharedAudioUnavailableReason.targetProcessUnresolved,
      );
    });

    test('a refresh surfaces a capture that is only hearing silence', () async {
      final backend = WindowsSharedAudioBackend(
        binding: _FakeBinding(
          capabilities: _capabilities(
            osBuild: kBuild19045,
            processLoopbackActivates: true,
          ),
          packetsCaptured: 5000,
          nonsilentBytesCaptured: 0,
        ),
      );
      await backend.start(
        const SharedAudioRequest(
          mode: SharedAudioCaptureMode.selectedApplication,
          targetProcessId: 4242,
        ),
      );

      final refreshed = await backend.refreshStatus();

      expect(refreshed.isCapturingOnlySilence, isTrue);
      expect(identical(backend.lastStatus, refreshed), isTrue);
    });

    test('a healthy capture is not reported as silent', () async {
      final backend = WindowsSharedAudioBackend(
        binding: _FakeBinding(
          capabilities: _capabilities(
            osBuild: kBuild19045,
            processLoopbackActivates: true,
          ),
          packetsCaptured: 5000,
          nonsilentBytesCaptured: 900000,
        ),
      );
      await backend.start(
        const SharedAudioRequest(
          mode: SharedAudioCaptureMode.selectedApplication,
          targetProcessId: 4242,
        ),
      );

      expect((await backend.refreshStatus()).isCapturingOnlySilence, isFalse);
    });

    test('stopping clears the capture but keeps the diagnosis', () async {
      final backend = WindowsSharedAudioBackend(
        binding: _FakeBinding(
          capabilities: _capabilities(
            osBuild: kBuild19045,
            processLoopbackActivates: true,
          ),
        ),
      );
      await backend.start(
        const SharedAudioRequest(
          mode: SharedAudioCaptureMode.selectedApplication,
          targetProcessId: 4242,
        ),
      );

      await backend.stop();

      expect(backend.lastStatus.capturing, isFalse);
      expect(
        backend.lastStatus.mode,
        SharedAudioCaptureMode.selectedApplication,
      );
    });

    test('carries everything ShareSession has to reconstruct: format, counters '
        'and the verbatim native reason', () async {
      final backend = WindowsSharedAudioBackend(
        binding: _FakeBinding(
          capabilities: _capabilities(
            osBuild: kBuild19045,
            processLoopbackActivates: true,
          ),
          packetsCaptured: 321,
        ),
      );
      await backend.start(
        const SharedAudioRequest(
          mode: SharedAudioCaptureMode.selectedApplication,
          targetProcessId: 4242,
        ),
      );

      final status = backend.lastStatus;
      // The developer diagnostics panel prints all of these; dropping them
      // degrades that line to zeroes without failing anything.
      expect(status.sampleRateHz, 44100);
      expect(status.numChannels, 2);
      expect(status.bitsPerSample, 16);
      expect(status.packetsCaptured, 321);
      expect(status.framesCaptured, 100);
      expect(status.bytesCaptured, 400);
      // The advisory matches this token exactly.
      expect(status.nativeReason, 'capturing');
      expect(status.state, SharedAudioCaptureState.active);
    });

    test(
      'preserves the platform refusal token a refused start reports',
      () async {
        final backend = WindowsSharedAudioBackend(
          binding: _FakeBinding(
            capabilities: _capabilities(
              osBuild: kBuild19045,
              processLoopbackActivates: true,
            ),
            startState: WindowsSharedAudioState.failed,
            startReason: 'process_loopback_activation_failed',
          ),
        );

        await backend.start(
          const SharedAudioRequest(
            mode: SharedAudioCaptureMode.selectedApplication,
            targetProcessId: 4242,
          ),
        );

        expect(
          backend.lastStatus.nativeReason,
          'process_loopback_activation_failed',
          reason:
              'The refusal advisory string-matches this exact token, so it must '
              'survive the trip through the platform-neutral status.',
        );
        expect(backend.lastStatus.state, SharedAudioCaptureState.failed);
      },
    );

    test('a stopped capture reads as stopped, not as failed', () async {
      final backend = WindowsSharedAudioBackend(
        binding: _FakeBinding(
          capabilities: _capabilities(
            osBuild: kBuild19045,
            processLoopbackActivates: true,
          ),
        ),
      );
      await backend.start(
        const SharedAudioRequest(
          mode: SharedAudioCaptureMode.selectedApplication,
          targetProcessId: 4242,
        ),
      );
      await backend.stop();

      expect(backend.lastStatus.state, SharedAudioCaptureState.stopped);
    });

    test(
      'refreshing with nothing running does not touch the platform',
      () async {
        final binding = _FakeBinding(
          capabilities: _capabilities(
            osBuild: kBuild19045,
            processLoopbackActivates: true,
          ),
        );
        final backend = WindowsSharedAudioBackend(binding: binding);

        final status = await backend.refreshStatus();

        expect(status.capturing, isFalse);
        expect(binding.pollReads, 0);
      },
    );
  });

  group('WindowsSharedAudioBackend start completion', () {
    test(
      'waits out a capture that is still starting instead of calling it failed',
      () async {
        final binding = _FakeBinding(
          capabilities: _capabilities(
            osBuild: kBuild19045,
            processLoopbackActivates: true,
          ),
          // Native Start() publishes `starting` and finishes on a capture
          // thread, so the first reads see a capture that is coming up fine.
          startingPolls: 3,
        );
        final backend = WindowsSharedAudioBackend(
          binding: binding,
          startPollInterval: const Duration(milliseconds: 1),
          startTimeout: const Duration(seconds: 2),
        );

        final result = await backend.start(
          const SharedAudioRequest(
            mode: SharedAudioCaptureMode.selectedApplication,
            targetProcessId: 4242,
            targetTitle: 'Some Game',
          ),
        );

        expect(
          result.started,
          isTrue,
          reason:
              'Reporting `starting` as a failure would fail nearly every real '
              'start, because that is what the native side reports first.',
        );
        expect(
          binding.pollReads,
          greaterThan(0),
          reason: 'The wait must actually poll for the settled state.',
        );
      },
    );

    test(
      'a capture stuck starting fails and leaves no session behind',
      () async {
        final binding = _FakeBinding(
          capabilities: _capabilities(
            osBuild: kBuild19045,
            processLoopbackActivates: true,
          ),
          startingPolls: 100000,
        );
        final backend = WindowsSharedAudioBackend(
          binding: binding,
          startPollInterval: const Duration(milliseconds: 1),
          startTimeout: const Duration(milliseconds: 20),
        );

        final result = await backend.start(
          const SharedAudioRequest(
            mode: SharedAudioCaptureMode.selectedApplication,
            targetProcessId: 4242,
          ),
        );

        expect(result.started, isFalse);
        expect(
          binding.disposedSessionIds,
          contains(1),
          reason: 'A start that never settles must still release its session.',
        );
      },
    );

    test(
      'a capture that settles into failure is not waited out again',
      () async {
        final binding = _FakeBinding(
          capabilities: _capabilities(
            osBuild: kBuild19045,
            processLoopbackActivates: true,
          ),
          startState: WindowsSharedAudioState.failed,
          startReason: 'process_loopback_activation_failed',
          lastHresult: '0x80070005',
          failureStage: WindowsSharedAudioFailureStage.activation,
        );
        final backend = WindowsSharedAudioBackend(
          binding: binding,
          startPollInterval: const Duration(milliseconds: 1),
          startTimeout: const Duration(seconds: 2),
        );

        final result = await backend.start(
          const SharedAudioRequest(
            mode: SharedAudioCaptureMode.selectedApplication,
            targetProcessId: 4242,
          ),
        );

        expect(result.started, isFalse);
        expect(result.nativeErrorCode, '0x80070005');
        expect(
          binding.pollReads,
          0,
          reason: 'An already-settled status must not be polled again.',
        );
      },
    );

    test(
      'does not publish when the native PCM bridge is unavailable',
      () async {
        final binding = _FakeBinding(
          capabilities: _capabilities(
            osBuild: kBuild19045,
            processLoopbackActivates: true,
          ),
          publicationSupported: true,
          pcmBridgeSupported: false,
        );
        final backend = WindowsSharedAudioBackend(binding: binding);

        final started = await backend.start(
          const SharedAudioRequest(
            mode: SharedAudioCaptureMode.selectedApplication,
            targetProcessId: 4242,
          ),
        );
        expect(started.started, isTrue);

        expect(await backend.createPublicationStream(), isNull);
        expect(
          binding.createdStreamSessionIds,
          isEmpty,
          reason:
              'The machine already reported it cannot build the bridge, so we '
              'should not ask it for a stream.',
        );
      },
    );
  });

  group('WindowsSharedAudioBackend publication lifecycle', () {
    Future<(WindowsSharedAudioBackend, _FakeBinding)> started({
      bool publicationSupported = true,
    }) async {
      final binding = _FakeBinding(
        capabilities: _capabilities(
          osBuild: kBuild19045,
          processLoopbackActivates: true,
        ),
        publicationSupported: publicationSupported,
      );
      final backend = WindowsSharedAudioBackend(binding: binding);
      final result = await backend.start(
        const SharedAudioRequest(
          mode: SharedAudioCaptureMode.selectedApplication,
          targetProcessId: 4242,
          targetTitle: 'Some Game',
        ),
      );
      expect(result.started, isTrue);
      return (backend, binding);
    }

    test('creates the publication once and reuses it', () async {
      final (backend, binding) = await started();

      final first = await backend.createPublicationStream();
      final second = await backend.createPublicationStream();

      expect(first, isNotNull);
      expect(identical(first, second), isTrue);
      expect(
        binding.createdStreamSessionIds,
        hasLength(1),
        reason: 'A second call must not open a second native stream.',
      );
    });

    test('publishes nothing when no capture is running', () async {
      final binding = _FakeBinding(
        capabilities: _capabilities(
          osBuild: kBuild19045,
          processLoopbackActivates: true,
        ),
        publicationSupported: true,
      );
      final backend = WindowsSharedAudioBackend(binding: binding);

      expect(await backend.createPublicationStream(), isNull);
      expect(binding.createdStreamSessionIds, isEmpty);
    });

    test(
      'releases the publication before disposing the session it belongs to',
      () async {
        final (backend, binding) = await started();
        await backend.createPublicationStream();

        await backend.dispose();

        final disposeStream = binding.callLog.indexOf('disposeStream:1');
        final disposeSession = binding.callLog.indexOf('disposeSession:1');
        expect(disposeStream, isNonNegative);
        expect(disposeSession, isNonNegative);
        expect(
          disposeStream,
          lessThan(disposeSession),
          reason:
              'A publication released after its session is disposed is a '
              'stream pointing at a capture that no longer exists.',
        );
      },
    );

    test('a superseding start releases the previous publication', () async {
      final (backend, binding) = await started();
      await backend.createPublicationStream();

      await backend.start(
        const SharedAudioRequest(
          mode: SharedAudioCaptureMode.selectedApplication,
          targetProcessId: 5150,
          targetTitle: 'Another Game',
        ),
      );

      expect(binding.disposedStreamSessionIds, contains(1));
      expect(
        binding.callLog.indexOf('disposeStream:1'),
        lessThan(binding.callLog.indexOf('disposeSession:1')),
      );
    });

    test('disposing the publication leaves the capture running', () async {
      final (backend, binding) = await started();
      await backend.createPublicationStream();

      await backend.disposePublicationStream();

      expect(binding.disposedStreamSessionIds, [1]);
      expect(binding.disposeAttempts, isEmpty);
      expect(backend.kind, SharedAudioBackendKind.windowsProcessLoopback);

      // The capture is still live, so publishing again is allowed and opens a
      // fresh native stream rather than handing back the released one.
      final republished = await backend.createPublicationStream();
      expect(republished, isNotNull);
      expect(binding.createdStreamSessionIds, [1, 1]);
    });

    test(
      'a publication disposal queued behind a start releases the new session',
      () async {
        final (backend, binding) = await started();

        // Queued together, so none of them has run when
        // `disposePublicationStream()` is called and `_session` is still the
        // outgoing session at that moment. `_serialized` invokes the closure
        // from inside its queued `.then`, so the field is read after the gate
        // drains and the disposal sees the session the start created. Nothing
        // asserted that before, which is how the shape came to be read as an
        // eager capture.
        final supersede = backend.start(
          const SharedAudioRequest(
            mode: SharedAudioCaptureMode.selectedApplication,
            targetProcessId: 5150,
            targetTitle: 'Another Game',
          ),
        );
        final publication = backend.createPublicationStream();
        final disposal = backend.disposePublicationStream();
        await Future.wait<void>([supersede, publication, disposal]);

        expect(
          binding.createdStreamSessionIds,
          [2],
          reason: 'The publication belongs to the superseding session.',
        );
        expect(
          binding.disposedStreamSessionIds,
          contains(2),
          reason:
              'The caller asked for the publication to be released and was '
              'told it had been.',
        );
      },
    );

    test(
      'a failed publication teardown is retried rather than forgotten',
      () async {
        final (backend, binding) = await started();
        await backend.createPublicationStream();
        binding.failDisposeStreamUntilAttempt = 2;

        await backend.disposePublicationStream();

        expect(
          binding.disposedStreamSessionIds,
          isEmpty,
          reason: 'The native side never confirmed the release.',
        );

        await backend.dispose();

        expect(
          binding.disposeStreamAttempts,
          [1, 1],
          reason:
              'The flags are cleared before the native call, so nothing else '
              'remembers the stream exists - without a retained id the leak is '
              'permanent and invisible.',
        );
        expect(binding.disposedStreamSessionIds, contains(1));
      },
    );

    test('disposing a publication that was never created is a no-op', () async {
      final (backend, binding) = await started();

      await backend.disposePublicationStream();

      expect(binding.disposedStreamSessionIds, isEmpty);
    });

    test(
      'an unsupported native stream publishes nothing and leaves no teardown '
      'owing',
      () async {
        final (backend, binding) = await started(publicationSupported: false);

        expect(await backend.createPublicationStream(), isNull);
        await backend.dispose();

        expect(
          binding.disposedStreamSessionIds,
          isEmpty,
          reason:
              'The native side reported it created nothing, so there is '
              'nothing to release.',
        );
      },
    );

    test(
      'a publication opened while a supersede lands is released, not orphaned',
      () async {
        final (backend, binding) = await started();

        // NOT "the supersede lands mid-publication" - `_serialized` makes that
        // impossible, because the supersede closure cannot start until
        // `_createPublicationStreamLocked` has returned. The real sequence is:
        // the publication completes and sets `publicationIssued`, then the
        // supersede calls `_openSession` -> `_releaseSession`, which disposes
        // the publication precisely because that flag is set.
        //
        // The same gate is why `_createPublicationStreamLocked`'s
        // `identical(current, session)` re-check is unreachable from any public
        // call: nothing can replace `_session` while a locked body is running.
        // It stays as defence for a future caller that mutates `_session`
        // outside the gate, and deliberately has no test rather than a test
        // that claims to reach it.
        final publication = backend.createPublicationStream();
        final supersede = backend.start(
          const SharedAudioRequest(
            mode: SharedAudioCaptureMode.selectedApplication,
            targetProcessId: 5150,
            targetTitle: 'Another Game',
          ),
        );
        await Future.wait<void>([publication, supersede]);

        expect(
          binding.disposedStreamSessionIds,
          contains(1),
          reason: 'The superseded session must not keep a native stream.',
        );
      },
    );
  });

  group('WindowsSharedAudioBackend start', () {
    test(
      'attempts process loopback on 19045 instead of refusing early',
      () async {
        final binding = _FakeBinding(
          capabilities: _capabilities(
            osBuild: kBuild19045,
            processLoopbackActivates: true,
          ),
        );
        final backend = WindowsSharedAudioBackend(binding: binding);

        final result = await backend.start(
          const SharedAudioRequest(
            mode: SharedAudioCaptureMode.selectedApplication,
            targetProcessId: 4242,
            targetTitle: 'Some Game',
          ),
        );

        expect(result.started, isTrue);
        expect(binding.createdAudioModes, [
          WindowsSharedAudioMode.processTreeLoopback,
        ]);
        expect(result.excludesOwnCallAudio, isTrue);
        expect(result.selectedSourceLabel, 'Some Game');
      },
    );

    test('maps desktop audio to endpoint loopback when process loopback is '
        'refused', () async {
      final binding = _FakeBinding(
        capabilities: _capabilities(
          osBuild: kBuild19045,
          processLoopbackActivates: false,
        ),
      );
      final backend = WindowsSharedAudioBackend(binding: binding);

      final result = await backend.start(
        const SharedAudioRequest(
          mode: SharedAudioCaptureMode.desktopAudio,
          sharingWholeScreen: true,
        ),
      );

      expect(result.started, isTrue);
      expect(binding.createdAudioModes, [
        WindowsSharedAudioMode.endpointLoopback,
      ]);
      expect(result.excludesOwnCallAudio, isFalse);
    });

    test(
      'passes the chosen device id through for selected-device capture',
      () async {
        final binding = _FakeBinding(
          capabilities: _capabilities(
            osBuild: kBuild19045,
            processLoopbackActivates: false,
          ),
        );
        final backend = WindowsSharedAudioBackend(binding: binding);

        final result = await backend.start(
          const SharedAudioRequest(
            mode: SharedAudioCaptureMode.selectedDevice,
            deviceId: 'cable-output',
          ),
        );

        expect(result.started, isTrue);
        expect(binding.createdAudioModes, [
          WindowsSharedAudioMode.deviceCapture,
        ]);
        expect(binding.createdDeviceIds, ['cable-output']);
      },
    );

    test(
      'treats an active capture against an elevated target as a failure',
      () async {
        final binding = _FakeBinding(
          capabilities: _capabilities(
            osBuild: 22631,
            processLoopbackActivates: true,
          ),
          startState: WindowsSharedAudioState.active,
          targetElevated: true,
        );
        final backend = WindowsSharedAudioBackend(binding: binding);

        final result = await backend.start(
          const SharedAudioRequest(
            mode: SharedAudioCaptureMode.selectedApplication,
            targetProcessId: 4242,
          ),
        );

        expect(result.started, isFalse);
        expect(result.reason, SharedAudioUnavailableReason.targetNotCapturable);
      },
    );

    test(
      'reports the native HRESULT and stage when the capture fails to start',
      () async {
        final binding = _FakeBinding(
          capabilities: _capabilities(
            osBuild: kBuild19045,
            processLoopbackActivates: true,
          ),
          startState: WindowsSharedAudioState.failed,
          startReason: 'process_loopback_activation_failed',
          lastHresult: '0x80070005',
          failureStage: WindowsSharedAudioFailureStage.activation,
        );
        final backend = WindowsSharedAudioBackend(binding: binding);

        final result = await backend.start(
          const SharedAudioRequest(
            mode: SharedAudioCaptureMode.selectedApplication,
            targetProcessId: 4242,
          ),
        );

        expect(result.started, isFalse);
        expect(result.nativeErrorCode, '0x80070005');
        expect(result.failureStage, 'activation');
        expect(result.reason, SharedAudioUnavailableReason.osRefusedActivation);
      },
    );

    test('a failed start releases the session it created', () async {
      // REGRESSION: both failure paths after createSession returned without
      // stopping or disposing it. start() reports a failure, so the caller
      // never learns a session exists and nothing else will ever tear it down
      // - the native loopback client would live until the process exits.
      final binding = _FakeBinding(
        capabilities: _capabilities(
          osBuild: kBuild19045,
          processLoopbackActivates: true,
        ),
        startState: WindowsSharedAudioState.failed,
        startReason: 'process_loopback_activation_failed',
      );
      final backend = WindowsSharedAudioBackend(binding: binding);

      final result = await backend.start(
        const SharedAudioRequest(
          mode: SharedAudioCaptureMode.selectedApplication,
          targetProcessId: 4242,
        ),
      );

      expect(result.started, isFalse);
      expect(binding.stoppedSessionIds, isNotEmpty);
      expect(binding.disposedSessionIds, binding.stoppedSessionIds);
    });

    test('an elevated target releases the session too', () async {
      // This path is worse than the plain failure: the capture IS active, so
      // the leak is an actively running capture of silence.
      final binding = _FakeBinding(
        capabilities: _capabilities(
          osBuild: kBuild19045,
          processLoopbackActivates: true,
        ),
        targetElevated: true,
      );
      final backend = WindowsSharedAudioBackend(binding: binding);

      final result = await backend.start(
        const SharedAudioRequest(
          mode: SharedAudioCaptureMode.selectedApplication,
          targetProcessId: 4242,
        ),
      );

      expect(result.started, isFalse);
      expect(result.reason, SharedAudioUnavailableReason.targetNotCapturable);
      expect(binding.disposedSessionIds, isNotEmpty);
    });

    test('stop() is idempotent and clears the reported backend', () async {
      final binding = _FakeBinding(
        capabilities: _capabilities(
          osBuild: kBuild19045,
          processLoopbackActivates: true,
        ),
      );
      final backend = WindowsSharedAudioBackend(binding: binding);
      final result = await backend.start(
        const SharedAudioRequest(
          mode: SharedAudioCaptureMode.selectedApplication,
          targetProcessId: 4242,
        ),
      );
      expect(result.started, isTrue);

      await backend.stop();
      await backend.stop();

      expect(
        binding.stoppedSessionIds.length,
        1,
        reason: 'the second stop must not re-issue against a dead session',
      );

      // The id still has to survive for dispose to release it.
      await backend.dispose();
      expect(binding.disposedSessionIds, isNotEmpty);

      // Pinned because the count is the whole point and the assertion above
      // runs BEFORE dispose(), which is exactly how a duplicate native stop
      // survived a green suite: release used to issue an unconditional second
      // stopSharedAudio here.
      expect(
        binding.stoppedSessionIds.length,
        1,
        reason: 'dispose() after stop() must not issue a second native stop',
      );
    });

    test('a session that fails to release is retried on dispose', () async {
      // REGRESSION: _abandonSession cleared _sessionId before attempting
      // teardown and swallowed the error, so a disposal that failed left the
      // native session alive with no handle anywhere - dispose() had nothing
      // to retry with and the leak became permanent and invisible.
      final binding = _FakeBinding(
        capabilities: _capabilities(
          osBuild: kBuild19045,
          processLoopbackActivates: true,
        ),
        startState: WindowsSharedAudioState.failed,
        startReason: 'process_loopback_activation_failed',
      )..failDisposeUntilAttempt = 2;
      final backend = WindowsSharedAudioBackend(binding: binding);

      final result = await backend.start(
        const SharedAudioRequest(
          mode: SharedAudioCaptureMode.selectedApplication,
          targetProcessId: 4242,
        ),
      );

      expect(result.started, isFalse);
      expect(
        binding.disposedSessionIds,
        isEmpty,
        reason: 'the first release attempt was rejected by the native side',
      );
      expect(binding.disposeAttempts, hasLength(1));

      // The handle was kept, so teardown can still succeed later.
      await backend.dispose();

      expect(binding.disposedSessionIds, isNotEmpty);
      expect(binding.disposeAttempts, hasLength(2));
    });

    test('a retained session survives a later start', () async {
      // The pending handle is held separately from _sessionId precisely so a
      // restart cannot overwrite the only reference to a leaked session. Both
      // starts fail their first release independently, so nothing here depends
      // on the ORDER in which the two sessions were attempted.
      final binding = _FakeBinding(
        capabilities: _capabilities(
          osBuild: kBuild19045,
          processLoopbackActivates: true,
        ),
        startState: WindowsSharedAudioState.failed,
        startReason: 'process_loopback_activation_failed',
      )..failDisposeUntilAttempt = 2;
      final backend = WindowsSharedAudioBackend(binding: binding);

      Future<void> failingStart() => backend.start(
        const SharedAudioRequest(
          mode: SharedAudioCaptureMode.selectedApplication,
          targetProcessId: 4242,
        ),
      );

      await failingStart();
      final firstSession = binding.disposeAttempts.single;
      await failingStart();
      final secondSession = binding.disposeAttempts.last;

      expect(secondSession, isNot(firstSession));
      expect(
        binding.disposedSessionIds,
        isEmpty,
        reason: 'each session was refused on its own first attempt',
      );

      await backend.dispose();

      expect(
        binding.disposedSessionIds,
        containsAll([firstSession, secondSession]),
        reason:
            'the session leaked by the first start must survive the second '
            'start and still be released',
      );
    });

    test(
      'start() rejects an unresolvable selected application itself',
      () async {
        // probe() reports this as targetProcessUnresolved; start() used to skip
        // the check and create a session with no owning process, so a caller
        // that did not probe first got a bogus capture or a raw OS failure
        // instead of the contractual reason.
        final binding = _FakeBinding(
          capabilities: _capabilities(
            osBuild: kBuild19045,
            processLoopbackActivates: true,
          ),
        );
        final backend = WindowsSharedAudioBackend(binding: binding);

        for (final request in const [
          // A whole-screen share has no single owning application.
          SharedAudioRequest(
            mode: SharedAudioCaptureMode.selectedApplication,
            targetProcessId: 4242,
            sharingWholeScreen: true,
          ),
          // The window owner could not be resolved.
          SharedAudioRequest(mode: SharedAudioCaptureMode.selectedApplication),
        ]) {
          final result = await backend.start(request);

          expect(result.started, isFalse);
          expect(
            result.reason,
            SharedAudioUnavailableReason.targetProcessUnresolved,
          );
        }

        expect(
          binding.createdAudioModes,
          isEmpty,
          reason: 'no native session may be created for an unresolvable target',
        );
      },
    );

    test('overlapping starts leave exactly one live session', () async {
      // REGRESSION: start() mutates _sessionId and _activeBackend across
      // awaits. Without serialization a first start that fails partway ran
      // _abandonSession over state already belonging to a second, successful
      // start. And even when both succeeded, the second overwrote _sessionId
      // without releasing the first, so that capture kept running with no
      // handle able to stop it.
      final binding = _FakeBinding(
        capabilities: _capabilities(
          osBuild: kBuild19045,
          processLoopbackActivates: true,
        ),
      );
      final backend = WindowsSharedAudioBackend(binding: binding);

      const request = SharedAudioRequest(
        mode: SharedAudioCaptureMode.selectedApplication,
        targetProcessId: 4242,
      );
      // Launched together, deliberately not awaited in sequence.
      final results = await Future.wait([
        backend.start(request),
        backend.start(request),
      ]);

      expect(results.every((result) => result.started), isTrue);
      expect(binding.createdSessionIds, hasLength(2));
      expect(
        binding.disposedSessionIds,
        contains(binding.createdSessionIds.first),
        reason: 'the superseded session must be released, not orphaned',
      );

      await backend.dispose();

      expect(
        binding.disposedSessionIds.toSet(),
        binding.createdSessionIds.toSet(),
        reason: 'every session created must be released by teardown',
      );
    });

    test('a throwing native call still releases what it created', () async {
      // These are platform-channel calls: they can throw outright rather than
      // report a failure status. A thrown error is the worst case to leak on,
      // because the caller gets an exception instead of a result and has no
      // way to know a session was left behind.
      final binding = _FakeBinding(
        capabilities: _capabilities(
          osBuild: kBuild19045,
          processLoopbackActivates: true,
        ),
      )..throwOnStartSharedAudio = true;
      final backend = WindowsSharedAudioBackend(binding: binding);

      const request = SharedAudioRequest(
        mode: SharedAudioCaptureMode.selectedApplication,
        targetProcessId: 4242,
      );
      await expectLater(backend.start(request), throwsStateError);

      expect(binding.createdSessionIds, hasLength(1));
      expect(
        binding.disposedSessionIds,
        binding.createdSessionIds,
        reason: 'the session created before the throw must be released',
      );

      // The gate must still be usable: a failed operation cannot wedge it.
      binding.throwOnStartSharedAudio = false;
      final recovered = await backend.start(request);
      expect(recovered.started, isTrue);
    });

    test('a throwing createSession does not leave a backend claim', () async {
      final binding = _FakeBinding(
        capabilities: _capabilities(
          osBuild: kBuild19045,
          processLoopbackActivates: true,
        ),
      )..throwOnCreateSession = true;
      final backend = WindowsSharedAudioBackend(binding: binding);

      await expectLater(
        backend.start(
          const SharedAudioRequest(
            mode: SharedAudioCaptureMode.selectedApplication,
            targetProcessId: 4242,
          ),
        ),
        throwsStateError,
      );

      expect(binding.createdSessionIds, isEmpty);
      // No session exists, so a later stop() must be a no-op rather than an
      // attempt against a capture that was never created.
      await backend.stop();
      expect(binding.stoppedSessionIds, isEmpty);
    });

    test('kind reports the running capture and stops claiming one after '
        'stop and dispose', () async {
      // The idempotence test above covers the native call; this covers what the
      // rest of the app reads. A finished capture reported as live is the same
      // defect seen through the accessor rather than through the binding, and
      // it was the half of that finding nothing asserted.
      final binding = _FakeBinding(
        capabilities: _capabilities(
          osBuild: kBuild19045,
          processLoopbackActivates: false,
        ),
      );
      final backend = WindowsSharedAudioBackend(binding: binding);

      expect(
        backend.kind,
        SharedAudioBackendKind.windowsProcessLoopback,
        reason: 'with nothing running, kind is the platform default',
      );

      final result = await backend.start(
        const SharedAudioRequest(
          mode: SharedAudioCaptureMode.desktopAudio,
          sharingWholeScreen: true,
        ),
      );
      expect(result.started, isTrue);
      expect(
        backend.kind,
        SharedAudioBackendKind.windowsEndpointLoopback,
        reason: 'a running capture reports the backend it actually runs on',
      );

      await backend.stop();
      expect(
        backend.kind,
        SharedAudioBackendKind.windowsProcessLoopback,
        reason: 'a stopped capture must not still be reported as live',
      );

      await backend.dispose();
      expect(backend.kind, SharedAudioBackendKind.windowsProcessLoopback);
    });

    test('a start that creates no session leaves nothing behind', () async {
      // The native side can refuse by returning a non-positive id rather than
      // throwing. It is the one start path that asked for a session and has
      // none to release, so it is also the one that could leave a claim behind
      // without any session existing to make the claim true.
      final binding = _FakeBinding(
        capabilities: _capabilities(
          osBuild: kBuild19045,
          processLoopbackActivates: true,
        ),
      )..createSessionReturnsNoSession = true;
      final backend = WindowsSharedAudioBackend(binding: binding);

      final result = await backend.start(
        const SharedAudioRequest(
          mode: SharedAudioCaptureMode.selectedApplication,
          targetProcessId: 4242,
        ),
      );

      expect(result.started, isFalse);
      expect(result.reason, SharedAudioUnavailableReason.backendUnavailable);
      expect(backend.kind, SharedAudioBackendKind.windowsProcessLoopback);

      await backend.stop();
      await backend.dispose();
      expect(binding.stoppedSessionIds, isEmpty);
      expect(binding.disposeAttempts, isEmpty);
    });

    test('a start after a stop still releases the stopped session', () async {
      // stop() ends the capture but deliberately keeps the session, because
      // dispose() still has to release it. A restart therefore supersedes a
      // session that is no longer capturing - and that one is easy to miss,
      // because nothing about it looks live.
      final binding = _FakeBinding(
        capabilities: _capabilities(
          osBuild: kBuild19045,
          processLoopbackActivates: true,
        ),
      );
      final backend = WindowsSharedAudioBackend(binding: binding);

      const request = SharedAudioRequest(
        mode: SharedAudioCaptureMode.selectedApplication,
        targetProcessId: 4242,
      );
      await backend.start(request);
      await backend.stop();
      final stopped = binding.createdSessionIds.single;

      await backend.start(request);

      expect(binding.createdSessionIds, hasLength(2));
      expect(
        binding.disposedSessionIds,
        contains(stopped),
        reason: 'the stopped-but-undisposed session must not be orphaned',
      );

      await backend.dispose();
      expect(
        binding.disposedSessionIds.toSet(),
        binding.createdSessionIds.toSet(),
      );
    });
  });
}

WindowsShareCapabilities _capabilities({
  required int osBuild,
  required bool processLoopbackActivates,
  bool hasVirtualAudioDevice = false,
  String processLoopbackHresult = '0x0',
  WindowsSharedAudioFailureStage processLoopbackStage =
      WindowsSharedAudioFailureStage.none,
}) {
  return WindowsShareCapabilities(
    supported: true,
    applicationLoopbackSupported: processLoopbackActivates,
    processTreeLoopbackSupported: processLoopbackActivates,
    wgcSupported: true,
    pcmBridgeSupported: true,
    endpointLoopbackSupported: true,
    deviceCaptureSupported: true,
    hasVirtualAudioDevice: hasVirtualAudioDevice,
    osBuild: osBuild,
    documentedProcessLoopbackBuild: 20348,
    processLoopbackHresult: processLoopbackHresult,
    processLoopbackStage: processLoopbackStage,
    reason: processLoopbackActivates
        ? 'ready'
        : 'process_loopback_activation_failed',
  );
}

class _FakeBinding implements WindowsShareNativeBinding {
  _FakeBinding({
    required this.capabilities,
    this.endpoints = const [
      WindowsAudioEndpointInfo(
        id: 'render-default',
        name: 'Speakers',
        isCapture: false,
        isDefault: true,
        isLikelyVirtual: false,
        virtualFamily: '',
      ),
      WindowsAudioEndpointInfo(
        id: 'mic-default',
        name: 'Microphone',
        isCapture: true,
        isDefault: true,
        isLikelyVirtual: false,
        virtualFamily: '',
      ),
    ],
    this.startState = WindowsSharedAudioState.active,
    this.startReason = 'capturing',
    this.lastHresult = '0x0',
    this.failureStage = WindowsSharedAudioFailureStage.none,
    this.targetElevated = false,
    this.publicationSupported = false,
    this.pcmBridgeSupported = true,
    this.startingPolls = 0,
    this.packetsCaptured = 10,
    this.nonsilentBytesCaptured = 400,
  });

  final WindowsShareCapabilities capabilities;
  final List<WindowsAudioEndpointInfo> endpoints;
  final WindowsSharedAudioState startState;
  final String startReason;
  final String lastHresult;
  final WindowsSharedAudioFailureStage failureStage;
  final bool targetElevated;

  /// When true, createSharedAudioStream returns a mappable stream so the
  /// publication path can be exercised end to end.
  final bool publicationSupported;

  /// Whether the native PCM bridge is reported available once capturing.
  final bool pcmBridgeSupported;

  /// How many status reads report `starting` before the state settles, so the
  /// start-completion wait can be exercised without real time passing.
  final int startingPolls;

  final int packetsCaptured;
  final int nonsilentBytesCaptured;

  int statusReads = 0;

  /// Counts only getSessionStatus calls, so a test can assert on the
  /// start-completion poll without stop/start status reads inflating it.
  int pollReads = 0;

  final List<WindowsSharedAudioMode> createdAudioModes = [];
  final List<String> createdDeviceIds = [];
  final List<int> createdStreamSessionIds = [];
  final List<int> disposedStreamSessionIds = [];

  /// Ordered log of native lifecycle calls. Ordering is the whole point of some
  /// of these assertions - releasing a publication after its session has been
  /// disposed is the defect, and only the order reveals it.
  final List<String> callLog = [];

  int _nextSessionId = 1;

  @override
  bool get isSupported => true;

  @override
  Future<WindowsShareCapabilities> getCapabilities() async => capabilities;

  @override
  Future<List<WindowsAudioEndpointInfo>> listAudioEndpoints() async =>
      endpoints;

  final List<int> createdSessionIds = [];

  /// Makes the corresponding native call throw, standing in for an FFI or
  /// platform-channel error rather than a reported failure status.
  bool throwOnCreateSession = false;
  bool throwOnStartSharedAudio = false;

  /// Makes createSession report "no session" (a non-positive id) instead of
  /// throwing. The native side can refuse this way, and it is the one start
  /// path where a session was requested but none exists to release.
  bool createSessionReturnsNoSession = false;
  final List<int> stoppedSessionIds = [];
  final List<int> disposedSessionIds = [];
  final List<int> disposeAttempts = [];
  final Map<int, int> _disposeAttemptsBySession = {};

  /// Makes disposeSession throw until this many attempts have been made FOR
  /// THAT session. Counted per session on purpose: a shared counter would let
  /// one session's failures decide when an unrelated one starts succeeding,
  /// so a test could pass because of call ordering rather than because a retry
  /// actually happened.
  int failDisposeUntilAttempt = 0;

  @override
  Future<List<WindowsShareTargetInfo>> listTargets() async => const [];

  @override
  Future<int> createSession({
    required WindowsShareTargetType targetType,
    required WindowsSharedAudioMode audioMode,
    int? processId,
    required bool requestSharedAudio,
    String deviceId = '',
  }) async {
    if (throwOnCreateSession) {
      throw StateError('native createSession failed');
    }
    createdAudioModes.add(audioMode);
    createdDeviceIds.add(deviceId);
    if (createSessionReturnsNoSession) {
      return 0;
    }
    final id = _nextSessionId++;
    createdSessionIds.add(id);
    return id;
  }

  @override
  Future<WindowsShareSessionStatus> startSharedAudio(int sessionId) async {
    if (throwOnStartSharedAudio) {
      throw StateError('native startSharedAudio failed');
    }
    return _status(sessionId);
  }

  @override
  Future<WindowsShareSessionStatus> stopSharedAudio(int sessionId) async {
    stoppedSessionIds.add(sessionId);
    return _status(sessionId);
  }

  @override
  Future<WindowsShareSessionStatus> getSessionStatus(int sessionId) async {
    pollReads++;
    return _status(sessionId);
  }

  WindowsShareSessionStatus _status(int sessionId) {
    // The native side reports `starting` until its capture thread has settled;
    // the first `startingPolls` reads reproduce that.
    final effectiveState = statusReads++ < startingPolls
        ? WindowsSharedAudioState.starting
        : startState;
    return WindowsShareSessionStatus(
      sessionId: sessionId,
      supported: true,
      requestedAudio: true,
      targetType: WindowsShareTargetType.window,
      audioMode: WindowsSharedAudioMode.processTreeLoopback,
      audioState: effectiveState,
      active: effectiveState == WindowsSharedAudioState.active,
      sampleRateHz: 44100,
      numChannels: 2,
      bitsPerSample: 16,
      packetsCaptured: packetsCaptured,
      framesCaptured: 100,
      bytesCaptured: 400,
      nonsilentBytesCaptured: nonsilentBytesCaptured,
      targetElevated: targetElevated,
      targetElevationKnown: true,
      pcmBridgeSupported: pcmBridgeSupported,
      wgcReady: true,
      lastHresult: lastHresult,
      failureStage: failureStage,
      selectedDeviceId: '',
      reason: startReason,
    );
  }

  @override
  Future<WindowsSharedAudioStreamInfo> createSharedAudioStream(
    int sessionId,
  ) async {
    createdStreamSessionIds.add(sessionId);
    callLog.add('createStream:$sessionId');
    if (!publicationSupported) {
      return WindowsSharedAudioStreamInfo.unavailable(sessionId: sessionId);
    }

    return WindowsSharedAudioStreamInfo(
      sessionId: sessionId,
      supported: true,
      streamId: 'stream-$sessionId',
      trackId: 'track-$sessionId',
      ownerTag: 'local',
      sampleRateHz: 44100,
      numChannels: 2,
      bitsPerSample: 16,
      audioTracks: const [
        WindowsSharedAudioTrackInfo(
          id: 'track',
          label: 'Windows shared audio',
          kind: 'audio',
          enabled: true,
          settings: {},
        ),
      ],
      videoTracks: const [],
      reason: 'ready',
    );
  }

  /// Makes disposeSharedAudioStream throw until this many attempts have been
  /// made, standing in for a native teardown that fails once and then works.
  int failDisposeStreamUntilAttempt = 0;

  /// Every attempt, successful or not. `disposedStreamSessionIds` records only
  /// the ones the native side confirmed, so the two together show whether a
  /// failed teardown was retried or silently forgotten.
  final List<int> disposeStreamAttempts = [];

  @override
  Future<void> disposeSharedAudioStream(int sessionId) async {
    disposeStreamAttempts.add(sessionId);
    if (disposeStreamAttempts.length < failDisposeStreamUntilAttempt) {
      throw StateError('native disposeSharedAudioStream failed');
    }
    disposedStreamSessionIds.add(sessionId);
    callLog.add('disposeStream:$sessionId');
  }

  @override
  Future<void> disposeSession(int sessionId) async {
    callLog.add('disposeSession:$sessionId');
    disposeAttempts.add(sessionId);
    final attempt = (_disposeAttemptsBySession[sessionId] ?? 0) + 1;
    _disposeAttemptsBySession[sessionId] = attempt;
    if (attempt < failDisposeUntilAttempt) {
      throw StateError('native dispose refused');
    }
    disposedSessionIds.add(sessionId);
  }
}
