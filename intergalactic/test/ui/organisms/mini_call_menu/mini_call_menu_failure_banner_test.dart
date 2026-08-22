import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/ui/organisms/mini_call_menu/mini_call_menu.dart';

void main() {
  testWidgets('a failed control renders its failure inline in the menu', (
    tester,
  ) async {
    // There is no Scaffold anywhere on the main navigation path, so a
    // SnackBar posted from this menu queues on the root messenger and never
    // draws. The failure must therefore appear in the menu itself - this test
    // fails against the old ScaffoldMessenger implementation.
    final session = _FakeVoipSession();

    await tester.pumpWidget(MaterialApp(home: MiniCallMenu(session)));

    await tester.tap(find.byIcon(Icons.call_end));
    await tester.pump();

    expect(
      find.text('Could not leave the call. Please try again.'),
      findsOneWidget,
    );

    await session.dispose();
  });

  testWidgets('the failure banner clears itself after four seconds', (
    tester,
  ) async {
    final session = _FakeVoipSession();

    await tester.pumpWidget(MaterialApp(home: MiniCallMenu(session)));

    await tester.tap(find.byIcon(Icons.call_end));
    await tester.pump();
    expect(
      find.text('Could not leave the call. Please try again.'),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 4));
    expect(
      find.text('Could not leave the call. Please try again.'),
      findsNothing,
    );

    await session.dispose();
  });

  testWidgets('a retry retires the previous failure banner immediately', (
    tester,
  ) async {
    final session = _FakeVoipSession();

    await tester.pumpWidget(MaterialApp(home: MiniCallMenu(session)));

    await tester.tap(find.byIcon(Icons.call_end));
    await tester.pump();
    expect(
      find.text('Could not leave the call. Please try again.'),
      findsOneWidget,
    );

    // The second attempt succeeds; the stale banner must not outlive it.
    session.failHangUp = false;
    await tester.tap(find.byIcon(Icons.call_end));
    await tester.pump();
    expect(
      find.text('Could not leave the call. Please try again.'),
      findsNothing,
    );

    await session.dispose();
  });

  sessionSwapTests();
}

// Appended tests use the same State across a session swap, which is exactly
// what the sidebar overlay produces: MiniCallMenu sits at a stable slot, so
// reconciliation reuses the State and only didUpdateWidget runs.
void sessionSwapTests() {
  testWidgets('a failure from a swapped-out session is not painted', (
    tester,
  ) async {
    final sessionA = _FakeVoipSession()..hangUpGate = Completer<void>();
    final sessionB = _FakeVoipSession();

    await tester.pumpWidget(MaterialApp(home: MiniCallMenu(sessionA)));
    await tester.tap(find.byIcon(Icons.call_end));
    await tester.pump();

    // Swap while A's hang-up is still in flight.
    await tester.pumpWidget(MaterialApp(home: MiniCallMenu(sessionB)));

    sessionA.hangUpGate!.completeError(StateError('hang up failed'));
    await tester.pump();
    await tester.pump();

    // B's menu must not wear A's failure. Removing the issuedFor guard in
    // _runControlAction fails this expectation.
    expect(
      find.text('Could not leave the call. Please try again.'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);

    await sessionA.dispose();
    await sessionB.dispose();
  });
}

class _FakeVoipSession implements VoipSession {
  final StreamController<void> _stateChanged =
      StreamController<void>.broadcast();
  bool failHangUp = true;

  Future<void> dispose() => _stateChanged.close();

  // One stable instance: _resolveRoom compares client identity across reads,
  // and a fresh fake per read would fail through noSuchMethod instead of an
  // assertion if that comparison is ever reached.
  final Client _client = _FakeClient();

  @override
  Client get client => _client;

  @override
  String get roomId => '!room:example.org';

  @override
  String get roomName => 'Test Voice';

  @override
  String? get remoteUserName => 'Alice';

  @override
  VoipState get state => VoipState.connected;

  @override
  bool get isMicrophoneMuted => false;

  @override
  Stream<void> get onStateChanged => _stateChanged.stream;

  /// When set, [hangUpCall] returns this future instead of settling
  /// immediately, so a test can hold the action in flight across a session
  /// swap and choose when (and how) it settles.
  Completer<void>? hangUpGate;

  @override
  Future<void> hangUpCall() {
    final gate = hangUpGate;
    if (gate != null) {
      return gate.future;
    }
    if (failHangUp) {
      return Future<void>.error(StateError('hang up failed'));
    }
    return Future<void>.value();
  }

  @override
  Future<void> setMicrophoneMute(bool state, {bool stopOnMute = true}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient implements Client {
  @override
  Room? getRoom(String identifier) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
