import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intergalactic/client/components/voip/share_session/shared_audio_media_stream.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic_windows_share/intergalactic_windows_share.dart';

import 'shared_audio_backend.dart';
import 'shared_audio_capability.dart';

/// Windows shared-audio backend.
///
/// Serves [SharedAudioCaptureMode.selectedApplication] with process-specific
/// loopback, and [SharedAudioCaptureMode.desktopAudio] with either
/// process-loopback-excluding-ourselves (preferred, because it keeps our own
/// call audio out) or classic endpoint loopback (which cannot).
///
/// Capability comes from the native layer's real activation attempt. This class
/// never compares an OS build against a minimum, and in particular never treats
/// build 19045 as incapable: Microsoft documents 20348, but the activation
/// succeeds on a number of earlier servicing builds and fails on some later
/// ones. Only [WindowsShareCapabilities.applicationLoopbackSupported] - which
/// the native probe derives from an attempted activation - decides.
class WindowsSharedAudioBackend implements SharedAudioBackend {
  WindowsSharedAudioBackend({
    required WindowsShareNativeBinding binding,
    Duration startPollInterval = const Duration(milliseconds: 75),
    Duration startTimeout = const Duration(seconds: 3),
  }) : _binding = binding,
       _startPollInterval = startPollInterval,
       _startTimeout = startTimeout;

  final WindowsShareNativeBinding _binding;

  /// How the backend waits out a capture that is still coming up.
  ///
  /// Native `Start()` publishes `starting` and finishes on a capture thread, so
  /// the status read immediately after `startSharedAudio` is usually `starting`
  /// on a capture that is about to succeed. Injectable so tests can drive the
  /// poll without sleeping; the defaults match what the legacy ShareSession
  /// path used.
  final Duration _startPollInterval;
  final Duration _startTimeout;

  /// Last observation of the capture, kept so the call UI can read it while
  /// building a frame. Updated wherever the backend already learns something
  /// about the capture, so it cannot silently go stale relative to [_sessions].
  ///
  /// Still singular while one key is in use. Per-share status is step 3's
  /// problem, not something this step can answer: with two live captures there
  /// is no single "the" status to report through this interface.
  SharedAudioCaptureStatus _lastStatus =
      const SharedAudioCaptureStatus.inactive();

  @override
  SharedAudioCaptureStatus get lastStatus => _lastStatus;

  /// The one field that owns native sessions, keyed by share.
  ///
  /// Written only by [_openSession] (the only place a session is created) and
  /// [_releaseSession] (the only place one is released). Nothing else records
  /// that a capture exists, so there is no second field that can disagree with
  /// this one about whether a session is live or which backend it runs on.
  ///
  /// Keyed rather than singular so that "one live session per share" is a
  /// property of the container instead of a rule each call site has to keep.
  /// [_openSession] releases the incumbent *for its own key*, which is what
  /// makes a second concurrent session for one share unexpressible - the shape
  /// BUG-301 exploited, where two per-source backends each held a session and
  /// neither could see the other's.
  ///
  /// Exactly one key is in use today ([_defaultSessionKey]); the caller does
  /// not yet register a share per video publication. Until it does, every
  /// keyed path below has the same behaviour the single field had.
  final Map<Object, _SharedAudioSession> _sessions =
      <Object, _SharedAudioSession>{};

  /// The single key in use while the caller still creates one share session.
  ///
  /// Named rather than inlined so the step that introduces real per-share keys
  /// changes call sites the compiler can find, instead of a bare literal.
  static const Object _defaultSessionKey = 'default';

  /// Serializes [start], [stop], and [dispose].
  ///
  /// All three mutate [_sessions] across awaits, so overlapping calls
  /// interleave: without the gate two concurrent starts each create a native
  /// session, and only one of them can be the owned one. Same hazard between a
  /// stop or dispose and an in-flight start.
  ///
  /// Queued rather than rejected, so a caller that stops and immediately
  /// restarts still gets both operations, in the order it asked for them.
  Future<void> _lifecycleGate = Future.value();

  /// Runs [operation] after every previously queued lifecycle operation has
  /// settled. A failing operation does not poison the queue.
  Future<T> _serialized<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _lifecycleGate = _lifecycleGate.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  @override
  String get platform => 'windows';

  /// The backend of the running capture, or this platform's default when
  /// nothing is capturing.
  ///
  /// Read off the session itself rather than off a parallel field, so a stopped
  /// or released capture cannot still be reported as live.
  @override
  SharedAudioBackendKind get kind {
    // First capturing session rather than a named key: with one key in use
    // this is that key, and it keeps the getter honest if a second is ever
    // registered before this interface grows a key of its own.
    for (final session in _sessions.values) {
      if (session.capturing) {
        return session.backend;
      }
    }
    return SharedAudioBackendKind.windowsProcessLoopback;
  }

