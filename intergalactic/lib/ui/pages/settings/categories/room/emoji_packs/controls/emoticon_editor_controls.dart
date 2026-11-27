import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_draft_store_models.dart';
import 'package:intergalactic/client/components/emoticon/image_cutout_service.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/emoticon_editor_controller.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Shared control widgets for the emoticon creator. The mobile tool trays and
/// the desktop docked panel both import these bodies, so a control change
/// reflects on both platforms (single implementation, no duplication).

class EmoticonCreatorStrings {
  static String get promptEmoticonCreatorSelectPhoto => Intl.message(
    "Select photo",
    name: "promptEmoticonCreatorSelectPhoto",
    desc: "Button text for picking a source photo for emoticon creation",
  );

  static String get promptEmoticonCreatorChangePhoto => Intl.message(
    "Change photo",
    name: "promptEmoticonCreatorChangePhoto",
    desc: "Button text for replacing the source photo",
  );

  static String get promptEmoticonCreatorCropPhoto => Intl.message(
    "Crop",
    name: "promptEmoticonCreatorCropPhoto",
    desc: "Button text for cropping the selected source photo",
  );

  static String get promptEmoticonCreatorAutoCutout => Intl.message(
    "Auto",
    name: "promptEmoticonCreatorAutoCutout",
    desc: "Button text for automatic background removal",
  );

  static String get promptEmoticonCreatorEraseBrush => Intl.message(
    "Erase",
    name: "promptEmoticonCreatorEraseBrush",
    desc: "Button text for manual erase brush",
  );

  static String get promptEmoticonCreatorRestoreBrush => Intl.message(
    "Restore",
    name: "promptEmoticonCreatorRestoreBrush",
    desc: "Button text for manual restore brush",
  );

  static String get promptEmoticonCreatorResetCutout => Intl.message(
    "Reset",
    name: "promptEmoticonCreatorResetCutout",
    desc: "Button text for resetting the generated cutout",
  );

  static String get promptEmoteName => Intl.message(
    "Emote name",
    name: "promptEmoteName",
    desc: "Prompt for the input of the name of an emoji",
  );

  static String get promptConfirmSaveEmoticon => Intl.message(
    "Save!",
    name: "promptConfirmSaveEmoticon",
    desc:
        "Prompt to confirm the creation of an Emoticon Pack, Emoji, or Sticker",
  );

  static String get promptEmoticonCreatorAdvancedEdit => Intl.message(
    "Advanced edit",
    name: "promptEmoticonCreatorAdvancedEdit",
    desc: "Button text that opens the full cutout editor",
  );

  static String get titleEmoticonCutoutEditor => Intl.message(
    "Cutout editor",
    name: "titleEmoticonCutoutEditor",
    desc: "Title of the full emoticon cutout editor surface",
  );

  static String get promptEmoticonEditorDone => Intl.message(
    "Done",
    name: "promptEmoticonEditorDone",
    desc: "Button that keeps the editor result and returns to the quick card",
  );
}

extension CutoutPreviewBackgroundLabel on CutoutPreviewBackground {
  String get label {
    return switch (this) {
      CutoutPreviewBackground.checkerboard => 'Checkerboard',
      CutoutPreviewBackground.dark => 'Dark',
      CutoutPreviewBackground.light => 'Light',
    };
  }

  String get semanticLabel {
    return switch (this) {
      CutoutPreviewBackground.checkerboard => 'checkerboard',
      CutoutPreviewBackground.dark => 'dark',
      CutoutPreviewBackground.light => 'light',
    };
  }

  IconData get icon {
    return switch (this) {
      CutoutPreviewBackground.checkerboard => Icons.grid_4x4_rounded,
      CutoutPreviewBackground.dark => Icons.dark_mode_outlined,
      CutoutPreviewBackground.light => Icons.light_mode_outlined,
    };
  }
}

extension EmoticonToolGroupPresentation on EmoticonToolGroup {
  String get label {
    return switch (this) {
      EmoticonToolGroup.cutout => 'Cutout',
      EmoticonToolGroup.brush => 'Brush',
      // The group owns photo *sourcing* as well as cropping on both platforms
      // now (KTD-3). The enum value stays `crop`, so every widget key —
      // `emoticon-tool-tab-crop`, `emoticon-desktop-group-crop` — is unchanged.
      EmoticonToolGroup.crop => 'Photo',
      EmoticonToolGroup.output => 'Output',
      EmoticonToolGroup.preview => 'Preview',
      EmoticonToolGroup.drafts => 'Drafts',
    };
  }

  IconData get icon {
    return switch (this) {
      EmoticonToolGroup.cutout => Icons.auto_fix_high_rounded,
      EmoticonToolGroup.brush => Icons.brush_outlined,
      EmoticonToolGroup.crop => Icons.image_outlined,
      EmoticonToolGroup.output => Icons.tune_rounded,
      EmoticonToolGroup.preview => Icons.contrast_rounded,
      EmoticonToolGroup.drafts => Icons.history_rounded,
    };
  }
}

/// Fixed neutral mattes used behind the cutout. They are deliberately not
/// theme colours: the point is to inspect transparent edges regardless of
/// whether the app theme is light, dark, or custom.
const Color emoticonDarkMatte = Color(0xFF151515);
const Color emoticonLightMatte = Color(0xFFF6F6F6);

/// Paints the preview backdrop into [canvas].
///
/// Shared by [EmoticonPreviewBackgroundSurface] and by the erase stroke
/// overlay, which reveals the backdrop through the dabs; both must produce the
/// same pattern in the same phase or an erased dab would not match the
/// surrounding transparency.
void paintEmoticonBackdrop(
  Canvas canvas,
  Size size,
  CutoutPreviewBackground mode, {
  required Color checkerLight,
  required Color checkerDark,
}) {
  switch (mode) {
    case CutoutPreviewBackground.checkerboard:
      const tile = 12.0;
      final paint = Paint();
      for (var y = 0.0; y < size.height; y += tile) {
        for (var x = 0.0; x < size.width; x += tile) {
          final even = ((x / tile).floor() + (y / tile).floor()).isEven;
          paint.color = even ? checkerLight : checkerDark;
          canvas.drawRect(Rect.fromLTWH(x, y, tile, tile), paint);
        }
      }
    case CutoutPreviewBackground.dark:
      canvas.drawRect(Offset.zero & size, Paint()..color = emoticonDarkMatte);
    case CutoutPreviewBackground.light:
      canvas.drawRect(Offset.zero & size, Paint()..color = emoticonLightMatte);
  }
}

class EmoticonCheckerboardPainter extends CustomPainter {
  const EmoticonCheckerboardPainter({required this.light, required this.dark});

  final Color light;
  final Color dark;

  @override
  void paint(Canvas canvas, Size size) {
    paintEmoticonBackdrop(
      canvas,
      size,
      CutoutPreviewBackground.checkerboard,
      checkerLight: light,
      checkerDark: dark,
    );
  }

  @override
  bool shouldRepaint(covariant EmoticonCheckerboardPainter oldDelegate) {
    return oldDelegate.light != light || oldDelegate.dark != dark;
  }
}

