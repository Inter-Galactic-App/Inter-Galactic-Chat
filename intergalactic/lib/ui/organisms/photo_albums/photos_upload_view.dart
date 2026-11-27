import 'package:intergalactic/client/components/photo_album_room/photo_album_room_component.dart';
import 'package:intergalactic/client/components/photo_album_room/photo_album_entry.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/ui/mobile/mobile_surface.dart';
import 'package:intergalactic/ui/mobile/mobile_visuals.dart';
import 'package:intergalactic/utils/local_file.dart';
import 'package:intergalactic/utils/mime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:path/path.dart' as p;

class PhotosAlbumUploadView extends StatefulWidget {
  final List<PickedPhoto> photos;
  final PhotoAlbumRoom component;
  final PhotoAlbumUploadMode mode;
  const PhotosAlbumUploadView(
    this.photos,
    this.component, {
    this.mode = PhotoAlbumUploadMode.individual,
    super.key,
  });

  @override
  State<PhotosAlbumUploadView> createState() => _PhotosAlbumUploadViewState();
}

class _PhotosAlbumUploadViewState extends State<PhotosAlbumUploadView> {
  bool sendOriginal = false;

  @override
  Widget build(BuildContext context) {
    final isStack = widget.mode == PhotoAlbumUploadMode.stack;
    final canUpload = !isStack || widget.photos.length >= 2;
    final scheme = Theme.of(context).colorScheme;
    final isMobile = Layout.mobile;
    final screenSize = MediaQuery.sizeOf(context);
    final radius =
        isMobile ? MobileVisuals.panelBorderRadius : BorderRadius.circular(8);
    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        isMobile ? 18 : 18,
        isMobile ? 12 : 16,
        isMobile ? 18 : 18,
        isMobile ? 18 : 18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(9),
                  child: Icon(
                    isStack
                        ? Icons.photo_library_outlined
                        : Icons.add_photo_alternate_outlined,
                    color: scheme.primary,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isStack ? 'Upload Photo Stack' : 'Upload Individual Photo',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              _UploadCountPill(
                label:
                    '${widget.photos.length} ${widget.photos.length == 1 ? "item" : "items"}',
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: isMobile ? 250 : 300,
            child: MasonryGridView.extent(
              maxCrossAxisExtent: isMobile ? 132 : 110,
              mainAxisSpacing: isMobile ? 10 : 8,
              crossAxisSpacing: isMobile ? 10 : 8,
              itemCount: widget.photos.length,
              itemBuilder: (context, i) {
                return _UploadPreviewTile(
                  photo: widget.photos[i],
                  preview: buildFilePreview(i),
                );
              },
            ),
          ),
          if (!canUpload)
            _UploadNotice(
              icon: Icons.info_outline_rounded,
              text: 'Photo stacks need at least two photos.',
              color: scheme.error,
            ),
          if (sendOriginal)
            _UploadNotice(
              icon: Icons.location_on_outlined,
              text:
                  'Original image files may include sensitive metadata, such as where they were taken.',
              color: scheme.error,
            ),
          const SizedBox(height: 10),
          DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh.withValues(
                alpha: isMobile ? 0.58 : 0.42,
              ),
              borderRadius: BorderRadius.circular(isMobile ? 22 : 8),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.36),
              ),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                isMobile ? 14 : 12,
                isMobile ? 10 : 8,
                isMobile ? 8 : 6,
                isMobile ? 10 : 8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Upload Original',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  tiamat.Switch(
                    state: sendOriginal,
                    onChanged: (val) => setState(() {
                      sendOriginal = val;
                    }),
                  )
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          tiamat.Button(
            text: isStack ? 'Upload Stack' : 'Upload Photo',
            onTap: canUpload
                ? () {
                    widget.component.uploadPhotos(
                      widget.photos,
                      mode: widget.mode,
                      sendOriginal: sendOriginal,
                      extractMetadata: true,
                    );
                    Navigator.of(context).pop();
                  }
                : null,
          )
        ],
      ),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: isMobile ? 0 : 420,
        maxWidth: isMobile ? screenSize.width - 24 : 560,
        maxHeight: isMobile ? screenSize.height * 0.78 : 560,
      ),
      child: isMobile
          ? ClipRRect(
              borderRadius: radius,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow.withValues(alpha: 0.92),
                  borderRadius: radius,
                ),
                child: MobileGlassEdgeHighlight(
                  borderRadius: radius,
                  style: MobileGlassHighlightStyle.composer,
                  child: content,
                ),
              ),
            )
          : content,
    );
  }

  Widget buildFilePreview(int i) {
    var extension = p.extension(widget.photos[i].name);
    if (extension.startsWith('.')) extension = extension.substring(1);
    var mime = Mime.fromExtenstion(extension);

    if (Mime.imageTypes.contains(mime)) {
      if (widget.photos[i].filepath != null) {
        return Image(
          fit: BoxFit.cover,
          image: buildLocalFileImage(widget.photos[i].filepath!),
        );
      }

      return Icon(Icons.image);
    }

    if (Mime.videoTypes.contains(mime)) {
      return Icon(Icons.video_file);
    }

    return Icon(Icons.file_present);
  }
}

class _UploadPreviewTile extends StatelessWidget {
  const _UploadPreviewTile({
    required this.photo,
    required this.preview,
  });

  final PickedPhoto photo;
  final Widget preview;

  @override
  Widget build(BuildContext context) {
    final isMobile = Layout.mobile;
    final radius = BorderRadius.circular(isMobile ? 22 : 8);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isMobile ? 0.14 : 0.08),
            blurRadius: isMobile ? 16 : 8,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              preview,
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.48),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                right: 8,
                bottom: 7,
                child: Text(
                  photo.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadCountPill extends StatelessWidget {
  const _UploadCountPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.16),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(9, 4, 9, 4),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}

class _UploadNotice extends StatelessWidget {
  const _UploadNotice({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(Layout.mobile ? 18 : 8),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 17, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  maxLines: 3,
                  softWrap: true,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
