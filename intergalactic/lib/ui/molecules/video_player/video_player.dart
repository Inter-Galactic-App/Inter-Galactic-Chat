import 'dart:async';

import 'package:intergalactic/cache/file_provider.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/ui/atoms/tiny_pill.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:intergalactic/ui/molecules/video_player/video_player_implementation.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';
import 'package:intergalactic/utils/text_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import '../../atoms/gradient_background.dart';
import 'video_player_controller.dart';

import '../../atoms/icon_button.dart' as i;

class VideoPlayer extends StatefulWidget {
  const VideoPlayer(
    this.videoFile, {
    this.thumbnail,
    this.fileName,
    super.key,
    this.canGoFullscreen = false,
    this.onFullscreen,
    this.decodeFirstFrame = false,
    this.autoplay = false,
    this.initialMuted = false,
    this.controller,
    this.doThumbnail = true,
    this.showProgressBar = true,
    this.controlsEnabled = true,
    this.fit = BoxFit.cover,
    this.letterboxFill = const Color(0xFF000000),
  });
  final FileProvider videoFile;
  final ImageProvider? thumbnail;
  final bool showProgressBar;
  final bool controlsEnabled;
  final bool canGoFullscreen;
  final bool doThumbnail;
  final bool decodeFirstFrame;
  final bool autoplay;
  final bool initialMuted;
  final BoxFit fit;

  /// Color painted by the video surface around the fitted frame. Story
  /// composition passes transparent so the story background owns letterbox
  /// pixels instead of the player.
  final Color letterboxFill;
  final String? fileName;
  final Function? onFullscreen;
  final VideoPlayerController? controller;

  @override
  State<VideoPlayer> createState() => VideoPlayerState();
}

class VideoPlayerState extends State<VideoPlayer> {
  late VideoPlayerController controller;
  bool ownsController = false;
  bool playing = false;
  bool inited = false;
  bool buffering = false;
  DownloadProgress? downloadProgress;
  late bool showThumbnail;
  bool shouldShowControls = true;
  bool isCompleted = false;
  double videoProgress = 0;
  bool updateSlider = true;
  bool pauseAnimatedMedia = false;
  Object? loadError;
  Timer? uiHideTimer;

  List<StreamSubscription> subscriptions = [];

  bool get _shouldAutoplay => widget.autoplay && !pauseAnimatedMedia;
  bool get _autoplayPausedByAccessibility =>
      widget.autoplay && pauseAnimatedMedia && !playing && !isCompleted;

  @override
  void initState() {
    showThumbnail = widget.doThumbnail;

    ownsController = widget.controller == null;
    controller = widget.controller ?? VideoPlayerController();
    _resetPlaybackState();
    _attachControllerListeners();

    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextPauseAnimatedMedia = AccessibilityScope.of(
      context,
    ).pauseAnimatedMedia;
    if (nextPauseAnimatedMedia == pauseAnimatedMedia) {
      return;
    }

    final wasPlaying = playing;
    pauseAnimatedMedia = nextPauseAnimatedMedia;
    if (!pauseAnimatedMedia) {
      return;
    }

    uiHideTimer?.cancel();
    uiHideTimer = null;
    playing = false;
    shouldShowControls = true;
    if (widget.autoplay && !widget.decodeFirstFrame) {
      inited = false;
    }
    if (wasPlaying) {
      unawaited(controller.pause());
    }
  }