  @override
  Future<SharedAudioCapabilityReport> probe(SharedAudioRequest request) async {
    if (!_binding.isSupported) {
      return _unavailableReport(
        SharedAudioUnavailableReason.backendUnavailable,
        'The Windows share plugin is not available in this build.',
      );
    }

    final capabilities = await _binding.getCapabilities();
    final endpoints = await _binding.listAudioEndpoints();
    final devices = endpoints
        .map(
          (endpoint) => SharedAudioDevice(
            id: endpoint.id,
            name: endpoint.name,
            isCapture: endpoint.isCapture,
            isDefault: endpoint.isDefault,
            isLikelyVirtual: endpoint.isLikelyVirtual,
            virtualFamily: endpoint.virtualFamily,
          ),
        )
        .toList(growable: false);

    return SharedAudioCapabilityReport(
      platform: platform,
      backend: capabilities.applicationLoopbackSupported
          ? SharedAudioBackendKind.windowsProcessLoopback
          : SharedAudioBackendKind.windowsEndpointLoopback,
      osBuildLabel: capabilities.osBuild == 0
          ? ''
          : capabilities.osBuild.toString(),
      devices: devices,
      modes: [
        _selectedApplicationAvailability(capabilities, request),
        _desktopAudioAvailability(capabilities),
        _selectedDeviceAvailability(capabilities, devices),
        const SharedAudioModeAvailability(
          mode: SharedAudioCaptureMode.none,
          available: true,
          backend: SharedAudioBackendKind.none,
          canExcludeOwnCallAudio: true,
        ),
      ],
    );
  }

  SharedAudioModeAvailability _selectedApplicationAvailability(
    WindowsShareCapabilities capabilities,
    SharedAudioRequest request,
  ) {
    const mode = SharedAudioCaptureMode.selectedApplication;

    if (!capabilities.processTreeLoopbackSupported) {
      return SharedAudioModeAvailability.unavailable(
        mode: mode,
        reason: SharedAudioUnavailableReason.osRefusedActivation,
        backend: SharedAudioBackendKind.windowsProcessLoopback,
        detail:
            'Windows refused per-application audio capture on this machine. '
            'This is the result of attempting the capture, not of the Windows '
            'version.',
        nativeErrorCode: _emptyToNull(capabilities.processLoopbackHresult),
        failureStage: capabilities.processLoopbackStage.name,
      );
    }

    if (request.sharingWholeScreen) {
      return SharedAudioModeAvailability.unavailable(
        mode: mode,
        reason: SharedAudioUnavailableReason.targetProcessUnresolved,
        backend: SharedAudioBackendKind.windowsProcessLoopback,
        detail:
            'A whole-screen share has no single owning application to capture '
            'audio from.',
      );
    }

    if (request.targetProcessId == null) {
      return SharedAudioModeAvailability.unavailable(
        mode: mode,
        reason: SharedAudioUnavailableReason.targetProcessUnresolved,
        backend: SharedAudioBackendKind.windowsProcessLoopback,
        detail:
            'The application that owns the shared window could not be '
            'identified.',
      );
    }

    return const SharedAudioModeAvailability(
      mode: mode,
      available: true,
      backend: SharedAudioBackendKind.windowsProcessLoopback,
      // Process loopback captures only the target tree, so our own call audio
      // is inherently excluded.
      canExcludeOwnCallAudio: true,
    );
  }

  SharedAudioModeAvailability _desktopAudioAvailability(
    WindowsShareCapabilities capabilities,
  ) {
    const mode = SharedAudioCaptureMode.desktopAudio;

    // Preferred: process loopback in exclude-our-own-tree mode. Captures every
    // other application while keeping Inter Galactic's received call audio out.
    if (capabilities.applicationLoopbackSupported) {
      return const SharedAudioModeAvailability(
        mode: mode,
        available: true,
        backend: SharedAudioBackendKind.windowsProcessLoopback,
        canExcludeOwnCallAudio: true,
      );
    }

    // Fallback: classic endpoint loopback. Works essentially everywhere WASAPI
    // does, but it reads the whole render mix and therefore re-captures our own
    // call audio.
    if (capabilities.endpointLoopbackSupported) {
      return SharedAudioModeAvailability(
        mode: mode,
        available: true,
        backend: SharedAudioBackendKind.windowsEndpointLoopback,
        canExcludeOwnCallAudio: false,
        detail:
            'Captures everything playing on the selected output device, '
            'including other apps and this call.',
        nativeErrorCode: _emptyToNull(capabilities.processLoopbackHresult),
        failureStage: capabilities.processLoopbackStage.name,
      );
    }

    return SharedAudioModeAvailability.unavailable(
      mode: mode,
      reason: SharedAudioUnavailableReason.noCaptureDevice,
      backend: SharedAudioBackendKind.windowsEndpointLoopback,
      detail: 'No playback device is available to capture from.',
      nativeErrorCode: _emptyToNull(capabilities.processLoopbackHresult),
    );
  }

