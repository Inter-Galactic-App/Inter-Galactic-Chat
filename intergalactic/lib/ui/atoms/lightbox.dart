import 'dart:async';

import 'package:intergalactic/cache/file_provider.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/accessibility/paused_animated_image.dart';
import 'package:intergalactic/ui/atoms/scaled_safe_area.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';
import 'package:intergalactic/ui/molecules/video_player/video_player.dart';
import 'package:intergalactic/ui/molecules/video_player/video_player_controller.dart';
import 'package:intergalactic/utils/image/lod_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tiamat/atoms/popup_dialog.dart';
import 'dart:ui' as ui;

typedef LightboxMobileActionsBuilder = Widget Function(
  BuildContext context,
  VoidCallback dismiss,
);

class Lightbox extends StatefulWidget {
  const Lightbox({
    this.image,
    this.video,
    this.thumbnail,
    this.aspectRatio,
    this.contentKey,
    this.customWidget,
    this.videoController,
    this.actionsBuilder,
    this.mobileActionsBuilder,
    this.onContentLongPress,
    super.key,
  });
  final ImageProvider? image;
  final FileProvider? video;
  final ImageProvider? thumbnail;
  final VideoPlayerController? videoController;
  final Widget? customWidget;
  final WidgetBuilder? actionsBuilder;
  final LightboxMobileActionsBuilder? mobileActionsBuilder;
  final FutureOr<void> Function(BuildContext context)? onContentLongPress;
  final double? aspectRatio;
  final Key? contentKey;

  @override
  State<Lightbox> createState() => _LightboxState();

  static Future<void> show(
    BuildContext context, {
    ImageProvider? image,
    ImageProvider? thumbnail,
    FileProvider? video,
    Widget? customWidget,
    VideoPlayerController? videoController,
    double? aspectRatio,
    WidgetBuilder? actionsBuilder,
    LightboxMobileActionsBuilder? mobileActionsBuilder,
    FutureOr<void> Function(BuildContext context)? onContentLongPress,
    Key? key,
  }) {
    final transitionDuration = InterGalacticMotion.duration(
      context,
      InterGalacticMotion.long,
    );
    return showGeneralDialog(
        context: context,
        barrierDismissible: false,
        barrierLabel: "LIGHTBOX",
        barrierColor: PopupDialog.barrierColor,
        pageBuilder: (context, _, __) {
          return Lightbox(
            image: image,
            video: video,
            videoController: videoController,
            aspectRatio: aspectRatio,
            thumbnail: thumbnail,
            contentKey: key,
            customWidget: customWidget,
            actionsBuilder: actionsBuilder,
            mobileActionsBuilder: mobileActionsBuilder,
            onContentLongPress: onContentLongPress,
            key: GlobalKey(),
          );
        },
        transitionDuration: transitionDuration,
        transitionBuilder: (context, animation, secondaryAnimation, child) =>
            SlideTransition(
              position:
                  Tween(begin: const Offset(0, 1), end: const Offset(0, 0))
                      .animate(CurvedAnimation(
                          parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            ));
  }
}

class _LightboxState extends State<Lightbox> with TickerProviderStateMixin {
  double aspectRatio = 1;
  bool dismissing = false;
  final controller = TransformationController();
  bool loadingHighQuality = false;

  StreamSubscription? onLodChanged;

  bool rotate = false;

  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 850),
    vsync: this,
  );