  void _attachControllerListeners() {
    final attachedController = controller;
    subscriptions = [
      attachedController.isBuffering.listen((isBuffering) {
        if (!_canUseAttachedController(attachedController)) return;
        setState(() {
          buffering = isBuffering;

          if (!isBuffering) {
            showThumbnail = false;
          }
        });
      }),
      attachedController.isCompleted.listen((event) {
        if (!_canUseAttachedController(attachedController)) return;
        setState(() {
          isCompleted = event;
          if (isCompleted) shouldShowControls = true;
        });
      }),
      attachedController.onDownloadProgressed.listen((event) {
        if (!_canUseAttachedController(attachedController)) return;
        setState(() {
          downloadProgress = event;
        });
      }),
      attachedController.errors.listen((event) {
        if (!_canUseAttachedController(attachedController)) return;
        setState(() {
          loadError = event;
          buffering = false;
          shouldShowControls = false;
        });
      }),
      attachedController.onProgressed.listen((event) async {
        final length = await attachedController.getLength();
        if (!_canUseAttachedController(attachedController) ||
            !updateSlider ||
            length.inMilliseconds <= 0) {
          return;
        }
        setState(() {
          videoProgress = clampDouble(
            event.inMilliseconds.toDouble() / length.inMilliseconds.toDouble(),
            0,
            1,
          );
        });
      }),
    ];
  }

  bool _canUseAttachedController(VideoPlayerController attachedController) =>
      mounted && identical(controller, attachedController);

  void _cancelControllerListeners() {
    for (var sub in subscriptions) {
      sub.cancel();
    }
    subscriptions.clear();
  }

  void _resetPlaybackState() {
    loadError = null;
    buffering = false;
    downloadProgress = null;
    isCompleted = false;
    videoProgress = 0;
    updateSlider = true;
    showThumbnail = widget.doThumbnail;
    final autoplay = _shouldAutoplay;
    inited = autoplay;
    playing = autoplay;
    shouldShowControls = !autoplay;
  }

  @override
  void didUpdateWidget(covariant VideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controllerChanged = oldWidget.controller != widget.controller;
    if (controllerChanged) {
      final previousController = controller;
      final shouldDisposePrevious = ownsController;
      _cancelControllerListeners();
      ownsController = widget.controller == null;
      controller = widget.controller ?? VideoPlayerController();
      _attachControllerListeners();
      if (shouldDisposePrevious) {
        unawaited(previousController.dispose());
      }
    }
    final sourceChanged =
        oldWidget.videoFile.fileIdentifier != widget.videoFile.fileIdentifier;
    if (!sourceChanged && !controllerChanged) {
      return;
    }

    _resetPlaybackState();
  }

  @override
  void dispose() {
    uiHideTimer?.cancel();
    uiHideTimer = null;
    _cancelControllerListeners();
    if (ownsController) {
      unawaited(controller.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (loadError == null && (widget.decodeFirstFrame || inited))
          pickPlayer(),
        if (showThumbnail) thumbnail(),
        if (buffering && loadError == null) bufferingWidget(),
        if (loadError != null) errorWidget(),
        if (loadError == null && widget.controlsEnabled) controls(),
      ],
    );
  }

