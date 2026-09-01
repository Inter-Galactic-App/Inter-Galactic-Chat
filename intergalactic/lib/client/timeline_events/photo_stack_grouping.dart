import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/timeline.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_feature_related.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';

/// Shared rules for deciding when a burst of image messages is one photo stack.
///
/// The timeline folds a run of bare image uploads from a single sender into one
/// stacked bubble, and the notification pipeline reuses these rules so a burst
/// that renders as one bubble also raises one notification instead of one per
/// photo. Keeping the predicate here stops the two from drifting apart.
class PhotoStackGrouping {
  /// How far apart two image messages may be and still belong to one stack.
  static const Duration window = Duration(minutes: 2);

  /// The lone [ImageAttachment] on [event], or null when the event is not a
  /// message carrying exactly one image.
  static ImageAttachment? singleImageAttachment(TimelineEvent? event) {
    if (event is! TimelineEventMessage) {
      return null;
    }

    final attachments = event.attachments;
    if (attachments == null || attachments.length != 1) {
      return null;
    }

    final attachment = attachments.single;
    return attachment is ImageAttachment ? attachment : null;
  }

  /// Whether [body] carries no message of its own, which is what clients emit
  /// for a plain image upload: an empty body, the filename repeated, or
  /// something that just ends in an image extension.
  static final RegExp _imageExtensionSuffix = RegExp(
    r'\.(avif|bmp|gif|heic|heif|jpe?g|png|webp)$',
    caseSensitive: false,
  );

  static bool looksLikeGeneratedImageBody(String? body, String attachmentName) {
    final normalizedBody = body?.trim();
    final normalizedAttachmentName = attachmentName.trim();
    if (normalizedBody == null || normalizedBody.isEmpty) {
      return true;
    }

    // A blank attachment name says nothing about the body. Only treat the body
    // as generated when it actually echoes the filename -- otherwise a real
    // caption on an attachment with no name would be folded into a stack and,
    // on the notification path, suppressed entirely.
    if (normalizedAttachmentName.isNotEmpty &&
        normalizedBody == normalizedAttachmentName) {
      return true;
    }

    return _imageExtensionSuffix.hasMatch(normalizedBody);
  }

  /// Whether [event] can take part in a photo stack at all, ignoring its
  /// neighbours. A captioned image, a reply, or anything that is not a single
  /// image is left on its own.
  static bool isStackable(TimelineEvent event) {
    final attachment = singleImageAttachment(event);
    if (attachment == null) {
      return false;
    }

    final TimelineEventFeatureRelated? related =
        event is TimelineEventFeatureRelated
        ? event as TimelineEventFeatureRelated
        : null;
    if (related?.relationshipType == EventRelationshipType.reply) {
      return false;
    }

    return looksLikeGeneratedImageBody(
      (event as TimelineEventMessage).body,
      attachment.name,
    );
  }
}
