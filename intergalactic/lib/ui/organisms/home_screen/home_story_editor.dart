import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crop_image/crop_image.dart';
import 'package:flutter/material.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_component.dart';
import 'package:intergalactic/ui/accessibility/paused_animated_image.dart';
import 'package:intergalactic/ui/molecules/emoji_picker.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_draft.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_filter.dart';
import 'package:intergalactic/ui/organisms/home_screen/story_image_renderer.dart';
import 'package:intergalactic/utils/emoji/unicode_emoji.dart';
import 'package:intergalactic/utils/image_utils.dart';
import 'package:intergalactic/utils/picker_utils.dart';
import 'package:intergalactic/utils/text_utils.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class HomeStoryEditor extends StatefulWidget {
  const HomeStoryEditor({
    super.key,
    required this.client,
    required this.draft,
    required this.onDone,
    required this.onCancel,
  });

  final Client client;
  final StoryDraft draft;
  final ValueChanged<StoryDraft> onDone;
  final VoidCallback onCancel;

  static Future<StoryDraft?> show(
    BuildContext context, {
    required Client client,
    required StoryDraft draft,
  }) {
    return Navigator.of(context).push<StoryDraft>(
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
        pageBuilder: (context, _, __) => HomeStoryEditor(
          client: client,
          draft: draft,
          onDone: (updated) => Navigator.of(context).pop(updated),
          onCancel: () => Navigator.of(context).pop(),
        ),
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

  @override
  State<HomeStoryEditor> createState() => _HomeStoryEditorState();
}

class _HomeStoryEditorState extends State<HomeStoryEditor> {
  final StoryImageRenderer _renderer = const StoryImageRenderer();
  late StoryDraft _draft;
  String? _selectedOverlayId;
  String? _error;
  bool _saving = false;
  bool _cropping = false;
  bool _filterControlsVisible = false;
  double _canvasHorizontalDragDistance = 0;
  Size _canvasSize = Size.zero;
  _OverlayGestureStart? _gestureStart;

  String get done => Intl.message(
    'Done',
    name: 'homeStoryEditorDone',
    desc: 'Button text for applying story editor changes',
  );

  String get crop => Intl.message(
    'Crop',
    name: 'homeStoryEditorCrop',
    desc: 'Tooltip for story crop editor action',
  );

  String get fillCanvas => Intl.message(
    'Fill canvas',
    name: 'homeStoryEditorFillCanvas',
    desc: 'Tooltip for filling the story canvas with a cropped photo',
  );

  String get fitWholePhoto => Intl.message(
    'Fit whole photo',
    name: 'homeStoryEditorFitWholePhoto',
    desc: 'Tooltip for fitting the whole story photo on a black canvas',
  );

  String get backgroundColor => Intl.message(
    'Background color',
    name: 'homeStoryEditorBackgroundColor',
    desc: 'Tooltip for changing the story canvas background color',
  );

  String get filter => Intl.message(
    'Filter',
    name: 'homeStoryEditorFilter',
    desc: 'Tooltip for changing the story photo filter',
  );

  String get filterIntensity => Intl.message(
    'Intensity',
    name: 'homeStoryEditorFilterIntensity',
    desc: 'Label for story filter intensity slider',
  );

  String get previousFilter => Intl.message(
    'Previous filter',
    name: 'homeStoryEditorPreviousFilter',
    desc: 'Tooltip for cycling to the previous story photo filter',
  );

  String get nextFilter => Intl.message(
    'Next filter',
    name: 'homeStoryEditorNextFilter',
    desc: 'Tooltip for cycling to the next story photo filter',
  );

  String get mention => Intl.message(
    'Mention',
    name: 'homeStoryEditorMention',
    desc: 'Tooltip for adding a visual story mention sticker',
  );

  String get text => Intl.message(
    'Text',
    name: 'homeStoryEditorText',
    desc: 'Tooltip for adding text to a story',
  );

  String get emoji => Intl.message(
    'Emoji',
    name: 'homeStoryEditorEmoji',
    desc: 'Tooltip for adding emoji to a story',
  );

  String get sticker => Intl.message(
    'Sticker',
    name: 'homeStoryEditorSticker',
    desc: 'Tooltip for adding a sticker to a story',
  );

  String get delete => Intl.message(
    'Delete',
    name: 'homeStoryEditorDelete',
    desc: 'Tooltip for deleting the selected story overlay',
  );

  String get previousOverlay => Intl.message(
    'Previous overlay',
    name: 'homeStoryEditorPreviousOverlay',
    desc: 'Tooltip for selecting the previous story overlay',
  );

  String get nextOverlay => Intl.message(
    'Next overlay',
    name: 'homeStoryEditorNextOverlay',
    desc: 'Tooltip for selecting the next story overlay',
  );

  String get editSelectedText => Intl.message(
    'Edit text',
    name: 'homeStoryEditorEditSelectedText',
    desc: 'Tooltip for editing the selected story text overlay',
  );

  String get moveOverlayUp => Intl.message(
    'Move up',
    name: 'homeStoryEditorMoveOverlayUp',
    desc: 'Tooltip for moving the selected story overlay up',
  );

  String get moveOverlayDown => Intl.message(
    'Move down',
    name: 'homeStoryEditorMoveOverlayDown',
    desc: 'Tooltip for moving the selected story overlay down',
  );

  String get moveOverlayLeft => Intl.message(
    'Move left',
    name: 'homeStoryEditorMoveOverlayLeft',
    desc: 'Tooltip for moving the selected story overlay left',
  );

  String get moveOverlayRight => Intl.message(
    'Move right',
    name: 'homeStoryEditorMoveOverlayRight',
    desc: 'Tooltip for moving the selected story overlay right',
  );

  String get increaseTextSize => Intl.message(
    'Increase text size',
    name: 'homeStoryEditorIncreaseTextSize',
    desc: 'Tooltip for increasing selected story text size',
  );

  String get decreaseTextSize => Intl.message(
    'Decrease text size',
    name: 'homeStoryEditorDecreaseTextSize',
    desc: 'Tooltip for decreasing selected story text size',
  );

  String get rotateTextLeft => Intl.message(
    'Rotate text left',
    name: 'homeStoryEditorRotateTextLeft',
    desc: 'Tooltip for rotating selected story text counter-clockwise',
  );

  String get rotateTextRight => Intl.message(
    'Rotate text right',
    name: 'homeStoryEditorRotateTextRight',
    desc: 'Tooltip for rotating selected story text clockwise',
  );

  String get boldText => Intl.message(
    'Bold text',
    name: 'homeStoryEditorBoldText',
    desc: 'Tooltip for toggling bold on selected story text',
  );

  String get italicText => Intl.message(
    'Italic text',
    name: 'homeStoryEditorItalicText',
    desc: 'Tooltip for toggling italic on selected story text',
  );

  String get textBackgroundColor => Intl.message(
    'Text fill',
    name: 'homeStoryEditorTextBackgroundColor',
    desc: 'Tooltip for changing selected story text background color',
  );

  String get increaseOverlaySize => Intl.message(
    'Increase size',
    name: 'homeStoryEditorIncreaseOverlaySize',
    desc: 'Tooltip for increasing selected story overlay size',
  );

  String get decreaseOverlaySize => Intl.message(
    'Decrease size',
    name: 'homeStoryEditorDecreaseOverlaySize',
    desc: 'Tooltip for decreasing selected story overlay size',
  );

  String get rotateOverlayLeft => Intl.message(
    'Rotate left',
    name: 'homeStoryEditorRotateOverlayLeft',
    desc: 'Tooltip for rotating selected story overlay counter-clockwise',
  );

  String get rotateOverlayRight => Intl.message(
    'Rotate right',
    name: 'homeStoryEditorRotateOverlayRight',
    desc: 'Tooltip for rotating selected story overlay clockwise',
  );

  String get renderError => Intl.message(
    'Story edits could not be applied.',
    name: 'homeStoryEditorRenderError',
    desc: 'Error shown when story editor rendering fails',
  );

  String get cropError => Intl.message(
    'Story crop could not be applied.',
    name: 'homeStoryEditorCropError',
    desc: 'Error shown when story crop rendering fails',
  );

  String get noStickers => Intl.message(
    'No account stickers available.',
    name: 'homeStoryEditorNoStickers',
    desc: 'Message shown when no account/global sticker packs are available',
  );

  String get stickerError => Intl.message(
    'That sticker could not be added.',
    name: 'homeStoryEditorStickerError',
    desc: 'Error shown when a story sticker cannot be resolved',
  );

  String get noMentionContacts => Intl.message(
    'No DM contacts available.',
    name: 'homeStoryEditorNoMentionContacts',
    desc:
        'Message shown when the story editor has no contacts to visually mention',
  );

  @override
  void initState() {
    super.initState();
    _draft = widget.draft;
  }

  StoryOverlay? get _selectedOverlay {
    final selectedId = _selectedOverlayId;
    if (selectedId == null) {
      return null;
    }

    for (final overlay in _draft.overlays) {
      if (overlay.id == selectedId) {
        return overlay;
      }
    }
    return null;
  }

  List<_StoryMentionContact> get _mentionContacts {
    final component = widget.client.getComponent<DirectMessagesComponent>();
    final rooms = component?.directMessageRooms ?? const <Room>[];
    final ownUserId = widget.client.self?.identifier;
    final contacts = <String, _StoryMentionContact>{};
    for (final room in rooms) {
      final userId = component?.getDirectMessagePartnerId(room);
      if (userId == null || userId == ownUserId) {
        continue;
      }
      final member = room.getMemberOrFallback(userId);
      contacts.putIfAbsent(
        userId,
        () => _StoryMentionContact(
          userId: userId,
          displayName: member.displayName,
          avatar: member.avatar,
        ),
      );
    }
    final list = contacts.values.toList(growable: false);
    list.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return list;
  }

  bool get _busy => _saving || _cropping;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: MaterialLocalizations.of(context).closeButtonLabel,
                    color: Colors.white,
                    onPressed: _busy ? null : widget.onCancel,
                    icon: const Icon(Icons.close),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _busy ? null : _finish,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(done),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.errorContainer.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Text(
                      _error!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Center(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final canvasHeight = math.min(
                          constraints.maxHeight,
                          constraints.maxWidth / storyEditorAspectRatio,
                        );
                        final canvasWidth =
                            canvasHeight * storyEditorAspectRatio;
                        final size = Size(canvasWidth, canvasHeight);
                        _canvasSize = size;
                        return SizedBox(
                          width: canvasWidth,
                          height: canvasHeight,
                          child: _buildCanvas(size),
                        );
                      },
                    ),
                  ),
                  if (_filterControlsVisible && !_draft.isTextOnly)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 8,
                      child: _buildFilterControls(context),
                    ),
                ],
              ),
            ),
            _buildToolbar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvas(Size size) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black,
        boxShadow: const [
          BoxShadow(color: Colors.black54, blurRadius: 24, spreadRadius: 2),
        ],
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              key: const ValueKey('story-filter-canvas'),
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _selectedOverlayId = null),
              onHorizontalDragStart: _draft.isTextOnly || _busy
                  ? null
                  : (_) => _canvasHorizontalDragDistance = 0,
              onHorizontalDragUpdate: _draft.isTextOnly || _busy
                  ? null
                  : (details) {
                      _canvasHorizontalDragDistance +=
                          details.primaryDelta ?? 0;
                    },
              onHorizontalDragCancel: _draft.isTextOnly || _busy
                  ? null
                  : () => _canvasHorizontalDragDistance = 0,
              onHorizontalDragEnd: _draft.isTextOnly || _busy
                  ? null
                  : _handleCanvasFilterSwipe,
              child: ColorFiltered(
                colorFilter: ColorFilter.matrix(
                  storyFilterMatrix(
                    _draft.filterPreset,
                    intensity: _draft.filterIntensity,
                  ),
                ),
                child: Image.memory(
                  _draft.baseBytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),
              ),
            ),
          ),
          for (final overlay in _draft.overlays)
            _StoryOverlayWidget(
              overlay: overlay,
              canvasSize: size,
              selected: overlay.id == _selectedOverlayId,
              onTap: () => _handleOverlayTap(overlay),
              onLongPress: () => _removeOverlay(overlay.id),
              onScaleStart: (details) => _startOverlayGesture(overlay, details),
              onScaleUpdate: _updateOverlayGesture,
              onScaleEnd: (_) => _gestureStart = null,
            ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final selected = _selectedOverlay;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_draft.overlays.isNotEmpty) ...[
                _buildOverlaySelectionControls(),
                const SizedBox(height: 4),
              ],
              if (selected is StoryTextOverlay) ...[
                _buildSelectedTextControls(selected),
                const SizedBox(height: 4),
              ] else if (selected is StoryEmojiOverlay) ...[
                _buildSelectedOverlayControls(selected),
                const SizedBox(height: 4),
              ] else if (selected is StoryStickerOverlay) ...[
                _buildSelectedOverlayControls(selected),
                const SizedBox(height: 4),
              ] else if (selected is StoryMentionOverlay) ...[
                _buildSelectedOverlayControls(selected),
                const SizedBox(height: 4),
              ],
              Center(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!_draft.isTextOnly) ...[
                        _ToolbarButton(
                          tooltip: fillCanvas,
                          icon: Icons.fullscreen,
                          selected:
                              _draft.imageFitMode == StoryImageFitMode.cover,
                          onPressed: _busy
                              ? null
                              : () => _setImageFitMode(StoryImageFitMode.cover),
                        ),
                        _ToolbarButton(
                          tooltip: fitWholePhoto,
                          icon: Icons.fit_screen,
                          selected:
                              _draft.imageFitMode == StoryImageFitMode.contain,
                          onPressed: _busy
                              ? null
                              : () =>
                                    _setImageFitMode(StoryImageFitMode.contain),
                        ),
                      ],
                      _ToolbarButton(
                        tooltip: backgroundColor,
                        icon: Icons.palette_outlined,
                        selected:
                            _draft.backgroundMode ==
                                StoryCanvasBackgroundMode.gradient ||
                            _draft.backgroundColor != Colors.black,
                        onPressed: _busy ? null : _pickBackgroundColor,
                      ),
                      const SizedBox(width: 8),
                      if (!_draft.isTextOnly) ...[
                        _ToolbarButton(
                          tooltip: filter,
                          icon: Icons.filter_b_and_w_outlined,
                          selected:
                              storyFilterIsActive(
                                _draft.filterPreset,
                                _draft.filterIntensity,
                              ) ||
                              _filterControlsVisible,
                          onPressed: _busy ? null : _toggleFilterControls,
                        ),
                        _ToolbarButton(
                          tooltip: crop,
                          icon: Icons.crop,
                          onPressed: _busy ? null : _cropPhoto,
                        ),
                      ],
                      _ToolbarButton(
                        tooltip: text,
                        icon: Icons.text_fields,
                        onPressed: _busy ? null : _addTextOverlay,
                      ),
                      _ToolbarButton(
                        tooltip: mention,
                        icon: Icons.alternate_email,
                        onPressed: _busy ? null : _addMentionOverlay,
                      ),
                      _ToolbarButton(
                        tooltip: emoji,
                        icon: Icons.emoji_emotions_outlined,
                        onPressed: _busy ? null : _addEmojiOverlay,
                      ),
                      _ToolbarButton(
                        tooltip: sticker,
                        icon: Icons.sticky_note_2_outlined,
                        onPressed: _busy ? null : _addStickerOverlay,
                      ),
                      if (selected != null) ...[
                        const SizedBox(width: 8),
                        _ToolbarButton(
                          tooltip: delete,
                          icon: Icons.delete_outline,
                          foregroundColor: Theme.of(context).colorScheme.error,
                          onPressed: _busy
                              ? null
                              : () => _removeOverlay(selected.id),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverlaySelectionControls() {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToolbarButton(
            tooltip: previousOverlay,
            icon: Icons.skip_previous,
            onPressed: _busy ? null : () => _selectAdjacentOverlay(-1),
          ),
          _ToolbarButton(
            tooltip: nextOverlay,
            icon: Icons.skip_next,
            onPressed: _busy ? null : () => _selectAdjacentOverlay(1),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterControls(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMobile = MediaQuery.sizeOf(context).width < 620;
    final intensity = _draft.filterIntensity.clamp(0.0, 1.0).toDouble();
    final hasIntensity = _draft.filterPreset != StoryFilterPreset.original;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isMobile ? 360 : 620),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(10, 8, 10, hasIntensity ? 8 : 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      key: const ValueKey('story-filter-previous'),
                      tooltip: previousFilter,
                      color: Colors.white,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _cycleFilterPreset(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        _filterLabel(_draft.filterPreset),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('story-filter-next'),
                      tooltip: nextFilter,
                      color: Colors.white,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _cycleFilterPreset(1),
                      icon: const Icon(Icons.chevron_right),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      color: Colors.white70,
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        setState(() {
                          _filterControlsVisible = false;
                        });
                      },
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                if (!isMobile) ...[
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final preset in storyFilterPresets)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              key: ValueKey('story-filter-${preset.name}'),
                              label: Text(_filterLabel(preset)),
                              selected: preset == _draft.filterPreset,
                              showCheckmark: false,
                              side: BorderSide(
                                color: preset == _draft.filterPreset
                                    ? scheme.primary
                                    : Colors.white24,
                              ),
                              labelStyle: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: preset == _draft.filterPreset
                                        ? scheme.onPrimaryContainer
                                        : Colors.white,
                                  ),
                              selectedColor: scheme.primaryContainer,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.08,
                              ),
                              onSelected: (_) => _selectFilterPreset(preset),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                if (hasIntensity) ...[
                  SizedBox(height: isMobile ? 2 : 8),
                  Row(
                    children: [
                      Text(
                        filterIntensity,
                        style: Theme.of(
                          context,
                        ).textTheme.labelMedium?.copyWith(color: Colors.white),
                      ),
                      const Spacer(),
                      Text(
                        '${(intensity * 100).round()}%',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                  Slider(
                    key: const ValueKey('story-filter-intensity'),
                    value: intensity,
                    min: 0,
                    max: 1,
                    divisions: 20,
                    label: '${(intensity * 100).round()}%',
                    onChanged: _setFilterIntensity,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedTextControls(StoryTextOverlay overlay) {
    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ToolbarButton(
              tooltip: editSelectedText,
              icon: Icons.edit,
              onPressed: _busy ? null : () => _editTextOverlay(overlay),
            ),
            const SizedBox(width: 4),
            _ToolbarButton(
              tooltip: decreaseTextSize,
              icon: Icons.text_decrease,
              onPressed: _busy ? null : () => _changeTextSize(overlay, -12),
            ),
            _ToolbarButton(
              tooltip: increaseTextSize,
              icon: Icons.text_increase,
              onPressed: _busy ? null : () => _changeTextSize(overlay, 12),
            ),
            const SizedBox(width: 4),
            _ToolbarButton(
              tooltip: rotateTextLeft,
              icon: Icons.rotate_90_degrees_ccw,
              onPressed: _busy
                  ? null
                  : () => _rotateText(overlay, -math.pi / 12),
            ),
            _ToolbarButton(
              tooltip: rotateTextRight,
              icon: Icons.rotate_90_degrees_cw,
              onPressed: _busy
                  ? null
                  : () => _rotateText(overlay, math.pi / 12),
            ),
            const SizedBox(width: 4),
            ..._buildSelectedOverlayMoveButtons(overlay),
            const SizedBox(width: 4),
            _ToolbarButton(
              tooltip: boldText,
              icon: Icons.format_bold,
              selected: overlay.isBold,
              onPressed: _busy
                  ? null
                  : () => _replaceTextOverlay(
                      overlay.copyWith(isBold: !overlay.isBold),
                    ),
            ),
            _ToolbarButton(
              tooltip: italicText,
              icon: Icons.format_italic,
              selected: overlay.isItalic,
              onPressed: _busy
                  ? null
                  : () => _replaceTextOverlay(
                      overlay.copyWith(isItalic: !overlay.isItalic),
                    ),
            ),
            _ToolbarButton(
              tooltip: textBackgroundColor,
              icon: Icons.format_color_fill,
              selected: overlay.backgroundColor != null,
              onPressed: _busy ? null : () => _pickTextBackgroundColor(overlay),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedOverlayControls(StoryOverlay overlay) {
    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ToolbarButton(
              tooltip: decreaseOverlaySize,
              icon: Icons.text_decrease,
              onPressed: _busy ? null : () => _changeOverlaySize(overlay, -24),
            ),
            _ToolbarButton(
              tooltip: increaseOverlaySize,
              icon: Icons.text_increase,
              onPressed: _busy ? null : () => _changeOverlaySize(overlay, 24),
            ),
            const SizedBox(width: 4),
            _ToolbarButton(
              tooltip: rotateOverlayLeft,
              icon: Icons.rotate_90_degrees_ccw,
              onPressed: _busy
                  ? null
                  : () => _rotateOverlay(overlay, -math.pi / 12),
            ),
            _ToolbarButton(
              tooltip: rotateOverlayRight,
              icon: Icons.rotate_90_degrees_cw,
              onPressed: _busy
                  ? null
                  : () => _rotateOverlay(overlay, math.pi / 12),
            ),
            const SizedBox(width: 4),
            ..._buildSelectedOverlayMoveButtons(overlay),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSelectedOverlayMoveButtons(StoryOverlay overlay) {
    return [
      _ToolbarButton(
        tooltip: moveOverlayLeft,
        icon: Icons.keyboard_arrow_left,
        onPressed: _busy
            ? null
            : () => _moveOverlay(
                overlay,
                const Offset(-storyOverlayKeyboardMoveStep, 0),
              ),
      ),
      _ToolbarButton(
        tooltip: moveOverlayUp,
        icon: Icons.keyboard_arrow_up,
        onPressed: _busy
            ? null
            : () => _moveOverlay(
                overlay,
                const Offset(0, -storyOverlayKeyboardMoveStep),
              ),
      ),
      _ToolbarButton(
        tooltip: moveOverlayDown,
        icon: Icons.keyboard_arrow_down,
        onPressed: _busy
            ? null
            : () => _moveOverlay(
                overlay,
                const Offset(0, storyOverlayKeyboardMoveStep),
              ),
      ),
      _ToolbarButton(
        tooltip: moveOverlayRight,
        icon: Icons.keyboard_arrow_right,
        onPressed: _busy
            ? null
            : () => _moveOverlay(
                overlay,
                const Offset(storyOverlayKeyboardMoveStep, 0),
              ),
      ),
    ];
  }

  void _changeTextSize(StoryTextOverlay overlay, double delta) {
    _replaceTextOverlay(
      overlay.copyWith(
        fontSize: _clampDouble(overlay.fontSize + delta, 42, 180),
      ),
    );
  }

  void _rotateText(StoryTextOverlay overlay, double deltaRadians) {
    _replaceTextOverlay(
      overlay.copyWith(rotationRadians: overlay.rotationRadians + deltaRadians),
    );
  }

  void _replaceTextOverlay(StoryTextOverlay overlay) {
    setState(() {
      _draft = _draft.replaceOverlay(overlay);
      _selectedOverlayId = overlay.id;
      _error = null;
    });
  }

  void _changeOverlaySize(StoryOverlay overlay, double delta) {
    switch (overlay) {
      case StoryEmojiOverlay():
        _replaceOverlay(
          overlay.copyWith(
            fontSize: _clampDouble(overlay.fontSize + delta, 72, 260),
          ),
        );
      case StoryStickerOverlay():
        _replaceOverlay(
          overlay.copyWith(
            size: _clampDouble(overlay.size + delta * 2, 96, 720),
          ),
        );
      case StoryMentionOverlay():
        _replaceOverlay(
          overlay.copyWith(
            fontSize: _clampDouble(overlay.fontSize + delta, 34, 108),
          ),
        );
      case StoryTextOverlay():
        _changeTextSize(overlay, delta);
    }
  }

  void _rotateOverlay(StoryOverlay overlay, double deltaRadians) {
    _replaceOverlay(
      overlay.copyWithTransform(
        rotationRadians: overlay.rotationRadians + deltaRadians,
      ),
    );
  }

  void _replaceOverlay(StoryOverlay overlay) {
    setState(() {
      _draft = _draft.replaceOverlay(overlay);
      _selectedOverlayId = overlay.id;
      _error = null;
    });
  }

  void _moveOverlay(StoryOverlay overlay, Offset delta) {
    _replaceOverlay(
      overlay.copyWithTransform(
        center: storyOverlayMovedCenter(center: overlay.center, delta: delta),
      ),
    );
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

  Future<void> _finish() async {
    final draft = _draft;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final previewBytes = await _renderer.renderPreviewBytes(draft);
      if (!mounted) {
        return;
      }
      widget.onDone(draft.copyWith(previewBytes: previewBytes));
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = renderError;
      });
    }
  }

  Future<void> _cropPhoto() async {
    if (_draft.isTextOnly) {
      return;
    }
    setState(() {
      _cropping = true;
      _error = null;
    });
    try {
      final cropped = await _showCropDialog(_draft.sourceBytes);
      if (!mounted || cropped == null) {
        return;
      }
      final baseBytes = await StoryImageRenderer.normalizeToStoryCanvasAsync(
        cropped,
        imageFitMode: _draft.imageFitMode,
        backgroundColor: _draft.backgroundColor,
        backgroundGradientColor: _draft.backgroundGradientColor,
        backgroundMode: _draft.backgroundMode,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _draft = _draft.copyWith(
          sourceBytes: cropped,
          baseBytes: baseBytes,
          previewBytes: baseBytes,
        );
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = cropError;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _cropping = false;
        });
      }
    }
  }

  Future<void> _setImageFitMode(StoryImageFitMode imageFitMode) async {
    if (_draft.isTextOnly) {
      return;
    }
    if (_draft.imageFitMode == imageFitMode) {
      return;
    }
    setState(() {
      _cropping = true;
      _error = null;
    });
    try {
      final baseBytes = await StoryImageRenderer.normalizeToStoryCanvasAsync(
        _draft.sourceBytes,
        imageFitMode: imageFitMode,
        backgroundColor: _draft.backgroundColor,
        backgroundGradientColor: _draft.backgroundGradientColor,
        backgroundMode: _draft.backgroundMode,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _draft = _draft.copyWith(
          baseBytes: baseBytes,
          previewBytes: baseBytes,
          imageFitMode: imageFitMode,
        );
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = cropError;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _cropping = false;
        });
      }
    }
  }

  Future<void> _pickBackgroundColor() async {
    final choice = await showModalBottomSheet<_StoryBackgroundChoice>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      showDragHandle: true,
      builder: (context) => _StoryBackgroundSheet(
        selectedColor: _draft.backgroundColor,
        selectedGradientColor: _draft.backgroundGradientColor,
        selectedMode: _draft.backgroundMode,
      ),
    );
    if (!mounted || choice == null) {
      return;
    }
    await _setBackground(choice);
  }

  void _toggleFilterControls() {
    if (_draft.isTextOnly) {
      return;
    }

    setState(() {
      _filterControlsVisible = !_filterControlsVisible;
      _selectedOverlayId = null;
      _error = null;
    });
  }

  void _selectFilterPreset(StoryFilterPreset preset) {
    if (_draft.isTextOnly) {
      return;
    }

    final nextIntensity = preset == StoryFilterPreset.original
        ? 1.0
        : (_draft.filterPreset == StoryFilterPreset.original
              ? 1.0
              : _draft.filterIntensity.clamp(0.0, 1.0).toDouble());
    setState(() {
      _draft = _draft.copyWith(
        filterPreset: preset,
        filterIntensity: nextIntensity,
      );
      _error = null;
    });
  }

  void _setFilterIntensity(double intensity) {
    if (_draft.isTextOnly ||
        _draft.filterPreset == StoryFilterPreset.original) {
      return;
    }

    setState(() {
      _draft = _draft.copyWith(
        filterIntensity: intensity.clamp(0.0, 1.0).toDouble(),
      );
      _error = null;
    });
  }

  void _cycleFilterPreset(int delta) {
    if (_draft.isTextOnly || storyFilterPresets.isEmpty) {
      return;
    }

    final currentIndex = storyFilterPresets.indexOf(_draft.filterPreset);
    final normalizedIndex = currentIndex < 0 ? 0 : currentIndex;
    final nextIndex = (normalizedIndex + delta) % storyFilterPresets.length;
    _selectFilterPreset(
      storyFilterPresets[nextIndex < 0
          ? nextIndex + storyFilterPresets.length
          : nextIndex],
    );
  }

  void _handleCanvasFilterSwipe(DragEndDetails details) {
    final isMobile = MediaQuery.sizeOf(context).width < 620;
    if (!isMobile || _draft.isTextOnly) {
      _canvasHorizontalDragDistance = 0;
      return;
    }

    final distance = _canvasHorizontalDragDistance;
    final velocity = details.primaryVelocity ?? 0;
    _canvasHorizontalDragDistance = 0;
    if (distance.abs() < 48 && velocity.abs() < 260) {
      return;
    }

    final direction = velocity.abs() >= 260
        ? (velocity < 0 ? 1 : -1)
        : (distance < 0 ? 1 : -1);
    _cycleFilterPreset(direction);
  }

  String _filterLabel(StoryFilterPreset preset) {
    return switch (preset) {
      StoryFilterPreset.original => Intl.message(
        'Original',
        name: 'homeStoryEditorFilterOriginal',
        desc: 'Label for the original story photo filter',
      ),
      StoryFilterPreset.mono => Intl.message(
        'Mono',
        name: 'homeStoryEditorFilterMono',
        desc: 'Label for the monochrome story photo filter',
      ),
      StoryFilterPreset.sepia => Intl.message(
        'Sepia',
        name: 'homeStoryEditorFilterSepia',
        desc: 'Label for the sepia story photo filter',
      ),
      StoryFilterPreset.warm => Intl.message(
        'Warm',
        name: 'homeStoryEditorFilterWarm',
        desc: 'Label for the warm story photo filter',
      ),
      StoryFilterPreset.cool => Intl.message(
        'Cool',
        name: 'homeStoryEditorFilterCool',
        desc: 'Label for the cool story photo filter',
      ),
      StoryFilterPreset.fade => Intl.message(
        'Fade',
        name: 'homeStoryEditorFilterFade',
        desc: 'Label for the faded story photo filter',
      ),
      StoryFilterPreset.contrast => Intl.message(
        'Contrast',
        name: 'homeStoryEditorFilterContrast',
        desc: 'Label for the contrast story photo filter',
      ),
    };
  }

  Future<void> _setBackground(_StoryBackgroundChoice choice) async {
    if (_draft.backgroundMode == choice.mode &&
        _draft.backgroundColor == choice.color &&
        _draft.backgroundGradientColor == choice.gradientColor) {
      return;
    }
    setState(() {
      _cropping = true;
      _error = null;
    });
    try {
      final baseBytes = _draft.isTextOnly
          ? await StoryImageRenderer.blankStoryCanvasAsync(
              backgroundColor: choice.color,
              backgroundGradientColor: choice.gradientColor,
              backgroundMode: choice.mode,
            )
          : await StoryImageRenderer.normalizeToStoryCanvasAsync(
              _draft.sourceBytes,
              imageFitMode: _draft.imageFitMode,
              backgroundColor: choice.color,
              backgroundGradientColor: choice.gradientColor,
              backgroundMode: choice.mode,
            );
      if (!mounted) {
        return;
      }
      setState(() {
        _draft = _draft.copyWith(
          baseBytes: baseBytes,
          previewBytes: baseBytes,
          backgroundColor: choice.color,
          backgroundGradientColor: choice.gradientColor,
          backgroundMode: choice.mode,
        );
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = cropError;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _cropping = false;
        });
      }
    }
  }

  Future<void> _pickTextBackgroundColor(StoryTextOverlay overlay) async {
    final choice = await _showColorSheet(
      selectedColor: overlay.backgroundColor,
      includeNone: true,
    );
    if (!mounted || choice == null) {
      return;
    }
    _replaceTextOverlay(overlay.copyWith(backgroundColor: choice.color));
  }

  Future<_StoryColorChoice?> _showColorSheet({
    required Color? selectedColor,
    bool includeNone = false,
  }) {
    return showModalBottomSheet<_StoryColorChoice>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      showDragHandle: true,
      builder: (context) => _StoryColorSheet(
        selectedColor: selectedColor,
        includeNone: includeNone,
      ),
    );
  }

  Future<Uint8List?> _showCropDialog(Uint8List imageBytes) async {
    final controller = CropController(
      aspectRatio: storyEditorAspectRatio,
      defaultCrop: const Rect.fromLTRB(0.08, 0.08, 0.92, 0.92),
    );
    final image = await ImageUtils.imageProviderToImage(
      MemoryImage(imageBytes),
    );
    final ratio = image.width.toDouble() / image.height.toDouble();

    if (!mounted) {
      return null;
    }

    return tiamat.PopupDialog.show<Uint8List>(
      context,
      content: ImageCropView(
        imageBytes,
        controller,
        ratio,
        onImageSubmitted: (data) => Navigator.of(context).pop(data),
      ),
    );
  }

  Future<void> _addTextOverlay() async {
    final edit = await _showTextDialog();
    if (!mounted || edit == null || edit.text.trim().isEmpty) {
      return;
    }
    final overlay = StoryTextOverlay(
      id: createStoryDraftId(),
      center: const Offset(0.5, 0.48),
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

  Future<void> _editTextOverlay(StoryTextOverlay overlay) async {
    final edit = await _showTextDialog(
      initialText: overlay.text,
      initialColor: overlay.color,
      initialBold: overlay.isBold,
      initialItalic: overlay.isItalic,
    );
    if (!mounted || edit == null || edit.text.trim().isEmpty) {
      return;
    }
    setState(() {
      _draft = _draft.replaceOverlay(
        overlay.copyWith(
          text: edit.text.trim(),
          color: edit.color,
          isBold: edit.isBold,
          isItalic: edit.isItalic,
        ),
      );
      _error = null;
    });
  }

  Future<_StoryTextEdit?> _showTextDialog({
    String initialText = '',
    Color initialColor = Colors.white,
    bool initialBold = true,
    bool initialItalic = false,
  }) {
    return showDialog<_StoryTextEdit>(
      context: context,
      builder: (context) => _StoryTextDialog(
        initialText: initialText,
        initialColor: initialColor,
        initialBold: initialBold,
        initialItalic: initialItalic,
      ),
    );
  }

  Future<void> _addMentionOverlay() async {
    final contacts = _mentionContacts;
    if (contacts.isEmpty) {
      setState(() => _error = noMentionContacts);
      return;
    }

    final contact = await showModalBottomSheet<_StoryMentionContact>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      showDragHandle: true,
      builder: (context) => _StoryMentionPickerSheet(
        contacts: contacts,
        emptyLabel: noMentionContacts,
      ),
    );
    if (!mounted || contact == null) {
      return;
    }

    final overlay = StoryMentionOverlay(
      id: createStoryDraftId(),
      center: const Offset(0.5, 0.58),
      userId: contact.userId,
      displayName: contact.displayName,
    );
    setState(() {
      _draft = _draft.addOverlay(overlay);
      _selectedOverlayId = overlay.id;
      _error = null;
    });
  }

  Future<void> _addEmojiOverlay() async {
    final emoji = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      showDragHandle: true,
      builder: (context) => const _StoryEmojiSheet(),
    );
    if (!mounted || emoji == null) {
      return;
    }
    final overlay = StoryEmojiOverlay(
      id: createStoryDraftId(),
      center: const Offset(0.5, 0.52),
      emoji: emoji,
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
      setState(() => _error = noStickers);
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
          size: 82,
          packButtonSize: 44,
          showSearchBar: false,
          mobileStyle: MediaQuery.sizeOf(context).width < 620,
          onEmoticonPressed: (sticker) => Navigator.of(context).pop(sticker),
        ),
      ),
    );
    if (!mounted || emoticon == null) {
      return;
    }

    final image = emoticon.image;
    if (image == null) {
      setState(() => _error = stickerError);
      return;
    }

    final overlay = StoryStickerOverlay(
      id: createStoryDraftId(),
      center: const Offset(0.5, 0.55),
      label: emoticon.shortcode ?? emoticon.slug,
      image: image,
    );
    setState(() {
      _draft = _draft.addOverlay(overlay);
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
    if (_selectedOverlayId == overlay.id && overlay is StoryTextOverlay) {
      _editTextOverlay(overlay);
      return;
    }
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
      _error = null;
    });
  }

  void _startOverlayGesture(StoryOverlay overlay, ScaleStartDetails details) {
    setState(() {
      _selectedOverlayId = overlay.id;
    });
    _gestureStart = _OverlayGestureStart(
      overlayId: overlay.id,
      center: overlay.center,
      scale: overlay.scale,
      rotationRadians: overlay.rotationRadians,
      focalPoint: details.focalPoint,
    );
  }

  void _updateOverlayGesture(ScaleUpdateDetails details) {
    final start = _gestureStart;
    if (start == null || _canvasSize == Size.zero) {
      return;
    }

    final delta = details.focalPoint - start.focalPoint;
    final center = Offset(
      _clampDouble(start.center.dx + delta.dx / _canvasSize.width, 0.04, 0.96),
      _clampDouble(start.center.dy + delta.dy / _canvasSize.height, 0.04, 0.96),
    );
    final scale = _clampDouble(start.scale * details.scale, 0.35, 4);
    final rotation = start.rotationRadians + details.rotation;

    final overlay = _draft.overlays
        .where((overlay) => overlay.id == start.overlayId)
        .firstOrNull;
    if (overlay == null) {
      return;
    }

    setState(() {
      _draft = _draft.replaceOverlay(
        overlay.copyWithTransform(
          center: center,
          scale: scale,
          rotationRadians: rotation,
        ),
      );
    });
  }
}