  Widget errorWidget() {
    final color = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface.withAlpha(180),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, color: color, size: 32),
              const SizedBox(height: 8),
              Text(
                'Video unavailable',
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget bufferingWidget() {
    double? progress;
    final download = downloadProgress;

    if (download != null) {
      progress = download.downloaded.toDouble() / download.total.toDouble();
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 50,
            height: 50,
            child: CircularProgressIndicator(value: progress),
          ),
          if (download != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
              child: TinyPill(
                background: Theme.of(context).colorScheme.secondaryContainer,
                foreground: Theme.of(context).colorScheme.onSecondaryContainer,
                "${TextUtils.readableFileSize(download.downloaded)} / ${TextUtils.readableFileSize(download.total)}",
              ),
            ),
        ],
      ),
    );
  }

  Widget thumbnail() {
    return widget.thumbnail != null
        ? Image(fit: widget.fit, image: widget.thumbnail!)
        : Container(color: widget.letterboxFill);
  }

  Widget controls() {
    return GestureDetector(
      onTap: () {
        if (BuildConfig.MOBILE) {
          if (shouldShowControls) {
            hideControls();
          } else {
            showControls();
          }
        }
      },
      child: MouseRegion(
        onEnter: (_) {
          showControls();
        },
        onExit: (_) {
          hideControls();
        },
        child: AnimatedOpacity(
          opacity: shouldShowControls ? 1.0 : 0.0,
          duration: InterGalacticMotion.duration(
            context,
            InterGalacticMotion.long,
          ),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.center,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Opacity(
                      opacity: 0.9,
                      child: tiamat.CircleButton(
                        radius: 30,
                        icon: isCompleted
                            ? Icons.replay
                            : playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        semanticLabel: _playControlLabel(),
                        tooltip: _playControlTooltip(),
                        onPressed: () {
                          if (isCompleted) return replay();
                          if (playing) return pause();
                          play();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.canGoFullscreen || widget.showProgressBar)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    height: 50,
                    child: GradientBackground(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerLowest.withAlpha(200),
                      child: Row(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (widget.showProgressBar)
                            Expanded(
                              child: tiamat.Slider(
                                value: videoProgress,
                                min: 0,
                                max: 1,
                                onChangeEnd: (value) {
                                  updateSlider = true;
                                  seekPercent(value);
                                },
                                onChanged: (value) {
                                  setState(() {
                                    videoProgress = value;
                                  });
                                },
                                onChangeStart: (value) {
                                  updateSlider = false;
                                },
                              ),
                            ),
                          if (widget.canGoFullscreen)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(0, 0, 8, 0),
                              child: i.IconButton(
                                icon: Icons.fullscreen_rounded,
                                size: 24,
                                semanticLabel: "Enter fullscreen video",
                                tooltip: "Fullscreen",
                                onPressed: () {
                                  widget.onFullscreen?.call();
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void pause() async {
    setState(() {
      playing = false;
    });

    controller.pause();
  }

  void play() async {
    setState(() {
      inited = true;
      playing = true;
      shouldShowControls = false;
      controller.play();
      if (BuildConfig.MOBILE) hideControls();
    });
  }

  void replay() async {
    setState(() {
      playing = true;
      controller.replay();
      shouldShowControls = false;
      if (BuildConfig.MOBILE) hideControls();
    });
  }

  String _playControlLabel() {
    if (isCompleted) {
      return 'Replay video';
    }
    if (playing) {
      return 'Pause video';
    }
    if (widget.autoplay && pauseAnimatedMedia) {
      return 'Play video. Autoplay paused by accessibility setting';
    }
    return 'Play video';
  }

  String _playControlTooltip() {
    if (isCompleted) {
      return 'Replay';
    }
    if (playing) {
      return 'Pause';
    }
    if (widget.autoplay && pauseAnimatedMedia) {
      return 'Play. Autoplay paused';
    }
    return 'Play';
  }

  void showControls() {
    if (!mounted) {
      return;
    }
    setState(() {
      shouldShowControls = true;
    });

    if (BuildConfig.MOBILE) {
      uiHideTimer?.cancel();
      uiHideTimer = Timer(const Duration(seconds: 3), hideControls);
    }
  }

  void hideControls() {
    if (!mounted) {
      return;
    }
    if (_autoplayPausedByAccessibility) {
      setState(() {
        shouldShowControls = true;
      });
      return;
    }
    setState(() {
      shouldShowControls = false;
    });
    uiHideTimer?.cancel();
    uiHideTimer = null;
  }

  void seekPercent(double percent) async {
    controller.seekTo(await controller.getLength() * percent);
    setState(() {
      videoProgress = percent;
    });
  }

  Widget pickPlayer() {
    return VideoPlayerImplementation(
      key: ValueKey(
        '${widget.videoFile.fileIdentifier}:${identityHashCode(controller)}',
      ),
      controller: controller,
      videoFile: widget.videoFile,
      decodeFirstFrame: widget.decodeFirstFrame,
      playOnOpen: playing,
      initialVolume: widget.initialMuted ? 0 : 100,
      fit: widget.fit,
      letterboxFill: widget.letterboxFill,
    );
  }
}
