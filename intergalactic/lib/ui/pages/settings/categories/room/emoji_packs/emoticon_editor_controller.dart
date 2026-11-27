import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_creator_validation.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_draft_store_models.dart';
import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/client/components/emoticon/image_cutout_service.dart';

/// Backdrop used to inspect transparent cutout edges in the preview.
enum CutoutPreviewBackground { checkerboard, dark, light }

/// The tool groups shared by the mobile tray editor and the desktop panel.
enum EmoticonToolGroup { cutout, brush, crop, output, preview, drafts }

typedef EmoticonSaveCallback =
    Future<bool> Function(String name, EmoticonUsage usage, Uint8List? data);
typedef EmoticonSaveToPhotosCallback =
    Future<bool> Function(String filename, Uint8List data);

const int emoticonDraftPanelDisplayLimit = 12;
const int emoticonDraftThumbnailReadLimit = 16;

bool hasManualCutoutMask(CutoutMask? workingMask, CutoutMask? autoMask) {
  if (workingMask == null || autoMask == null) {
    return false;
  }
  if (workingMask.width != autoMask.width ||
      workingMask.height != autoMask.height ||
      workingMask.alpha.length != autoMask.alpha.length) {
    return true;
  }
  for (var index = 0; index < workingMask.alpha.length; index++) {
    if (workingMask.alpha[index] != autoMask.alpha[index]) {
      return true;
    }
  }
  return false;
}

/// Output geometry latched for the whole duration of one brush stroke.
///
/// The engine recomputes the subject bounds — and therefore [cropBounds],
/// [width] and [height] — on every render, so letting a mid-stroke render
/// replace them makes the preview rescale under the finger *and* makes the
/// same screen point resolve to a different source pixel. Latching at stroke
/// start keeps both the layout and the brush mapping fixed until the user
/// lifts (FR2).
class EmoticonStrokeGeometry {
  const EmoticonStrokeGeometry({
    required this.cropBounds,
    required this.width,
    required this.height,
    required this.sourceWidth,
    required this.sourceHeight,
  });

  EmoticonStrokeGeometry.fromResult(CutoutResult result)
    : cropBounds = result.cropBounds,
      width = result.width,
      height = result.height,
      sourceWidth = result.sourceWidth,
      sourceHeight = result.sourceHeight;

  final CutoutIntRect cropBounds;
  final int width;
  final int height;
  final int sourceWidth;
  final int sourceHeight;
}

/// One dab recorded for the in-stroke overlay.
///
/// The position is normalised against the image rect rather than stored in
/// canvas pixels, so the overlay stays registered with the image if the canvas
/// is zoomed, panned, or relaid out (tray raise/collapse) mid-stroke.
class EmoticonStrokeDab {
  const EmoticonStrokeDab({
    required this.normalizedX,
    required this.normalizedY,
    required this.radiusFraction,
    required this.strength,
  });

  final double normalizedX;
  final double normalizedY;
  final double radiusFraction;
  final double strength;
}

/// Snapshot of the shape-affecting editor state, used to discard an Editor
/// sub-mode session (Back) without touching the Quick surface's image.
class _EditorStateSnapshot {
  _EditorStateSnapshot(EmoticonEditorController controller)
    : sourceImageData = controller.sourceImageData,
      sourceImageName = controller.sourceImageName,
      imageData = controller.imageData,
      cutoutResult = controller.cutoutResult,
      autoCutoutMask = controller.autoCutoutMask,
      workingMask = controller.workingMask,
      cutoutSettings = controller.cutoutSettings,
      previewBackground = controller.previewBackground,
      brushMode = controller.brushMode,
      brushRadius = controller.brushRadius,
      brushStrength = controller.brushStrength,
      image = controller.image,
      savedDraft = controller.savedDraft,
      statusText = controller.statusText,
      errorText = controller.errorText;

  final Uint8List? sourceImageData;
  final String? sourceImageName;
  final Uint8List? imageData;
  final CutoutResult? cutoutResult;
  final CutoutMask? autoCutoutMask;
  final CutoutMask? workingMask;
  final CutoutSettings cutoutSettings;
  final CutoutPreviewBackground previewBackground;
  final CutoutBrushMode brushMode;
  final double brushRadius;
  final double brushStrength;
  final ImageProvider? image;
  final EmoticonDraft? savedDraft;
  final String? statusText;
  final String? errorText;
}

/// Shared state controller for the emoticon (cutout) creator.
///
/// Holds the source image, cutout settings/masks, brush state, output
/// options, drafts, and validation state, and owns the single call path into
/// [ImageCutoutService]. The mobile Quick card + tray Editor and the desktop
/// Quick panel + two-pane Editor are presentation layers over this
/// controller; neither forks engine calls. Pickers, dialogs, and navigation
/// stay in the widget layer.
class EmoticonEditorController extends ChangeNotifier {
  EmoticonEditorController({
    required ImageCutoutService cutoutService,
    required this.draftStore,
    this.pack,
    this.initialEmoticon,
    this.creatingNew = false,
    this.onCreate,
    this.onDelete,
    this.onSaveToPhotos,
  }) {
    this.cutoutService = cutoutService.withAdditionalDiagnostics(
      _handleCutoutDiagnostics,
    );
    usage = initialEmoticon?.usage ?? EmoticonUsage.inherit;
    shortcodeController.text = initialEmoticon?.shortcode ?? '';
    image = initialEmoticon?.image;
  }

  late final ImageCutoutService cutoutService;
  final EmoticonDraftStore draftStore;
  final EmoticonPack? pack;
  final Emoticon? initialEmoticon;
  final bool creatingNew;
  final EmoticonSaveCallback? onCreate;
  final Future<void> Function()? onDelete;
  final EmoticonSaveToPhotosCallback? onSaveToPhotos;

  final TextEditingController shortcodeController = TextEditingController();
  final TextEditingController draftSearchController = TextEditingController();