double _clampDouble(double value, double min, double max) {
  return value.clamp(min, max).toDouble();
}

class _OverlayGestureStart {
  const _OverlayGestureStart({
    required this.overlayId,
    required this.center,
    required this.scale,
    required this.rotationRadians,
    required this.focalPoint,
  });

  final String overlayId;
  final Offset center;
  final double scale;
  final double rotationRadians;
  final Offset focalPoint;
}

class _StoryMentionContact {
  const _StoryMentionContact({
    required this.userId,
    required this.displayName,
    required this.avatar,
  });

  final String userId;
  final String displayName;
  final ImageProvider? avatar;
}

class _StoryMentionPickerSheet extends StatelessWidget {
  const _StoryMentionPickerSheet({
    required this.contacts,
    required this.emptyLabel,
  });

  final List<_StoryMentionContact> contacts;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final height = math.min(MediaQuery.sizeOf(context).height * 0.72, 520.0);
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: height,
        child: contacts.isEmpty
            ? Center(
                child: Text(
                  emptyLabel,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                itemCount: contacts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 2),
                itemBuilder: (context, index) {
                  final contact = contacts[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: contact.avatar,
                      child: contact.avatar == null
                          ? Text(
                              contact.displayName.characters
                                  .take(1)
                                  .toString()
                                  .toUpperCase(),
                            )
                          : null,
                    ),
                    title: Text(contact.displayName),
                    subtitle: Text(contact.userId),
                    trailing: const Icon(Icons.alternate_email),
                    onTap: () => Navigator.of(context).pop(contact),
                  );
                },
              ),
      ),
    );
  }
}

