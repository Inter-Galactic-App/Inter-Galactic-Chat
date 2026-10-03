import 'dart:typed_data';

import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/matrix/components/message_forwarding/forwarded_message_payload.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_message.dart';

/// The portable, locally prepared representation of a Matrix message forward.
///
/// This deliberately contains only displayed content and author attribution.
/// It must never carry source-event relationships, mentions, room/event IDs,
/// ciphertext, encrypted-file metadata, or media keys.
class MatrixForwardedMessage {
  static const presentationKey = ForwardedMessagePayload.presentationKey;
  static const presentationVersion =
      ForwardedMessagePayload.presentationVersion;

  const MatrixForwardedMessage({
    required this.payload,
    required this.attachments,
  });

  final ForwardedMessagePayload payload;
  final List<MatrixForwardedAttachment> attachments;

  bool get hasAttachments => attachments.isNotEmpty;

  Map<String, Object?> get textContent => payload.textContent;

  Map<String, dynamic> get attachmentExtraContent {
    final content = Map<String, dynamic>.from(payload.textContent);
    content.remove('msgtype');
    return content;
  }
}

class MatrixForwardedAttachment {
  const MatrixForwardedAttachment({
    required this.name,
    required this.bytes,
    required this.mimeType,
    required this.spoiler,
  });

  final String name;
  final Uint8List bytes;
  final String? mimeType;
  final bool spoiler;

  /// Creates a fresh pending attachment for one destination. It is important
  /// that callers do not reuse a processed MatrixFile across rooms, because
  /// each destination must run its normal encryption and upload flow.
  PendingFileAttachment toPendingAttachment() => PendingFileAttachment(
    name: name,
    data: Uint8List.fromList(bytes),
    mimeType: mimeType,
    spoiler: spoiler,
  );
}

enum MatrixForwardAttemptState { pending, success, failure, unknown }

/// Parsed display-only attribution. This is deliberately sender-supplied
/// metadata, not a cryptographic claim about the original author.
class MatrixForwardedPresentation {
  static final RegExp _leadingLineBreak = RegExp(
    r'^\s*<br\s*/?>',
    caseSensitive: false,
  );

  const MatrixForwardedPresentation({
    required this.originalAuthorId,
    required this.originalAuthorLabel,
  });

  final String originalAuthorId;
  final String originalAuthorLabel;

  /// The fallback attribution this forward carries inside its own body for
  /// clients that cannot read the envelope.
  String get fallbackHeader =>
      ForwardedMessagePayload.headerFor(originalAuthorLabel, originalAuthorId);

  /// Removes the fallback attribution from a plain body.
  ///
  /// Returns [body] untouched unless it starts with the exact header. A
  /// forwarded message that was edited, or written by another client that
  /// worded its attribution differently, must lose nothing: printing the line
  /// twice is a blemish, deleting the first line of someone's message is not.
  String stripFallbackHeader(String body) {
    if (!body.startsWith(fallbackHeader)) {
      return body;
    }

    return body.substring(fallbackHeader.length).trimLeft();
  }

  /// The [stripFallbackHeader] rule for `formatted_body`, including the line
  /// breaks the writer puts between the header and the message.
  String stripFallbackHeaderHtml(String html) {
    final header = ForwardedMessagePayload.formattedHeaderFor(
      originalAuthorLabel,
      originalAuthorId,
    );
    if (!html.startsWith(header)) {
      return html;
    }

    var rest = html.substring(header.length);
    while (true) {
      final match = _leadingLineBreak.matchAsPrefix(rest);
      if (match == null) {
        break;
      }
      rest = rest.substring(match.end);
    }

    return rest.trimLeft();
  }

  static MatrixForwardedPresentation? tryParse(
    MatrixTimelineEventMessage event,
  ) {
    final raw = event.event.content[MatrixForwardedMessage.presentationKey];
    if (raw is! Map) return null;
    final version = raw['v'];
    final id = raw['original_sender'];
    final label = raw['original_sender_label'];
    if (version != MatrixForwardedMessage.presentationVersion ||
        id is! String ||
        id.isEmpty ||
        label is! String ||
        label.isEmpty) {
      return null;
    }
    return MatrixForwardedPresentation(
      originalAuthorId: id,
      originalAuthorLabel: label,
    );
  }
}

class MatrixForwardAttempt {
  MatrixForwardAttempt({
    required this.destinationRoomId,
    required this.transactionId,
    this.state = MatrixForwardAttemptState.pending,
    this.eventId,
    this.error,
  });

  final String destinationRoomId;
  final String transactionId;
  MatrixForwardAttemptState state;
  String? eventId;
  Object? error;

  bool get isComplete => state == MatrixForwardAttemptState.success;
}
