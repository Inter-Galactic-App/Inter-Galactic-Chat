import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/components/emoticon/dynamic_emoticon_pack.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_component.dart';
import 'package:intergalactic/client/components/emoticon_recent/recent_emoticon_component.dart';
import 'package:intergalactic/client/components/message_effects/message_effect_component.dart';
import 'package:intergalactic/client/components/photo_album_room/photo_album_room_component.dart';
import 'package:intergalactic/client/components/pinned_messages/pinned_messages_component.dart';
import 'package:intergalactic/client/components/polls/poll_component.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/components/push_notification/notification_manager.dart';
import 'package:intergalactic/client/matrix/components/message_forwarding/matrix_message_forwarder.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/vodozemac_single_flight.dart';
import 'package:intergalactic/client/timeline.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_emote.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_encrypted.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_sticker.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/atoms/code_block.dart';
import 'package:intergalactic/ui/molecules/emoji_picker.dart';
import 'package:intergalactic/ui/molecules/forward_message/forward_message_dialog.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/utils/autofill_utils.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:intergalactic/utils/download_utils.dart';
import 'package:intergalactic/utils/error_utils.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Why the timeline's Retry Decrypt entry cannot run, or null when it can.
///
/// THE SILENCE THIS EXISTS TO END. The entry's action is `Event.requestKey`,
/// which reaches `Room.requestSessionKey`, which returns without doing
/// anything when `client.encryptionEnabled` is false and calls through a
/// null-aware `client.encryption?.` when it is not. Both are silent. So with
/// vodozemac still initializing, or failed for the session, the user presses
/// Retry Decrypt, no request is sent, no error is raised, and the message
/// stays undecryptable with nothing said. `encryptionAvailability` is
/// documented as fail-closed for exactly this - "a surface that acts on
/// encryption must not offer itself as operable in either" state - and this
/// surface was still offering itself.
///
/// WHY A MESSAGE AND NOT A DISABLED ENTRY, which is what the room quick
/// access menu's sibling gate does. `TimelineEventMenuEntry.action` is not a
/// disable: three of the four renderers wrap it as `() => e.action?.call(...)`
/// so a null action still builds an enabled control that does nothing when
/// pressed, and tiamat's `ContextMenuItem` takes its tap handler from the
/// menu rather than from the entry, so it has no disabled state to give.
/// Passing null here would reproduce the silence rather than fix it. The
/// entry therefore stays enabled and the ACTION explains itself, through the
/// `ErrorUtils.tryRun` wrapper the action already ran inside - the same path
/// the SDK's own "Session key not requestable" refusal takes.
String? timelineRetryDecryptUnavailableReason(
  EncryptionAvailability availability,
) {
  switch (availability) {
    case EncryptionAvailability.ready:
      return null;
    case EncryptionAvailability.pending:
      return "Encryption is still preparing, so the key cannot be requested "
          "yet. Try again in a moment.";
    case EncryptionAvailability.unavailable:
      return "Encryption did not start for this session, so the key cannot be "
          "requested. Restart the app to try again.";
  }
}

/// Runs the timeline's Retry Decrypt action, refusing audibly when
/// encryption cannot serve it.
///
/// Separate from the menu so the refusal can be tested where it decides. The
/// assertion that matters is that `requestKey` is NOT REACHED - a test that
/// only checked the thrown message would pass against a version that threw
/// and sent the request anyway.
Future<void> runTimelineRetryDecrypt({
  required EncryptionAvailability availability,
  required Future<void> Function() requestKey,
}) async {
  final unavailable = timelineRetryDecryptUnavailableReason(availability);
  // Thrown rather than returned: the caller already runs this inside
  // `ErrorUtils.tryRun`, which is the surface that shows the user a reason,
  // and it is the same path the SDK's own "Session key not requestable"
  // refusal takes out of `Event.requestKey`.
  if (unavailable != null) throw unavailable;
  await requestKey();
}

class TimelineEventMenu {
  final Timeline timeline;
  final TimelineEvent event;

  late final List<TimelineEventMenuEntry> primaryActions;
  late final List<TimelineEventMenuEntry> secondaryActions;
  late final List<Emoticon> quickReactions;
  TimelineEventMenuEntry? addReactionAction;

