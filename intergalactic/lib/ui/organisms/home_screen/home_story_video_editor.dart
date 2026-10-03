import 'dart:async';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intergalactic/cache/file_provider.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_component.dart';
import 'package:intergalactic/client/components/stories/story_component.dart';
import 'package:intergalactic/ui/accessibility/paused_animated_image.dart';
import 'package:intergalactic/ui/molecules/emoji_picker.dart';
import 'package:intergalactic/ui/molecules/video_player/video_player.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_draft.dart';
import 'package:intergalactic/ui/organisms/home_screen/story_video_frame.dart';
import 'package:intergalactic/utils/text_utils.dart';
import 'package:intl/intl.dart';

class HomeStoryVideoEditor {
  static Future<StoryVideoDraft?> show(
    BuildContext context, {
    required Client client,
    required StoryVideoDraft draft,
  }) {
    return Navigator.of(context).push<StoryVideoDraft>(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: InterGalacticMotion.duration(
          context,
          InterGalacticMotion.short,
        ),
        reverseTransitionDuration: InterGalacticMotion.duration(
          context,
          InterGalacticMotion.short,
        ),
        pageBuilder: (context, _, __) =>
            _HomeStoryVideoEditorPage(client: client, draft: draft),
        transitionsBuilder: (context, animation, _, child) {
          if (InterGalacticMotion.shouldReduce(context)) {
            return child;
          }
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: InterGalacticMotion.standardOut,
              reverseCurve: InterGalacticMotion.standardIn,
            ),
            child: child,
          );
        },
      ),
    );
  }
}

/// True when the chosen clip cannot be posted as-is.
///
/// This used to be "does it need re-encoding", answered by shipping an
/// `ffmpeg.exe` that could cut and shrink the source. That binary is gone, so
/// there is no re-encoder on any platform and an unusable clip is now a
/// validation failure the person resolves by picking a different video. See
/// `docs/DECISIONS.md` - "Story Video Trim Is Removed With The Bundled FFmpeg"
/// (2026-08-15).
@visibleForTesting
bool homeStoryVideoEditorSourceIsUnusable({
  required Duration duration,
  required int sizeBytes,
}) {
  return duration > storyMaxVideoDuration ||
      !storyVideoSizeIsAllowed(sizeBytes);
}

@visibleForTesting
bool homeStoryVideoEditorCanEditDecorations({
  required bool preparedForDecoration,
}) => preparedForDecoration;

class _HomeStoryVideoEditorPage extends StatefulWidget {
  const _HomeStoryVideoEditorPage({required this.client, required this.draft});

  final Client client;
  final StoryVideoDraft draft;

  @override
  State<_HomeStoryVideoEditorPage> createState() =>
      _HomeStoryVideoEditorPageState();
}

class _HomeStoryVideoEditorPageState extends State<_HomeStoryVideoEditorPage> {
  late StoryVideoDraft _draft = widget.draft.copyWith(
    canvasMode: StoryVideoCanvasMode.portrait,
  );
  String? _selectedOverlayId;
  _OverlayGestureStart? _gestureStart;
  String? _error;

  String get homeStoryVideoEditorDone => Intl.message(
    'Done',
    name: 'homeStoryVideoEditorDone',
    desc: 'Button text for applying story video editor changes',
  );

  String get homeStoryVideoEditorPrepare => Intl.message(
    'Prepare',
    name: 'homeStoryVideoEditorPrepare',
    desc:
        'Button text for preparing a selected story video segment before editing',
  );

  String get homeStoryVideoEditorText => Intl.message(
    'Text',
    name: 'homeStoryVideoEditorText',
    desc: 'Tooltip for adding text to a story video',
  );

  String get homeStoryVideoEditorEmoji => Intl.message(
    'Emoji',
    name: 'homeStoryVideoEditorEmoji',
    desc: 'Tooltip for adding emoji to a story video',
  );

  String get homeStoryVideoEditorSticker => Intl.message(
    'Sticker',
    name: 'homeStoryVideoEditorSticker',
    desc: 'Tooltip for adding a sticker to a story video',
  );

  String get homeStoryVideoEditorDelete => Intl.message(
    'Delete',
    name: 'homeStoryVideoEditorDelete',
    desc: 'Tooltip for deleting a selected story video overlay',
  );

  String get homeStoryVideoEditorEditSelectedText => Intl.message(
    'Edit text',
    name: 'homeStoryVideoEditorEditSelectedText',
    desc: 'Tooltip for editing a selected story video text overlay',
  );

  String get homeStoryVideoEditorPreviousOverlay => Intl.message(
    'Previous overlay',
    name: 'homeStoryVideoEditorPreviousOverlay',
    desc: 'Tooltip for selecting the previous story video overlay',
  );

