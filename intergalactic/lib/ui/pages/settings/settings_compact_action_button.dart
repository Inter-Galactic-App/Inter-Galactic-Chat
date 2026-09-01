import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class SettingsCompactActionButton extends StatelessWidget {
  const SettingsCompactActionButton({
    required this.label,
    required this.onTap,
    this.semanticLabel,
    this.width = 104,
    this.height = 44,
    super.key,
  });

  final String label;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: width,
      height: height,
      child: tiamat.Button.secondary(
        text: label,
        onTap: onTap,
      ),
    );

    return Semantics(
      label: semanticLabel ?? label,
      button: true,
      enabled: onTap != null,
      onTap: onTap,
      child: ExcludeSemantics(child: button),
    );
  }
}
