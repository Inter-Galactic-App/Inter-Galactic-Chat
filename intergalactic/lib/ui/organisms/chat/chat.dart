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
import 'package:intergalactic/client/components/inbound_share/inbound_share_controller.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_draft.dart';
import 'package:intergalactic/client/components/gif/gif_search_result.dart';
import 'package:intergalactic/client/components/read_receipts/read_receipt_component.dart';
import 'package:intergalactic/client/components/threads/thread_component.dart';
import 'package:intergalactic/client/components/url_preview/url_preview_component.dart';
import 'package:intergalactic/client/components/typing_indicators/typing_indicator_component.dart';
import 'package:intergalactic/client/matrix/room_open_decrypt_retry.dart';
import 'package:intergalactic/client/timeline_events/local_media_send_event.dart';
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
import 'package:intergalactic/utils/mime.dart';
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
  const Chat(
    this.room, {
    this.threadId,
    this.isBubble = false,
    this.autoLoadTimelineBoundaries = true,
    this.showTimelineBoundaryLoadingIndicators = true,
    this.inboundShareDraft,
    super.key,
  });
  final Room room;
  final String? threadId;
  final bool isBubble;
  final bool autoLoadTimelineBoundaries;
  final bool showTimelineBoundaryLoadingIndicators;
  final InboundShareDraft? inboundShareDraft;
  @override
  State<Chat> createState() => ChatState();
}

enum EventInteractionType { reply, edit }

class ChatState extends State<Chat> {
  Room get room => widget.room;
  Timeline? _timeline;

  Timeline? get timeline => _timeline;

  ThreadsComponent? threadsComponent;

  String get labelChatPageFileTooLarge => Intl.message(
    "This file is too large to upload!",
    desc:
        "Text that is shown when the user attempts to upload a file that is greater than the allowed size",
    name: "labelChatPageFileTooLarge",
  );

  String get labelChatPageFileTooLargeTitle => Intl.message(
    "Max file size exceeded",
    desc:
        "Title for the dialog that is shown when the user attempts to upload a file that is greater than the allowed size",
    name: "labelChatPageFileTooLargeTitle",
  );

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
  bool _sendInboundShareLiterally = false;
  InboundShareDraft? _appliedInboundShareDraft;
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

