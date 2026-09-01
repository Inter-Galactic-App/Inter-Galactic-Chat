import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/organisms/call_view/call_view.dart';

void main() {
  test('call control actions still run through the recovery wrapper', () async {
    var ran = false;

    await debugRunCallViewControlActionForTesting(() {
      ran = true;
    });

    expect(ran, isTrue);
  });

  test('sync call control action failures are recovered', () async {
    await expectLater(
      debugRunCallViewControlActionForTesting(() {
        throw StateError('camera toggle failed');
      }),
      completes,
    );
  });

  test('async call control action failures are recovered', () async {
    await expectLater(
      debugRunCallViewControlActionForTesting(() async {
        throw StateError('mute failed');
      }),
      completes,
    );
  });

  test('a user-pressed control is told when its action failed', () async {
    var failures = 0;

    await debugRunCallViewControlActionForTesting(() {
      throw StateError('leave call failed');
    }, onFailure: () => failures++);

    expect(failures, 1);
  });

  test('a user-pressed control stays quiet when its action succeeds', () async {
    var failures = 0;

    await debugRunCallViewControlActionForTesting(
      () async {},
      onFailure: () => failures++,
    );

    expect(failures, 0);
  });

  test('diagnostic controls without a failure hook stay silent', () async {
    await expectLater(
      debugRunCallViewControlActionForTesting(() async {
        throw StateError('receive priority failed');
      }),
      completes,
    );
  });

  test('stream menu actions report failures when a hook is given', () async {
    var failures = 0;

    await debugRunCallViewStreamMenuActionForTesting(() {
      throw StateError('stop streaming failed');
    }, onFailure: () => failures++);

    expect(failures, 1);
  });

  test('a user-pressed control is told when an ASYNC action failed', () async {
    // The synchronous throws above enter the wrapper's try/catch directly. The
    // normal path for these actions is a returned future that rejects later,
    // which is a different catch site, and nothing covered it.
    var failures = 0;

    await debugRunCallViewControlActionForTesting(() async {
      await Future<void>.delayed(Duration.zero);
      throw StateError('leave call failed asynchronously');
    }, onFailure: () => failures++);

    expect(failures, 1);
  });

  test('stream menu actions report ASYNC failures too', () async {
    var failures = 0;

    await debugRunCallViewStreamMenuActionForTesting(() async {
      await Future<void>.delayed(Duration.zero);
      throw StateError('stop streaming failed asynchronously');
    }, onFailure: () => failures++);

    expect(failures, 1);
  });

  test('mobile picture-in-picture actions use recovered controls', () async {
    var ran = false;

    await debugRunCallViewMobilePictureInPictureActionForTesting(() {
      ran = true;
    });

    expect(ran, isTrue);
  });

  test('compact picture-in-picture participant layout caps grid tiles', () {
    expect(debugCompactPipTileLimitForTesting(0), 0);
    expect(debugCompactPipTileLimitForTesting(1), 1);
    expect(debugCompactPipTileLimitForTesting(2), 2);
    expect(debugCompactPipTileLimitForTesting(3), 3);
    expect(debugCompactPipTileLimitForTesting(6), 4);
  });

  test('sync mobile picture-in-picture failures are recovered', () async {
    await expectLater(
      debugRunCallViewMobilePictureInPictureActionForTesting(() {
        throw StateError('source rect failed');
      }),
      completes,
    );
  });

  test('async mobile picture-in-picture failures are recovered', () async {
    await expectLater(
      debugRunCallViewMobilePictureInPictureActionForTesting(() async {
        throw StateError('pip launch failed');
      }),
      completes,
    );
  });

  test('stream test actions still run through the recovery wrapper', () async {
    var ran = false;

    await debugRunCallViewStreamTestActionForTesting(() {
      ran = true;
    });

    expect(ran, isTrue);
  });

  test('sync stream test action failures are recovered', () async {
    await expectLater(
      debugRunCallViewStreamTestActionForTesting(() {
        throw StateError('stream test failed');
      }),
      completes,
    );
  });

  test('async stream test action failures are recovered', () async {
    await expectLater(
      debugRunCallViewStreamTestActionForTesting(() async {
        throw StateError('stream test future failed');
      }),
      completes,
    );
  });

  test('voice menu actions still run through the recovery wrapper', () async {
    var ran = false;

    await debugRunCallViewVoiceMenuActionForTesting(() {
      ran = true;
    });

    expect(ran, isTrue);
  });

  test('sync voice menu action failures are recovered', () async {
    await expectLater(
      debugRunCallViewVoiceMenuActionForTesting(() {
        throw StateError('device switch failed');
      }),
      completes,
    );
  });

  test('async voice menu action failures are recovered', () async {
    await expectLater(
      debugRunCallViewVoiceMenuActionForTesting(() async {
        throw StateError('volume apply failed');
      }),
      completes,
    );
  });

  test('stream menu actions still run through the recovery wrapper', () async {
    var ran = false;

    await debugRunCallViewStreamMenuActionForTesting(() {
      ran = true;
    });

    expect(ran, isTrue);
  });

  test('sync stream menu action failures are recovered', () async {
    await expectLater(
      debugRunCallViewStreamMenuActionForTesting(() {
        throw StateError('stream republish failed');
      }),
      completes,
    );
  });

  test('async stream menu action failures are recovered', () async {
    await expectLater(
      debugRunCallViewStreamMenuActionForTesting(() async {
        throw StateError('stream audio republish failed');
      }),
      completes,
    );
  });

  test('mobile call controls pin hang up when the rail overflows', () {
    expect(
      debugShouldPinMobileHangUpControlForTesting(
        mobile: true,
        hasHangUpControl: true,
        scrollableControlCount: 8,
        maxDockWidth: 320,
      ),
      isTrue,
    );

    expect(
      debugShouldPinMobileHangUpControlForTesting(
        mobile: true,
        hasHangUpControl: true,
        scrollableControlCount: 2,
        maxDockWidth: 420,
      ),
      isFalse,
    );

    expect(
      debugShouldPinMobileHangUpControlForTesting(
        mobile: false,
        hasHangUpControl: true,
        scrollableControlCount: 8,
        maxDockWidth: 320,
      ),
      isFalse,
    );

    expect(
      debugShouldPinMobileHangUpControlForTesting(
        mobile: true,
        hasHangUpControl: false,
        scrollableControlCount: 8,
        maxDockWidth: 320,
      ),
      isFalse,
    );
  });

  test(
    'desktop focused call rail uses a second row when participants overflow',
    () {
      final columns = debugFocusedCallRailColumnsForTesting(
        itemCount: 14,
        maxWidth: 960,
        maxHeight: 620,
      );

      expect(columns, greaterThan(1));
      expect(
        debugFocusedCallRailRowsForTesting(
          itemCount: columns + 1,
          maxWidth: 960,
          maxHeight: 620,
        ),
        2,
      );
    },
  );

  test(
    'desktop focused call rail keeps one secondary tile thumbnail-sized',
    () {
      expect(
        debugFocusedCallRailColumnsForTesting(
          itemCount: 1,
          maxWidth: 960,
          maxHeight: 620,
        ),
        greaterThan(1),
      );
      expect(
        debugFocusedCallRailHeightForTesting(
          itemCount: 1,
          maxWidth: 960,
          maxHeight: 620,
        ),
        lessThan(160),
      );
    },
  );

  test('mobile focused call rail remains a single horizontal layer', () {
    expect(
      debugFocusedCallRailColumnsForTesting(
        itemCount: 12,
        maxWidth: 360,
        maxHeight: 640,
        mobile: true,
      ),
      1,
    );
    expect(
      debugFocusedCallRailRowsForTesting(
        itemCount: 12,
        maxWidth: 360,
        maxHeight: 640,
        mobile: true,
      ),
      1,
    );
  });

  test('hidden camera tiles do not visibility-mute microphone audio', () {
    expect(
      debugShouldMuteHiddenTileLocalPlaybackForTesting(
        tileIsScreenshare: false,
        targetIsScreenShareAudio: false,
        hasVisibleSurface: true,
        streamHidden: true,
      ),
      isFalse,
    );
  });

  test('hidden screenshare tiles still visibility-mute screenshare audio', () {
    expect(
      debugShouldMuteHiddenTileLocalPlaybackForTesting(
        tileIsScreenshare: true,
        targetIsScreenShareAudio: true,
        hasVisibleSurface: true,
        streamHidden: true,
      ),
      isTrue,
    );
  });

  test('visibility mute reapplies if a hidden stream was locally unmuted', () {
    expect(
      debugShouldApplyVisibilityMuteForTesting(
        shouldMute: true,
        mutedByVisibility: true,
        locallyMuted: false,
      ),
      isTrue,
    );
    expect(
      debugShouldApplyVisibilityMuteForTesting(
        shouldMute: true,
        mutedByVisibility: true,
        locallyMuted: true,
      ),
      isFalse,
    );
  });
}
