import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intergalactic/client/components/stories/story_component.dart';

const double storyVideoPortraitAspectRatio = 9 / 16;
const double storyVideoLandscapeAspectRatio = 16 / 9;

double storyVideoCanvasAspectRatio(StoryVideoCanvasMode mode) {
  return mode.aspectRatio;
}

Size storyVideoCanvasSizeForConstraints({
  required BoxConstraints constraints,
  required StoryVideoCanvasMode canvasMode,
  double? maxDesktopWidth,
}) {
  final maxWidth = maxDesktopWidth == null
      ? constraints.maxWidth
      : math.min(constraints.maxWidth, maxDesktopWidth);
  final maxHeight = constraints.maxHeight;
  if (maxWidth <= 0 || maxHeight <= 0) {
    return Size.zero;
  }

  final aspectRatio = storyVideoCanvasAspectRatio(canvasMode);
  final heightForWidth = maxWidth / aspectRatio;
  if (heightForWidth <= maxHeight) {
    return Size(maxWidth, heightForWidth);
  }
  return Size(maxHeight * aspectRatio, maxHeight);
}

BoxDecoration storyVideoBackgroundDecoration({
  required Color backgroundColor,
  required Color backgroundGradientColor,
  required StoryBackgroundMode backgroundMode,
  BorderRadius? borderRadius,
  Border? border,
  List<BoxShadow>? boxShadow,
}) {
  return BoxDecoration(
    color: backgroundMode == StoryBackgroundMode.solid ? backgroundColor : null,
    gradient: backgroundMode == StoryBackgroundMode.gradient
        ? LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [backgroundColor, backgroundGradientColor],
          )
        : null,
    borderRadius: borderRadius,
    border: border,
    boxShadow: boxShadow,
  );
}

class StoryVideoCompositionLayout {
  const StoryVideoCompositionLayout({
    required this.canvasRect,
    required this.mediaDisplayRect,
    required this.mediaSourceSize,
    required this.nonMediaRects,
    required this.usesBakedLetterboxCrop,
    required this.innerFit,
  });

  final Rect canvasRect;
  final Rect mediaDisplayRect;
  final Size mediaSourceSize;
  final List<Rect> nonMediaRects;
  final bool usesBakedLetterboxCrop;
  final BoxFit innerFit;
}

StoryVideoCompositionLayout storyVideoCompositionLayout({
  required Size canvasSize,
  required StoryVideoFitMode fitMode,
  required int? mediaWidth,
  required int? mediaHeight,
  int? displayWidth,
  int? displayHeight,
  bool hasBakedLetterbox = false,
}) {
  final canvasRect = Offset.zero & canvasSize;
  if (canvasSize.width <= 0 || canvasSize.height <= 0) {
    return StoryVideoCompositionLayout(
      canvasRect: canvasRect,
      mediaDisplayRect: canvasRect,
      mediaSourceSize: Size.zero,
      nonMediaRects: const [],
      usesBakedLetterboxCrop: false,
      innerFit: storyVideoInnerFit(fitMode),
    );
  }

  final mediaFrameSize = storyVideoMediaFrameSize(
    canvasSize: canvasSize,
    fitMode: fitMode,
    mediaWidth: mediaWidth,
    mediaHeight: mediaHeight,
    displayWidth: displayWidth,
    displayHeight: displayHeight,
  );
  final mediaDisplayRect = Rect.fromCenter(
    center: canvasRect.center,
    width: math.min(canvasSize.width, mediaFrameSize.width),
    height: math.min(canvasSize.height, mediaFrameSize.height),
  );
  final hasMediaSource =
      mediaWidth != null &&
      mediaHeight != null &&
      mediaWidth > 0 &&
      mediaHeight > 0;
  final usesBakedLetterboxCrop =
      fitMode == StoryVideoFitMode.fit &&
      hasBakedLetterbox &&
      hasMediaSource &&
      displayWidth != null &&
      displayHeight != null &&
      displayWidth > 0 &&
      displayHeight > 0;
  return StoryVideoCompositionLayout(
    canvasRect: canvasRect,
    mediaDisplayRect: mediaDisplayRect,
    mediaSourceSize: hasMediaSource
        ? Size(mediaWidth.toDouble(), mediaHeight.toDouble())
        : mediaDisplayRect.size,
    nonMediaRects: _subtractCenteredRect(canvasRect, mediaDisplayRect),
    usesBakedLetterboxCrop: usesBakedLetterboxCrop,
    innerFit: usesBakedLetterboxCrop
        ? BoxFit.fill
        : storyVideoInnerFit(fitMode, hasBakedLetterbox: false),
  );
}

List<Rect> _subtractCenteredRect(Rect canvasRect, Rect mediaRect) {
  if (canvasRect.isEmpty || mediaRect.isEmpty) {
    return const [];
  }
  final clippedMedia = mediaRect.intersect(canvasRect);
  if (clippedMedia.isEmpty || clippedMedia == canvasRect) {
    return const [];
  }

  final rects = <Rect>[];
  if (clippedMedia.top > canvasRect.top) {
    rects.add(
      Rect.fromLTRB(
        canvasRect.left,
        canvasRect.top,
        canvasRect.right,
        clippedMedia.top,
      ),
    );
  }
  if (clippedMedia.bottom < canvasRect.bottom) {
    rects.add(
      Rect.fromLTRB(
        canvasRect.left,
        clippedMedia.bottom,
        canvasRect.right,
        canvasRect.bottom,
      ),
    );
  }
  if (clippedMedia.left > canvasRect.left) {
    rects.add(
      Rect.fromLTRB(
        canvasRect.left,
        clippedMedia.top,
        clippedMedia.left,
        clippedMedia.bottom,
      ),
    );
  }
  if (clippedMedia.right < canvasRect.right) {
    rects.add(
      Rect.fromLTRB(
        clippedMedia.right,
        clippedMedia.top,
        canvasRect.right,
        clippedMedia.bottom,
      ),
    );
  }
  return List.unmodifiable(rects.where((rect) => !rect.isEmpty));
}

