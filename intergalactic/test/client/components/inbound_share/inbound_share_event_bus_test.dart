import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_delivery_gate.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_payload.dart';
import 'package:intergalactic/utils/event_bus.dart';

InboundSharePayload _payload(String label) =>
    InboundSharePayload(items: [InboundShareItem.text(label)], body: label);

void _drainPendingPayloads() {
  while (EventBus.takePendingInboundSharePayload() != null) {}
}

void _drainPendingFailures() {
  for (final pending in EventBus.pendingInboundShareFailures) {
    EventBus.claimPendingInboundShareFailure(pending);
  }
}

void _drainAll() {
  _drainPendingPayloads();
  _drainPendingFailures();
}

void main() {
  setUp(_drainAll);
  tearDown(_drainAll);

  group('inbound-share failures are reported, not swallowed', () {
    test('a cold-start failure waits for a host that can show it', () {
      // The failing share can arrive before any MainPage exists. Dropping it
      // then would restore the silent failure this whole path exists to remove.
      EventBus.emitInboundShareFailure(InboundShareFailure.permissionDenied);

      expect(EventBus.pendingInboundShareFailures, [
        InboundShareFailure.permissionDenied,
      ]);
    });

    test('a claimed failure is not shown twice', () {
      EventBus.emitInboundShareFailure(InboundShareFailure.unreadable);

      expect(
        EventBus.claimPendingInboundShareFailure(
          InboundShareFailure.unreadable,
        ),
        isTrue,
      );
      expect(
        EventBus.claimPendingInboundShareFailure(
          InboundShareFailure.unreadable,
        ),
        isFalse,
      );
    });

    test('an unclaimed failure survives for a replacement host', () async {
      final received = Completer<InboundShareFailure>();
      final subscription = EventBus.inboundShareFailure.stream.listen(
        received.complete,
      );

      EventBus.emitInboundShareFailure(InboundShareFailure.tooLarge);

      expect(await received.future, InboundShareFailure.tooLarge);
      await subscription.cancel();
      // Deliberately never claimed: a host that heard it but was disposed
      // before showing anything must not consume the only report.
      expect(EventBus.pendingInboundShareFailures, [
        InboundShareFailure.tooLarge,
      ]);
    });

    test('distinct failures are each reported', () {
      EventBus.emitInboundShareFailure(InboundShareFailure.permissionDenied);
      EventBus.emitInboundShareFailure(InboundShareFailure.tooLarge);

      expect(EventBus.pendingInboundShareFailures, [
        InboundShareFailure.permissionDenied,
        InboundShareFailure.tooLarge,
      ]);
    });

    test('consecutive equal failures are stored and published once', () async {
      final received = <InboundShareFailure>[];
      final subscription = EventBus.inboundShareFailure.stream.listen(
        received.add,
      );

      EventBus.emitInboundShareFailure(InboundShareFailure.permissionDenied);
      EventBus.emitInboundShareFailure(InboundShareFailure.permissionDenied);
      await pumpEventQueue();

      expect(received, [InboundShareFailure.permissionDenied]);
      expect(EventBus.pendingInboundShareFailures, [
        InboundShareFailure.permissionDenied,
      ]);
      expect(
        EventBus.claimPendingInboundShareFailure(
          InboundShareFailure.permissionDenied,
        ),
        isTrue,
      );
      expect(
        EventBus.claimPendingInboundShareFailure(
          InboundShareFailure.permissionDenied,
        ),
        isFalse,
      );
      await subscription.cancel();
    });
  });

  test('cold-start payload remains pending without a listener', () {
    final payload = _payload('cold');

    EventBus.emitInboundSharePayload(payload);

    expect(EventBus.takePendingInboundSharePayload(), same(payload));
  });

  test('warm payload remains pending until the listener claims it', () async {
    final payload = _payload('warm');
    final received = Completer<InboundSharePayload>();
    late final StreamSubscription<InboundSharePayload> subscription;
    subscription = EventBus.inboundSharePayload.stream.listen((event) {
      expect(EventBus.claimPendingInboundSharePayload(event), isTrue);
      received.complete(event);
    });

    EventBus.emitInboundSharePayload(payload);

    expect(await received.future, same(payload));
    expect(EventBus.takePendingInboundSharePayload(), isNull);
    await subscription.cancel();
  });

  test('payload survives disposal after dequeue but before admission', () {
    final payload = _payload('admission-boundary');
    final firstHost = InboundShareDeliveryGate()..markHostReady();
    EventBus.emitInboundSharePayload(payload);
    for (final pending in EventBus.pendingInboundSharePayloads) {
      firstHost.enqueue(pending);
    }

    expect(firstHost.takeNext(), same(payload));

    final replacementHost = InboundShareDeliveryGate()..markHostReady();
    for (final pending in EventBus.pendingInboundSharePayloads) {
      replacementHost.enqueue(pending);
    }
    expect(replacementHost.takeNext(), same(payload));
    expect(EventBus.claimPendingInboundSharePayload(payload), isTrue);
    expect(EventBus.claimPendingInboundSharePayload(payload), isFalse);
  });
  test(
    'unclaimed payload survives listener disposal for replacement',
    () async {
      final payload = _payload('replacement');
      final received = Completer<void>();
      final firstSubscription = EventBus.inboundSharePayload.stream.listen((_) {
        received.complete();
      });

      EventBus.emitInboundSharePayload(payload);
      await received.future;
      await firstSubscription.cancel();

      expect(EventBus.takePendingInboundSharePayload(), same(payload));
    },
  );
}
