import 'dart:math';

import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/matrix/components/threads/matrix_thread_timeline.dart';
import 'package:intergalactic/client/matrix/components/message_forwarding/matrix_forwarded_message.dart';
import 'package:intergalactic/client/matrix/extensions/matrix_event_extensions.dart';
import 'package:intergalactic/client/matrix/matrix_mxc_file_provider.dart';
import 'package:intergalactic/client/matrix/matrix_mxc_image_provider.dart';
import 'package:intergalactic/client/matrix/matrix_timeline.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_mixin_reactions.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_mixin_related.dart';
import 'package:intergalactic/client/timeline.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/ui/atoms/rich_text/matrix_html_parser.dart';
import 'package:intergalactic/utils/mime.dart';
import 'package:intergalactic/utils/text_utils.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as matrix;

import 'package:html/parser.dart' as html_parser;
import 'package:html_unescape/html_unescape.dart';

class MatrixTimelineEventMessage extends MatrixTimelineEvent
    with MatrixTimelineEventRelated, MatrixTimelineEventReactions
    implements TimelineEventMessage {
  MatrixTimelineEventMessage(super.event, {required super.client}) {
    attachments = _parseAnyAttachments();
  }

  matrix.Client get mx => client.getMatrixClient();

  @override
  late List<Attachment>? attachments;

  @override
  bool get editable => true;

  @override
  String? get body => event.plaintextBody;

  String get formattedBody =>
      event.formattedText != "" ? event.formattedText : event.plaintextBody;

  @override
  String? get bodyFormat =>
      event.content.tryGet<String>("format") ??
      "chat.commet.custom.matrix_plain";

  @override
  String get plainTextBody => event.plaintextBody;

  String _getPlaintextBody({Timeline? timeline}) {
    var e = getDisplayEvent(timeline);

    if (["m.file", "m.image", "m.video", "m.audio"].contains(e.messageType)) {
      var file = e.content["file"] is Map<String, dynamic>
          ? e.content['file'] as Map<String, dynamic>
          : null;
      if (e.content.containsKey("url") == false &&
          (file?.containsKey("url") != true)) {
        return e.plaintextBody;
      }

      if (e.content.containsKey("filename")) {
        if (e.content["filename"] == e.plaintextBody) {
          return "";
        }

        return e.plaintextBody;
      } else {
        return "";
      }
    }

    return e.plaintextBody;
  }

  String _getFormattedBody({Timeline? timeline}) {
    var e = getDisplayEvent(timeline);

    if (["m.file", "m.image", "m.video", "m.audio"].contains(e.messageType)) {
      return e.formattedText;
    }

    if (e.formattedText == "") {
      return e.plaintextBody;
    }

    return e.formattedText;
  }

  @override
  String getPlaintextBody(Timeline timeline) {
    var displayEvent = getDisplayEvent(timeline);

    return displayEvent.plaintextBody;
  }

  /// The visible body once a forward's fallback attribution is removed.
  ///
  /// A forward carries its attribution twice on purpose: in the presentation
  /// envelope, which this client draws above the message, and as a header line
  /// inside `body`, so a client that cannot read the envelope still sees who
  /// wrote it. Rendering the body verbatim printed the same sentence twice -
  /// and for a forward with no text of its own, the header WAS the whole
  /// message.
  ///
  /// Every render branch in [buildFormattedContent] goes through here,
  /// including the one that runs before the room is loaded. Three branches each
  /// remembering to strip is three chances to forget, and the branch that
  /// forgets looks exactly like the bug this exists to fix.
  static String visibleForwardedBody(
    MatrixForwardedPresentation? forwarded,
    String raw, {
    required bool html,
  }) {
    if (forwarded == null) {
      return raw;
    }

    return html
        ? forwarded.stripFallbackHeaderHtml(raw)
        : forwarded.stripFallbackHeader(raw);
  }

  @override
  Widget? buildFormattedContent({Timeline? timeline}) {
    final roomId = event.roomId;
    final room = roomId == null ? null : client.getRoom(roomId);
    final forwarded = MatrixForwardedPresentation.tryParse(this);
    if (room == null) {
      final plain = visibleForwardedBody(
        forwarded,
        _getPlaintextBody(timeline: timeline),
        html: false,
      );
      if (plain.isNotEmpty) {
        return PlaintextMessageBody(
          content: plain,
          clientIdentifier: client.identifier,
        );
      }

      return null;
    }

    var displayEvent = getDisplayEvent(timeline);
    bool isFormatted = displayEvent.content.tryGet<String>("format") != null;
    if (isFormatted) {
      final visible = visibleForwardedBody(
        forwarded,
        _getFormattedBody(timeline: timeline),
        html: true,
      );
      // Once the attribution is gone, a forwarded attachment has nothing left
      // to draw and the attachment stands on its own. Scoped to forwards so a
      // message with an empty formatted body keeps whatever it rendered before.
      if (forwarded != null && visible.trim().isEmpty) {
        return null;
      }

      return MatrixHtmlParser.parse(visible, client, room);
    } else {
      final plain = visibleForwardedBody(
        forwarded,
        _getPlaintextBody(timeline: timeline),
        html: false,
      );
      if (plain != "") {
        return PlaintextMessageBody(
          content: plain,
          clientIdentifier: client.identifier,
        );
      }
    }

    return null;
  }

  @override
  bool isEdited(Timeline timeline) {
    var e = event.getDisplayEvent(getTimeline(timeline)!);
    return e.eventId != event.eventId;
  }

  List<Attachment>? _parseAnyAttachments() {
    String filename = event.content.containsKey("filename")
        ? event.content["filename"] as String
        : event.body;
    final spoiler =
        event.content["chat.intergalactic.spoiler"] == true ||
        event.content["org.matrix.msc1767.spoiler"] == true ||
        event.content["fi.mau.spoiler"] == true;

    if (event.hasAttachment) {
      double? width = event.attachmentWidth;
      double? height = event.attachmentHeight;
      final attachmentMimeType = event.attachmentMimetype;
      final looksAudio = _attachmentLooksAudio(
        attachmentMimeType,
        filename,
        event.messageType,
      );

      Attachment? attachment;

      if (Mime.imageTypes.contains(attachmentMimeType)) {
        attachment = ImageAttachment(
          MatrixMxcImage(
            event.attachmentMxcUrl!,
            mx,
            blurhash: event.attachmentBlurhash,
            doThumbnail: event.hasThumbnail,
            doFullres: true,
            thumbnailHeight: event.thumbnailHeight != null
                ? min(700, event.thumbnailHeight!.toInt())
                : 700,
            // I noticed on linux, decoding really high res images would cause a flicker, so we will limit it to 1440p
            fullResHeight: PlatformUtils.isLinux
                ? (event.attachmentHeight != null
                      ? min(1440, event.attachmentHeight!.toInt())
                      : 1440)
                : null,
            autoLoadFullRes: !event.hasThumbnail,
            matrixEvent: event,
          ),
          MxcFileProvider(mx, event.attachmentMxcUrl!, event: event),
          mimeType: attachmentMimeType,
          width: width,
          fileSize: event.infoMap['size'] as int?,
          name: filename,
          spoiler: spoiler,
          height: height,
        );
      } else if (looksAudio) {
        attachment = AudioAttachment(
          MxcFileProvider(mx, event.attachmentMxcUrl!, event: event),
          name: filename,
          mimeType: attachmentMimeType,
          duration: event.attachmentDuration,
          spoiler: spoiler,
          fileSize: event.infoMap['size'] as int?,
        );
      } else if (Mime.videoTypes.contains(attachmentMimeType)) {
        // Only load videos if the event has finished sending, otherwise
        // matrix dart sdk gives us the video file when we ask for thumbnail
        if (event.status.isSending == false) {
          attachment = VideoAttachment(
            MxcFileProvider(mx, event.attachmentMxcUrl!, event: event),
            thumbnail: event.videoThumbnailUrl != null
                ? MatrixMxcImage(
                    event.videoThumbnailUrl!,
                    mx,
                    blurhash: event.attachmentBlurhash,
                    doFullres: false,
                    autoLoadFullRes: false,
                    doThumbnail: true,
                    matrixEvent: event,
                  )
                : null,
            name: filename,
            mimeType: attachmentMimeType,
            duration: event.attachmentDuration,
            width: width,
            fileSize: event.infoMap['size'] as int?,
            spoiler: spoiler,
            height: height,
          );
        }
      } else {
        attachment = FileAttachment(
          MxcFileProvider(mx, event.attachmentMxcUrl!, event: event),
          name: filename,
          mimeType: attachmentMimeType,
          spoiler: spoiler,
          fileSize: event.infoMap['size'] as int?,
        );
      }

      return List.from([attachment]);
    }

    return null;
  }

  bool _attachmentLooksAudio(
    String? mimeType,
    String filename,
    String messageType,
  ) {
    if (messageType == 'm.audio') {
      return true;
    }

    final normalizedMime = mimeType?.toLowerCase();
    if (normalizedMime != null &&
        (Mime.playableAudioTypes.contains(normalizedMime) ||
            normalizedMime.startsWith('audio/'))) {
      return true;
    }

    final lowerFilename = filename.toLowerCase();
    final extensionSeparator = lowerFilename.lastIndexOf('.');
    final extension = extensionSeparator == -1
        ? null
        : lowerFilename.substring(extensionSeparator + 1);
    final extensionMime = extension == null
        ? null
        : Mime.fromExtenstion(extension)?.toLowerCase();
    return extensionMime != null &&
        (Mime.playableAudioTypes.contains(extensionMime) ||
            extensionMime.startsWith('audio/'));
  }

  @override
  List<Uri>? getLinks({Timeline? timeline}) {
    var text = _getFormattedBody(timeline: timeline);
    var start = text.indexOf("<mx-reply>");
    var end = text.indexOf("</mx-reply>");

    if (start != -1 && end != -1 && start < end) {
      text = text.replaceRange(start, end, "");
    }

    // The formatted body is HTML, which entity-encodes `&` as `&amp;`.
    // TextUtils' URL regex does not match `;`, so a query string containing
    // `&` (routine on TikTok, YouTube, and most tracking links) truncated at
    // `&amp` and the request went out for a URL that was never the real one.
    // Unescaping first is a no-op on plain text, which is what this is when
    // the event carries no `formatted_body`.
    text = HtmlUnescape().convert(text);

    var foundLinks = TextUtils.findUrls(text);

    foundLinks?.removeWhere((element) => element.authority == "matrix.to");
    if (foundLinks?.isEmpty == true) {
      foundLinks = null;
    }

    return foundLinks;
  }

  matrix.Event getDisplayEvent(Timeline? tl) {
    var mx = getTimeline(tl);

    if (mx == null) return event;

    return event.getDisplayEvent(mx);
  }

  matrix.Timeline? getTimeline(Timeline? tl) {
    if (tl == null) return null;

    if (tl is MatrixThreadTimeline) {
      return tl.mainRoomTimeline.matrixTimeline;
    } else {
      return (tl as MatrixTimeline).matrixTimeline;
    }
  }
}

class PlaintextMessageBody extends StatelessWidget {
  const PlaintextMessageBody({
    required this.content,
    required this.clientIdentifier,
    super.key,
  });
  final String content;
  final String clientIdentifier;

  @override
  Widget build(BuildContext context) {
    var document = html_parser.parse(content);
    bool big = shouldDoBigEmoji(document);

    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: big ? 34 : null),
        children: TextUtils.linkifyString(
          content,
          context: context,
          clientId: clientIdentifier,
        ),
      ),
    );
  }
}
