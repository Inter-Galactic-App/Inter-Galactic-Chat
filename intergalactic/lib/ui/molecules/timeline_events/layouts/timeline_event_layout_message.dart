import 'package:intergalactic/diagnostic/benchmark_values.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class TimelineEventLayoutMessage extends StatelessWidget {
  const TimelineEventLayoutMessage(
      {super.key,
      required this.senderName,
      required this.senderColor,
      this.senderAvatar,
      this.formattedContent,
      this.attachments,
      this.inResponseTo,
      this.reactions,
      this.timestamp,
      this.sticker,
      this.thread,
      this.urlPreviews,
      this.readReceipts,
      this.onAvatarTapped,
      this.onDoubleTap,
      this.edited = false,
      this.avatarSize = 32,
      this.avatarBuilder,
      this.showSender = true,
      this.showAvatar = true,
      this.bubbleMessages = false,
      this.alignRight = false,
      this.messageTextScale = 1,
      this.pendingStatusLabel,
      this.pendingStatusSemanticLabel,
      this.pendingStatusTone = TimelineEventPendingStatusTone.progress,
      this.bubbleColor});
  final String senderName;
  final Color senderColor;
  final ImageProvider? senderAvatar;
  final Widget? formattedContent;
  final Widget? attachments;
  final Widget? inResponseTo;
  final Widget? reactions;
  final Widget? urlPreviews;
  final Widget? thread;
  final Widget? sticker;
  final Widget? readReceipts;
  final bool showSender;
  final bool showAvatar;
  final bool edited;
  final String? timestamp;
  final Function()? onAvatarTapped;
  final VoidCallback? onDoubleTap;
  final Widget Function(Widget child)? avatarBuilder;

  final double avatarSize;
  final bool bubbleMessages;
  final bool alignRight;
  final double messageTextScale;
  final String? pendingStatusLabel;
  final String? pendingStatusSemanticLabel;
  final TimelineEventPendingStatusTone? pendingStatusTone;
  final Color? bubbleColor;

  String get messageEditedMarker => Intl.message("(Edited)",
      name: "messageEditedMarker",
      desc: "Short text to mark that a message has been edited");

  @override
  Widget build(BuildContext context) {
    BenchmarkValues.numTimelineMessageBodyBuilt += 1;
    final messageAlignment =
        alignRight ? Alignment.centerRight : Alignment.centerLeft;
    final messageCrossAxisAlignment =
        alignRight ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final readReceiptsWidth = bubbleMessages ? 28.0 : 35.0;
    final textContent = scaledMessageText(
      context,
      Column(
        crossAxisAlignment: messageCrossAxisAlignment,
        children: [
          if (formattedContent != null)
            RepaintBoundary(child: formattedContent!),
          if (edited) tiamat.Text.labelLow(messageEditedMarker),
        ],
      ),
    );
    final textBody = Column(
      crossAxisAlignment: messageCrossAxisAlignment,
      children: [
        textContent,
      ],
    );
    final status = pendingStatus(context);
    final standardMessageBody = Column(
      crossAxisAlignment: messageCrossAxisAlignment,
      children: [
        textContent,
        if (attachments != null) attachments!,
        if (sticker != null) sticker!,
        if (urlPreviews != null) urlPreviews!,
        if (status != null) status,
        if (reactions != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
            child: reactions!,
          ),
      ],
    );
    final hasTextBubble = formattedContent != null || edited;
    final messageBody = bubbleMessages
        ? Column(
            crossAxisAlignment: messageCrossAxisAlignment,
            children: [
              if (hasTextBubble) messageContent(context, textBody),
              if (attachments != null)
                Padding(
                  padding: EdgeInsets.only(top: hasTextBubble ? 4 : 0),
                  child: attachments!,
                ),
              if (sticker != null)
                Padding(
                  padding: EdgeInsets.only(top: hasTextBubble ? 4 : 0),
                  child: sticker!,
                ),
              if (urlPreviews != null)
                Padding(
                  padding: EdgeInsets.only(top: hasTextBubble ? 4 : 0),
                  child: urlPreviews!,
                ),
              if (status != null) status,
              if (reactions != null)
                Transform.translate(
                  offset: Offset(alignRight ? -8 : 8, -3),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 2),
                    child: reactions!,
                  ),
                ),
            ],
          )
        : messageContent(context, standardMessageBody);

    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        alignRight ? 8 : 16,
        2,
        alignRight ? 16 : 8,
        2,
      ),
      child: Column(
        children: [
          if (inResponseTo != null)
            Align(
              alignment: messageAlignment,
              child: inResponseTo!,
            ),
          Row(
            crossAxisAlignment: bubbleMessages
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (!alignRight) avatar(),
              Flexible(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(alignRight ? 0 : 12, 0, 0, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (showSender) senderHeader(context),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: alignRight
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.spaceBetween,
                        mainAxisSize: MainAxisSize.max,
                        children: alignRight
                            ? [
                                SizedBox(
                                  width: readReceiptsWidth,
                                  child: readReceipts,
                                ),
                                Flexible(
                                  child: Align(
                                    alignment: messageAlignment,
                                    child: messageBody,
                                  ),
                                ),
                              ]
                            : [
                                Flexible(
                                  child: Align(
                                    alignment: messageAlignment,
                                    child: messageBody,
                                  ),
                                ),
                                SizedBox(
                                  width: readReceiptsWidth,
                                  child: readReceipts,
                                )
                              ],
                      )
                    ],
                  ),
                ),
              )
            ],
          ),
          if (thread != null) thread!,
        ],
      ),
    );

    if (onDoubleTap == null) {
      return content;
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: onDoubleTap,
      child: content,
    );
  }

  Widget scaledMessageText(BuildContext context, Widget child) {
    if (messageTextScale == 1) {
      return child;
    }

    final mediaQuery = MediaQuery.of(context);
    final baseScale = mediaQuery.textScaler.scale(1);
    return MediaQuery(
      data: mediaQuery.copyWith(
        textScaler: TextScaler.linear(baseScale * messageTextScale),
      ),
      child: child,
    );
  }

  Widget senderHeader(BuildContext context) {
    if (alignRight) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (timestamp != null) tiamat.Text.labelLow(timestamp!),
          if (timestamp != null) const SizedBox(width: 8),
          name(context),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        name(context),
        if (timestamp != null) tiamat.Text.labelLow(timestamp!),
      ],
    );
  }

  Widget messageContent(BuildContext context, Widget messageBody) {
    if (!bubbleMessages) {
      return messageBody;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bubbleColor ?? Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: 0.08,
            ),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          14,
          11,
          14,
          12,
        ),
        child: messageBody,
      ),
    );
  }

  Widget? pendingStatus(BuildContext context) {
    final label = pendingStatusLabel;
    final tone = pendingStatusTone;
    if (label == null || tone == null) {
      return null;
    }

    final colorScheme = Theme.of(context).colorScheme;
    final statusColor = switch (tone) {
      TimelineEventPendingStatusTone.error => colorScheme.error,
      TimelineEventPendingStatusTone.success => colorScheme.primary,
      TimelineEventPendingStatusTone.progress => colorScheme.onSurfaceVariant,
      TimelineEventPendingStatusTone.muted => colorScheme.onSurfaceVariant,
    };
    final backgroundColor = tone == TimelineEventPendingStatusTone.error
        ? colorScheme.errorContainer.withValues(alpha: 0.36)
        : colorScheme.surfaceContainerHighest.withValues(alpha: 0.72);
    final borderColor = statusColor.withValues(
      alpha: tone == TimelineEventPendingStatusTone.error ? 0.28 : 0.18,
    );
    final reduceMotion = InterGalacticMotion.shouldReduce(context);
    final chip = DecoratedBox(
      key: ValueKey(
        'pending-status-${tone.name}-$label',
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 7,
          vertical: 3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pendingStatusIndicator(statusColor, tone),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 136),
              child: tiamat.Text.labelLow(
                label,
                color: statusColor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softwrap: false,
              ),
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: SelectionContainer.disabled(
        child: Semantics(
          container: true,
          liveRegion: true,
          label: pendingStatusSemanticLabel ?? label,
          child: ExcludeSemantics(
            child: AnimatedSwitcher(
              duration: InterGalacticMotion.duration(
                context,
                InterGalacticMotion.shortEmphasis,
              ),
              reverseDuration: InterGalacticMotion.duration(
                context,
                InterGalacticMotion.short,
              ),
              switchInCurve: InterGalacticMotion.standardOut,
              switchOutCurve: InterGalacticMotion.standardIn,
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                );
              },
              transitionBuilder: (child, animation) {
                if (reduceMotion) {
                  return child;
                }
                final curved = CurvedAnimation(
                  parent: animation,
                  curve: InterGalacticMotion.standardOut,
                );
                return FadeTransition(
                  opacity: curved,
                  child: ScaleTransition(
                    alignment: Alignment.centerLeft,
                    scale: Tween<double>(
                      begin: 0.98,
                      end: 1,
                    ).animate(curved),
                    child: child,
                  ),
                );
              },
              child: chip,
            ),
          ),
        ),
      ),
    );
  }

  Widget _pendingStatusIndicator(
    Color statusColor,
    TimelineEventPendingStatusTone tone,
  ) {
    switch (tone) {
      case TimelineEventPendingStatusTone.error:
        return Icon(
          Icons.error_outline,
          size: 13,
          color: statusColor,
        );
      case TimelineEventPendingStatusTone.success:
        return Icon(
          Icons.check_circle_outline,
          size: 13,
          color: statusColor,
        );
      case TimelineEventPendingStatusTone.muted:
        return Icon(
          Icons.cancel_outlined,
          size: 13,
          color: statusColor,
        );
      case TimelineEventPendingStatusTone.progress:
        return SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.7,
            color: statusColor,
          ),
        );
    }
  }

  Widget name(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nameColor = AccessibilityScope.tokensOf(context)
        .resolveIdentityTextColor(senderColor, scheme);

    return SelectionContainer.disabled(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onAvatarTapped,
          child: tiamat.Text.name(
            senderName,
            color: nameColor,
          ),
        ),
      ),
    );
  }

  Widget avatar() {
    Widget result = SizedBox(
      width: avatarSize,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onAvatarTapped,
          child: tiamat.Avatar(
            radius: avatarSize / 2,
            image: senderAvatar,
            placeholderText: senderName,
            placeholderColor: senderColor,
            isPadding: showAvatar == false,
          ),
        ),
      ),
    );

    if (avatarBuilder != null) {
      result = avatarBuilder!.call(result);
    }

    return result;
  }
}

enum TimelineEventPendingStatusTone {
  progress,
  success,
  error,
  muted,
}
