import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';

/// Opens Inbox as a compact desktop catch-up panel or a full-screen mobile
/// route. Main-page ownership stays at the call site; this class only owns the
/// adaptive presentation contract.
class InboxNavigation {
  const InboxNavigation._();

  static Future<T?> show<T>(
    BuildContext context,
    Widget page, {
    FocusNode? returnFocus,
  }) async {
    final result = Layout.desktop
        ? await _showDesktop<T>(context, page)
        : await _showMobile<T>(context, page);
    if (returnFocus?.canRequestFocus ?? false) {
      returnFocus!.requestFocus();
    }
    return result;
  }

  static Future<T?> _showMobile<T>(BuildContext context, Widget page) {
    if (PlatformUtils.isIOS) {
      return Navigator.of(
        context,
      ).push<T>(cupertino.CupertinoPageRoute<T>(builder: (_) => page));
    }

    final reduceMotion = InterGalacticMotion.shouldReduce(context);
    return Navigator.of(context).push<T>(
      PageRouteBuilder<T>(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: InterGalacticMotion.duration(
          context,
          InterGalacticMotion.mobileRoute,
        ),
        transitionsBuilder: (_, animation, __, child) {
          if (reduceMotion) return child;
          return SlideTransition(
            position:
                Tween<Offset>(
                  begin: const Offset(0, 1.15),
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

  static Future<T?> _showDesktop<T>(BuildContext context, Widget page) {
    final reduceMotion = InterGalacticMotion.shouldReduce(context);
    return Navigator.of(context).push<T>(
      PageRouteBuilder<T>(
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
        pageBuilder: (_, __, ___) => _DesktopInboxOverlay(child: page),
        transitionsBuilder: (_, animation, __, child) {
          if (reduceMotion) return child;
          final curved = CurvedAnimation(
            parent: animation,
            curve: InterGalacticMotion.standardOut,
            reverseCurve: InterGalacticMotion.standardIn,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.08, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }
}

class _DesktopInboxOverlay extends StatelessWidget {
  const _DesktopInboxOverlay({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceTransparency = AccessibilityScope.of(
      context,
    ).reduceTransparency;
    return SafeArea(
      minimum: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540, minWidth: 360),
          child: FractionallySizedBox(
            heightFactor: 0.9,
            child: Material(
              color: reduceTransparency
                  ? theme.colorScheme.surfaceContainer
                  : theme.colorScheme.surfaceContainer.withValues(alpha: 0.96),
              borderRadius: BorderRadius.circular(24),
              clipBehavior: Clip.antiAlias,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.32),
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.36),
                      blurRadius: 30,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