  String get homeStoryVideoEditorNextOverlay => Intl.message(
    'Next overlay',
    name: 'homeStoryVideoEditorNextOverlay',
    desc: 'Tooltip for selecting the next story video overlay',
  );

  String get homeStoryVideoEditorMoveOverlayUp => Intl.message(
    'Move up',
    name: 'homeStoryVideoEditorMoveOverlayUp',
    desc: 'Tooltip for moving a selected story video overlay up',
  );

  String get homeStoryVideoEditorMoveOverlayDown => Intl.message(
    'Move down',
    name: 'homeStoryVideoEditorMoveOverlayDown',
    desc: 'Tooltip for moving a selected story video overlay down',
  );

  String get homeStoryVideoEditorMoveOverlayLeft => Intl.message(
    'Move left',
    name: 'homeStoryVideoEditorMoveOverlayLeft',
    desc: 'Tooltip for moving a selected story video overlay left',
  );

  String get homeStoryVideoEditorMoveOverlayRight => Intl.message(
    'Move right',
    name: 'homeStoryVideoEditorMoveOverlayRight',
    desc: 'Tooltip for moving a selected story video overlay right',
  );

  String get homeStoryVideoEditorSmaller => Intl.message(
    'Smaller',
    name: 'homeStoryVideoEditorSmaller',
    desc: 'Tooltip for reducing a selected story video overlay size',
  );

  String get homeStoryVideoEditorLarger => Intl.message(
    'Larger',
    name: 'homeStoryVideoEditorLarger',
    desc: 'Tooltip for increasing a selected story video overlay size',
  );

  String get homeStoryVideoEditorRotateLeft => Intl.message(
    'Rotate left',
    name: 'homeStoryVideoEditorRotateLeft',
    desc: 'Tooltip for rotating a selected story video overlay left',
  );

  String get homeStoryVideoEditorRotateRight => Intl.message(
    'Rotate right',
    name: 'homeStoryVideoEditorRotateRight',
    desc: 'Tooltip for rotating a selected story video overlay right',
  );

  String get homeStoryVideoEditorFit => Intl.message(
    'Fit',
    name: 'homeStoryVideoEditorFit',
    desc: 'Tooltip for fitting the full story video inside the frame',
  );

  String get homeStoryVideoEditorFill => Intl.message(
    'Fill',
    name: 'homeStoryVideoEditorFill',
    desc: 'Tooltip for filling the story frame with cropped video',
  );

  /// The ARB key still says `InvalidRange` on purpose: it is a translation key
  /// with existing translations behind it, and renaming it would orphan them.
  /// Only the Dart member is renamed, because "range" stopped meaning anything
  /// here when the trim range was removed.
  String get homeStoryVideoEditorInvalidRange => Intl.message(
    'Story videos must be 30 seconds or shorter.',
    name: 'homeStoryVideoEditorInvalidRange',
    desc: 'Validation shown when a story video is longer than the limit',
  );

  String get homeStoryVideoEditorSourceTooLarge => Intl.message(
    'That video is too large to post. Choose a shorter or smaller recording.',
    name: 'homeStoryVideoEditorSourceTooLarge',
    desc: 'Validation shown when a story video file exceeds the size limit',
  );

  String get homeStoryVideoEditorPrepareBeforeEditing => Intl.message(
    'Choose the canvas shape, then Prepare before adding text, emoji, stickers, or backgrounds.',
    name: 'homeStoryVideoEditorPrepareBeforeEditing',
    desc:
        'State text shown when a story video must be prepared before overlay editing',
  );

  String get homeStoryVideoEditorBackgroundColor => Intl.message(
    'Background',
    name: 'homeStoryVideoEditorBackgroundColor',
    desc: 'Tooltip for changing the story video background color',
  );

  String get homeStoryVideoEditorNoStickers => Intl.message(
    'No account stickers available.',
    name: 'homeStoryVideoEditorNoStickers',
    desc: 'Message shown when no account/global sticker packs are available',
  );

  String get homeStoryVideoEditorStickerError => Intl.message(
    'That sticker could not be added.',
    name: 'homeStoryVideoEditorStickerError',
    desc: 'Error shown when a story video sticker cannot be resolved',
  );

  String get homeStoryVideoEditorTextDialogTitle => Intl.message(
    'Story Text',
    name: 'homeStoryVideoEditorTextDialogTitle',
    desc: 'Title for editing story video text',
  );

  StoryOverlay? get _selectedOverlay {
    final selectedId = _selectedOverlayId;
    if (selectedId == null) {
      return null;
    }
    return _draft.overlays
        .where((overlay) => overlay.id == selectedId)
        .firstOrNull;
  }