/// Draws the source photo aligned with the cutout so its pixels land exactly
/// where the cutout's do (KTD-2a).
///
/// Used twice: at low opacity *below* the cutout as the Restore aiming ghost,
/// and at full opacity *inside* the stroke dabs as the Restore reveal.
class EmoticonSourceGhostPainter extends CustomPainter {
  const EmoticonSourceGhostPainter({
    required this.sourceImage,
    required this.imageRect,
    required this.destinationRect,
    required this.opacity,
  });

  final ui.Image sourceImage;
  final Rect imageRect;
  final Rect destinationRect;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..clipRect(imageRect);
    canvas.drawImageRect(
      sourceImage,
      Rect.fromLTWH(
        0,
        0,
        sourceImage.width.toDouble(),
        sourceImage.height.toDouble(),
      ),
      destinationRect,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(0, 0, 0, opacity),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant EmoticonSourceGhostPainter oldDelegate) {
    return !identical(oldDelegate.sourceImage, sourceImage) ||
        oldDelegate.imageRect != imageRect ||
        oldDelegate.destinationRect != destinationRect ||
        oldDelegate.opacity != opacity;
  }
}

/// Marks where the exported image actually ends.
///
/// Without this the backdrop fills the whole canvas, so Square crop and Tight
/// crop look identical: the subject is drawn at the same size either way and
/// the only difference — how much transparent margin the output carries — is
/// invisible against a backdrop that extends past it. Dimming outside the
/// output rect and outlining it turns the artboard into something you can see
/// change shape.
class EmoticonOutputBoundsPainter extends CustomPainter {
  const EmoticonOutputBoundsPainter({
    required this.imageRect,
    required this.scrimColor,
    required this.borderColor,
  });

  final Rect imageRect;
  final Color scrimColor;
  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final surface = Offset.zero & size;
    if (imageRect.isEmpty || !surface.overlaps(imageRect)) {
      return;
    }

    final visible = imageRect.intersect(surface);
    if (visible.width < surface.width || visible.height < surface.height) {
      canvas.drawPath(
        Path()
          ..addRect(surface)
          ..addRect(visible)
          ..fillType = PathFillType.evenOdd,
        Paint()..color = scrimColor,
      );
    }

    canvas.drawRect(
      imageRect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = borderColor,
    );
  }

  @override
  bool shouldRepaint(covariant EmoticonOutputBoundsPainter oldDelegate) {
    return oldDelegate.imageRect != imageRect ||
        oldDelegate.scrimColor != scrimColor ||
        oldDelegate.borderColor != borderColor;
  }
}

/// The in-stroke overlay: what the dabs painted so far will look like, drawn
/// above the latched cutout frame while the production render is deferred to
/// stroke end (KTD-2).
///
/// Both modes build the same shape — a `saveLayer` holding the union of the
/// dabs as an alpha mask — and then fill it with `BlendMode.srcIn`:
///
/// * **Erase** fills with the preview backdrop, so the matte shows through the
///   stroke exactly as it will once the pixels are actually gone.
/// * **Restore** fills with the aligned source photo, so the real pixels come
///   back inside the stroke and nowhere else.
///
/// The overlay deliberately does not reproduce edge softness, outline, shadow,
/// or the re-crop; those arrive with the settle.
class EmoticonStrokeOverlayPainter extends CustomPainter {
  const EmoticonStrokeOverlayPainter({
    required this.dabs,
    required this.mode,
    required this.imageRect,
    required this.controller,
    required this.background,
    required this.checkerLight,
    required this.checkerDark,
    this.sourceImage,
    this.sourceDestinationRect,
  });

  final List<EmoticonStrokeDab> dabs;
  final CutoutBrushMode mode;
  final Rect imageRect;
  final EmoticonEditorController controller;
  final CutoutPreviewBackground background;
  final Color checkerLight;
  final Color checkerDark;
  final ui.Image? sourceImage;
  final Rect? sourceDestinationRect;

  bool get _canPaint {
    if (dabs.isEmpty || imageRect.isEmpty) {
      return false;
    }
    if (mode == CutoutBrushMode.restore) {
      return sourceImage != null && sourceDestinationRect != null;
    }
    return true;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (!_canPaint) {
      return;
    }

    canvas
      ..save()
      ..clipRect(imageRect)
      ..saveLayer(imageRect, Paint());

    for (final dab in dabs) {
      final radius = controller.brushRadiusPixels(
        imageRect,
        radiusFraction: dab.radiusFraction,
      );
      final centre = Offset(
        imageRect.left + imageRect.width * dab.normalizedX,
        imageRect.top + imageRect.height * dab.normalizedY,
      );
      final strength = dab.strength.clamp(0.0, 1.0);
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          // `applyBrush` weights each pixel by `(1 - distance / radius) *
          // strength` and touches nothing beyond `radius`. A radial gradient
          // reproduces that profile exactly; the earlier `MaskFilter.blur`
          // approximated it with a Gaussian *and* spilled past the radius, so
          // the overlay and the settled render disagreed at every stroke edge.
          ..shader = ui.Gradient.radial(
            centre,
            radius,
            <Color>[
              Color.fromRGBO(0, 0, 0, strength),
              const Color.fromRGBO(0, 0, 0, 0),
            ],
            const <double>[0, 1],
          ),
      );
    }

    final fill = Paint()..blendMode = BlendMode.srcIn;
    if (mode == CutoutBrushMode.restore) {
      final source = sourceImage!;
      canvas.drawImageRect(
        source,
        Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
        sourceDestinationRect!,
        fill..filterQuality = FilterQuality.medium,
      );
    } else {
      canvas.saveLayer(imageRect, fill);
      paintEmoticonBackdrop(
        canvas,
        size,
        background,
        checkerLight: checkerLight,
        checkerDark: checkerDark,
      );
      canvas.restore();
    }

    canvas
      ..restore()
      ..restore();
  }

  @override
  bool shouldRepaint(covariant EmoticonStrokeOverlayPainter oldDelegate) {
    return oldDelegate.dabs.length != dabs.length ||
        !identical(oldDelegate.dabs, dabs) ||
        oldDelegate.mode != mode ||
        oldDelegate.imageRect != imageRect ||
        oldDelegate.background != background ||
        !identical(oldDelegate.sourceImage, sourceImage) ||
        oldDelegate.sourceDestinationRect != sourceDestinationRect;
  }
}

class EmoticonBrushCursorPainter extends CustomPainter {
  const EmoticonBrushCursorPainter({
    required this.center,
    required this.radius,
    required this.color,
    required this.outlineColor,
  });

  final Offset center;
  final double radius;
  final Color color;
  final Color outlineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final outerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = outlineColor.withValues(alpha: 0.72);
    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color.withValues(alpha: 0.95);

    canvas
      ..drawCircle(center, radius, outerPaint)
      ..drawCircle(center, radius, innerPaint);
  }

  @override
  bool shouldRepaint(covariant EmoticonBrushCursorPainter oldDelegate) {
    return oldDelegate.center != center ||
        oldDelegate.radius != radius ||
        oldDelegate.color != color ||
        oldDelegate.outlineColor != outlineColor;
  }
}

