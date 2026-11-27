import 'package:intergalactic/client/components/inbox/inbox_query.dart';
import 'package:intergalactic/client/components/url_preview/url_preview_component.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;

/// Compact Inbox context. URL cards resolve only after this row is visible and
/// only through the existing room/E2EE preview policy.
class InboxMessagePreview extends StatefulWidget {
  const InboxMessagePreview({
    required this.event,
    required this.isMasked,
    required this.onOpenMessage,
    super.key,
  });

  final InboxEventSnapshot event;
  final bool isMasked;
  final VoidCallback onOpenMessage;

  @override
  State<InboxMessagePreview> createState() => _InboxMessagePreviewState();
}

class _InboxMessagePreviewState extends State<InboxMessagePreview> {
  Future<UrlPreviewData?>? _urlPreviewFuture;
  ScrollPosition? _scrollPosition;
  var _previewLoadStarted = false;
  var _visibilityCheckScheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleVisibilityCheck();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextPosition = Scrollable.maybeOf(context)?.position;
    if (nextPosition != _scrollPosition) {
      _scrollPosition?.removeListener(_scheduleVisibilityCheck);
      _scrollPosition = nextPosition;
      _scrollPosition?.addListener(_scheduleVisibilityCheck);
    }
    _scheduleVisibilityCheck();
  }

  @override
  void didUpdateWidget(covariant InboxMessagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event != widget.event ||
        oldWidget.isMasked != widget.isMasked) {
      _urlPreviewFuture = null;
      _previewLoadStarted = false;
      _scheduleVisibilityCheck();
    }
  }

  void _scheduleVisibilityCheck() {
    if (_visibilityCheckScheduled) return;
    _visibilityCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityCheckScheduled = false;
      // `_previewLoadStarted` is checked here as well as inside
      // `_startUrlPreviewLoad`. Without it the inner guard still returns
      // without changing anything, but the `setState` around it has already
      // marked the element dirty - so every visible inbox row rebuilt on every
      // scroll frame for a load that had already happened.
      if (!mounted || _previewLoadStarted || !_isVisibleInScrollable()) return;
      setState(_startUrlPreviewLoad);
    });
  }

  bool _isVisibleInScrollable() {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return false;
    }

    final position = _scrollPosition;
    final viewport = RenderAbstractViewport.maybeOf(renderObject);
    // Standalone callers, including the compact widget harness, have no
    // scroll viewport. Their mounted preview is the visible surface.
    if (position == null || viewport == null) return true;

    final revealOffset = viewport.getOffsetToReveal(renderObject, 0).offset;
    final viewportStart = position.pixels;
    final viewportEnd = viewportStart + position.viewportDimension;
    return revealOffset < viewportEnd &&
        revealOffset + renderObject.size.height > viewportStart;
  }

  void _startUrlPreviewLoad() {
    if (_previewLoadStarted) return;
    _previewLoadStarted = true;
    if (widget.isMasked || widget.event.cachedUrlPreview != null) {
      _urlPreviewFuture = null;
      return;
    }
    _urlPreviewFuture = widget.event.loadUrlPreview?.call();
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_scheduleVisibilityCheck);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isMasked) {
      return Semantics(
        label: 'Locked conversation preview',
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Locked conversation'),
        ),
      );
    }

    final event = widget.event;
    return Semantics(
      container: true,
      label: 'Inbox message preview',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            event.plainTextBody.isEmpty
                ? 'Message preview unavailable'
                : event.plainTextBody,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          if (event.cachedImagePreview case final imagePreview?) ...[
            const SizedBox(height: 8),
            CachedInboxImagePreview(image: imagePreview),
          ],
          _urlPreview(context, event),
          const SizedBox(height: 4),
          TextButton(
            onPressed: widget.onOpenMessage,
            child: const Text('Open full message'),
          ),
        ],
      ),
    );
  }

  Widget _urlPreview(BuildContext context, InboxEventSnapshot event) {
    final cached = event.cachedUrlPreview;
    if (cached != null) {
      return _InboxUrlPreview(data: cached);
    }

    final future = _urlPreviewFuture;
    if (future == null) return const SizedBox.shrink();
    return FutureBuilder<UrlPreviewData?>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              label: 'Loading link preview',
              liveRegion: true,
              child: const LinearProgressIndicator(),
            ),
          );
        }
        final data = snapshot.data;
        return data == null
            ? const SizedBox.shrink()
            : _InboxUrlPreview(data: data);
      },
    );
  }
}

