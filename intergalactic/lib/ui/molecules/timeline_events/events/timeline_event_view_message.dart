import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/threads/thread_component.dart';
import 'package:intergalactic/client/components/url_preview/url_preview_component.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_encrypted.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_feature_reactions.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_feature_related.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_sticker.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_unknown.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/custom_theme_definition.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/atoms/rich_text/matrix_html_parser.dart';
import 'package:intergalactic/ui/molecules/read_indicator.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_attachments.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_reactions.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_reply.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_sticker.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_thread.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_url_previews.dart';
import 'package:intergalactic/ui/molecules/timeline_events/layouts/timeline_event_layout_message.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_diagnostics_visibility.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_event_layout.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_event_menu.dart';
import 'package:intergalactic/ui/molecules/user_list.dart';
import 'package:intergalactic/ui/organisms/user_profile/user_profile.dart';
import 'package:intergalactic/utils/text_utils.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:intl/intl.dart' as intl;

import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class TimelineEventViewMessage extends StatefulWidget {
  const TimelineEventViewMessage(
      {super.key,
      this.timeline,
      this.room,
      this.initialEvent,
      this.isThreadTimeline = false,
      this.overrideShowSender = false,
      this.jumpToEvent,
      this.readReceipts = const [],
      this.onReadReceiptsTapped,
      this.detailed = false,
      this.previewMedia = false,
      this.suppressBubble = false,
      this.setEditingEvent,
      this.setReplyingEvent,
      required this.initialIndex});

  final Function(String eventId)? jumpToEvent;

  final Timeline? timeline;
  final TimelineEvent? initialEvent;
  final Room? room;
  final List<String> readReceipts;
  final int initialIndex;
  final bool overrideShowSender;
  final bool detailed;
  final bool isThreadTimeline;
  final bool previewMedia;
  final bool suppressBubble;
  final Function()? onReadReceiptsTapped;
  final Function(TimelineEvent event)? setEditingEvent;
  final Function(TimelineEvent event)? setReplyingEvent;

  @override
  State<TimelineEventViewMessage> createState() =>
      _TimelineEventViewMessageState();
}

