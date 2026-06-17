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
import 'package:intergalactic/ui/molecules/emoji_picker.dart';
import 'package:intergalactic/ui/molecules/video_player/video_player.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_draft.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_video_tools.dart';
import 'package:intergalactic/ui/organisms/home_screen/story_video_trim_exporter.dart';
import 'package:intergalactic/utils/mime.dart';
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
        pageBuilder: (context, _, __) => _HomeStoryVideoEditorPage(
          client: client,
          draft: draft,
        ),
        transitionsBuilder: (context, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }
}

@visibleForTesting
bool homeStoryVideoEditorShouldExportBeforeUpload({
  required bool usesFullSource,
  required Duration duration,
  required int sizeBytes,
}) {
  return !usesFullSource ||
      duration > storyMaxVideoDuration ||
      !storyVideoSizeIsAllowed(sizeBytes);
}

class _HomeStoryVideoEditorPage extends StatefulWidget {
  const _HomeStoryVideoEditorPage({
    required this.client,
    required this.draft,
  });

  final Client client;
  final StoryVideoDraft draft;

  @override
  State<_HomeStoryVideoEditorPage> createState() =>
      _HomeStoryVideoEditorPageState();
}

class _HomeStoryVideoEditorPageState extends State<_HomeStoryVideoEditorPage> {
  final StoryVideoProbe _videoProbe = const StoryVideoProbe();
  final StoryVideoTrimExporter _trimExporter = const StoryVideoTrimExporter();
  late StoryVideoDraft _draft = widget.draft;
  String? _selectedOverlayId;
  _OverlayGestureStart? _gestureStart;
  String? _error;
  bool _exporting = false;

  String get done => Intl.message(
        'Done',
        name: 'homeStoryVideoEditorDone',
        desc: 'Button text for applying story video editor changes',
      );

  String get text => Intl.message(
        'Text',
        name: 'homeStoryVideoEditorText',
        desc: 'Tooltip for adding text to a story video',
      );

  String get emoji => Intl.message(
        'Emoji',
        name: 'homeStoryVideoEditorEmoji',
        desc: 'Tooltip for adding emoji to a story video',
      );

  String get sticker => Intl.message(
        'Sticker',
        name: 'homeStoryVideoEditorSticker',
        desc: 'Tooltip for adding a sticker to a story video',
      );

  String get delete => Intl.message(
        'Delete',
        name: 'homeStoryVideoEditorDelete',
        desc: 'Tooltip for deleting a selected story video overlay',
      );

  String get trimUnavailable => Intl.message(
        'Video trim export is not available on this device yet. Choose a video 30 seconds or shorter, or reset to the full clip before posting.',
        name: 'homeStoryVideoEditorTrimUnavailable',
        desc:
            'Validation shown when a story video selection requires trimming export',
      );

  String get trimExportFailed => Intl.message(
        'That video segment could not be prepared. Try a different range or a shorter video.',
        name: 'homeStoryVideoEditorTrimExportFailed',
        desc: 'Error shown when a story video trim export fails',
      );

  String get exportingVideo => Intl.message(
        'Preparing video...',
        name: 'homeStoryVideoEditorExportingVideo',
        desc: 'Status shown while a story video trim is being exported',
      );

  String get invalidRange => Intl.message(
        'Story videos must be 30 seconds or shorter.',
        name: 'homeStoryVideoEditorInvalidRange',
        desc: 'Validation shown when a story video trim range is too long',
      );

  String get resetTrim => Intl.message(
        'Reset',
        name: 'homeStoryVideoEditorResetTrim',
        desc: 'Button text for resetting story video trim to the full source',
      );

  String get backgroundColor => Intl.message(
        'Background',
        name: 'homeStoryVideoEditorBackgroundColor',
        desc: 'Tooltip for changing the story video background color',
      );

  String get dragTrimRegion => Intl.message(
        'Drag selected range',
        name: 'homeStoryVideoEditorDragTrimRegion',
        desc: 'Accessibility label for dragging the selected video trim range',
      );

  String get noStickers => Intl.message(
        'No account stickers available.',
        name: 'homeStoryVideoEditorNoStickers',
        desc:
            'Message shown when no account/global sticker packs are available',
      );

  String get stickerError => Intl.message(
        'That sticker could not be added.',
        name: 'homeStoryVideoEditorStickerError',
        desc: 'Error shown when a story video sticker cannot be resolved',
      );

