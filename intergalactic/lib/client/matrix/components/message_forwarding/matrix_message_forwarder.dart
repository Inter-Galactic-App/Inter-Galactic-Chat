import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/matrix/components/message_forwarding/forwarded_message_payload.dart';
import 'package:intergalactic/client/matrix/components/message_forwarding/matrix_forwarded_message.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/utils/mime.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Why a forward could not be prepared.
///
/// The two are kept apart because they need OPPOSITE advice. A message that is
/// redacted or of a kind this client cannot forward is gone, and there is
/// nothing to do about it. A file that is merely over the client bound is
/// still there and can still be sent another way - telling the member it is no
/// longer available sends them away from a message they could act on, which is
/// as bad as saying nothing at all.
enum MatrixForwardRefusal {
  /// The source is not forwardable: redacted, the wrong event or message type,
  /// an unsupported attachment, an attachment whose bytes did not resolve, or
  /// nothing visible left to send.
  unavailable,

  /// An attachment is larger than
  /// [MatrixMessageForwarder.maxForwardAttachmentBytes].
  attachmentTooLarge,
}

/// The result of a [MatrixMessageForwarder.prepare] attempt.
///
/// A refusal is an EXPECTED outcome on this path, not an exception, so every
/// one carries a structured [refusal] the caller renders. This replaced a bare
/// nullable return, which could only say THAT preparation failed.
class MatrixForwardPrepareOutcome {
  const MatrixForwardPrepareOutcome.prepared(
    MatrixForwardedMessage this.message,
  ) : refusal = null;

  // Both formals narrow the nullable field types on purpose: an outcome that
  // is neither prepared nor refused would contradict the invariant documented
  // below, and the compiler is a better place to enforce that than a review.
  const MatrixForwardPrepareOutcome.refused(MatrixForwardRefusal this.refusal)
    : message = null;

  /// The prepared forward; null exactly when [refusal] is set.
  final MatrixForwardedMessage? message;

  /// Why the forward was refused; null exactly when [message] is set. Prefer
  /// asserting this over the rendered wording in tests.
  final MatrixForwardRefusal? refusal;
}

/// Builds safe, destination-independent forward payloads and sends them using
/// the Matrix-only forwarding boundary.
class MatrixMessageForwarder {
  MatrixMessageForwarder._();

  /// The largest attachment this client is willing to forward.
  ///
  /// A forward re-uploads the file rather than re-pointing at the original, so
  /// the whole attachment is held in memory here, and again per destination
  /// while each room encrypts its own copy. That is what this bounds.
  ///
  /// It is a CLIENT MEMORY GUARD, not a protocol rule and deliberately not
  /// this account's homeserver upload limit: every homeserver picks its own,
  /// and reading ours here would bake one server's number into a client that
  /// talks to many. A destination that allows less will still refuse the
  /// upload, and that refusal is reported per destination as it always was.
  static const int maxForwardAttachmentBytes = 100 * 1024 * 1024;

  static Future<MatrixForwardPrepareOutcome> prepare({
    required MatrixRoom sourceRoom,
    required MatrixTimelineEventMessage source,
  }) async {
    const unavailable = MatrixForwardPrepareOutcome.refused(
      MatrixForwardRefusal.unavailable,
    );

    final displayEvent = source.getDisplayEvent(null);
    if (!_isForwardable(displayEvent)) {
      return unavailable;
    }

    final attachments = <MatrixForwardedAttachment>[];
    for (final attachment in source.attachments ?? const <Attachment>[]) {
      if (attachment is! FileAttachment ||
          !_isSupportedAttachment(
            attachment.mimeType,
            displayEvent.messageType,
          )) {
        return unavailable;
      }

      final loaded = await forwardableAttachmentBytes(attachment);
      final bytes = loaded.bytes;
      if (bytes == null) {
        // The load always names its refusal. The fallback is there so a future
        // refusal path that forgets to set one degrades to the message this
        // showed before the size bound existed, rather than forwarding.
        return MatrixForwardPrepareOutcome.refused(
          loaded.refusal ?? MatrixForwardRefusal.unavailable,
        );
      }
      // The bytes are passed on as loaded. getFileData builds its buffer for
      // this call, and toPendingAttachment already takes a fresh copy per
      // destination, so copying here only held the file twice.
      attachments.add(
        MatrixForwardedAttachment(
          name: attachment.name,
          bytes: bytes,
          mimeType: attachment.mimeType,
          spoiler: attachment.spoiler,
        ),
      );
    }

    final originalAuthor = sourceRoom.getMemberOrFallback(source.senderId);
    final plain = _visibleBody(displayEvent);
    if (attachments.isEmpty && plain.trim().isEmpty) {
      return unavailable;
    }

    return MatrixForwardPrepareOutcome.prepared(
      MatrixForwardedMessage(
        payload: ForwardedMessagePayload.fromVisibleContent(
          originalAuthorId: source.senderId,
          originalAuthorDisplayName: originalAuthor.displayName,
          visibleContent: {'body': plain},
        ),
        attachments: attachments,
      ),
    );
  }

