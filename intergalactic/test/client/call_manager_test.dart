import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/voip/mobile_call_background_controller.dart';
import 'package:intergalactic/client/components/voip/share_session/share_session.dart';
import 'package:intergalactic/client/components/voip/voip_call_diagnostics.dart';
import 'package:intergalactic/client/components/voip/voip_component.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/client/stale_info.dart';
import 'package:intergalactic/config/app_globals.dart' as globals;
import 'package:intergalactic/utils/system_wide_shortcuts/system_wide_shortcuts.dart';
import 'package:intergalactic/utils/stored_stream_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('CallManager lifecycle cleanup', () {
    test(
      'cancels session listeners when a session reaches ended state',
      () async {
        final manager = ClientManager();
        manager.callManager.disableSoundEffectsForTesting = true;
        addTearDown(manager.close);
        final client = _FakeClient(identifier: 'client-a');
        manager.addClient(client);
        await Future<void>.delayed(Duration.zero);

        final session = _FakeVoipSession(
          client: client,
          sessionId: 'session-a',
        );
        final started = expectLater(
          manager.callManager.onSessionStarted,
          emits(session),
        );
        client.voip.emitSessionStarted(session);
        await started;
        await Future<void>.delayed(Duration.zero);

        expect(manager.callManager.currentSessions, [session]);

        session.emitState(VoipState.ended);
        await Future<void>.delayed(Duration.zero);

        expect(manager.callManager.currentSessions, isEmpty);
        expect(session.stateListenerCancelCount, 1);
      },
    );

    test(
      'client removal cancels VoIP listeners and drops tracked sessions',
      () async {
        final manager = ClientManager();
        manager.callManager.disableSoundEffectsForTesting = true;
        addTearDown(manager.close);
        final client = _FakeClient(identifier: 'client-a')
          ..self = const _FakeProfile(identifier: '@alice:example.test');
        manager.addClient(client);
        await Future<void>.delayed(Duration.zero);

        final session = _FakeVoipSession(
          client: client,
          sessionId: 'session-a',
        );
        client.voip.emitSessionStarted(session);
        await Future<void>.delayed(Duration.zero);

        manager.onClientRemoved.add(
          StalePeerInfo(
            index: 0,
            identifier: client.self!.identifier,
            localClientId: client.identifier,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(manager.callManager.currentSessions, isEmpty);
        expect(client.voip.startedListenerCancelCount, 1);
        expect(client.voip.endedListenerCancelCount, 1);
        expect(session.stateListenerCancelCount, 1);
      },
    );

    test(
      'recovers client and session subscription cancellation failures',
      () async {
        final manager = ClientManager();
        manager.callManager.disableSoundEffectsForTesting = true;
        addTearDown(manager.close);
        final client = _FakeClient(
          identifier: 'client-a',
          failVoipSubscriptionCancel: true,
        );
        manager.addClient(client);
        await Future<void>.delayed(Duration.zero);

        final session = _FakeVoipSession(
          client: client,
          sessionId: 'session-a',
          failStateListenerCancel: true,
        );
        client.voip.emitSessionStarted(session);
        await Future<void>.delayed(Duration.zero);

        await expectLater(manager.callManager.dispose(), completes);

        expect(client.voip.startedListenerCancelCount, 1);
        expect(client.voip.endedListenerCancelCount, 1);
        expect(session.stateListenerCancelCount, 1);
      },
    );

    test(
      'syncs mobile call background retention with active sessions',
      () async {
        final manager = ClientManager();
        final backgroundPlatform = _FakeMobileCallBackgroundPlatform();
        manager.callManager
          ..disableSoundEffectsForTesting = true
          ..mobileCallBackgroundController = MobileCallBackgroundController(
            platform: backgroundPlatform,
          );
        addTearDown(manager.close);
        final client = _FakeClient(identifier: 'client-a');
        manager.addClient(client);
        await Future<void>.delayed(Duration.zero);

        final session = _FakeVoipSession(
          client: client,
          sessionId: 'session-a',
          state: VoipState.connected,
          isMicrophoneMuted: false,
          isCameraEnabled: true,
        );
        client.voip.emitSessionStarted(session);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(backgroundPlatform.requests, hasLength(1));
        expect(backgroundPlatform.requests.single.active, isTrue);
        expect(backgroundPlatform.requests.single.roomName, 'Room');
        expect(backgroundPlatform.requests.single.usesMicrophone, isTrue);
        expect(backgroundPlatform.requests.single.usesCamera, isTrue);

        session.emitState(VoipState.ended);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(backgroundPlatform.requests, hasLength(2));
        expect(backgroundPlatform.requests.last.active, isFalse);
      },
    );

    test('recovers when push-to-talk mute operations fail', () async {
      SharedPreferences.setMockInitialValues({
        'voip_push_to_talk_enabled': false,
      });
      await globals.preferences.init();
      final previousPushToTalk =
          globals.preferences.voipPushToTalkEnabled.value;
      addTearDown(
        () => globals.preferences.voipPushToTalkEnabled.set(previousPushToTalk),
      );
      await globals.preferences.voipPushToTalkEnabled.set(true);
      final pushToTalkShortcut = SystemWideShortcuts
          .shortcuts[SystemWideShortcuts.pushToTalkShortcutKey]!;
      final previousPushToTalkHotkey = pushToTalkShortcut.hotkey;
      pushToTalkShortcut.hotkey = _testPushToTalkHotkey();
      addTearDown(() {
        pushToTalkShortcut.hotkey = previousPushToTalkHotkey;
      });

      final manager = ClientManager();
      manager.callManager.disableSoundEffectsForTesting = true;
      addTearDown(manager.close);
      final client = _FakeClient(identifier: 'client-a');
      manager.addClient(client);
      await Future<void>.delayed(Duration.zero);

      final session = _FakeVoipSession(
        client: client,
        sessionId: 'session-a',
        state: VoipState.connected,
        microphoneMuteError: StateError('test mute failure'),
      );
      client.voip.emitSessionStarted(session);
      await Future<void>.delayed(Duration.zero);

      manager.callManager.pushToTalkStart();
      manager.callManager.pushToTalkEnd();
      manager.callManager.applyPushToTalkPreference();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        session.microphoneMuteRequests,
        orderedEquals([true, false, true]),
      );
      expect(
        session.microphoneStopOnMuteRequests,
        orderedEquals([false, false, false]),
      );
    });

    test('recovers when manual mute operations fail', () async {
      final manager = ClientManager();
      manager.callManager.disableSoundEffectsForTesting = true;
      addTearDown(manager.close);
      final client = _FakeClient(identifier: 'client-a');
      manager.addClient(client);
      await Future<void>.delayed(Duration.zero);

      final session = _FakeVoipSession(
        client: client,
        sessionId: 'session-a',
        state: VoipState.connected,
        microphoneMuteError: StateError('test mute failure'),
      );
      client.voip.emitSessionStarted(session);
      await Future<void>.delayed(Duration.zero);

      manager.callManager.mute();
      manager.callManager.unmute();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(session.microphoneMuteRequests, orderedEquals([true, false]));
      expect(session.microphoneStopOnMuteRequests, orderedEquals([true, true]));
    });

    test(
      'a per-session mute uses the same intent map and coalescing drain',
      () async {
        // The call controls and the mini call menu used to call
        // `session.setMicrophoneMute` directly, which bypassed both. Two
        // consequences this covers: rapid presses coalesce instead of
        // interleaving, and the future returned by the request that STARTS the
        // drain completes only once that drain settles.
        //
        // The second `setMicrophoneMuteForSession` below is awaited directly
        // and cannot deadlock on `firstMuteDelay`: a request that lands while
        // a drain is in flight records its intent and returns an
        // already-completed future rather than joining the running drain
        // (`call_manager.dart` `_setMicrophoneMuteForManualAction`). That
        // asymmetry is the contract - see the doc on
        // `setMicrophoneMuteForSession` - and it is what the assertion
        // immediately after the await pins.
        final manager = ClientManager();
        manager.callManager.disableSoundEffectsForTesting = true;
        addTearDown(manager.close);
        final client = _FakeClient(identifier: 'client-a');
        manager.addClient(client);
        await Future<void>.delayed(Duration.zero);

        final firstMuteDelay = Completer<void>();
        final session = _FakeVoipSession(
          client: client,
          sessionId: 'session-a',
          state: VoipState.connected,
          microphoneMuteDelays: [firstMuteDelay],
        );
        client.voip.emitSessionStarted(session);
        await Future<void>.delayed(Duration.zero);

        var firstCompleted = false;
        final first = manager.callManager
            .setMicrophoneMuteForSession(session, true)
            .then((_) => firstCompleted = true);
        await Future<void>.delayed(Duration.zero);

        expect(session.microphoneMuteRequests, orderedEquals([true]));
        expect(firstCompleted, isFalse);

        // Lands while the first apply is still in flight: the drain picks the
        // value up rather than issuing a second overlapping write.
        await manager.callManager.setMicrophoneMuteForSession(session, false);
        expect(session.microphoneMuteRequests, orderedEquals([true]));

        firstMuteDelay.complete();
        await first;

        expect(firstCompleted, isTrue);
        expect(session.microphoneMuteRequests, orderedEquals([true, false]));
      },
    );

    test(
      'the effective mute state reports pending intent, not applied state',
      () async {
        // What a mute BUTTON must toggle away from. While the drain is
        // applying a request the session still reports the old applied state,
        // so a surface computing `!session.isMicrophoneMuted` on a fast second
        // press asks for the value already queued - the manager absorbs it as
        // a duplicate and the press does nothing. `CallView` and
        // `MiniCallMenu` both read this instead.
        final manager = ClientManager();
        manager.callManager.disableSoundEffectsForTesting = true;
        addTearDown(manager.close);
        final client = _FakeClient(identifier: 'client-a');
        manager.addClient(client);
        await Future<void>.delayed(Duration.zero);

        final muteDelay = Completer<void>();
        final session = _FakeVoipSession(
          client: client,
          sessionId: 'session-a',
          state: VoipState.connected,
          microphoneMuteDelays: [muteDelay],
        );
        client.voip.emitSessionStarted(session);
        await Future<void>.delayed(Duration.zero);

        expect(
          manager.callManager.effectiveManualMuteState(session),
          isFalse,
          reason: 'with nothing in flight it falls back to the session',
        );

        final first = manager.callManager.setMicrophoneMuteForSession(
          session,
          true,
        );
        await Future<void>.delayed(Duration.zero);

        expect(
          session.isMicrophoneMuted,
          isFalse,
          reason: 'the apply has not landed yet',
        );
        expect(
          manager.callManager.effectiveManualMuteState(session),
          isTrue,
          reason: 'the pending request is what a second press must invert',
        );

        muteDelay.complete();
        await first;

        expect(manager.callManager.effectiveManualMuteState(session), isTrue);
        expect(session.microphoneMuteRequests, orderedEquals([true]));
      },
    );

    test(
      'manual mute drains to latest requested state when toggled quickly',
      () async {
        final manager = ClientManager();
        manager.callManager.disableSoundEffectsForTesting = true;
        addTearDown(manager.close);
        final client = _FakeClient(identifier: 'client-a');
        manager.addClient(client);
        await Future<void>.delayed(Duration.zero);

        final firstMuteDelay = Completer<void>();
        final session = _FakeVoipSession(
          client: client,
          sessionId: 'session-a',
          state: VoipState.connected,
          microphoneMuteDelays: [firstMuteDelay],
        );
        client.voip.emitSessionStarted(session);
        await Future<void>.delayed(Duration.zero);

        manager.callManager.mute();
        await Future<void>.delayed(Duration.zero);

        expect(session.microphoneMuteRequests, orderedEquals([true]));
        expect(session.isMicrophoneMuted, isFalse);

        manager.callManager.toggleMute();
        await Future<void>.delayed(Duration.zero);

        expect(session.microphoneMuteRequests, orderedEquals([true]));

        firstMuteDelay.complete();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(session.microphoneMuteRequests, orderedEquals([true, false]));
        expect(
          session.microphoneStopOnMuteRequests,
          orderedEquals([true, true]),
        );
        expect(session.isMicrophoneMuted, isFalse);
      },
    );

    test(
      'push-to-talk enabled without saved hotkey uses default hotkey',
      () async {
        SharedPreferences.setMockInitialValues({
          'voip_push_to_talk_enabled': false,
        });
        await globals.preferences.init();
        final previousPushToTalk =
            globals.preferences.voipPushToTalkEnabled.value;
        addTearDown(
          () =>
              globals.preferences.voipPushToTalkEnabled.set(previousPushToTalk),
        );
        await globals.preferences.voipPushToTalkEnabled.set(true);
        final pushToTalkShortcut = SystemWideShortcuts
            .shortcuts[SystemWideShortcuts.pushToTalkShortcutKey]!;
        final previousPushToTalkHotkey = pushToTalkShortcut.hotkey;
        pushToTalkShortcut.hotkey = null;
        addTearDown(() {
          pushToTalkShortcut.hotkey = previousPushToTalkHotkey;
        });

        final manager = ClientManager();
        manager.callManager.disableSoundEffectsForTesting = true;
        addTearDown(manager.close);
        final client = _FakeClient(identifier: 'client-a');
        manager.addClient(client);
        await Future<void>.delayed(Duration.zero);

        final session = _FakeVoipSession(
          client: client,
          sessionId: 'session-a',
          state: VoipState.connected,
        );
        client.voip.emitSessionStarted(session);
        await Future<void>.delayed(Duration.zero);

        manager.callManager.pushToTalkStart();
        manager.callManager.pushToTalkEnd();
        manager.callManager.applyPushToTalkPreference();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(
          session.microphoneMuteRequests,
          orderedEquals([true, false, true]),
        );
        expect(
          session.microphoneStopOnMuteRequests,
          orderedEquals([false, false, false]),
        );
      },
    );

    test(
      'push-to-talk releases applied mute when hotkey becomes unavailable',
      () async {
        SharedPreferences.setMockInitialValues({
          'voip_push_to_talk_enabled': false,
        });
        await globals.preferences.init();
        final previousPushToTalk =
            globals.preferences.voipPushToTalkEnabled.value;
        addTearDown(
          () =>
              globals.preferences.voipPushToTalkEnabled.set(previousPushToTalk),
        );
        await globals.preferences.voipPushToTalkEnabled.set(true);

        const shortcutKey = SystemWideShortcuts.pushToTalkShortcutKey;
        final pushToTalkShortcut = SystemWideShortcuts.shortcuts[shortcutKey]!;
        final previousPushToTalkHotkey = pushToTalkShortcut.hotkey;
        addTearDown(() {
          SystemWideShortcuts.shortcuts[shortcutKey] = pushToTalkShortcut;
          pushToTalkShortcut.hotkey = previousPushToTalkHotkey;
        });
        pushToTalkShortcut.hotkey = _testPushToTalkHotkey();

        final manager = ClientManager();
        manager.callManager.disableSoundEffectsForTesting = true;
        addTearDown(manager.close);
        final client = _FakeClient(identifier: 'client-a');
        manager.addClient(client);
        await Future<void>.delayed(Duration.zero);

        final session = _FakeVoipSession(
          client: client,
          sessionId: 'session-a',
          state: VoipState.connected,
        );
        client.voip.emitSessionStarted(session);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(session.microphoneMuteRequests, orderedEquals([true]));

        SystemWideShortcuts.shortcuts.remove(shortcutKey);
        manager.callManager.applyPushToTalkPreference();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(session.microphoneMuteRequests, orderedEquals([true, false]));
        expect(
          session.microphoneStopOnMuteRequests,
          orderedEquals([false, false]),
        );
      },
    );

    test(
      'push-to-talk releases a partially applied mute after failure',
      () async {
        SharedPreferences.setMockInitialValues({
          'voip_push_to_talk_enabled': false,
        });
        await globals.preferences.init();
        final previousPushToTalk =
            globals.preferences.voipPushToTalkEnabled.value;
        addTearDown(
          () =>
              globals.preferences.voipPushToTalkEnabled.set(previousPushToTalk),
        );
        await globals.preferences.voipPushToTalkEnabled.set(true);

        const shortcutKey = SystemWideShortcuts.pushToTalkShortcutKey;
        final pushToTalkShortcut = SystemWideShortcuts.shortcuts[shortcutKey]!;
        final previousPushToTalkHotkey = pushToTalkShortcut.hotkey;
        addTearDown(() {
          SystemWideShortcuts.shortcuts[shortcutKey] = pushToTalkShortcut;
          pushToTalkShortcut.hotkey = previousPushToTalkHotkey;
        });
        pushToTalkShortcut.hotkey = _testPushToTalkHotkey();

        final manager = ClientManager();
        manager.callManager.disableSoundEffectsForTesting = true;
        addTearDown(manager.close);
        final client = _FakeClient(identifier: 'client-a');
        manager.addClient(client);
        await Future<void>.delayed(Duration.zero);

        final session = _FakeVoipSession(
          client: client,
          sessionId: 'session-a',
          state: VoipState.connected,
          microphoneMuteError: StateError('test partial mute failure'),
          microphoneMuteErrorStates: const {true},
          applyMicrophoneMuteBeforeError: true,
        );
        client.voip.emitSessionStarted(session);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(session.microphoneMuteRequests, orderedEquals([true]));
        expect(session.isMicrophoneMuted, isTrue);

        SystemWideShortcuts.shortcuts.remove(shortcutKey);
        manager.callManager.applyPushToTalkPreference();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(session.microphoneMuteRequests, orderedEquals([true, false]));
        expect(
          session.microphoneStopOnMuteRequests,
          orderedEquals([false, false]),
        );
        expect(session.isMicrophoneMuted, isFalse);
      },
    );

    test(
      'push-to-talk ignores state changes caused by its own mute apply',
      () async {
        SharedPreferences.setMockInitialValues({
          'voip_push_to_talk_enabled': false,
        });
        await globals.preferences.init();
        final previousPushToTalk =
            globals.preferences.voipPushToTalkEnabled.value;
        addTearDown(
          () =>
              globals.preferences.voipPushToTalkEnabled.set(previousPushToTalk),
        );
        await globals.preferences.voipPushToTalkEnabled.set(true);
        final pushToTalkShortcut = SystemWideShortcuts
            .shortcuts[SystemWideShortcuts.pushToTalkShortcutKey]!;
        final previousPushToTalkHotkey = pushToTalkShortcut.hotkey;
        pushToTalkShortcut.hotkey = _testPushToTalkHotkey();
        addTearDown(() {
          pushToTalkShortcut.hotkey = previousPushToTalkHotkey;
        });

        final manager = ClientManager();
        manager.callManager.disableSoundEffectsForTesting = true;
        addTearDown(manager.close);
        final client = _FakeClient(identifier: 'client-a');
        manager.addClient(client);
        await Future<void>.delayed(Duration.zero);

        final session = _FakeVoipSession(
          client: client,
          sessionId: 'session-a',
          state: VoipState.connected,
          emitStateChangeAfterMicrophoneMute: true,
        );
        client.voip.emitSessionStarted(session);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(session.microphoneMuteRequests, orderedEquals([true]));
        expect(session.microphoneStopOnMuteRequests, orderedEquals([false]));
      },
    );

    test('emits deafen changes while active', () async {
      final manager = ClientManager();
      manager.callManager.disableSoundEffectsForTesting = true;
      addTearDown(manager.close);

      final deafenChanged = expectLater(
        manager.callManager.onDeafenChanged,
        emits(true),
      );

      manager.callManager.setDeafened(true);

      await deafenChanged;
      expect(manager.callManager.isDeafened, isTrue);
    });

    test('ignores deafen changes after dispose closes controller', () async {
      final manager = ClientManager();
      manager.callManager.disableSoundEffectsForTesting = true;
      addTearDown(manager.close);

      await manager.callManager.dispose();

      expect(() => manager.callManager.setDeafened(true), returnsNormally);
      expect(manager.callManager.isDeafened, isFalse);
    });
  });
}

