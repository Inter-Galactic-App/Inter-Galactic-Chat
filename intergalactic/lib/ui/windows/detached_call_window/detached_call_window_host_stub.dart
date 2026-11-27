import 'package:intergalactic/client/call_manager.dart';
import 'package:flutter/material.dart';

bool get supportsDetachedCallWindows => false;

bool get isDetachedCallWindowPlatformSupported => false;

bool get isDetachedCallWindowingEnabled => false;

bool get wasDetachedCallWindowingForced => false;

String get detachedCallWindowSupportReason => 'unsupported_platform';

class DetachedCallWindowHost extends StatelessWidget {
  const DetachedCallWindowHost({
    super.key,
    required this.callManager,
    required this.child,
  });

  final CallManager callManager;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
