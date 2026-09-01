import 'inbound_share_manifest.dart';
import 'inbound_share_payload.dart';
import 'inbound_share_staging.dart';

enum InboundShareSessionState {
  reviewing,
  queued,
  completed,
  cancelled,
  failed,
  rejected,
}

enum InboundShareAdmission { active, queued, rejected }

class InboundShareSession {
  InboundShareSession({
    required this.manifest,
    required this.payload,
    required this.state,
  });
  final InboundShareManifest manifest;
  final InboundSharePayload payload;
  InboundShareSessionState state;
}

class InboundShareAdmissionResult {
  const InboundShareAdmissionResult(
    this.admission, {
    this.session,
    this.reason,
  });
  final InboundShareAdmission admission;
  final InboundShareSession? session;
  final String? reason;
}

class InboundShareController {
  InboundShareController(
    this.staging, {
    this.maxItems = 20,
    this.maxItemBytes = 100 * 1024 * 1024,
    this.maxSessionBytes = 250 * 1024 * 1024,
    this.maxCombinedBytes = 300 * 1024 * 1024,
  });
  final InboundShareStaging staging;
  final int maxItems;
  final int maxItemBytes;
  final int maxSessionBytes;
  final int maxCombinedBytes;
  InboundShareSession? active;
  InboundShareSession? queued;

  Future<InboundShareAdmissionResult> accept(
    InboundShareManifest manifest,
    InboundSharePayload payload,
  ) async {
    final reason = _invalidReason(payload);
    if (reason != null) {
      await staging.release(manifest);
      return InboundShareAdmissionResult(
        InboundShareAdmission.rejected,
        reason: reason,
      );
    }
    final session = InboundShareSession(
      manifest: manifest,
      payload: payload,
      state: active == null
          ? InboundShareSessionState.reviewing
          : InboundShareSessionState.queued,
    );
    if (active == null) {
      active = session;
      return InboundShareAdmissionResult(
        InboundShareAdmission.active,
        session: session,
      );
    }
    if (queued != null ||
        _totalBytes + payload.stagedBytes > maxCombinedBytes) {
      await staging.release(manifest);
      return const InboundShareAdmissionResult(
        InboundShareAdmission.rejected,
        reason: 'Another share is already queued.',
      );
    }
    queued = session;
    return InboundShareAdmissionResult(
      InboundShareAdmission.queued,
      session: session,
    );
  }

  Future<void> finishActive(InboundShareSessionState terminal) async {
    final current = active;
    if (current == null) return;
    await finish(current, terminal);
  }

  Future<InboundShareSession?> finish(
    InboundShareSession session,
    InboundShareSessionState terminal,
  ) async {
    if (!identical(active, session)) return active;
    if (!{
      InboundShareSessionState.completed,
      InboundShareSessionState.cancelled,
      InboundShareSessionState.failed,
    }.contains(terminal)) {
      throw ArgumentError.value(terminal, 'terminal');
    }
    session.state = terminal;
    await staging.release(session.manifest);
    active = queued;
    queued = null;
    if (active != null) active!.state = InboundShareSessionState.reviewing;
    return active;
  }

  Future<void> cancelAll() async {
    final sessions = [if (active != null) active!, if (queued != null) queued!];
    active = null;
    queued = null;
    for (final session in sessions) {
      session.state = InboundShareSessionState.cancelled;
      await staging.release(session.manifest);
    }
  }

  int get _totalBytes =>
      (active?.payload.stagedBytes ?? 0) + (queued?.payload.stagedBytes ?? 0);
  String? _invalidReason(InboundSharePayload payload) {
    if (!payload.hasUsableContent) return 'This share has no usable content.';
    if (payload.itemCount > maxItems)
      return 'This share contains too many items.';
    if (payload.stagedBytes > maxSessionBytes)
      return 'This share is too large.';
    if (payload.items.any((item) => (item.file?.size ?? 0) > maxItemBytes))
      return 'A shared item is too large.';
    return null;
  }
}
