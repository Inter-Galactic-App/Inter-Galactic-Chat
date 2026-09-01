import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/soundboard_settings_page.dart';

void main() {
  test('App Settings soundboard previews use the in-call surface layers', () {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff6750a4),
      brightness: Brightness.dark,
    );

    expect(soundboardPreviewPackSurface(scheme), scheme.surfaceContainer);
    expect(
      soundboardPreviewPackOutline(scheme),
      scheme.outlineVariant.withValues(alpha: 0.42),
    );
    expect(
      soundboardPreviewTileSurface(scheme),
      scheme.surfaceContainerHigh.withValues(alpha: 0.62),
    );
  });
}
