import 'dart:convert';

enum StreamLifecycleCue { start, end }

class StreamLifecycleCueProtocol {
  static const topic = 'intergalactic.stream-lifecycle.v1';

  static List<int> encode(StreamLifecycleCue cue) => ascii.encode(cue.name);

  static StreamLifecycleCue? decode(String? packetTopic, List<int> data) {
    if (packetTopic != topic || data.length > 5) return null;
    try {
      return switch (ascii.decode(data)) {
        'start' => StreamLifecycleCue.start,
        'end' => StreamLifecycleCue.end,
        _ => null,
      };
    } on FormatException {
      return null;
    }
  }
}

class RemoteStreamLifecycleCueState {
  final Set<String> _activeParticipants = {};

  void seedActive(String participantIdentity) {
    _activeParticipants.add(participantIdentity);
  }

  bool shouldPlay(String participantIdentity, StreamLifecycleCue cue) {
    if (cue == StreamLifecycleCue.start) {
      return _activeParticipants.add(participantIdentity);
    }
    return _activeParticipants.remove(participantIdentity);
  }

  void participantLeft(String participantIdentity) {
    _activeParticipants.remove(participantIdentity);
  }
}

class LocalStreamLifecycleCueState {
  bool _active = false;

  bool onDeliberateStart({required bool shareActive}) {
    if (!shareActive || _active) return false;
    _active = true;
    return true;
  }

  bool onShareOperationFinished({required bool shareActive}) {
    if (shareActive || !_active) return false;
    _active = false;
    return true;
  }
}

Future<void> runScreenShareFallbackWithCueReconciliation({
  required Future<void> Function() fallback,
  required LocalStreamLifecycleCueState cueState,
  required bool Function() shareActive,
  required void Function() announceEnd,
}) async {
  try {
    await fallback();
  } finally {
    if (cueState.onShareOperationFinished(shareActive: shareActive())) {
      announceEnd();
    }
  }
}
