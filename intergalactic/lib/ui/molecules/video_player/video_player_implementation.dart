import 'dart:async';
import 'dart:typed_data';

import 'package:intergalactic/cache/file_provider.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'video_player_controller.dart';

class VideoPlayerImplementation extends StatefulWidget {
  const VideoPlayerImplementation(
      {required this.controller,
      required this.videoFile,
      this.decodeFirstFrame = false,
      this.playOnOpen = false,
      this.initialVolume = 100,
      this.width = 640,
      this.height = 340,
      this.fit = BoxFit.cover,
      super.key});
  final FileProvider videoFile;
  final int width;
  final int height;
  final bool decodeFirstFrame;
  final bool playOnOpen;
  final double initialVolume;
  final BoxFit fit;
  final VideoPlayerController controller;
  @override
  State<VideoPlayerImplementation> createState() =>
      _VideoPlayerImplementationState();
}

class _VideoPlayerImplementationState extends State<VideoPlayerImplementation> {
  late Player player;
  VideoController? controller;
  bool loaded = false;
  Uri? file;

  @override
  void initState() {
    super.initState();

    player = Player();

    widget.controller.attach(
        pause: pause,
        play: play,
        replay: replay,
        screenshot: screenshot,
        setVolume: setVolume,
        getSize: getSize,
        seekTo: seekTo,
        getLength: getLength);

    player.stream.position.listen((event) {
      widget.controller.setProgress(event);
    });

    player.stream.completed.listen(
      (completed) {
        widget.controller.setCompleted(completed);
      },
    );

    controller = VideoController(player);

    Future.microtask(() async {
      StreamSubscription<DownloadProgress>? sub;
      try {
        widget.controller.setBuffering(true);
        sub = widget.videoFile.onProgressChanged?.listen((data) {
          widget.controller.setBufferingProgress(data);
        });
        final resolved = await widget.videoFile.resolve();
        await sub?.cancel();
        sub = null;

        if (resolved == null) {
          throw StateError('Video media could not be resolved');
        }

        file = resolved;
        await setVolume(widget.initialVolume);
        await player.open(
          Playlist([Media(resolved.toString())]),
          play: widget.playOnOpen,
        );

        if (!mounted) {
          return;
        }
        setState(() {
          loaded = true;
        });
        widget.controller.setBuffering(false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            widget.controller.setReady();
          }
        });
      } catch (error, stackTrace) {
        await sub?.cancel();
        widget.controller.setBuffering(false);
        widget.controller.setError(error);
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to load video media',
        );
      }
    });
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loaded) {
      return Video(
        fit: widget.fit,
        controller: controller!,
        controls: null,
      );
    }
    return Container();
  }

  Future<void> pause() async {
    player.pause();
  }

  Future<void> play() async {
    player.play();
  }

  Future<Uint8List?> screenshot() async {
    return player.screenshot();
  }

  Future<void> replay() async {
    await player.seek(Duration.zero);
    await player.play();
  }

  Future<void> seekTo(Duration duration) async {
    await player.seek(duration);
  }

  Future<void> setVolume(double volume) async {
    await player.setVolume(volume.clamp(0, 100).toDouble());
  }

  Future<Duration> getLength() async {
    return player.state.duration;
  }

  Future<Size?> getSize() async {
    if (player.state.height == null || player.state.width == null) {
      return null;
    }

    return Size(
        player.state.width!.toDouble(), player.state.height!.toDouble());
  }
}
