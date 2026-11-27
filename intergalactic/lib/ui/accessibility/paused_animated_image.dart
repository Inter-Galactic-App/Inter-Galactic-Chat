import 'package:flutter/material.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';

class PausedAnimatedImage extends StatefulWidget {
  const PausedAnimatedImage({
    required this.image,
    super.key,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.repeat = ImageRepeat.noRepeat,
    this.matchTextDirection = false,
    this.filterQuality = FilterQuality.medium,
    this.isAntiAlias = false,
    this.color,
    this.colorBlendMode,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.errorBuilder,
    this.placeholder,
  });

  final ImageProvider image;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final ImageRepeat repeat;
  final bool matchTextDirection;
  final FilterQuality filterQuality;
  final bool isAntiAlias;
  final Color? color;
  final BlendMode? colorBlendMode;
  final String? semanticLabel;
  final bool excludeFromSemantics;
  final ImageErrorWidgetBuilder? errorBuilder;
  final Widget? placeholder;

  @override
  State<PausedAnimatedImage> createState() => _PausedAnimatedImageState();
}

class _PausedAnimatedImageState extends State<PausedAnimatedImage> {
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;
  ImageInfo? _firstFrame;
  Object? _lastError;
  StackTrace? _lastStackTrace;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updatePausedImage();
  }

  @override
  void didUpdateWidget(covariant PausedAnimatedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image ||
        oldWidget.width != widget.width ||
        oldWidget.height != widget.height) {
      _clearPausedFrame();
    }
    _updatePausedImage();
  }

  @override
  void dispose() {
    _stopListening();
    _firstFrame?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pauseAnimatedMedia =
        AccessibilityScope.of(context).pauseAnimatedMedia;
    if (!pauseAnimatedMedia) {
      return Image(
        image: widget.image,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        alignment: widget.alignment,
        repeat: widget.repeat,
        matchTextDirection: widget.matchTextDirection,
        filterQuality: widget.filterQuality,
        isAntiAlias: widget.isAntiAlias,
        color: widget.color,
        colorBlendMode: widget.colorBlendMode,
        semanticLabel: widget.semanticLabel,
        excludeFromSemantics: widget.excludeFromSemantics,
        errorBuilder: widget.errorBuilder,
      );
    }

    if (_lastError != null) {
      final errorBuilder = widget.errorBuilder;
      if (errorBuilder != null) {
        return errorBuilder(context, _lastError!, _lastStackTrace);
      }
      return SizedBox(width: widget.width, height: widget.height);
    }

    final frame = _firstFrame;
    if (frame == null) {
      return widget.placeholder ??
          SizedBox(width: widget.width, height: widget.height);
    }

    Widget child = RawImage(
      image: frame.image,
      scale: frame.scale,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      repeat: widget.repeat,
      matchTextDirection: widget.matchTextDirection,
      filterQuality: widget.filterQuality,
      isAntiAlias: widget.isAntiAlias,
      color: widget.color,
      colorBlendMode: widget.colorBlendMode,
    );

    if (!widget.excludeFromSemantics) {
      child = Semantics(
        image: true,
        label: widget.semanticLabel,
        child: child,
      );
    }

    return child;
  }

  void _updatePausedImage() {
    if (!AccessibilityScope.of(context).pauseAnimatedMedia) {
      _stopListening();
      _clearPausedFrame();
      return;
    }

    final stream = widget.image.resolve(
      createLocalImageConfiguration(
        context,
        size: widget.width != null && widget.height != null
            ? Size(widget.width!, widget.height!)
            : null,
      ),
    );

    if (_imageStream?.key == stream.key) {
      return;
    }

    _stopListening();
    _clearPausedFrame();
    _imageStream = stream;
    _imageStreamListener = ImageStreamListener(
      (imageInfo, _) {
        _stopListening();
        final ownedFrame = imageInfo.clone();
        imageInfo.dispose();
        if (!mounted) {
          ownedFrame.dispose();
          return;
        }
        setState(() {
          _firstFrame?.dispose();
          _firstFrame = ownedFrame;
          _lastError = null;
          _lastStackTrace = null;
        });
      },
      onError: (error, stackTrace) {
        _stopListening();
        if (!mounted) {
          return;
        }
        setState(() {
          _firstFrame?.dispose();
          _firstFrame = null;
          _lastError = error;
          _lastStackTrace = stackTrace;
        });
      },
    );
    stream.addListener(_imageStreamListener!);
  }

  void _stopListening() {
    final listener = _imageStreamListener;
    if (listener == null) {
      return;
    }
    _imageStream?.removeListener(listener);
    _imageStreamListener = null;
    _imageStream = null;
  }

  void _clearPausedFrame() {
    _firstFrame?.dispose();
    _firstFrame = null;
    _lastError = null;
    _lastStackTrace = null;
  }
}