  Debouncer typingStatusDebouncer = Debouncer(
    delay: const Duration(seconds: 5),
  );
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
        unawaited(_prepareTimelineForDisplay(room.timeline!));
      } else {
        loadTimeline();
      }
    }

    _applyInboundShareDraft(widget.inboundShareDraft);
    super.initState();
  }

  void _applyInboundShareDraft(InboundShareDraft? draft) {
    if (draft == null || identical(_appliedInboundShareDraft, draft)) return;
    _appliedInboundShareDraft = draft;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_preloadInboundShareDraft(draft));
    });
  }

  Future<void> _preloadInboundShareDraft(InboundShareDraft draft) async {
    // Collected rather than added as they are accepted: rejecting one review
    // cancels the whole share, and a partially populated composer would let the
    // user send a body without the attachment they just refused.
    final processedAttachments = <PendingFileAttachment>[];
    for (final attachment in draft.payload.pendingAttachments) {
      final processedAttachment = await prepareAttachmentForComposer(
        context,
        attachment,
      );
      if (!mounted) return;
      if (processedAttachment == null) {
        await draft.onTerminal(InboundShareSessionState.cancelled);
        return;
      }
      processedAttachments.add(processedAttachment);
    }
    if (!mounted) return;
    for (final processedAttachment in processedAttachments) {
      addAttachment(processedAttachment);
    }
    _sendInboundShareLiterally = true;
    setMessageInputText.add(draft.body);
  }

  @override
  void didUpdateWidget(covariant Chat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.inboundShareDraft, widget.inboundShareDraft)) {
      _applyInboundShareDraft(widget.inboundShareDraft);
    }
  }

  Future<void> loadTimeline() async {
    var t = await room.getTimeline();
    await _prepareTimelineForDisplay(t);
  }

  Future<void> _prepareTimelineForDisplay(Timeline timeline) async {
    await roomOpenDecryptRetryCoordinator.maybeRetryForLoadedTimeline(timeline);
    if (!mounted) {
      return;
    }
    setState(() {
      _setTimeline(timeline, retryDecryptOnAttach: false);
    });
  }

  Future<void> loadThreadTimeline() async {
    Timeline? timeline = room.timeline;
    timeline ??= await room.getTimeline();

    var threadTimeline = await threadsComponent!.getThreadTimeline(
      roomTimeline: timeline,
      threadRootEventId: widget.threadId!,
    );
    if (!mounted) {
      return;
    }
    final timelineToDisplay = threadTimeline ?? timeline;
    await roomOpenDecryptRetryCoordinator.maybeRetryForLoadedTimeline(
      timelineToDisplay,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _setTimeline(timelineToDisplay, retryDecryptOnAttach: false);
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

  void _setTimeline(Timeline timeline, {bool retryDecryptOnAttach = true}) {
    if (!identical(_timeline, timeline)) {
      _timelineEventSubscription?.cancel();
      _timelineChangeSubscription?.cancel();
      _timeline = timeline;
      _timelineEventSubscription = timeline.onEventAdded.stream.listen(
        _onTimelineEventAdded,
      );
      _timelineChangeSubscription = timeline.onChange.stream.listen(
        _onTimelineEventChanged,
      );
    }

    _warmUrlPreviewsForTimeline(timeline);
    if (retryDecryptOnAttach) {
      unawaited(
        roomOpenDecryptRetryCoordinator.maybeRetryForLoadedTimeline(timeline),
      );
    }
  }

  Future<bool> retryDecryptTimelineAfterHistoryLoad(Timeline timeline) {
    if (!identical(_timeline, timeline)) {
      return Future.value(false);
    }

    return roomOpenDecryptRetryCoordinator.maybeRetryForLoadedTimeline(
      timeline,
      trigger: 'history_pagination',
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

    urlPreviews?.warmTimelinePreviews(timeline, limit: limit, concurrency: 2);
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
        AdaptiveDialog.show(
          context,
          builder: (_) {
            return SizedBox(
              height: 100,
              child: Center(
                child: tiamat.Text.label(labelChatPageFileTooLarge),
              ),
            );
          },
          title: labelChatPageFileTooLargeTitle,
        );

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

  void onAttachmentsChanged() {
    setState(() {});
  }

  void updateMobileComposerHeight(double height) {
    if (!Layout.mobile) {
      return;
    }

    final nextHeight = height
        .clamp(48.0, maxMobileComposerObstructionHeight)
        .toDouble();
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

    final attachmentSnapshot = List<PendingFileAttachment>.from(attachments);

    try {
      for (var file in attachmentSnapshot) {
        await file.resolve();
        var exif = await readExifFromBytes(file.data!);

        if (exif.keys.any((e) => e.toLowerCase().contains("gps"))) {
          if (!mounted) return;
          var confirmation = await AdaptiveDialog.confirmation(
            context,
            title: file.name ?? "File",
            confirmationText: "Send File",
            cancelText: "Don't send file",
            dangerous: true,
            prompt:
                "Location data was detected in file '${file.name}', are you sure you want to send?",
          );

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
            "Failed to find correct room to send event for override client. Cancelling",
          );

          return;
        }
      }

      if (!targetRoom.permissions.canSendMessage) {
        Log.w(
          "Inbound share target room is no longer writable: ${targetRoom.identifier}",
        );
        if (mounted) {
          await AdaptiveDialog.show(
            context,
            title: 'Room unavailable',
            builder: (_) => tiamat.Text.label(
              'This room is no longer available for sending.',
            ),
          );
        }
        return;
      }

      var component = targetRoom.client.getComponent<CommandComponent>();

      if (!_sendInboundShareLiterally &&
          component?.isExecutable(message) == true) {
        await doCommand(component, message, targetRoom: targetRoom);
        _clearComposerAfterAcceptedSend();
        return;
      }

      final optimisticDraft = _createOptimisticMediaSendDraft(
        message: message,
        attachmentSnapshot: attachmentSnapshot,
        targetRoom: targetRoom,
        targetThread: targetThread,
        overrideClient: overrideClient,
      );
      if (optimisticDraft != null && widget.inboundShareDraft == null) {
        _clearComposerAfterAcceptedSend();
        unawaited(_sendOptimisticMediaDraft(optimisticDraft));
        return;
      }

      var processedAttachments = await targetRoom.processAttachments(
        attachmentSnapshot,
      );

      if (isThread) {
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
          processedAttachments: processedAttachments,
        );
      } else {
        await targetRoom.sendMessage(
          message: message,
          inReplyTo: interactionType == EventInteractionType.reply
              ? interactingEvent
              : null,
          replaceEvent: interactionType == EventInteractionType.edit
              ? interactingEvent
              : null,
          processedAttachments: processedAttachments,
        );
      }

      final inboundDraft = widget.inboundShareDraft;
      if (inboundDraft != null) {
        await inboundDraft.onTerminal(InboundShareSessionState.completed);
      }
      _clearComposerAfterAcceptedSend();
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

  void _clearComposerAfterAcceptedSend() {
    typingIndicators?.setTypingStatus(false);
    _sendInboundShareLiterally = false;
    if (!mounted) {
      return;
    }

    setInteractingEvent(null);
    clearAttachments();
    setMessageInputText.add("");
  }

  _OptimisticMediaSendDraft? _createOptimisticMediaSendDraft({
    required String message,
    required List<PendingFileAttachment> attachmentSnapshot,
    required Room targetRoom,
    required ThreadsComponent? targetThread,
    required Client? overrideClient,
  }) {
    final timeline = _timeline;
    if (timeline == null ||
        overrideClient != null ||
        attachmentSnapshot.length != 1 ||
        interactionType == EventInteractionType.edit ||
        (isThread && targetThread == null)) {
      return null;
    }

    final pendingAttachment = attachmentSnapshot.single;
    final mimeType = pendingAttachment.mimeType;
    if (!Mime.imageTypes.contains(mimeType) &&
        !Mime.videoTypes.contains(mimeType)) {
      return null;
    }

    late final _OptimisticMediaSendDraft draft;
    final eventId =
        'local-media-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30)}';
    final localEvent = LocalMediaSendEvent.fromPendingAttachment(
      eventId: eventId,
      senderId: targetRoom.client.self!.identifier,
      originServerTs: DateTime.now(),
      pendingAttachment: pendingAttachment,
      body: message,
      onRetry: (_) => _retryOptimisticMediaDraft(draft),
      onCancel: (_) => _cancelOptimisticMediaDraft(draft),
    );

    if (localEvent == null) {
      return null;
    }

    draft = _OptimisticMediaSendDraft(
      timeline: timeline,
      targetRoom: targetRoom,
      targetThread: targetThread,
      pendingAttachment: pendingAttachment,
      message: message,
      inReplyTo: interactionType == EventInteractionType.reply
          ? interactingEvent
          : null,
      isThread: isThread,
      threadId: widget.threadId,
      event: localEvent,
    );

    timeline.insertEvent(0, localEvent);
    return draft;
  }

  Future<void> _sendOptimisticMediaDraft(
    _OptimisticMediaSendDraft draft,
  ) async {
    if (draft.running) {
      return;
    }

    draft.running = true;
    draft.cancelled = false;

    try {
      _markOptimisticMediaDraft(draft, LocalMediaSendState.preparing);
      final processedAttachments = await draft.targetRoom.processAttachments([
        draft.pendingAttachment,
      ]);
      if (draft.cancelled || draft.event.isCancelled) {
        return;
      }

      _markOptimisticMediaDraft(draft, LocalMediaSendState.uploading);
      if (draft.isThread) {
        final threadComponent = draft.targetThread;
        final threadId = draft.threadId;
        if (threadComponent == null || threadId == null) {
          throw StateError("Thread messaging is unavailable for media send");
        }

        await threadComponent.sendMessage(
          threadRootEventId: threadId,
          room: draft.targetRoom,
          message: draft.message,
          inReplyTo: draft.inReplyTo,
          processedAttachments: processedAttachments,
        );
      } else {
        await draft.targetRoom.sendMessage(
          message: draft.message,
          inReplyTo: draft.inReplyTo,
          processedAttachments: processedAttachments,
        );
      }

      if (draft.cancelled || draft.event.isCancelled) {
        return;
      }

      _markOptimisticMediaDraft(draft, LocalMediaSendState.sent);
      draft.timeline.removeEvent(draft.event.eventId);
    } catch (error, trace) {
      if (draft.cancelled || draft.event.isCancelled) {
        return;
      }

      Log.onError(
        error,
        trace,
        content: "Failed to send local optimistic media message",
      );
      _markOptimisticMediaDraft(
        draft,
        LocalMediaSendState.failed,
        error: error,
      );
    } finally {
      draft.running = false;
    }
  }

  Future<void> _retryOptimisticMediaDraft(
    _OptimisticMediaSendDraft draft,
  ) async {
    if (draft.running || draft.event.sendState != LocalMediaSendState.failed) {
      return;
    }

    await _sendOptimisticMediaDraft(draft);
  }

  Future<void> _cancelOptimisticMediaDraft(
    _OptimisticMediaSendDraft draft,
  ) async {
    draft.cancelled = true;
    draft.timeline.removeEvent(draft.event.eventId);
  }

  void _markOptimisticMediaDraft(
    _OptimisticMediaSendDraft draft,
    LocalMediaSendState sendState, {
    Object? error,
  }) {
    draft.event.mark(sendState, error: error);
    final index = draft.timeline.events.indexWhere(
      (event) => event.eventId == draft.event.eventId,
    );
    if (index != -1) {
      draft.timeline.notifyChanged(index);
    }
  }

  Future<void> doCommand(
    CommandComponent<Client>? component,
    String message, {
    required Room targetRoom,
  }) async {
    await component?.executeCommand(
      message,
      targetRoom,
      interactingEvent: interactingEvent,
      type: interactionType,
    );
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
          if (event case TimelineEventMessage m)
            if (timeline != null) {
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
      interactionType == EventInteractionType.reply ? interactingEvent : null,
    );
  }

  Future<void> sendGif(GifSearchResult gif) async {
    final gifComponent = gifs;
    if (gifComponent == null) {
      Log.w("GIF support is not available for room ${room.identifier}.");
      return;
    }

    await gifComponent.sendGif(
      gif,
      interactionType == EventInteractionType.reply ? interactingEvent : null,
      threadRootEventId: isThread ? widget.threadId : null,
    );
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
      // The shared body is gone, so the literal-send protection has nothing
      // left to protect. This is the only place it is dropped short of a
      // terminal state - see stopTyping.
      _sendInboundShareLiterally = false;
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
    // Deliberately does NOT clear _sendInboundShareLiterally. This runs off the
    // typing debounce, so clearing here let a shared body such as "/command"
    // become executable again after a few seconds of inactivity. The flag is
    // dropped on a terminal state or an explicitly emptied composer instead.
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
          name: file.name,
          path: file.path,
          size: size,
          data: data,
        );

        final processedAttachment = await prepareAttachmentForComposer(
          context,
          attachment,
        );

        if (!mounted) {
          return;
        }
        if (processedAttachment == null) {
          continue;
        }

        addAttachment(processedAttachment);
      }
    }
  }
}

class _OptimisticMediaSendDraft {
  _OptimisticMediaSendDraft({
    required this.timeline,
    required this.targetRoom,
    required this.targetThread,
    required this.pendingAttachment,
    required this.message,
    required this.inReplyTo,
    required this.isThread,
    required this.threadId,
    required this.event,
  });

  final Timeline timeline;
  final Room targetRoom;
  final ThreadsComponent? targetThread;
  final PendingFileAttachment pendingAttachment;
  final String message;
  final TimelineEvent? inReplyTo;
  final bool isThread;
  final String? threadId;
  final LocalMediaSendEvent event;

  bool cancelled = false;
  bool running = false;
}