class EmoticonPreviewBackgroundSurface extends StatelessWidget {
  const EmoticonPreviewBackgroundSurface({
    required this.mode,
    required this.child,
    super.key,
  });

  final CutoutPreviewBackground mode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return switch (mode) {
      CutoutPreviewBackground.checkerboard => CustomPaint(
        painter: EmoticonCheckerboardPainter(
          light: theme.colorScheme.surfaceContainerHigh,
          dark: theme.colorScheme.surfaceContainerLow,
        ),
        child: child,
      ),
      CutoutPreviewBackground.dark => ColoredBox(
        // Fixed neutral mattes help users inspect transparent edges regardless
        // of whether the current app theme is light, dark, or custom.
        color: emoticonDarkMatte,
        child: child,
      ),
      CutoutPreviewBackground.light => ColoredBox(
        color: emoticonLightMatte,
        child: child,
      ),
    };
  }
}

/// Decode width for a preview that will be displayed at [logicalWidth],
/// rounded up to whole device pixels. Display only — every save path keeps the
/// full-resolution bytes (FR7).
int? _previewCacheWidth(BuildContext context, double logicalWidth) {
  if (!logicalWidth.isFinite || logicalWidth <= 0) {
    return null;
  }
  final devicePixels =
      logicalWidth * MediaQuery.devicePixelRatioOf(context).clamp(1.0, 4.0);
  return math.max(1, devicePixels.ceil());
}

class EmoticonMiniPreview extends StatelessWidget {
  const EmoticonMiniPreview({
    required this.bytes,
    required this.size,
    required this.background,
    super.key,
  });

  final Uint8List? bytes;
  final double size;
  final CutoutPreviewBackground background;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: size <= 40
          ? 'Emoji-size preview on ${background.semanticLabel} background'
          : 'Sticker-size preview on ${background.semanticLabel} background',
      child: EmoticonPreviewBackgroundSurface(
        mode: background,
        child: SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.38),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: bytes == null
                ? Icon(
                    Icons.image_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: size * 0.42,
                  )
                : Image.memory(
                    bytes!,
                    fit: BoxFit.contain,
                    // Keep the last frame while the next brush render decodes
                    // instead of blanking to the backdrop (FR1).
                    gaplessPlayback: true,
                    // These tiles judge the emoji at real size; decoding the
                    // full-resolution PNG for a 32/72px box just evicts the
                    // app's image cache (FR4).
                    cacheWidth: _previewCacheWidth(context, size),
                  ),
          ),
        ),
      ),
    );
  }
}

/// The interactive cutout canvas: preview image on a selectable backdrop with
/// the brush gesture surface, the live stroke overlay, the Restore ghost, the
/// cursor ring, and pinch/scroll zoom. Fills its constraints when [square] is
/// false (mobile canvas-dominant editor) or keeps the legacy 1:1 aspect
/// (desktop preview column).
///
/// Everything the canvas draws is positioned from one rect —
/// [EmoticonEditorController.zoomedImageRect] — so the overlay can never drift
/// from the pixels it is describing (KTD-2b).
class EmoticonCutoutCanvas extends StatefulWidget {
  const EmoticonCutoutCanvas({
    required this.controller,
    this.square = true,
    this.onPickSourceImage,
    super.key,
  });

  final EmoticonEditorController controller;
  final bool square;

  /// When set and no image has been chosen yet, the empty placeholder becomes
  /// a labelled tap target (U5). The stranded user is looking at the canvas,
  /// not at a tray.
  final VoidCallback? onPickSourceImage;

  @override
  State<EmoticonCutoutCanvas> createState() => _EmoticonCutoutCanvasState();
}

class _EmoticonCutoutCanvasState extends State<EmoticonCutoutCanvas> {
  static const double _ghostOpacity = 0.22;

  Offset? brushPreviewPosition;

  /// The decoded source photo, held while Restore is selected so the ghost and
  /// the reveal do not re-decode per frame.
  ui.Image? _sourceImage;
  Uint8List? _sourceImageBytes;
  bool _decodingSource = false;

  int _activePointers = 0;
  bool _gestureWasMultiPointer = false;
  bool _middleDragPanning = false;
  Offset? _middleDragLastPosition;
  double _gestureStartZoomScale = 1;
  Offset _gestureZoomAnchor = Offset.zero;

