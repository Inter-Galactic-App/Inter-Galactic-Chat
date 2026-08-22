import 'dart:async';

import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/ui/accessibility/paused_animated_image.dart';
import 'package:intergalactic/ui/atoms/lightbox.dart';
import 'package:intergalactic/ui/molecules/audio_player/audio_player.dart';
import 'package:intergalactic/ui/molecules/video_player/video_player.dart';
import 'package:intergalactic/ui/molecules/video_player/video_player_controller.dart';
import 'package:intergalactic/utils/background_tasks/background_task_manager.dart';
import 'package:intergalactic/utils/download_utils.dart';
import 'package:intergalactic/utils/mime.dart';
import 'package:intergalactic/utils/text_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class MessageAttachment extends StatefulWidget {
  const MessageAttachment(
    this.attachment, {
    super.key,
    this.ignorePointer = false,
    this.previewMedia = false,
    this.alignRight = false,
    this.bubbleMessages = false,
    this.bubbleColor,
    this.room,
    this.lightboxActionsBuilder,
    this.mobileLightboxActionsBuilder,
    this.onFullscreenLongPress,
  });
  final Attachment attachment;
  final bool ignorePointer;
  final bool previewMedia;
  final bool alignRight;
  final bool bubbleMessages;
  final Color? bubbleColor;
  final Room? room;
  final WidgetBuilder? lightboxActionsBuilder;
  final LightboxMobileActionsBuilder? mobileLightboxActionsBuilder;
  final Future<void> Function(BuildContext context)? onFullscreenLongPress;
  @override
  State<MessageAttachment> createState() => _MessageAttachmentState();
}

class _MessageAttachmentState extends State<MessageAttachment> {
  late Key videoPlayerKey;
  bool isFullscreen = false;
  bool spoilerRevealed = false;
  var controller = VideoPlayerController();

  String get spoilerLabel => Intl.message(
    'Spoiler',
    name: 'attachmentSpoilerLabel',
    desc: 'Label shown over an image attachment that is hidden as a spoiler',
  );

  String get videoAttachmentLabel => Intl.message(
    'Video',
    name: 'videoAttachmentLabel',
    desc:
        'Generic label shown over a video attachment without exposing the file name',
  );
  @override
  void initState() {
    videoPlayerKey = GlobalKey();
    super.initState();
  }

  @override
  void dispose() {
    unawaited(controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.previewMedia) {
      if (widget.attachment is ImageAttachment) return buildImage();
      if (widget.attachment is VideoAttachment) {
        if (BuildConfig.WEB) {
          return buildFile(Icons.video_file, widget.attachment.name, null);
        }
        return buildVideo();
      }
    }

    final attachment = widget.attachment;
    if (attachment is FileAttachment) {
      if (attachment is AudioAttachment ||
          attachment.mimeType != null &&
              Mime.playableAudioTypes.contains(attachment.mimeType!)) {
        return buildAudio(attachment);
      }

      return buildFile(
        Mime.toIcon(attachment.mimeType),
        attachment.name,
        attachment.fileSize,
      );
    }

    return const Placeholder();
  }