  String get textDialogTitle => Intl.message(
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

  bool get _canFinish => !_exporting && _draft.toUpload().hasValidSelection;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final validation = _validationMessage;
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
                    tooltip:
                        MaterialLocalizations.of(context).closeButtonTooltip,
                    color: Colors.white,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _canFinish ? _finish : null,
                    child: Text(done),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final canvasHeight = math.min(
                      constraints.maxHeight,
                      constraints.maxWidth / storyEditorAspectRatio,
                    );
                    final canvasWidth = canvasHeight * storyEditorAspectRatio;
                    return SizedBox(
                      width: canvasWidth,
                      height: canvasHeight,
                      child: _buildCanvas(Size(canvasWidth, canvasHeight)),
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
            if (_exporting)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          exportingVideo,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            _buildTrimControls(context),
            _buildToolbar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvas(Size size) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _draft.backgroundColor,
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: ClipRect(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _selectedOverlayId = null),
                child: VideoPlayer(
                  SystemFileProvider(_draft.path),
                  thumbnail: _draft.thumbnailBytes == null
                      ? null
                      : MemoryImage(_draft.thumbnailBytes!),
                  fileName: _draft.sourceName,
                  doThumbnail: _draft.thumbnailBytes != null,
                  decodeFirstFrame: true,
                  showProgressBar: true,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            for (final overlay in _draft.overlays)
              _StoryVideoOverlayWidget(
                overlay: overlay,
                canvasSize: size,
                selected: overlay.id == _selectedOverlayId,
                onTap: _exporting ? () {} : () => _handleOverlayTap(overlay),
                onLongPress:
                    _exporting ? () {} : () => _removeOverlay(overlay.id),
                onScaleStart: _exporting
                    ? (_) {}
                    : (details) => _startOverlayGesture(overlay, details, size),
                onScaleUpdate: _exporting ? (_) {} : _updateOverlayGesture,
                onScaleEnd: (_) => _gestureStart = null,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrimControls(BuildContext context) {
    final durationMs = math.max(1, _draft.duration.inMilliseconds).toDouble();
    final start =
        _draft.trimStart.inMilliseconds.clamp(0, durationMs - 1).toDouble();
    final end =
        _draft.trimEnd.inMilliseconds.clamp(start + 1, durationMs).toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    storyVideoDurationLabel(_draft.selectedDuration),
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _exporting || _draft.usesFullSource
                        ? null
                        : () {
                            setState(() {
                              _draft = _draft.copyWith(
                                trimStart: Duration.zero,
                                trimEnd: _draft.duration,
                              );
                              _error = null;
                            });
                          },
                    icon: const Icon(Icons.restore, size: 18),
                    label: Text(resetTrim),
                  ),
                ],
              ),
              RangeSlider(
                min: 0,
                max: durationMs,
                values: RangeValues(start, end),
                divisions: math.max(1, _draft.duration.inSeconds * 2),
                labels: RangeLabels(
                  storyVideoDurationLabel(_draft.trimStart),
                  storyVideoDurationLabel(_draft.trimEnd),
                ),
                onChanged: _exporting
                    ? null
                    : (values) {
                        final startMs = values.start.round();
                        var endMs = values.end.round();
                        final maxEndMs =
                            startMs + storyMaxVideoDuration.inMilliseconds;
                        if (endMs > maxEndMs) {
                          endMs = maxEndMs;
                        }
                        setState(() {
                          _draft = _draft.copyWith(
                            trimStart: Duration(milliseconds: startMs),
                            trimEnd: Duration(milliseconds: endMs),
                          );
                          _error = null;
                        });
                      },
              ),
              const SizedBox(height: 2),
              _buildTrimRegionDragTrack(context, durationMs),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    storyVideoDurationLabel(_draft.trimStart),
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: Colors.white70),
                  ),
                  const Spacer(),
                  Text(
                    storyVideoDurationLabel(_draft.trimEnd),
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrimRegionDragTrack(BuildContext context, double durationMs) {
    final scheme = Theme.of(context).colorScheme;
    final startFraction = (_draft.trimStart.inMilliseconds / durationMs)
        .clamp(0.0, 1.0)
        .toDouble();
    final endFraction =
        (_draft.trimEnd.inMilliseconds / durationMs).clamp(0.0, 1.0).toDouble();
    final selectedFraction =
        (endFraction - startFraction).clamp(0.0, 1.0).toDouble();
    final canDrag = !_exporting &&
        _draft.selectedDuration > Duration.zero &&
        _draft.selectedDuration < _draft.duration;

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        if (trackWidth <= 0) {
          return const SizedBox.shrink();
        }

        final left =
            (trackWidth * startFraction).clamp(0.0, trackWidth).toDouble();
        final maxWidth = math.max(0.0, trackWidth - left);
        final selectedWidth = (trackWidth * selectedFraction)
            .clamp(math.min(28.0, maxWidth), maxWidth)
            .toDouble();

        return SizedBox(
          height: 32,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              Positioned.fill(
                top: 11,
                bottom: 11,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Positioned(
                left: left,
                width: selectedWidth,
                height: 32,
                child: Semantics(
                  label: dragTrimRegion,
                  enabled: canDrag,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: canDrag
                        ? (details) {
                            final deltaX = details.primaryDelta ?? 0;
                            if (deltaX == 0) {
                              return;
                            }
                            final deltaMs = (deltaX /
                                    trackWidth *
                                    _draft.duration.inMilliseconds)
                                .round();
                            if (deltaMs == 0) {
                              return;
                            }
                            final shifted = storyVideoShiftTrimRange(
                              sourceDuration: _draft.duration,
                              trimStart: _draft.trimStart,
                              trimEnd: _draft.trimEnd,
                              delta: Duration(milliseconds: deltaMs),
                            );
                            setState(() {
                              _draft = _draft.copyWith(
                                trimStart: shifted.trimStart,
                                trimEnd: shifted.trimEnd,
                              );
                              _error = null;
                            });
                          }
                        : null,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: canDrag
                            ? scheme.primary.withValues(alpha: 0.72)
                            : Colors.white.withValues(alpha: 0.24),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.32),
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.drag_indicator,
                          size: 18,
                          color: canDrag
                              ? scheme.onPrimary
                              : Colors.white.withValues(alpha: 0.68),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToolbar(BuildContext context) {
    final selected = _selectedOverlay;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ToolbarButton(
              tooltip: text,
              icon: Icons.text_fields,
              onPressed: _exporting ? null : _addTextOverlay,
            ),
            _ToolbarButton(
              tooltip: emoji,
              icon: Icons.emoji_emotions_outlined,
              onPressed: _exporting ? null : _addEmojiOverlay,
            ),
            _ToolbarButton(
              tooltip: sticker,
              icon: Icons.sticky_note_2_outlined,
              onPressed: _exporting ? null : _addStickerOverlay,
            ),
            _ToolbarButton(
              tooltip: backgroundColor,
              icon: Icons.palette_outlined,
              selected: _draft.backgroundColor !=
                  const Color(storyDefaultVideoBackgroundColor),
              onPressed: _exporting ? null : _chooseBackgroundColor,
            ),
            if (selected != null) ...[
              const SizedBox(width: 8),
              _ToolbarButton(
                tooltip: delete,
                icon: Icons.delete_outline,
                foregroundColor: Theme.of(context).colorScheme.error,
                onPressed:
                    _exporting ? null : () => _removeOverlay(selected.id),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String? get _validationMessage {
    if (_draft.selectedDuration <= Duration.zero ||
        _draft.selectedDuration > storyMaxVideoDuration) {
      return invalidRange;
    }
    return null;
  }

  Future<void> _chooseBackgroundColor() async {
    final color = await showModalBottomSheet<Color>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      builder: (context) => _StoryVideoBackgroundSheet(
        selectedColor: _draft.backgroundColor,
      ),
    );
    if (!mounted || color == null) {
      return;
    }
    setState(() {
      _draft = _draft.copyWith(backgroundColor: color);
      _error = null;
    });
  }

  Future<void> _finish() async {
    setState(() => _error = null);
    final upload = _draft.toUpload();
    if (!upload.hasValidSelection) {
      setState(() => _error = invalidRange);
      return;
    }

    if (!homeStoryVideoEditorShouldExportBeforeUpload(
      usesFullSource: _draft.usesFullSource,
      duration: _draft.duration,
      sizeBytes: _draft.sizeBytes,
    )) {
      Navigator.of(context).pop(_draft);
      return;
    }

    setState(() => _exporting = true);
    late final StoryVideoTrimExportResult result;
    try {
      result = await _trimExporter.exportTrim(
        sourcePath: _draft.path,
        trimStart: _draft.trimStart,
        trimEnd: _draft.trimEnd,
        sourceName: _draft.sourceName,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _exporting = false;
        _error = trimExportFailed;
      });
      return;
    }
    if (!mounted) {
      return;
    }

    if (!result.isSuccess || result.path == null || result.name == null) {
      setState(() {
        _exporting = false;
        _error = result.status == StoryVideoTrimExportStatus.unsupported
            ? trimUnavailable
            : trimExportFailed;
      });
      return;
    }
    final sizeBytes = result.sizeBytes ?? 0;
    if (!storyVideoSizeIsAllowed(sizeBytes)) {
      setState(() {
        _exporting = false;
        _error = trimExportFailed;
      });
      return;
    }

    StoryVideoProbeResult? probe;
    try {
      probe = await _videoProbe.probe(result.path!);
    } catch (_) {
      probe = null;
    }
    if (!mounted) {
      return;
    }

    var exportedDuration = probe?.duration ?? Duration.zero;
    if (exportedDuration <= Duration.zero) {
      exportedDuration = _draft.selectedDuration;
    }
    if (exportedDuration <= Duration.zero ||
        exportedDuration > storyMaxVideoDuration) {
      setState(() {
        _exporting = false;
        _error = trimExportFailed;
      });
      return;
    }

    final thumbnailBytes = probe?.thumbnailBytes ?? _draft.thumbnailBytes;
    final exportedDraft = _draft.copyWith(
      path: result.path,
      sourceName: result.name,
      sourceMimeType: 'video/mp4',
      sizeBytes: sizeBytes,
      duration: exportedDuration,
      width: probe?.size?.width.round() ?? _draft.width,
      height: probe?.size?.height.round() ?? _draft.height,
      thumbnailBytes: thumbnailBytes,
      thumbnailMimeType: probe?.thumbnailBytes == null
          ? _draft.thumbnailMimeType
          : Mime.lookupType('', data: probe!.thumbnailBytes),
      trimStart: Duration.zero,
      trimEnd: exportedDuration,
    );
    Navigator.of(context).pop(exportedDraft);
  }

  Future<void> _addTextOverlay() async {
    final edit = await showDialog<_StoryTextEdit>(
      context: context,
      builder: (context) => _StoryTextDialog(title: textDialogTitle),
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
          size: 76,
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
    final mediaUri = Uri.tryParse(emoticon.key);
    if (image == null || mediaUri?.scheme != 'mxc') {
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
                shadows: const [
                  Shadow(color: Colors.black87, blurRadius: 6),
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
        child = Image(
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
  const _StoryTextDialog({required this.title});

  final String title;

  @override
  State<_StoryTextDialog> createState() => _StoryTextDialogState();
}

class _StoryTextDialogState extends State<_StoryTextDialog> {
  final TextEditingController _controller = TextEditingController();
  Color _color = Colors.white;
  bool _isBold = true;
  bool _isItalic = false;

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
          onPressed: () => Navigator.of(context).pop(
            _StoryTextEdit(_controller.text, _color, _isBold, _isItalic),
          ),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}

class _StoryTextEdit {
  const _StoryTextEdit(
    this.text,
    this.color,
    this.isBold,
    this.isItalic,
  );

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
  const _StoryVideoBackgroundSheet({required this.selectedColor});

  final Color selectedColor;

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
            for (final (index, color) in _storyVideoBackgroundColors.indexed)
              _StoryVideoColorButton(
                key: ValueKey('story-video-background-color-$index'),
                color: color,
                selected: color == selectedColor,
                onTap: () => Navigator.of(context).pop(color),
              ),
          ],
        ),
      ),
    );
  }
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

const List<Color> _textColors = [
  Colors.white,
  Colors.black,
  Color(0xFFFFD54F),
  Color(0xFFFF7043),
  Color(0xFF29B6F6),
  Color(0xFF66BB6A),
  Color(0xFFEC407A),
];

const List<Color> _storyVideoBackgroundColors = [
  Color(storyDefaultVideoBackgroundColor),
  Color(0xFF1B1E2A),
  Color(0xFF3A233C),
  Color(0xFF10303A),
  Color(0xFF26351E),
  Color(0xFF4A2C13),
  Color(0xFFF5F5F5),
  Color(0xFFB71C1C),
  Color(0xFF0D47A1),
  Color(0xFF1B5E20),
];
