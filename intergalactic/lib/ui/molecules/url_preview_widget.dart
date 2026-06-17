import 'dart:math';

import 'package:intergalactic/client/components/url_preview/url_preview_component.dart';
import 'package:intergalactic/client/components/url_preview/url_preview_utils.dart';
import 'package:intergalactic/ui/atoms/shimmer_loading.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/atoms/tile.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class UrlPreviewWidget extends StatefulWidget {
  const UrlPreviewWidget(this.data,
      {super.key,
      this.onTap,
      this.onImageError,
      this.messageBubbleMode = false,
      this.alignRight = false});
  final UrlPreviewData? data;
  final void Function()? onTap;
  final void Function(Object error, StackTrace? stackTrace)? onImageError;
  final bool messageBubbleMode;
  final bool alignRight;

  @override
  State<UrlPreviewWidget> createState() => _UrlPreviewWidgetState();
}

class _UrlPreviewWidgetState extends State<UrlPreviewWidget> {
  static const double _mobileBreakpoint = 640;
  static const double _mobilePreviewScale = 0.84;
  static const double _imageWidth = 176;
  static const double _defaultImageHeight = 132;
  static const double _minImageHeight = 96;
  static const double _maxImageHeight = 320;
  double titleWidth = 0;
  double bodyWidth1 = 0;
  double bodyWidth2 = 0;
  Object? _reportedImageErrorKey;

  @override
  void initState() {
    var rng = Random();
    titleWidth = (rng.nextDouble() * 50) + 50;
    bodyWidth1 = (rng.nextDouble() * 200) + 100;
    bodyWidth2 = (rng.nextDouble() * 200) + 100;

    super.initState();
  }

