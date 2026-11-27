import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/components/photo_album_room/photo.dart';
import 'package:intergalactic/client/components/photo_album_room/photo_album_entry.dart';
import 'package:intergalactic/client/components/photo_album_room/photo_album_room_component.dart';
import 'package:intergalactic/client/components/photo_album_room/photo_album_timeline.dart';
import 'package:intergalactic/client/matrix/components/photo_album_room/matrix_photo.dart';
import 'package:intergalactic/client/matrix/components/photo_album_room/matrix_photo_album_room_component.dart';
import 'package:intergalactic/client/matrix/components/photo_album_room/matrix_photo_album_timeline.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:intergalactic/client/timeline.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_feature_reactions.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/ui/atoms/drag_drop_file_target.dart';
import 'package:intergalactic/ui/atoms/lightbox.dart';
import 'package:intergalactic/ui/atoms/scaled_safe_area.dart';
import 'package:intergalactic/ui/mobile/mobile_surface.dart';
import 'package:intergalactic/ui/mobile/mobile_visuals.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_attachments.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_reactions.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_event_menu.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_event_menu_dialog.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/organisms/photo_albums/photos_upload_view.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:intergalactic/utils/mime.dart';
import 'package:intergalactic/utils/text_utils.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class PhotoAlbumView extends StatefulWidget {
  const PhotoAlbumView(this.component, {super.key});
  final PhotoAlbumRoom component;

  @override
  State<PhotoAlbumView> createState() => _PhotoAlbumViewState();
}

class _PhotoAlbumViewState extends State<PhotoAlbumView> {
  PhotoAlbumTimeline? timeline;
  bool loadingMorePhotos = false;
  final controller = ScrollController();

  List<StreamSubscription> subs = [];

  List<PhotoAlbumEntry> get entries => timeline?.entries ?? const [];

  void onAdded(int event) {
    setState(() {});
  }

  @override
  void initState() {
    controller.addListener(onScroll);

    widget.component.getTimeline().then((t) {
      if (mounted) {
        setState(() {
          timeline = t;
        });

        subs = [
          t.onAdded.listen(onAdded),
          t.onChanged.listen(onChanged),
          t.onRemoved.listen(onRemoved),
        ];
        SchedulerBinding.instance.addPostFrameCallback(postFrameCallback);
      }
    });

    super.initState();
  }

  @override
  void dispose() {
    controller.removeListener(onScroll);
    controller.dispose();
    for (var sub in subs) {
      sub.cancel();
    }
    super.dispose();
  }

  void postFrameCallback(Duration timeStamp) {
    pollLoadingMorePhotos();
  }

  void onScroll() {
    pollLoadingMorePhotos();
  }

