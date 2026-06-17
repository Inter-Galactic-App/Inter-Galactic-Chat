import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

class ConstellationBackground extends StatefulWidget {
  const ConstellationBackground({super.key, this.child});
  final Widget? child;

  @override
  State<ConstellationBackground> createState() =>
      _ConstellationBackgroundState();
}

class _ConstellationBackgroundState extends State<ConstellationBackground> {
  static const _shaderAsset = 'assets/shader/constellation.frag';
  static bool _loadingShader = false;
  static FragmentShader? _shader;
  static Object? _shaderError;

  Timer? _timer;
  Duration? _previousFrameTime;
  double _elapsedSeconds = 0;
  int _slowFrames = 0;
  bool _animate = true;
  bool _reduceMotion = false;

  Future<void> _loadShader() async {
    _loadingShader = true;

    try {
      final program = await FragmentProgram.fromAsset(_shaderAsset);
      _shader = program.fragmentShader();
      _shaderError = null;
    } catch (error) {
      _shaderError = error;
      debugPrint('Inter Galactic login background shader failed: $error');
    } finally {
      _loadingShader = false;
    }

    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void initState() {
    super.initState();
    if (_shader == null && _loadingShader == false && _shaderError == null) {
      _loadShader();
    }

    WidgetsBinding.instance.addPostFrameCallback(_watchFrameRate);

    _timer = Timer.periodic(const Duration(milliseconds: 16), _frameTimer);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.of(context).disableAnimations ||
        TickerMode.valuesOf(context).enabled == false;
  }

  void _frameTimer(Timer timer) {
    if (_animate && _reduceMotion == false && mounted) {
      setState(() {
        _elapsedSeconds += 1 / 60;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_shader == null || _shaderError != null) {
      return _LoginBackgroundFallback(
        colorScheme: scheme,
        child: widget.child,
      );
    }

    return CustomPaint(
      painter: _InterGalacticLoginBackgroundPainter(
        _shader!,
        _elapsedSeconds,
        baseColor: scheme.surface,
        accentColor: scheme.primary,
        glowColor: scheme.secondary,
      ),
      child: SizedBox.expand(child: widget.child),
    );
  }

  void _watchFrameRate(Duration timeStamp) {
    if (_previousFrameTime != null && _reduceMotion == false) {
      final diff = timeStamp - _previousFrameTime!;
      final diffMs = diff.inMilliseconds;
      if (diffMs > 0) {
        final fps = 1000 / diffMs;

        if (fps < 30) {
          _slowFrames += 1;
        } else {
          _slowFrames = 0;
        }

        if (_slowFrames > 10) {
          debugPrint(
            'Inter Galactic login background animation disabled for performance',
          );
          _animate = false;
        }
      }
    }

    if (_animate && _reduceMotion == false) {
      _previousFrameTime = timeStamp;
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback(_watchFrameRate);
      }
    }
  }
}

class _InterGalacticLoginBackgroundPainter extends CustomPainter {
  final FragmentShader shader;
  final double time;
  final Color baseColor;
  final Color accentColor;
  final Color glowColor;

  const _InterGalacticLoginBackgroundPainter(
    this.shader,
    this.time, {
    required this.baseColor,
    required this.accentColor,
    required this.glowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, time);
    _setColor(3, baseColor);
    _setColor(7, accentColor);
    _setColor(11, glowColor);

    paint.shader = shader;
    canvas.drawRect(Offset.zero & size, paint);
  }

  void _setColor(int offset, Color color) {
    shader.setFloat(offset, color.r);
    shader.setFloat(offset + 1, color.g);
    shader.setFloat(offset + 2, color.b);
    shader.setFloat(offset + 3, color.a);
  }

  @override
  bool shouldRepaint(
    covariant _InterGalacticLoginBackgroundPainter oldDelegate,
  ) {
    return oldDelegate.time != time ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.glowColor != glowColor;
  }
}

class _LoginBackgroundFallback extends StatelessWidget {
  const _LoginBackgroundFallback({
    required this.colorScheme,
    this.child,
  });

  final ColorScheme colorScheme;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(colorScheme.surface, colorScheme.primaryContainer, 0.2)!,
            Color.lerp(
              colorScheme.surface,
              colorScheme.secondaryContainer,
              0.12,
            )!,
            colorScheme.surface,
          ],
        ),
      ),
      child: SizedBox.expand(child: child),
    );
  }
}