  SharedAudioModeAvailability _selectedDeviceAvailability(
    WindowsShareCapabilities capabilities,
    List<SharedAudioDevice> devices,
  ) {
    const mode = SharedAudioCaptureMode.selectedDevice;

    final hasCaptureEndpoint = devices.any((device) => device.isCapture);
    if (!capabilities.deviceCaptureSupported || !hasCaptureEndpoint) {
      return const SharedAudioModeAvailability.unavailable(
        mode: mode,
        reason: SharedAudioUnavailableReason.noCaptureDevice,
        backend: SharedAudioBackendKind.windowsDeviceCapture,
        detail: 'No recording device is available to capture from.',
      );
    }

    return const SharedAudioModeAvailability(
      mode: mode,
      available: true,
      backend: SharedAudioBackendKind.windowsDeviceCapture,
      // A virtual cable carries whatever the user routed into it, which may
      // include this call.
      canExcludeOwnCallAudio: false,
      detail:
          'Captures whatever is routed into the chosen device. Inter Galactic '
          'does not change your audio routing.',
    );
  }

  @override
  Future<SharedAudioStartResult> start(SharedAudioRequest request) =>
      _serialized(() => _startAndRecord(request));

  /// Set by [_captureWith] when the attempt got far enough to read a native
  /// status, which carries more than the start result does - capture counters,
  /// target capturability, publishability. Consumed by [_startAndRecord].
  SharedAudioCaptureStatus? _nativeAttemptStatus;

  /// Records the outcome in [lastStatus] whatever it is.
  ///
  /// Wrapping [_startLocked] rather than assigning at each of its exits is what
  /// makes this hold: a failure path added to [_startLocked] later is recorded
  /// without its author having to remember to, the same reason session release
  /// is wrapped rather than repeated.
  Future<SharedAudioStartResult> _startAndRecord(
    SharedAudioRequest request,
  ) async {
    _nativeAttemptStatus = null;
    try {
      final result = await _startLocked(request);
      final observed = _nativeAttemptStatus ?? _statusFromResult(result);
      // An elevated target reports `active` natively while the start is
      // reported as failed, and the session is released. Deriving `capturing`
      // from whether the capture was KEPT rather than from the native state is
      // what stops the snapshot claiming a live capture that no longer exists,
      // without discarding the diagnosis the UI needs.
      _lastStatus = result.started ? observed : observed.asStopped();
      return result;
    } catch (_) {
      // A throw means no usable observation, so record that nothing is running
      // rather than leaving the previous capture's status standing.
      _lastStatus =
          _nativeAttemptStatus ??
          SharedAudioCaptureStatus.inactive(
            mode: request.mode,
            reason: SharedAudioUnavailableReason.unknown,
            detail: 'The Windows share plugin failed while starting capture.',
          );
      rethrow;
    } finally {
      _nativeAttemptStatus = null;
    }
  }

  /// Fallback mapping for attempts that never reached a native status, such as
  /// an unresolvable target or a mode this machine cannot serve.
  SharedAudioCaptureStatus _statusFromResult(SharedAudioStartResult result) {
    return SharedAudioCaptureStatus(
      mode: result.mode,
      backend: result.backend,
      state: result.started
          ? SharedAudioCaptureState.active
          : SharedAudioCaptureState.unavailable,
      reason: result.reason,
      // Deliberately left empty. This path never reached the native layer, so
      // there is no platform token to carry, and `detail` here is a
      // user-facing sentence. Putting it in `nativeReason` corrupted the
      // `reason=` field of the structured evidence lines - that field is
      // matched verbatim and must stay a single token.
      detail: result.detail,
      nativeErrorCode: result.nativeErrorCode,
      failureStage: result.failureStage,
    );
  }

