import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:intergalactic/ui/mobile/mobile_visuals.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

enum MobileGlassHighlightStyle { standard, composer }

/// Rounded mobile section surface for settings or grouped controls.
class MobileSectionCard extends StatelessWidget {
  const MobileSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(8),
    this.mode = tiamat.TileType.surfaceContainerLow,
    this.highlightStyle = MobileGlassHighlightStyle.standard,
    this.highlightIntensity = 1,
  });

  final Widget child;
  final EdgeInsets padding;
  final tiamat.TileType mode;
  final MobileGlassHighlightStyle highlightStyle;
  final double highlightIntensity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reduceTransparency =
        AccessibilityScope.of(context).reduceTransparency;
    final useLiquidGlassFallback = PlatformUtils.isIOS && !reduceTransparency;
    final baseSurface = _surfaceForMode(scheme, mode);
    final radius = MobileVisuals.cardBorderRadius;
    final effectiveHighlightIntensity = useLiquidGlassFallback
        ? (highlightIntensity * 0.58).clamp(0.0, 1.0).toDouble()
        : highlightIntensity;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha:
                  useLiquidGlassFallback ? 0.055 : MobileVisuals.shadowOpacity,
            ),
            blurRadius: useLiquidGlassFallback ? 24 : MobileVisuals.blurRadius,
            offset: Offset(0, useLiquidGlassFallback ? 6 : 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            if (useLiquidGlassFallback)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 18,
                    sigmaY: 18,
                    tileMode: TileMode.mirror,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: useLiquidGlassFallback
                      ? baseSurface.withValues(alpha: 0.62)
                      : reduceTransparency
                          ? baseSurface
                          : null,
                  gradient: reduceTransparency
                      ? null
                      : LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: useLiquidGlassFallback
                              ? [
                                  scheme.surfaceContainerHighest.withValues(
                                    alpha: 0.16,
                                  ),
                                  baseSurface.withValues(alpha: 0.54),
                                  scheme.surfaceContainerLowest.withValues(
                                    alpha: 0.36,
                                  ),
                                ]
                              : [
                                  scheme.surfaceContainerHighest.withValues(
                                    alpha: MobileVisuals.highlightOpacity,
                                  ),
                                  scheme.surface.withValues(alpha: 0.02),
                                ],
                          stops: useLiquidGlassFallback
                              ? const [0, 0.52, 1]
                              : null,
                        ),
                  border: Border.all(
                    color: scheme.outline.withValues(
                      alpha: useLiquidGlassFallback
                          ? 0.045
                          : reduceTransparency
                              ? 0.18
                              : MobileVisuals.strokeOpacity,
                    ),
                  ),
                ),
              ),
            ),
            if (useLiquidGlassFallback || reduceTransparency)
              Padding(padding: padding, child: child)
            else
              tiamat.Tile(
                mode: mode,
                child: Padding(padding: padding, child: child),
              ),
            Positioned.fill(
              child: MobileGlassEdgeHighlight(
                borderRadius: radius,
                enabled: !reduceTransparency,
                style: highlightStyle,
                intensity: effectiveHighlightIntensity,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A mobile-friendly list action with a pill silhouette.
class MobilePillButton extends StatelessWidget {
  const MobilePillButton({
    super.key,
    required this.label,
    this.icon,
    this.highlighted = false,
    this.color,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool highlighted;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;
    final reduceTransparency =
        AccessibilityScope.of(context).reduceTransparency;
    final useLiquidGlassFallback = PlatformUtils.isIOS && !reduceTransparency;
    final solidBackground = highlighted
        ? Color.alphaBlend(
            accent.withValues(alpha: 0.18),
            scheme.surfaceContainerHigh,
          )
        : scheme.surfaceContainerLow;

    return SizedBox(
      height: MobileVisuals.listItemHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: MobileVisuals.pillBorderRadius,
          color: reduceTransparency ? solidBackground : null,
          gradient: reduceTransparency
              ? null
              : LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: highlighted
                      ? [
                          accent.withValues(
                            alpha: useLiquidGlassFallback ? 0.18 : 0.24,
                          ),
                          accent.withValues(
                            alpha: useLiquidGlassFallback ? 0.09 : 0.14,
                          ),
                        ]
                      : [
                          scheme.surfaceContainerHighest.withValues(
                            alpha: useLiquidGlassFallback ? 0.15 : 0.14,
                          ),
                          scheme.surfaceContainerLow.withValues(
                            alpha: useLiquidGlassFallback ? 0.07 : 0.08,
                          ),
                        ],
                ),
          border: Border.all(
            color: highlighted
                ? accent.withValues(
                    alpha: reduceTransparency
                        ? 1
                        : useLiquidGlassFallback
                            ? 0.16
                            : 0.24,
                  )
                : scheme.outline.withValues(
                    alpha: reduceTransparency
                        ? 0.28
                        : useLiquidGlassFallback
                            ? 0.045
                            : 0.12,
                  ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: useLiquidGlassFallback ? 0.035 : 0.08,
              ),
              blurRadius: useLiquidGlassFallback ? 18 : 12,
              offset: Offset(0, useLiquidGlassFallback ? 4 : 4),
            ),
          ],
        ),
        child: MobileGlassEdgeHighlight(
          borderRadius: MobileVisuals.pillBorderRadius,
          enabled: !reduceTransparency,
          highlighted: highlighted,
          intensity: useLiquidGlassFallback ? 0.55 : 1,
          child: ClipRRect(
            borderRadius: MobileVisuals.pillBorderRadius,
            child: useLiquidGlassFallback || reduceTransparency
                ? Material(
                    color: Colors.transparent,
                    child: _MobilePillButtonLabel(
                      label: label,
                      icon: icon,
                      highlighted: highlighted,
                      onTap: onTap,
                      color: color,
                    ),
                  )
                : tiamat.Tile.low(
                    child: _MobilePillButtonLabel(
                      label: label,
                      icon: icon,
                      highlighted: highlighted,
                      onTap: onTap,
                      color: color,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _MobilePillButtonLabel extends StatelessWidget {
  const _MobilePillButtonLabel({
    required this.label,
    required this.highlighted,
    this.icon,
    this.color,
    this.onTap,
  });

  final String label;
  final IconData? icon;
  final bool highlighted;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return tiamat.TextButton(
      label,
      icon: icon,
      highlighted: highlighted,
      onTap: onTap,
      textColor: color,
      iconColor: color,
      highlightColor: PlatformUtils.isIOS ? Colors.transparent : null,
    );
  }
}

class MobileGlassEdgeHighlight extends StatelessWidget {
  const MobileGlassEdgeHighlight({
    super.key,
    required this.borderRadius,
    this.enabled = true,
    this.highlighted = false,
    this.style = MobileGlassHighlightStyle.standard,
    this.intensity = 1,
    this.child,
  });

  final BorderRadius borderRadius;
  final bool enabled;
  final bool highlighted;
  final MobileGlassHighlightStyle style;
  final double intensity;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final reduceTransparency =
        AccessibilityScope.maybeOf(context)?.reduceTransparency ?? false;
    if (!enabled || reduceTransparency) {
      return child ?? const SizedBox.shrink();
    }

    final painter = _MobileGlassEdgePainter(
      borderRadius: borderRadius,
      accent: Theme.of(context).colorScheme.primary,
      highlighted: highlighted,
      style: style,
      intensity: intensity,
      liquidGlassFallback: PlatformUtils.isIOS,
    );

    final highlight = IgnorePointer(child: CustomPaint(painter: painter));

    if (child == null) {
      return highlight;
    }

    return Stack(
      children: [
        child!,
        Positioned.fill(child: highlight),
      ],
    );
  }
}

class _MobileGlassEdgePainter extends CustomPainter {
  const _MobileGlassEdgePainter({
    required this.borderRadius,
    required this.accent,
    required this.highlighted,
    required this.style,
    required this.intensity,
    required this.liquidGlassFallback,
  });

  final BorderRadius borderRadius;
  final Color accent;
  final bool highlighted;
  final MobileGlassHighlightStyle style;
  final double intensity;
  final bool liquidGlassFallback;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect.deflate(0.75));
    final opacityScale = intensity.clamp(0.0, 1.0).toDouble();
    final edgeOpacity = (highlighted
            ? MobileVisuals.edgeHighlightOpacity + 0.08
            : MobileVisuals.edgeHighlightOpacity) *
        opacityScale;
    if (style == MobileGlassHighlightStyle.composer) {
      final composerEdgeOpacity =
          liquidGlassFallback ? edgeOpacity * 0.92 : edgeOpacity;
      _paintComposer(canvas, rect, rrect, composerEdgeOpacity);
      return;
    }

    final resolvedEdgeOpacity =
        liquidGlassFallback ? edgeOpacity * 0.72 : edgeOpacity;

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = liquidGlassFallback ? 0.9 : 1.15
        ..shader = LinearGradient(
          begin: const Alignment(-0.72, -1),
          end: const Alignment(1, 0.58),
          colors: [
            Colors.white.withValues(alpha: resolvedEdgeOpacity),
            Colors.white.withValues(alpha: resolvedEdgeOpacity * 0.32),
            Colors.white.withValues(alpha: 0),
          ],
          stops: liquidGlassFallback ? const [0, 0.38, 1] : const [0, 0.46, 1],
        ).createShader(rect),
    );

    canvas.drawRRect(
      rrect.deflate(0.45),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = liquidGlassFallback ? 0.45 : 0.65
        ..shader = LinearGradient(
          begin: const Alignment(-0.58, -1),
          end: const Alignment(0.92, 0.72),
          colors: [
            Colors.white.withValues(alpha: resolvedEdgeOpacity * 0.22),
            accent.withValues(alpha: highlighted ? 0.11 : 0.02),
            Colors.black.withValues(
              alpha: liquidGlassFallback
                  ? MobileVisuals.edgeShadowOpacity * 0.45
                  : MobileVisuals.edgeShadowOpacity,
            ),
          ],
          stops: const [0, 0.5, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_MobileGlassEdgePainter oldDelegate) {
    return borderRadius != oldDelegate.borderRadius ||
        accent != oldDelegate.accent ||
        highlighted != oldDelegate.highlighted ||
        style != oldDelegate.style ||
        intensity != oldDelegate.intensity ||
        liquidGlassFallback != oldDelegate.liquidGlassFallback;
  }

  void _paintComposer(
    Canvas canvas,
    Rect rect,
    RRect rrect,
    double edgeOpacity,
  ) {
    final baseRect = rect.inflate(2);

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: edgeOpacity * 0.32),
            Colors.white.withValues(alpha: edgeOpacity * 0.12),
            Colors.black.withValues(
              alpha: MobileVisuals.edgeShadowOpacity * 0.55,
            ),
          ],
          stops: const [0, 0.52, 1],
        ).createShader(baseRect),
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25
        ..shader = LinearGradient(
          begin: const Alignment(-0.78, -1),
          end: const Alignment(0.84, -0.42),
          colors: [
            Colors.white.withValues(alpha: edgeOpacity * 0.82),
            Colors.white.withValues(alpha: edgeOpacity * 0.44),
            Colors.white.withValues(alpha: edgeOpacity * 0.14),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.34, 0.7, 1],
        ).createShader(baseRect),
    );

    canvas.drawRRect(
      rrect.deflate(0.15),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..shader = RadialGradient(
          center: const Alignment(0.72, 0.82),
          radius: 0.9,
          colors: [
            Colors.white.withValues(alpha: edgeOpacity * 0.32),
            Colors.white.withValues(alpha: edgeOpacity * 0.12),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0, 0.42, 1],
        ).createShader(baseRect),
    );

    canvas.drawRRect(
      rrect.deflate(0.35),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..shader = LinearGradient(
          begin: const Alignment(-0.82, 0.16),
          end: const Alignment(0.88, 1),
          colors: [
            Colors.transparent,
            Colors.black.withValues(
              alpha: MobileVisuals.edgeShadowOpacity * 0.12,
            ),
            Colors.black.withValues(
              alpha: MobileVisuals.edgeShadowOpacity * 0.48,
            ),
          ],
          stops: const [0, 0.64, 1],
        ).createShader(baseRect),
    );
  }
}

Color _surfaceForMode(ColorScheme scheme, tiamat.TileType mode) {
  return switch (mode) {
    tiamat.TileType.surface => scheme.surface,
    tiamat.TileType.surfaceContainer => scheme.surfaceContainer,
    tiamat.TileType.surfaceContainerLow => scheme.surfaceContainerLow,
    tiamat.TileType.surfaceContainerLowest => scheme.surfaceContainerLowest,
    tiamat.TileType.surfaceContainerHigh => scheme.surfaceContainerHigh,
    tiamat.TileType.surfaceContainerHighest => scheme.surfaceContainerHighest,
    tiamat.TileType.surfaceDim => scheme.surfaceDim,
  };
}
