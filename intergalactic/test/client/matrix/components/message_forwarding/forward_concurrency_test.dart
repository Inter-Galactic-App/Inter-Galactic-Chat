// The fan-out bound on `send`, asserted where it is decided.
//
// WHAT WOULD MAKE THIS VACUOUS, stated first: asserting the constants back to
// themselves. `forwardConcurrencyFor` exists so the POLICY is observable -
// `send`'s worker count is otherwise unreachable from a test without standing
// up three real MatrixRooms and a homeserver. So these assert the two answers
// the policy gives, and the reason each one matters, rather than the literals
// 1 and 3 in isolation.
//
// The reason for the attachment case is memory, not politeness. Each
// destination copies the bytes with `Uint8List.fromList` and encrypts its own
// copy, so three at once against a 100 MB per-attachment cap peaks near 400 MB
// before encryption buffers - past what an Android process holds, and past the
// per-attachment bound this class documents.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/message_forwarding/forwarded_message_payload.dart';
import 'package:intergalactic/client/matrix/components/message_forwarding/matrix_forwarded_message.dart';
import 'package:intergalactic/client/matrix/components/message_forwarding/matrix_message_forwarder.dart';

const _payload = ForwardedMessagePayload(
  originalAuthorId: '@alex:example.org',
  originalAuthorDisplayName: 'Alex',
  body: 'A caption',
);

MatrixForwardedMessage _message({required bool withAttachment}) {
  return MatrixForwardedMessage(
    payload: _payload,
    attachments: [
      if (withAttachment)
        MatrixForwardedAttachment(
          name: 'photo.gif',
          bytes: Uint8List.fromList(const [1, 2, 3]),
          mimeType: 'image/gif',
          spoiler: false,
        ),
    ],
  );
}

void main() {
  test('a forward carrying attachments is sent one destination at a time', () {
    final message = _message(withAttachment: true);

    // Arming: the policy is keyed off this, so a message that silently lost
    // its attachment would make the assertion below pass for the wrong reason.
    expect(message.hasAttachments, isTrue);

    expect(
      MatrixMessageForwarder.forwardConcurrencyFor(message),
      1,
      reason:
          'each destination holds its own copy of every attachment while it '
          'encrypts, so concurrent sends multiply peak memory by the fan-out',
    );
  });

  test('a text-only forward keeps the wider fan-out', () {
    final message = _message(withAttachment: false);

    expect(message.hasAttachments, isFalse);

    expect(
      MatrixMessageForwarder.forwardConcurrencyFor(message),
      greaterThan(1),
      reason:
          'a text-only forward copies no bytes, so the memory bound that '
          'serialises attachment forwards does not apply to it',
    );
  });

  test('the two cases are not the same answer', () {
    // Guards the whole point: a change that serialised everything, or that
    // dropped the attachment check, would leave both tests above passing
    // individually if either used a loose matcher.
    expect(
      MatrixMessageForwarder.forwardConcurrencyFor(
        _message(withAttachment: true),
      ),
      lessThan(
        MatrixMessageForwarder.forwardConcurrencyFor(
          _message(withAttachment: false),
        ),
      ),
    );
  });
}