class _StoryOverlayWidget extends StatelessWidget {
  const _StoryOverlayWidget({
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
        final textStyle = TextStyle(
          color: textOverlay.color,
          fontSize: fontSize,
          fontWeight: textOverlay.isBold ? FontWeight.w700 : FontWeight.w400,
          fontStyle: textOverlay.isItalic ? FontStyle.italic : FontStyle.normal,
          shadows: const [
            Shadow(color: Colors.black87, blurRadius: 10, offset: Offset(0, 2)),
          ],
        );
        final textChild = Text.rich(
          TextSpan(
            children: TextUtils.nativeEmojiTextSpans(
              textOverlay.text,
              style: textStyle,
            ),
          ),
          textAlign: TextAlign.center,
          maxLines: 4,
          overflow: TextOverflow.visible,
        );
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
              child: textChild,
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
                shadows: const [
                  Shadow(
                    color: Colors.black87,
                    blurRadius: 10,
                    offset: Offset(0, 2),
                  ),
                ],
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
        final mentionOverlay = overlay as StoryMentionOverlay;
        final fontSize =
            mentionOverlay.fontSize * outputScale * mentionOverlay.scale;
        width = math.min(
          canvasSize.width * 0.82,
          math.max(112.0, mentionOverlay.label.length * fontSize * 0.64 + 44),
        );
        height = math.max(42.0, fontSize * 1.7);
        child = Center(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: mentionOverlay.backgroundColor,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 18 * outputScale * mentionOverlay.scale,
                vertical: 8 * outputScale * mentionOverlay.scale,
              ),
              child: Text.rich(
                TextSpan(
                  children: TextUtils.nativeEmojiTextSpans(
                    mentionOverlay.label,
                    style: TextStyle(
                      color: mentionOverlay.foregroundColor,
                      fontSize: fontSize,
                      fontWeight: FontWeight.w800,
                      shadows: const [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        );
    }

    final left = overlay.center.dx * canvasSize.width - width / 2;
    final top = overlay.center.dy * canvasSize.height - height / 2;

    return Positioned(
      left: left,
      top: top,
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
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 8),
                    ],
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
        backgroundColor: selected ? Colors.white.withValues(alpha: 0.16) : null,
      ),
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}

class _StoryTextDialog extends StatefulWidget {
  const _StoryTextDialog({
    required this.initialText,
    required this.initialColor,
    required this.initialBold,
    required this.initialItalic,
  });

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

  String get title => Intl.message(
    'Story Text',
    name: 'homeStoryEditorTextDialogTitle',
    desc: 'Title for editing story text',
  );

  String get add => Intl.message(
    'Add',
    name: 'homeStoryEditorTextDialogAdd',
    desc: 'Button text for adding story text',
  );

  String get cancel => Intl.message(
    'Cancel',
    name: 'homeStoryEditorTextDialogCancel',
    desc: 'Button text for canceling story text editing',
  );

  String get bold => Intl.message(
    'Bold',
    name: 'homeStoryEditorTextDialogBold',
    desc: 'Tooltip for the story text bold button',
  );

  String get italic => Intl.message(
    'Italic',
    name: 'homeStoryEditorTextDialogItalic',
    desc: 'Tooltip for the story text italic button',
  );

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
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final color in _textColors)
                _ColorButton(
                  color: color,
                  selected: color == _color,
                  onTap: () => setState(() => _color = color),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                tooltip: bold,
                isSelected: _isBold,
                onPressed: () => setState(() => _isBold = !_isBold),
                icon: const Icon(Icons.format_bold),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: italic,
                isSelected: _isItalic,
                onPressed: () => setState(() => _isItalic = !_isItalic),
                icon: const Icon(Icons.format_italic),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(_StoryTextEdit(_controller.text, _color, _isBold, _isItalic)),
          child: Text(add),
        ),
      ],
    );
  }
}

