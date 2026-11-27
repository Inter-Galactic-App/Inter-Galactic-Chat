import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/activity/game_activity_overlay.dart';

void main() {
  group('game activity overlay helpers', () {
    test('extracts game title from Matrix activity presence summary', () {
      final gameSummary = formatGameActivityPresenceSummary(
        'MECCHA Chameleons',
      );

      expect(
        gameActivityTitleFromPresenceText(gameSummary),
        'MECCHA Chameleons',
      );
      expect(formatGameActivityPresenceSummary('   '), isNull);
      expect(
        gameActivityTitleFromPresenceText('Playing MECCHA Chameleons'),
        isNull,
      );
      expect(
        gameActivityTitleFromPresenceText('Playing: Deep Rock Galactic'),
        isNull,
      );
      expect(gameActivityTitleFromPresenceText('Playing'), isNull);
      expect(
        gameActivityTitleFromPresenceText('Listening to Inter Galactic Theme'),
        isNull,
      );
    });

    test('picks first visible game activity for overlays', () {
      const music = UserActivity(
        id: 'spotify',
        kind: ActivityKind.music,
        provider: 'spotify',
        title: 'Inter Galactic Theme',
      );
      const hiddenGame = UserActivity(
        id: 'hidden-game',
        kind: ActivityKind.game,
        provider: 'steam',
        title: 'Hidden Game',
        visibility: ActivityVisibility.off,
      );
      const visibleGame = UserActivity(
        id: 'steam',
        kind: ActivityKind.game,
        provider: 'steam',
        title: 'MECCHA Chameleons',
        artworkUrl: 'https://example.invalid/game.png',
      );

      expect(
        gameActivityForOverlay([music, hiddenGame, visibleGame]),
        visibleGame,
      );
      expect(gameActivityForOverlay([music, hiddenGame]), isNull);
    });
  });
}
