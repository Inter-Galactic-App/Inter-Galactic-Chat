import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/stories/story_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_mxc_image_provider.dart';
import 'package:intergalactic/ui/accessibility/paused_animated_image.dart';
import 'package:intergalactic/ui/molecules/video_player/video_player.dart';
import 'package:intergalactic/ui/molecules/video_player/video_player_controller.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_draft.dart';
import 'package:intergalactic/ui/organisms/home_screen/story_video_frame.dart';
import 'package:intergalactic/utils/text_utils.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

@visibleForTesting
bool homeStoryViewerRequiresVideoReadySignal(StoryItem story) =>
    story.isVideo && story.video != null;

class HomeStoryViewer {
  static Future<void> show(
    BuildContext context, {
    required Client client,
    required String userId,
    required List<StoryItem> stories,
    required String displayName,
    required Color avatarColor,
    ImageProvider? avatar,
    String? initialStoryId,
    String? initialStoryEventId,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black,
      transitionDuration: InterGalacticMotion.duration(
        context,
        InterGalacticMotion.short,
      ),
      pageBuilder: (_, __, ___) {
        return _HomeStoryViewerDialog(
          client: client,
          userId: userId,
          stories: stories,
          displayName: displayName,
          avatar: avatar,
          avatarColor: avatarColor,
          initialStoryId: initialStoryId,
          initialStoryEventId: initialStoryEventId,
        );
      },
      transitionBuilder: (context, animation, _, child) {
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
    );
  }
}

class _HomeStoryViewerDialog extends StatefulWidget {
  const _HomeStoryViewerDialog({
    required this.client,
    required this.userId,
    required this.stories,
    required this.displayName,
    required this.avatarColor,
    this.avatar,
    this.initialStoryId,
    this.initialStoryEventId,
  });

  final Client client;
  final String userId;
  final List<StoryItem> stories;
  final String displayName;
  final ImageProvider? avatar;
  final Color avatarColor;
  final String? initialStoryId;
  final String? initialStoryEventId;

  @override
  State<_HomeStoryViewerDialog> createState() => _HomeStoryViewerDialogState();
}

class _HomeStoryViewerDialogState extends State<_HomeStoryViewerDialog> {
  static const Duration _storyDuration = Duration(seconds: 5);
  static const Duration _navigationTapTimeout = Duration(milliseconds: 300);

  late List<StoryItem> _stories;
  int _index = 0;
  DateTime _startedAt = DateTime.now();
  DateTime? _pointerDownAt;
  Duration _pausedElapsed = Duration.zero;
  Timer? _timer;
  int _preloadGeneration = 0;
  bool _imageReady = false;
  bool _pressPaused = false;
  bool _deleting = false;
  bool _mentionSheetOpen = false;
  bool _muted = false;
  VideoPlayerController? _videoController;
  StreamSubscription<void>? _videoReadySubscription;
  StreamSubscription<Object>? _videoErrorSubscription;
  String? _reacting;
  String? _error;

  String get homeStoryViewerDeleteStory => Intl.message(
    'Delete story',
    name: 'homeStoryViewerDeleteStory',
    desc: 'Tooltip for deleting an owned story',
  );

  String get homeStoryViewerDeleteError => Intl.message(
    'Story could not be deleted.',
    name: 'homeStoryViewerDeleteError',
    desc: 'Error shown when deleting a story from the viewer fails',
  );

  String get homeStoryViewerReactionError => Intl.message(
    'Reaction could not be sent.',
    name: 'homeStoryViewerReactionError',
    desc: 'Error shown when reacting to a story fails',
  );

  String get homeStoryViewerShowAllMentions => Intl.message(
    'Show all mentions',
    name: 'homeStoryViewerShowAllMentions',
    desc: 'Tooltip for opening the story mention details sheet',
  );

  String get homeStoryViewerMentionedPeople => Intl.message(
    'Mentioned people',
    name: 'homeStoryViewerMentionedPeople',
    desc: 'Title for the story mention details sheet',
  );

