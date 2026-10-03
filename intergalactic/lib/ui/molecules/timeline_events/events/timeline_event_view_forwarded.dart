import 'package:flutter/material.dart';
import 'package:intergalactic/client/matrix/components/message_forwarding/matrix_forwarded_message.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_reply.dart';
import 'package:intl/intl.dart';

/// Forward attribution, drawn to read like the reply attribution above a
/// message rather than as a separate labelled box.
///
/// Both occupy the same slot in the message layout and both answer
/// the same question - "where did this come from" - so they now share the
/// elbow-line shape outside bubbles and the tinted capsule inside them. The
/// forward glyph is what tells them apart at a glance; the shape no longer
/// has to.
///
/// It is still deliberately NOT interactive. A reply resolves to a real event
/// in this room and can jump to it; a forward creates no relation to a source
/// room or event, and the named author is a claim by the sender rather than a
/// verified one. Making it tappable would imply otherwise.
class TimelineEventViewForwarded extends StatelessWidget {
  const TimelineEventViewForwarded({
    super.key,
    required this.presentation,
    required this.bubbleMessages,
    required this.alignRight,
    this.bubbleColor,
    this.originalAuthorColor,
    this.avatarSize = 32,
  });

  final MatrixForwardedPresentation presentation;
  final bool bubbleMessages;
  final bool alignRight;
  final Color? bubbleColor;

  /// The colour the original author's name would carry if they were a member
  /// here, so a forward credits them in the same colour a reply would.
  final Color? originalAuthorColor;
  final double avatarSize;

  /// The attribution wording, localized.
  ///
  /// Only the DRAWN attribution belongs here.
  /// `ForwardedMessagePayload.headerFor` writes the same sentence into the
  /// message body for clients that do not understand the presentation
  /// envelope; that one is wire content read by other people's clients and
  /// must stay in one language, or the stripper stops matching it.
  String forwardedFromPrefix() => Intl.message(
    "Forwarded from ",
    name: "forwardedFromPrefix",
    desc:
        "Prefix before the claimed original author of a forwarded message. The "
        "author name and their Matrix ID follow as separately coloured spans, "
        "so the trailing space is part of the string",
  );

  String forwardedFromAuthor(String author) => Intl.message(
    "Forwarded from $author",
    name: "forwardedFromAuthor",
    args: [author],
    desc:
        "Attribution above a forwarded message, naming the author the sender "
        "claims it came from",
  );

  String forwardedSemanticsLabel(String label, String id) => Intl.message(
    "Forwarded message. Original author claimed by sender: $label, $id.",
    name: "forwardedSemanticsLabel",
    args: [label, id],
    desc:
        "Screen reader description of a forwarded message. The wording is "
        "deliberately hedged: the named author is the sender's claim rather "
        "than a verified fact",
  );

  String get _semanticsLabel => forwardedSemanticsLabel(
    presentation.originalAuthorLabel,
    presentation.originalAuthorId,
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: _semanticsLabel,
      excludeSemantics: true,
      child: bubbleMessages ? _bubble(context) : _inline(context),
    );
  }

  /// The non-bubble shape: the reply elbow, then the attribution on one line.
  ///
  /// The author's name and their Matrix ID are separate spans so that when the
  /// line runs out of room the ID ellipsises first. The ID is the disambiguator
  /// and the name is the thing being credited, so losing the tail of the ID
  /// costs less than losing the name.
  Widget _inline(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nameColor = AccessibilityScope.tokensOf(
      context,
    ).resolveIdentityTextColor(originalAuthorColor, scheme);
    final secondary = scheme.secondary;
    final body = Theme.of(context).textTheme.bodyMedium;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 45,
            child: SizedBox.expand(
              child: CustomPaint(
                painter: ReplyLinePainter2(
                  pathColor: secondary,
                  avatarSize: avatarSize,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 1, 4, 0),
            child: Icon(Icons.forward, size: 14, color: secondary),
          ),
          Flexible(
            child: RichText(
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: forwardedFromPrefix(),
                    style: body?.copyWith(color: secondary),
                  ),
                  TextSpan(
                    text: presentation.originalAuthorLabel,
                    style: body?.copyWith(color: nameColor),
                  ),
                  TextSpan(
                    text: ' (${presentation.originalAuthorId})',
                    style: body?.copyWith(color: secondary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The bubble shape: the same tinted capsule the reply attribution uses, so
  /// the two line up above their message instead of one being a box and the
  /// other a pill.
  Widget _bubble(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = bubbleColor ?? scheme.surfaceContainerLow;
    final nameColor = AccessibilityScope.tokensOf(context)
        .resolveIdentityTextColor(
          originalAuthorColor,
          scheme,
          background: background,
        );
    final crossAxisAlignment = alignRight
        ? CrossAxisAlignment.end
        : CrossAxisAlignment.start;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        alignRight ? 0 : avatarSize + 12,
        0,
        alignRight ? 28 : 0,
        4,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background.withValues(alpha: 0.54),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.24),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: crossAxisAlignment,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.forward, size: 14, color: nameColor),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      forwardedFromAuthor(presentation.originalAuthorLabel),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: nameColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                presentation.originalAuthorId,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: alignRight ? TextAlign.right : TextAlign.left,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