  Future<SharedAudioStartResult> _startLocked(
    SharedAudioRequest request,
  ) async {
    if (request.mode == SharedAudioCaptureMode.none) {
      return const SharedAudioStartResult.failed(
        mode: SharedAudioCaptureMode.none,
        backend: SharedAudioBackendKind.none,
        reason: SharedAudioUnavailableReason.notRequested,
      );
    }

    // The same rejection probe() reports, applied here too. start() must not
    // depend on the caller having probed first: without this it would create a
    // display-or-window session with no owning process and then report either
    // a bogus success or a raw OS failure, instead of the reason the contract
    // says a selected-application request with no resolvable target gets.
    if (request.mode == SharedAudioCaptureMode.selectedApplication &&
        (request.sharingWholeScreen || request.targetProcessId == null)) {
      return SharedAudioStartResult.failed(
        mode: request.mode,
        backend: SharedAudioBackendKind.windowsProcessLoopback,
        reason: SharedAudioUnavailableReason.targetProcessUnresolved,
        detail: request.sharingWholeScreen
            ? 'A whole-screen share has no single owning application to '
                  'capture audio from.'
            : 'The application that owns the shared window could not be '
                  'identified.',
        selectedSourceLabel: _sourceLabel(request),
      );
    }

    final capabilities = await _binding.getCapabilities();
    final resolved = _resolveNativeMode(request, capabilities);
    if (resolved == null) {
      return SharedAudioStartResult.failed(
        mode: request.mode,
        backend: SharedAudioBackendKind.none,
        reason: SharedAudioUnavailableReason.osRefusedActivation,
        detail: 'No Windows capture mechanism can serve ${request.mode.label}.',
        nativeErrorCode: _emptyToNull(capabilities.processLoopbackHresult),
        failureStage: capabilities.processLoopbackStage.name,
      );
    }

    final session = await _openSession(_defaultSessionKey, request, resolved);
    if (session == null) {
      // Nothing was created, so there is nothing to release.
      return SharedAudioStartResult.failed(
        mode: request.mode,
        backend: resolved.backend,
        reason: SharedAudioUnavailableReason.backendUnavailable,
        detail: 'The Windows share plugin did not create a capture session.',
      );
    }

    // A session exists from here on, and the only way out of this block that
    // keeps it is a result saying the capture started. A failure result and a
    // thrown platform-channel error both release it, and neither depends on the
    // code below remembering to - which is what stops the next failure path
    // added here from reintroducing a leaked session.
    try {
      final result = await _captureWith(request, session);
      if (!result.started) {
        await _releaseSession(_defaultSessionKey);
      }
      return result;
    } catch (_) {
      await _releaseSession(_defaultSessionKey);
      rethrow;
    }
  }

  /// Brings [session] up as a running capture, or describes why it did not.
  ///
  /// Never releases anything: the caller does that for every unsuccessful
  /// outcome, including a thrown one.
  Future<SharedAudioStartResult> _captureWith(
    SharedAudioRequest request,
    _SharedAudioSession session,
  ) async {
    // A platform-channel call, so it can throw outright rather than report a
    // failure status.
    final status = await _awaitStartOutcome(
      session,
      await _binding.startSharedAudio(session.id),
    );

    _nativeAttemptStatus = _statusFrom(
      status,
      mode: request.mode,
      backend: session.backend,
    );

    if (status.audioState != WindowsSharedAudioState.active) {
      return SharedAudioStartResult.failed(
        mode: request.mode,
        backend: session.backend,
        reason: _reasonForStatus(status),
        detail: status.reason,
        nativeErrorCode: _emptyToNull(status.lastHresult),
        failureStage: status.failureStage.name,
        selectedSourceLabel: _sourceLabel(request),
      );
    }

    // An active capture against an elevated target only ever yields silence, so
    // it is reported as a failure rather than as a working capture.
    if (status.targetElevated) {
      return SharedAudioStartResult.failed(
        mode: request.mode,
        backend: session.backend,
        reason: SharedAudioUnavailableReason.targetNotCapturable,
        detail:
            'The shared application runs with higher privileges than Inter '
            'Galactic, so Windows blocks capturing its audio.',
        nativeErrorCode: _emptyToNull(status.lastHresult),
        selectedSourceLabel: _sourceLabel(request),
      );
    }

    session.capturing = true;
    session.pcmBridgeSupported = status.pcmBridgeSupported;
    return SharedAudioStartResult(
      started: true,
      mode: request.mode,
      backend: session.backend,
      selectedSourceLabel: _sourceLabel(request),
      excludesOwnCallAudio:
          session.backend == SharedAudioBackendKind.windowsProcessLoopback,
    );
  }

  /// Resolves a still-starting capture into its settled outcome.
  ///
  /// `startSharedAudio` returns as soon as the native side has *accepted* the
  /// request: `ProcessLoopbackCapture::Start` sets `starting` and then does the
  /// activation on a capture thread. So the first status is normally `starting`
  /// even for a capture that comes up fine, and treating it as a failure would
  /// report almost every successful start as failed. Polls until the state
  /// settles or the timeout elapses.
  ///
  /// A timeout deliberately returns the last `starting` status rather than
  /// synthesising a failure: the caller's existing mapping turns a non-active
  /// state into a failure result, and inventing a reason here would replace the
  /// native one.
  Future<WindowsShareSessionStatus> _awaitStartOutcome(
    _SharedAudioSession session,
    WindowsShareSessionStatus initial,
  ) async {
    if (initial.audioState != WindowsSharedAudioState.starting) {
      return initial;
    }

    // No re-check of _sessions inside the loop: this runs inside the lifecycle
    // gate, so a superseding start, stop or dispose queued behind it cannot run
    // until this returns. The session polled here is therefore still the owned
    // one for the whole wait. The cost is that a stop issued during a slow
    // start waits it out, which is the intended reading of the gate - the stop
    // applies to a capture whose outcome is known.
    var status = initial;
    final deadline = DateTime.now().add(_startTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(_startPollInterval);
      status = await _binding.getSessionStatus(session.id);
      if (status.audioState != WindowsSharedAudioState.starting) {
        return status;
      }
    }

    return status;
  }

