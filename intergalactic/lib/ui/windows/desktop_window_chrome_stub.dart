import 'package:flutter/widgets.dart';

class DesktopWindowFrame extends StatelessWidget {
  const DesktopWindowFrame({
    required this.child,
    this.navigatorKey,
    this.showNavigation = true,
    this.showHelp = true,
    this.showSmallWindowToggle = true,
    super.key,
  });

  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;
  final bool showNavigation;
  final bool showHelp;
  final bool showSmallWindowToggle;

  @override
  Widget build(BuildContext context) => child;
}