class _ColorButton extends StatelessWidget {
  const _ColorButton({
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
      radius: 20,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
            width: selected ? 3 : 1,
          ),
        ),
        child: const SizedBox(width: 28, height: 28),
      ),
    );
  }
}

class _StoryBackgroundChoice {
  const _StoryBackgroundChoice({
    required this.mode,
    required this.color,
    required this.gradientColor,
  });

  final StoryCanvasBackgroundMode mode;
  final Color color;
  final Color gradientColor;
}

class _StoryBackgroundSheet extends StatelessWidget {
  const _StoryBackgroundSheet({
    required this.selectedColor,
    required this.selectedGradientColor,
    required this.selectedMode,
  });

  final Color selectedColor;
  final Color selectedGradientColor;
  final StoryCanvasBackgroundMode selectedMode;

  String get solidColors => Intl.message(
    'Solid',
    name: 'homeStoryEditorSolidBackgrounds',
    desc: 'Label for solid story background color choices',
  );

  String get gradients => Intl.message(
    'Gradient',
    name: 'homeStoryEditorGradientBackgrounds',
    desc: 'Label for gradient story background choices',
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
            Text(solidColors, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final (index, color)
                    in storyEditorBackgroundColors.indexed)
                  _ColorButton(
                    key: ValueKey('story-background-color-$index'),
                    color: color,
                    selected:
                        selectedMode == StoryCanvasBackgroundMode.solid &&
                        color == selectedColor,
                    onTap: () => Navigator.of(context).pop(
                      _StoryBackgroundChoice(
                        mode: StoryCanvasBackgroundMode.solid,
                        color: color,
                        gradientColor: selectedGradientColor,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            Text(gradients, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final (index, preset)
                    in storyEditorBackgroundGradientPresets.indexed)
                  _GradientButton(
                    key: ValueKey('story-gradient-$index'),
                    startColor: preset.startColor,
                    endColor: preset.endColor,
                    selected:
                        selectedMode == StoryCanvasBackgroundMode.gradient &&
                        selectedColor == preset.startColor &&
                        selectedGradientColor == preset.endColor,
                    onTap: () => Navigator.of(context).pop(
                      _StoryBackgroundChoice(
                        mode: StoryCanvasBackgroundMode.gradient,
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

class _GradientButton extends StatelessWidget {
  const _GradientButton({
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
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [startColor, endColor],
          ),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
            width: selected ? 3 : 1,
          ),
        ),
        child: const SizedBox(width: 32, height: 32),
      ),
    );
  }
}

class _StoryColorSheet extends StatelessWidget {
  const _StoryColorSheet({
    required this.selectedColor,
    required this.includeNone,
  });

  final Color? selectedColor;
  final bool includeNone;

  String get noFill => Intl.message(
    'No fill',
    name: 'homeStoryEditorNoTextFill',
    desc: 'Tooltip for removing selected story text background fill',
  );

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
        child: Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            if (includeNone)
              IconButton.filledTonal(
                key: const ValueKey('story-color-none'),
                tooltip: noFill,
                isSelected: selectedColor == null,
                onPressed: () =>
                    Navigator.of(context).pop(const _StoryColorChoice(null)),
                icon: const Icon(Icons.format_color_reset),
              ),
            for (final (index, color) in storyEditorBackgroundColors.indexed)
              _ColorButton(
                key: ValueKey('story-color-$index'),
                color: color,
                selected: color == selectedColor,
                onTap: () =>
                    Navigator.of(context).pop(_StoryColorChoice(color)),
              ),
          ],
        ),
      ),
    );
  }
}

