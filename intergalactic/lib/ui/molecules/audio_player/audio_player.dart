import 'dart:async';
import 'dart:math' as math;

import 'package:intergalactic/cache/file_provider.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:intergalactic/utils/text_utils.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

class AudioPlayer extends StatefulWidget {
  const AudioPlayer({
    required this.file,
    this.fileName,
    this.fileSize,
    this.duration,
    this.bubbleColor,
    super.key,
  });

  final String? fileName;
  final int? fileSize;
  final Duration? duration;
  final Color? bubbleColor;
  final FileProvider file;

  @override
  State<AudioPlayer> createState() => _AudioPlayerState();
}

enum AudioPlayerState { paused, loading, playing }

class _AudioPlayerState extends State<AudioPlayer> {
  Player player = Player();
  late List<StreamSubscription> subs;

  @override
  void initState() {
    super.initState();

    subs = [
      player.stream.playing.listen(onPlayingChanged),
      player.stream.position.listen(onPositionChanged),
      if (widget.file.onProgressChanged != null)
        widget.file.onProgressChanged!.listen(onDownloadProgressChanged),
    ];
  }

  @override
  void dispose() {
    for (var sub in subs) {
      sub.cancel();
    }

    player.dispose();

    super.dispose();
  }

  var state = AudioPlayerState.paused;

  bool dragging = false;

  double displayPosition = 0;
  double? downloadProgress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = widget.bubbleColor ?? scheme.surfaceContainerLow;
    final foreground = AccessibilityScope.tokensOf(context)
        .resolveIdentityTextColor(
          scheme.onSurface,
          scheme,
          background: background,
          minimumContrast: 4.5,
        );
    final buttonBackground = foreground.withValues(alpha: 0.95);
    final buttonForeground = AccessibilityScope.tokensOf(context)
        .resolveIdentityTextColor(
          background,
          scheme,
          background: buttonBackground,
          minimumContrast: 4.5,
        );
    final tooltip = _attachmentDetailsLabel();

    final bubble = SelectionContainer.disabled(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 214, maxWidth: 310),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.45),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(7, 6, 11, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _VoicePlayButton(
                  state: state,
                  progress: downloadProgress,
                  background: buttonBackground,
                  foreground: buttonForeground,
                  onPressed: onPlayButtonPressed,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 30,
                    child: CustomPaint(
                      painter: _VoiceWaveformPainter(
                        color: foreground,
                        inactiveColor: foreground.withValues(alpha: 0.34),
                        progress: displayPosition,
                        seed: _waveSeed,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _durationLabel(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: foreground,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (tooltip.isEmpty) {
      return bubble;
    }

    return Semantics(label: tooltip, child: bubble);
  }

  onPlayButtonPressed() {
    if (state == AudioPlayerState.paused) {
      if (player.state.playlist.medias.isEmpty) {
        setState(() {
          state = AudioPlayerState.loading;
          loadAudio();
        });
      } else {
        player.play();
      }
    }

    if (state == AudioPlayerState.playing) {
      player.pause();
      setState(() {
        state = AudioPlayerState.paused;
      });
    }
  }

  void loadAudio() async {
    try {
      var uri = await widget.file.resolve();

      if (uri == null) {
        if (!mounted) {
          return;
        }

        setState(() {
          state = AudioPlayerState.paused;
        });
        return;
      }

      await player.open(Media(uri.toString()));
      player.setPlaylistMode(PlaylistMode.none);

      if (!mounted) {
        return;
      }

      setState(() {
        state = AudioPlayerState.playing;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        state = AudioPlayerState.paused;
      });
    }
  }

  void onPlayingChanged(bool event) {
    if (!mounted) {
      return;
    }

    if (event) {
      setState(() {
        state = AudioPlayerState.playing;
      });
    } else {
      setState(() {
        state = AudioPlayerState.paused;
      });
    }
  }

  void onPositionChanged(Duration event) {
    if (!mounted) {
      return;
    }

    if (!dragging) {
      setState(() {
        final duration = player.state.duration;
        if (duration <= Duration.zero) {
          displayPosition = 0;
          return;
        }

        var pos =
            event.inMilliseconds.toDouble() /
            duration.inMilliseconds.toDouble();

        if (pos >= 0 && pos <= 1) {
          displayPosition = pos;
        }
      });
    }
  }

  void onDownloadProgressChanged(DownloadProgress event) {
    if (!mounted) {
      return;
    }

    setState(() {
      downloadProgress = event.downloaded.toDouble() / event.total.toDouble();
    });
  }

  int get _waveSeed => (widget.fileName ?? widget.file.hashCode.toString())
      .codeUnits
      .fold<int>(0, (value, codeUnit) => value + codeUnit);

  Duration get _visibleDuration {
    if (player.state.duration > Duration.zero) {
      return player.state.duration;
    }

    return widget.duration ?? Duration.zero;
  }

  String _durationLabel() {
    final duration = _visibleDuration;
    if (duration <= Duration.zero) {
      return '--:--';
    }

    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }

    return '$minutes:$seconds';
  }

  String _attachmentDetailsLabel() {
    final parts = <String>[];
    if (widget.fileName?.trim().isNotEmpty == true) {
      parts.add(widget.fileName!.trim());
    }

    if (widget.fileSize != null) {
      parts.add(TextUtils.readableFileSize(widget.fileSize!));
    }

    return parts.join(' - ');
  }
}

class _VoicePlayButton extends StatelessWidget {
  const _VoicePlayButton({
    required this.state,
    required this.background,
    required this.foreground,
    required this.onPressed,
    this.progress,
  });

  final AudioPlayerState state;
  final Color background;
  final Color foreground;
  final double? progress;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 29,
      height: 29,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: state == AudioPlayerState.loading ? null : onPressed,
          child: Center(
            child: state == AudioPlayerState.loading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: progress,
                      color: foreground,
                    ),
                  )
                : Icon(
                    state == AudioPlayerState.paused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                    color: foreground,
                    size: 21,
                  ),
          ),
        ),
      ),
    );
  }
}

class _VoiceWaveformPainter extends CustomPainter {
  const _VoiceWaveformPainter({
    required this.color,
    required this.inactiveColor,
    required this.progress,
    required this.seed,
  });

  final Color color;
  final Color inactiveColor;
  final double progress;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }

    final barCount = (size.width / 5).floor().clamp(18, 42).toInt();
    final step = size.width / barCount;
    final barWidth = math.min(2.6, step * 0.5);
    final minHeight = size.height * 0.2;
    final maxHeight = size.height * 0.9;
    final playedCutoff = (barCount - 1) * progress.clamp(0, 1).toDouble();

    for (var index = 0; index < barCount; index++) {
      final phase = index + (seed % 31);
      final wave =
          (math.sin(phase * 0.76).abs() * 0.62) +
          (math.cos(phase * 1.43).abs() * 0.38);
      final normalized = 0.18 + (wave % 1) * 0.82;
      final height = minHeight + (maxHeight - minHeight) * normalized;
      final x = index * step + (step - barWidth) / 2;
      final y = (size.height - height) / 2;
      final paint = Paint()
        ..color = index <= playedCutoff ? color : inactiveColor
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, height),
          Radius.circular(barWidth),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWaveformPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.progress != progress ||
        oldDelegate.seed != seed;
  }
}