HotKey _testPushToTalkHotkey() {
  return HotKey(
    identifier: 'push-to-talk-test',
    key: PhysicalKeyboardKey.space,
    modifiers: const [],
  );
}

class _FakeProfile implements Profile {
  const _FakeProfile({required this.identifier});

  @override
  final String identifier;

  @override
  String get userName => identifier;

  @override
  String get displayName => identifier;

  @override
  String? get detail => null;

  @override
  ImageProvider? get avatar => null;

  @override
  ImageProvider? get banner => null;

  @override
  Color get defaultColor => Colors.blue;

  @override
  String get source => 'test';
}

class _FakeClient implements Client {
  _FakeClient({
    required this.identifier,
    bool failVoipSubscriptionCancel = false,
  }) {
    voip = _FakeVoipComponent(
      this,
      failSubscriptionCancel: failVoipSubscriptionCancel,
    );
  }

  @override
  final String identifier;

  @override
  Profile? self;

  late final _FakeVoipComponent voip;

  final _onSync = StreamController<void>.broadcast();
  final _onSelfUpdated = StreamController<void>.broadcast();
  final _onRoomAdded = StreamController<int>.broadcast();
  final _onRoomRemoved = StreamController<int>.broadcast();
  final _onSpaceAdded = StreamController<int>.broadcast();
  final _onSpaceRemoved = StreamController<int>.broadcast();
  bool _closed = false;