  late final Animation<double> rotationAnimation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  ).drive(Tween(begin: -0.25, end: 0.0));

  late final Animation<double> scaleAnimation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  ).drive(Tween(begin: 0.6, end: 1.0));

  late final Animation<double> rotation =
      ConstantTween(0.0).animate(_controller);
  late final Animation<double> scale = ConstantTween(1.0).animate(_controller);

  @override
  void dispose() {
    unawaited(onLodChanged?.cancel());
    _controller.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();

    _controller.stop(canceled: true);

    if (widget.aspectRatio != null) {
      aspectRatio = widget.aspectRatio!;
    }

    if (widget.image != null) {
      getImageInfo();
    }

    if (widget.video != null) {
      getVideoInfo();
    }

    if (widget.image case LODImageProvider lod) {
      onLodChanged = lod.onLODChanged.listen((_) {
        getImageInfo();
      });

      loadingHighQuality = true;
      lod.fetchFullRes().then((_) {
        if (mounted) {
          getImageInfo();

          setState(() {
            loadingHighQuality = false;
          });
        }
      });
    }
  }

  void getImageInfo() async {
    late final ui.Image image;
    try {
      image = await getImage();
    } catch (_) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      aspectRatio = image.width / image.height;
    });

    shouldRotate();
  }

  void getVideoInfo() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }

      if (widget.aspectRatio != null) {
        shouldRotate();
      }

      var size = await widget.videoController?.getSize();
      if (!mounted) {
        return;
      }

      if (size != null) {
        setState(() {
          aspectRatio = size.width / size.height;
        });
      }

      shouldRotate();
    });
  }

  double counterRotation = 0.25;

  void shouldRotate() {
    if (!Layout.mobile) {
      return;
    }

    if (widget.image != null && preferences.autoRotateImages.value == false) {
      return;
    }

    if (widget.video != null && preferences.autoRotateVideos.value == false) {
      return;
    }

    var size = MediaQuery.sizeOf(context);
    var screenRatio = size.width / size.height;
    bool prevValue = rotate;
    setState(() {
      rotate = (aspectRatio < 1 && screenRatio > 1) ||
          (aspectRatio > 1 && screenRatio < 1);
    });

    if (rotate != prevValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        if (InterGalacticMotion.shouldReduce(context)) {
          _controller.value = 1;
          return;
        }

        _controller.value = 0;
        _controller.animateTo(1);
      });
    }
  }

  Future<ui.Image> getImage() {
    Completer<ui.Image> completer = Completer<ui.Image>();

    final imageStream = widget.image!.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener((info, synchronousCall) {
      imageStream.removeListener(listener);
      if (!completer.isCompleted) {
        completer.complete(info.image);
      }
    }, onError: (error, stackTrace) {
      imageStream.removeListener(listener);
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    });
    imageStream.addListener(listener);

    return completer.future;
  }

  void dismiss() {
    if (dismissing) {
      return;
    }

    setState(() {
      dismissing = true;
    });
    Navigator.pop(context, widget.contentKey);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): dismiss,
      },
      child: Focus(
        autofocus: true,
        child: GestureDetector(
          onTap: () {
            dismiss();
          },
          child: Container(
            color: Colors.transparent,
            child: Padding(
              padding: const EdgeInsets.all(BuildConfig.MOBILE ? 10 : 100.0),
              child: ScaledSafeArea(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    RotatedBox(
                      quarterTurns: rotate ? 1 : 0,
                      child: ScaleTransition(
                        scale: rotate ? scaleAnimation : scale,
                        child: RotationTransition(
                          turns: rotate ? rotationAnimation : rotation,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: InteractiveViewer(
                                  trackpadScrollCausesScale: true,
                                  transformationController: controller,
                                  maxScale: 3.5,
                                  child: Container(
                                    alignment: Alignment.center,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: GestureDetector(
                                        onTap: () {},
                                        onLongPress:
                                            widget.onContentLongPress == null
                                                ? null
                                                : () =>
                                                    widget.onContentLongPress!(
                                                        context),
                                        child: AspectRatio(
                                            aspectRatio: aspectRatio,
                                            child: widget.customWidget ??
                                                (widget.image != null
                                                    ? Stack(
                                                        fit: StackFit.expand,
                                                        children: [
                                                          PausedAnimatedImage(
                                                            fit: BoxFit.cover,
                                                            image:
                                                                widget.image!,
                                                            isAntiAlias: true,
                                                            filterQuality:
                                                                FilterQuality
                                                                    .medium,
                                                          ),
                                                          if (loadingHighQuality)
                                                            Align(
                                                              alignment: Alignment
                                                                  .bottomRight,
                                                              child: Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .all(
                                                                        8.0),
                                                                child:
                                                                    Container(
                                                                        decoration: BoxDecoration(
                                                                            color: Theme.of(context)
                                                                                .colorScheme
                                                                                .surfaceContainer,
                                                                            borderRadius: BorderRadius.circular(
                                                                                8)),
                                                                        child:
                                                                            Padding(
                                                                          padding: const EdgeInsets
                                                                              .all(
                                                                              8.0),
                                                                          child: SizedBox(
                                                                              width: 12,
                                                                              height: 12,
                                                                              child: CircularProgressIndicator()),
                                                                        )),
                                                              ),
                                                            )
                                                        ],
                                                      )
                                                    : widget.video != null
                                                        ? dismissing
                                                            ? widget.thumbnail !=
                                                                    null
                                                                ? PausedAnimatedImage(
                                                                    fit: BoxFit
                                                                        .cover,
                                                                    image: widget
                                                                        .thumbnail!,
                                                                  )
                                                                : Container(
                                                                    color: Colors
                                                                        .black,
                                                                  )
                                                            : VideoPlayer(
                                                                widget.video!,
                                                                controller: widget
                                                                    .videoController,
                                                                showProgressBar:
                                                                    true,
                                                                canGoFullscreen:
                                                                    false,
                                                                thumbnail: widget
                                                                    .thumbnail,
                                                                key: widget
                                                                    .contentKey,
                                                              )
                                                        : const Placeholder())),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (widget.actionsBuilder != null &&
                                  !BuildConfig.MOBILE)
                                Positioned(
                                  top: 10,
                                  right: 10,
                                  child: widget.actionsBuilder!(context),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (BuildConfig.MOBILE)
                      Positioned(
                        top: 12,
                        right: 12,
                        child: _LightboxCloseButton(onPressed: dismiss),
                      ),
                    if (BuildConfig.MOBILE &&
                        widget.mobileActionsBuilder != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: widget.mobileActionsBuilder!(context, dismiss),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LightboxCloseButton extends StatelessWidget {
  const _LightboxCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.34),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: IconButton(
        tooltip: 'Close',
        icon: const Icon(Icons.close_rounded),
        color: scheme.onSurface,
        onPressed: onPressed,
      ),
    );
  }
}
