import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/activity/game_activity_overlay.dart';
import 'package:intergalactic/client/components/voip/voip_stream.dart';
import 'package:intergalactic/ui/organisms/activity/game_activity_overlay_pill.dart';
import 'package:intergalactic/ui/organisms/call_view/voip_stream_view.dart';

void main() {
  test(
    'stream tile subscription cancellation failures are recovered',
    () async {
      final subscription = _FailingCancelSubscription();

      await expectLater(
        debugCancelVoipStreamViewSubscriptionForTesting(subscription),
        completes,
      );

      expect(subscription.cancelAttempts, 1);
    },
  );

  test('stream tile game pill falls back to remote presence summary', () {
    final pill = debugGameActivityPillForTesting(
      presenceText: formatGameActivityPresenceSummary('Meccha Chameleons'),
    );

    expect(pill, isA<GameActivityOverlayPill>());
    final typed = pill! as GameActivityOverlayPill;
    expect(typed.title, 'Meccha Chameleons');
    expect(typed.artworkUrl, isNull);
  });

  test('stream tile game pill prefers local rich activity over presence', () {
    final pill = debugGameActivityPillForTesting(
      activity: const UserActivity(
        id: 'steam',
        kind: ActivityKind.game,
        provider: 'steam',
        title: 'Cult of the Lamb',
        artworkUrl: 'https://example.invalid/cult.png',
      ),
      presenceText: formatGameActivityPresenceSummary('Other Game'),
    );

    expect(pill, isA<GameActivityOverlayPill>());
    final typed = pill! as GameActivityOverlayPill;
    expect(typed.title, 'Cult of the Lamb');
    expect(typed.artworkUrl, 'https://example.invalid/cult.png');
  });

  test('local screenshare stream options menu is shown when actions exist', () {
    expect(
      debugShouldShowLocalStreamOptionsMenuForTesting(
        isLocalUser: true,
        streamType: VoipStreamType.screenshare,
        isVideoHidden: false,
        hasStopStreaming: true,
        hasQualitySelection: false,
        hasAudioSharingSelection: false,
      ),
      isTrue,
    );
  });

  test('stream options menu stays off for remote or hidden tiles', () {
    expect(
      debugShouldShowLocalStreamOptionsMenuForTesting(
        isLocalUser: false,
        streamType: VoipStreamType.screenshare,
        isVideoHidden: false,
        hasStopStreaming: true,
        hasQualitySelection: true,
        hasAudioSharingSelection: true,
      ),
      isFalse,
    );
    expect(
      debugShouldShowLocalStreamOptionsMenuForTesting(
        isLocalUser: true,
        streamType: VoipStreamType.screenshare,
        isVideoHidden: true,
        hasStopStreaming: true,
        hasQualitySelection: true,
        hasAudioSharingSelection: true,
      ),
      isFalse,
    );
    expect(
      debugShouldShowLocalStreamOptionsMenuForTesting(
        isLocalUser: true,
        streamType: VoipStreamType.video,
        isVideoHidden: false,
        hasStopStreaming: true,
        hasQualitySelection: true,
        hasAudioSharingSelection: true,
      ),
      isFalse,
    );
  });

  test('stream tile actions remain visible while stream menu is open', () {
    expect(
      debugShouldKeepStreamTileActionsVisibleForTesting(
        mobile: false,
        hovering: false,
        streamMenuOpen: true,
        forceActionButtonsVisible: false,
      ),
      isTrue,
    );
    expect(
      debugShouldKeepStreamTileActionsVisibleForTesting(
        mobile: false,
        hovering: false,
        streamMenuOpen: false,
        forceActionButtonsVisible: false,
      ),
      isFalse,
    );
  });

  test('stream menus can use the detached window local overlay', () {
    expect(
      debugShouldUseStreamMenuRootOverlayForTesting(
        useRootOverlayForMenus: true,
      ),
      isTrue,
    );
    expect(
      debugShouldUseStreamMenuRootOverlayForTesting(
        useRootOverlayForMenus: false,
      ),
      isFalse,
    );
  });

  test('auto-paused local preview copy explains the performance pause', () {
    expect(
      debugHiddenPreviewStateLabelForTesting(
        streamType: VoipStreamType.screenshare,
        localPreviewAutoPaused: true,
      ),
      'Stream preview paused',
    );
    expect(
      debugHiddenPreviewActionLabelForTesting(
        streamType: VoipStreamType.screenshare,
        canReveal: true,
        localPreviewAutoPaused: true,
      ),
      'Show preview',
    );
    expect(
      debugHiddenPreviewDetailLabelForTesting(localPreviewAutoPaused: true),
      contains('save performance'),
    );
  });

  test('local preview warning only appears after manual reveal', () {
    expect(
      debugShouldShowLocalPreviewPerformanceWarningForTesting(
        isLocalUser: true,
        streamType: VoipStreamType.screenshare,
        isVideoHidden: false,
        showLocalPreviewPerformanceWarning: true,
      ),
      isTrue,
    );
    expect(
      debugShouldShowLocalPreviewPerformanceWarningForTesting(
        isLocalUser: true,
        streamType: VoipStreamType.screenshare,
        isVideoHidden: true,
        showLocalPreviewPerformanceWarning: true,
      ),
      isFalse,
    );
    expect(
      debugShouldShowLocalPreviewPerformanceWarningForTesting(
        isLocalUser: false,
        streamType: VoipStreamType.screenshare,
        isVideoHidden: false,
        showLocalPreviewPerformanceWarning: true,
      ),
      isFalse,
    );
  });
}

class _FailingCancelSubscription implements StreamSubscription<void> {
  int cancelAttempts = 0;

  @override
  Future<void> cancel() {
    cancelAttempts++;
    throw StateError('stream cancel failed');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
