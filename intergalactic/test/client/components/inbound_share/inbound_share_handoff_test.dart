import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_controller.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_handoff.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_manifest.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_payload.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('chat.intergalactic.app/inbound_share');
  const token = 'a1b2c3d4e5f60718';
  late List<MethodCall> calls;
  Object? Function(MethodCall)? responder;

  setUp(() {
    calls = [];
    responder = (_) => true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return responder!(call);
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('MethodChannelInboundShareHandoff', () {
    const handoff = MethodChannelInboundShareHandoff(channel);

    test('acknowledge sends the token on the documented method', () async {
      await handoff.acknowledge(token);
      expect(calls.single.method, 'acknowledgeInboundShare');
      expect(calls.single.arguments, token);
    });

    test('reject sends the token on the documented method', () async {
      await handoff.reject(token);
      expect(calls.single.method, 'rejectInboundShare');
      expect(calls.single.arguments, token);
    });

    test('an empty token is not sent', () async {
      await handoff.acknowledge('');
      await handoff.reject('');
      expect(calls, isEmpty);
    });

    test('a native false is tolerated, not thrown', () async {
      // Native returns false when its filesystem mutation failed and it has
      // deliberately retained the reservation. Nothing here should escalate.
      responder = (_) => false;
      await expectLater(handoff.acknowledge(token), completes);
      await expectLater(handoff.reject(token), completes);
    });

    test('a PlatformException does not propagate', () async {
      // The reservation lapsing is the recoverable outcome by design.
      responder = (_) => throw PlatformException(code: 'boom');
      await expectLater(handoff.acknowledge(token), completes);
      await expectLater(handoff.reject(token), completes);
    });

    test('a missing handler does not propagate', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await expectLater(handoff.acknowledge(token), completes);
    });
  });

  group(
    'settleInboundShareAdmission - the acknowledgement ordering contract',
    () {
      InboundShareSession session() => InboundShareSession(
        manifest: InboundShareManifest(
          token: token,
          sessionRoot: '/tmp/$token',
          createdAt: DateTime(2026),
        ),
        payload: const InboundSharePayload(items: []),
        state: InboundShareSessionState.reviewing,
      );

      test('an ADMITTED session is acknowledged', () async {
        final h = _RecordingHandoff();
        await settleInboundShareAdmission(
          admission: InboundShareAdmissionResult(
            InboundShareAdmission.active,
            session: session(),
          ),
          token: token,
          handoff: h,
        );
        expect(h.calls, ['ack:$token']);
      });

      test(
        'a QUEUED session is acknowledged - the lifecycle owns it',
        () async {
          final h = _RecordingHandoff();
          await settleInboundShareAdmission(
            admission: InboundShareAdmissionResult(
              InboundShareAdmission.queued,
              session: session(),
            ),
            token: token,
            handoff: h,
          );
          expect(h.calls, ['ack:$token']);
        },
      );

      test(
        'a REJECTED admission rejects, so staged bytes are removed',
        () async {
          final h = _RecordingHandoff();
          await settleInboundShareAdmission(
            admission: const InboundShareAdmissionResult(
              InboundShareAdmission.rejected,
              reason: 'over budget',
            ),
            token: token,
            handoff: h,
          );
          expect(h.calls, ['reject:$token']);
        },
      );

      test(
        'an admission with no session rejects even if not marked rejected',
        () async {
          // Defensive: a null session means nothing owns the staging, so
          // acknowledging would strand it.
          final h = _RecordingHandoff();
          await settleInboundShareAdmission(
            admission: const InboundShareAdmissionResult(
              InboundShareAdmission.active,
            ),
            token: token,
            handoff: h,
          );
          expect(h.calls, ['reject:$token']);
        },
      );

      test('a payload with no staging token settles nothing', () async {
        // Not a native session - an Android text share has nothing to settle.
        final h = _RecordingHandoff();
        await settleInboundShareAdmission(
          admission: InboundShareAdmissionResult(
            InboundShareAdmission.active,
            session: session(),
          ),
          token: null,
          handoff: h,
        );
        await settleInboundShareAdmission(
          admission: InboundShareAdmissionResult(
            InboundShareAdmission.active,
            session: session(),
          ),
          token: '',
          handoff: h,
        );
        expect(h.calls, isEmpty);
      });
    },
  );

  group('InboundShareConversationDonor', () {
    const donor = InboundShareConversationDonor(channel);

    test('sends the room id and display name', () async {
      expect(
        await donor.donate(roomId: '!r:e.org', displayName: 'Team'),
        isTrue,
      );
      expect(calls.single.method, 'donateConversation');
      expect(calls.single.arguments, {
        'roomId': '!r:e.org',
        'displayName': 'Team',
      });
    });

    test('refuses to donate a blank room or name', () async {
      // A donation with nothing meaningful in it would still publish an entry
      // to the system suggestion store.
      expect(await donor.donate(roomId: '', displayName: 'Team'), isFalse);
      expect(
        await donor.donate(roomId: '!r:e.org', displayName: '   '),
        isFalse,
      );
      expect(calls, isEmpty);
    });

    test(
      'reports false rather than throwing when the platform refuses',
      () async {
        responder = (_) => throw PlatformException(code: 'nope');
        expect(
          await donor.donate(roomId: '!r:e.org', displayName: 'Team'),
          isFalse,
        );
      },
    );

    test('reports false when native returns false', () async {
      responder = (_) => false;
      expect(
        await donor.donate(roomId: '!r:e.org', displayName: 'Team'),
        isFalse,
      );
    });
  });

  group('NoopInboundShareHandoff', () {
    test('reports nothing at all', () async {
      // Android stages through the host process and has no reservation to
      // settle, so a call here would hit a method that does not exist.
      const noop = NoopInboundShareHandoff();
      await noop.acknowledge(token);
      await noop.reject(token);
      expect(calls, isEmpty);
    });
  });

  test('a state transition preserves the manifest schema version', () {
    // claim() and terminal() rebuild the manifest, and schemaVersion defaults
    // to 1 - so omitting it silently rewrote any non-1 manifest's format on its
    // FIRST transition, which is the point at which a version field stops being
    // able to tell you anything.
    final manifest = InboundShareManifest(
      schemaVersion: 7,
      token: 'abcdef0123456789',
      sessionRoot: '/tmp/session',
      createdAt: DateTime(2026),
      state: InboundShareManifestState.ready,
    );
    final claimed = manifest.claim();
    expect(claimed.schemaVersion, 7);
    expect(
      claimed.terminal(InboundShareManifestState.transferred).schemaVersion,
      7,
    );
  });
}

/// Records what was settled and when, so ordering can be asserted.
class _RecordingHandoff implements InboundShareHandoff {
  final List<String> calls = [];
  @override
  Future<void> acknowledge(String token) async => calls.add('ack:$token');
  @override
  Future<void> reject(String token) async => calls.add('reject:$token');
}