  /// Loads one attachment, refusing anything over [maxForwardAttachmentBytes].
  ///
  /// Returns the bytes, or the [MatrixForwardRefusal] that stopped them -
  /// exactly one of the two is non-null. A refusal still stops the whole
  /// forward, as it always did, rather than sending it with the file missing;
  /// the reason rides along so the caller can say WHICH refusal it was.
  ///
  /// The declared size is checked FIRST because it is the only check that can
  /// stop the download before the bytes exist. It is sender-supplied metadata
  /// though - absent on some events and free to lie on any - so the loaded
  /// length is checked again. By then this copy is already in memory, but it
  /// is the check that keeps the file out of the per-destination upload loop,
  /// where the cost is multiplied.
  ///
  /// Takes the attachment rather than the whole event so the bound is
  /// reachable from a test without building an SDK event and its room.
  @visibleForTesting
  static Future<({Uint8List? bytes, MatrixForwardRefusal? refusal})>
  forwardableAttachmentBytes(FileAttachment attachment) async {
    final declared = attachment.fileSize;
    if (declared != null && declared > maxForwardAttachmentBytes) {
      Log.w(
        'Not forwarding an attachment declaring $declared bytes; the client '
        'forward limit is $maxForwardAttachmentBytes bytes.',
      );
      return (bytes: null, refusal: MatrixForwardRefusal.attachmentTooLarge);
    }

    final bytes = await attachment.file.getFileData();
    if (bytes == null || bytes.isEmpty) {
      // Nothing resolved, so there is nothing to say about its size. This is
      // the pre-existing "no longer available" case and must stay that way.
      return (bytes: null, refusal: MatrixForwardRefusal.unavailable);
    }
    if (bytes.length > maxForwardAttachmentBytes) {
      Log.w(
        'Not forwarding a ${bytes.length} byte attachment; the client forward '
        'limit is $maxForwardAttachmentBytes bytes.',
      );
      return (bytes: null, refusal: MatrixForwardRefusal.attachmentTooLarge);
    }
    return (bytes: bytes, refusal: null);
  }

  static bool isForwardableMessage(MatrixTimelineEventMessage source) {
    return _isForwardable(source.getDisplayEvent(null)) &&
        (source.plainTextBody.trim().isNotEmpty ||
            source.attachments?.isNotEmpty == true);
  }

  /// How many destinations a forward of [message] may be sent to at once.
  ///
  /// A forward carrying attachments goes ONE destination at a time. Each
  /// destination calls `toPendingAttachment()`, which copies the bytes with
  /// `Uint8List.fromList`, and then encrypts its own copy. At three at once,
  /// with [maxForwardAttachmentBytes] at 100 MB, the peak resident size is the
  /// retained source plus three destination copies - roughly 400 MB before
  /// encryption buffers. That is more than an Android process can hold, and it
  /// defeats the per-attachment bound this class documents.
  ///
  /// Text-only forwards keep the wider fan-out: they carry no bytes to copy,
  /// so the reason for the limit does not apply to them. The cost is that a
  /// forward of one attachment to N rooms now takes N sequential uploads
  /// instead of ceil(N/3) rounds.
  @visibleForTesting
  static int forwardConcurrencyFor(MatrixForwardedMessage message) =>
      message.hasAttachments ? 1 : 3;

  /// Sends only attempts that have not already succeeded. Retry callers retain
  /// the same attempt instances, and therefore the same per-destination txids.
  static Future<List<MatrixForwardAttempt>> send({
    required MatrixForwardedMessage message,
    required Map<String, MatrixRoom> destinations,
    required List<MatrixForwardAttempt> attempts,
  }) async {
    final pending = attempts.where((attempt) => !attempt.isComplete).toList();
    var next = 0;
    final workers = List.generate(
      math.min(forwardConcurrencyFor(message), pending.length),
      (_) async {
        while (next < pending.length) {
          final attempt = pending[next++];
          await _sendAttempt(
            message: message,
            destinations: destinations,
            attempt: attempt,
          );
        }
      },
    );
    await Future.wait(workers);
    return attempts;
  }

