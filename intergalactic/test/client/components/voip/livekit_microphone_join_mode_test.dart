import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/voip_room/livekit_microphone_sender_gate.dart';

/// BUG-322: with Push to Talk on, the Windows join skipped the microphone
/// publish entirely, so the call had no local publication - "Waiting for
/// streams..." instead of the user's own tile, and a mute indicator with
/// nothing to read. The join now publishes with the sender detached, which is
/// Push to Talk's steady state, instead of publishing nothing.
void main() {
  test('Windows with Push to Talk publishes muted rather than skipping', () {
    expect(
      LivekitMicrophoneSenderGate.initialJoinMode(
        isWindows: true,
        pushToTalkEnabled: true,
      ),
      InitialMicrophoneJoinMode.publishMutedForPushToTalk,
    );
  });

  test('Windows without Push to Talk enables normally', () {
    expect(
      LivekitMicrophoneSenderGate.initialJoinMode(
        isWindows: true,
        pushToTalkEnabled: false,
      ),
      InitialMicrophoneJoinMode.enable,
    );
  });

  test('off Windows, Push to Talk does not change the join', () {
    // The sender-detach mute model is Windows-only; other platforms never
    // had the skip and keep the normal enable.
    expect(
      LivekitMicrophoneSenderGate.initialJoinMode(
        isWindows: false,
        pushToTalkEnabled: true,
      ),
      InitialMicrophoneJoinMode.enable,
    );
  });
}
