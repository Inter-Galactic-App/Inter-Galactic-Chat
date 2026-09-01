import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/inbound_share/android_inbound_share_bridge.dart';
import 'package:intergalactic/client/components/inbound_share/android_inbound_share_intake.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_payload.dart';

void main() {
  test(
    'normalizes Android text and links without treating files as text-only',
    () {
      final link = AndroidInboundShareIntake.textPayload(
        AndroidInboundShareIntent(text: 'https://example.test/a', streams: []),
      );
      expect(link?.items.single.kind, InboundShareItemKind.url);
      final text = AndroidInboundShareIntake.textPayload(
        AndroidInboundShareIntent(text: 'hello', streams: []),
      );
      expect(text?.body, 'hello');
      expect(
        AndroidInboundShareIntake.textPayload(
          AndroidInboundShareIntent(
            text: 'x',
            streams: [Uri(scheme: 'content', path: '/a')],
          ),
        ),
        isNull,
      );
    },
  );
}
