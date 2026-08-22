import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_delivery_gate.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_payload.dart';

InboundSharePayload _payload(String label) =>
    InboundSharePayload(items: [InboundShareItem.text(label)], body: label);

void main() {
  group('InboundShareDeliveryGate', () {
    test('defers a cold-start payload until the host is post-frame ready', () {
      final gate = InboundShareDeliveryGate();
      final payload = _payload('cold');

      gate.enqueue(payload);

      expect(gate.takeNext(), isNull);
      gate.markHostReady();
      expect(gate.takeNext(), same(payload));
      expect(gate.takeNext(), isNull);
    });

    test('delivers a warm payload exactly once to a ready host', () {
      final gate = InboundShareDeliveryGate()..markHostReady();
      final payload = _payload('warm');

      gate.enqueue(payload);

      expect(gate.takeNext(), same(payload));
      expect(gate.takeNext(), isNull);
    });

    test(
      'deduplicates the same payload during snapshot and stream delivery',
      () {
        final gate = InboundShareDeliveryGate()..markHostReady();
        final payload = _payload('duplicate');

        gate.enqueue(payload);
        gate.enqueue(payload);

        expect(gate.takeNext(), same(payload));
        expect(gate.takeNext(), isNull);
      },
    );

    test('transfers an undelivered payload to a replacement host', () {
      final firstHost = InboundShareDeliveryGate();
      final payload = _payload('replacement');
      firstHost.enqueue(payload);

      final replacementHost = InboundShareDeliveryGate();
      for (final pending in firstHost.takeAll()) {
        replacementHost.enqueue(pending);
      }
      replacementHost.markHostReady();

      expect(replacementHost.takeNext(), same(payload));
      expect(replacementHost.takeNext(), isNull);
    });
  });
}
