import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/account_switch_prefix/account_switch_prefix.dart';
import 'package:intergalactic/client/components/command/command_component.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_component.dart';
import 'package:intergalactic/client/components/gif/gif_component.dart';
import 'package:intergalactic/client/components/gif/gif_search_result.dart';
import 'package:intergalactic/client/components/read_receipts/read_receipt_component.dart';
import 'package:intergalactic/client/components/threads/thread_component.dart';
import 'package:intergalactic/client/components/url_preview/url_preview_component.dart';
import 'package:intergalactic/client/components/typing_indicators/typing_indicator_component.dart';
import 'package:intergalactic/client/matrix/room_open_decrypt_retry.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_sticker.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/atoms/drag_drop_file_target.dart';
import 'package:intergalactic/ui/organisms/attachment_processor/attachment_processor.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/organisms/chat/chat_view.dart';
import 'package:intergalactic/utils/debounce.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

String _chatLogHash(Object? value) {
  final text = value?.toString();
  if (text == null || text.isEmpty) {
    return 'none';
  }
  return sha256.convert(utf8.encode(text)).toString().substring(0, 12);
}

class Chat extends StatefulWidget {
  const Chat(this.room, {this.threadId, this.isBubble = false, super.key});
  final Room room;
  final String? threadId;
  final bool isBubble;
  @override
  State<Chat> createState() => ChatState();
}

enum EventInteractionType {
  reply,
  edit,
}

class ChatState extends State<Chat> {
  static final RoomOpenDecryptRetryCoordinator _decryptRetryCoordinator =
      RoomOpenDecryptRetryCoordinator();

  Room get room => widget.room;
  Timeline? _timeline;

  Timeline? get timeline => _timeline;

  ThreadsComponent? threadsComponent;

  String get labelChatPageFileTooLarge => Intl.message(
      "This file is too large to upload!",
      desc:
          "Text that is shown when the user attempts to upload a file that is greater than the allowed size",
      name: "labelChatPageFileTooLarge");

  String get labelChatPageFileTooLargeTitle => Intl.message(
      "Max file size exceeded",
      desc:
          "Title for the dialog that is shown when the user attempts to upload a file that is greater than the allowed size",
      name: "labelChatPageFileTooLargeTitle");

  String get labelMessageSendFailedTitle => Intl.message(
        "Message failed to send",
        desc: "Title shown when a message or command send fails",
        name: "labelMessageSendFailedTitle",
      );

  String get labelMessageSendFailed => Intl.message(
        "Something went wrong while sending. Please try again.",
        desc: "Generic body shown when a message or command send fails",
        name: "labelMessageSendFailed",
      );

  bool processing = false;
  static const double maxMobileComposerObstructionHeight = 560.0;
  double mobileComposerHeight = 64.0;
  List<PendingFileAttachment> attachments = List.empty(growable: true);

  EventInteractionType? interactionType;
  TimelineEvent? interactingEvent;

  StreamController<void> onFocusMessageInput = StreamController();
  StreamController<String> setMessageInputText = StreamController();
  StreamSubscription? _settingsSubscription;

  GifComponent? gifs;
  RoomEmoticonComponent? emoticons;
  ReadReceiptComponent? receipts;
  TypingIndicatorComponent? typingIndicators;
  UrlPreviewComponent? urlPreviews;
  StreamSubscription<int>? _timelineEventSubscription;
  StreamSubscription<int>? _timelineChangeSubscription;

  Debouncer typingStatusDebouncer =
      Debouncer(delay: const Duration(seconds: 5));
  DateTime lastSetTyping = DateTime.fromMicrosecondsSinceEpoch(0);

  bool get isThread => widget.threadId != null;

  String? get threadId => widget.threadId;

  bool get isBubble => widget.isBubble;

  @override
  void initState() {
    Log.i(
      "Initializing room timeline room=${_chatLogHash(widget.room.identifier)} "
      "thread=${_chatLogHash(widget.threadId)}",
    );

    gifs = room.getComponent<GifComponent>();
    emoticons = room.getComponent<RoomEmoticonComponent>();
    threadsComponent = room.client.getComponent<ThreadsComponent>();
    receipts = room.getComponent<ReadReceiptComponent>();
    typingIndicators = room.getComponent<TypingIndicatorComponent>();
    urlPreviews = room.client.getComponent<UrlPreviewComponent>();
    if (BuildConfig.MOBILE) {
      _settingsSubscription = preferences.onSettingChanged.listen((_) {
        if (mounted) setState(() {});
      });
    }

    if (widget.threadId != null && threadsComponent != null) {
      loadThreadTimeline();
    } else {
      if (room.timeline != null) {
        _setTimeline(room.timeline!);
      } else {
        loadTimeline();
      }
    }

    super.initState();
  }

  Future<void> loadTimeline() async {
    var t = await room.getTimeline();
    if (!mounted) {
      return;
    }
    setState(() {
      _setTimeline(t);
    });
  }

