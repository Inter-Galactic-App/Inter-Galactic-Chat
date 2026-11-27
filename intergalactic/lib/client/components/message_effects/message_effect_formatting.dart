import 'package:flutter/material.dart';
import 'package:intergalactic/utils/color_utils.dart';

String rainbowFormattedBody(String message) {
  final characters = message.characters;
  if (characters.isEmpty) {
    return "";
  }

  final formatted = StringBuffer();
  var hue = 0.0;
  for (final char in characters) {
    final color = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0);
    final hexColor = color.toColor().toHexCode();

    hue += 360.0 / characters.length.toDouble();
    formatted.write('<span data-mx-color="$hexColor">$char</span>');
  }

  return formatted.toString();
}
