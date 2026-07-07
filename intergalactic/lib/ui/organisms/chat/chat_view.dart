import 'package:intergalactic/client/components/account_switch_prefix/account_switch_prefix.dart';
import 'package:intergalactic/client/components/push_notification/notification_manager.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/molecules/message_input.dart';
import 'package:intergalactic/ui/molecules/room_timeline_widget/room_timeline_widget.dart';
import 'package:intergalactic/ui/molecules/typing_indicators_widget.dart';
import 'package:intergalactic/ui/onboarding/tutorial_anchor.dart';
import 'package:intergalactic/ui/organisms/chat/chat.dart';
import 'package:intergalactic/ui/organisms/particle_player/particle_player.dart';
import 'package:intergalactic/utils/autofill_utils.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:intergalactic/utils/message_background/message_background_manager.dart';
import 'package:intergalactic/utils/scaled_app.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ChatView extends StatelessWidget {
  const ChatView(this.state, {super.key});
  final ChatState state;

  String get sendEncryptedMessagePrompt => Intl.message(
    "Send an encrypted message",
    name: "sendEncryptedMessagePrompt",
    desc: "Placeholder text for message input in an encrypted room",
  );

  String get sendUnencryptedMessagePrompt => Intl.message(
    "Send a message",
    name: "sendUnencryptedMessagePrompt",
    desc: "Placeholder text for message input in an unencrypted room",
  );

  String get cantSentMessagePrompt => Intl.message(
    "You do not have permission to send a message in this room",
    name: "cantSentMessagePrompt",
    desc: "Text that explains the user cannot send a message in this room",
  );

  String? get relatedEventSenderName => state.interactingEvent == null
      ? null
      : state.room
            .getMemberOrFallback(state.interactingEvent!.senderId)
            .displayName;

  Color? get relatedEventSenderColor => state.interactingEvent == null
      ? null
      : state.room.getColorOfUser(state.interactingEvent!.senderId);

  @override
  Widget build(BuildContext context) {
    final background = messageBackground(context);

    if (Layout.mobile) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (background != null) background,
          Positioned.fill(
            child: Stack(
              fit: StackFit.expand,
              children: [timeline(context), const ParticlePlayer()],
            ),
          ),
          Positioned(left: 0, right: 0, bottom: 0, child: input()),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (background != null) background,
        Column(
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [timeline(context), const ParticlePlayer()],
              ),
            ),
            input(),
          ],
        ),
      ],
    );
  }

  Widget? messageBackground(BuildContext context) {
    if ((!BuildConfig.MOBILE && !BuildConfig.DESKTOP) ||
        !MessageBackgroundManager.supportsLocalImages) {
      return null;
    }

    final storedPath =
        preferences.getRoomMessageBackgroundPath(state.room.localId) ??
        preferences.messageBackgroundImagePath.value;
    if (storedPath == null || storedPath.isEmpty) {
      return null;
    }
    final opacity = preferences
        .getEffectiveMessageBackgroundOpacity(state.room.localId)
        .clamp(0.0, 1.0)
        .toDouble();
    final image = MessageBackgroundManager.imageProvider(storedPath);
    if (image != null) {
      return _messageBackgroundImage(context, image, opacity);
    }

    return FutureBuilder<ImageProvider?>(
      future: MessageBackgroundManager.resolveImageProvider(storedPath),
      builder: (context, snapshot) {
        final image = snapshot.data;
        if (image == null) {
          return const SizedBox.shrink();
        }

        return _messageBackgroundImage(context, image, opacity);
      },
    );
  }

  Widget _messageBackgroundImage(
    BuildContext context,
    ImageProvider image,
    double opacity,
  ) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
          ),
        ),
        Opacity(
          opacity: opacity,
          child: Image(
            image: image,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ],
    );
  }

  Widget timeline(BuildContext context) {
    if (state.timeline == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final keyboardVisible =
        Layout.mobile && MediaQuery.of(context).scale().viewInsets.bottom > 0;
    final timeline = RoomTimelineWidget(
      key: ValueKey("${state.room.identifier}-timeline"),
      timeline: state.timeline!,
      bottomInset: Layout.mobile ? mobileTimelineBottomInset(context) : 0,
      keyboardVisible: keyboardVisible,
      autoLoadTimelineBoundaries: state.widget.autoLoadTimelineBoundaries,
      showTimelineBoundaryLoadingIndicators:
          state.widget.showTimelineBoundaryLoadingIndicators,
      onHistoryPageLoaded: state.retryDecryptTimelineAfterHistoryLoad,
      setReplyingEvent: (event) =>
          state.setInteractingEvent(event, type: EventInteractionType.reply),
      setEditingEvent: (event) =>
          state.setInteractingEvent(event, type: EventInteractionType.edit),
      isThreadTimeline: state.isThread,
      clearNotifications: clearNotifications,
    );

    return TutorialAnchor(id: TutorialAnchorIds.timeline, child: timeline);
  }

  double mobileTimelineBottomInset(BuildContext context) {
    final mediaQuery = MediaQuery.of(context).scale();
    final keyboardHeight = mediaQuery.viewInsets.bottom;
    final keyboardVisible = keyboardHeight > 0;
    final retainedSafeArea = PlatformUtils.isIOS && keyboardVisible
        ? 0.0
        : mediaQuery.padding.bottom;
    final keyboardGap = keyboardVisible ? 8.0 : 0.0;

    final mobileComposerClearance = state.mobileComposerHeight;
    return mobileComposerClearance +
        keyboardHeight +
        keyboardGap +
        retainedSafeArea;
  }

  void handleMarkAsRead(TimelineEvent event) async {
    // Dont update read receipts if in background
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }

    final timeline = state.room.timeline;
    if (timeline == null) {
      return;
    }

    timeline.markAsRead(event);
  }

  void clearNotifications(Room room) {
    // if we clear notifications when opening bubble, the bubble disappears
    if (state.isBubble) {
      return;
    }

    NotificationManager.clearNotifications(room);
  }

  Widget input() {
    String? interactingEventBody = state.interactingEvent?.plainTextBody;
    final desktopSmallWindowComposer =
        BuildConfig.DESKTOP &&
        !Layout.mobile &&
        preferences.desktopSmallWindowMode.value;

    if (state.interactingEvent case TimelineEventMessage m) {
      if (state.timeline != null) {
        interactingEventBody = m.getPlaintextBody(state.timeline!);
      }
    }

    return TutorialAnchor(
      id: TutorialAnchorIds.composer,
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
      child: ClipRRect(
        child: MessageInput(
          client: state.room.client,
          room: state.room,
          isRoomE2EE: state.room.isE2EE,
          focusKeyboard: state.onFocusMessageInput.stream,
          attachments: state.attachments,
          interactionType: state.interactionType,
          gifComponent: state.gifs,
          onSendMessage: (message, {overrideClient}) {
            if (overrideClient != null) {
              final processedText = state.room.client
                  .getComponent<AccountSwitchPrefix>()
                  ?.removePrefix(message, state.room);

              if (processedText != null) {
                message = processedText;
              }
            }
            state.sendMessage(message, overrideClient: overrideClient);
            return MessageInputSendResult.success;
          },
          onTextUpdated: state.onInputTextUpdated,
          addAttachment: state.addAttachment,
          removeAttachment: state.removeAttachment,
          size: desktopSmallWindowComposer ? 44 : (Layout.mobile ? 40 : 35),
          iconScale: desktopSmallWindowComposer
              ? 0.56
              : (Layout.mobile ? 0.6 : 0.5),
          isProcessing: state.processing,
          enabled: state.room.permissions.canSendMessage,
          relatedEventBody: interactingEventBody,
          relatedEventSenderName: relatedEventSenderName,
          relatedEventSenderColor: relatedEventSenderColor,
          setInputText: state.setMessageInputText.stream,
          availibleEmoticons: state.emoticons?.availableEmoji,
          availibleStickers: state.emoticons?.availableStickers,
          sendSticker: state.sendSticker,
          sendGif: state.sendGif,
          findOverrideClient: (input) => state.room.client
              .getComponent<AccountSwitchPrefix>()
              ?.getPrefixedAccount(input, state.room)
              ?.$1,
          onTapOverrideClient: (overrideClient) {
            EventBus.openRoom.add((
              state.room.identifier,
              overrideClient.identifier,
            ));

            if (state.isThread) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                EventBus.openThread.add((
                  overrideClient.identifier,
                  state.room.identifier,
                  state.threadId!,
                ));
              });
            }
          },
          editLastMessage: state.editLastMessage,
          hintText: state.room.permissions.canSendMessage
              ? state.room.isE2EE
                    ? sendEncryptedMessagePrompt
                    : sendUnencryptedMessagePrompt
              : cantSentMessagePrompt,
          cancelReply: () {
            state.setInteractingEvent(null);
          },
          typingIndicatorWidget: state.typingIndicators != null
              ? TypingIndicatorsWidget(
                  component: state.typingIndicators!,
                  key: ValueKey(
                    "room_typing_indicators_key_${state.room.identifier}",
                  ),
                )
              : null,
          processAutofill: (text) =>
              AutofillUtils.search(text, state.room.client, room: state.room),
          onHeightChanged: state.updateMobileComposerHeight,
        ),
      ),
    );
  }
}
