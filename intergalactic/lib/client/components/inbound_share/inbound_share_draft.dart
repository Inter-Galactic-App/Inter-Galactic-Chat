import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_controller.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_payload.dart';

typedef InboundShareTerminalHandler =
    Future<void> Function(InboundShareSessionState terminal);

class InboundShareDraft {
  const InboundShareDraft({
    required this.room,
    required this.payload,
    required this.session,
    required this.onTerminal,
  });

  final Room room;
  final InboundSharePayload payload;
  final InboundShareSession session;
  final InboundShareTerminalHandler onTerminal;

  String get body => payload.body ?? '';
}