  @override
  void didUpdateWidget(covariant UrlPreviewWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_previewImageKey(oldWidget.data) != _previewImageKey(widget.data)) {
      _reportedImageErrorKey = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (widget.messageBubbleMode) {
      return buildMessagePreview(context, data);
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: _scaleMobilePreview(
        context,
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Tile.surfaceContainer(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: data == null
                      ? buildLoadingDisplay()
                      : bodyLayout(context, data),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget buildMessagePreview(BuildContext context, UrlPreviewData? data) {
    final availableWidth = MediaQuery.sizeOf(context).width;
    final maxWidth = max(220.0, min(360.0, availableWidth - 96));

    return Align(
      alignment:
          widget.alignRight ? Alignment.centerRight : Alignment.centerLeft,
      child: _scaleMobilePreview(
        context,
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .outlineVariant
                      .withValues(alpha: 0.42),
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onTap,
                  child: data == null
                      ? Padding(
                          padding: const EdgeInsets.all(12),
                          child: buildLoadingDisplay(),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (data.image != null) messagePreviewImage(data),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(13, 10, 13, 12),
                              child: body(context, data),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
        alignment: widget.alignRight ? Alignment.topRight : Alignment.topLeft,
      ),
    );
  }

  Widget messagePreviewImage(UrlPreviewData data) {
    final image = data.image;
    if (image == null) {
      return ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
      );
    }

    final aspectRatio = (data.imageWidth != null &&
            data.imageHeight != null &&
            data.imageWidth! > 0 &&
            data.imageHeight! > 0)
        ? (data.imageWidth! / data.imageHeight!).clamp(0.75, 2.2)
        : 16.0 / 9.0;

    return AspectRatio(
      aspectRatio: aspectRatio,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: Image(
          image: image,
          filterQuality: FilterQuality.medium,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            _reportImageError(error, stackTrace);
            return ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
            );
          },
        ),
      ),
    );
  }

  Widget bodyLayout(BuildContext context, UrlPreviewData data) {
    final imageHeight = _imageHeightFor(data);
    final source = normalizeUrlPreviewText(data.siteName) ??
        inferUrlPreviewSource(data.uri);
    final compactRedditWithoutImage =
        data.image == null && source.toLowerCase() == 'reddit';
    final useMobileLayout = MediaQuery.sizeOf(context).width < 640;

    // Narrow layouts: stack image above text so the context is readable on
    // phones and installed mobile PWAs, regardless of platform.
    if (useMobileLayout) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: compactRedditWithoutImage ? 420 : double.infinity,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (data.image != null) imageMobile(data),
            if (data.image != null) const SizedBox(height: 8),
            body(context, data),
          ],
        ),
      );
    }

    // Wider layouts: image beside text.
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: data.image != null ? imageHeight : 0,
        maxWidth: compactRedditWithoutImage ? 420 : 540,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.image != null) image(data),
          if (data.image != null) const SizedBox(width: 12),
          Expanded(child: body(context, data)),
        ],
      ),
    );
  }

  /// Full-width image for the mobile column layout.  Uses AspectRatio so the
  /// card height stays proportional regardless of screen width.
  Widget imageMobile(UrlPreviewData data) {
    final imageProvider = data.image;
    if (imageProvider == null) {
      return const SizedBox.shrink();
    }

    final useContain = data.imageWidth != null && data.imageHeight != null;
    final aspectRatio = (data.imageWidth != null &&
            data.imageHeight != null &&
            data.imageWidth! > 0 &&
            data.imageHeight! > 0)
        ? (data.imageWidth! / data.imageHeight!).clamp(0.5, 3.0)
        : 16.0 / 9.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          child: Image(
            image: imageProvider,
            filterQuality: FilterQuality.medium,
            fit: useContain ? BoxFit.contain : BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              _reportImageError(error, stackTrace);
              return ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget buildLoadingDisplay() {
    var color = Theme.of(context).colorScheme.surfaceContainerLowest;
    return SizedBox(
      height: _defaultImageHeight,
      child: Shimmer(
        child: ShimmerLoading(
          isLoading: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: ConstrainedBox(
                      constraints: const BoxConstraints.tightFor(
                        width: _imageWidth,
                        height: _defaultImageHeight,
                      ),
                      child: Container(
                        color: color,
                      ))),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      height: 12,
                      width: titleWidth,
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4), color: color),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 16,
                      width: min(bodyWidth1, 180),
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4), color: color),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 10,
                      width: bodyWidth1,
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4), color: color),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 10,
                      width: bodyWidth2,
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4), color: color),
                    ),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget image(UrlPreviewData data) {
    final imageProvider = data.image;
    if (imageProvider == null) {
      return const SizedBox.shrink();
    }

    final imageHeight = _imageHeightFor(data);
    final useContain = data.imageWidth != null && data.imageHeight != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: _imageWidth,
        height: imageHeight,
        child: ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          child: Image(
            image: imageProvider,
            filterQuality: FilterQuality.medium,
            fit: useContain ? BoxFit.contain : BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              _reportImageError(error, stackTrace);
              return ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerLowest,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget body(BuildContext context, UrlPreviewData data) {
    final source = normalizeUrlPreviewText(data.siteName) ??
        inferUrlPreviewSource(data.uri);
    final postingAccount = _distinctPreviewLine(
      normalizeUrlPreviewPostingAccount(data.postingAccount),
      disallow: {source},
    );
    final stats = normalizeUrlPreviewText(data.stats);
    final title = _distinctPreviewLine(
      normalizeUrlPreviewText(data.title),
      disallow: {source, postingAccount},
    );
    final description = _distinctPreviewLine(
      trimUrlPreviewDescription(data.description),
      disallow: {source, postingAccount, title},
    );
    final useStructuredLayout = postingAccount != null || stats != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tiamat.Text.labelLow(
          source,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        if (useStructuredLayout && postingAccount != null)
          tiamat.Text.labelEmphasised(
            postingAccount,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
        else if (title != null)
          tiamat.Text.labelEmphasised(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        if (useStructuredLayout && postingAccount != null && title != null) ...[
          const SizedBox(height: 4),
          Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (stats != null) ...[
          const SizedBox(height: 4),
          tiamat.Text.tiny(
            stats,
            maxLines: 1,
            color: Theme.of(context).colorScheme.secondary,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        if (description != null) ...[
          const SizedBox(height: 6),
          Text(
            description,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                  height: 1.2,
                ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }

  double _imageHeightFor(UrlPreviewData data) {
    final width = data.imageWidth;
    final height = data.imageHeight;

    if (width == null || height == null || width <= 0 || height <= 0) {
      return _defaultImageHeight;
    }

    final calculated = _imageWidth * (height / width);
    return calculated.clamp(_minImageHeight, _maxImageHeight);
  }

  Widget _scaleMobilePreview(
    BuildContext context,
    Widget child, {
    Alignment alignment = Alignment.topLeft,
  }) {
    if (MediaQuery.sizeOf(context).width >= _mobileBreakpoint) {
      return child;
    }

    return Align(
      alignment: alignment,
      widthFactor: _mobilePreviewScale,
      heightFactor: _mobilePreviewScale,
      child: Transform.scale(
        alignment: alignment,
        scale: _mobilePreviewScale,
        child: child,
      ),
    );
  }

  String? _distinctPreviewLine(String? value,
      {required Set<String?> disallow}) {
    final normalized = normalizeUrlPreviewText(value);
    if (normalized == null) {
      return null;
    }

    final lower = normalized.toLowerCase();
    for (final item in disallow) {
      final other = normalizeUrlPreviewText(item);
      if (other != null && other.toLowerCase() == lower) {
        return null;
      }
    }

    return normalized;
  }

  Object? _previewImageKey(UrlPreviewData? data) {
    if (data == null) {
      return null;
    }

    return data.imageUri?.toString() ?? data.image;
  }

  void _reportImageError(Object error, StackTrace? stackTrace) {
    final key = _previewImageKey(widget.data);
    if (key == null || key == _reportedImageErrorKey) {
      return;
    }

    _reportedImageErrorKey = key;
    widget.onImageError?.call(error, stackTrace);
  }
}