  bool get _sourceIsUnusable => homeStoryVideoEditorSourceIsUnusable(
    duration: _draft.duration,
    sizeBytes: _draft.sizeBytes,
  );

  bool get _isPrepareStage => !_draft.preparedForDecoration;

  bool get _canEditOverlays => homeStoryVideoEditorCanEditDecorations(
    preparedForDecoration: _draft.preparedForDecoration,
  );

  bool get _canFinish => _draft.toUpload().hasValidSelection;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final validation = _validationMessage;
    final isPrepareStage = _isPrepareStage;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    color: Colors.white,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _canFinish ? _finish : null,
                    child: Text(
                      isPrepareStage
                          ? homeStoryVideoEditorPrepare
                          : homeStoryVideoEditorDone,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = storyVideoCanvasSizeForConstraints(
                      constraints: constraints,
                      canvasMode: _draft.canvasMode,
                    );
                    return SizedBox(
                      width: size.width,
                      height: size.height,
                      child: _buildCanvas(size),
                    );
                  },
                ),
              ),
            ),
            if (_error != null || validation != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.errorContainer.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      _error ?? validation!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ),
            if (_error == null && validation == null && isPrepareStage)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        // Not scissors: the trim range was removed, and the
                        // icon was still advertising a cut the editor cannot
                        // make.
                        const Icon(
                          Icons.movie_outlined,
                          size: 18,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            homeStoryVideoEditorPrepareBeforeEditing,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            _buildToolbar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvas(Size size) {
    final canEditOverlays = _canEditOverlays;
    final layout = storyVideoCompositionLayout(
      canvasSize: size,
      fitMode: _draft.fitMode,
      mediaWidth: _draft.width,
      mediaHeight: _draft.height,
      displayWidth: _draft.displayWidth,
      displayHeight: _draft.displayHeight,
      hasBakedLetterbox: _draft.hasBakedLetterbox,
    );
    return DecoratedBox(
      decoration: storyVideoBackgroundDecoration(
        backgroundColor: _draft.backgroundColor,
        backgroundGradientColor: _draft.backgroundGradientColor,
        backgroundMode: _draft.backgroundMode,
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: ClipRect(
        child: Stack(
          children: [
            Positioned.fromRect(
              rect: layout.mediaDisplayRect,
              child: StoryVideoMediaLayer(
                layout: layout,
                builder: (fit) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: canEditOverlays
                      ? () => setState(() => _selectedOverlayId = null)
                      : null,
                  child: VideoPlayer(
                    SystemFileProvider(_draft.path),
                    thumbnail: _draft.thumbnailBytes == null
                        ? null
                        : MemoryImage(_draft.thumbnailBytes!),
                    fileName: _draft.sourceName,
                    doThumbnail: _draft.thumbnailBytes != null,
                    decodeFirstFrame: true,
                    showProgressBar: true,
                    fit: fit,
                    // The story background owns non-media pixels; the video
                    // surface must not paint its own black letterbox.
                    letterboxFill: Colors.transparent,
                  ),
                ),
              ),
            ),
            StoryVideoBackgroundMatte(
              rects: layout.nonMediaRects,
              backgroundColor: _draft.backgroundColor,
              backgroundGradientColor: _draft.backgroundGradientColor,
              backgroundMode: _draft.backgroundMode,
            ),
            for (final overlay in _draft.overlays)
              _StoryVideoOverlayWidget(
                overlay: overlay,
                canvasSize: size,
                selected: overlay.id == _selectedOverlayId,
                onTap: canEditOverlays
                    ? () => _handleOverlayTap(overlay)
                    : () {},
                onLongPress: canEditOverlays
                    ? () => _removeOverlay(overlay.id)
                    : () {},
                onScaleStart: canEditOverlays
                    ? (details) => _startOverlayGesture(overlay, details, size)
                    : (_) {},
                onScaleUpdate: canEditOverlays ? _updateOverlayGesture : (_) {},
                onScaleEnd: (_) => _gestureStart = null,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final selected = _selectedOverlay;
    final canEditOverlays = _canEditOverlays;
    final isPrepareStage = _isPrepareStage;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isPrepareStage) ...[
              _ToolbarButton(
                tooltip: homeStoryVideoEditorFit,
                icon: Icons.fit_screen,
                selected: _draft.fitMode == StoryVideoFitMode.fit,
                onPressed: () => _setFitMode(StoryVideoFitMode.fit),
              ),
              _ToolbarButton(
                tooltip: homeStoryVideoEditorFill,
                icon: Icons.crop,
                selected: _draft.fitMode == StoryVideoFitMode.fill,
                onPressed: () => _setFitMode(StoryVideoFitMode.fill),
              ),
            ] else ...[
              if (_draft.overlays.isNotEmpty && canEditOverlays) ...[
                _ToolbarButton(
                  tooltip: homeStoryVideoEditorPreviousOverlay,
                  icon: Icons.skip_previous,
                  onPressed: () => _selectAdjacentOverlay(-1),
                ),
                _ToolbarButton(
                  tooltip: homeStoryVideoEditorNextOverlay,
                  icon: Icons.skip_next,
                  onPressed: () => _selectAdjacentOverlay(1),
                ),
                const SizedBox(width: 8),
              ],
              _ToolbarButton(
                tooltip: homeStoryVideoEditorText,
                icon: Icons.text_fields,
                onPressed: canEditOverlays ? _addTextOverlay : null,
              ),
              _ToolbarButton(
                tooltip: homeStoryVideoEditorEmoji,
                icon: Icons.emoji_emotions_outlined,
                onPressed: canEditOverlays ? _addEmojiOverlay : null,
              ),
              _ToolbarButton(
                tooltip: homeStoryVideoEditorSticker,
                icon: Icons.sticky_note_2_outlined,
                onPressed: canEditOverlays ? _addStickerOverlay : null,
              ),
              _ToolbarButton(
                tooltip: homeStoryVideoEditorBackgroundColor,
                icon: Icons.palette_outlined,
                selected:
                    _draft.backgroundMode != StoryBackgroundMode.solid ||
                    _draft.backgroundColor !=
                        const Color(storyDefaultVideoBackgroundColor),
                onPressed: _chooseBackgroundColor,
              ),
            ],
            if (selected != null && canEditOverlays) ...[
              const SizedBox(width: 8),
              if (selected is StoryTextOverlay) ...[
                _ToolbarButton(
                  tooltip: homeStoryVideoEditorEditSelectedText,
                  icon: Icons.edit,
                  onPressed: () => _editTextOverlay(selected),
                ),
                const SizedBox(width: 4),
              ],
              _ToolbarButton(
                tooltip: homeStoryVideoEditorSmaller,
                icon: Icons.remove_circle_outline,
                onPressed: () => _scaleSelectedOverlay(selected, 0.9),
              ),
              _ToolbarButton(
                tooltip: homeStoryVideoEditorLarger,
                icon: Icons.add_circle_outline,
                onPressed: () => _scaleSelectedOverlay(selected, 1.1),
              ),
              _ToolbarButton(
                tooltip: homeStoryVideoEditorRotateLeft,
                icon: Icons.rotate_left,
                onPressed: () =>
                    _rotateSelectedOverlay(selected, -math.pi / 18),
              ),
              _ToolbarButton(
                tooltip: homeStoryVideoEditorRotateRight,
                icon: Icons.rotate_right,
                onPressed: () => _rotateSelectedOverlay(selected, math.pi / 18),
              ),
              const SizedBox(width: 4),
              ..._buildSelectedOverlayMoveButtons(selected),
              _ToolbarButton(
                tooltip: homeStoryVideoEditorDelete,
                icon: Icons.delete_outline,
                foregroundColor: Theme.of(context).colorScheme.error,
                onPressed: () => _removeOverlay(selected.id),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSelectedOverlayMoveButtons(StoryOverlay overlay) {
    return [
      _ToolbarButton(
        tooltip: homeStoryVideoEditorMoveOverlayLeft,
        icon: Icons.keyboard_arrow_left,
        onPressed: () => _moveSelectedOverlay(
          overlay,
          const Offset(-storyOverlayKeyboardMoveStep, 0),
        ),
      ),
      _ToolbarButton(
        tooltip: homeStoryVideoEditorMoveOverlayUp,
        icon: Icons.keyboard_arrow_up,
        onPressed: () => _moveSelectedOverlay(
          overlay,
          const Offset(0, -storyOverlayKeyboardMoveStep),
        ),
      ),
      _ToolbarButton(
        tooltip: homeStoryVideoEditorMoveOverlayDown,
        icon: Icons.keyboard_arrow_down,
        onPressed: () => _moveSelectedOverlay(
          overlay,
          const Offset(0, storyOverlayKeyboardMoveStep),
        ),
      ),
      _ToolbarButton(
        tooltip: homeStoryVideoEditorMoveOverlayRight,
        icon: Icons.keyboard_arrow_right,
        onPressed: () => _moveSelectedOverlay(
          overlay,
          const Offset(storyOverlayKeyboardMoveStep, 0),
        ),
      ),
    ];
  }

  String? get _validationMessage {
    if (_draft.selectedDuration <= Duration.zero ||
        _draft.selectedDuration > storyMaxVideoDuration) {
      return homeStoryVideoEditorInvalidRange;
    }
    return null;
  }

  Future<void> _chooseBackgroundColor() async {
    final choice = await showModalBottomSheet<_StoryVideoBackgroundChoice>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      builder: (context) => _StoryVideoBackgroundSheet(
        selectedColor: _draft.backgroundColor,
        selectedGradientColor: _draft.backgroundGradientColor,
        selectedMode: _draft.backgroundMode,
      ),
    );
    if (!mounted || choice == null) {
      return;
    }
    setState(() {
      _draft = _draft.copyWith(
        backgroundColor: choice.color,
        backgroundGradientColor: choice.gradientColor,
        backgroundMode: choice.mode,
      );
      _error = null;
    });
  }

  void _setFitMode(StoryVideoFitMode fitMode) {
    if (_draft.fitMode == fitMode) {
      return;
    }
    setState(() {
      _draft = _draft.copyWith(fitMode: fitMode);
      _error = null;
    });
  }

  Future<void> _finish() async {
    setState(() => _error = null);
    final upload = _draft.toUpload();
    if (!upload.hasValidSelection) {
      setState(() => _error = homeStoryVideoEditorInvalidRange);
      return;
    }

    if (!_isPrepareStage) {
      Navigator.of(context).pop(_draft);
      return;
    }

    // Nothing can re-encode the source any more, so an oversized clip is
    // refused here instead of being silently shrunk. The person picks a
    // different recording; that is the whole remedy.
    if (_sourceIsUnusable) {
      setState(
        () => _error = _draft.duration > storyMaxVideoDuration
            ? homeStoryVideoEditorInvalidRange
            : homeStoryVideoEditorSourceTooLarge,
      );
      return;
    }

    setState(() {
      _draft = _draft.copyWith(preparedForDecoration: true);
      _selectedOverlayId = null;
      _gestureStart = null;
      _error = null;
    });
  }

  Future<void> _addTextOverlay() async {
    final edit = await showDialog<_StoryTextEdit>(
      context: context,
      builder: (context) =>
          _StoryTextDialog(title: homeStoryVideoEditorTextDialogTitle),
    );
    if (!mounted || edit == null || edit.text.trim().isEmpty) {
      return;
    }
    final overlay = StoryTextOverlay(
      id: createStoryDraftId(),
      center: const Offset(0.5, 0.45),
      text: edit.text.trim(),
      color: edit.color,
      isBold: edit.isBold,
      isItalic: edit.isItalic,
    );
    setState(() {
      _draft = _draft.addOverlay(overlay);
      _selectedOverlayId = overlay.id;
      _error = null;
    });
  }

  Future<void> _addEmojiOverlay() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      builder: (context) => const _StoryEmojiSheet(),
    );
    if (!mounted || selected == null || selected.trim().isEmpty) {
      return;
    }
    final overlay = StoryEmojiOverlay(
      id: createStoryDraftId(),
      center: const Offset(0.5, 0.52),
      emoji: selected,
    );
    setState(() {
      _draft = _draft.addOverlay(overlay);
      _selectedOverlayId = overlay.id;
      _error = null;
    });
  }

  Future<void> _addStickerOverlay() async {
    final packs = _accountStickerPacks();
    if (packs.isEmpty) {
      setState(() => _error = homeStoryVideoEditorNoStickers);
      return;
    }
    final emoticon = await showModalBottomSheet<Emoticon>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: math.min(MediaQuery.sizeOf(context).height * 0.72, 520.0),
        child: EmojiPicker(
          packs,
          onlyStickers: true,
          size: 76,
          packButtonSize: 44,
          showSearchBar: false,
          mobileStyle: MediaQuery.sizeOf(context).width < 620,
          onEmoticonPressed: (homeStoryVideoEditorSticker) =>
              Navigator.of(context).pop(homeStoryVideoEditorSticker),
        ),
      ),
    );
    if (!mounted || emoticon == null) {
      return;
    }

    final image = emoticon.image;
    final mediaUri = Uri.tryParse(emoticon.key);
    if (image == null || mediaUri?.scheme != 'mxc') {
      setState(() => _error = homeStoryVideoEditorStickerError);
      return;
    }

    final overlay = StoryStickerOverlay(
      id: createStoryDraftId(),
      center: const Offset(0.5, 0.55),
      label: emoticon.shortcode ?? emoticon.slug,
      image: image,
    );
    setState(() {
      _draft = _draft.addOverlay(overlay, stickerMediaUri: mediaUri);
      _selectedOverlayId = overlay.id;
      _error = null;
    });
  }

  List<EmoticonPack> _accountStickerPacks() {
    final emoticons = widget.client.getComponent<EmoticonComponent>();
    if (emoticons == null) {
      return const [];
    }

    final packs = <EmoticonPack>[];
    final seen = <String>{};
    void addPack(EmoticonPack pack) {
      if (pack.stickers.isEmpty || !seen.add(pack.identifier)) {
        return;
      }
      packs.add(pack);
    }

    for (final pack in emoticons.globalPacks()) {
      addPack(pack);
    }
    for (final pack in emoticons.ownedPacks) {
      addPack(pack);
    }
    return packs;
  }

  void _handleOverlayTap(StoryOverlay overlay) {
    setState(() {
      _selectedOverlayId = overlay.id;
    });
  }

  void _removeOverlay(String overlayId) {
    setState(() {
      _draft = _draft.removeOverlay(overlayId);
      if (_selectedOverlayId == overlayId) {
        _selectedOverlayId = null;
      }
    });
  }

  Future<void> _editTextOverlay(StoryTextOverlay overlay) async {
    final edit = await showDialog<_StoryTextEdit>(
      context: context,
      builder: (context) => _StoryTextDialog(
        title: homeStoryVideoEditorTextDialogTitle,
        initialText: overlay.text,
        initialColor: overlay.color,
        initialBold: overlay.isBold,
        initialItalic: overlay.isItalic,
      ),
    );
    if (!mounted || edit == null || edit.text.trim().isEmpty) {
      return;
    }
    final next = overlay.copyWith(
      text: edit.text.trim(),
      color: edit.color,
      isBold: edit.isBold,
      isItalic: edit.isItalic,
    );
    setState(() {
      _draft = _draft.replaceOverlay(next);
      _selectedOverlayId = overlay.id;
      _error = null;
    });
  }

  void _scaleSelectedOverlay(StoryOverlay overlay, double factor) {
    final next = overlay.copyWithTransform(
      scale: (overlay.scale * factor).clamp(0.35, 5.0).toDouble(),
    );
    setState(() {
      _draft = _draft.replaceOverlay(next);
      _selectedOverlayId = overlay.id;
    });
  }

  void _rotateSelectedOverlay(StoryOverlay overlay, double deltaRadians) {
    final next = overlay.copyWithTransform(
      rotationRadians: overlay.rotationRadians + deltaRadians,
    );
    setState(() {
      _draft = _draft.replaceOverlay(next);
      _selectedOverlayId = overlay.id;
    });
  }

  void _moveSelectedOverlay(StoryOverlay overlay, Offset delta) {
    final next = overlay.copyWithTransform(
      center: storyOverlayMovedCenter(center: overlay.center, delta: delta),
    );
    setState(() {
      _draft = _draft.replaceOverlay(next);
      _selectedOverlayId = overlay.id;
    });
  }

  void _selectAdjacentOverlay(int direction) {
    final overlays = _draft.overlays;
    if (overlays.isEmpty) {
      return;
    }
    final selectedIndex = overlays.indexWhere(
      (overlay) => overlay.id == _selectedOverlayId,
    );
    final nextIndex = selectedIndex < 0
        ? (direction < 0 ? overlays.length - 1 : 0)
        : (selectedIndex + direction) % overlays.length;
    setState(() {
      _selectedOverlayId = overlays[nextIndex].id;
      _error = null;
    });
  }

  void _startOverlayGesture(
    StoryOverlay overlay,
    ScaleStartDetails details,
    Size canvasSize,
  ) {
    setState(() {
      _selectedOverlayId = overlay.id;
      _gestureStart = _OverlayGestureStart(
        overlay: overlay,
        focalPoint: details.focalPoint,
        canvasSize: canvasSize,
      );
    });
  }

  void _updateOverlayGesture(ScaleUpdateDetails details) {
    final start = _gestureStart;
    if (start == null) {
      return;
    }
    final canvas = start.canvasSize;
    if (canvas.width <= 0 || canvas.height <= 0) {
      return;
    }
    final delta = details.focalPoint - start.focalPoint;
    final nextCenter = Offset(
      (start.overlay.center.dx + delta.dx / canvas.width).clamp(0.02, 0.98),
      (start.overlay.center.dy + delta.dy / canvas.height).clamp(0.02, 0.98),
    );
    final next = start.overlay.copyWithTransform(
      center: nextCenter,
      scale: (start.overlay.scale * details.scale).clamp(0.35, 5.0),
      rotationRadians: start.overlay.rotationRadians + details.rotation,
    );
    setState(() {
      _draft = _draft.replaceOverlay(next);
    });
  }
}

class _OverlayGestureStart {
  const _OverlayGestureStart({
    required this.overlay,
    required this.focalPoint,
    required this.canvasSize,
  });

  final StoryOverlay overlay;
  final Offset focalPoint;
  final Size canvasSize;
}

class _StoryVideoOverlayWidget extends StatelessWidget {
  const _StoryVideoOverlayWidget({
    required this.overlay,
    required this.canvasSize,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.onScaleEnd,
  });

  final StoryOverlay overlay;
  final Size canvasSize;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final GestureScaleStartCallback onScaleStart;
  final GestureScaleUpdateCallback onScaleUpdate;
  final GestureScaleEndCallback onScaleEnd;

  @override
  Widget build(BuildContext context) {
    final outputScale = canvasSize.width / storyEditorOutputWidth;
    late final Widget child;
    late final double width;
    late final double height;

    switch (overlay) {
      case StoryTextOverlay():
        final textOverlay = overlay as StoryTextOverlay;
        final fontSize = textOverlay.fontSize * outputScale * textOverlay.scale;
        width = canvasSize.width * 0.86;
        height = math.max(54.0, fontSize * 1.9);
        child = Center(
          child: DecoratedBox(
            decoration: textOverlay.backgroundColor == null
                ? const BoxDecoration()
                : BoxDecoration(
                    color: textOverlay.backgroundColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
            child: Padding(
              padding: textOverlay.backgroundColor == null
                  ? EdgeInsets.zero
                  : EdgeInsets.symmetric(
                      horizontal: 14 * outputScale * textOverlay.scale,
                      vertical: 8 * outputScale * textOverlay.scale,
                    ),
              child: Text.rich(
                TextSpan(
                  children: TextUtils.nativeEmojiTextSpans(
                    textOverlay.text,
                    style: TextStyle(
                      color: textOverlay.color,
                      fontSize: fontSize,
                      fontWeight: textOverlay.isBold
                          ? FontWeight.w700
                          : FontWeight.w400,
                      fontStyle: textOverlay.isItalic
                          ? FontStyle.italic
                          : FontStyle.normal,
                      shadows: const [
                        Shadow(color: Colors.black87, blurRadius: 6),
                      ],
                    ),
                  ),
                ),
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.visible,
              ),
            ),
          ),
        );
      case StoryEmojiOverlay():
        final emojiOverlay = overlay as StoryEmojiOverlay;
        final fontSize =
            emojiOverlay.fontSize * outputScale * emojiOverlay.scale;
        width = math.max(72.0, fontSize * 1.4);
        height = math.max(72.0, fontSize * 1.4);
        child = Center(
          child: Text(
            emojiOverlay.emoji,
            style: TextUtils.withNativeEmojiFallback(
              TextStyle(
                fontSize: fontSize,
                shadows: const [Shadow(color: Colors.black87, blurRadius: 6)],
              ),
            ),
          ),
        );
      case StoryStickerOverlay():
        final stickerOverlay = overlay as StoryStickerOverlay;
        final size = stickerOverlay.size * outputScale * stickerOverlay.scale;
        width = math.max(56.0, size);
        height = math.max(56.0, size);
        child = PausedAnimatedImage(
          image: stickerOverlay.image,
          fit: BoxFit.contain,
          errorBuilder: (context, _, __) => Icon(
            Icons.broken_image_outlined,
            color: Theme.of(context).colorScheme.error,
          ),
        );
      case StoryMentionOverlay():
        width = 0;
        height = 0;
        child = const SizedBox.shrink();
    }

    if (width <= 0 || height <= 0) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: overlay.center.dx * canvasSize.width - width / 2,
      top: overlay.center.dy * canvasSize.height - height / 2,
      width: width,
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onTap,
        onLongPress: onLongPress,
        onScaleStart: onScaleStart,
        onScaleUpdate: onScaleUpdate,
        onScaleEnd: onScaleEnd,
        child: Transform.rotate(
          angle: overlay.rotationRadians,
          child: DecoratedBox(
            decoration: selected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white, width: 2),
                  )
                : const BoxDecoration(),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.foregroundColor,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? foregroundColor;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      style: IconButton.styleFrom(
        foregroundColor: foregroundColor ?? Colors.white,
        disabledForegroundColor: Colors.white38,
        backgroundColor: selected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.34)
            : Colors.white.withValues(alpha: 0.10),
        minimumSize: const Size.square(46),
      ),
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}

class _StoryTextDialog extends StatefulWidget {
  const _StoryTextDialog({
    required this.title,
    this.initialText = '',
    this.initialColor = Colors.white,
    this.initialBold = true,
    this.initialItalic = false,
  });

  final String title;
  final String initialText;
  final Color initialColor;
  final bool initialBold;
  final bool initialItalic;

  @override
  State<_StoryTextDialog> createState() => _StoryTextDialogState();
}

class _StoryTextDialogState extends State<_StoryTextDialog> {
  late final TextEditingController _controller;
  late Color _color;
  late bool _isBold;
  late bool _isItalic;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _color = widget.initialColor;
    _isBold = widget.initialBold;
    _isItalic = widget.initialItalic;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final color in _textColors)
                InkResponse(
                  onTap: () => setState(() => _color = color),
                  radius: 20,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: color == _color
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                        width: color == _color ? 3 : 1,
                      ),
                    ),
                    child: const SizedBox.square(dimension: 32),
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Bold',
          isSelected: _isBold,
          onPressed: () => setState(() => _isBold = !_isBold),
          icon: const Icon(Icons.format_bold),
        ),
        IconButton(
          tooltip: 'Italic',
          isSelected: _isItalic,
          onPressed: () => setState(() => _isItalic = !_isItalic),
          icon: const Icon(Icons.format_italic),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(_StoryTextEdit(_controller.text, _color, _isBold, _isItalic)),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}

class _StoryTextEdit {
  const _StoryTextEdit(this.text, this.color, this.isBold, this.isItalic);

  final String text;
  final Color color;
  final bool isBold;
  final bool isItalic;
}

class _StoryEmojiSheet extends StatelessWidget {
  const _StoryEmojiSheet();

  static const List<String> choices = [
    '\u{1F602}',
    '\u{1F60D}',
    '\u{1F525}',
    '\u{2728}',
    '\u{1F44D}',
    '\u{1F389}',
    '\u{1F680}',
    '\u{1F48E}',
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: 170,
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 72,
            mainAxisExtent: 64,
          ),
          itemCount: choices.length,
          itemBuilder: (context, index) {
            final value = choices[index];
            return InkResponse(
              onTap: () => Navigator.of(context).pop(value),
              child: Center(
                child: Text(
                  value,
                  style: TextUtils.withNativeEmojiFallback(
                    const TextStyle(fontSize: 34),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StoryVideoBackgroundSheet extends StatelessWidget {
  const _StoryVideoBackgroundSheet({
    required this.selectedColor,
    required this.selectedGradientColor,
    required this.selectedMode,
  });

  final Color selectedColor;
  final Color selectedGradientColor;
  final StoryBackgroundMode selectedMode;

  String get homeStoryVideoEditorSolidBackgrounds => Intl.message(
    'Solid',
    name: 'homeStoryVideoEditorSolidBackgrounds',
    desc: 'Label for solid story video background color choices',
  );

  String get homeStoryVideoEditorGradientBackgrounds => Intl.message(
    'Gradient',
    name: 'homeStoryVideoEditorGradientBackgrounds',
    desc: 'Label for gradient story video background choices',
  );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              homeStoryVideoEditorSolidBackgrounds,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final (index, color)
                    in storyEditorBackgroundColors.indexed)
                  _StoryVideoColorButton(
                    key: ValueKey('story-video-background-color-$index'),
                    color: color,
                    selected:
                        selectedMode == StoryBackgroundMode.solid &&
                        color == selectedColor,
                    onTap: () => Navigator.of(context).pop(
                      _StoryVideoBackgroundChoice(
                        mode: StoryBackgroundMode.solid,
                        color: color,
                        gradientColor: selectedGradientColor,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              homeStoryVideoEditorGradientBackgrounds,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final (index, preset)
                    in storyEditorBackgroundGradientPresets.indexed)
                  _StoryVideoGradientButton(
                    key: ValueKey('story-video-background-gradient-$index'),
                    startColor: preset.startColor,
                    endColor: preset.endColor,
                    selected:
                        selectedMode == StoryBackgroundMode.gradient &&
                        selectedColor == preset.startColor &&
                        selectedGradientColor == preset.endColor,
                    onTap: () => Navigator.of(context).pop(
                      _StoryVideoBackgroundChoice(
                        mode: StoryBackgroundMode.gradient,
                        color: preset.startColor,
                        gradientColor: preset.endColor,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryVideoBackgroundChoice {
  const _StoryVideoBackgroundChoice({
    required this.mode,
    required this.color,
    required this.gradientColor,
  });

  final StoryBackgroundMode mode;
  final Color color;
  final Color gradientColor;
}

class _StoryVideoColorButton extends StatelessWidget {
  const _StoryVideoColorButton({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
            width: selected ? 3 : 1,
          ),
        ),
        child: const SizedBox.square(dimension: 34),
      ),
    );
  }
}

class _StoryVideoGradientButton extends StatelessWidget {
  const _StoryVideoGradientButton({
    super.key,
    required this.startColor,
    required this.endColor,
    required this.selected,
    required this.onTap,
  });

  final Color startColor;
  final Color endColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [startColor, endColor],
          ),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
            width: selected ? 3 : 1,
          ),
        ),
        child: const SizedBox.square(dimension: 34),
      ),
    );
  }
}

const List<Color> _textColors = [
  Colors.white,
  Colors.black,
  Color(0xFFFFD54F),
  Color(0xFFFF7043),
  Color(0xFF29B6F6),
  Color(0xFF66BB6A),
  Color(0xFFEC407A),
];