  static Future<void> _sendAttempt({
    required MatrixForwardedMessage message,
    required Map<String, MatrixRoom> destinations,
    required MatrixForwardAttempt attempt,
  }) async {
    final destination = destinations[attempt.destinationRoomId];
    if (destination == null || !destination.permissions.canSendMessage) {
      attempt.state = MatrixForwardAttemptState.failure;
      attempt.error = StateError('The destination is not currently sendable.');
      return;
    }

    attempt.state = MatrixForwardAttemptState.pending;
    attempt.error = null;
    try {
      final eventId = await destination.sendForwardedMessage(
        message: message,
        transactionId: attempt.transactionId,
      );
      if (eventId == null) {
        // The request left this process without a confirmed event id. Keep
        // the txid so a later retry can be reconciled by the SDK/server.
        attempt.state = MatrixForwardAttemptState.unknown;
      } else {
        attempt.state = MatrixForwardAttemptState.success;
        attempt.eventId = eventId;
      }
    } catch (error) {
      attempt.state = MatrixForwardAttemptState.failure;
      attempt.error = error;
    }
  }

  static List<MatrixForwardAttempt> createAttempts({
    required Iterable<MatrixRoom> destinations,
  }) => [
    for (final destination in destinations)
      MatrixForwardAttempt(
        destinationRoomId: destination.identifier,
        transactionId: destination.matrixRoom.client
            .generateUniqueTransactionId(),
      ),
  ];

  static bool _isForwardable(matrix.Event event) {
    if (event.redacted || event.type != matrix.EventTypes.Message) {
      return false;
    }
    return event.messageType == matrix.MessageTypes.Text ||
        event.messageType == matrix.MessageTypes.Image ||
        event.messageType == matrix.MessageTypes.Video ||
        event.messageType == matrix.MessageTypes.File;
  }

  static bool _isSupportedAttachment(String? mimeType, String messageType) =>
      messageType == matrix.MessageTypes.Image ||
      messageType == matrix.MessageTypes.Video ||
      messageType == matrix.MessageTypes.File ||
      Mime.imageTypes.contains(mimeType) ||
      Mime.videoTypes.contains(mimeType);

  static String _visibleBody(matrix.Event event) {
    final visible = forwardedVisibleBody(
      content: event.content,
      plaintextBody: event.plaintextBody,
    );
    if (event.hasAttachment) {
      final filename = event.content['filename']?.toString() ?? event.body;
      return filename == event.plaintextBody ? '' : visible;
    }
    return visible;
  }

  /// The body a forward may carry, with the legacy reply fallback removed.
  ///
  /// A rich reply MAY prefix `body` with a `> <@alice:example.org> quoted text`
  /// block. `Event.plaintextBody` does NOT remove it: read at
  /// matrix-dart-sdk-58e0bd24, `formattedText` is `content['formatted_body']
  /// ?? ''`, and `plaintextBody` returns `body` VERBATIM when that is empty. A
  /// reply WITH `formatted_body` is already safe - `HtmlToText.convert` strips
  /// `<mx-reply>`, and the SDK says it does that to prevent impersonation - but
  /// a reply WITHOUT one carried the quoted author's MXID into the destination.
  ///
  /// That MXID is a NEW disclosure: the destination room may have no idea who
  /// the quoted person is, and it contradicts [ForwardedMessagePayload]'s
  /// stated boundary of carrying no source references.
  ///
  /// Takes content rather than an `Event` so the gate and the strip are both
  /// reachable from a test without building an SDK event and its room.
  @visibleForTesting
  static String forwardedVisibleBody({
    required Map<String, Object?> content,
    required String plaintextBody,
  }) {
    // Only replies carry the fallback, so an ordinary message that happens to
    // begin with "> " keeps its own quoting.
    if (!_isRichReplyContent(content)) {
      return plaintextBody;
    }

    final lines = plaintextBody.split('\n');
    var index = 0;
    while (index < lines.length && lines[index].startsWith('> ')) {
      index++;
    }
    if (index == 0) {
      return plaintextBody;
    }
    // The spec separates the fallback from the real message with one blank
    // line. Drop it, but only when a quote block actually preceded it.
    if (index < lines.length && lines[index].trim().isEmpty) {
      index++;
    }
    return lines.sublist(index).join('\n');
  }

  static bool _isRichReplyContent(Map<String, Object?> content) {
    final relates = content['m.relates_to'];
    return relates is Map && relates['m.in_reply_to'] is Map;
  }
}