  final Function(TimelineEvent event)? setEditingEvent;
  final Function(TimelineEvent event)? setReplyingEvent;
  final Function()? onActionFinished;

  final bool isThreadTimeline;
  final Attachment? attachmentForDownload;

  String get promptPinMessage => Intl.message(
    "Pin Message",
    desc: "Label for the menu option to pin a message",
    name: "promptPinMessage",
  );

  String get promptUnpinMessage => Intl.message(
    "Unpin Message",
    desc: "Label for the menu option to unpin a message",
    name: "promptUnpinMessage",
  );

  String get promptReplyInThread => Intl.message(
    "Reply In Thread",
    desc: "Label for the menu option to reply to a message inside a thread",
    name: "promptReplyInThread",
  );

  String get promptShowSource => Intl.message(
    "Show Source",
    desc: "Label for the menu option to view the JSON source of an event",
    name: "promptShowSource",
  );

  String get promptReplayMessageEffect => Intl.message(
    "Replay Effect",
    desc:
        "If a message was sent with an effect, this prompts to replay the effect",
    name: "promptReplayMessageEffect",
  );

  String get promptCancelEventSend => Intl.message(
    "Cancel",
    desc:
        "When a message failed to send, this prompts to cancel sending the event",
    name: "promptCancelEventSend",
  );

  String get promptRetryEventSend => Intl.message(
    "Retry",
    desc:
        "When a message failed to send, this prompts to retry sending the event",
    name: "promptRetryEventSend",
  );

  String get promptEndPoll => Intl.message(
    "End Poll",
    desc: "Prompt the user to end a poll",
    name: "promptEndPoll",
  );

