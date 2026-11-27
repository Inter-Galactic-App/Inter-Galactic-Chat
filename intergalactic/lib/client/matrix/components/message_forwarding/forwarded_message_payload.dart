/// A portable, safe representation of the visible part of a forwarded message.
///
/// This is deliberately not a copy of the source Matrix event.  It only keeps
/// fields that are useful when creating a new event in another room, so source
/// event/room identifiers, relations, mentions, ciphertext, and file metadata
/// cannot cross the forwarding boundary.
class ForwardedMessagePayload {
  static const presentationKey = 'chat.intergalactic.forwarded';
  static const presentationVersion = 1;

  const ForwardedMessagePayload({
    required this.originalAuthorId,
    required this.originalAuthorDisplayName,
    required this.body,
    this.formattedBody,
  });

  /// The original visible sender's Matrix ID. This is presentation metadata,
  /// not an automatic mention or a cryptographic sender assertion.
  final String originalAuthorId;

  /// The original visible sender name at the time the user forwarded it.
  final String originalAuthorDisplayName;

  /// The visible plain-text message or attachment caption.
  final String body;

  /// Optional visible HTML formatting for [body].
  final String? formattedBody;

  factory ForwardedMessagePayload.fromVisibleContent({
    required String originalAuthorId,
    required String originalAuthorDisplayName,
    required Map<String, Object?> visibleContent,
  }) {
    final content = _sanitizeVisibleContent(visibleContent);
    return ForwardedMessagePayload(
      originalAuthorId: originalAuthorId,
      originalAuthorDisplayName: originalAuthorDisplayName,
      body: content['body'] as String? ?? '',
      formattedBody: _escapedPlainHtml(content['body'] as String? ?? ''),
    );
  }

  /// The exact fallback attribution written into `body` for clients which do
  /// not understand the Inter Galactic presentation envelope.
  ///
  /// A client that DOES understand the envelope draws the attribution itself,
  /// so it has to remove this line or the same sentence is printed twice - once
  /// as the attribution and once as the message. Both sides derive the string
  /// from here rather than each spelling it out, because a stripper that
  /// guesses the writer's wording silently stops matching the day the wording
  /// changes, and the failure looks like the original bug.
  static String headerFor(String label, String id) =>
      'Forwarded from $label ($id)';

  /// The same header as it appears in `formatted_body`.
  static String formattedHeaderFor(String label, String id) =>
      '<strong>${_escapeHtml(headerFor(label, id))}</strong>';

  /// A human-readable fallback for clients which do not understand the
  /// Inter Galactic presentation envelope.
  String get header => headerFor(originalAuthorDisplayName, originalAuthorId);

  String get fallbackBody => body.trim().isEmpty ? header : '$header\n\n$body';

  String get fallbackFormattedBody {
    final escapedHeader = formattedHeaderFor(
      originalAuthorDisplayName,
      originalAuthorId,
    );
    final formatted = formattedBody?.trim();
    return formatted == null || formatted.isEmpty
        ? escapedHeader
        : '$escapedHeader<br><br>$formatted';
  }

  /// Sender-provided display metadata. It intentionally contains no source
  /// room or event reference, and never creates an `m.mentions` entry.
  Map<String, Object?> get presentationEnvelope => Map.unmodifiable({
    'v': presentationVersion,
    'original_sender': originalAuthorId,
    'original_sender_label': originalAuthorDisplayName,
  });

  /// Content for a new, ordinary Matrix text event in a destination room.
  Map<String, Object?> get textContent => Map.unmodifiable({
    'msgtype': 'm.text',
    'body': fallbackBody,
    'format': 'org.matrix.custom.html',
    'formatted_body': fallbackFormattedBody,
    presentationKey: presentationEnvelope,
  });

  /// Keeps only the visible text fields that may safely be re-sent. This is an
  /// allow-list rather than a copy-and-delete transform, so source metadata
  /// cannot survive under an unexpected nested key.
  static Map<String, Object?> _sanitizeVisibleContent(
    Map<String, Object?> source,
  ) {
    final body = source['body'];
    final result = <String, Object?>{
      if (body is String) 'body': body,
      // Never reuse source HTML. A forward has a new context, and copying
      // source markup could preserve pills, reply fallbacks or unsupported
      // elements. Production rebuilds formatted content from this plain body.
    };
    return Map.unmodifiable(result);
  }
}

String _escapeHtml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

String _escapedPlainHtml(String value) =>
    _escapeHtml(value).replaceAll('\n', '<br>');
