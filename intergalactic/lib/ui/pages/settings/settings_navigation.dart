import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart' as c;
import 'package:flutter/material.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';

class SettingsNavigation {
  /// Wraps a settings route in the Scaffold its SnackBars are drawn by.
  ///
  /// Settings pages report failures through
  /// `ScaffoldMessenger.maybeOf(context)?.showSnackBar(...)`, and no settings
  /// route registered a Scaffold, so those messages were queued and drawn
  /// nowhere. The Scaffold carries no chrome: transparent, so the page keeps
  /// painting its own background, and `resizeToAvoidBottomInset: false` so the
  /// keyboard behaves exactly as it did before the wrapper existed.
  ///
  /// The local [ScaffoldMessenger] is what keeps the desktop overlay looking
  /// unchanged. That route is `opaque: false`, so `MainPage`'s Scaffold is
  /// still mounted and visible behind it, and a messenger presents a SnackBar
  /// on *every* registered root Scaffold at once - a settings message would
  /// have drawn a second time, behind the barrier, at the bottom of the
  /// screen. Scoping the messenger to this route keeps it in this route.
  static Widget _settingsSnackBarSurface(Widget page) {
    return ScaffoldMessenger(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: page,
      ),
    );
  }

  static Future<T?> show<T>(BuildContext context, Widget page) {
    final reduceMotion = InterGalacticMotion.shouldReduce(context);
    final surface = _settingsSnackBarSurface(page);

    if (!Layout.desktop) {
      if (PlatformUtils.isIOS) {
        return Navigator.of(
          context,
        ).push<T>(c.CupertinoPageRoute<T>(builder: (_) => surface));
      }

      return Navigator.of(context).push<T>(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => surface,
          transitionDuration: InterGalacticMotion.duration(
            context,
            InterGalacticMotion.mobileRoute,
          ),
          transitionsBuilder: (_, animation, __, child) {
            if (reduceMotion) {
              return child;
            }

            return SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 1.5),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: InterGalacticMotion.standardOut,
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
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        barrierColor: Colors.black.withValues(alpha: 0.34),
        transitionDuration: InterGalacticMotion.duration(
          context,
          InterGalacticMotion.settingsOverlayIn,
        ),
        reverseTransitionDuration: InterGalacticMotion.duration(
          context,
          InterGalacticMotion.settingsOverlayOut,
        ),
        pageBuilder: (_, __, ___) {
          return _DesktopSettingsOverlay(child: surface);
        },
        transitionsBuilder: (_, animation, __, child) {
          if (reduceMotion) {
            return child;
          }

          final curvedAnimation = CurvedAnimation(
            parent: animation,
            curve: InterGalacticMotion.standardOut,
            reverseCurve: InterGalacticMotion.standardIn,
          );

          return FadeTransition(
            opacity: curvedAnimation,
            child: ScaleTransition(
              scale: Tween<double>(
                begin: 0.985,
                end: 1,
              ).animate(curvedAnimation),
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
    final reduceTransparency = AccessibilityScope.of(
      context,
    ).reduceTransparency;

    final overlay = SafeArea(
      minimum: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxFrameWidth = math.max(320.0, constraints.maxWidth - 48);
          final maxFrameHeight = math.max(360.0, constraints.maxHeight - 48);
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
                    color: theme.colorScheme.outline.withValues(alpha: 0.32),
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
    );

    return Material(
      color: Colors.transparent,
      child: reduceTransparency
          ? overlay
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 1.4, sigmaY: 1.4),
              child: overlay,
            ),
    );
  }
}