  @override
  void initState() {
    super.initState();
    _stories = List<StoryItem>.from(widget.stories)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final initialIndex = _stories.indexWhere(
      (story) =>
          story.storyId == widget.initialStoryId ||
          (widget.initialStoryEventId != null &&
              story.eventId == widget.initialStoryEventId),
    );
    if (initialIndex >= 0) {
      _index = initialIndex;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prepareCurrentStory();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cancelVideoSubscriptions();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_stories.isEmpty) {
      return const SizedBox.shrink();
    }

    final story = _stories[_index];
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                key: ValueKey('home-story-media-${story.storyId}'),
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) => _pauseForPress(),
                onTapUp: (details) {
                  final pressedAt = _pointerDownAt;
                  final wasNavigationTap =
                      pressedAt != null &&
                      DateTime.now().difference(pressedAt) <=
                          _navigationTapTimeout;
                  if (!wasNavigationTap) {
                    _resumeAfterPress();
                    return;
                  }
                  _clearPressPause();
                  final width = MediaQuery.sizeOf(context).width;
                  if (details.localPosition.dx < width / 2) {
                    _previous();
                  } else {
                    _next();
                  }
                },
                onTapCancel: _resumeAfterPress,
                child: _buildStoryMedia(story),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              top: 10,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      for (var i = 0; i < _stories.length; i++)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: i == 0 ? 0 : 3,
                              right: i == _stories.length - 1 ? 0 : 3,
                            ),
                            child: LinearProgressIndicator(
                              value: _progressFor(i),
                              minHeight: 3,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.24,
                              ),
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      tiamat.Avatar(
                        radius: 18,
                        image: widget.avatar,
                        placeholderText: widget.displayName,
                        placeholderColor: widget.avatarColor,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(
                            context,
                          ).textTheme.titleSmall?.copyWith(color: Colors.white),
                        ),
                      ),
                      if (story.isVideo)
                        IconButton(
                          tooltip: _muted ? 'Unmute' : 'Mute',
                          onPressed: _toggleMute,
                          icon: Icon(
                            _muted
                                ? Icons.volume_off_outlined
                                : Icons.volume_up_outlined,
                          ),
                          color: Colors.white,
                        ),
                      if (story.isOwn)
                        IconButton(
                          tooltip: homeStoryViewerDeleteStory,
                          onPressed: _deleting ? null : _deleteCurrent,
                          icon: _deleting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.delete_outline),
                          color: Colors.white,
                        ),
                      IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).closeButtonLabel,
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close),
                        color: Colors.white,
                      ),
                    ],
                  ),
                  if (story.mentionedUserIds.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildMentionPills(story),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _error!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 18,
              child: _buildReactionPanel(story),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMentionPills(StoryItem story) {
    final room = _roomForStory(story);
    final mentions = _mentionSummaries(room, story);
    if (mentions.isEmpty) {
      return const SizedBox.shrink();
    }

    final visibleMentions = mentions.take(2).toList();
    final hiddenCount = mentions.length - visibleMentions.length;

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final mention in visibleMentions)
              _StoryMentionChip(
                label: mention.label,
                tooltip: homeStoryViewerShowAllMentions,
                onPressed: () => _showMentionSheet(story),
              ),
            if (hiddenCount > 0)
              _StoryMentionChip(
                label: '+$hiddenCount',
                tooltip: homeStoryViewerShowAllMentions,
                onPressed: () => _showMentionSheet(story),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoryMedia(StoryItem story) {
    if (story.isVideo) {
      final video = story.video;
      return LayoutBuilder(
        builder: (context, constraints) {
          final size = _storyFrameSize(
            constraints,
            canvasMode: story.canvasMode,
          );
          final layout = storyVideoCompositionLayout(
            canvasSize: size,
            fitMode: story.fitMode,
            mediaWidth: story.width,
            mediaHeight: story.height,
            displayWidth: story.displayWidth,
            displayHeight: story.displayHeight,
            hasBakedLetterbox: story.hasBakedLetterbox,
          );
          return Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: DecoratedBox(
                decoration: storyVideoBackgroundDecoration(
                  backgroundColor: Color(
                    story.backgroundColor ?? storyDefaultVideoBackgroundColor,
                  ),
                  backgroundGradientColor: Color(
                    story.backgroundGradientColor ??
                        storyDefaultVideoBackgroundGradientColor,
                  ),
                  backgroundMode: story.backgroundMode,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (video == null)
                      const Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white70,
                          size: 48,
                        ),
                      )
                    else
                      Positioned.fromRect(
                        rect: layout.mediaDisplayRect,
                        child: StoryVideoMediaLayer(
                          layout: layout,
                          builder: (fit) => VideoPlayer(
                            video,
                            key: ValueKey(_storyVideoKey(story)),
                            thumbnail: story.thumbnail,
                            fileName: story.rawContent['filename'] as String?,
                            controller: _videoController,
                            autoplay: true,
                            initialMuted: _muted,
                            doThumbnail: story.thumbnail != null,
                            showProgressBar: false,
                            controlsEnabled: false,
                            fit: fit,
                            // The story background owns non-media pixels; the
                            // video surface must not paint its own black
                            // letterbox.
                            letterboxFill: Colors.transparent,
                          ),
                        ),
                      ),
                    StoryVideoBackgroundMatte(
                      rects: layout.nonMediaRects,
                      backgroundColor: Color(
                        story.backgroundColor ??
                            storyDefaultVideoBackgroundColor,
                      ),
                      backgroundGradientColor: Color(
                        story.backgroundGradientColor ??
                            storyDefaultVideoBackgroundGradientColor,
                      ),
                      backgroundMode: story.backgroundMode,
                    ),
                    for (final overlay in story.overlays)
                      _StoryPlaybackOverlayWidget(
                        overlay: overlay,
                        canvasSize: size,
                        stickerImage: _stickerImageForOverlay(overlay),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    return Center(
      child: story.image == null
          ? const Icon(
              Icons.broken_image_outlined,
              color: Colors.white70,
              size: 48,
            )
          : PausedAnimatedImage(
              image: story.image!,
              fit: BoxFit.contain,
              width: double.infinity,
              height: double.infinity,
            ),
    );
  }

  Size _storyFrameSize(
    BoxConstraints constraints, {
    StoryVideoCanvasMode canvasMode = StoryVideoCanvasMode.portrait,
  }) {
    return storyVideoCanvasSizeForConstraints(
      constraints: constraints,
      canvasMode: canvasMode,
    );
  }

  Widget _buildReactionPanel(StoryItem story) {
    final component = widget.client.getComponent<StoryComponent>();
    if (component == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<void>(
      stream: component.onStoriesChanged,
      builder: (context, _) {
        if (story.isOwn) {
          return _buildOwnReactionSummary(component, story);
        }
        return _buildQuickReactionBar(component, story);
      },
    );
  }

  Widget _buildQuickReactionBar(StoryComponent component, StoryItem story) {
    final currentReaction = component.reactionForStoryByCurrentUser(story);
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final reaction in storyReactionChoices)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _StoryReactionButton(
                    reaction: reaction,
                    selected: currentReaction?.reaction == reaction,
                    busy: _reacting == reaction,
                    onPressed: _reacting == null
                        ? () => _sendReaction(story, reaction)
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOwnReactionSummary(StoryComponent component, StoryItem story) {
    final reactions = component.reactionsForStory(story);
    if (reactions.isEmpty) {
      return const SizedBox.shrink();
    }

    final room = story.roomId == null
        ? null
        : widget.client.getRoom(story.roomId!);
    return Align(
      alignment: Alignment.bottomLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final reaction in reactions)
                  _StoryReactionChip(
                    label: _reactionDisplayName(room, reaction.reactorId),
                    reaction: reaction.reaction,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _reactionDisplayName(Room? room, String userId) {
    final member = room?.getMember(userId);
    final displayName = member?.displayName;
    if (displayName != null && displayName.trim().isNotEmpty) {
      return displayName;
    }
    return userId;
  }

  Room? _roomForStory(StoryItem story) =>
      story.roomId == null ? null : widget.client.getRoom(story.roomId!);

  List<_StoryMentionSummary> _mentionSummaries(Room? room, StoryItem story) {
    final seen = <String>{};
    final summaries = <_StoryMentionSummary>[];
    for (final userId in story.mentionedUserIds) {
      if (!seen.add(userId)) {
        continue;
      }
      final member = room?.getMember(userId);
      final displayName = member?.displayName.trim();
      final name = displayName == null || displayName.isEmpty
          ? userId
          : displayName;
      summaries.add(
        _StoryMentionSummary(
          userId: userId,
          displayName: name,
          label: name.startsWith('@') ? name : '@$name',
          avatar: member?.avatar,
          avatarColor: member?.defaultColor ?? _mentionColor(userId),
        ),
      );
    }
    return summaries;
  }

  Color _mentionColor(String userId) {
    final hash = userId.codeUnits.fold<int>(
      0,
      (value, codeUnit) => (value * 31 + codeUnit) & 0x7fffffff,
    );
    return Colors.primaries[hash % Colors.primaries.length].shade400;
  }

  Future<void> _showMentionSheet(StoryItem story) async {
    final room = _roomForStory(story);
    final mentions = _mentionSummaries(room, story);
    if (mentions.isEmpty) {
      return;
    }

    _mentionSheetOpen = true;
    _timer?.cancel();
    try {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        builder: (context) => _StoryMentionSheet(
          title: homeStoryViewerMentionedPeople,
          mentions: mentions,
        ),
      );
    } finally {
      _mentionSheetOpen = false;
    }
    if (!mounted) {
      return;
    }

    setState(() {
      _startedAt = DateTime.now();
    });
    if (_imageReady) {
      _startTimer();
    }
  }

  double _progressFor(int storyIndex) {
    if (storyIndex < _index) {
      return 1;
    }
    if (storyIndex > _index) {
      return 0;
    }
    if (!_imageReady) {
      return 0;
    }
    final elapsed = _pressPaused
        ? _pausedElapsed
        : DateTime.now().difference(_startedAt);
    return (elapsed.inMilliseconds /
            _durationForStory(_stories[_index]).inMilliseconds)
        .clamp(0, 1)
        .toDouble();
  }

  Duration _durationForStory(StoryItem story) {
    if (story.isVideo && story.durationMs != null && story.durationMs! > 0) {
      final duration = Duration(milliseconds: story.durationMs!);
      if (duration < const Duration(seconds: 1)) {
        return const Duration(seconds: 1);
      }
      if (duration > storyMaxVideoDuration) {
        return storyMaxVideoDuration;
      }
      return duration;
    }
    return _storyDuration;
  }

  void _startTimer() {
    _timer?.cancel();
    if (_pressPaused) {
      return;
    }
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) {
        return;
      }
      if (_progressFor(_index) >= 1) {
        _next();
      } else {
        setState(() {});
      }
    });
  }

  void _prepareCurrentStory() {
    if (!mounted || _stories.isEmpty) {
      return;
    }

    final generation = ++_preloadGeneration;
    final story = _stories[_index];
    final image = story.image;
    _timer?.cancel();
    _clearPressPause();
    _cancelVideoSubscriptions();
    _videoController = story.isVideo ? VideoPlayerController() : null;
    setState(() {
      _imageReady = false;
    });

    if (homeStoryViewerRequiresVideoReadySignal(story)) {
      final controller = _videoController!;
      _videoReadySubscription = controller.ready.listen((_) {
        _markStoryReady(generation);
      });
      _videoErrorSubscription = controller.errors.listen((_) {
        _markStoryReady(generation);
      });
      return;
    }

    final load = image == null
        ? Future<void>.value()
        : precacheImage(image, context).catchError((_) {});
    unawaited(
      load.whenComplete(() {
        _markStoryReady(generation);
      }),
    );
  }

  void _markStoryReady(int generation) {
    if (!mounted || generation != _preloadGeneration || _imageReady) {
      return;
    }
    setState(() {
      _imageReady = true;
      _startedAt = DateTime.now();
    });
    _markCurrentSeen();
    if (_pointerDownAt != null) {
      _pressPaused = true;
      _pausedElapsed = Duration.zero;
      unawaited(_videoController?.pause());
    } else if (!_mentionSheetOpen) {
      _startTimer();
    }
  }

  void _pauseForPress() {
    _pointerDownAt = DateTime.now();
    if (!_imageReady || _mentionSheetOpen || _pressPaused) {
      return;
    }

    final duration = _durationForStory(_stories[_index]);
    final elapsed = DateTime.now().difference(_startedAt);
    _pausedElapsed = elapsed < Duration.zero
        ? Duration.zero
        : elapsed > duration
        ? duration
        : elapsed;
    _pressPaused = true;
    _timer?.cancel();
    unawaited(_videoController?.pause());
  }

  void _resumeAfterPress() {
    _pointerDownAt = null;
    if (!_pressPaused) {
      return;
    }

    _pressPaused = false;
    _startedAt = DateTime.now().subtract(_pausedElapsed);
    if (_imageReady && !_mentionSheetOpen) {
      _startTimer();
      unawaited(_videoController?.play());
    }
  }

  void _clearPressPause() {
    _pointerDownAt = null;
    _pressPaused = false;
    _pausedElapsed = Duration.zero;
  }

  void _cancelVideoSubscriptions() {
    unawaited(_videoReadySubscription?.cancel());
    unawaited(_videoErrorSubscription?.cancel());
    _videoReadySubscription = null;
    _videoErrorSubscription = null;
    final controller = _videoController;
    _videoController = null;
    if (controller != null) {
      unawaited(controller.dispose());
    }
  }

  void _next() {
    if (_index >= _stories.length - 1) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _index++;
      _imageReady = false;
      _error = null;
    });
    _prepareCurrentStory();
  }

  void _previous() {
    if (_index == 0) {
      setState(() {
        _imageReady = false;
        _error = null;
      });
      _prepareCurrentStory();
      return;
    }
    setState(() {
      _index--;
      _imageReady = false;
      _error = null;
    });
    _prepareCurrentStory();
  }

  void _markCurrentSeen() {
    final component = widget.client.getComponent<StoryComponent>();
    if (component != null && _stories.isNotEmpty) {
      unawaited(component.markStoriesSeen(widget.userId, [_stories[_index]]));
    }
  }

  Future<void> _sendReaction(StoryItem story, String reaction) async {
    final component = widget.client.getComponent<StoryComponent>();
    if (component == null) {
      return;
    }

    setState(() {
      _reacting = reaction;
      _error = null;
    });
    try {
      await component.sendStoryReaction(story, reaction);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = homeStoryViewerReactionError;
        _startedAt = DateTime.now();
      });
    } finally {
      if (mounted) {
        setState(() {
          _reacting = null;
        });
      }
    }
  }

  Future<void> _deleteCurrent() async {
    final story = _stories[_index];
    final component = widget.client.getComponent<StoryComponent>();
    if (component == null) {
      return;
    }

    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await component.deleteStory(story.storyId);
      if (!mounted) {
        return;
      }
      setState(() {
        _stories.removeAt(_index);
        _deleting = false;
        _error = null;
        if (_stories.isNotEmpty && _index >= _stories.length) {
          _index = _stories.length - 1;
        }
        _imageReady = false;
      });
      if (_stories.isEmpty) {
        Navigator.of(context).maybePop();
      } else {
        _prepareCurrentStory();
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = homeStoryViewerDeleteError;
        _startedAt = DateTime.now();
      });
    } finally {
      if (mounted && _deleting) {
        setState(() {
          _deleting = false;
        });
      }
    }
  }

  void _toggleMute() {
    final nextMuted = !_muted;
    setState(() {
      _muted = nextMuted;
    });
    unawaited(_videoController?.setVolume(nextMuted ? 0 : 100));
  }

  String _storyVideoKey(StoryItem story) {
    return [
      story.senderId,
      story.storyId,
      story.eventId,
      story.mediaUri.toString(),
    ].whereType<String>().join('|');
  }

  ImageProvider? _stickerImageForOverlay(StoryMediaOverlay overlay) {
    final uri = overlay.mediaUri;
    if (overlay.type != StoryMediaOverlayType.sticker ||
        uri == null ||
        uri.scheme != 'mxc') {
      return null;
    }
    final client = widget.client;
    if (client is MatrixClient) {
      return MatrixMxcImage(
        uri,
        client.matrixClient,
        doThumbnail: false,
        doFullres: true,
        autoLoadFullRes: true,
      );
    }
    return null;
  }
}

