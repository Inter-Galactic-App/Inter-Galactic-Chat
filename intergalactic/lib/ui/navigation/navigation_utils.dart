import 'package:flutter/material.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';

class NavigationUtils {
  static void navigateTo(BuildContext context, Widget page) {
    final reduceMotion = InterGalacticMotion.shouldReduce(context);

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: InterGalacticMotion.duration(
          context,
          InterGalacticMotion.mobileRoute,
        ),
        transitionsBuilder: (_, animation, __, child) {
          if (reduceMotion) {
            return child;
          }

          return SlideTransition(
            position: Tween<Offset>(
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
}
