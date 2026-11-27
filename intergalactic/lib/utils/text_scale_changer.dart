import 'package:flutter/material.dart';

class TextScaleChanger extends StatelessWidget {
  const TextScaleChanger({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // AccessibilityScope applies the legacy text scale together with platform
    // scaling and accessibility text-size presets inside MaterialApp.builder.
    return child;
  }
}