Size storyVideoMediaFrameSize({
  required Size canvasSize,
  required StoryVideoFitMode fitMode,
  required int? mediaWidth,
  required int? mediaHeight,
  int? displayWidth,
  int? displayHeight,
}) {
  final hasDisplaySize =
      displayWidth != null &&
      displayHeight != null &&
      displayWidth > 0 &&
      displayHeight > 0;
  final layoutWidth = hasDisplaySize ? displayWidth : mediaWidth;
  final layoutHeight = hasDisplaySize ? displayHeight : mediaHeight;
  if (fitMode != StoryVideoFitMode.fit ||
      canvasSize.width <= 0 ||
      canvasSize.height <= 0 ||
      layoutWidth == null ||
      layoutHeight == null ||
      layoutWidth <= 0 ||
      layoutHeight <= 0) {
    return canvasSize;
  }

  final mediaRatio = layoutWidth / layoutHeight;
  final canvasRatio = canvasSize.width / canvasSize.height;
  if (!mediaRatio.isFinite || mediaRatio <= 0) {
    return canvasSize;
  }

  if (mediaRatio > canvasRatio) {
    final height = canvasSize.width / mediaRatio;
    return Size(canvasSize.width, math.max(1.0, height));
  }

  final width = canvasSize.height * mediaRatio;
  return Size(math.max(1.0, width), canvasSize.height);
}

BoxFit storyVideoInnerFit(
  StoryVideoFitMode fitMode, {
  bool hasBakedLetterbox = false,
}) {
  // Baked-letterbox handling is owned by StoryVideoMediaLayer so callers do
  // not reintroduce zoomed crops by covering ordinary Fit videos.
  return switch (fitMode) {
    StoryVideoFitMode.fit => BoxFit.contain,
    StoryVideoFitMode.fill => BoxFit.cover,
  };
}

class StoryVideoMediaLayer extends StatelessWidget {
  const StoryVideoMediaLayer({
    super.key,
    required this.layout,
    required this.builder,
  });

  final StoryVideoCompositionLayout layout;
  final Widget Function(BoxFit fit) builder;

  @override
  Widget build(BuildContext context) {
    if (layout.usesBakedLetterboxCrop &&
        layout.mediaSourceSize.width > 0 &&
        layout.mediaSourceSize.height > 0) {
      return ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: layout.mediaSourceSize.width,
            height: layout.mediaSourceSize.height,
            child: builder(BoxFit.fill),
          ),
        ),
      );
    }

    return builder(layout.innerFit);
  }
}

class StoryVideoBackgroundMatte extends StatelessWidget {
  const StoryVideoBackgroundMatte({
    super.key,
    required this.rects,
    required this.backgroundColor,
    required this.backgroundGradientColor,
    required this.backgroundMode,
  });

  final List<Rect> rects;
  final Color backgroundColor;
  final Color backgroundGradientColor;
  final StoryBackgroundMode backgroundMode;

  @override
  Widget build(BuildContext context) {
    if (rects.isEmpty) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: CustomPaint(
        painter: _StoryVideoBackgroundMattePainter(
          rects: rects,
          backgroundColor: backgroundColor,
          backgroundGradientColor: backgroundGradientColor,
          backgroundMode: backgroundMode,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _StoryVideoBackgroundMattePainter extends CustomPainter {
  const _StoryVideoBackgroundMattePainter({
    required this.rects,
    required this.backgroundColor,
    required this.backgroundGradientColor,
    required this.backgroundMode,
  });

  final List<Rect> rects;
  final Color backgroundColor;
  final Color backgroundGradientColor;
  final StoryBackgroundMode backgroundMode;

  @override
  void paint(Canvas canvas, Size size) {
    paintStoryVideoBackgroundMatte(
      canvas: canvas,
      size: size,
      rects: rects,
      backgroundColor: backgroundColor,
      backgroundGradientColor: backgroundGradientColor,
      backgroundMode: backgroundMode,
    );
  }

  @override
  bool shouldRepaint(_StoryVideoBackgroundMattePainter oldDelegate) {
    return oldDelegate.rects != rects ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.backgroundGradientColor != backgroundGradientColor ||
        oldDelegate.backgroundMode != backgroundMode;
  }
}

@visibleForTesting
void paintStoryVideoBackgroundMatte({
  required Canvas canvas,
  required Size size,
  required List<Rect> rects,
  required Color backgroundColor,
  required Color backgroundGradientColor,
  required StoryBackgroundMode backgroundMode,
}) {
  if (size.width <= 0 || size.height <= 0 || rects.isEmpty) {
    return;
  }

  final canvasRect = Offset.zero & size;
  final paint = Paint();
  if (backgroundMode == StoryBackgroundMode.gradient) {
    paint.shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [backgroundColor, backgroundGradientColor],
    ).createShader(canvasRect);
  } else {
    paint.color = backgroundColor;
  }

  for (final rect in rects) {
    final clipped = rect.intersect(canvasRect);
    if (clipped.isEmpty) {
      continue;
    }
    canvas.drawRect(clipped, paint);
  }
}
