import 'package:flutter/services.dart';

import 'inbound_share_controller.dart';

/// Reports the fate of a staged native share session back to the platform.
///
/// On iOS the host only *reserves* a session when it hands the token over. The
/// reservation lapses and the share is offered again unless something reports
/// an outcome, so this is what closes the loop.
///
/// The report must happen after the session is genuinely admitted, not when the
/// payload is merely emitted onto an in-memory bus: acknowledging at emission
/// meant a process death between emit and admit left an `.accepted` session
/// nothing would ever pick up. REVIEW, 2026-08-02.
abstract interface class InboundShareHandoff {
  /// The session was admitted and is now owned by the review flow.
  Future<void> acknowledge(String token);

  /// The session cannot be used and its staged bytes should be removed.
  Future<void> reject(String token);
}

/// No-op used on platforms whose staging the host does not own.
///
/// Android stages through the host process itself and has no reservation to
/// settle, so reporting there would be a call into a method that does not
/// exist.
class NoopInboundShareHandoff implements InboundShareHandoff {
  const NoopInboundShareHandoff();

  @override
  Future<void> acknowledge(String token) async {}

  @override
  Future<void> reject(String token) async {}
}

class MethodChannelInboundShareHandoff implements InboundShareHandoff {
  const MethodChannelInboundShareHandoff([
    this.channel = const MethodChannel('chat.intergalactic.app/inbound_share'),
  ]);

  final MethodChannel channel;

  @override
  Future<void> acknowledge(String token) =>
      _report('acknowledgeInboundShare', token);

  @override
  Future<void> reject(String token) => _report('rejectInboundShare', token);

  Future<void> _report(String method, String token) async {
    if (token.isEmpty) return;
    try {
      await channel.invokeMethod<bool>(method, token);
    } on PlatformException {
      // Worst case the reservation lapses and the session is offered again,
      // which is the recoverable outcome by design. Native returning false is
      // the same story: it retains the reservation deliberately.
    } on MissingPluginException {
      // Platform without the handler; nothing to settle.
    }
  }
}

/// Settles the native staging reservation from an admission outcome.
///
/// This is the ordering contract REVIEW required, expressed as a unit rather
/// than as inline widget code, so it can be regression-tested: a session is
/// acknowledged **only** once `InboundShareLifecycle.admit` has actually
/// admitted it, never merely because the payload was emitted onto an in-memory
/// bus. A rejected admission settles the other way, removing the staged bytes.
///
/// A payload without a staging token is not a native session (Android text
/// shares, for instance) and there is nothing to settle.
Future<void> settleInboundShareAdmission({
  required InboundShareAdmissionResult admission,
  required String? token,
  required InboundShareHandoff handoff,
}) async {
  if (token == null || token.isEmpty) return;
  final rejected =
      admission.admission == InboundShareAdmission.rejected ||
      admission.session == null;
  if (rejected) {
    await handoff.reject(token);
    return;
  }
  // `queued` counts as admitted: the lifecycle owns the session and will
  // promote it, so native must stop offering it.
  await handoff.acknowledge(token);
}

/// Tells the platform about a conversation the user just sent to, so the share
/// sheet can offer it as a suggestion next time.
///
/// This is the other half of preselection: without donated interactions iOS has
/// nothing to suggest, so the Share Extension's intent is always nil and
/// [InboundSharePayload.preselectedRoomId] never arrives.
///
/// **Privacy.** Donating publishes the conversation's display name to iOS,
/// where it can appear in the share sheet and Siri suggestions - including on
/// the lock screen. That is the same class of disclosure as a notification
/// preview, so the caller must gate it on the user's existing notification
/// preview privacy choice, which defaults to private. No message content and no
/// avatar are sent.
class InboundShareConversationDonor {
  const InboundShareConversationDonor([
    this.channel = const MethodChannel('chat.intergalactic.app/inbound_share'),
  ]);

  final MethodChannel channel;

  Future<bool> donate({
    required String roomId,
    required String displayName,
  }) async {
    if (roomId.trim().isEmpty || displayName.trim().isEmpty) return false;
    try {
      return await channel.invokeMethod<bool>('donateConversation', {
            'roomId': roomId,
            'displayName': displayName,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // Platform without the handler; suggestions simply never appear.
      return false;
    }
  }
}