  @override
  final StoredStreamController<ClientConnectionStatusUpdate>
  connectionStatusChanged = StoredStreamController();

  @override
  List<Room> get rooms => const [];

  @override
  List<Space> get spaces => const [];

  @override
  Stream<void> get onSync => _onSync.stream;

  @override
  Stream<void> get onSelfUpdated => _onSelfUpdated.stream;

  @override
  Stream<int> get onRoomAdded => _onRoomAdded.stream;

  @override
  Stream<int> get onRoomRemoved => _onRoomRemoved.stream;

  @override
  Stream<int> get onSpaceAdded => _onSpaceAdded.stream;

  @override
  Stream<int> get onSpaceRemoved => _onSpaceRemoved.stream;

  @override
  Room? getRoom(String identifier) => null;

  @override
  T? getComponent<T extends Component>() {
    if (voip is T) {
      return voip as T;
    }
    return null;
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await Future.wait([
      _onSync.close(),
      _onSelfUpdated.close(),
      _onRoomAdded.close(),
      _onRoomRemoved.close(),
      _onSpaceAdded.close(),
      _onSpaceRemoved.close(),
      connectionStatusChanged.close(),
      voip.close(),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVoipComponent implements VoipComponent<_FakeClient> {
  _FakeVoipComponent(this.client, {this.failSubscriptionCancel = false});

  @override
  final _FakeClient client;

  final bool failSubscriptionCancel;
  int startedListenerCancelCount = 0;
  int endedListenerCancelCount = 0;

  final StreamController<VoipSession> _onSessionStarted =
      StreamController<VoipSession>.broadcast();
  final StreamController<VoipSession> _onSessionEnded =
      StreamController<VoipSession>.broadcast();

  late final Stream<VoipSession> _onSessionStartedStream = _TrackedCancelStream(
    _onSessionStarted.stream,
    onCancel: () {
      startedListenerCancelCount++;
      if (failSubscriptionCancel) {
        return StateError('started subscription cancel failed');
      }
      return null;
    },
  );
  late final Stream<VoipSession> _onSessionEndedStream = _TrackedCancelStream(
    _onSessionEnded.stream,
    onCancel: () {
      endedListenerCancelCount++;
      if (failSubscriptionCancel) {
        return StateError('ended subscription cancel failed');
      }
      return null;
    },
  );

  @override
  Stream<VoipSession> get onSessionStarted => _onSessionStartedStream;

  @override
  Stream<VoipSession> get onSessionEnded => _onSessionEndedStream;

  void emitSessionStarted(VoipSession session) {
    _onSessionStarted.add(session);
  }

  @override
  List<VoipSession> getSessionsInRoom(String roomId) => const [];

  @override
  Future<void> startCall(
    String roomId,
    CallType type, {
    String? userId,
  }) async {}

  @override
  bool canCallRoom(String roomId) => true;

  Future<void> close() async {
    await Future.wait([_onSessionStarted.close(), _onSessionEnded.close()]);
  }
}

class _FakeVoipSession implements VoipSession {
  _FakeVoipSession({
    required this.client,
    required this.sessionId,
    this.state = VoipState.unknown,
    bool isMicrophoneMuted = false,
    this.isCameraEnabled = false,
    this.microphoneMuteError,
    this.microphoneMuteErrorStates = const <bool>{},
    this.applyMicrophoneMuteBeforeError = false,
    this.emitStateChangeAfterMicrophoneMute = false,
    this.failStateListenerCancel = false,
    List<Completer<void>>? microphoneMuteDelays,
  }) : _isMicrophoneMuted = isMicrophoneMuted,
       _microphoneMuteDelays = microphoneMuteDelays ?? <Completer<void>>[];

  @override
  final _FakeClient client;

  @override
  final String sessionId;

  @override
  VoipState state;

  @override
  bool get isMicrophoneMuted => _isMicrophoneMuted;

  @override
  final bool isCameraEnabled;

  bool _isMicrophoneMuted;
  final Object? microphoneMuteError;
  final Set<bool> microphoneMuteErrorStates;
  final bool applyMicrophoneMuteBeforeError;
  final bool emitStateChangeAfterMicrophoneMute;
  final bool failStateListenerCancel;
  final List<Completer<void>> _microphoneMuteDelays;
  final List<bool> microphoneMuteRequests = [];
  final List<bool> microphoneStopOnMuteRequests = [];

  int stateListenerCancelCount = 0;

  final StreamController<void> _onStateChanged =
      StreamController<void>.broadcast();
  late final Stream<void> _onStateChangedStream = _TrackedCancelStream(
    _onStateChanged.stream,
    onCancel: () {
      stateListenerCancelCount++;
      if (failStateListenerCancel) {
        return StateError('session state subscription cancel failed');
      }
      return null;
    },
  );

  void emitState(VoipState nextState) {
    state = nextState;
    _onStateChanged.add(null);
  }

  @override
  String get roomId => '!room:example.test';

  @override
  String? get remoteUserId => '@remote:example.test';

  @override
  String? get remoteUserName => 'Remote';

  @override
  String get roomName => 'Room';

  @override
  bool get supportsScreenshare => false;

  @override
  bool get isSharingScreen => false;

  @override
  ShareSession? get currentShareSession => null;

  @override
  double get generalAudioLevel => 0;

  @override
  VoipStream? get remoteUserMediaStream => null;

  @override
  List<VoipStream> get streams => const [];

  @override
  Future<void> acceptCall({
    bool withMicrophone = false,
    bool withCamera = false,
  }) async {}

  @override
  Future<void> declineCall() async {}

  @override
  Future<void> hangUpCall() async {}

  @override
  Stream<VoipState> get onConnectionStateChanged =>
      const Stream<VoipState>.empty();

  @override
  Stream<void> get onStateChanged => _onStateChangedStream;

  @override
  Stream<void> get onUpdateVolumeVisualizers => const Stream<void>.empty();

  @override
  VoipCallDiagnosticsSnapshot get diagnosticsSnapshot =>
      throw UnimplementedError();

  @override
  Stream<void> get onDiagnosticsChanged => const Stream<void>.empty();

  @override
  Future<void> setMicrophoneMute(bool state, {bool stopOnMute = true}) async {
    microphoneMuteRequests.add(state);
    microphoneStopOnMuteRequests.add(stopOnMute);
    if (_microphoneMuteDelays.isNotEmpty) {
      await _microphoneMuteDelays.removeAt(0).future;
    }
    final error = microphoneMuteError;
    final shouldThrow =
        error != null &&
        (microphoneMuteErrorStates.isEmpty ||
            microphoneMuteErrorStates.contains(state));
    if (shouldThrow && applyMicrophoneMuteBeforeError) {
      _isMicrophoneMuted = state;
    }
    if (shouldThrow) {
      throw error;
    }
    _isMicrophoneMuted = state;
    if (emitStateChangeAfterMicrophoneMute) {
      _onStateChanged.add(null);
    }
  }

  @override
  Future<void> updateStats() async {}

  @override
  Future<ScreenCaptureSource?> pickScreenCapture(BuildContext context) async {
    return null;
  }

  @override
  Future<void> setScreenShare(ScreenCaptureSource source) async {}

  @override
  Future<void> stopScreenshare() async {}

  @override
  Future<void> setCamera(MediaDeviceInfo? device) async {}

  @override
  Future<void> stopCamera() async {}
}

class _MobileCallBackgroundRequest {
  const _MobileCallBackgroundRequest({
    required this.active,
    required this.roomName,
    required this.usesMicrophone,
    required this.usesCamera,
  });

  final bool active;
  final String? roomName;
  final bool usesMicrophone;
  final bool usesCamera;
}

class _FakeMobileCallBackgroundPlatform
    implements MobileCallBackgroundPlatform {
  final List<_MobileCallBackgroundRequest> requests = [];

  @override
  bool get isSupported => true;

  @override
  Future<void> setCallBackgroundActive({
    required bool active,
    String? roomName,
    required bool usesMicrophone,
    required bool usesCamera,
  }) async {
    requests.add(
      _MobileCallBackgroundRequest(
        active: active,
        roomName: roomName,
        usesMicrophone: usesMicrophone,
        usesCamera: usesCamera,
      ),
    );
  }
}

class _TrackedCancelStream<T> extends Stream<T> {
  const _TrackedCancelStream(this._inner, {required this.onCancel});

  final Stream<T> _inner;
  final Object? Function() onCancel;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _TrackedCancelSubscription<T>(
      _inner.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      ),
      onCancel: onCancel,
    );
  }
}

class _TrackedCancelSubscription<T> implements StreamSubscription<T> {
  _TrackedCancelSubscription(this._inner, {required this.onCancel});

  final StreamSubscription<T> _inner;
  final Object? Function() onCancel;

  @override
  Future<void> cancel() async {
    await _inner.cancel();
    final error = onCancel();
    if (error != null) {
      return Future<void>.error(error);
    }
  }

  @override
  Future<E> asFuture<E>([E? futureValue]) => _inner.asFuture(futureValue);

  @override
  bool get isPaused => _inner.isPaused;

  @override
  void onData(void Function(T data)? handleData) => _inner.onData(handleData);

  @override
  void onDone(void Function()? handleDone) => _inner.onDone(handleDone);

  @override
  void onError(Function? handleError) => _inner.onError(handleError);

  @override
  void pause([Future<void>? resumeSignal]) => _inner.pause(resumeSignal);

  @override
  void resume() => _inner.resume();
}
