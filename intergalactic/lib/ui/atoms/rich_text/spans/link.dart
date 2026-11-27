import 'package:intergalactic/utils/links/link_utils.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';

class LinkSpan {
  static InlineSpan create(String text,
      {required BuildContext context,
      required String clientId,
      destination,
      TextStyle? style}) {
    final settings = AccessibilityScope.of(context);
    final color = AccessibilityScope.tokensOf(context).linkText;

    return TextSpan(
        text: text,
        style: (style ?? const TextStyle()).copyWith(
          color: color,
          decoration: settings.underlineLinks ? TextDecoration.underline : null,
          decorationColor: color,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () {
            if (destination != null) {
              LinkUtils.open(destination, clientId: clientId, context: context);
            }
          });
  }
}
