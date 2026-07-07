import 'package:flutter/widgets.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class ThemeListWidget extends StatelessWidget {
  const ThemeListWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: tiamat.Text.labelLow(
        'Custom theme archives are currently unavailable in the web build.',
      ),
    );
  }
}