class _StoryColorChoice {
  const _StoryColorChoice(this.color);

  final Color? color;
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
    '\u{1F62D}',
    '\u{1F525}',
    '\u{2728}',
    '\u{1F44D}',
    '\u{1F631}',
    '\u{1F929}',
    '\u{1F389}',
    '\u{1F49A}',
    '\u{1F680}',
    '\u{1F31F}',
  ];

  String get moreEmoji => Intl.message(
    'More emoji',
    name: 'homeStoryEditorMoreEmoji',
    desc: 'Tooltip for opening the full story emoji picker',
  );

  Future<void> _openFullEmojiPicker(BuildContext context) async {
    final unicodePacks = UnicodeEmojis.packs ?? await UnicodeEmojis.load();
    final packs = List<EmoticonPack>.from(unicodePacks);
    if (!context.mounted) {
      return;
    }
    final selected = await showModalBottomSheet<Emoticon>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      showDragHandle: true,
      builder: (context) => SizedBox(
        height: math.min(MediaQuery.sizeOf(context).height * 0.72, 520.0),
        child: EmojiPicker(
          packs,
          onlyEmoji: true,
          size: 44,
          packButtonSize: 44,
          showSearchBar: false,
          mobileStyle: MediaQuery.sizeOf(context).width < 620,
          onEmoticonPressed: (emoji) => Navigator.of(context).pop(emoji),
        ),
      ),
    );
    if (selected == null || !context.mounted) {
      return;
    }
    Navigator.of(context).pop(selected.slug);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: 260,
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 72,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemCount: choices.length + 1,
          itemBuilder: (context, index) {
            if (index == choices.length) {
              return IconButton(
                tooltip: moreEmoji,
                onPressed: () => _openFullEmojiPicker(context),
                icon: const Icon(Icons.add),
              );
            }
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

const List<Color> _textColors = [
  Colors.white,
  Colors.black,
  Color(0xFFFFD54F),
  Color(0xFFFF6B6B),
  Color(0xFF4DD0E1),
  Color(0xFF81C784),
  Color(0xFFCE93D8),
];
