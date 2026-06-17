import 'package:flutter/material.dart';

class NotificationBadge extends StatelessWidget {
  const NotificationBadge(this.count,
      {super.key, this.size = 15, this.exclamation = false});
  final double size;
  final int count;
  final bool exclamation;

  @override
  Widget build(BuildContext context) {
    const alertOrange = Color(0xFFFF8A00);

    return SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size / 2),
              color: exclamation ? alertOrange : Colors.red.shade600),
          child: Center(
            child: Text(
              exclamation
                  ? "!"
                  : count > 9
                      ? "9+"
                      : count.toString(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  color: Colors.white,
                  shadows: [const BoxShadow(blurRadius: 2)]),
            ),
          ),
        ));
  }
}