/// Renders an image only when another surface has already populated Flutter's
/// image cache. It never calls [ImageProvider.resolve], so a cache miss cannot
/// open a network/file request or start a media decrypt.
class CachedInboxImagePreview extends StatefulWidget {
  const CachedInboxImagePreview({required this.image, super.key});

  final ImageProvider image;

  @override
  State<CachedInboxImagePreview> createState() =>
      _CachedInboxImagePreviewState();
}

class _CachedInboxImagePreviewState extends State<CachedInboxImagePreview> {
  ImageStreamCompleter? _completer;
  ImageStreamListener? _listener;
  ImageInfo? _imageInfo;

  @override
  void initState() {
    super.initState();
    _loadFromCache();
  }

  @override
  void didUpdateWidget(CachedInboxImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _stopListening();
      _loadFromCache();
    }
  }

  Future<void> _loadFromCache() async {
    final key = await widget.image.obtainKey(const ImageConfiguration());
    if (!mounted || !PaintingBinding.instance.imageCache.containsKey(key)) {
      return;
    }

    // [containsKey] proves this is an existing cache entry. The sentinel loader
    // must remain unreachable; it makes a future cache-behaviour change fail
    // closed instead of resolving the provider and fetching media.
    final completer = PaintingBinding.instance.imageCache.putIfAbsent(
      key,
      () => throw StateError('Inbox image cache entry disappeared.'),
    );
    if (completer == null || !mounted) return;

    _completer = completer;
    _listener = ImageStreamListener((imageInfo, _) {
      if (!mounted) return;
      final nextImageInfo = imageInfo.clone();
      final previousImageInfo = _imageInfo;
      setState(() => _imageInfo = nextImageInfo);
      previousImageInfo?.dispose();
      _detachListener();
    });
    completer.addListener(_listener!);
  }

  void _detachListener() {
    if (_completer != null && _listener != null) {
      _completer!.removeListener(_listener!);
    }
    _completer = null;
    _listener = null;
  }

  void _stopListening() {
    _detachListener();
    _imageInfo?.dispose();
    _imageInfo = null;
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imageInfo = _imageInfo;
    if (imageInfo == null) return const SizedBox.shrink();
    return Semantics(
      label: 'Cached image preview',
      image: true,
      child: AspectRatio(
        aspectRatio: imageInfo.image.width / imageInfo.image.height,
        child: RawImage(
          image: imageInfo.image,
          scale: imageInfo.scale,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _InboxUrlPreview extends StatelessWidget {
  const _InboxUrlPreview({required this.data});

  final UrlPreviewData data;

  @override
  Widget build(BuildContext context) {
    final image = data.image;
    final imageWidth = data.imageWidth;
    final imageHeight = data.imageHeight;
    final aspectRatio =
        imageWidth != null &&
            imageHeight != null &&
            imageWidth > 0 &&
            imageHeight > 0
        ? imageWidth / imageHeight
        : 16 / 9;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (image != null) ...[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: AspectRatio(
                    aspectRatio: aspectRatio,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image(
                        image: image,
                        fit: BoxFit.cover,
                        semanticLabel: 'Link preview image',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (data.title != null) Text(data.title!),
              if (data.description != null) Text(data.description!),
            ],
          ),
        ),
      ),
    );
  }
}