  EmoticonEditorController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_handleControllerChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncSourceImage();
  }

  @override
  void didUpdateWidget(covariant EmoticonCutoutCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      // The decoded source belongs to the OLD controller. Without this the
      // image and its bytes survive until the new controller happens to notify,
      // holding memory that no longer matches what the widget is showing.
      _syncSourceImage();
    }
  }

  @override
  void dispose() {
    controller.removeListener(_handleControllerChanged);
    _disposeSourceImage();
    super.dispose();
  }

  void _handleControllerChanged() {
    // The host rebuilds this widget through its own ListenableBuilder; this
    // listener exists only to keep the decoded source in step with the tool
    // and the source bytes.
    if (!mounted) {
      return;
    }
    _syncSourceImage();
  }

  void _disposeSourceImage() {
    _sourceImage?.dispose();
    _sourceImage = null;
    _sourceImageBytes = null;
  }

  bool get _wantsSourceImage =>
      controller.brushMode == CutoutBrushMode.restore &&
      controller.sourceImageData != null &&
      controller.cutoutResult != null;

  /// Called outside build (controller notifications, dependency changes).
  void _syncSourceImage() {
    if (!_wantsSourceImage) {
      if (_sourceImage != null || _sourceImageBytes != null) {
        setState(_disposeSourceImage);
      }
      return;
    }
    _startSourceDecodeIfNeeded();
  }

  /// Safe to call during build: it only ever *starts* an async decode, and the
  /// `setState` happens when that decode lands.
  void _startSourceDecodeIfNeeded() {
    if (!_wantsSourceImage) {
      return;
    }
    final bytes = controller.sourceImageData!;
    if (identical(_sourceImageBytes, bytes) ||
        _decodingSource ||
        // Wait for the first layout: decoding against a zero viewport would
        // pin a 64px ghost that never re-decodes, because the bytes match.
        controller.viewportSize.isEmpty) {
      return;
    }
    _decodingSource = true;
    unawaited(_decodeSourceImage(bytes));
  }

  Future<void> _decodeSourceImage(Uint8List bytes) async {
    try {
      final devicePixelRatio = MediaQuery.devicePixelRatioOf(
        context,
      ).clamp(1.0, 4.0);
      // Bounded by the canvas, not by the source resolution (FR4).
      final targetWidth = math.max(
        64,
        (controller.viewportSize.width * devicePixelRatio).ceil(),
      );
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
      );
      // try/finally, not a bare dispose after the await: the catch below
      // deliberately swallows decode failures, so a throwing getNextFrame would
      // otherwise leak the codec's native memory on every failed decode.
      final ui.FrameInfo frame;
      try {
        frame = await codec.getNextFrame();
      } finally {
        codec.dispose();
      }

      if (!mounted || !identical(controller.sourceImageData, bytes)) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _sourceImage?.dispose();
        _sourceImage = frame.image;
        _sourceImageBytes = bytes;
      });
    } catch (_) {
      // A source the engine already accepted failing to decode here is not
      // worth surfacing: the ghost is an aid, and the cutout still renders.
    } finally {
      _decodingSource = false;
    }
  }

  void _setBrushPreviewPosition(Offset position, Rect imageRect) {
    final nextPosition = imageRect.contains(position) ? position : null;
    if (brushPreviewPosition == nextPosition || !mounted) {
      return;
    }

    setState(() {
      brushPreviewPosition = nextPosition;
    });
  }

  void _clearBrushPreviewPosition() {
    if (brushPreviewPosition == null || !mounted) {
      return;
    }

    setState(() {
      brushPreviewPosition = null;
    });
  }

  // -------------------------------------------------------------------
  // Gestures (KTD-2c)
  // -------------------------------------------------------------------

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers++;
    if (_activePointers > 1) {
      _gestureWasMultiPointer = true;
    }
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons & kMiddleMouseButton != 0) {
      _middleDragPanning = true;
      _middleDragLastPosition = event.localPosition;
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_middleDragPanning) {
      return;
    }
    final last = _middleDragLastPosition;
    _middleDragLastPosition = event.localPosition;
    if (last != null) {
      controller.panZoomBy(event.localPosition - last);
    }
  }

  void _handlePointerRelease() {
    _activePointers = math.max(0, _activePointers - 1);
    if (_activePointers == 0) {
      _gestureWasMultiPointer = false;
      _middleDragPanning = false;
      _middleDragLastPosition = null;
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || controller.cutoutResult == null) {
      return;
    }

    // Claim the signal through the resolver instead of handling it inline.
    // A scroll event is delivered to every hit-test entry, so handling it here
    // and returning left the enclosing Scrollable free to scroll the editor
    // panel at the same time — zooming the canvas also scrolled the window.
    // The resolver runs exactly one callback, and registration order is
    // innermost-first, so the canvas wins over any ancestor scroll view.
    //
    // Registering only when the canvas will actually zoom keeps normal
    // scrolling of the surrounding panel working when the pointer is over a
    // canvas that has nothing to magnify.
    GestureBinding.instance.pointerSignalResolver.register(event, (
      PointerSignalEvent resolved,
    ) {
      if (resolved is! PointerScrollEvent) {
        return;
      }
      // Anchored at the pointer, never at the canvas centre: centre-anchored
      // zoom slides the detail you are aiming at out from under you.
      final anchor = controller.normalizedImagePoint(resolved.localPosition);
      final factor = math.exp(-resolved.scrollDelta.dy / 320);
      controller.setZoom(
        scale: controller.zoomScale * factor,
        focalPoint: resolved.localPosition,
        anchorNormalized: anchor,
      );
    });
  }

  bool get _shouldPaintOnSinglePointer =>
      !_gestureWasMultiPointer && !_middleDragPanning;

  void _handleScaleStart(ScaleStartDetails details, Rect imageRect) {
    // Latched unconditionally, including for a gesture that starts as painting.
    // A second pointer can join an open stroke, at which point
    // _handleScaleUpdate ends the stroke and pinches from _gestureStartZoomScale
    // - so if the paint branch returned without latching, that pinch would scale
    // from a stale value (1 on the first gesture). Symptom: magnify to 4x, paint,
    // add a second finger, and the canvas snaps back toward fit.
    _gestureStartZoomScale = controller.zoomScale;
    _gestureZoomAnchor = controller.normalizedImagePoint(
      details.localFocalPoint,
    );

    if (details.pointerCount >= 2 || !_shouldPaintOnSinglePointer) {
      return;
    }

    _setBrushPreviewPosition(details.localFocalPoint, imageRect);
    controller.beginBrushStroke();
    controller.applyBrushAt(details.localFocalPoint, imageRect);
  }

  void _handleScaleUpdate(ScaleUpdateDetails details, Rect imageRect) {
    if (details.pointerCount >= 2) {
      _gestureWasMultiPointer = true;
      if (controller.strokeActive) {
        // A half-committed stroke silently becoming a pinch is the "it didn't
        // paint" bug; end it and let it settle instead (FR10).
        unawaited(controller.endBrushStroke());
        _clearBrushPreviewPosition();
      }
      controller.setZoom(
        scale: _gestureStartZoomScale * details.scale,
        focalPoint: details.localFocalPoint,
        anchorNormalized: _gestureZoomAnchor,
      );
      return;
    }

    if (!controller.strokeActive) {
      return;
    }
    _setBrushPreviewPosition(details.localFocalPoint, imageRect);
    controller.applyBrushAt(details.localFocalPoint, imageRect);
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _clearBrushPreviewPosition();
    if (controller.strokeActive) {
      unawaited(controller.endBrushStroke());
    }
  }

  /// A tap is a one-dab stroke. It begins and ends in the same frame, so the
  /// overlay never renders for it (OQ-2) and exactly one render still runs.
  ///
  /// Deliberately **not** paired with a double-tap-to-zoom recogniser: a
  /// competing `DoubleTapGestureRecognizer` holds the arena open for the
  /// double-tap window, which delays every single dab by ~300ms and paints two
  /// dabs on the way to a zoom. Pinch, scroll-at-pointer and the fit-to-view
  /// control cover the same affordance without taxing the primary interaction.
  void _handleTapDown(TapDownDetails details, Rect imageRect) {
    _setBrushPreviewPosition(details.localPosition, imageRect);
    controller.beginBrushStroke();
    controller.applyBrushAt(details.localPosition, imageRect);
    unawaited(controller.endBrushStroke());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final previewBytes =
        controller.cutoutResult?.pngBytes ??
        controller.imageData ??
        controller.sourceImageData;
    final previewLabel =
        'Transparent cutout preview on ${controller.previewBackground.semanticLabel} background. Drag on the image to refine the mask.';
    final canEditMask = controller.canEditMask;

    final surface = LayoutBuilder(
      builder: (context, previewConstraints) {
        final size = Size(
          previewConstraints.maxWidth,
          previewConstraints.maxHeight,
        );
        controller.setViewportSize(size);
        _startSourceDecodeIfNeeded();

        final hasGeometry = controller.displayImageWidth > 0;
        final imageRect = controller.zoomedImageRect();
        // Publish the decode width once and let both the image widget and the
        // settle precache read it back, so they cannot disagree.
        controller.setPreviewCacheWidth(_canvasCacheWidth(context, size));
        final brushPosition = canEditMask ? brushPreviewPosition : null;
        final cursorRadius = controller.brushRadiusPixels(imageRect);
        final sourceDestination = controller.sourceImageDestinationRect(
          imageRect,
        );
        final showGhost =
            controller.brushMode == CutoutBrushMode.restore &&
            controller.cutoutResult != null &&
            _sourceImage != null &&
            sourceDestination != null;
        final strokeDabs = controller.strokeDabs;

        return Listener(
          onPointerDown: _handlePointerDown,
          onPointerMove: _handlePointerMove,
          onPointerUp: (_) => _handlePointerRelease(),
          onPointerCancel: (_) => _handlePointerRelease(),
          onPointerSignal: _handlePointerSignal,
          child: MouseRegion(
            cursor: canEditMask
                ? SystemMouseCursors.precise
                : MouseCursor.defer,
            onHover: !canEditMask
                ? null
                : (event) =>
                      _setBrushPreviewPosition(event.localPosition, imageRect),
            onExit: (_) => _clearBrushPreviewPosition(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: !canEditMask
                  ? null
                  : (details) => _handleTapDown(details, imageRect),
              onTapUp: !canEditMask
                  ? null
                  : (_) => _clearBrushPreviewPosition(),
              onTapCancel: !canEditMask ? null : _clearBrushPreviewPosition,
              // The brush lives on the scale callbacks rather than onPan*
              // because Flutter asserts if one detector owns both, and zoom
              // needs the scale recogniser (KTD-2c).
              onScaleStart: !canEditMask
                  ? null
                  : (details) => _handleScaleStart(details, imageRect),
              onScaleUpdate: !canEditMask
                  ? null
                  : (details) => _handleScaleUpdate(details, imageRect),
              onScaleEnd: !canEditMask ? null : _handleScaleEnd,
              child: EmoticonPreviewBackgroundSurface(
                mode: controller.previewBackground,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.48),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Below the cutout, so it only shows through the
                        // transparent regions the user is aiming into.
                        if (showGhost)
                          IgnorePointer(
                            child: CustomPaint(
                              painter: EmoticonSourceGhostPainter(
                                sourceImage: _sourceImage!,
                                imageRect: imageRect,
                                destinationRect: sourceDestination,
                                opacity: _ghostOpacity,
                              ),
                            ),
                          ),
                        if (previewBytes == null)
                          _buildEmptyState(context)
                        else
                          Positioned.fromRect(
                            rect: imageRect,
                            child: Image.memory(
                              previewBytes,
                              // With known output geometry the rect *is* the
                              // image box, so fill it exactly; without it fall
                              // back to contain inside the zoomed rect.
                              fit: hasGeometry ? BoxFit.fill : BoxFit.contain,
                              filterQuality: FilterQuality.medium,
                              // Keep the previous frame on screen until the
                              // next one decodes — this is the strobe (FR1).
                              gaplessPlayback: true,
                              cacheWidth: controller.previewCacheWidth,
                            ),
                          ),
                        // Only meaningful once the output has real dimensions;
                        // before a cutout the rect is just the whole canvas.
                        if (hasGeometry)
                          IgnorePointer(
                            child: CustomPaint(
                              painter: EmoticonOutputBoundsPainter(
                                imageRect: imageRect,
                                scrimColor: Colors.black.withValues(
                                  alpha: 0.28,
                                ),
                                borderColor: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        if (strokeDabs.isNotEmpty)
                          IgnorePointer(
                            child: CustomPaint(
                              painter: EmoticonStrokeOverlayPainter(
                                dabs: strokeDabs,
                                mode: controller.strokeBrushMode,
                                imageRect: imageRect,
                                controller: controller,
                                background: controller.previewBackground,
                                checkerLight:
                                    theme.colorScheme.surfaceContainerHigh,
                                checkerDark:
                                    theme.colorScheme.surfaceContainerLow,
                                sourceImage: _sourceImage,
                                sourceDestinationRect: sourceDestination,
                              ),
                            ),
                          ),
                        if (brushPosition != null)
                          IgnorePointer(
                            child: CustomPaint(
                              painter: EmoticonBrushCursorPainter(
                                center: brushPosition,
                                radius: cursorRadius,
                                color: theme.colorScheme.primary,
                                outlineColor: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        if (controller.zoomScale >
                            EmoticonEditorController.minZoomScale)
                          _buildFitToViewControl(context),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    return Semantics(
      label: previewLabel,
      liveRegion: controller.processingCutout,
      child: widget.square
          ? AspectRatio(aspectRatio: 1, child: surface)
          : surface,
    );
  }

  /// Canvas decode width: the *viewport* in device pixels, scaled by the
  /// current magnification and hard-capped.
  ///
  /// Deliberately derived from the viewport rather than from `imageRect` or the
  /// output width: a stroke-end re-crop changes both of those, which would
  /// change the `ImageCache` key between the settle precache and the build that
  /// consumes it, and the precache would warm an entry nobody asks for.
  ///
  /// Display only — `cutoutResult.pngBytes`, the draft store, and every save
  /// path keep the full-resolution bytes (FR7).
  int? _canvasCacheWidth(BuildContext context, Size viewport) {
    if (viewport.isEmpty) {
      return null;
    }
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(
      context,
    ).clamp(1.0, 4.0);
    final width = viewport.width * controller.zoomScale * devicePixelRatio;
    if (!width.isFinite || width <= 0) {
      return null;
    }
    return math.min(4096, math.max(1, width.ceil()));
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final icon = Icon(
      Icons.add_photo_alternate_outlined,
      color: theme.colorScheme.onSurfaceVariant,
      size: 54,
    );
    final onPick = widget.onPickSourceImage;
    if (onPick == null) {
      return icon;
    }

    return Center(
      child: Semantics(
        // Its own node, not merged into the canvas: the canvas keeps its exact
        // preview label and the button is announced separately.
        container: true,
        // The Text child renders this same string, and container:true keeps it
        // as a separate node - so without this a screen reader announces the
        // label twice.
        excludeSemantics: true,
        button: true,
        label: EmoticonCreatorStrings.promptEmoticonCreatorSelectPhoto,
        child: InkWell(
          key: const ValueKey('emoticon-canvas-pick-photo'),
          onTap: onPick,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(height: 8),
                Text(
                  EmoticonCreatorStrings.promptEmoticonCreatorSelectPhoto,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Only present while magnified, so it costs nothing at rest.
  Widget _buildFitToViewControl(BuildContext context) {
    return Positioned(
      right: 8,
      bottom: 8,
      child: EmoticonCanvasOverlayButton(
        key: const ValueKey('emoticon-canvas-fit-to-view'),
        icon: Icons.zoom_out_map_rounded,
        tooltip: 'Fit to view',
        onPressed: controller.resetZoom,
      ),
    );
  }
}

class EmoticonPreviewBackgroundPicker extends StatelessWidget {
  const EmoticonPreviewBackgroundPicker({required this.controller, super.key});

  final EmoticonEditorController controller;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Preview background mode',
      value: controller.previewBackground.label,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: CutoutPreviewBackground.values
            .map((mode) {
              return FilterChip(
                label: Text(mode.label),
                avatar: Icon(mode.icon, size: 16),
                selected: controller.previewBackground == mode,
                onSelected: controller.loading
                    ? null
                    : (_) => controller.setPreviewBackground(mode),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

/// Sensitivity / Softness / Edge offset sliders (settle-to-apply) plus the
/// Auto and Reset engine actions.
class EmoticonAutoMaskControls extends StatelessWidget {
  const EmoticonAutoMaskControls({
    required this.controller,
    this.includeActions = true,
    super.key,
  });

  final EmoticonEditorController controller;
  final bool includeActions;

  @override
  Widget build(BuildContext context) {
    final enabled =
        controller.sourceImageData != null &&
        !controller.loading &&
        !controller.processingCutout;
    final settings = controller.cutoutSettings;
    final edgeExpansion = settings.edgeExpansion;
    final edgeExpansionLabel = edgeExpansion == 0
        ? '0'
        : edgeExpansion > 0
        ? '+$edgeExpansion'
        : '$edgeExpansion';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (includeActions) ...[
          EmoticonCutoutEngineActions(controller: controller),
          const SizedBox(height: 4),
        ],
        EmoticonSliderRow(
          label: 'Sensitivity',
          value: settings.backgroundTolerance.toDouble(),
          min: 20,
          max: 96,
          divisions: 19,
          valueText: '${settings.backgroundTolerance}',
          enabled: enabled,
          onChanged: (value) => controller.updateCutoutSettings(
            settings.copyWith(backgroundTolerance: value.round()),
          ),
          onChangeEnd: (_) => controller.rerunAutoCutoutAfterMaskChange(),
        ),
        EmoticonSliderRow(
          label: 'Softness',
          value: settings.edgeSoftness.toDouble(),
          min: 0,
          max: 4,
          divisions: 4,
          valueText: '${settings.edgeSoftness}',
          enabled: enabled,
          onChanged: (value) => controller.updateCutoutSettings(
            settings.copyWith(edgeSoftness: value.round()),
          ),
          onChangeEnd: (_) => controller.rerunAutoCutoutAfterMaskChange(),
        ),
        EmoticonSliderRow(
          label: 'Edge offset',
          value: edgeExpansion.toDouble(),
          min: -4,
          max: 4,
          divisions: 8,
          valueText: edgeExpansionLabel,
          enabled: enabled,
          onChanged: (value) => controller.updateCutoutSettings(
            settings.copyWith(edgeExpansion: value.round()),
          ),
          onChangeEnd: (_) => controller.rerunAutoCutoutAfterMaskChange(),
        ),
      ],
    );
  }
}

/// Auto-run and reset actions for the cutout engine.
class EmoticonCutoutEngineActions extends StatelessWidget {
  const EmoticonCutoutEngineActions({required this.controller, super.key});

  final EmoticonEditorController controller;

  @override
  Widget build(BuildContext context) {
    final busy =
        controller.sourceImageData == null ||
        controller.loading ||
        controller.processingCutout;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.tonalIcon(
          key: const ValueKey('emoticon-auto-cutout'),
          onPressed: busy ? null : controller.runAutoCutout,
          icon: controller.processingCutout
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.auto_fix_high_rounded, size: 18),
          label: Text(
            controller.processingCutout
                ? 'Processing...'
                : EmoticonCreatorStrings.promptEmoticonCreatorAutoCutout,
          ),
        ),
        OutlinedButton.icon(
          key: const ValueKey('emoticon-reset-cutout'),
          onPressed: busy ? null : controller.resetCutout,
          icon: const Icon(Icons.restart_alt_rounded, size: 18),
          label: Text(EmoticonCreatorStrings.promptEmoticonCreatorResetCutout),
        ),
      ],
    );
  }
}

/// Erase/Restore chips + brush size and opacity sliders. [compact] renders
/// the thin-strip variant used while the mobile Brush tray is active.
class EmoticonBrushControls extends StatelessWidget {
  const EmoticonBrushControls({
    required this.controller,
    this.compact = false,
    super.key,
  });

  final EmoticonEditorController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final enabled = controller.canEditMask;

    final chips = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilterChip(
          label: Text(EmoticonCreatorStrings.promptEmoticonCreatorEraseBrush),
          selected: controller.brushMode == CutoutBrushMode.erase,
          onSelected: enabled
              ? (_) => controller.setBrushMode(CutoutBrushMode.erase)
              : null,
          avatar: const Icon(Icons.cleaning_services_outlined, size: 18),
          visualDensity: compact ? VisualDensity.compact : null,
        ),
        FilterChip(
          label: Text(EmoticonCreatorStrings.promptEmoticonCreatorRestoreBrush),
          selected: controller.brushMode == CutoutBrushMode.restore,
          onSelected: enabled
              ? (_) => controller.setBrushMode(CutoutBrushMode.restore)
              : null,
          avatar: const Icon(Icons.brush_outlined, size: 18),
          visualDensity: compact ? VisualDensity.compact : null,
        ),
      ],
    );

    // The old floor of 0.02 is 2% of the source's shorter side — 20px on a
    // 1000px photo, far too coarse for edge work once the canvas can zoom.
    // 0.005 in 0.005 steps gives four usable sizes below the old minimum
    // while keeping the same top end.
    final sizeSlider = EmoticonSliderRow(
      label: 'Brush size',
      value: controller.brushRadius,
      min: EmoticonEditorController.minBrushRadius,
      max: EmoticonEditorController.maxBrushRadius,
      divisions: 23,
      valueText: (controller.brushRadius * 1000).round().toString(),
      enabled: enabled,
      dense: compact,
      onChanged: controller.setBrushRadius,
    );
    final opacitySlider = EmoticonSliderRow(
      label: 'Brush opacity',
      value: controller.brushStrength,
      min: 0.1,
      max: 1.0,
      divisions: 9,
      valueText: '${(controller.brushStrength * 100).round()}%',
      enabled: enabled,
      dense: compact,
      onChanged: controller.setBrushStrength,
    );

    if (compact) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [chips, sizeSlider, opacitySlider],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [chips, const SizedBox(height: 4), sizeSlider, opacitySlider],
    );
  }
}

/// Undo/redo for mask edits, shared by both Editor surfaces.
///
/// Lives in the editor chrome rather than in a tool tray: the mobile Brush tray
/// is a thin strip by R5, and the desktop accordion is lazily laid out, so
/// growing either one to hold these moves unrelated content out of view.
class EmoticonMaskHistoryControls extends StatelessWidget {
  const EmoticonMaskHistoryControls({required this.controller, super.key});

  final EmoticonEditorController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        tiamat.IconButton(
          key: const ValueKey('emoticon-mask-undo'),
          icon: Icons.undo_rounded,
          size: 20,
          tooltip: 'Undo mask edit',
          semanticLabel: 'Undo mask edit',
          onPressed: controller.canUndoBrush
              ? () => unawaited(controller.undoBrush())
              : null,
        ),
        tiamat.IconButton(
          key: const ValueKey('emoticon-mask-redo'),
          icon: Icons.redo_rounded,
          size: 20,
          tooltip: 'Redo mask edit',
          semanticLabel: 'Redo mask edit',
          onPressed: controller.canRedoBrush
              ? () => unawaited(controller.redoBrush())
              : null,
        ),
      ],
    );
  }
}

/// A round canvas-overlay control, used for fit-to-view.
class EmoticonCanvasOverlayButton extends StatelessWidget {
  const EmoticonCanvasOverlayButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;

    return tiamat.Tooltip(
      text: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: Material(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: enabled ? 0.86 : 0.5,
          ),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(
                icon,
                size: 20,
                color: enabled
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.38,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EmoticonOutputControls extends StatelessWidget {
  const EmoticonOutputControls({required this.controller, super.key});

  final EmoticonEditorController controller;

  @override
  Widget build(BuildContext context) {
    final canUpdateOutput = controller.canEditMask;
    final settings = controller.cutoutSettings;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'Crop framing',
          value: settings.squareCanvas ? 'Square crop' : 'Tight crop',
          enabled: canUpdateOutput,
          child: EmoticonChoiceRow(
            label: 'Crop',
            children: [
              FilterChip(
                label: const Text('Square crop'),
                avatar: const Icon(Icons.crop_square_rounded, size: 18),
                selected: settings.squareCanvas,
                onSelected: canUpdateOutput
                    ? (_) => controller.setSquareCanvas(true)
                    : null,
              ),
              FilterChip(
                label: const Text('Tight crop'),
                avatar: const Icon(Icons.crop_free_rounded, size: 18),
                selected: !settings.squareCanvas,
                onSelected: canUpdateOutput
                    ? (_) => controller.setSquareCanvas(false)
                    : null,
              ),
            ],
          ),
        ),
        EmoticonSliderRow(
          label: 'Padding',
          value: settings.paddingFraction,
          min: 0,
          max: 0.32,
          divisions: 16,
          enabled: canUpdateOutput,
          onChanged: (value) => controller.updateCutoutSettings(
            settings.copyWith(paddingFraction: value),
          ),
          onChangeEnd: (_) => controller.rerenderCutout(),
        ),
        EmoticonSliderRow(
          label: 'Outline',
          value: settings.outlineWidth.toDouble(),
          min: 0,
          max: 10,
          divisions: 10,
          enabled: canUpdateOutput,
          onChanged: (value) => controller.updateCutoutSettings(
            settings.copyWith(outlineWidth: value.round()),
          ),
          onChangeEnd: (_) => controller.rerenderCutout(),
        ),
        SwitchListTile.adaptive(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Shadow'),
          value: settings.shadow,
          onChanged: !canUpdateOutput
              ? null
              : (value) {
                  controller.updateCutoutSettings(
                    settings.copyWith(shadow: value),
                  );
                  controller.rerenderCutout();
                },
        ),
      ],
    );
  }
}

class EmoticonStatusText extends StatelessWidget {
  const EmoticonStatusText({
    required this.text,
    required this.isError,
    super.key,
  });

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: isError
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class EmoticonStatusMessages extends StatelessWidget {
  const EmoticonStatusMessages({required this.controller, super.key});

  final EmoticonEditorController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // One line of space is reserved whether or not there is anything to say,
    // so a status flip mid-stroke cannot reflow the desktop action bar (FR8).
    final lineHeight =
        (theme.textTheme.bodySmall?.fontSize ?? 12) *
        (theme.textTheme.bodySmall?.height ?? 1.4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        _reservedLine(
          lineHeight,
          controller.errorText == null
              ? null
              : EmoticonStatusText(text: controller.errorText!, isError: true),
        ),
        const SizedBox(height: 10),
        _reservedLine(
          lineHeight,
          controller.statusText == null
              ? null
              : EmoticonStatusText(
                  text: controller.statusText!,
                  isError: false,
                ),
        ),
      ],
    );
  }

  /// Reserves one line as a *minimum* rather than a fixed height: a null →
  /// short-message flip no longer moves anything, while a long message that
  /// genuinely needs two lines is still shown in full rather than clipped.
  Widget _reservedLine(double lineHeight, Widget? child) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: lineHeight),
      child: Align(
        alignment: Alignment.centerLeft,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}

class EmoticonPreviewMetadata extends StatelessWidget {
  const EmoticonPreviewMetadata({required this.controller, super.key});

  final EmoticonEditorController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = controller.cutoutResult;
    final draft = controller.savedDraft;
    final pngBytes = controller.imageData;
    final diagnostic = controller.lastCutoutDiagnostic;
    final lines = result != null
        ? [
            '${result.width} x ${result.height} PNG',
            formatEmoticonByteSize(result.pngBytes.length),
            'Backend: ${result.backend.name}',
            'Metadata stripped on export',
          ]
        : draft != null
        ? [
            '${draft.width} x ${draft.height} PNG',
            formatEmoticonByteSize(draft.fileSize),
            'Draft: ${draft.shortcode}',
            'Backend: ${draft.backend.name}',
            'Saved locally ${DateFormat.yMMMd().add_jm().format(draft.createdAt.toLocal())}',
            'Metadata stripped on export',
          ]
        : pngBytes != null
        ? [
            'Loaded transparent PNG',
            formatEmoticonByteSize(pngBytes.length),
            'Photos stay local until you save.',
          ]
        : const ['No cutout yet.', 'Photos stay local until you save.'];
    final diagnosticLines = diagnostic == null
        ? const <String>[]
        : _cutoutDiagnosticLines(diagnostic);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Output',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                line,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (diagnosticLines.isNotEmpty) ...[
            const SizedBox(height: 8),
            Divider(
              height: 1,
              color: theme.colorScheme.outline.withValues(alpha: 0.24),
            ),
            const SizedBox(height: 8),
            Semantics(
              label: 'Cutout diagnostics',
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Cutout details',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final line in diagnosticLines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        line,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static List<String> _cutoutDiagnosticLines(
    ImageCutoutDiagnosticEvent diagnostic,
  ) {
    return [
      'Operation: ${diagnostic.operation.name}',
      'Host: ${diagnostic.hostPlatform.name}',
      'Preferred: ${diagnostic.preferredBackend.name}',
      'Selected: ${diagnostic.selectedBackend.name}',
      'Runtime backend: ${diagnostic.backend.name}',
      'Fallback: ${diagnostic.usesFallback ? 'yes' : 'no'}',
      if (diagnostic.requiresNativeBridge) 'Native bridge required',
      if (diagnostic.requiresModelArtifact) 'Model artifact required',
      'Result: ${diagnostic.success ? 'success' : diagnostic.failureCode?.name ?? 'failed'}',
      'Duration: ${formatEmoticonDuration(diagnostic.duration)}',
      if (diagnostic.sourceWidth != null && diagnostic.sourceHeight != null)
        'Source: ${diagnostic.sourceWidth} x ${diagnostic.sourceHeight}',
      if (diagnostic.outputWidth != null && diagnostic.outputHeight != null)
        'Output: ${diagnostic.outputWidth} x ${diagnostic.outputHeight}',
      if (diagnostic.maskWidth != null && diagnostic.maskHeight != null)
        'Mask: ${diagnostic.maskWidth} x ${diagnostic.maskHeight}',
      if (diagnostic.outputPngByteCount != null)
        'PNG: ${formatEmoticonByteSize(diagnostic.outputPngByteCount!)}',
      if (diagnostic.thumbnailByteCount != null)
        'Thumbnail: ${formatEmoticonByteSize(diagnostic.thumbnailByteCount!)}',
    ];
  }
}

/// The searchable local drafts panel. Deletion confirmations are provided by
/// the host surface via [confirmDeleteDraft]/[confirmDeleteDrafts] so this
/// widget stays dialog-free.
class EmoticonDraftsPanel extends StatelessWidget {
  const EmoticonDraftsPanel({
    required this.controller,
    required this.confirmDeleteDraft,
    required this.confirmDeleteDrafts,
    super.key,
  });

  final EmoticonEditorController controller;
  final Future<bool> Function(EmoticonDraft draft) confirmDeleteDraft;
  final Future<bool> Function(List<EmoticonDraft> drafts) confirmDeleteDrafts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filteredDrafts = controller.filteredDrafts();
    final visibleDrafts = filteredDrafts
        .take(emoticonDraftPanelDisplayLimit)
        .toList(growable: false);
    final hiddenMatchCount = math.max(
      0,
      filteredDrafts.length - visibleDrafts.length,
    );
    final hasSearch = controller.draftSearchQuery.trim().isNotEmpty;

    if (!controller.draftsLoading &&
        controller.drafts.isEmpty &&
        controller.draftErrorText == null) {
      return const SizedBox.shrink();
    }

    return Semantics(
      label: 'Local emoticon drafts',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.28),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.history_rounded, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Recent drafts',
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  if (controller.draftsLoading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      tooltip: 'Refresh drafts',
                      onPressed: controller.loading
                          ? null
                          : controller.loadDrafts,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                    ),
                ],
              ),
              if (controller.drafts.isNotEmpty) ...[
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('emoticon-draft-search'),
                  controller: controller.draftSearchController,
                  enabled: !controller.loading && !controller.draftsLoading,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    suffixIcon: hasSearch
                        ? IconButton(
                            tooltip: 'Clear draft search',
                            onPressed: controller.loading
                                ? null
                                : controller.clearDraftSearch,
                            icon: const Icon(Icons.close_rounded, size: 18),
                          )
                        : null,
                    labelText: 'Search local drafts',
                    hintText: 'Shortcode, size, or backend',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: controller.setDraftSearchQuery,
                ),
              ],
              if (controller.draftErrorText != null) ...[
                const SizedBox(height: 6),
                EmoticonStatusText(
                  text: controller.draftErrorText!,
                  isError: true,
                ),
              ],
              if (controller.drafts.isNotEmpty &&
                  filteredDrafts.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const ValueKey('emoticon-draft-bulk-delete'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    onPressed: controller.loading || controller.draftsLoading
                        ? null
                        : () async {
                            if (await confirmDeleteDrafts(filteredDrafts)) {
                              await controller.deleteDrafts(filteredDrafts);
                            }
                          },
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: Text(hasSearch ? 'Delete matching' : 'Delete all'),
                  ),
                ),
              ],
              if (visibleDrafts.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...visibleDrafts.map(
                  (draft) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: EmoticonDraftTile(
                      draft: draft,
                      thumbnailBytes: controller.draftThumbnails[draft.id],
                      selected: controller.savedDraft?.id == draft.id,
                      onLoad: controller.loading
                          ? null
                          : () => controller.loadDraft(draft),
                      onDelete: controller.loading
                          ? null
                          : () async {
                              if (await confirmDeleteDraft(draft)) {
                                await controller.deleteDraft(draft);
                              }
                            },
                    ),
                  ),
                ),
                if (hiddenMatchCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      hasSearch
                          ? '$hiddenMatchCount more local drafts match this search.'
                          : '$hiddenMatchCount more local drafts saved. Search to narrow them down.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ] else if (!controller.draftsLoading && hasSearch) ...[
                const SizedBox(height: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No local drafts found.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: controller.loading
                              ? null
                              : controller.clearDraftSearch,
                          child: const Text('Clear search'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class EmoticonDraftTile extends StatelessWidget {
  const EmoticonDraftTile({
    required this.draft,
    required this.thumbnailBytes,
    required this.selected,
    required this.onLoad,
    required this.onDelete,
    super.key,
  });

  final EmoticonDraft draft;
  final Uint8List? thumbnailBytes;
  final bool selected;
  final VoidCallback? onLoad;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = [
      '${draft.width} x ${draft.height}',
      formatEmoticonByteSize(draft.fileSize),
      draft.backend.name,
    ].join(' | ');
    final created = DateFormat.MMMd().add_jm().format(
      draft.createdAt.toLocal(),
    );

    return Semantics(
      selected: selected,
      label: 'Local draft ${draft.shortcode}, $subtitle',
      child: Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.surfaceContainerHigh
                : theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline.withValues(alpha: 0.28),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                _DraftThumbnail(bytes: thumbnailBytes),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              draft.shortcode,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge,
                            ),
                          ),
                          if (selected) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.check_circle_rounded,
                              size: 14,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'Loaded',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        created,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: onLoad, child: const Text('Load')),
                tiamat.Tooltip(
                  text: 'Delete local draft',
                  child: IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DraftThumbnail extends StatelessWidget {
  const _DraftThumbnail({required this.bytes});

  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CustomPaint(
        painter: EmoticonCheckerboardPainter(
          light: theme.colorScheme.surfaceContainerHigh,
          dark: theme.colorScheme.surfaceContainerLow,
        ),
        child: SizedBox(
          width: 44,
          height: 44,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.32),
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: bytes == null
                ? Icon(
                    Icons.image_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                : Image.memory(
                    bytes!,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
          ),
        ),
      ),
    );
  }
}

class EmoticonChoiceRow extends StatelessWidget {
  const EmoticonChoiceRow({
    required this.label,
    required this.children,
    super.key,
  });

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelWidget = SizedBox(width: 92, child: Text(label));
        final choices = Wrap(spacing: 8, runSpacing: 8, children: children);

        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(label), const SizedBox(height: 8), choices],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            labelWidget,
            Expanded(child: choices),
          ],
        );
      },
    );
  }
}

