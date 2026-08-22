import 'dart:collection';

import 'package:intergalactic/client/components/inbound_share/inbound_share_payload.dart';

/// Holds inbound shares until the current UI host has completed its first frame.
class InboundShareDeliveryGate {
  final ListQueue<InboundSharePayload> _pending =
      ListQueue<InboundSharePayload>();
  bool _hostReady = false;

  bool get isHostReady => _hostReady;

  void enqueue(InboundSharePayload payload) {
    if (!_pending.contains(payload)) {
      _pending.addLast(payload);
    }
  }

  void markHostReady() => _hostReady = true;

  InboundSharePayload? takeNext() =>
      !_hostReady || _pending.isEmpty ? null : _pending.removeFirst();

  List<InboundSharePayload> takeAll() {
    final pending = _pending.toList(growable: false);
    _pending.clear();
    return pending;
  }
}
