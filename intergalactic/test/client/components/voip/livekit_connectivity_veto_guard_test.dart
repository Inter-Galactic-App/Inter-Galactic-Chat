import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/livekit_connectivity_veto_guard.dart';

class _FakeConnectivityPlatform extends ConnectivityPlatform {
  _FakeConnectivityPlatform(this.reported);

  List<ConnectivityResult> reported;
  final StreamController<List<ConnectivityResult>> controller =
      StreamController<List<ConnectivityResult>>.broadcast();
  int checkCalls = 0;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async {
    checkCalls++;
    return reported;
  }

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      controller.stream;
}

void main() {
  late _FakeConnectivityPlatform delegate;

  setUp(() => delegate = _FakeConnectivityPlatform(const []));
  tearDown(() => delegate.controller.close());

  LivekitConnectivityVetoGuard guardWith({required bool hasAddress}) {
    return LivekitConnectivityVetoGuard(
      delegate,
      probe: () async => hasAddress,
    );
  }

  group('LivekitConnectivityVetoGuard', () {
    test('overrides `none` when the machine holds a routable address', () async {
      // The confirmed BUG-296 state: the plugin says there is no network while
      // the same process resolves the SFU host in 6ms.
      delegate.reported = const [ConnectivityResult.none];

      final result = await guardWith(hasAddress: true).checkConnectivity();

      expect(result, isNot(contains(ConnectivityResult.none)));
      expect(result, [ConnectivityResult.other]);
    });

    test('leaves `none` alone when there is genuinely no address', () async {
      // The case the guard must NOT break: really offline. LiveKit's fast
      // refusal is correct here and is left intact.
      delegate.reported = const [ConnectivityResult.none];

      final result = await guardWith(hasAddress: false).checkConnectivity();

      expect(result, [ConnectivityResult.none]);
    });

    test('passes a healthy verdict through untouched', () async {
      delegate.reported = const [
        ConnectivityResult.ethernet,
        ConnectivityResult.vpn,
      ];

      final result = await guardWith(hasAddress: true).checkConnectivity();

      expect(result, [ConnectivityResult.ethernet, ConnectivityResult.vpn]);
    });

    test('does not probe at all unless the verdict is `none`', () async {
      var probed = false;
      delegate.reported = const [ConnectivityResult.wifi];
      final guard = LivekitConnectivityVetoGuard(
        delegate,
        probe: () async {
          probed = true;
          return true;
        },
      );

      await guard.checkConnectivity();

      // The probe enumerates interfaces; running it on the healthy path would
      // add cost to every connect for no benefit.
      expect(probed, isFalse);
    });

    test('corrects the change stream, not just the one-shot check', () async {
      // SignalClient subscribes to this on every connect, so a stale `none`
      // arriving here would re-poison an otherwise healthy client.
      final guard = guardWith(hasAddress: true);
      final seen = <List<ConnectivityResult>>[];
      final subscription = guard.onConnectivityChanged.listen(seen.add);

      delegate.controller.add(const [ConnectivityResult.none]);
      delegate.controller.add(const [ConnectivityResult.ethernet]);
      await pumpEventQueue();

      expect(seen, [
        [ConnectivityResult.other],
        [ConnectivityResult.ethernet],
      ]);
      await subscription.cancel();
    });
  });

  group('installIfSupported', () {
    tearDown(
      () => ConnectivityPlatform.instance = _FakeConnectivityPlatform([]),
    );

    test('does not install off Windows', () {
      final before = ConnectivityPlatform.instance;

      expect(
        LivekitConnectivityVetoGuard.installIfSupported(
          isWindowsOverride: false,
        ),
        isFalse,
      );
      expect(ConnectivityPlatform.instance, same(before));
    });

    test('installs once and wraps the existing implementation', () {
      ConnectivityPlatform.instance = delegate;

      expect(
        LivekitConnectivityVetoGuard.installIfSupported(
          isWindowsOverride: true,
        ),
        isTrue,
      );
      expect(
        ConnectivityPlatform.instance,
        isA<LivekitConnectivityVetoGuard>(),
      );
    });

    test('a second install does not stack a second guard', () async {
      ConnectivityPlatform.instance = delegate;
      LivekitConnectivityVetoGuard.installIfSupported(isWindowsOverride: true);
      final first = ConnectivityPlatform.instance;

      expect(
        LivekitConnectivityVetoGuard.installIfSupported(
          isWindowsOverride: true,
        ),
        isFalse,
      );
      expect(ConnectivityPlatform.instance, same(first));

      // Stacked guards would each run the interface probe per query.
      await ConnectivityPlatform.instance.checkConnectivity();
      expect(delegate.checkCalls, 1);
    });
  });
}