class EmoticonSliderRow extends StatelessWidget {
  const EmoticonSliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
    this.divisions,
    this.valueText,
    this.onChangeEnd,
    this.dense = false,
    super.key,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? valueText;
  final bool enabled;
  final bool dense;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final semanticValue = valueText ?? value.toStringAsFixed(2);
    final theme = Theme.of(context);
    final labelWidget = Text(label);
    final slider = Slider(
      value: value.clamp(min, max),
      min: min,
      max: max,
      divisions: divisions,
      semanticFormatterCallback: (_) => '$label $semanticValue',
      onChanged: enabled ? onChanged : null,
      onChangeEnd: enabled ? onChangeEnd : null,
    );
    final valueWidget = valueText == null
        ? null
        : Text(
            valueText!,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (!dense && constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: labelWidget),
                  if (valueWidget != null)
                    SizedBox(width: 44, child: valueWidget),
                ],
              ),
              slider,
            ],
          );
        }

        return Row(
          children: [
            SizedBox(width: dense ? 84 : 92, child: labelWidget),
            Expanded(child: slider),
            if (valueWidget != null) SizedBox(width: 40, child: valueWidget),
          ],
        );
      },
    );
  }
}

class EmoticonImagePickTile extends StatelessWidget {
  const EmoticonImagePickTile({
    required this.image,
    required this.tooltip,
    required this.onTap,
    super.key,
  });

  final ImageProvider? image;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return tiamat.Tooltip(
      text: tooltip,
      child: Material(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: image == null
              ? Icon(
                  Icons.add_a_photo,
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : Image(
                  image: image!,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                  // The Quick-card thumbnail tracks the live cutout, so it
                  // strobes with the same missing flag as the canvas (FR1).
                  gaplessPlayback: true,
                ),
        ),
      ),
    );
  }
}