  /// The only place a native session is created.
  ///
  /// Releases the session already held for [key] first: overwriting the entry
  /// would otherwise drop the only handle to a capture that keeps running with
  /// nothing able to stop it.
  ///
  /// The release is scoped to [key] on purpose. Releasing every key here would
  /// make a second share silently stop the first, which is the behaviour change
  /// this step is specifically not making.
  ///
  /// Returns null when the native side declined to create one. [createSession]
  /// is a platform-channel call and can throw instead; either way nothing was
  /// acquired, and the entry for [key] is already absent because of the release
  /// above - so neither outcome can leave a session or a backend claim behind.
  Future<_SharedAudioSession?> _openSession(
    Object key,
    SharedAudioRequest request,
    _ResolvedWindowsMode resolved,
  ) async {
    await _releaseSession(key);

    final sessionId = await _binding.createSession(
      targetType: request.sharingWholeScreen
          ? WindowsShareTargetType.display
          : WindowsShareTargetType.window,
      audioMode: resolved.nativeMode,
      processId: request.targetProcessId,
      requestSharedAudio: true,
      deviceId: request.deviceId,
    );
    if (sessionId <= 0) {
      return null;
    }

    return _sessions[key] = _SharedAudioSession(
      id: sessionId,
      backend: resolved.backend,
    );
  }

  _ResolvedWindowsMode? _resolveNativeMode(
    SharedAudioRequest request,
    WindowsShareCapabilities capabilities,
  ) {
    switch (request.mode) {
      case SharedAudioCaptureMode.selectedApplication:
        if (!capabilities.processTreeLoopbackSupported) {
          return null;
        }
        return const _ResolvedWindowsMode(
          WindowsSharedAudioMode.processTreeLoopback,
          SharedAudioBackendKind.windowsProcessLoopback,
        );

      case SharedAudioCaptureMode.desktopAudio:
        if (capabilities.applicationLoopbackSupported) {
          return const _ResolvedWindowsMode(
            WindowsSharedAudioMode.systemLoopback,
            SharedAudioBackendKind.windowsProcessLoopback,
          );
        }
        if (capabilities.endpointLoopbackSupported) {
          return const _ResolvedWindowsMode(
            WindowsSharedAudioMode.endpointLoopback,
            SharedAudioBackendKind.windowsEndpointLoopback,
          );
        }
        return null;

      case SharedAudioCaptureMode.selectedDevice:
        if (!capabilities.deviceCaptureSupported) {
          return null;
        }
        return const _ResolvedWindowsMode(
          WindowsSharedAudioMode.deviceCapture,
          SharedAudioBackendKind.windowsDeviceCapture,
        );

      case SharedAudioCaptureMode.none:
        return null;
    }
  }

  SharedAudioUnavailableReason _reasonForStatus(
    WindowsShareSessionStatus status,
  ) {
    if (status.targetElevated) {
      return SharedAudioUnavailableReason.targetNotCapturable;
    }
    if (status.reason == 'target_process_unresolved') {
      return SharedAudioUnavailableReason.targetProcessUnresolved;
    }
    if (status.reason == 'selected_audio_device_unavailable' ||
        status.failureStage == WindowsSharedAudioFailureStage.deviceNotFound) {
      return SharedAudioUnavailableReason.noCaptureDevice;
    }
    return SharedAudioUnavailableReason.osRefusedActivation;
  }

  String _sourceLabel(SharedAudioRequest request) {
    if (request.mode == SharedAudioCaptureMode.selectedDevice) {
      return request.deviceId.isEmpty ? 'default device' : request.deviceId;
    }
    return request.targetTitle;
  }

