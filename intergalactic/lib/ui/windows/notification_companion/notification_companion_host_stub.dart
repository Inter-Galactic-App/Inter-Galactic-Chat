import 'package:flutter/material.dart';

bool get supportsNotificationCompanionOverlay => false;

class NotificationCompanionHost extends StatelessWidget {
  const NotificationCompanionHost({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