class _StoryPlaybackOverlayWidget extends StatelessWidget {
  const _StoryPlaybackOverlayWidget({
    required this.overlay,
    required this.canvasSize,
    this.stickerImage,
  });

  final StoryMediaOverlay overlay;
  final Size canvasSize;
  final ImageProvider? stickerImage;

  @override
  Widget build(BuildContext context) {
    final outputScale = canvasSize.width / storyEditorOutputWidth;
    late final Widget child;
    late final double width;
    late final double height;

    switch (overlay.type) {
      case StoryMediaOverlayType.text:
        final clampedScale = overlay.scale.clamp(0.35, 5.0).toDouble();
        final fontSize = (overlay.fontSize ?? 96) * outputScale * clampedScale;
        width = canvasSize.width * 0.86;
        height = math.max(54.0, fontSize * 1.9);
        child = Center(
          child: DecoratedBox(
            decoration: overlay.backgroundColor == null
                ? const BoxDecoration()
                : BoxDecoration(
                    color: Color(overlay.backgroundColor!),
                    borderRadius: BorderRadius.circular(8),
                  ),
            child: Padding(
              padding: overlay.backgroundColor == null
                  ? EdgeInsets.zero
                  : EdgeInsets.symmetric(
                      horizontal: 14 * outputScale * clampedScale,
                      vertical: 8 * outputScale * clampedScale,
                    ),
              child: Text.rich(
                TextSpan(
                  children: TextUtils.nativeEmojiTextSpans(
                    overlay.content ?? '',
                    style: TextStyle(
                      color: Color(overlay.color ?? 0xFFFFFFFF),
                      fontSize: fontSize,
                      fontWeight: overlay.bold
                          ? FontWeight.w700
                          : FontWeight.w400,
                      fontStyle: overlay.italic
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
      case StoryMediaOverlayType.emoji:
        final fontSize =
            (overlay.fontSize ?? 140) *
            outputScale *
            overlay.scale.clamp(0.35, 5.0);
        width = math.max(72.0, fontSize * 1.4);
        height = math.max(72.0, fontSize * 1.4);
        child = Center(
          child: Text(
            overlay.content ?? '',
            style: TextUtils.withNativeEmojiFallback(
              TextStyle(
                fontSize: fontSize,
                shadows: const [Shadow(color: Colors.black87, blurRadius: 6)],
              ),
            ),
          ),
        );
      case StoryMediaOverlayType.sticker:
        final size =
            (overlay.fontSize ?? 360) *
            outputScale *
            overlay.scale.clamp(0.35, 5.0);
        width = math.max(56.0, size);
        height = math.max(56.0, size);
        child = stickerImage == null
            ? Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.48),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      overlay.content ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              )
            : PausedAnimatedImage(
                image: stickerImage!,
                fit: BoxFit.contain,
                errorBuilder: (context, _, __) => Icon(
                  Icons.broken_image_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
              );
    }

    return Positioned(
      left: overlay.x * canvasSize.width - width / 2,
      top: overlay.y * canvasSize.height - height / 2,
      width: width,
      height: height,
      child: IgnorePointer(
        child: Transform.rotate(angle: overlay.rotationRadians, child: child),
      ),
    );
  }
}

class _StoryMentionSummary {
  const _StoryMentionSummary({
    required this.userId,
    required this.displayName,
    required this.label,
    required this.avatarColor,
    this.avatar,
  });

  final String userId;
  final String displayName;
  final String label;
  final ImageProvider? avatar;
  final Color avatarColor;
}

class _StoryMentionChip extends StatelessWidget {
  const _StoryMentionChip({
    required this.label,
    required this.tooltip,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return tiamat.Tooltip(
      text: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onPressed,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.52),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.alternate_email,
                    color: Colors.white70,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 170),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StoryMentionSheet extends StatelessWidget {
  const _StoryMentionSheet({required this.title, required this.mentions});

  final String title;
  final List<_StoryMentionSummary> mentions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    return SafeArea(
      child: SizedBox(
        height: media.size.height * 0.42,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                itemCount: mentions.length,
                separatorBuilder: (_, __) => const SizedBox(height: 2),
                itemBuilder: (context, index) {
                  final mention = mentions[index];
                  return ListTile(
                    leading: tiamat.Avatar(
                      radius: 18,
                      image: mention.avatar,
                      placeholderText: mention.displayName,
                      placeholderColor: mention.avatarColor,
                    ),
                    title: Text(
                      mention.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: mention.displayName == mention.userId
                        ? null
                        : Text(
                            mention.userId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StoryReactionButton extends StatelessWidget {
  const _StoryReactionButton({
    required this.reaction,
    required this.selected,
    required this.busy,
    required this.onPressed,
  });

  final String reaction;
  final bool selected;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: reaction,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: selected ? Colors.white.withValues(alpha: 0.18) : null,
        foregroundColor: Colors.white,
      ),
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              reaction,
              style: TextUtils.withNativeEmojiFallback(
                const TextStyle(color: Colors.white, fontSize: 22),
              ),
            ),
    );
  }
}

class _StoryReactionChip extends StatelessWidget {
  const _StoryReactionChip({required this.label, required this.reaction});

  final String label;
  final String reaction;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text.rich(
          TextSpan(
            children: TextUtils.nativeEmojiTextSpans(
              '$label $reaction',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.white),
            ),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
