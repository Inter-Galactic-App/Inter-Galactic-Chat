import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intergalactic/config/layout_config.dart';

class SettingsNavigation {
  static Future<T?> show<T>(BuildContext context, Widget page) {
    if (!Layout.desktop) {
      return Navigator.of(context).push<T>(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => page,
          transitionDuration: const Duration(milliseconds: 500),
          transitionsBuilder: (_, animation, __, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 1.5),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
              ),
              child: child,
            );
          },
        ),
      );
    }

    return Navigator.of(context).push<T>(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierLabel:
            MaterialLocalizations.of(context).modalBarrierDismissLabel,
        barrierColor: Colors.black.withValues(alpha: 0.34),
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 140),
        pageBuilder: (_, __, ___) {
          return _DesktopSettingsOverlay(child: page);
        },
        transitionsBuilder: (_, animation, __, child) {
          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );

          return FadeTransition(
            opacity: curvedAnimation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.985, end: 1).animate(
                curvedAnimation,
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

class _DesktopSettingsOverlay extends StatelessWidget {
  const _DesktopSettingsOverlay({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 1.4, sigmaY: 1.4),
        child: SafeArea(
          minimum: const EdgeInsets.all(24),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxFrameWidth = math.max(
                320.0,
                constraints.maxWidth - 48,
              );
              final maxFrameHeight = math.max(
                360.0,
                constraints.maxHeight - 48,
              );
              final preferredWidth = constraints.maxWidth >= 1500
                  ? constraints.maxWidth * 0.79
                  : constraints.maxWidth * 0.88;
              final preferredHeight = constraints.maxHeight * 0.9;
              final frameWidth = math.min(
                maxFrameWidth,
                math.max(760.0, preferredWidth),
              );
              final frameHeight = math.min(
                maxFrameHeight,
                math.max(560.0, preferredHeight),
              );

              return Center(
                child: SizedBox(
                  width: frameWidth,
                  height: frameHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(
                          alpha: 0.32,
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 34,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(23),
                      child: child,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