class _TimelineEventViewMessageState extends State<TimelineEventViewMessage>
    implements TimelineEventViewWidget {
  bool _ready = false;
  late String senderName;
  late String senderId;
  late Color senderColor;

  String get messageFailedToDecrypt => Intl.message("Failed to decrypt event",
      desc: "Placeholde text for when a message fails to decrypt",
      name: "messageFailedToDecrypt");

  GlobalKey reactionsKey = GlobalKey();
  GlobalKey urlPreviewsKey = GlobalKey();

  Widget? formattedContent;
  String? body;
  ImageProvider? senderAvatar;
  List<Attachment>? attachments;
  List<PhotoStackAttachmentItem>? photoStackAttachments;
  bool hideAsPhotoStackChild = false;
  ImageProvider? sticker;
  bool hasReactions = false;
  bool isInResponse = false;
  bool showSender = false;
  bool emojiOnlyMessage = false;
  late String eventId;
  late String currentUserIdentifier;
  late DateTime sentTime;

  UrlPreviewComponent? previewComponent;
  bool doUrlPreview = false;

  ThreadsComponent? threadComponent;
  bool isHeadOfThread = false;

  bool get showTimelineDiagnostics => shouldShowTimelineDiagnostics(
        developerMode: preferences.developerMode.value,
        showTimelineDiagnostics: preferences.showTimelineDiagnostics.value,
      );

  int index = 0;

  bool edited = false;

  @override
  void initState() {
    var room = widget.room ?? widget.timeline?.room;
    var client = room?.client;
    currentUserIdentifier = client?.self?.identifier ?? '';
    if (client == null) {
      super.initState();
      return;
    }
    _ready = true;

    if (widget.previewMedia) {
      previewComponent = client.getComponent<UrlPreviewComponent>();
    }

    if (!widget.isThreadTimeline) {
      threadComponent = client.getComponent<ThreadsComponent>();
    }

    if (widget.timeline != null) {
      loadEventState(widget.initialIndex);
    }

    if (widget.initialEvent != null) {
      loadStateFromEvent(widget.initialEvent!);
    }
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const SizedBox.shrink();
    }

    if (hideAsPhotoStackChild) {
      return const SizedBox.shrink();
    }

    var room = widget.room ?? widget.timeline?.room;
    final isSelf = senderId == room?.client.self?.identifier;
    final alignRight = isSelf && preferences.alignSentMessagesRight.value;
    final bubbleColorHex = isSelf
        ? preferences.getEffectiveSentMessageBubbleColor(room?.localId)
        : preferences.getEffectiveReceivedMessageBubbleColor(room?.localId);
    final bubbleMessages = preferences.bubbleMessages.value &&
        !emojiOnlyMessage &&
        !widget.suppressBubble;
    final showSenderHeader = alignRight && bubbleMessages ? false : showSender;
    final showAvatar = bubbleMessages && !alignRight
        ? shouldShowBubbleAvatar(index)
        : showSenderHeader;
    return TimelineEventLayoutMessage(
      senderName: senderName,
      senderColor: senderColor,
      senderAvatar: senderAvatar,
      showSender: showSenderHeader,
      showAvatar: showAvatar,
      bubbleMessages: bubbleMessages,
      alignRight: alignRight,
      bubbleColor:
          bubbleColorHex == null ? null : parseHexColor(bubbleColorHex),
      formattedContent: formattedContent,
      messageTextScale: _messageTextScale,
      timestamp: timestampToString(sentTime),
      edited: edited,
      avatarBuilder: (child) {
        var room = widget.room ?? widget.timeline?.room;

        if (room != null) {
          return RoomMemberList.userContextMenu(context,
              userId: senderId,
              userDisplayName: senderName,
              room: room,
              child: child,
              isSelf: senderId == room.client.self!.identifier);
        }

        return child;
      },
      attachments: attachments != null
          ? photoStackAttachments != null
              ? PhotoStackAttachmentView(
                  items: photoStackAttachments!,
                  timeline: widget.timeline!,
                  previewMedia: widget.previewMedia,
                  isThreadTimeline: widget.isThreadTimeline,
                  setEditingEvent: widget.setEditingEvent,
                  setReplyingEvent: widget.setReplyingEvent,
                )
              : TimelineEventViewAttachments(
                  attachments: attachments!,
                  previewMedia: widget.previewMedia,
                  alignRight: alignRight,
                  timeline: widget.timeline,
                  event: widget.timeline?.events[index] ?? widget.initialEvent,
                  isThreadTimeline: widget.isThreadTimeline,
                  setEditingEvent: widget.setEditingEvent,
                  setReplyingEvent: widget.setReplyingEvent,
                )
          : null,
      readReceipts: room != null
          ? ReadIndicator(
              room: room,
              users: widget.readReceipts,
              onTap: widget.onReadReceiptsTapped,
            )
          : null,
      sticker: sticker != null
          ? TimelineEventViewSticker(
              sticker!,
              stickerName: body,
              previewMedia: widget.previewMedia,
            )
          : null,
      inResponseTo: isInResponse && widget.timeline != null
          ? TimelineEventViewReply(
              timeline: widget.timeline!,
              index: index,
              jumpToEvent: widget.jumpToEvent,
              bubbleMessages: bubbleMessages,
              alignRight: alignRight,
              bubbleColor:
                  bubbleColorHex == null ? null : parseHexColor(bubbleColorHex),
            )
          : null,
      reactions: hasReactions && widget.timeline != null
          ? TimelineEventViewReactions(
              key: reactionsKey,
              timeline: widget.timeline!,
              initialIndex: index)
          : null,
      urlPreviews:
          previewComponent != null && doUrlPreview && widget.timeline != null
              ? TimelineEventViewUrlPreviews(
                  initialIndex: index,
                  timeline: widget.timeline!,
                  component: previewComponent!,
                  bubbleMessages: bubbleMessages,
                  alignRight: alignRight,
                  key: urlPreviewsKey,
                )
              : null,
      thread: isHeadOfThread && widget.timeline != null
          ? TimelineEventViewThread(
              initialIndex: index,
              timeline: widget.timeline!,
              component: threadComponent!,
              alignRight: alignRight)
          : null,
      onAvatarTapped: () {
        final client = widget.timeline?.client ?? widget.room?.client;
        if (client == null) {
          return;
        }

        UserProfile.show(context, client: client, userId: senderId);
      },
      onDoubleTap: applyPrimaryQuickReaction,
    );
  }

  double get _messageTextScale => BuildConfig.DESKTOP &&
          !Layout.mobile &&
          preferences.desktopSmallWindowMode.value
      ? 1.5
      : 1.0;

  void applyPrimaryQuickReaction() {
    final timeline = widget.timeline;
    if (timeline == null) {
      return;
    }

    TimelineEvent? event;
    for (final candidate in timeline.events) {
      if (candidate.eventId == eventId) {
        event = candidate;
        break;
      }
    }
    if (event == null) {
      return;
    }

    final menu = TimelineEventMenu(
      timeline: timeline,
      event: event,
      setEditingEvent: widget.setEditingEvent,
      setReplyingEvent: widget.setReplyingEvent,
      isThreadTimeline: widget.isThreadTimeline,
    );

    if (menu.addReactionAction == null || menu.quickReactions.isEmpty) {
      return;
    }

    timeline.room.addReaction(event, menu.quickReactions.first);
  }

  @override
  void update(int newIndex) {
    setState(() {
      loadEventState(newIndex);
    });

    for (var key in [reactionsKey, urlPreviewsKey]) {
      if (key.currentState is TimelineEventViewWidget) {
        (key.currentState as TimelineEventViewWidget).update(newIndex);
      }
    }
  }

  void loadEventState(var eventIndex) {
    index = eventIndex;
    if (widget.timeline != null) {
      var event = widget.timeline!.events[eventIndex];
      loadStateFromEvent(event);
    }
  }

  void loadStateFromEvent(TimelineEvent event) {
    formattedContent = null;
    body = null;
    attachments = null;
    sticker = null;
    hasReactions = false;
    isInResponse = false;
    doUrlPreview = false;
    edited = false;
    isHeadOfThread = false;
    hideAsPhotoStackChild = false;
    photoStackAttachments = null;
    emojiOnlyMessage = false;
    showSender = shouldShowSender(index);
    var room = widget.room ?? widget.timeline?.room;

    var sender = room!.getMemberOrFallback(event.senderId);
    eventId = event.eventId;

    senderId = sender.identifier;
    senderName = sender.displayName;
    senderAvatar = sender.avatar;
    senderColor = sender.defaultColor;

    sentTime = event.originServerTs;

    if (widget.timeline != null) {
      if (event is TimelineEventFeatureReactions) {
        hasReactions = (event as TimelineEventFeatureReactions)
            .hasReactions(widget.timeline!);
      }

      isHeadOfThread =
          threadComponent?.isHeadOfThread(event, widget.timeline!) ?? false;

      if (event is TimelineEventMessage) {
        edited = event.isEdited(widget.timeline!);
      }
    } else {
      edited = false;
      isHeadOfThread = false;
      hasReactions = false;
    }

    if (event is TimelineEventSticker) {
      sticker = event.stickerImage;
      body = event.plainTextBody;
    }

    isInResponse = event is TimelineEventFeatureRelated &&
        (event as TimelineEventFeatureRelated).relationshipType ==
            EventRelationshipType.reply;

    if (event is TimelineEventEncrypted) {
      formattedContent = tiamat.Text.error(messageFailedToDecrypt);
    }

    if (event is! TimelineEventMessage) {
      return;
    }

    var content = event.buildFormattedContent(timeline: widget.timeline);
    if (content == null) {
      formattedContent = null;
    } else {
      formattedContent = Container(key: GlobalKey(), child: content);
    }

    attachments = event.attachments;
    final photoStack = _resolvePhotoStack(event);
    hideAsPhotoStackChild = photoStack.hideChild;
    photoStackAttachments = photoStack.attachments;

    doUrlPreview = widget.timeline != null &&
        previewComponent?.shouldGetPreviewDataForTimelineEvent(
                widget.timeline!, event) ==
            true &&
        event.getLinks(timeline: widget.timeline!)?.isEmpty == false;
    final knownPreviewData = doUrlPreview && widget.timeline != null
        ? previewComponent?.getCachedPreview(widget.timeline!, event)
        : null;

    emojiOnlyMessage = _isEmojiOnlyTextMessage(event);

    if (doUrlPreview &&
        knownPreviewData != null &&
        knownPreviewData != UrlPreviewComponent.invalidPreviewData &&
        _messageIsOnlyPreviewLinks(event)) {
      formattedContent = null;
    }
  }

  bool _isEmojiOnlyTextMessage(TimelineEventMessage event) {
    if (edited ||
        attachments?.isNotEmpty == true ||
        photoStackAttachments?.isNotEmpty == true ||
        sticker != null ||
        doUrlPreview) {
      return false;
    }

    return TextUtils.isEmojiOnly(_plainTextBodyFor(event)) ||
        _isEmojiOnlyFormattedMessage(event);
  }

  bool _isEmojiOnlyFormattedMessage(TimelineEventMessage event) {
    final formattedBody = event.formattedBody;
    if (formattedBody == null ||
        formattedBody.trim().isEmpty ||
        !formattedBody.contains('data-mx-emoticon')) {
      return false;
    }

    return shouldDoBigEmoji(html_parser.parse(formattedBody));
  }

  String _plainTextBodyFor(TimelineEventMessage event) {
    final timeline = widget.timeline;
    return timeline == null
        ? event.plainTextBody
        : event.getPlaintextBody(timeline);
  }

  bool _messageIsOnlyPreviewLinks(TimelineEventMessage event) {
    final timeline = widget.timeline;
    if (timeline == null) {
      return false;
    }

    final links = event.getLinks(timeline: timeline);
    if (links == null || links.isEmpty) {
      return false;
    }

    var remaining = event.getPlaintextBody(timeline).trim();
    for (final link in links) {
      remaining = remaining.replaceAll(link.toString(), '');
    }

    return remaining.trim().isEmpty;
  }

  _PhotoStackResolution _resolvePhotoStack(TimelineEventMessage event) {
    final timeline = widget.timeline;
    if (timeline == null || !widget.previewMedia) {
      return const _PhotoStackResolution();
    }

    if (!_isStackablePhotoEvent(event, timeline)) {
      return const _PhotoStackResolution();
    }

    final events = timeline.events;
    var start = index;
    var end = index;

    while (start + 1 < events.length &&
        _canStackWith(event, events[start + 1], timeline)) {
      start++;
    }

    while (end - 1 >= 0 && _canStackWith(event, events[end - 1], timeline)) {
      end--;
    }

    if (start == end) {
      return const _PhotoStackResolution();
    }

    final anchor = end;
    if (index != anchor) {
      return const _PhotoStackResolution(hideChild: true);
    }

    final groupIndices = [
      for (var groupIndex = end; groupIndex <= start; groupIndex++) groupIndex,
    ]..sort((left, right) {
        final leftTime = events[left].originServerTs;
        final rightTime = events[right].originServerTs;
        final timeCompare = leftTime.compareTo(rightTime);
        if (timeCompare != 0) {
          return timeCompare;
        }

        return right.compareTo(left);
      });

    final images = groupIndices
        .map((groupIndex) {
          final groupEvent = events[groupIndex];
          final attachment = _singleImageAttachment(groupEvent);
          if (groupEvent is! TimelineEventMessage || attachment == null) {
            return null;
          }

          return PhotoStackAttachmentItem(
            event: groupEvent,
            index: groupIndex,
            attachment: attachment,
          );
        })
        .whereType<PhotoStackAttachmentItem>()
        .toList(growable: false);

    if (images.length < 2) {
      return const _PhotoStackResolution();
    }

    return _PhotoStackResolution(attachments: images);
  }

  bool _canStackWith(
    TimelineEventMessage anchor,
    TimelineEvent candidate,
    Timeline timeline,
  ) {
    if (candidate is! TimelineEventMessage) {
      return false;
    }

    if (candidate.senderId != anchor.senderId) {
      return false;
    }

    final difference =
        candidate.originServerTs.difference(anchor.originServerTs).abs();
    if (difference > const Duration(minutes: 2)) {
      return false;
    }

    return _isStackablePhotoEvent(candidate, timeline);
  }

  bool _isStackablePhotoEvent(TimelineEventMessage event, Timeline timeline) {
    if (_singleImageAttachment(event) == null) {
      return false;
    }

    final TimelineEventFeatureRelated? relatedEvent =
        event is TimelineEventFeatureRelated
            ? event as TimelineEventFeatureRelated
            : null;
    if (relatedEvent?.relationshipType == EventRelationshipType.reply) {
      return false;
    }

    if (threadComponent?.isHeadOfThread(event, timeline) == true) {
      return false;
    }

    final body = event.body?.trim();
    final attachmentName = _singleImageAttachment(event)?.name.trim();
    return body == null ||
        body.isEmpty ||
        attachmentName == null ||
        body == attachmentName;
  }

  ImageAttachment? _singleImageAttachment(TimelineEvent event) {
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

  String timestampToString(DateTime time) {
    if (PlatformUtils.isAndroid) {
      // I think this only works properly on android and ios, there is no documented
      // Behaviour for other platforms
      var use24 = MediaQuery.of(context).alwaysUse24HourFormat;

      if (widget.detailed) {
        if (use24) {
          return intl.DateFormat.yMMMMd().add_Hms().format(time.toLocal());
        } else {
          return intl.DateFormat.yMMMMd().add_jms().format(time.toLocal());
        }
      } else {
        if (use24) {
          return intl.DateFormat.Hm().format(time.toLocal());
        } else {
          return intl.DateFormat.jm().format(time.toLocal());
        }
      }
    }

    if (widget.detailed) {
      return TextUtils.timestampToLocalizedTimeSpecific(time, context);
    } else {
      return MaterialLocalizations.of(context)
          .formatTimeOfDay(TimeOfDay.fromDateTime(time));
    }
  }

  bool shouldShowSender(int index) {
    if (widget.overrideShowSender) return true;
    if (widget.timeline == null) return true;

    TimelineEvent? prevEvent;
    for (int i = 1; i < 5; i++) {
      int testIndex = index + i;
      if (widget.timeline!.events.length <= testIndex) {
        return true;
      }
      var event = widget.timeline!.events[testIndex];

      if (showTimelineDiagnostics) {
        prevEvent = event;
        break;
      }

      if (event is! TimelineEventUnknown) {
        prevEvent = event;
        break;
      }
    }

    if (prevEvent == null) {
      return true;
    }

    final thisEvent = widget.timeline!.events[index];
    if (thisEvent is! TimelineEventMessage &&
        thisEvent is! TimelineEventSticker &&
        thisEvent is! TimelineEventEncrypted) {
      return false;
    }

    if (thisEvent is TimelineEventFeatureRelated) {
      if ((thisEvent as TimelineEventFeatureRelated).relationshipType ==
          EventRelationshipType.reply) {
        return true;
      }
    }

    if (prevEvent is! TimelineEventMessage &&
        prevEvent is! TimelineEventEncrypted &&
        prevEvent is! TimelineEventSticker) {
      return true;
    }

    if (widget.timeline!.isEventRedacted(prevEvent)) {
      return true;
    }

    if (widget.isThreadTimeline == false &&
        threadComponent?.isEventInResponseToThread(
                prevEvent, widget.timeline!) ==
            true) {
      return true;
    }

    if (thisEvent.originServerTs
            .difference(prevEvent.originServerTs)
            .inMinutes >
        1) return true;

    return thisEvent.senderId != prevEvent.senderId;
  }

  bool shouldShowBubbleAvatar(int index) {
    if (widget.overrideShowSender) return true;
    if (widget.timeline == null) return true;

    TimelineEvent? nextEvent;
    for (int i = 1; i < 5; i++) {
      final testIndex = index - i;
      if (testIndex < 0) {
        return true;
      }
      final event = widget.timeline!.events[testIndex];

      if (showTimelineDiagnostics) {
        nextEvent = event;
        break;
      }

      if (event is! TimelineEventUnknown) {
        nextEvent = event;
        break;
      }
    }

    if (nextEvent == null) {
      return true;
    }

    final thisEvent = widget.timeline!.events[index];
    if (thisEvent is! TimelineEventMessage &&
        thisEvent is! TimelineEventSticker &&
        thisEvent is! TimelineEventEncrypted) {
      return false;
    }

    if (nextEvent is! TimelineEventMessage &&
        nextEvent is! TimelineEventEncrypted &&
        nextEvent is! TimelineEventSticker) {
      return true;
    }

    if (widget.timeline!.isEventRedacted(nextEvent)) {
      return true;
    }

    if (widget.isThreadTimeline == false &&
        threadComponent?.isEventInResponseToThread(
                nextEvent, widget.timeline!) ==
            true) {
      return true;
    }

    if (nextEvent is TimelineEventFeatureRelated) {
      if ((nextEvent as TimelineEventFeatureRelated).relationshipType ==
          EventRelationshipType.reply) {
        return true;
      }
    }

    if (nextEvent.originServerTs
            .difference(thisEvent.originServerTs)
            .inMinutes
            .abs() >
        1) return true;

    return thisEvent.senderId != nextEvent.senderId;
  }
}

class _PhotoStackResolution {
  const _PhotoStackResolution({this.attachments, this.hideChild = false});

  final List<PhotoStackAttachmentItem>? attachments;
  final bool hideChild;
}