  void pollLoadingMorePhotos() {
    if (loadingMorePhotos) return;
    if (timeline?.canLoadMorePhotos != true) return;
    if (!controller.hasClients) return;

    if ((controller.position.maxScrollExtent - controller.position.pixels) <
        20) {
      setState(() {
        loadingMorePhotos = true;
        timeline?.loadMorePhotos().then((_) {
          if (mounted) {
            setState(() {
              loadingMorePhotos = false;
            });

            Future.delayed(const Duration(seconds: 1)).then((_) {
              if (mounted) {
                pollLoadingMorePhotos();
              }
            });
          }
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (timeline == null) {
      return const Material(
        type: MaterialType.transparency,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final padding = Layout.desktop
        ? const EdgeInsets.fromLTRB(22, 20, 22, 22)
        : const EdgeInsets.fromLTRB(
            MobileVisuals.screenPadding,
            12,
            MobileVisuals.screenPadding,
            16,
          );
    final albumEntries = entries;

    return Material(
      type: MaterialType.transparency,
      child: DragDropFileTarget(
        onDropComplete: onFileDropped,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scheme.surfaceContainerLowest,
                scheme.surface.withValues(alpha: Layout.mobile ? 0.94 : 0.88),
              ],
            ),
          ),
          child: Padding(
            padding: padding,
            child: Stack(
              children: [
                if (albumEntries.isEmpty) _buildEmptyState(),
                if (albumEntries.isNotEmpty)
                  MasonryGridView.extent(
                    padding: EdgeInsets.fromLTRB(
                      0,
                      0,
                      0,
                      Layout.mobile ? 112 : 92,
                    ),
                    crossAxisSpacing: Layout.desktop ? 16 : 12,
                    controller: controller,
                    mainAxisSpacing: Layout.desktop ? 16 : 12,
                    maxCrossAxisExtent: Layout.desktop ? 292 : 188,
                    itemCount: albumEntries.length,
                    itemBuilder: (context, index) {
                      final item = albumEntries[index];
                      return _buildEntry(item);
                    },
                  ),
                if (loadingMorePhotos)
                  ScaledSafeArea(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: CircularProgressIndicator(),
                    ),
                  ),
                if (widget.component.canUpload)
                  ScaledSafeArea(
                    child: Align(
                      alignment: Alignment.bottomRight,
                      child: _PhotoAlbumAddButton(onSelected: uploadImages),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final scheme = Theme.of(context).colorScheme;
    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        Layout.mobile ? 24 : 22,
        Layout.mobile ? 24 : 20,
        Layout.mobile ? 24 : 22,
        Layout.mobile ? 26 : 22,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Icon(
                Icons.photo_library_outlined,
                size: Layout.mobile ? 34 : 32,
                color: scheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No photos yet',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            widget.component.canUpload
                ? 'Use the add button to upload a single photo or a photo stack.'
                : 'Photos shared in this room will appear here.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );

    if (Layout.mobile) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: MobileSectionCard(
            padding: EdgeInsets.zero,
            highlightStyle: MobileGlassHighlightStyle.composer,
            child: content,
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: content,
        ),
      ),
    );
  }

  Widget _buildEntry(PhotoAlbumEntry entry) {
    Widget result = _PhotoAlbumEntryCard(
      entry: entry,
      timeline: timeline,
      previewBuilder: _buildEntryPreview,
      reactionsBuilder: _buildEntryReactions,
      onOpenComments: () => _openEntryThread(entry),
      onOpenFullscreen: () => _openEntryFullscreen(entry),
    );

    result = _withTimelineContextMenu(entry, result);

    return AspectRatio(aspectRatio: _aspectRatioForEntry(entry), child: result);
  }

  Widget _buildEntryPreview(PhotoAlbumEntry entry) {
    if (entry.isStack) {
      return _buildStackPreview(entry);
    }

    return _buildPhotoPreview(entry.coverPhoto);
  }

  Widget _buildStackPreview(PhotoAlbumEntry entry) {
    final photos = entry.photos;
    final primary = photos.isNotEmpty ? photos.first : entry.coverPhoto;
    final secondary = photos.length > 1 ? photos[1] : primary;
    final tertiary = photos.length > 2 ? photos[2] : secondary;

    final tertiaryInset = Layout.mobile ? 22.0 : 18.0;
    final secondaryInset = Layout.mobile ? 11.0 : 9.0;
    final primaryInset = Layout.mobile ? 17.0 : 16.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          left: tertiaryInset,
          top: tertiaryInset,
          right: 2,
          bottom: 2,
          child: _buildStackLayer(tertiary, opacity: 0.38),
        ),
        Positioned.fill(
          left: secondaryInset,
          top: secondaryInset,
          right: 8,
          bottom: 8,
          child: _buildStackLayer(secondary, opacity: 0.68),
        ),
        Positioned.fill(
          right: primaryInset,
          bottom: primaryInset,
          child: _buildStackLayer(primary, opacity: 1),
        ),
      ],
    );
  }

  Widget _buildStackLayer(Photo photo, {required double opacity}) {
    final radius = BorderRadius.circular(Layout.mobile ? 20 : 8);
    return Opacity(
      opacity: opacity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: Layout.mobile ? 0.16 : 0.2),
              blurRadius: Layout.mobile ? 18 : 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildPhotoPreview(photo),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoPreview(Photo item) {
    Widget? result;
    final attachment = item.attachment;
    final scheme = Theme.of(context).colorScheme;

    if (attachment == null) {
      if (item.status == TimelineEventStatus.sending) {
        result = Container(
          color: scheme.surfaceContainerLow,
          child: Center(child: CircularProgressIndicator()),
        );
      }

      if (item.status == TimelineEventStatus.error) {
        result = Container(
          color: scheme.surfaceContainerLow,
          child: Center(child: Icon(Icons.error, color: scheme.error)),
        );
      }
    }

    if (attachment is ImageAttachment) {
      result = Image(
        fit: BoxFit.cover,
        image: attachment.image,
        filterQuality: FilterQuality.medium,
      );
    }

    if (attachment is VideoAttachment) {
      result = Stack(
        fit: StackFit.expand,
        children: [
          if (attachment.thumbnail != null)
            Image(
              fit: BoxFit.cover,
              image: attachment.thumbnail!,
              filterQuality: FilterQuality.medium,
            )
          else
            ColoredBox(
              color: scheme.surfaceContainerLow,
              child: Icon(
                Icons.video_file_outlined,
                color: scheme.onSurfaceVariant,
              ),
            ),
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.92),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.45),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.play_arrow_rounded,
                        color: scheme.onSurfaceVariant,
                        size: 14,
                      ),
                      const SizedBox(width: 3),
                      tiamat.Text.tiny(
                        attachment.duration != null
                            ? TextUtils.formatDuration(attachment.duration!)
                            : 'Video',
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return result ??
        ColoredBox(
          color: scheme.surfaceContainerLow,
          child: Center(
            child: Icon(
              Icons.image_not_supported_outlined,
              color: scheme.onSurfaceVariant,
            ),
          ),
        );
  }

  Widget _buildEntryReactions(PhotoAlbumEntry entry) {
    if (timeline is! MatrixPhotoAlbumTimeline) {
      return const SizedBox.shrink();
    }

    final root = entry.rootPhoto;
    if (root is! MatrixPhoto) {
      return const SizedBox.shrink();
    }

    final matrixTimeline =
        (timeline! as MatrixPhotoAlbumTimeline).matrixTimeline;
    final index = matrixTimeline.events.indexWhere(
      (event) => event.eventId == root.event.eventId,
    );

    if (index < 0 ||
        root.event is! TimelineEventFeatureReactions ||
        !(root.event as TimelineEventFeatureReactions).hasReactions(
          matrixTimeline,
        )) {
      return const SizedBox.shrink();
    }

    return TimelineEventViewReactions(
      key: ValueKey('photo-album-reactions-${root.event.eventId}'),
      index: index,
      timeline: matrixTimeline,
    );
  }

  Widget _withTimelineContextMenu(PhotoAlbumEntry entry, Widget child) {
    if (!Layout.desktop) {
      return child;
    }

    if (timeline is! MatrixPhotoAlbumTimeline ||
        widget.component is! MatrixPhotoAlbumRoomComponent ||
        entry.rootPhoto is! MatrixPhoto) {
      return child;
    }

    final root = entry.rootPhoto as MatrixPhoto;
    final menu = TimelineEventMenu(
      timeline: (timeline! as MatrixPhotoAlbumTimeline).matrixTimeline,
      event: root.event,
    );

    return tiamat.ContextMenu(
      items: (menu.primaryActions + menu.secondaryActions)
          .map(
            (entry) => tiamat.ContextMenuItem(
              text: entry.name,
              icon: entry.icon,
              onPressed: () => entry.action?.call(context),
            ),
          )
          .toList(),
      child: child,
    );
  }

  double _aspectRatioForEntry(PhotoAlbumEntry entry) {
    final width = entry.coverPhoto.width ?? 500;
    final height = entry.coverPhoto.height ?? 500;
    if (height <= 0) {
      return 1;
    }

    final ratio = width / height;
    final minRatio = entry.isStack ? 0.78 : 0.62;
    final maxRatio = entry.isStack ? 1.32 : 1.9;
    return ratio.clamp(minRatio, maxRatio).toDouble();
  }

  void _openEntryThread(PhotoAlbumEntry entry) {
    EventBus.openThread.add((
      widget.component.room.client.identifier,
      widget.component.room.identifier,
      entry.rootPhoto.id,
    ));
  }

  void _openEntryFullscreen(PhotoAlbumEntry entry) {
    if (entry.isStack && timeline is MatrixPhotoAlbumTimeline) {
      final stackItems = _photoStackLightboxItems(entry);
      if (stackItems.length > 1) {
        PhotoStackLightbox.show(
          context,
          items: stackItems,
          timeline: (timeline! as MatrixPhotoAlbumTimeline).matrixTimeline,
          onOpenThread: () => _openEntryThread(entry),
        );
        return;
      }
    }

    // Stacks that are not backed by a Matrix timeline (e.g. the offline demo
    // album) can't use PhotoStackLightbox, so page through them with a
    // lightweight image-only viewer instead of collapsing to the cover photo.
    if (entry.isStack) {
      final images = _stackImageProviders(entry);
      if (images.length > 1) {
        _PhotoStackImageViewer.show(context, images: images);
        return;
      }
    }

    _openPhotoFullscreen(
      entry.coverPhoto,
      onOpenThread: () => _openEntryThread(entry),
    );
  }

  List<ImageProvider> _stackImageProviders(PhotoAlbumEntry entry) {
    final images = <ImageProvider>[];
    for (final photo in entry.photos) {
      final attachment = photo.attachment;
      if (attachment is ImageAttachment) {
        images.add(attachment.image);
      }
    }
    return images;
  }

  List<PhotoStackAttachmentItem> _photoStackLightboxItems(
    PhotoAlbumEntry entry,
  ) {
    if (timeline is! MatrixPhotoAlbumTimeline) {
      return const [];
    }

    final matrixTimeline =
        (timeline! as MatrixPhotoAlbumTimeline).matrixTimeline;
    final items = <PhotoStackAttachmentItem>[];

    for (final photo in entry.photos) {
      if (photo is! MatrixPhoto) {
        continue;
      }

      final attachment = photo.attachment;
      final event = photo.event;
      if (attachment is! ImageAttachment ||
          event is! MatrixTimelineEventMessage) {
        continue;
      }

      final index = matrixTimeline.events.indexWhere(
        (candidate) => candidate.eventId == event.eventId,
      );
      if (index < 0) {
        continue;
      }

      items.add(
        PhotoStackAttachmentItem(
          event: event,
          index: index,
          attachment: attachment,
        ),
      );
    }

    return items;
  }

  void _openPhotoFullscreen(Photo item, {VoidCallback? onOpenThread}) {
    final attachment = item.attachment;
    if (attachment is ImageAttachment) {
      Lightbox.show(
        context,
        image: attachment.image,
        mobileActionsBuilder:
            item is MatrixPhoto && timeline is MatrixPhotoAlbumTimeline
            ? (context, dismiss) {
                final matrixTimeline =
                    (timeline! as MatrixPhotoAlbumTimeline).matrixTimeline;
                return MobileFocusedMediaActions(
                  menu: TimelineEventMenu(
                    timeline: matrixTimeline,
                    event: item.event,
                    onActionFinished: dismiss,
                    attachmentForDownload: attachment,
                  ),
                  attachment: attachment,
                  onClose: dismiss,
                  onOpenThread: onOpenThread,
                );
              }
            : null,
      );
      return;
    }

    if (attachment is VideoAttachment) {
      Lightbox.show(
        context,
        video: attachment.file,
        aspectRatio: attachment.aspectRatio,
        thumbnail: attachment.thumbnail,
      );
    }
  }

  Future<void> uploadImages(PhotoAlbumUploadMode mode) async {
    final photos = await _pickPhotos(mode);
    if (photos == null || photos.isEmpty) {
      return;
    }

    _showUploadReview(photos, mode);
  }

  Future<List<PickedPhoto>?> _pickPhotos(PhotoAlbumUploadMode mode) async {
    if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
      return _pickPhotosOnMobile(mode);
    }

    final files = await FilePicker.platform.pickFiles(
      allowMultiple: mode == PhotoAlbumUploadMode.stack,
      type: FileType.image,
      withReadStream: true,
    );
    if (files == null) return null;

    return files.files
        .map(
          (e) => PickedPhoto(
            filepath: e.path,
            name: e.name,
            getBytes: () async {
              var result = List<int>.empty(growable: true);
              await for (final data in e.readStream!) {
                result.addAll(data);
              }

              return Uint8List.fromList(result);
            },
          ),
        )
        .toList();
  }

  Future<List<PickedPhoto>?> _pickPhotosOnMobile(
    PhotoAlbumUploadMode mode,
  ) async {
    final usePhotoPicker = await AdaptiveDialog.pickOne<bool>(
      context,
      items: [true, false],
      itemBuilder: (context, item, onTapped) {
        if (Layout.mobile) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: MobilePillButton(
              label: item ? 'Photos' : 'Browse Files',
              icon: item ? Icons.add_to_photos : Icons.file_open,
              onTap: onTapped,
            ),
          );
        }

        return SizedBox(
          height: 50,
          child: tiamat.TextButton(
            item ? 'Photos' : 'Browse Files',
            icon: item ? Icons.add_to_photos : Icons.file_open,
            onTap: onTapped,
          ),
        );
      },
    );
    if (usePhotoPicker == null) {
      return null;
    }

    final picker = ImagePicker();
    final files = <XFile>[];

    if (usePhotoPicker) {
      if (mode == PhotoAlbumUploadMode.individual) {
        final file = await picker.pickImage(source: ImageSource.gallery);
        if (file != null) {
          files.add(file);
        }
      } else {
        files.addAll(await picker.pickMultiImage());
      }
    } else {
      final picked = await picker.pickMultipleMedia();
      files.addAll(
        mode == PhotoAlbumUploadMode.individual && picked.isNotEmpty
            ? [picked.first]
            : picked,
      );
    }

    return files
        .map(
          (f) => PickedPhoto(
            name: f.name,
            filepath: f.path,
            getBytes: () {
              return f.readAsBytes();
            },
          ),
        )
        .toList();
  }

  void onFileDropped(DropDoneDetails event) {
    final files = event.files
        .map(
          (e) => PickedPhoto(
            filepath: e.path,
            name: e.name,
            getBytes: () => e.readAsBytes(),
          ),
        )
        .toList();

    final mode = files.length > 1 && files.every(_isImageFile)
        ? PhotoAlbumUploadMode.stack
        : PhotoAlbumUploadMode.individual;
    _showUploadReview(files, mode);
  }

  bool _isImageFile(PickedPhoto photo) {
    final dotIndex = photo.name.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == photo.name.length - 1) {
      return false;
    }

    final extension = photo.name.substring(dotIndex + 1);
    return Mime.imageTypes.contains(Mime.fromExtenstion(extension));
  }

  Future<void> _showUploadReview(
    List<PickedPhoto> photos,
    PhotoAlbumUploadMode mode,
  ) async {
    if (mode == PhotoAlbumUploadMode.stack && photos.length < 2) {
      await AdaptiveDialog.show(
        context,
        title: 'Photo stack needs more photos',
        builder: (_) =>
            tiamat.Text.label('Choose at least two photos to create a stack.'),
      );
      return;
    }

    if (!mounted) return;

    AdaptiveDialog.show(
      context,
      builder: (_) =>
          PhotosAlbumUploadView(photos, widget.component, mode: mode),
    );
  }

  void onChanged(int event) {
    setState(() {});
  }

  void onRemoved(int event) {
    setState(() {});
  }
}

class _PhotoAlbumEntryCard extends StatefulWidget {
  const _PhotoAlbumEntryCard({
    required this.entry,
    required this.timeline,
    required this.previewBuilder,
    required this.reactionsBuilder,
    required this.onOpenComments,
    required this.onOpenFullscreen,
  });

  final PhotoAlbumEntry entry;
  final PhotoAlbumTimeline? timeline;
  final Widget Function(PhotoAlbumEntry entry) previewBuilder;
  final Widget Function(PhotoAlbumEntry entry) reactionsBuilder;
  final VoidCallback onOpenComments;
  final VoidCallback onOpenFullscreen;

  @override
  State<_PhotoAlbumEntryCard> createState() => _PhotoAlbumEntryCardState();
}

class _PhotoAlbumEntryCardState extends State<_PhotoAlbumEntryCard> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final root = widget.entry.rootPhoto;
    final hasComments = root.threadReplyCount > 0;
    final isMobile = Layout.mobile;
    final radius = isMobile ? MobileVisuals.cardRadius : 8.0;
    final borderRadius = BorderRadius.circular(radius);
    final card = AnimatedScale(
      scale: hovering && Layout.desktop ? 1.012 : 1,
      duration: Durations.short3,
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
        duration: Durations.short3,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: isMobile
              ? scheme.surfaceContainerLow.withValues(alpha: 0.78)
              : scheme.surfaceContainerLow,
          borderRadius: borderRadius,
          border: Border.all(
            color: hovering && Layout.desktop
                ? scheme.primary.withValues(alpha: 0.44)
                : scheme.outlineVariant.withValues(
                    alpha: isMobile ? 0.28 : 0.42,
                  ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: isMobile ? 0.16 : (hovering ? 0.24 : 0.14),
              ),
              blurRadius: isMobile ? 24 : (hovering ? 22 : 12),
              offset: Offset(0, isMobile ? 10 : (hovering ? 10 : 5)),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Material(
            color: Colors.transparent,
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.previewBuilder(widget.entry),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(
                            alpha: isMobile ? 0.04 : 0.10,
                          ),
                          Colors.transparent,
                          Colors.black.withValues(
                            alpha: isMobile ? 0.42 : 0.32,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: InkWell(
                    onTap: isMobile
                        ? widget.onOpenFullscreen
                        : widget.onOpenComments,
                    onLongPress: Layout.desktop ? null : _showMobileMenu,
                  ),
                ),
                Positioned(
                  left: isMobile ? 10 : 8,
                  right: isMobile ? 10 : 8,
                  bottom: isMobile ? 10 : 8,
                  child: _PhotoAlbumEntryFooter(
                    entry: widget.entry,
                    hasComments: hasComments,
                    reactions: widget.reactionsBuilder(widget.entry),
                  ),
                ),
                if (widget.entry.isStack)
                  Positioned(
                    left: isMobile ? 10 : 8,
                    top: isMobile ? 10 : 8,
                    child: _Badge(
                      icon: Icons.filter_none_rounded,
                      label: '${widget.entry.displayCount}',
                    ),
                  ),
                if (Layout.desktop)
                  Positioned(
                    right: 7,
                    top: 7,
                    child: AnimatedOpacity(
                      duration: Durations.short2,
                      opacity: hovering ? 1 : 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _IconAction(
                            tooltip: 'Open full size',
                            icon: Icons.open_in_full_rounded,
                            onTap: widget.onOpenFullscreen,
                          ),
                          const SizedBox(width: 6),
                          _IconAction(
                            tooltip: 'Comments',
                            icon: Icons.mode_comment_outlined,
                            onTap: widget.onOpenComments,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    final polishedCard = isMobile
        ? MobileGlassEdgeHighlight(
            borderRadius: borderRadius,
            style: MobileGlassHighlightStyle.composer,
            intensity: 0.72,
            child: card,
          )
        : card;

    return MouseRegion(
      onEnter: (_) => setState(() => hovering = true),
      onExit: (_) => setState(() => hovering = false),
      child: polishedCard,
    );
  }

  Future<void> _showMobileMenu() async {
    if (widget.timeline is! MatrixPhotoAlbumTimeline ||
        widget.entry.rootPhoto is! MatrixPhoto) {
      return;
    }

    final root = widget.entry.rootPhoto as MatrixPhoto;
    final tl = (widget.timeline! as MatrixPhotoAlbumTimeline).matrixTimeline;

    await showModalBottomSheet(
      showDragHandle: true,
      isScrollControlled: true,
      elevation: 0,
      context: context,
      builder: (context) => TimelineEventMenuDialog(
        event: root.event,
        timeline: tl,
        menu: TimelineEventMenu(
          timeline: tl,
          event: root.event,
          onActionFinished: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}

class _PhotoAlbumEntryFooter extends StatelessWidget {
  const _PhotoAlbumEntryFooter({
    required this.entry,
    required this.hasComments,
    required this.reactions,
  });

  final PhotoAlbumEntry entry;
  final bool hasComments;
  final Widget reactions;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        reactions,
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            if (entry.isStack)
              _Badge(
                icon: Icons.photo_library_outlined,
                label:
                    '${entry.displayCount} ${entry.displayCount == 1 ? "photo" : "photos"}',
              ),
            if (hasComments)
              _Badge(
                icon: Icons.mode_comment_outlined,
                label: entry.rootPhoto.threadReplyCount.toString(),
              )
            else
              const _Badge(
                icon: Icons.mode_comment_outlined,
                label: 'Comments',
              ),
          ],
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final isMobile = Layout.mobile;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: isMobile ? 0.5 : 0.58),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withValues(alpha: isMobile ? 0.2 : 0.16),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(7, isMobile ? 5 : 4, 8, isMobile ? 5 : 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 13),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return tiamat.Tooltip(
      text: tooltip,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: SizedBox(
              width: 34,
              height: 34,
              child: Icon(icon, color: Colors.white, size: 16),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoAlbumAddButton extends StatelessWidget {
  const _PhotoAlbumAddButton({required this.onSelected});

  final ValueChanged<PhotoAlbumUploadMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (Layout.mobile) {
      return _MobileAddButton(onTap: () => _showMobileUploadModeSheet(context));
    }

    return PopupMenuButton<PhotoAlbumUploadMode>(
      tooltip: 'Add photos',
      position: PopupMenuPosition.over,
      offset: const Offset(0, -8),
      onSelected: onSelected,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: PhotoAlbumUploadMode.individual,
          child: _UploadModeMenuItem(
            icon: Icons.add_photo_alternate_outlined,
            title: 'Individual photo',
            subtitle: 'Choose one photo',
          ),
        ),
        PopupMenuItem(
          value: PhotoAlbumUploadMode.stack,
          child: _UploadModeMenuItem(
            icon: Icons.photo_library_outlined,
            title: 'Photo stack',
            subtitle: 'Choose multiple photos',
          ),
        ),
      ],
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.primary,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: SizedBox(
          width: 58,
          height: 58,
          child: Icon(Icons.add_rounded, color: scheme.onPrimary, size: 30),
        ),
      ),
    );
  }

  Future<void> _showMobileUploadModeSheet(BuildContext context) async {
    final selected = await showModalBottomSheet<PhotoAlbumUploadMode>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(MobileVisuals.panelRadius),
        ),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _UploadModeSheetOption(
                icon: Icons.add_photo_alternate_outlined,
                title: 'Individual photo',
                subtitle: 'Choose one photo',
                onTap: () =>
                    Navigator.of(context).pop(PhotoAlbumUploadMode.individual),
              ),
              const SizedBox(height: 10),
              _UploadModeSheetOption(
                icon: Icons.photo_library_outlined,
                title: 'Photo stack',
                subtitle: 'Choose multiple photos',
                onTap: () =>
                    Navigator.of(context).pop(PhotoAlbumUploadMode.stack),
              ),
            ],
          ),
        ),
      ),
    );

    if (selected != null) {
      onSelected(selected);
    }
  }
}

class _MobileAddButton extends StatelessWidget {
  const _MobileAddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(999);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: MobileGlassEdgeHighlight(
        borderRadius: radius,
        highlighted: true,
        style: MobileGlassHighlightStyle.composer,
        child: Material(
          color: scheme.primary,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: SizedBox(
              width: 62,
              height: 62,
              child: Icon(Icons.add_rounded, color: scheme.onPrimary, size: 32),
            ),
          ),
        ),
      ),
    );
  }
}