  EmoticonUsage usage = EmoticonUsage.inherit;
  ImageProvider? image;
  Uint8List? sourceImageData;
  String? sourceImageName;
  Uint8List? imageData;
  CutoutResult? cutoutResult;
  CutoutMask? autoCutoutMask;
  CutoutMask? workingMask;
  EmoticonDraft? savedDraft;
  List<EmoticonDraft> drafts = const [];
  Map<String, Uint8List> draftThumbnails = const {};
  CutoutSettings cutoutSettings = const CutoutSettings();
  ImageCutoutDiagnosticEvent? lastCutoutDiagnostic;
  CutoutPreviewBackground previewBackground =
      CutoutPreviewBackground.checkerboard;
  CutoutBrushMode brushMode = CutoutBrushMode.erase;
  double brushRadius = 0.05;
  double brushStrength = 1.0;
  bool loading = false;
  bool processingCutout = false;
  bool savingToPhotos = false;
  bool draftsLoading = false;
  String? errorText;
  String? statusText;
  String? draftErrorText;
  String draftSearchQuery = '';
  bool brushRendering = false;
  bool brushRenderQueued = false;

  /// True between [beginBrushStroke] and [endBrushStroke] — i.e. while a
  /// pointer is down and painting.
  bool strokeActive = false;

  /// Latched output geometry for the stroke currently being painted or
  /// settled. Non-null means the canvas must lay out from these numbers and
  /// paint the stroke overlay; it is cleared in the same notification that
  /// adopts the settled render, so no frame ever shows both.
  EmoticonStrokeGeometry? strokeGeometry;

  /// Dabs accumulated during the current stroke, drawn as the live overlay.
  List<EmoticonStrokeDab> strokeDabs = const [];

  /// The brush mode latched at stroke start. One stroke paints one mode.
  CutoutBrushMode strokeBrushMode = CutoutBrushMode.erase;

  /// Canvas magnification (U7). 1.0 is fit-to-view; [zoomOffset] translates the
  /// magnified rect and is forced to zero at rest.
  double zoomScale = minZoomScale;
  Offset zoomOffset = Offset.zero;

  /// The canvas viewport, published by the canvas during layout so zoom
  /// clamping and the stroke-settle re-anchor (FR12) can be computed on the
  /// controller instead of being threaded through gesture callbacks.
  Size viewportSize = Size.zero;

  static const double minZoomScale = 1.0;
  static const double maxZoomScale = 8.0;

  /// Brush radius as a fraction of the source's shorter side. The floor is
  /// deliberately small — QA found 0.02 (20px on a 1000px photo) too coarse for
  /// edge work now that the canvas zooms.
  static const double minBrushRadius = 0.005;
  static const double maxBrushRadius = 0.12;

  /// The tray/accordion group currently raised. `null` means every tray is
  /// closed and the canvas is fully maximal (KTD-3).
  EmoticonToolGroup? activeToolGroup;

  _EditorStateSnapshot? _editSessionSnapshot;
  int _cutoutGeneration = 0;
  bool _disposed = false;
  bool _strokeMaskDirty = false;
  Offset? _pendingZoomAnchor;

  /// Mask history for undo/redo. Entries are whole masks, which is why the
  /// stack is bounded by bytes as well as depth: a mask is one byte per source
  /// pixel, so on a large photo a handful of entries is already tens of MB.
  /// Exceeding either bound drops the oldest entries, so undo depth degrades on
  /// huge sources rather than the editor running out of memory.
  final List<CutoutMask> _maskUndoStack = [];
  final List<CutoutMask> _maskRedoStack = [];
  int _maskHistoryBytes = 0;
  CutoutMask? _preStrokeMask;

  static const int _maskHistoryDepthCap = 32;
  static const int _maskHistoryByteBudget = 64 * 1024 * 1024;

