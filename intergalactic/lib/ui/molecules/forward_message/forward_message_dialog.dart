import 'package:flutter/material.dart';
import 'package:intergalactic/client/matrix/components/message_forwarding/matrix_forwarded_message.dart';
import 'package:intergalactic/client/matrix/components/message_forwarding/matrix_message_forwarder.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/forward_message/forward_destination_page.dart';

/// Chooses up to ten rooms on the source account and sends an ordinary new
/// Matrix event to each. The source event is prepared only after a destination
/// is selected, so choosing Forward alone does not upload or resend anything.
class ForwardMessageDialog {
  static const _maximumDestinations = 10;

  static Future<void> show(
    BuildContext context, {
    required MatrixRoom sourceRoom,
    required MatrixTimelineEventMessage source,
  }) async {
    final rooms = sourceRoom.client.rooms
        .whereType<MatrixRoom>()
        .where(
          (room) =>
              room.identifier != sourceRoom.identifier &&
              room.permissions.canSendMessage,
        )
        .toList(growable: false);
    if (rooms.isEmpty) {
      _showNotice(context, 'No other sendable rooms are available.');
      return;
    }

    // The destination limit now lives in the picker, which stops the eleventh
    // selection rather than rejecting a finished choice - so there is no
    // over-limit branch to handle here.
    final chosen = await ForwardDestinationPage.show(
      context,
      destinations: ForwardDestination.forRooms(rooms),
      maximumSelections: _maximumDestinations,
    );
    if (!context.mounted || chosen == null) return;
    final selected = chosen.whereType<MatrixRoom>().toList(growable: false);
    if (selected.isEmpty) {
      _showNotice(context, 'Choose at least one room.');
      return;
    }

    MatrixForwardPrepareOutcome outcome;
    try {
      outcome = await MatrixMessageForwarder.prepare(
        sourceRoom: sourceRoom,
        source: source,
      );
    } catch (error, stackTrace) {
      // Logged, because the notice cannot say what went wrong: a failed media
      // re-upload and a decryption failure both surface as the same sentence,
      // and without this the cause is unrecoverable from the logs.
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to prepare a message for forwarding',
      );
      // An unexpected throw says nothing about why, so it keeps the message it
      // has always shown rather than guessing at a cause.
      outcome = const MatrixForwardPrepareOutcome.refused(
        MatrixForwardRefusal.unavailable,
      );
    }
    if (!context.mounted) return;
    final message = outcome.message;
    if (message == null) {
      _showNotice(context, refusalNotice(outcome.refusal));
      return;
    }

    final attempts = MatrixMessageForwarder.createAttempts(
      destinations: selected,
    );
    final destinationById = {
      for (final room in selected) room.identifier: room,
    };
    await MatrixMessageForwarder.send(
      message: message,
      destinations: destinationById,
      attempts: attempts,
    );
    if (!context.mounted) return;
    await _showResults(
      context,
      message: message,
      destinations: destinationById,
      attempts: attempts,
    );
  }

  static Future<void> _showResults(
    BuildContext context, {
    required MatrixForwardedMessage message,
    required Map<String, MatrixRoom> destinations,
    required List<MatrixForwardAttempt> attempts,
  }) {
    var retrying = false;
    return AdaptiveDialog.show<void>(
      context,
      title: 'Forward message',
      dismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final successes = attempts
              .where(
                (attempt) => attempt.state == MatrixForwardAttemptState.success,
              )
              .length;
          final unresolved = attempts
              .where((attempt) => !attempt.isComplete)
              .length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                unresolved == 0
                    ? 'Forwarded to $successes ${successes == 1 ? 'room' : 'rooms'}.'
                    : 'Forwarded to $successes. $unresolved ${unresolved == 1 ? 'room needs' : 'rooms need'} attention.',
              ),
              if (unresolved > 0) ...[
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry unsuccessful rooms'),
                  onPressed: retrying
                      ? null
                      : () async {
                          setState(() => retrying = true);
                          await MatrixMessageForwarder.send(
                            message: message,
                            destinations: destinations,
                            attempts: attempts,
                          );
                          // Done stays enabled through the retry, so the
                          // dialog can be popped while this await is in
                          // flight; the StatefulBuilder element is then gone
                          // and setState throws on a defunct element.
                          if (!context.mounted) return;
                          setState(() => retrying = false);
                        },
                ),
              ],
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// What the member is told when a forward could not be prepared.
  ///
  /// An oversize attachment gets its own wording because the generic one is
  /// actively wrong for it: the message IS still available, and naming the
  /// bound leaves the member somewhere to go - send the file another way -
  /// instead of telling them to give up on something they can still act on.
  ///
  /// The number is derived from the guard rather than typed out, so the two
  /// cannot drift apart. Rendered as MB the way every other size limit in the
  /// app is (see the inbound share and emoji import notices), even though the
  /// bound itself is binary.
  @visibleForTesting
  static String refusalNotice(MatrixForwardRefusal? refusal) {
    if (refusal == MatrixForwardRefusal.attachmentTooLarge) {
      final limit =
          MatrixMessageForwarder.maxForwardAttachmentBytes ~/ (1024 * 1024);
      return 'That attachment is too large to forward. Attachments must be '
          '$limit MB or smaller.';
    }
    return 'This message is no longer available to forward.';
  }

  static void _showNotice(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
