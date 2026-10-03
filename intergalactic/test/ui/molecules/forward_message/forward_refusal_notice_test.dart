import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/message_forwarding/matrix_message_forwarder.dart';
import 'package:intergalactic/ui/molecules/forward_message/forward_message_dialog.dart';

/// The forwarder reporting a distinguishable refusal is only half of the fix.
/// These hold the other half: that the dialog actually SAYS something
/// different for it. A typed reason that renders as the same sentence is the
/// same misleading error with more code behind it.
void main() {
  group('the forward refusal notice', () {
    test('an oversize attachment is not called unavailable', () {
      final tooLarge = ForwardMessageDialog.refusalNotice(
        MatrixForwardRefusal.attachmentTooLarge,
      );
      final unavailable = ForwardMessageDialog.refusalNotice(
        MatrixForwardRefusal.unavailable,
      );

      expect(tooLarge, isNot(unavailable));
      expect(tooLarge, contains('too large'));
      expect(
        tooLarge,
        isNot(contains('no longer available')),
        reason:
            'the message IS available; telling the member otherwise sends '
            'them away from a file they could still send another way',
      );
    });

    test('the notice states the bound it was refused by', () {
      // Written against the constant, not the number, so raising the guard
      // cannot leave the sentence quoting the old limit.
      final limit =
          MatrixMessageForwarder.maxForwardAttachmentBytes ~/ (1024 * 1024);

      expect(
        ForwardMessageDialog.refusalNotice(
          MatrixForwardRefusal.attachmentTooLarge,
        ),
        contains('$limit MB'),
      );
    });

    test('every other refusal keeps the wording it had', () {
      // The generic message is correct for a redacted or unforwardable
      // message, and this is the only place that is still asserted.
      const unchanged = 'This message is no longer available to forward.';

      expect(
        ForwardMessageDialog.refusalNotice(MatrixForwardRefusal.unavailable),
        unchanged,
      );
      expect(ForwardMessageDialog.refusalNotice(null), unchanged);
    });
  });
}