  Future<void> loadThreadTimeline() async {
    Timeline? timeline = room.timeline;
    timeline ??= await room.getTimeline();

    var threadTimeline = await threadsComponent!.getThreadTimeline(
        roomTimeline: timeline, threadRootEventId: widget.threadId!);
    if (!mounted) {
      return;
    }
    setState(() {
      _setTimeline(threadTimeline ?? timeline!);
    });
  }

  @override
  void dispose() {
    Log.i(
      "Disposing room timeline room=${_chatLogHash(widget.room.identifier)} "
      "thread=${_chatLogHash(widget.threadId)}",
    );

    _settingsSubscription?.cancel();
    _timelineEventSubscription?.cancel();
    _timelineChangeSubscription?.cancel();
    super.dispose();
  }

  void _setTimeline(Timeline timeline) {
    if (!identical(_timeline, timeline)) {
      _timelineEventSubscription?.cancel();
      _timelineChangeSubscription?.cancel();
      _timeline = timeline;
      _timelineEventSubscription =
          timeline.onEventAdded.stream.listen(_onTimelineEventAdded);
      _timelineChangeSubscription =
          timeline.onChange.stream.listen(_onTimelineEventChanged);
    }

    _warmUrlPreviewsForTimeline(timeline);
    unawaited(
      _decryptRetryCoordinator.maybeRetryForLoadedTimeline(
        timeline,
      ),
    );
  }

  void _onTimelineEventAdded(int index) {
    if (index <= 2 && _timeline != null) {
      _warmUrlPreviewsForTimeline(_timeline!, limit: index == 0 ? 4 : 1);
    }
  }

  void _onTimelineEventChanged(int index) {
    if (index <= 2 && _timeline != null) {
      _warmUrlPreviewsForTimeline(_timeline!, limit: index == 0 ? 4 : 1);
    }
  }

  void _warmUrlPreviewsForTimeline(Timeline timeline, {int limit = 10}) {
    if (!timeline.room.shouldPreviewMedia) {
      return;
    }

    urlPreviews?.warmTimelinePreviews(
      timeline,
      limit: limit,
      concurrency: 2,
    );
  }

  @override
  Widget build(BuildContext context) {
    return DragDropFileTarget(
      onDropComplete: (details) => onFileDropped(details),
      child: ChatView(this),
    );
  }

  void addAttachment(PendingFileAttachment attachment) {
    if (room.client.maxFileSize != null) {
      if (attachment.size != null &&
          attachment.size! > room.client.maxFileSize!) {
        AdaptiveDialog.show(context, builder: (_) {
          return SizedBox(
              height: 100,
              child:
                  Center(child: tiamat.Text.label(labelChatPageFileTooLarge)));
        }, title: labelChatPageFileTooLargeTitle);

        return;
      }
    }

    setState(() {
      attachments.add(attachment);
    });
  }

  void removeAttachment(PendingFileAttachment attachment) {
    setState(() {
      attachments.remove(attachment);
    });
  }

  void updateMobileComposerHeight(double height) {
    if (!Layout.mobile) {
      return;
    }

    final nextHeight =
        height.clamp(48.0, maxMobileComposerObstructionHeight).toDouble();
    if ((mobileComposerHeight - nextHeight).abs() < 0.5) {
      return;
    }

    setState(() {
      mobileComposerHeight = nextHeight;
    });
  }