class _UploadModeSheetOption extends StatelessWidget {
  const _UploadModeSheetOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = MobileVisuals.cardBorderRadius;
    return MobileGlassEdgeHighlight(
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: scheme.surfaceContainerHigh.withValues(alpha: 0.72),
          border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Icon(icon, color: scheme.primary, size: 22),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UploadModeMenuItem extends StatelessWidget {
  const _UploadModeMenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 22, color: scheme.secondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Lightweight full-screen pager for photo stacks that are not backed by a
/// Matrix timeline (offline demo album). Image-only: swipe/arrow to page,
/// pinch/scroll to zoom, tap the backdrop or press escape to dismiss.
class _PhotoStackImageViewer extends StatefulWidget {
  const _PhotoStackImageViewer({required this.images});

  final List<ImageProvider> images;

  static Future<void> show(
    BuildContext context, {
    required List<ImageProvider> images,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'PHOTO_STACK',
      barrierColor: Colors.black.withValues(alpha: 0.82),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, _, __) => _PhotoStackImageViewer(images: images),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          SlideTransition(
            position: Tween(begin: const Offset(0, 1), end: Offset.zero)
                .animate(
                  CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ),
                ),
            child: child,
          ),
    );
  }

  @override
  State<_PhotoStackImageViewer> createState() => _PhotoStackImageViewerState();
}

class _PhotoStackImageViewerState extends State<_PhotoStackImageViewer> {
  final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _dismiss() => Navigator.of(context).maybePop();

