// The encryption gate on the timeline's Retry Decrypt action, asserted where
// it decides.
//
// WHAT WOULD MAKE THESE WRONG, stated first. The defect being fixed is a
// SILENT no-op: `Event.requestKey` reaches `Room.requestSessionKey`, which
// returns without doing anything when encryption is disabled and calls
// through a null-aware `client.encryption?.` when it is not. So a test that
// only asserted "a message was thrown" would pass against a version that
// threw the message and issued the request anyway - which is the same wasted
// round trip the user already had, now with an error dialog on top. Every
// refusal case therefore asserts that `requestKey` was NOT REACHED, and on
// the message second.
//
// The `ready` case is the control: it pins that the gate is what stopped the
// other two, rather than the action being broken for every state.

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/vodozemac_single_flight.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_event_menu.dart';

void main() {
  /// Runs the action, recording whether the key request was reached.
  Future<({Object? thrown, int requests})> run(
    EncryptionAvailability availability,
  ) async {
    var requests = 0;
    Object? thrown;
    try {
      await runTimelineRetryDecrypt(
        availability: availability,
        requestKey: () async => requests += 1,
      );
    } catch (error) {
      thrown = error;
    }
    return (thrown: thrown, requests: requests);
  }

  test('a ready stack sends the key request and says nothing', () async {
    final result = await run(EncryptionAvailability.ready);

    expect(result.requests, 1);
    expect(
      result.thrown,
      isNull,
      reason: 'the ordinary case must not put a dialog in front of the user',
    );
  });

  test('a preparing stack is refused before the request is sent', () async {
    final result = await run(EncryptionAvailability.pending);

    expect(
      result.requests,
      0,
      reason:
          'requestKey would be swallowed by requestSessionKey here; sending '
          'it anyway is the silence this gate exists to end',
    );
    expect(result.thrown, isA<String>());
    expect(
      result.thrown as String,
      contains('still preparing'),
      reason: 'and the reason has to say the state is temporary',
    );
  });

  test('a failed stack is refused, and says it will not fix itself', () async {
    final result = await run(EncryptionAvailability.unavailable);

    expect(result.requests, 0);
    expect(
      result.thrown as String,
      contains('did not start'),
      reason:
          'a session-long failure must not read like the preparing case, or '
          'the user retries something that can never succeed',
    );
  });

  test('the three states give three distinct answers', () {
    // Guards against a gate that collapses to one branch: a mutation making
    // every state return the same reason, or none, is caught here even if the
    // cases above were read as three copies of one assertion.
    expect(
      timelineRetryDecryptUnavailableReason(EncryptionAvailability.ready),
      isNull,
    );
    final pending = timelineRetryDecryptUnavailableReason(
      EncryptionAvailability.pending,
    );
    final unavailable = timelineRetryDecryptUnavailableReason(
      EncryptionAvailability.unavailable,
    );
    expect(pending, isNotNull);
    expect(unavailable, isNotNull);
    expect(pending, isNot(unavailable));
  });
}
