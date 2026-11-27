import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/message_forwarding/forwarded_message_payload.dart';
import 'package:intergalactic/client/matrix/components/message_forwarding/matrix_forwarded_message.dart';

void main() {
  test(
    'media forwarding keeps only a new presentation envelope and caption',
    () {
      final message = MatrixForwardedMessage(
        payload: const ForwardedMessagePayload(
          originalAuthorId: '@alex:example.org',
          originalAuthorDisplayName: 'Alex',
          body: 'A caption',
        ),
        attachments: [
          MatrixForwardedAttachment(
            name: 'photo.gif',
            bytes: Uint8List.fromList([1, 2, 3]),
            mimeType: 'image/gif',
            spoiler: false,
          ),
          MatrixForwardedAttachment(
            name: 'notes.pdf',
            bytes: Uint8List.fromList([4, 5, 6]),
            mimeType: 'application/pdf',
            spoiler: false,
          ),
        ],
      );

      expect(message.hasAttachments, isTrue);
      expect(message.attachmentExtraContent['body'], contains('A caption'));
      // The "keeps" half of the name, which nothing here asserted. Everything
      // else in this test is an absence, so dropping the envelope from the
      // attachment content left the suite green while every receiving client
      // lost the forward attribution on a media forward and fell back to the
      // plain-text header alone.
      expect(
        message.attachmentExtraContent,
        contains(ForwardedMessagePayload.presentationKey),
      );
      expect(
        message.attachmentExtraContent[ForwardedMessagePayload.presentationKey],
        containsPair('original_sender', '@alex:example.org'),
      );
      expect(
        message.attachmentExtraContent[ForwardedMessagePayload.presentationKey],
        containsPair('original_sender_label', 'Alex'),
      );
      expect(message.attachmentExtraContent, isNot(contains('m.mentions')));
      expect(message.attachmentExtraContent, isNot(contains('m.relates_to')));
      expect(message.attachments.map((attachment) => attachment.name), [
        'photo.gif',
        'notes.pdf',
      ]);
      expect(message.attachments.first.toPendingAttachment().data, [1, 2, 3]);
    },
  );

  test(
    'attempts retain destination transaction ids across unknown outcomes',
    () {
      final attempt = MatrixForwardAttempt(
        destinationRoomId: '!destination:example.org',
        transactionId: 'stable-transaction-id',
        state: MatrixForwardAttemptState.unknown,
      );

      expect(attempt.state, MatrixForwardAttemptState.unknown);
      expect(attempt.transactionId, 'stable-transaction-id');
      expect(attempt.isComplete, isFalse);
    },
  );
}