  void _goTo(int target) {
    final clamped = target.clamp(0, widget.images.length - 1);
    if (clamped == _index) return;
    _controller.animateToPage(
      clamped,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showArrows = Layout.desktop && widget.images.length > 1;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _dismiss,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _goTo(_index - 1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _goTo(_index + 1),
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            // Backdrop tap target: dismisses without swallowing image gestures.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _dismiss,
              ),
            ),
            Padding(
              padding: EdgeInsets.all(Layout.mobile ? 10 : 100),
              child: ScaledSafeArea(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: widget.images.length,
                  onPageChanged: (value) => setState(() => _index = value),
                  itemBuilder: (context, i) {
                    return InteractiveViewer(
                      trackpadScrollCausesScale: true,
                      maxScale: 3.5,
                      child: Center(
                        child: Image(
                          image: widget.images[i],
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            if (showArrows) ...[
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _PhotoStackNavButton(
                    icon: Icons.chevron_left_rounded,
                    tooltip: "Previous photo",
                    onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
                  ),
                ),
              ),
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _PhotoStackNavButton(
                    icon: Icons.chevron_right_rounded,
                    tooltip: "Next photo",
                    onPressed: _index < widget.images.length - 1
                        ? () => _goTo(_index + 1)
                        : null,
                  ),
                ),
              ),
            ],
            Positioned(
              top: 12,
              right: 12,
              child: _PhotoStackNavButton(
                icon: Icons.close_rounded,
                tooltip: "Close",
                onPressed: _dismiss,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 20,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var i = 0; i < widget.images.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 3),
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i == _index
                                    ? scheme.onSurface
                                    : scheme.onSurface.withValues(alpha: 0.34),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoStackNavButton extends StatelessWidget {
  const _PhotoStackNavButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.34)),
      ),
      child: IconButton(
        icon: Icon(icon),
        color: scheme.onSurface,
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}
