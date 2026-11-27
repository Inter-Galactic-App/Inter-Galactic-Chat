class AndroidInboundShareIntent {
  const AndroidInboundShareIntent({
    required this.text,
    required this.streams,
    this.mimeType,
  });
  final String? text;
  final List<Uri> streams;
  final String? mimeType;
  bool get hasPayload =>
      (text?.trim().isNotEmpty ?? false) || streams.isNotEmpty;
}

class AndroidInboundShareBridge {
  static const actionSend = 'android.intent.action.SEND';
  static const actionSendMultiple = 'android.intent.action.SEND_MULTIPLE';
  static const extraText = 'android.intent.extra.TEXT';
  static const extraStream = 'android.intent.extra.STREAM';

  static AndroidInboundShareIntent? tryParse(dynamic intent) {
    final action = intent?.action;
    if (action != actionSend && action != actionSendMultiple) return null;
    final extra = intent?.extra;
    if (extra is! Map) return null;
    // Every field below comes from an intent another app constructed, so a
    // wrong type is a malformed share to reject - not an exception to throw out
    // of inbound-share handling. `as String?` would have thrown here.
    final rawText = extra[extraText];
    if (rawText != null && rawText is! String) return null;
    final text = rawText as String?;
    final rawStreams = extra[extraStream];
    final values = rawStreams is Iterable
        ? rawStreams
        : rawStreams == null
        ? const []
        : [rawStreams];
    final streams = <Uri>[];
    for (final value in values) {
      final uri = value is Uri ? value : Uri.tryParse(value?.toString() ?? '');
      if (uri == null || uri.scheme != 'content') return null;
      streams.add(uri);
    }
    // `receive_intent` serializes only the public Intent fields it exposes; it
    // does not include Android's `Intent.type`. Keep MIME metadata optional and
    // fall back to the ContentResolver value gathered during staging instead of
    // throwing before a valid share can reach the destination picker.
    Object? rawMimeType;
    try {
      rawMimeType = intent?.type;
    } on NoSuchMethodError {
      rawMimeType = null;
    }
    if (rawMimeType != null && rawMimeType is! String) return null;
    final result = AndroidInboundShareIntent(
      text: text,
      streams: streams,
      mimeType: rawMimeType as String?,
    );
    return result.hasPayload ? result : null;
  }
}
