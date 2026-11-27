import 'package:intergalactic/client/components/inbound_share/android_inbound_share_bridge.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_payload.dart';

class AndroidInboundShareIntake {
  static InboundSharePayload? textPayload(AndroidInboundShareIntent intent) {
    if (intent.streams.isNotEmpty) return null;
    final text = intent.text?.trim();
    if (text == null || text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    final item = uri != null && uri.hasScheme
        ? InboundShareItem.url(uri)
        : InboundShareItem.text(text);
    return InboundSharePayload(items: [item], body: text);
  }
}
