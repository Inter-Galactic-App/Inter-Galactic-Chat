import 'package:matrix/matrix.dart' as matrix;

enum BackgroundNotificationEventClass { message, sticker, encrypted, other }

/// Produces a privacy-safe media-shape summary for background notification
/// diagnostics. Do not add event identifiers, content, filenames, or URIs.
String summarizeBackgroundNotificationMedia({
  required BackgroundNotificationEventClass eventClass,
  required String implementation,
  required bool routingEventMatches,
  required bool routingRoomMatches,
  required bool hasSdkAttachment,
  required bool hasPresentation,
  required matrix.MatrixEvent? matrixEvent,
  required int attachmentCount,
}) {
  final eventType = switch (matrixEvent?.type) {
    matrix.EventTypes.Message => 'message',
    matrix.EventTypes.Sticker => 'sticker',
    matrix.EventTypes.Encrypted => 'encrypted',
    _ => 'other',
  };
  final messageType = _messageTypeCategory(matrixEvent?.content['msgtype']);
  final hasUrl = matrixEvent?.content['url'] is String;
  final hasFile = matrixEvent?.content['file'] is Map;
  return 'background_notification_media '
      'event_class=${eventClass.name} implementation=$implementation '
      'event_type=$eventType '
      'message_type=$messageType has_sdk_attachment=$hasSdkAttachment '
      'has_url=$hasUrl has_file=$hasFile '
      'routing_event_match=$routingEventMatches '
      'routing_room_match=$routingRoomMatches '
      'has_presentation=$hasPresentation '
      'attachment_count=$attachmentCount';
}

String _messageTypeCategory(Object? messageType) {
  return switch (messageType) {
    'm.text' || 'm.notice' || 'm.emote' => 'text',
    'm.image' => 'image',
    'm.video' => 'video',
    'm.audio' => 'audio',
    'm.file' => 'file',
    String value when value.startsWith('m.') => 'standard_other',
    String() => 'custom',
    _ => 'missing',
  };
}