  void sendMessage(String message, {Client? overrideClient}) async {
    setState(() {
      processing = true;
    });

    try {
      for (var file in attachments) {
        await file.resolve();
        var exif = await readExifFromBytes(file.data!);

        if (exif.keys.any((e) => e.toLowerCase().contains("gps"))) {
          if (!mounted) return;
          var confirmation = await AdaptiveDialog.confirmation(context,
              title: file.name ?? "File",
              confirmationText: "Send File",
              cancelText: "Don't send file",
              dangerous: true,
              prompt:
                  "Location data was detected in file '${file.name}', are you sure you want to send?");

          if (confirmation != true) {
            return;
          }
        }
      }

      var targetRoom = room;
      var targetThread = threadsComponent;

      if (overrideClient != null) {
        var newRoom = overrideClient.getRoom(targetRoom.identifier);
        if (newRoom != null) {
          targetRoom = newRoom;
          targetThread = targetRoom.client.getComponent<ThreadsComponent>();
          Log.d("Overriding room for client: ${overrideClient}");
        } else {
          Log.e(
              "Failed to find correct room to send event for override client. Cancelling");

          return;
        }
      }

      var processedAttachments =
          await targetRoom.processAttachments(attachments);

      var component = targetRoom.client.getComponent<CommandComponent>();

      if (component?.isExecutable(message) == true) {
        await doCommand(component, message, targetRoom: targetRoom);
      } else if (isThread) {
        final threadComponent = targetThread;
        if (threadComponent == null) {
          throw StateError(
            "Thread messaging is unavailable for room ${targetRoom.identifier}",
          );
        }
        await threadComponent.sendMessage(
            threadRootEventId: widget.threadId!,
            room: targetRoom,
            message: message,
            inReplyTo: interactionType == EventInteractionType.reply
                ? interactingEvent
                : null,
            replaceEvent: interactionType == EventInteractionType.edit
                ? interactingEvent
                : null,
            processedAttachments: processedAttachments);
      } else {
        await targetRoom.sendMessage(
            message: message,
            inReplyTo: interactionType == EventInteractionType.reply
                ? interactingEvent
                : null,
            replaceEvent: interactionType == EventInteractionType.edit
                ? interactingEvent
                : null,
            processedAttachments: processedAttachments);
      }

      typingIndicators?.setTypingStatus(false);
      if (mounted) {
        setInteractingEvent(null);
        clearAttachments();
        setMessageInputText.add("");
      }
    } catch (error, trace) {
      Log.onError(error, trace, content: "Failed to send chat message");
      if (mounted) {
        await AdaptiveDialog.show(
          context,
          title: labelMessageSendFailedTitle,
          builder: (_) => tiamat.Text.label(labelMessageSendFailed),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          processing = false;
        });
      }
    }
  }

  Future<void> doCommand(
    CommandComponent<Client>? component,
    String message, {
    required Room targetRoom,
  }) async {
    await component?.executeCommand(message, targetRoom,
        interactingEvent: interactingEvent, type: interactionType);
  }

  void setInteractingEvent(TimelineEvent? event, {EventInteractionType? type}) {
    if (event == null) {
      setState(() {
        interactingEvent = null;
        interactionType = null;
      });
      return;
    }

    if (event is! TimelineEventMessage && event is! TimelineEventSticker) {
      return;
    }

    setState(() {
      interactingEvent = event;
      interactionType = type;

      switch (type) {
        case EventInteractionType.reply:
          onFocusMessageInput.add(null);
          break;
        case EventInteractionType.edit:
          if (event case TimelineEventMessage m) if (timeline != null) {
            setMessageInputText.add(m.getPlaintextBody(timeline!));
          }

          onFocusMessageInput.add(null);
          break;
        default:
      }
    });
  }

  void clearAttachments() {
    setState(() {
      attachments.clear();
    });
  }

  void addReaction(TimelineEvent event, Emoticon emote) {
    room.addReaction(event, emote);
  }

  void sendSticker(Emoticon sticker) {
    emoticons?.sendSticker(
        sticker,
        interactionType == EventInteractionType.reply
            ? interactingEvent
            : null);
  }

  Future<void> sendGif(GifSearchResult gif) async {
    final gifComponent = gifs;
    if (gifComponent == null) {
      Log.w("GIF support is not available for room ${room.identifier}.");
      return;
    }

    await gifComponent.sendGif(gif,
        interactionType == EventInteractionType.reply ? interactingEvent : null,
        threadRootEventId: isThread ? widget.threadId : null);
  }

  void editLastMessage() {
    if (!room.permissions.canUserEditMessages) return;
    if (interactionType != null) return;

    for (int i = 0; i < min(20, room.timeline!.events.length); i++) {
      var event = room.timeline!.events[i];

      if (event.senderId != room.client.self!.identifier) continue;

      if (!(event is TimelineEventMessage)) continue;

      setInteractingEvent(event, type: EventInteractionType.edit);
      break;
    }
  }

  void onInputTextUpdated(String currentText) {
    if (isThread) {
      return;
    }

    var component = room.client.getComponent<CommandComponent>();
    if (component?.isPossiblyCommand(currentText) == true) {
      return;
    }

    var prefixComp = room.client.getComponent<AccountSwitchPrefix>();
    if (prefixComp?.isPossiblyUsingPrefix(currentText) == true) {
      return;
    }

    if (currentText.isEmpty) {
      stopTyping();
      typingStatusDebouncer.cancel();
      lastSetTyping = DateTime.fromMicrosecondsSinceEpoch(0);
    } else {
      if ((DateTime.now().difference(lastSetTyping)).inSeconds > 3) {
        typingIndicators?.setTypingStatus(true);
        lastSetTyping = DateTime.now();
      }
      typingStatusDebouncer.run(stopTyping);
    }
  }

  void stopTyping() {
    typingIndicators?.setTypingStatus(false);
  }

  void onFileDropped(DropDoneDetails event) async {
    for (var file in event.files) {
      var size = await file.length();
      Uint8List? data;
      if (size < 50000000) {
        data = await file.readAsBytes();
      }

      if (mounted) {
        var attachment = PendingFileAttachment(
            name: file.name, path: file.path, size: size, data: data);

        var processedAttachment =
            await AdaptiveDialog.show<PendingFileAttachment>(context,
                scrollable: false,
                builder: (context) => AttachmentProcessor(
                      attachment: attachment,
                    ));

        if (processedAttachment != null) {
          setState(() {
            attachments.add(processedAttachment);
          });
        }
      }
    }
  }
}