  /// The only way a session stops being owned.
  ///
  /// Stops the capture and disposes it, then drops [key] from [_sessions]. It
  /// takes a key rather than a session on purpose: releasing anything other
  /// than the session the owner holds for that key is not something a caller
  /// can ask for.
  ///
  /// This is also the reason a session created by a failed [start] does not
  /// leak. [start] returns a failure result on those paths, so the caller never
  /// learns a session existed and nothing would ever call [stop] or [dispose]
  /// for it — the native loopback client would live until the process exits,
  /// and in the elevated-target case it is actively capturing (silence) while
  /// it does.
  ///
  /// Teardown errors are logged, not thrown, unless [reportFailure] is set:
  /// cleanup callers are already telling the caller why the start failed, and
  /// replacing that specific reason with a teardown error would lose the
  /// diagnosis. [dispose] is the one caller that asked for teardown and is
  /// entitled to know it did not happen, so it sets the flag. Forgetting it
  /// changes only what is reported, never what is released.
  ///
  /// A session whose disposal fails is moved to [_sessionsAwaitingDispose]
  /// rather than dropped. Swallowing the error AND forgetting the id would make
  /// the leak permanent and invisible — [dispose] could not retry, because
  /// nothing would remember the session existed.
  Future<void> _releaseSession(Object key, {bool reportFailure = false}) async {
    final session = _sessions.remove(key);
    if (session == null) {
      return;
    }
    session.capturing = false;
    _lastStatus = _lastStatus.asStopped();

    // Publication first, and before the stop: it is a child of this session, so
    // releasing it after disposeSession would be releasing a stream whose
    // capture no longer exists. This is the only teardown path, so it is also
    // the only place the publication has to be remembered.
    //
    // Gated on publicationIssued so teardown releases exactly what was created.
    // The flag tracks the native side rather than the Dart handle, and there is
    // no await between the native create returning `supported` and it being
    // set, so it cannot disagree with what the native layer holds.
    if (session.publicationIssued) {
      await _disposeNativePublication(session);
    }

    // Stop only if nothing has stopped this session yet. Gating on `capturing`
    // instead would look equivalent and is not: a start that fails after
    // createSession never sets it, and the failed-start path asserts the
    // session is both stopped AND disposed, so that gate would silently skip
    // the stop and reopen the leak. Tracking the stop removes the duplicate on
    // the stop-then-dispose and stop-then-supersede paths without touching it.
    if (!session.stopIssued) {
      session.stopIssued = true;
      try {
        await _binding.stopSharedAudio(session.id);
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to stop shared-audio session ${session.id}',
        );
      }
    }
    try {
      await _binding.disposeSession(session.id);
      // The session owns its publication, so releasing it releases any stream
      // still outstanding. Retrying that id afterwards would be a call against
      // a session that no longer exists.
      _publicationsAwaitingDispose.remove(session.id);
    } catch (error, stackTrace) {
      _sessionsAwaitingDispose.add(session.id);
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to dispose shared-audio session ${session.id}; retained '
            'for retry on a later dispose',
      );
      if (reportFailure) {
        rethrow;
      }
    }
  }

  /// Releases every key. Call teardown ends all of this owner's captures, and
  /// doing it one key at a time keeps each release's failure handling - the
  /// [_sessionsAwaitingDispose] retry in particular - identical to the single
  /// case rather than a second implementation of it.
  ///
  /// Iterates a copy: [_releaseSession] mutates [_sessions].
  Future<void> _releaseAllSessions({bool reportFailure = false}) async {
    for (final key in _sessions.keys.toList()) {
      await _releaseSession(key, reportFailure: reportFailure);
    }
  }

  /// Sessions the native side still holds because a release attempt failed.
  /// Retried on [dispose]; kept separate from [_sessions] so a subsequent
  /// [start] cannot overwrite the only handle to a leaked session.
  ///
  /// Written from [_releaseSession] only, so an id can leave [_sessions] without
  /// landing here in exactly one case: the native side confirmed the disposal.
  final Set<int> _sessionsAwaitingDispose = <int>{};

  /// Retries every session a previous release attempt could not free.
  ///
  /// Failures are logged and the handle is kept, so a later [dispose] can try
  /// again rather than the session becoming unreachable.
  Future<void> _drainPendingDisposals() async {
    // Publications first: a stream outlives nothing, so releasing it before the
    // session it belongs to is the same ordering every other teardown path uses.
    for (final pending in _publicationsAwaitingDispose.toList()) {
      try {
        await _binding.disposeSharedAudioStream(pending);
        _publicationsAwaitingDispose.remove(pending);
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Retry of shared-audio publication $pending disposal failed',
        );
      }
    }

    if (_sessionsAwaitingDispose.isEmpty) {
      return;
    }
    for (final pending in _sessionsAwaitingDispose.toList()) {
      try {
        await _binding.disposeSession(pending);
        _sessionsAwaitingDispose.remove(pending);
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Retry of shared-audio session $pending disposal failed',
        );
      }
    }
  }

  @override
  Future<SharedAudioCaptureStatus> refreshStatus() =>
      _serialized(_refreshStatusLocked);

  /// Serialized like everything else that reads [_sessions] across an await: a
  /// refresh racing a teardown would otherwise query a disposed id.
  Future<SharedAudioCaptureStatus> _refreshStatusLocked() async {
    final session = _sessions[_defaultSessionKey];
    if (session == null || !session.capturing) {
      return _lastStatus;
    }

    final status = await _binding.getSessionStatus(session.id);
    return _lastStatus = _statusFrom(
      status,
      mode: _lastStatus.mode,
      backend: session.backend,
    );
  }

  /// Maps a native status onto the platform-neutral observation.
  SharedAudioCaptureStatus _statusFrom(
    WindowsShareSessionStatus status, {
    required SharedAudioCaptureMode mode,
    required SharedAudioBackendKind backend,
  }) {
    final capturing = status.audioState == WindowsSharedAudioState.active;
    return SharedAudioCaptureStatus(
      mode: mode,
      backend: backend,
      state: _captureStateFrom(status.audioState),
      reason: capturing ? null : _reasonForStatus(status),
      // Verbatim, and kept even while capturing: the advisory matches on this
      // exact token, so normalising or blanking it is what would silently stop
      // the refusal advisory firing.
      nativeReason: status.reason,
      detail: capturing ? '' : status.reason,
      nativeErrorCode: _emptyToNull(status.lastHresult),
      failureStage: status.failureStage.name,
      sampleRateHz: status.sampleRateHz,
      numChannels: status.numChannels,
      bitsPerSample: status.bitsPerSample,
      packetsCaptured: status.packetsCaptured,
      framesCaptured: status.framesCaptured,
      bytesCaptured: status.bytesCaptured,
      nonsilentBytesCaptured: status.nonsilentBytesCaptured,
      targetNotCapturable: status.targetElevated,
      targetCapturabilityKnown: status.targetElevationKnown,
      canPublish: status.pcmBridgeSupported,
    );
  }

  SharedAudioCaptureState _captureStateFrom(WindowsSharedAudioState state) {
    return switch (state) {
      WindowsSharedAudioState.inactive => SharedAudioCaptureState.disabled,
      WindowsSharedAudioState.starting => SharedAudioCaptureState.starting,
      WindowsSharedAudioState.active => SharedAudioCaptureState.active,
      WindowsSharedAudioState.unavailable =>
        SharedAudioCaptureState.unavailable,
      WindowsSharedAudioState.failed => SharedAudioCaptureState.failed,
      WindowsSharedAudioState.stopped => SharedAudioCaptureState.stopped,
    };
  }

  @override
  Future<MediaStream?> createPublicationStream() =>
      _serialized(_createPublicationStreamLocked);

  /// Serialized with [start]/[stop]/[dispose] because it reads [_sessions]
  /// across an await. Without the gate a publication could be opened against a
  /// session that a concurrent stop or supersede is already tearing down, which
  /// is the orphan this whole handle exists to prevent.
  Future<MediaStream?> _createPublicationStreamLocked() async {
    final session = _sessions[_defaultSessionKey];
    if (session == null || !session.capturing) {
      return null;
    }

    if (session.publicationIssued) {
      return session.publicationStream;
    }

    // Parity with the path this replaces, which refuses to publish without the
    // PCM bridge. The native layer refuses too, so this changes no outcome - it
    // just stops us asking for a stream the machine has already said it cannot
    // build.
    if (!session.pcmBridgeSupported) {
      return null;
    }

    final streamInfo = await _binding.createSharedAudioStream(session.id);
    if (!streamInfo.supported) {
      Log.w(
        'Windows shared-audio publication unavailable for session '
        '${session.id}: ${streamInfo.reason}; continuing video-only.',
      );
      return null;
    }

    // Marked before the mapping, not after: the native stream exists from here
    // on regardless of what the mapping yields, and it is the native side that
    // has to be released.
    session.publicationIssued = true;

    // Re-read rather than trusting the captured local: the await above is a
    // suspension point, and a superseding start could have replaced the session
    // while the native call was in flight. Publishing the new session's stream
    // under the old session's handle would attach the capture to the wrong one.
    final current = _sessions[_defaultSessionKey];
    if (!identical(current, session)) {
      await _disposeNativePublication(session);
      return null;
    }

    session.publicationStream = windowsSharedAudioStreamInfoToMediaStream(
      streamInfo,
    );
    return session.publicationStream;
  }

  @override
  Future<void> disposePublicationStream() => _serialized(
    () => _disposePublicationLocked(_sessions[_defaultSessionKey]),
  );

  /// The session argument is read inside the gate, not at call time.
  ///
  /// This reads like an eager capture and is not one: [_serialized] invokes the
  /// closure from inside its queued `.then`, so the lookup is evaluated after
  /// every earlier lifecycle operation has settled - the same instant every
  /// `*Locked` body reads the field directly. A disposal queued behind a
  /// pending `start()` therefore sees the session that start created, which is
  /// what `a publication disposal queued behind a start releases the new
  /// session` pins.
  Future<void> _disposePublicationLocked(_SharedAudioSession? session) async {
    if (session == null || !session.publicationIssued) {
      return;
    }
    await _disposeNativePublication(session);
  }

  /// Publications the native side still holds because a release attempt failed.
  ///
  /// The same hazard [_sessionsAwaitingDispose] exists for, one level down.
  /// [_disposeNativePublication] clears `publicationIssued` before it awaits,
  /// so a throw used to leave the native stream alive with nothing recording
  /// that it existed: the flag said there was nothing to release, and no later
  /// teardown could retry it.
  final Set<int> _publicationsAwaitingDispose = <int>{};

  /// Releases the native publication for [session] and clears its handles.
  ///
  /// Errors are logged rather than thrown: every caller is either tearing the
  /// session down anyway or reporting a more specific failure, and letting a
  /// publication-teardown error escape would replace that diagnosis. The id is
  /// retained for retry instead, so the leak is neither permanent nor invisible.
  Future<void> _disposeNativePublication(_SharedAudioSession session) async {
    session.publicationStream = null;
    session.publicationIssued = false;
    try {
      await _binding.disposeSharedAudioStream(session.id);
      _publicationsAwaitingDispose.remove(session.id);
    } catch (error, stackTrace) {
      _publicationsAwaitingDispose.add(session.id);
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to dispose shared-audio publication for session '
            '${session.id}; retained for retry on a later dispose',
      );
    }
  }

  @override
  Future<void> stop() => _serialized(_stopLocked);

  Future<void> _stopLocked() async {
    final session = _sessions[_defaultSessionKey];
    if (session == null || !session.capturing) {
      return;
    }
    // Cleared as the "still capturing" flag the guard above reads, so a second
    // stop() no longer re-issues stopSharedAudio against a capture that has
    // already ended. The session itself deliberately survives: dispose() still
    // has to release it. (`kind` is unaffected either way — it falls back to
    // this platform's default backend when nothing is capturing.)
    session.capturing = false;
    session.stopIssued = true;
    _lastStatus = _lastStatus.asStopped();
    await _binding.stopSharedAudio(session.id);
  }

  @override
  Future<void> dispose() => _serialized(_disposeLocked);

  Future<void> _disposeLocked() async {
    // Earlier failed releases first, and unconditionally: they are the whole
    // reason those ids were kept, and there may be no owned session below.
    await _drainPendingDisposals();
    await _releaseAllSessions(reportFailure: true);
  }

  SharedAudioCapabilityReport _unavailableReport(
    SharedAudioUnavailableReason reason,
    String detail,
  ) {
    return SharedAudioCapabilityReport(
      platform: platform,
      backend: SharedAudioBackendKind.none,
      modes: [
        for (final mode in const [
          SharedAudioCaptureMode.selectedApplication,
          SharedAudioCaptureMode.desktopAudio,
          SharedAudioCaptureMode.selectedDevice,
        ])
          SharedAudioModeAvailability.unavailable(
            mode: mode,
            reason: reason,
            detail: detail,
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
}

/// One native capture session, owned by exactly one entry of one field.
///
/// This type exists so that "a session" is something that can be owned rather
/// than a set of loose fields kept consistent by hand.
/// [WindowsSharedAudioBackend._sessions] is the only field that holds them,
/// [WindowsSharedAudioBackend._openSession] the only place one is made, and
/// [WindowsSharedAudioBackend._releaseSession] the only way out of it - so a
/// session nothing can tear down is not a state this class can reach, instead
/// of a mistake every exit path has to individually avoid.
class _SharedAudioSession {
  _SharedAudioSession({required this.id, required this.backend});

  /// Native session id, always positive: [WindowsSharedAudioBackend._openSession]
  /// treats anything else as "no session was created".
  final int id;

  /// Backend kind this session runs on. Fixed at creation, because the resolved
  /// mode is what the native session was created for.
  final SharedAudioBackendKind backend;

  /// True only while the native capture is running. Set by a successful start,
  /// cleared by [WindowsSharedAudioBackend.stop] and by release. The session
  /// deliberately outlives it: a stopped capture still has to be disposed.
  bool capturing = false;

  /// Whether the native PCM bridge was available when this capture came up.
  ///
  /// Recorded on the session rather than re-queried at publish time so the
  /// answer cannot drift between starting a capture and publishing it.
  bool pcmBridgeSupported = false;

  /// The publication stream opened for this session, if any.
  ///
  /// Held on the session rather than on the backend for the same reason the
  /// session id is: a stream that outlives its native session publishes a
  /// disposed capture. Making it a field of the session means releasing the
  /// session is the only thing that has to remember to release the stream.
  MediaStream? publicationStream;

  /// Whether `disposeSharedAudioStream` still needs to be issued for this id.
  ///
  /// Distinct from `publicationStream != null` because the native stream can
  /// exist while the Dart-side mapping produced nothing: on web-stub builds
  /// [windowsSharedAudioStreamInfoToMediaStream] returns null even though the
  /// native side created and now owns a stream. Keying the teardown on the Dart
  /// object would leak exactly those.
  bool publicationIssued = false;

  /// Whether `stopSharedAudio` has already been issued for this id.
  ///
  /// This is NOT the same question as [capturing], and the difference is the
  /// whole reason it exists. A start that fails after `createSession` never
  /// sets [capturing], yet its session still has to be stopped and disposed —
  /// so gating the release-path stop on [capturing] would skip it and reopen
  /// the leak this handle exists to close.
  ///
  /// Tracking the stop itself is what makes the duplicate avoidable without
  /// that regression: release issues a stop only when nothing has stopped this
  /// session yet.
  bool stopIssued = false;
}

class _ResolvedWindowsMode {
  const _ResolvedWindowsMode(this.nativeMode, this.backend);

  final WindowsSharedAudioMode nativeMode;
  final SharedAudioBackendKind backend;
}

String? _emptyToNull(String value) => value.isEmpty ? null : value;