  Widget buildImage() {
    assert(widget.attachment is ImageAttachment);
    var attachment = widget.attachment as ImageAttachment;
    final hideSpoiler = attachment.spoiler && !spoilerRevealed;
    final spoilerSurface = _attachmentSurfaceColor(
      context,
      fallback: Theme.of(context).colorScheme.surface,
    );

    return IgnorePointer(
      ignoring: widget.ignorePointer,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Material(
          color: widget.bubbleColor ?? Colors.transparent,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: 200,
              minHeight: 40,
              maxWidth: 500,
              minWidth: 40,
            ),
            child: InkWell(
              onTap: hideSpoiler
                  ? () => setState(() {
                      spoilerRevealed = true;
                    })
                  : fullscreenAttachment,
              child: FittedBox(
                fit: BoxFit.fitWidth,
                child: SizedBox(
                  width: attachment.width ?? 500,
                  height: attachment.height ?? 500,
                  child: hideSpoiler
                      ? ColoredBox(
                          color: Color.alphaBlend(
                            Colors.black.withValues(alpha: 0.62),
                            spoilerSurface,
                          ),
                          child: Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: spoilerSurface.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  14,
                                  8,
                                  14,
                                  8,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.visibility_off, size: 18),
                                    const SizedBox(width: 8),
                                    tiamat.Text.labelEmphasised(spoilerLabel),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                      : PausedAnimatedImage(
                          image: attachment.image,
                          filterQuality: FilterQuality.medium,
                          // if we know the height, its safe to fill as it wont appear stretched
                          fit:
                              attachment.width != null &&
                                  attachment.height != null
                              ? BoxFit.fill
                              : BoxFit.fitWidth,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildVideo() {
    var attachment = widget.attachment as VideoAttachment;
    final showHeader = !widget.bubbleMessages;
    final panel = _withBubbleTileTheme(
      Panel(
        mainAxisSize: MainAxisSize.min,
        header: showHeader ? videoAttachmentHeader(attachment) : null,
        mode: TileType.surfaceContainerLow,
        padding: 0,
        child: SizedBox(
          height: 200,
          width: 500,
          child: AspectRatio(
            aspectRatio: attachment.aspectRatio,
            child: isFullscreen
                ? null
                : VideoPlayer(
                    attachment.file,
                    thumbnail: attachment.thumbnail,
                    fileName: attachment.name,
                    doThumbnail: true,
                    canGoFullscreen: true,
                    onFullscreen: fullscreenVideo,
                    controller: controller,
                    key: videoPlayerKey,
                  ),
          ),
        ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: 200 + (showHeader ? 30 : 0),
        width: attachment.aspectRatio * 200,
        child: panel,
      ),
    );
  }

  void fullscreenAttachment() {
    if (widget.attachment is ImageAttachment) {
      final attachment = widget.attachment as ImageAttachment;
      Lightbox.show(
        context,
        image: attachment.image,
        actionsBuilder: widget.lightboxActionsBuilder,
        mobileActionsBuilder: widget.mobileLightboxActionsBuilder,
        onContentLongPress: widget.onFullscreenLongPress,
      );
    }

    if (widget.attachment is VideoAttachment) {
      fullscreenVideo();
    }
  }

  void fullscreenVideo() {
    var attachment = (widget.attachment as VideoAttachment);
    setState(() {
      isFullscreen = true;
    });
    Lightbox.show(
      context,
      video: attachment.file,
      aspectRatio: attachment.aspectRatio,
      thumbnail: attachment.thumbnail,
      videoController: controller,
      key: videoPlayerKey,
    ).then((value) {
      if (!mounted) {
        return;
      }

      setState(() {
        isFullscreen = false;
      });
    });
  }

  Widget buildFile(IconData icon, String fileName, int? fileSize) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: _attachmentSurfaceColor(context),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Icon(icon),
                  ),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        tiamat.Text.labelEmphasised(
                          fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (fileSize != null)
                          tiamat.Text.labelLow(
                            TextUtils.readableFileSize(fileSize),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (widget.attachment is ImageAttachment ||
                widget.attachment is VideoAttachment)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                child: tiamat.IconButton(
                  size: 20,
                  icon: Icons.visibility,
                  onPressed: fullscreenAttachment,
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 4, 0),
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: tiamat.IconButton(
                    size: 20,
                    icon: Icons.download,
                    onPressed: () async {
                      if (widget.attachment is FileAttachment) {
                        downloadAttachment(widget.attachment as FileAttachment);
                      }
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> downloadAttachment(FileAttachment attachment) async {
    return DownloadUtils.downloadAttachment(attachment, room: widget.room);
  }

  Future<BackgroundTaskStatus> downloadTask(
    FileAttachment attachment,
    String path,
  ) async {
    await attachment.file.save(path);

    return BackgroundTaskStatus.completed;
  }

  Widget buildAudio(FileAttachment attachment) {
    return AudioPlayer(
      file: attachment.file,
      fileName: attachment.name,
      fileSize: attachment.fileSize,
      duration: attachment is AudioAttachment ? attachment.duration : null,
      bubbleColor: widget.bubbleColor,
    );
  }

  String videoAttachmentHeader(VideoAttachment attachment) {
    final fileSize = attachment.fileSize;
    if (fileSize == null) {
      return videoAttachmentLabel;
    }

    return '$videoAttachmentLabel - ${TextUtils.readableFileSize(fileSize)}';
  }

  Color _attachmentSurfaceColor(BuildContext context, {Color? fallback}) {
    return widget.bubbleColor ??
        fallback ??
        Theme.of(context).colorScheme.surfaceContainerLow;
  }

  Widget _withBubbleTileTheme(Widget child) {
    final bubbleColor = widget.bubbleColor;
    if (bubbleColor == null) {
      return child;
    }

    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          surfaceContainerLow: bubbleColor,
        ),
      ),
      child: child,
    );
  }
}
