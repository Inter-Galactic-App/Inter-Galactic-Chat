import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/activity/game_activity_overlay.dart';
import 'package:intergalactic/ui/organisms/activity/game_activity_overlay_pill.dart';

void main() {
  test('activity factory preserves title casing and artwork', () {
    final pill = GameActivityOverlayPill.maybeFromActivity(
      const UserActivity(
        id: 'steam',
        kind: ActivityKind.game,
        provider: 'steam',
        title: 'Meccha Chameleons',
        artworkUrl: 'https://example.invalid/game.png',
      ),
    );

    expect(pill, isA<GameActivityOverlayPill>());
    final typed = pill! as GameActivityOverlayPill;
    expect(typed.title, 'Meccha Chameleons');
    expect(typed.artworkUrl, 'https://example.invalid/game.png');
  });

  test('presence factory uses published game summary title', () {
    final pill = GameActivityOverlayPill.maybeFromPresenceText(
      formatGameActivityPresenceSummary('Deep Rock Galactic'),
      overlay: false,
    );

    expect(pill, isA<GameActivityOverlayPill>());
    final typed = pill! as GameActivityOverlayPill;
    expect(typed.title, 'Deep Rock Galactic');
    expect(typed.artworkUrl, isNull);
    expect(typed.overlay, isFalse);
  });

  testWidgets('data image artwork is decoded case-insensitively',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: GameActivityOverlayPill(
            title: 'Meccha Chameleons',
            artworkUrl:
                'Data:Image/PNG;Base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADElEQVR42mP8z8AARQAFAAH+AcqaAAAAAElFTkSuQmCC',
            overlay: false,
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<MemoryImage>());
  });

  testWidgets('network artwork keeps its fallback error builder',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: GameActivityOverlayPill(
            title: 'Meccha Chameleons',
            artworkUrl: 'https://example.invalid/game.png',
            overlay: false,
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<NetworkImage>());
    expect(image.errorBuilder, isNotNull);
  });

  testWidgets('semantics label keeps human-readable playing text',
      (tester) async {
    final summary = formatGameActivityPresenceSummary('Deep Rock Galactic')!;

    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: GameActivityOverlayPill(
            title: 'Deep Rock Galactic',
            overlay: false,
          ),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label == 'Playing Deep Rock Galactic',
      ),
      findsOneWidget,
    );
    expect(summary, isNot(contains('ig:game')));
    expect(_visiblePresenceCharacters(summary), 'Playing Deep Rock Galactic');
  });
}

String _visiblePresenceCharacters(String value) {
  const hiddenMarkerCodePoints = {
    0x200B,
    0x200C,
    0x200D,
    0x2060,
    0x2063,
  };
  return String.fromCharCodes(
    value.runes.where((codePoint) {
      return !hiddenMarkerCodePoints.contains(codePoint);
    }),
  );
}
