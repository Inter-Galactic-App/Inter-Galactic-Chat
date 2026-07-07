import 'package:intergalactic/client/components/activity/game_activity_overlay.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_activity_status.dart';
import 'package:test/test.dart';

void main() {
  test('game activity status detection follows presence activity summaries',
      () {
    final gameSummary = formatGameActivityPresenceSummary('Stardew Valley');

    expect(isGameActivityStatusText(gameSummary), isTrue);
    expect(isGameActivityStatusText('Playing Stardew Valley'), isFalse);
    expect(isGameActivityStatusText(' playing: Nebula Drift '), isFalse);
    expect(isGameActivityStatusText('Playing'), isFalse);
    expect(isGameActivityStatusText('Listening to orbitals'), isFalse);
    expect(isGameActivityStatusText('In a call'), isFalse);
    expect(isGameActivityStatusText(null), isFalse);
  });

  test('music activity status detection follows presence activity summaries',
      () {
    expect(isMusicActivityStatusText('Listening to Artist - Song'), isTrue);
    expect(isMusicActivityStatusText(' listening to Orbitals '), isTrue);
    expect(isMusicActivityStatusText('Listening to'), isTrue);
    expect(isMusicActivityStatusText('Listening carefully'), isFalse);
    expect(isMusicActivityStatusText('Playing Stardew Valley'), isFalse);
    expect(isMusicActivityStatusText(null), isFalse);
  });

  test('activity status kind classifies home status badges', () {
    expect(
      homeActivityStatusKindForStatusText(
        formatGameActivityPresenceSummary('Stardew Valley'),
      ),
      HomeActivityStatusKind.game,
    );
    expect(
      homeActivityStatusKindForStatusText('Listening to Artist - Song'),
      HomeActivityStatusKind.music,
    );
    expect(homeActivityStatusKindForStatusText('In a call'), isNull);
    expect(homeActivityStatusKindForStatusText(''), isNull);
  });

  test('home activity bubble text removes redundant activity prefixes', () {
    expect(
      homeActivityStatusBubbleText('Listening to Artist - Song'),
      'Artist - Song',
    );
    expect(
      homeActivityStatusBubbleText(
        formatGameActivityPresenceSummary('Nebula Drift'),
      ),
      'Nebula Drift',
    );
    expect(
      homeActivityStatusBubbleText(
        formatGameActivityPresenceSummary('Baldur\'s Gate 3'),
      ),
      'Baldur\'s Gate 3',
    );
    expect(homeActivityStatusBubbleText('Listening to'), 'Listening to');
    expect(homeActivityStatusBubbleText('In a call'), 'In a call');
    expect(homeActivityStatusBubbleText(''), isNull);
  });
}
