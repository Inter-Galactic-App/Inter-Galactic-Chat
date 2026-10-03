import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_view_entry.dart';

/// A custom message background image is painted behind the whole timeline
/// (`ChatView.messageBackground`), so anything the timeline paints on top of it
/// with a fully opaque colour does not tint that area - it replaces the user's
/// wallpaper there with a theme token.
///
/// That is what the jump-to-message highlight used to do: an opaque
/// `surfaceContainer` fill over the highlighted row. The highlight itself is
/// wanted; blanking the wallpaper under it is not. Owner report, 2026-09-03.
///
/// The second test is the one that is easy to lose. Every colour role is
/// independently user-authored in a custom theme and nothing validates
/// contrast, so a fill keyed to `primary` puts an arbitrary hue under body text
/// with no bound. The fill has to come off the same surface ramp `onSurface` is
/// already read against. That was an actual first attempt here, not a
/// hypothetical.
void main() {
  const light = ColorScheme.light();
  const dark = ColorScheme.dark();
  const schemes = [light, dark];

  test(
    'the highlight fill is translucent so a background image shows through',
    () {
      for (final colors in schemes) {
        final fill = TimelineViewEntryState.highlightDecoration(colors).color;

        expect(fill, isNotNull);
        expect(
          fill!.a,
          lessThan(1.0),
          reason:
              'an opaque fill covers the custom message background image for the '
              'highlighted row instead of tinting it',
        );
        expect(
          fill.a,
          greaterThan(0.0),
          reason: 'a fully transparent fill is no highlight at all',
        );
      }
    },
  );

  test('the highlight fill comes off the surface ramp, not the accent', () {
    for (final colors in schemes) {
      final fill = TimelineViewEntryState.highlightDecoration(colors).color!;

      expect(
        fill.withValues(alpha: 1.0),
        colors.surfaceContainerHighest,
        reason:
            'the fill must be a surface role. Custom themes set every role '
            'independently with no contrast validation, so a primary-derived '
            'wash under body text has no bound.',
      );
    }
  });

  test('the highlight is still visibly a highlight', () {
    for (final colors in schemes) {
      final decoration = TimelineViewEntryState.highlightDecoration(colors);

      // The accent border is the part of the cue that survives any wallpaper,
      // so it stays at full strength and the fill does not have to be strong.
      final left = (decoration.border as Border).left;
      expect(left.width, greaterThan(0.0));
      expect(left.color.a, 1.0);
    }
  });
}