  @override
  void dispose() {
    _disposed = true;
    _cutoutGeneration++;
    brushRenderQueued = false;
    _resetStrokeState();
    _clearMaskHistory();
    shortcodeController.dispose();
    draftSearchController.dispose();
    super.dispose();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  bool get canEditMask => cutoutResult != null && !loading && !processingCutout;

  bool get canSave {
    final validation = validateShortcode();
    return !loading &&
        !processingCutout &&
        !brushRendering &&
        !strokeActive &&
        validation.isValid &&
        // An unedited source photo is enough to save; a cutout is optional.
        (imageData != null || sourceImageData != null || !creatingNew);
  }

  bool get canSaveToPhotos =>
      onSaveToPhotos != null &&
      cutoutResult != null &&
      !loading &&
      !processingCutout &&
      !brushRendering &&
      !strokeActive &&
      !savingToPhotos;

  void _handleCutoutDiagnostics(ImageCutoutDiagnosticEvent event) {
    lastCutoutDiagnostic = event;
    _notify();
  }

  // ---------------------------------------------------------------------
  // Editor sub-mode session (Quick surface <-> Editor)
  // ---------------------------------------------------------------------

  /// Snapshots the shape-affecting state when the Editor sub-mode opens.
  void beginEditSession() {
    _editSessionSnapshot = _EditorStateSnapshot(this);
    activeToolGroup = null;
    _notify();
  }

  /// Keeps the Editor's shaped image (Done).
  void commitEditSession() {
    _editSessionSnapshot = null;
    activeToolGroup = null;
    _notify();
  }

  /// Restores the pre-Editor state (Back), leaving the Quick surface's image
  /// unchanged.
  void discardEditSession() {
    final snapshot = _editSessionSnapshot;
    _editSessionSnapshot = null;
    activeToolGroup = null;
    _cutoutGeneration++;
    loading = false;
    processingCutout = false;
    brushRendering = false;
    brushRenderQueued = false;
    _resetStrokeState();
    _resetZoomState();
    _clearMaskHistory();
    if (snapshot == null) {
      _notify();
      return;
    }
    sourceImageData = snapshot.sourceImageData;
    sourceImageName = snapshot.sourceImageName;
    imageData = snapshot.imageData;
    cutoutResult = snapshot.cutoutResult;
    autoCutoutMask = snapshot.autoCutoutMask;
    workingMask = snapshot.workingMask;
    cutoutSettings = snapshot.cutoutSettings;
    previewBackground = snapshot.previewBackground;
    brushMode = snapshot.brushMode;
    brushRadius = snapshot.brushRadius;
    brushStrength = snapshot.brushStrength;
    image = snapshot.image;
    savedDraft = snapshot.savedDraft;
    statusText = snapshot.statusText;
    errorText = snapshot.errorText;
    _notify();
  }

  void setActiveToolGroup(EmoticonToolGroup? group) {
    if (activeToolGroup == group) {
      return;
    }
    activeToolGroup = group;
    _notify();
  }

  /// Tap-tab semantics: tapping the active tab closes its tray (KTD-3).
  void toggleToolGroup(EmoticonToolGroup group) {
    activeToolGroup = activeToolGroup == group ? null : group;
    _notify();
  }

  // ---------------------------------------------------------------------
  // Simple state mutators
  // ---------------------------------------------------------------------

  void setUsage(EmoticonUsage value) {
    if (usage == value) {
      return;
    }
    usage = value;
    _notify();
  }

  void setPreviewBackground(CutoutPreviewBackground value) {
    if (previewBackground == value) {
      return;
    }
    previewBackground = value;
    _notify();
  }

  void setBrushMode(CutoutBrushMode value) {
    if (brushMode == value) {
      return;
    }
    brushMode = value;
    _notify();
  }

  void setBrushRadius(double value) {
    if (brushRadius == value) {
      return;
    }
    brushRadius = value;
    _notify();
  }

  void setBrushStrength(double value) {
    if (brushStrength == value) {
      return;
    }
    brushStrength = value;
    _notify();
  }

  void updateCutoutSettings(CutoutSettings value) {
    cutoutSettings = value;
    _notify();
  }

  void setSquareCanvas(bool squareCanvas) {
    if (cutoutSettings.squareCanvas == squareCanvas) {
      return;
    }
    cutoutSettings = cutoutSettings.copyWith(squareCanvas: squareCanvas);
    _notify();
    unawaited(rerenderCutout());
  }

  /// Called on every shortcode keystroke so listeners re-run validation.
  void notifyShortcodeChanged() => _notify();

  // ---------------------------------------------------------------------
  // Source image
  // ---------------------------------------------------------------------

  void setSourceImage(
    Uint8List bytes, {
    String? name,
    bool seedShortcode = false,
  }) {
    _cutoutGeneration++;
    loading = false;
    processingCutout = false;
    brushRendering = false;
    brushRenderQueued = false;
    _resetStrokeState();
    _resetZoomState();
    _clearMaskHistory();
    sourceImageData = bytes;
    sourceImageName = name;
    cutoutResult = null;
    autoCutoutMask = null;
    workingMask = null;
    lastCutoutDiagnostic = null;
    imageData = null;
    savedDraft = null;
    image = Image.memory(bytes).image;
    errorText = null;
    statusText = null;
    if (seedShortcode) {
      final shortcode = shortcodeSeedFromImageName(name);
      if (shortcode.isNotEmpty) {
        shortcodeController.text = shortcode;
      }
    }
    _notify();
  }

  void reportSourceImageError(String message) {
    errorText = message;
    statusText = null;
    _notify();
  }

  static String shortcodeSeedFromImageName(String? name) {
    final rawName = name?.trim();
    if (rawName == null || rawName.isEmpty) {
      return '';
    }

    final slashIndex = math.max(
      rawName.lastIndexOf('/'),
      rawName.lastIndexOf(r'\'),
    );
    final filename = slashIndex == -1
        ? rawName
        : rawName.substring(slashIndex + 1);
    final dotIndex = filename.lastIndexOf('.');
    final base = (dotIndex > 0 ? filename.substring(0, dotIndex) : filename)
        .toLowerCase();

    return base
        .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  // ---------------------------------------------------------------------
  // Cutout engine calls (single call path for both platforms)
  // ---------------------------------------------------------------------

  Future<void> runAutoCutout({bool preserveManualMask = false}) async {
    final source = sourceImageData;
    if (source == null) {
      return;
    }
    final generation = ++_cutoutGeneration;
    brushRenderQueued = false;
    _resetStrokeState();
    // A fresh auto mask is a new baseline, not a step on from the old one.
    _clearMaskHistory();
    final preservedWorkingMask =
        preserveManualMask && hasManualCutoutMask(workingMask, autoCutoutMask)
        ? workingMask
        : null;

    loading = true;
    processingCutout = true;
    errorText = null;
    lastCutoutDiagnostic = null;
    statusText = 'Preparing local background removal...';
    _notify();

    try {
      final result = await cutoutService.generate(
        imageBytes: source,
        settings: cutoutSettings,
      );
      final canPreserveWorkingMask =
          preservedWorkingMask != null &&
          preservedWorkingMask.width == result.mask.width &&
          preservedWorkingMask.height == result.mask.height;
      final displayResult = canPreserveWorkingMask
          ? await cutoutService.render(
              imageBytes: source,
              mask: preservedWorkingMask,
              settings: cutoutSettings,
            )
          : result;
      if (_disposed ||
          generation != _cutoutGeneration ||
          !identical(sourceImageData, source)) {
        return;
      }
      cutoutResult = displayResult;
      autoCutoutMask = result.mask;
      workingMask = canPreserveWorkingMask ? preservedWorkingMask : result.mask;
      imageData = displayResult.pngBytes;
      image = Image.memory(displayResult.pngBytes).image;
      statusText = 'Transparent PNG ready. Backend: ${result.backend.name}.';
    } on ImageCutoutException catch (exception) {
      if (!_disposed &&
          generation == _cutoutGeneration &&
          identical(sourceImageData, source)) {
        errorText = exception.message;
        statusText = null;
      }
    } catch (_) {
      if (!_disposed &&
          generation == _cutoutGeneration &&
          identical(sourceImageData, source)) {
        errorText = 'This photo could not be processed.';
        statusText = null;
      }
    } finally {
      if (!_disposed &&
          generation == _cutoutGeneration &&
          identical(sourceImageData, source)) {
        loading = false;
        processingCutout = false;
        _notify();
      }
    }
  }

  Future<void> rerunAutoCutoutAfterMaskChange() async {
    if (sourceImageData == null ||
        cutoutResult == null ||
        loading ||
        processingCutout) {
      return;
    }
    await runAutoCutout(preserveManualMask: true);
  }

  Future<void> rerenderCutout({
    CutoutMask? mask,
    String? successStatusText,
  }) async {
    final source = sourceImageData;
    final current = cutoutResult;
    final nextMask = mask ?? workingMask ?? current?.mask;
    if (source == null ||
        current == null ||
        nextMask == null ||
        processingCutout) {
      return;
    }

    final generation = ++_cutoutGeneration;
    brushRenderQueued = false;
    processingCutout = true;
    lastCutoutDiagnostic = null;
    statusText = 'Updating transparent PNG...';
    _notify();

    try {
      final result = await cutoutService.render(
        imageBytes: source,
        mask: nextMask,
        settings: cutoutSettings,
      );
      if (_disposed ||
          generation != _cutoutGeneration ||
          !identical(sourceImageData, source)) {
        return;
      }
      cutoutResult = result;
      workingMask = result.mask;
      imageData = result.pngBytes;
      image = Image.memory(result.pngBytes).image;
      statusText = successStatusText ?? 'Transparent PNG updated.';
    } catch (_) {
      if (!_disposed &&
          generation == _cutoutGeneration &&
          identical(sourceImageData, source)) {
        errorText = 'This edit could not be applied.';
        statusText = null;
      }
    } finally {
      if (!_disposed &&
          generation == _cutoutGeneration &&
          identical(sourceImageData, source)) {
        processingCutout = false;
        _notify();
      }
    }
  }

  // ---------------------------------------------------------------------
  // Brush stroke lifecycle (U2)
  // ---------------------------------------------------------------------

  /// Opens a stroke: latches the output geometry and starts a fresh overlay.
  /// No render runs here.
  ///
  /// If the previous stroke's render is still in flight, the accumulated dabs
  /// are kept rather than cleared — they are already in [workingMask] and that
  /// pending render will include them, so dropping the overlay would blank the
  /// user's marks for the duration of the render.
  void beginBrushStroke() {
    final result = cutoutResult;
    if (result == null || !canEditMask) {
      return;
    }

    strokeActive = true;
    strokeBrushMode = brushMode;
    strokeGeometry ??= EmoticonStrokeGeometry.fromResult(result);
    if (!brushRendering) {
      strokeDabs = const [];
    }
    // Captured now, committed to the undo stack only if the stroke actually
    // paints something — an aborted stroke must not add an empty history step.
    _preStrokeMask = workingMask ?? result.mask;
    _strokeMaskDirty = false;
    _notify();
  }

  /// Closes the stroke and runs exactly **one** production render for it.
  ///
  /// The overlay and the latched geometry survive until that render is adopted
  /// (see [_clearStrokeOverlayIfSettled]), so the settle never flashes back to
  /// the pre-stroke image.
  Future<void> endBrushStroke() async {
    if (!strokeActive) {
      return;
    }
    strokeActive = false;

    if (!_strokeMaskDirty) {
      // Nothing was painted (a tap in the letterbox, or a pinch that arrived
      // before the first dab). Drop the stroke without touching the engine.
      if (!brushRendering) {
        strokeGeometry = null;
        strokeDabs = const [];
      }
      _preStrokeMask = null;
      _notify();
      return;
    }

    // One stroke is one undo step, matching what the user perceives as one
    // action. Painting after an undo drops the redo branch, as in every other
    // editor.
    _pushUndoMask(_preStrokeMask);
    _clearRedoHistory();
    _preStrokeMask = null;

    _strokeMaskDirty = false;
    _pendingZoomAnchor = _sourcePointAtViewportCentre();
    if (brushRendering) {
      brushRenderQueued = true;
      _notify();
      return;
    }
    await _runBrushRender();
  }

  /// Applies one brush dab at a canvas position inside [imageRect].
  ///
  /// The source-space mapping is unchanged from the pre-controller
  /// implementation except that it reads the **latched** stroke geometry while
  /// a stroke is open, so `cropBounds` cannot move under the finger. Dabs no
  /// longer schedule a render; [endBrushStroke] does that once per stroke.
  void applyBrushAt(Offset position, Rect imageRect) {
    final result = cutoutResult;
    final source = sourceImageData;
    if (result == null ||
        source == null ||
        imageRect.isEmpty ||
        !imageRect.contains(position)) {
      return;
    }

    final geometry =
        strokeGeometry ?? EmoticonStrokeGeometry.fromResult(result);
    final x = ((position.dx - imageRect.left) / imageRect.width).clamp(
      0.0,
      1.0,
    );
    final y = ((position.dy - imageRect.top) / imageRect.height).clamp(
      0.0,
      1.0,
    );
    final crop = geometry.cropBounds;
    final sourceX = crop.left + (crop.width * x);
    final sourceY = crop.top + (crop.height * y);
    final normalizedSourceX = (sourceX / math.max(1, geometry.sourceWidth - 1))
        .clamp(0.0, 1.0);
    final normalizedSourceY = (sourceY / math.max(1, geometry.sourceHeight - 1))
        .clamp(0.0, 1.0);
    final nextMask = (workingMask ?? result.mask).applyBrush(
      normalizedX: normalizedSourceX,
      normalizedY: normalizedSourceY,
      radiusFraction: brushRadius,
      mode: brushMode,
      strength: brushStrength,
    );

    workingMask = nextMask;

    if (!strokeActive) {
      // No explicit stroke lifecycle (a programmatic caller). Preserve the
      // pre-U2 behaviour and settle immediately.
      _scheduleBrushRender();
      return;
    }

    strokeDabs = [
      ...strokeDabs,
      EmoticonStrokeDab(
        normalizedX: x,
        normalizedY: y,
        radiusFraction: brushRadius,
        strength: brushStrength,
      ),
    ];
    _strokeMaskDirty = true;
    _notify();
  }

  // ---------------------------------------------------------------------
  // Mask undo / redo
  // ---------------------------------------------------------------------

  /// Undo and redo cover user-initiated mask replacements: brush strokes and
  /// Reset. Auto cutout starts a new baseline and clears the history, because
  /// the mask it produces is not a step on from the previous one.
  bool get canUndoBrush =>
      _maskUndoStack.isNotEmpty &&
      canEditMask &&
      !strokeActive &&
      !brushRendering;

  bool get canRedoBrush =>
      _maskRedoStack.isNotEmpty &&
      canEditMask &&
      !strokeActive &&
      !brushRendering;

  int get undoDepth => _maskUndoStack.length;
  int get redoDepth => _maskRedoStack.length;

  void _pushUndoMask(CutoutMask? mask) {
    if (mask == null) {
      return;
    }
    _maskUndoStack.add(mask);
    _maskHistoryBytes += mask.alpha.length;
    _trimMaskHistory();
  }

  void _pushRedoMask(CutoutMask? mask) {
    if (mask == null) {
      return;
    }
    _maskRedoStack.add(mask);
    _maskHistoryBytes += mask.alpha.length;
    _trimMaskHistory();
  }

  void _trimMaskHistory() {
    // Drop the oldest undo entries first: the most recent steps are the ones a
    // user actually reaches for.
    while (_maskUndoStack.isNotEmpty &&
        (_maskUndoStack.length + _maskRedoStack.length > _maskHistoryDepthCap ||
            _maskHistoryBytes > _maskHistoryByteBudget)) {
      final dropped = _maskUndoStack.removeAt(0);
      _maskHistoryBytes -= dropped.alpha.length;
    }
    while (_maskRedoStack.isNotEmpty &&
        (_maskUndoStack.length + _maskRedoStack.length > _maskHistoryDepthCap ||
            _maskHistoryBytes > _maskHistoryByteBudget)) {
      final dropped = _maskRedoStack.removeAt(0);
      _maskHistoryBytes -= dropped.alpha.length;
    }
  }

  void _clearRedoHistory() {
    for (final mask in _maskRedoStack) {
      _maskHistoryBytes -= mask.alpha.length;
    }
    _maskRedoStack.clear();
  }

  void _clearMaskHistory() {
    _maskUndoStack.clear();
    _maskRedoStack.clear();
    _maskHistoryBytes = 0;
    _preStrokeMask = null;
  }

  Future<void> undoBrush() async {
    if (!canUndoBrush) {
      return;
    }
    final previous = _maskUndoStack.removeLast();
    _maskHistoryBytes -= previous.alpha.length;
    _pushRedoMask(workingMask ?? cutoutResult?.mask);
    workingMask = previous;
    _notify();
    await _runBrushRender();
  }

  Future<void> redoBrush() async {
    if (!canRedoBrush) {
      return;
    }
    final next = _maskRedoStack.removeLast();
    _maskHistoryBytes -= next.alpha.length;
    _pushUndoMask(workingMask ?? cutoutResult?.mask);
    workingMask = next;
    _notify();
    await _runBrushRender();
  }

  void _clearStrokeOverlayIfSettled() {
    if (strokeActive || brushRenderQueued) {
      return;
    }
    strokeGeometry = null;
    strokeDabs = const [];
    _strokeMaskDirty = false;
  }

  void _resetStrokeState() {
    strokeActive = false;
    strokeGeometry = null;
    strokeDabs = const [];
    _strokeMaskDirty = false;
    _pendingZoomAnchor = null;
  }

  // ---------------------------------------------------------------------
  // Canvas zoom and pan (U7)
  // ---------------------------------------------------------------------

  /// The output dimensions the canvas must lay out from: latched during a
  /// stroke, otherwise the current result.
  int get displayImageWidth =>
      strokeGeometry?.width ?? cutoutResult?.width ?? 0;

  int get displayImageHeight =>
      strokeGeometry?.height ?? cutoutResult?.height ?? 0;

  CutoutIntRect? get displayCropBounds =>
      strokeGeometry?.cropBounds ?? cutoutResult?.cropBounds;

  int get displaySourceWidth =>
      strokeGeometry?.sourceWidth ?? cutoutResult?.sourceWidth ?? 0;

  int get displaySourceHeight =>
      strokeGeometry?.sourceHeight ?? cutoutResult?.sourceHeight ?? 0;

  /// Published by the canvas each layout pass. Deliberately does not notify —
  /// it is read during build, and notifying from layout would loop.
  void setViewportSize(Size value) {
    viewportSize = value;
  }

  /// The unzoomed `BoxFit.contain` rect for the current display geometry.
  Rect fittedImageRect() {
    if (viewportSize.isEmpty) {
      return Rect.zero;
    }
    final width = displayImageWidth;
    final height = displayImageHeight;
    if (width <= 0 || height <= 0) {
      return Rect.fromLTWH(0, 0, viewportSize.width, viewportSize.height);
    }
    return containedImageRect(
      containerSize: viewportSize,
      imageWidth: width,
      imageHeight: height,
    );
  }

  /// The rect every canvas consumer works in: the image itself, the Restore
  /// ghost, the stroke overlay, the cursor ring, and [applyBrushAt]. Applying
  /// zoom here rather than to the widget tree is what keeps the brush
  /// coordinate math unchanged (KTD-2b).
  Rect zoomedImageRect() {
    final fitted = fittedImageRect();
    if (fitted.isEmpty) {
      return fitted;
    }
    // Clamp on read as well as on write: a re-crop or a viewport change can
    // invalidate a stored offset between gestures, and the image must never be
    // displayed outside the viewport because of it.
    final offset = zoomScale <= minZoomScale
        ? Offset.zero
        : _clampZoomOffset(zoomOffset);
    return Rect.fromLTWH(
      fitted.left + offset.dx,
      fitted.top + offset.dy,
      fitted.width * zoomScale,
      fitted.height * zoomScale,
    );
  }

  /// Where the source photo must be drawn so its pixels land exactly on the
  /// cutout's (KTD-2a). Handles a crop that extends past the source edge —
  /// padding and square framing are not clamped to the source — with no
  /// special case: the uncovered margin simply stays empty.
  Rect? sourceImageDestinationRect(Rect imageRect) {
    final crop = displayCropBounds;
    final sourceWidth = displaySourceWidth;
    final sourceHeight = displaySourceHeight;
    if (crop == null ||
        crop.width <= 0 ||
        crop.height <= 0 ||
        sourceWidth <= 0 ||
        sourceHeight <= 0 ||
        imageRect.isEmpty) {
      return null;
    }

    final scaleX = imageRect.width / crop.width;
    final scaleY = imageRect.height / crop.height;
    return Rect.fromLTWH(
      imageRect.left - crop.left * scaleX,
      imageRect.top - crop.top * scaleY,
      sourceWidth * scaleX,
      sourceHeight * scaleY,
    );
  }

  /// The on-screen radius of a dab whose mask footprint is [radiusFraction].
  ///
  /// `applyBrush` measures the radius in *mask* (source) pixels, so the honest
  /// screen radius has to go through the crop scale. Deriving it from
  /// `imageRect.shortestSide` alone understates a tight crop several times
  /// over, which would make both the cursor ring and the stroke overlay lie
  /// about the result (FR11).
  double brushRadiusPixels(Rect imageRect, {double? radiusFraction}) {
    final fraction = radiusFraction ?? brushRadius;
    final crop = displayCropBounds;
    final sourceWidth = displaySourceWidth;
    final sourceHeight = displaySourceHeight;
    // A 2px on-screen floor, not 6: the ring and the stroke overlay share this
    // number, so a generous floor would draw a circle several times the mask
    // footprint at the small end of the size slider and the settle would visibly
    // shrink it.
    const minScreenRadius = 2.0;
    if (crop == null ||
        crop.width <= 0 ||
        sourceWidth <= 0 ||
        sourceHeight <= 0 ||
        imageRect.isEmpty) {
      return math.max(minScreenRadius, imageRect.shortestSide * fraction);
    }

    final sourceRadius = math.max(
      2.0,
      math.min(sourceWidth, sourceHeight) * fraction,
    );
    return math.max(
      minScreenRadius,
      sourceRadius * (imageRect.width / crop.width),
    );
  }

  /// The normalised image coordinate under a canvas point, used as the zoom
  /// anchor so a pinch or scroll keeps that point under the pointer.
  Offset normalizedImagePoint(Offset point) {
    final rect = zoomedImageRect();
    if (rect.isEmpty) {
      return Offset.zero;
    }
    return Offset(
      (point.dx - rect.left) / rect.width,
      (point.dy - rect.top) / rect.height,
    );
  }

  void setZoom({
    required double scale,
    Offset? focalPoint,
    Offset? anchorNormalized,
  }) {
    final nextScale = scale.clamp(minZoomScale, maxZoomScale).toDouble();
    final fitted = fittedImageRect();

    Offset nextOffset;
    if (nextScale <= minZoomScale ||
        fitted.isEmpty ||
        focalPoint == null ||
        anchorNormalized == null) {
      nextOffset = Offset.zero;
    } else {
      nextOffset = _clampZoomOffset(
        Offset(
          focalPoint.dx -
              fitted.left -
              anchorNormalized.dx * fitted.width * nextScale,
          focalPoint.dy -
              fitted.top -
              anchorNormalized.dy * fitted.height * nextScale,
        ),
        scale: nextScale,
      );
    }

    if (zoomScale == nextScale && zoomOffset == nextOffset) {
      return;
    }
    zoomScale = nextScale;
    zoomOffset = nextOffset;
    _notify();
  }

  void panZoomBy(Offset delta) {
    if (zoomScale <= minZoomScale || delta == Offset.zero) {
      return;
    }
    final next = _clampZoomOffset(zoomOffset + delta);
    if (next == zoomOffset) {
      return;
    }
    zoomOffset = next;
    _notify();
  }

  void resetZoom() {
    if (zoomScale == minZoomScale && zoomOffset == Offset.zero) {
      return;
    }
    zoomScale = minZoomScale;
    zoomOffset = Offset.zero;
    _notify();
  }

  void _resetZoomState() {
    zoomScale = minZoomScale;
    zoomOffset = Offset.zero;
  }

  /// Keeps the magnified image overlapping the viewport centre, so it can be
  /// panned freely but never dragged entirely out of view.
  Offset _clampZoomOffset(Offset offset, {double? scale}) {
    final effectiveScale = scale ?? zoomScale;
    final fitted = fittedImageRect();
    if (fitted.isEmpty || viewportSize.isEmpty) {
      return offset;
    }

    final width = fitted.width * effectiveScale;
    final height = fitted.height * effectiveScale;
    final centreX = viewportSize.width / 2;
    final centreY = viewportSize.height / 2;
    return Offset(
      offset.dx.clamp(centreX - fitted.left - width, centreX - fitted.left),
      offset.dy.clamp(centreY - fitted.top - height, centreY - fitted.top),
    );
  }

  /// The source pixel currently under the viewport centre, captured before a
  /// stroke settles so the re-crop cannot move the view (FR12).
  Offset? _sourcePointAtViewportCentre() {
    final crop = displayCropBounds;
    if (crop == null || zoomScale <= minZoomScale || viewportSize.isEmpty) {
      return null;
    }
    final rect = zoomedImageRect();
    if (rect.isEmpty) {
      return null;
    }

    final normalizedX = (viewportSize.width / 2 - rect.left) / rect.width;
    final normalizedY = (viewportSize.height / 2 - rect.top) / rect.height;
    return Offset(
      crop.left + crop.width * normalizedX,
      crop.top + crop.height * normalizedY,
    );
  }

  /// Puts [sourcePoint] back under the viewport centre against the *new*
  /// crop bounds. Both crops are in hand at settle time, so this is a direct
  /// computation rather than a heuristic.
  void _reanchorZoomToSourcePoint(Offset sourcePoint) {
    final crop = cutoutResult?.cropBounds;
    if (crop == null ||
        crop.width <= 0 ||
        crop.height <= 0 ||
        zoomScale <= minZoomScale ||
        viewportSize.isEmpty) {
      return;
    }
    final fitted = fittedImageRect();
    if (fitted.isEmpty) {
      return;
    }

    final normalizedX = (sourcePoint.dx - crop.left) / crop.width;
    final normalizedY = (sourcePoint.dy - crop.top) / crop.height;
    zoomOffset = _clampZoomOffset(
      Offset(
        viewportSize.width / 2 -
            fitted.left -
            normalizedX * fitted.width * zoomScale,
        viewportSize.height / 2 -
            fitted.top -
            normalizedY * fitted.height * zoomScale,
      ),
    );
  }

  /// Renders the current brush mask live during a stroke. Unlike the slider
  /// re-render this does not set [processingCutout] (which would disable the
  /// brush mid-stroke) and does not overwrite [workingMask] from the rendered
  /// result, so dabs added while a render is in flight are preserved. Renders
  /// are throttled to one in flight with a single trailing render queued, so
  /// the preview keeps up with the stroke instead of only updating on pause.
  void _scheduleBrushRender() {
    if (brushRendering) {
      brushRenderQueued = true;
      return;
    }
    unawaited(_runBrushRender());
  }

  /// The decode width the canvas is currently using, published during layout.
  ///
  /// Derived from the viewport rather than from the output geometry so it stays
  /// stable across a stroke-end re-crop: a key that changed on every settle
  /// would force a fresh decode of every settled frame, which is the cost U3
  /// exists to avoid.
  int? previewCacheWidth;

  void setPreviewCacheWidth(int? value) {
    previewCacheWidth = value;
  }

  Future<void> _runBrushRender() async {
    final source = sourceImageData;
    final mask = workingMask;
    final generation = _cutoutGeneration;
    if (source == null || mask == null || cutoutResult == null) {
      return;
    }

    brushRendering = true;
    try {
      final result = await cutoutService.render(
        imageBytes: source,
        mask: mask,
        settings: cutoutSettings,
      );
      // Drop the render if the image was reset or replaced while it ran.
      if (_disposed ||
          generation != _cutoutGeneration ||
          !identical(sourceImageData, source) ||
          cutoutResult == null) {
        return;
      }

      cutoutResult = result;
      imageData = result.pngBytes;
      image = Image.memory(result.pngBytes).image;
      errorText = null;
      // Drop the overlay in the same notification that adopts the settled
      // result, so no frame shows the dabs twice, then put the zoomed viewport
      // back on the source point it was centred on before the re-crop (FR12).
      final wasSettled = !strokeActive && !brushRenderQueued;
      _clearStrokeOverlayIfSettled();
      final anchor = _pendingZoomAnchor;
      if (wasSettled && anchor != null) {
        _pendingZoomAnchor = null;
        _reanchorZoomToSourcePoint(anchor);
      }
      _notify();
    } catch (_) {
      if (!_disposed && generation == _cutoutGeneration) {
        errorText = 'This edit could not be applied.';
        statusText = null;
        _clearStrokeOverlayIfSettled();
        _notify();
      }
    } finally {
      if (_disposed ||
          generation != _cutoutGeneration ||
          !identical(sourceImageData, source)) {
        return;
      }
      brushRendering = false;
      if (brushRenderQueued) {
        brushRenderQueued = false;
        unawaited(_runBrushRender());
      } else {
        brushRenderQueued = false;
      }
    }
  }

  Future<void> resetCutout() async {
    _cutoutGeneration++;
    loading = false;
    processingCutout = false;
    brushRendering = false;
    brushRenderQueued = false;
    _resetStrokeState();
    final autoMask = autoCutoutMask;
    if (sourceImageData != null && cutoutResult != null && autoMask != null) {
      // Reset is a user-initiated mask replacement, so it is undoable like a
      // stroke: discarding an hour of edge work should not be one-way.
      _pushUndoMask(workingMask ?? cutoutResult?.mask);
      _clearRedoHistory();
      workingMask = autoMask;
      errorText = null;
      _notify();
      await rerenderCutout(
        mask: autoMask,
        successStatusText: 'Auto mask restored.',
      );
      return;
    }

    _clearMaskHistory();
    cutoutResult = null;
    autoCutoutMask = null;
    workingMask = null;
    lastCutoutDiagnostic = null;
    imageData = null;
    image = sourceImageData == null
        ? image
        : Image.memory(sourceImageData!).image;
    statusText = null;
    errorText = null;
    _notify();
  }

  // ---------------------------------------------------------------------
  // Validation and persistence
  // ---------------------------------------------------------------------

  EmoticonShortcodeValidationResult validateShortcode() {
    return validateEmoticonShortcode(
      shortcodeController.text,
      existingShortcodes: pack?.getShortcodes() ?? const [],
      previousShortcode: initialEmoticon?.shortcode,
    );
  }

  /// Saves through the existing pack-save path. Returns true when the pack
  /// update completed, so the presentation layer can close its surface.
  Future<bool> save() async {
    final validation = validateShortcode();
    if (!validation.isValid) {
      errorText = validation.message;
      _notify();
      return false;
    }

    loading = true;
    errorText = null;
    statusText = 'Saving local draft...';
    _notify();

    var didSave = false;
    try {
      final result = cutoutResult;
      // Fall back to the raw source photo when the user chose not to run a
      // cutout, so unedited images can still be submitted.
      final bytes = imageData ?? sourceImageData;
      if (result != null && imageData != null) {
        savedDraft = await draftStore.saveDraft(
          shortcode: validation.normalized,
          pngBytes: imageData!,
          thumbnailBytes: result.thumbnailBytes,
          backend: result.backend,
          width: result.width,
          height: result.height,
          sourceImageHash: sourceImageData == null
              ? null
              : sha256.convert(sourceImageData!).toString(),
          packId: pack?.identifier,
        );
      }

      didSave =
          await onCreate?.call(validation.normalized, usage, bytes) ?? true;

      if (!didSave && !_disposed) {
        statusText = savedDraft == null
            ? 'Save was not completed.'
            : 'Local draft saved. Pack update was not completed.';
        if (savedDraft != null) {
          await loadDrafts();
        }
      }
    } catch (_) {
      if (_disposed) {
        return false;
      }
      errorText = 'This emoticon could not be saved.';
      statusText = savedDraft == null
          ? null
          : 'Local draft saved. Pack update was not completed.';
      if (savedDraft != null) {
        await loadDrafts();
      }
    } finally {
      if (!_disposed) {
        loading = false;
        _notify();
      }
    }

    return didSave;
  }

  Future<bool> saveCutoutToPhotos() async {
    final callback = onSaveToPhotos;
    final result = cutoutResult;
    if (callback == null || result == null || !canSaveToPhotos) {
      return false;
    }

    final validation = validateShortcode();
    final sourceSeed = shortcodeSeedFromImageName(sourceImageName);
    final filenameSeed = validation.normalized.isNotEmpty
        ? validation.normalized
        : sourceSeed.isNotEmpty
        ? sourceSeed
        : 'intergalactic-emoticon';

    savingToPhotos = true;
    errorText = null;
    statusText = 'Saving cutout to Photos...';
    _notify();
    try {
      final saved = await callback('$filenameSeed.png', result.pngBytes);
      if (!_disposed) {
        statusText = saved ? 'Saved cutout to Photos.' : null;
        errorText = saved ? null : 'This cutout could not be saved to Photos.';
      }
      return saved;
    } catch (_) {
      if (!_disposed) {
        statusText = null;
        errorText = 'This cutout could not be saved to Photos.';
      }
      return false;
    } finally {
      if (!_disposed) {
        savingToPhotos = false;
        _notify();
      }
    }
  }

  /// Deletes through the existing callback. Returns true on success so the
  /// presentation layer can close its surface. Confirmation stays in the
  /// widget layer.
  Future<bool> delete() async {
    loading = true;
    errorText = null;
    _notify();

    try {
      await onDelete?.call();
      return true;
    } catch (_) {
      if (!_disposed) {
        errorText = 'This emoticon could not be deleted.';
      }
      return false;
    } finally {
      if (!_disposed) {
        loading = false;
        _notify();
      }
    }
  }

  // ---------------------------------------------------------------------
  // Drafts
  // ---------------------------------------------------------------------

  List<EmoticonDraft> filteredDrafts() {
    final query = draftSearchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return drafts;
    }
    return drafts
        .where((draft) => _draftMatchesSearch(draft, query))
        .toList(growable: false);
  }

  bool _draftMatchesSearch(EmoticonDraft draft, String query) {
    final searchText = [
      draft.shortcode,
      draft.backend.name,
      '${draft.width}x${draft.height}',
      '${draft.width} x ${draft.height}',
      formatEmoticonByteSize(draft.fileSize),
    ].join(' ').toLowerCase();
    return searchText.contains(query);
  }

  void setDraftSearchQuery(String value) {
    draftSearchQuery = value;
    _notify();
  }

  void clearDraftSearch() {
    draftSearchController.clear();
    draftSearchQuery = '';
    _notify();
  }

  Future<void> loadDrafts() async {
    draftsLoading = true;
    draftErrorText = null;
    _notify();

    try {
      final loadedDrafts = await draftStore.listDrafts();
      final thumbnails = <String, Uint8List>{};
      for (final draft in loadedDrafts.take(emoticonDraftThumbnailReadLimit)) {
        final thumbnail = await draftStore.readDraftThumbnail(draft.id);
        if (thumbnail != null) {
          thumbnails[draft.id] = thumbnail;
        }
      }
      if (_disposed) {
        return;
      }
      drafts = loadedDrafts;
      draftThumbnails = thumbnails;
    } catch (_) {
      if (_disposed) {
        return;
      }
      draftErrorText = 'Local drafts could not be loaded.';
    } finally {
      if (!_disposed) {
        draftsLoading = false;
        _notify();
      }
    }
  }

  Future<void> loadDraft(EmoticonDraft draft) async {
    final generation = ++_cutoutGeneration;
    processingCutout = false;
    brushRendering = false;
    brushRenderQueued = false;
    _resetStrokeState();
    _resetZoomState();
    _clearMaskHistory();
    loading = true;
    errorText = null;
    statusText = 'Loading local draft...';
    _notify();

    try {
      final loaded = await draftStore.loadDraft(draft.id);
      if (_disposed || generation != _cutoutGeneration) {
        return;
      }
      if (loaded == null) {
        errorText = 'This local draft is no longer available.';
        await loadDrafts();
        return;
      }

      shortcodeController.text = loaded.draft.shortcode;
      sourceImageData = null;
      sourceImageName = null;
      cutoutResult = null;
      autoCutoutMask = null;
      workingMask = null;
      imageData = loaded.pngBytes;
      image = Image.memory(loaded.pngBytes).image;
      savedDraft = loaded.draft;
      statusText = 'Loaded local draft. Save to add it to this pack.';
    } catch (_) {
      if (!_disposed && generation == _cutoutGeneration) {
        errorText = 'This local draft could not be loaded.';
      }
    } finally {
      if (!_disposed && generation == _cutoutGeneration) {
        loading = false;
        _notify();
      }
    }
  }

  /// Deletes one draft. Confirmation stays in the widget layer.
  Future<void> deleteDraft(EmoticonDraft draft) async {
    loading = true;
    errorText = null;
    statusText = 'Deleting local draft...';
    _notify();

    try {
      await draftStore.deleteDraft(draft.id);
      if (_disposed) {
        return;
      }
      if (savedDraft?.id == draft.id) {
        savedDraft = null;
        statusText =
            'Local draft deleted. The current preview remains until changed.';
      } else {
        statusText = 'Local draft deleted.';
      }
      await loadDrafts();
    } catch (_) {
      if (_disposed) {
        return;
      }
      errorText = 'This local draft could not be deleted.';
    } finally {
      if (!_disposed) {
        loading = false;
        _notify();
      }
    }
  }

  /// Deletes a set of drafts. Confirmation stays in the widget layer.
  Future<void> deleteDrafts(List<EmoticonDraft> targetDrafts) async {
    if (targetDrafts.isEmpty) {
      return;
    }

    final targetIds = targetDrafts.map((draft) => draft.id).toSet();
    loading = true;
    errorText = null;
    statusText = 'Deleting local drafts...';
    _notify();

    try {
      for (final draftId in targetIds) {
        await draftStore.deleteDraft(draftId);
      }
      if (_disposed) {
        return;
      }
      if (targetIds.contains(savedDraft?.id)) {
        savedDraft = null;
        statusText =
            'Local drafts deleted. The current preview remains until changed.';
      } else {
        statusText = 'Local drafts deleted.';
      }
      await loadDrafts();
    } catch (_) {
      if (_disposed) {
        return;
      }
      await loadDrafts();
      if (_disposed) {
        return;
      }
      errorText = 'These local drafts could not be deleted.';
    } finally {
      if (!_disposed) {
        loading = false;
        _notify();
      }
    }
  }
}

String formatEmoticonByteSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kib = bytes / 1024;
  if (kib < 1024) {
    return '${kib.toStringAsFixed(1)} KB';
  }
  return '${(kib / 1024).toStringAsFixed(1)} MB';
}

String formatEmoticonDuration(Duration duration) {
  final milliseconds = duration.inMilliseconds;
  if (milliseconds < 1000) {
    return '$milliseconds ms';
  }

  final seconds = milliseconds / Duration.millisecondsPerSecond;
  return '${seconds.toStringAsFixed(seconds < 10 ? 1 : 0)} s';
}

/// The rect an image occupies inside a container under `BoxFit.contain`.
Rect containedImageRect({
  required Size containerSize,
  required int imageWidth,
  required int imageHeight,
}) {
  if (containerSize.isEmpty || imageWidth <= 0 || imageHeight <= 0) {
    return Rect.zero;
  }

  final scale = math.min(
    containerSize.width / imageWidth,
    containerSize.height / imageHeight,
  );
  final fittedWidth = imageWidth * scale;
  final fittedHeight = imageHeight * scale;
  return Rect.fromLTWH(
    (containerSize.width - fittedWidth) / 2,
    (containerSize.height - fittedHeight) / 2,
    fittedWidth,
    fittedHeight,
  );
}