  TimelineEventMenu({
    required this.timeline,
    required this.event,
    this.setEditingEvent,
    this.setReplyingEvent,
    this.onActionFinished,
    this.isThreadTimeline = false,
    this.attachmentForDownload,
  }) {
    bool canEditEvent = false;
    bool canSaveAttachment = false;
    bool canAddReaction = false;
    bool canReplyInThread = false;
    bool canCopy = false;
    bool canEditPinState = false;
    bool canPin = false;
    bool canUnpin = false;
    bool hasEffect = false;
    bool canReply = false;
    bool canDeleteEvent = false;
    bool canEndPoll = false;
    bool canForward = false;

    bool canRetrySend = event.status != TimelineEventStatus.synced;
    bool canCancelSend = event.status != TimelineEventStatus.synced;

    var effects = timeline.room.client.getComponent<MessageEffectComponent>();
    var emoticons = timeline.room.getComponent<RoomEmoticonComponent>();
    var pins = timeline.room.getComponent<PinnedMessagesComponent>();
    var photos = timeline.room.getComponent<PhotoAlbumRoom>();
    var polls = timeline.client.getComponent<PollComponent>();

    if (event.status == TimelineEventStatus.synced) {
      canEditEvent =
          event is TimelineEventMessage &&
          timeline.room.permissions.canUserEditMessages &&
          event.senderId == timeline.room.client.self!.identifier &&
          setEditingEvent != null;

      canDeleteEvent =
          timeline.canDeleteEvent(event) &&
          event.status == TimelineEventStatus.synced;

      canReply =
          event is TimelineEventMessage ||
          event is TimelineEventSticker ||
          event is TimelineEventEmote;

      if (photos != null) {
        canReply = false;
        canEditEvent = false;
      }

      if (event is TimelineEventMessage) {
        canSaveAttachment =
            (event as TimelineEventMessage).attachments?.isNotEmpty == true;
      }

      canAddReaction =
          (event is TimelineEventMessage || event is TimelineEventSticker) &&
          emoticons != null;

      canReplyInThread = !isThreadTimeline && event is TimelineEventMessage;

      canCopy = event is TimelineEventMessage;

      canForward =
          timeline.room is MatrixRoom &&
          event is MatrixTimelineEventMessage &&
          MatrixMessageForwarder.isForwardableMessage(
            event as MatrixTimelineEventMessage,
          );

      if (polls?.isPollEvent(event) == true &&
          polls?.canEndPoll(timeline.room, event, timeline) == true) {
        canEndPoll = true;
      }

      canEditPinState =
          pins?.canPinMessages == true &&
          (event is TimelineEventMessage ||
              event is TimelineEventSticker ||
              event is TimelineEventEmote);

      bool isPinned = pins?.isMessagePinned(event.eventId) == true;

      canPin = canEditPinState && !isPinned;
      canUnpin = canEditPinState && isPinned;

      hasEffect = effects?.hasEffect(event) == true;
    }

    var reactions = timeline.room.client
        .getComponent<RecentEmoticonComponent>();
    if (reactions != null && canAddReaction) {
      quickReactions = reactions.getQuickReactionEmoticon(timeline.room);
    } else {
      quickReactions = List.empty();
    }

    if (canAddReaction) {
      var recent = timeline.room.client
          .getComponent<RecentEmoticonComponent>()
          ?.getRecentReactionEmoticon(timeline.room);

      var availableEmoji = emoticons!.availableEmoji;

      if (recent != null && recent.isNotEmpty) {
        availableEmoji.insert(
          0,
          DynamicEmoticonPack(
            identifier: "dynamic_pack_frequently_used_reactions",
            displayName: "Frequently Used",
            icon: Icons.schedule,
            emoticons: recent,
            usage: EmoticonUsage.all,
          ),
        );
      }

      addReactionAction = TimelineEventMenuEntry(
        name: CommonStrings.promptAddReaction,
        icon: Icons.add_reaction,
        secondaryMenuBuilder: (context, dismissSecondaryMenu) {
          return EmojiPicker(
            availableEmoji,
            searchDelegate: (search) => AutofillUtils.searchEmoticon(
              search,
              client: timeline.client,
              room: timeline.room,
              limit: 50,
            ).whereType<AutofillSearchResultEmoticon>().toList(),
            preferredTooltipDirection: AxisDirection.left,
            onEmoticonPressed: (emote) async {
              timeline.room.addReaction(event, emote);
              await Future.delayed(const Duration(milliseconds: 100));
              dismissSecondaryMenu();
            },
          );
        },
      );
    }

    primaryActions = [
      if (canEndPoll)
        TimelineEventMenuEntry(
          name: promptEndPoll,
          icon: Icons.poll,
          action: (context) async {
            if (await AdaptiveDialog.confirmation(
                  context,
                  title: promptEndPoll,
                  prompt: "Are you sure you want to end the poll?",
                ) ==
                true)
              polls?.endPoll(timeline.room, event);
          },
        ),
      if (event is TimelineEventEncrypted)
        TimelineEventMenuEntry(
          name: "Retry Decrypt",
          icon: Icons.lock_open,
          action: (context) {
            var mx = (event as MatrixTimelineEvent).event;

            ErrorUtils.tryRun(
              context,
              // Availability is read at PRESS time, not at menu-build time, so
              // the reason describes the state the press actually met.
              () => runTimelineRetryDecrypt(
                availability: MatrixClient.encryptionAvailability.value,
                requestKey: mx.requestKey,
              ),
            );
          },
        ),
      if (canRetrySend)
        TimelineEventMenuEntry(
          name: promptRetryEventSend,
          icon: Icons.refresh,
          action: (BuildContext context) {
            timeline.room.retrySend(event);
            onActionFinished?.call();
          },
        ),
      if (canCancelSend)
        TimelineEventMenuEntry(
          name: promptCancelEventSend,
          icon: Icons.cancel,
          action: (BuildContext context) {
            timeline.room.cancelSend(event);
            onActionFinished?.call();
          },
        ),
      if (hasEffect)
        TimelineEventMenuEntry(
          name: promptReplayMessageEffect,
          icon: Icons.celebration,
          action: (BuildContext context) {
            effects?.doEffect(event);
            onActionFinished?.call();
          },
        ),
      if (canEditEvent)
        TimelineEventMenuEntry(
          name: CommonStrings.promptEdit,
          icon: Icons.edit,
          action: (BuildContext context) {
            setEditingEvent?.call(event);
            onActionFinished?.call();
          },
        ),
      if (canReply)
        TimelineEventMenuEntry(
          name: CommonStrings.promptReply,
          icon: Icons.reply,
          action: (BuildContext context) {
            setReplyingEvent?.call(event);
            onActionFinished?.call();
          },
        ),
      if (canForward)
        TimelineEventMenuEntry(
          name: CommonStrings.promptForwardMessage,
          icon: Icons.forward,
          action: (BuildContext context) async {
            await ForwardMessageDialog.show(
              context,
              sourceRoom: timeline.room as MatrixRoom,
              source: event as MatrixTimelineEventMessage,
            );
            onActionFinished?.call();
          },
        ),
      if (canSaveAttachment)
        TimelineEventMenuEntry(
          name: CommonStrings.promptDownload,
          icon: Icons.download,
          action: (BuildContext context) {
            var attachment =
                attachmentForDownload ??
                (event as TimelineEventMessage).attachments?.firstOrNull;
            if (attachment != null) {
              DownloadUtils.downloadAttachment(attachment, room: timeline.room);
            }
            onActionFinished?.call();
          },
        ),
      if (canDeleteEvent)
        TimelineEventMenuEntry(
          name: CommonStrings.promptDelete,
          icon: Icons.delete,
          destructive: true,
          action: (BuildContext context) {
            if (preferences.askBeforeDeletingMessageEnabled.value) {
              AdaptiveDialog.confirmation(context).then((value) {
                if (value == true) {
                  timeline.deleteEvent(event);
                }
                onActionFinished?.call();
              });
            } else {
              timeline.deleteEvent(event);
              onActionFinished?.call();
            }
          },
        ),
    ];

    secondaryActions = [
      if (canReplyInThread)
        TimelineEventMenuEntry(
          name: promptReplyInThread,
          icon: Icons.message_rounded,
          action: (context) {
            EventBus.openThread.add((
              timeline.client.identifier,
              timeline.room.identifier,
              event.eventId,
            ));
            onActionFinished?.call();
          },
        ),
      if (canPin)
        TimelineEventMenuEntry(
          name: promptPinMessage,
          icon: Icons.push_pin,
          action: (context) {
            pins!.pinMessage(event.eventId);
            onActionFinished?.call();
          },
        ),
      if (canUnpin)
        TimelineEventMenuEntry(
          name: promptUnpinMessage,
          icon: Icons.push_pin,
          action: (context) {
            pins!.unpinMessage(event.eventId);
            onActionFinished?.call();
          },
        ),
      if (canCopy)
        TimelineEventMenuEntry(
          name: CommonStrings.promptCopy,
          icon: Icons.copy,
          action: (context) {
            Clipboard.setData(
              ClipboardData(
                text: (event as TimelineEventMessage).plainTextBody,
              ),
            );
          },
        ),
      TimelineEventMenuEntry(
        name: promptShowSource,
        icon: Icons.code,
        action: (BuildContext context) {
          onActionFinished?.call();

          AdaptiveDialog.show(
            context,
            title: "Source",
            builder: (context) {
              return SizedBox(
                width: 1000,
                child: SelectionArea(
                  child: ExpandableCodeBlock(
                    expanded: true,
                    text: event.source,
                    language: "json",
                  ),
                ),
              );
            },
          );
        },
      ),
      if (preferences.developerMode.value &&
          (event is TimelineEventMessage || event is TimelineEventSticker))
        TimelineEventMenuEntry(
          name: "Show Notification",
          icon: Icons.notification_add,
          action: (BuildContext context) async {
            var room = timeline.room;

            var content = await MessageNotificationContent.fromEvent(
              event,
              room,
            );
            if (content != null) {
              NotificationManager.notify(content, forceShow: true);
            }

            onActionFinished?.call();
          },
        ),
    ];
  }
}

class TimelineEventMenuEntry {
  final String name;
  final Function(BuildContext context)? action;
  final IconData icon;
  final bool destructive;

  final Widget Function(BuildContext context, Function() dismissMenu)?
  secondaryMenuBuilder;

  TimelineEventMenuEntry({
    required this.name,
    required this.icon,
    this.action,
    this.secondaryMenuBuilder,
    this.destructive = false,
  });
}
