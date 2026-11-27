import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Presentation-only view of one protected local-data case.
///
/// IOS remains the authority for every value here. This model deliberately has
/// no filesystem, database, lease, or cleanup capability.
enum DriftQuarantinePresentationState {
  unresolved,
  pendingRetry,
  resolved,
  unsafeOrAmbiguous,
}

enum DriftQuarantinePresentationReason {
  none,
  accountUnverified,
  clockUntrusted,
  safetyIncomplete,
  partialCleanup,
  restorationFailed,
  unsupported,
  ambiguous,
}

/// IOS supplies this verdict after applying the persisted clock policy.
///
/// The UI must never infer it from a local clock, a countdown, or a generic
/// recovery reason. `ordinaryEligibility` is intentionally separate from the
/// last-resort path: the former has proven the ordinary 30-day interval while
/// the latter only reached the accepted, uncorroborated 37-day UTC fallback.
enum DriftQuarantineTimingVerdict {
  normalCountdown,
  ordinaryEligibility,
  clockUncertainGrace,
  lastResortEligibility,
  safetyBlockedRetention,
}

enum DriftQuarantineHistoricalValidation {
  notChecked,
  historicallyValidated,
  unavailable,
}

enum DriftQuarantineNoticeKind { none, firstForeground, daySeven }

enum DriftQuarantineAcknowledgementResult { recorded, stale, unavailable }

class DriftQuarantinePresentationCase {
  DriftQuarantinePresentationCase({
    required this.caseId,
    required this.expectedRevision,
    required this.acknowledgementToken,
    required this.state,
    required this.reason,
    required this.historicalValidation,
    required this.notice,
    this.timingVerdict,
    this.daysRemaining,
    this.verifiedAssociatedAccountLabel,
  }) : assert(caseId.isNotEmpty),
       assert(expectedRevision >= 0),
       assert(acknowledgementToken.isNotEmpty) {
    final days = daysRemaining;
    if (timingVerdict == DriftQuarantineTimingVerdict.normalCountdown) {
      if (days == null || days <= 0 || days >= 30) {
        throw ArgumentError('A normal countdown requires 1 to 29 days.');
      }
    } else if (days != null) {
      throw ArgumentError(
        'Only a normal countdown may specify remaining days.',
      );
    }
  }

  /// Opaque to UI: never render this value or derive an identity from it.
  final String caseId;
  final int expectedRevision;

  /// Opaque optimistic-concurrency token supplied by IOS.
  final String acknowledgementToken;
  final DriftQuarantinePresentationState state;
  final DriftQuarantinePresentationReason reason;

  /// Historical only; it never represents a currently open database or lease.
  final DriftQuarantineHistoricalValidation historicalValidation;
  final DriftQuarantineNoticeKind notice;

  /// A precomputed, sanitized timing verdict from IOS. Null means that no
  /// timing-specific disclosure is safe to show for this case.
  final DriftQuarantineTimingVerdict? timingVerdict;

  /// Present only for [DriftQuarantineTimingVerdict.normalCountdown].
  final int? daysRemaining;

  /// Present only after IOS has verified the local account association.
  final String? verifiedAssociatedAccountLabel;

  bool get isUnresolved =>
      state == DriftQuarantinePresentationState.unresolved ||
      state == DriftQuarantinePresentationState.pendingRetry ||
      state == DriftQuarantinePresentationState.unsafeOrAmbiguous;
}

class DriftQuarantinePresentationSnapshot {
  DriftQuarantinePresentationSnapshot._({
    required this.isLoading,
    required this.isUnavailable,
    required this.recordRevision,
    required List<DriftQuarantinePresentationCase> cases,
  }) : cases = List.unmodifiable(cases) {
    if (recordRevision < 0 || cases.length > maxCases) {
      throw ArgumentError.value(
        cases,
        'cases',
        'must contain at most $maxCases cases',
      );
    }
  }

  DriftQuarantinePresentationSnapshot.loading()
    : this._(
        isLoading: true,
        isUnavailable: false,
        recordRevision: 0,
        cases: const [],
      );

  DriftQuarantinePresentationSnapshot.unavailable()
    : this._(
        isLoading: false,
        isUnavailable: true,
        recordRevision: 0,
        cases: const [],
      );

  factory DriftQuarantinePresentationSnapshot.ready({
    required int recordRevision,
    required List<DriftQuarantinePresentationCase> cases,
  }) => DriftQuarantinePresentationSnapshot._(
    isLoading: false,
    isUnavailable: false,
    recordRevision: recordRevision,
    cases: cases,
  );

  static const maxCases = 64;
  final bool isLoading;
  final bool isUnavailable;
  final int recordRevision;
  final List<DriftQuarantinePresentationCase> cases;
}

class DriftQuarantinePresentationCopy {
  const DriftQuarantinePresentationCopy(this.title, this.description);

  final String title;
  final String description;

  static DriftQuarantinePresentationCopy forCase(
    DriftQuarantinePresentationCase item,
  ) {
    if (item.state == DriftQuarantinePresentationState.unsafeOrAmbiguous ||
        item.reason == DriftQuarantinePresentationReason.clockUntrusted ||
        item.reason == DriftQuarantinePresentationReason.accountUnverified ||
        item.reason == DriftQuarantinePresentationReason.unsupported ||
        item.reason == DriftQuarantinePresentationReason.ambiguous) {
      return const DriftQuarantinePresentationCopy(
        'Manual review needed',
        'This protected local data is being retained because Inter Galactic cannot verify a safe automatic recovery path.',
      );
    }
    switch (item.timingVerdict) {
      case DriftQuarantineTimingVerdict.normalCountdown:
        return DriftQuarantinePresentationCopy(
          'Automatic removal eligibility in ${item.daysRemaining} ${item.daysRemaining == 1 ? 'day' : 'days'}',
          'After 720 hours (30 full days) of trusted elapsed time, Inter Galactic will automatically remove this older copy when required safety checks pass, even if it differs. Local-only or unsynchronized data could be permanently lost. It retains the copy when safety or timing cannot be verified.',
        );
      case DriftQuarantineTimingVerdict.ordinaryEligibility:
        return const DriftQuarantinePresentationCopy(
          'Automatic safety check pending',
          'The normal 720-hour (30 full days) period has passed. Inter Galactic will remove the older copy only after it proves the account, timing, local data, and active writers are safe. Local-only or unsynchronized data could be permanently lost.',
        );
      case DriftQuarantineTimingVerdict.clockUncertainGrace:
        return const DriftQuarantinePresentationCopy(
          'Timing needs an additional safety check',
          'Inter Galactic cannot yet independently verify the normal 720-hour timing. It is retaining this protected local data during an additional 168-hour (seven full days) safety grace period. This notice does not authorize automatic removal.',
        );
      case DriftQuarantineTimingVerdict.lastResortEligibility:
        return const DriftQuarantinePresentationCopy(
          'Automatic safety check pending',
          'Inter Galactic could not independently verify elapsed time. The device\'s recorded UTC time reached the 888-hour (37 full days) last-resort eligibility point; this is not proof that 37 real days passed. It will remove the older copy only after account, file, writer, and lifecycle safety checks pass. Local-only or unsynchronized data could be permanently lost.',
        );
      case DriftQuarantineTimingVerdict.safetyBlockedRetention:
        return const DriftQuarantinePresentationCopy(
          'Automatic removal paused for safety',
          'A removal eligibility point has been reached, but Inter Galactic cannot verify that the account, protected files, active writers, and lifecycle are safe. The copy is retained and no removal is being performed.',
        );
      case null:
        break;
    }
    if (item.state == DriftQuarantinePresentationState.pendingRetry) {
      return const DriftQuarantinePresentationCopy(
        'Recovery is still in progress',
        'A previous recovery attempt did not finish. Inter Galactic is retaining this protected local data and will retry only after the required safety checks pass. After 720 hours (30 full days) of trusted elapsed time, it may automatically remove the older copy when those checks pass, even if it differs. Local-only or unsynchronized data could be permanently lost.',
      );
    }
    if (item.notice == DriftQuarantineNoticeKind.daySeven) {
      return const DriftQuarantinePresentationCopy(
        'Recovery is still in progress',
        'The protected local data still needs a safe recovery decision. After 720 hours (30 full days) of trusted elapsed time, Inter Galactic will automatically remove the older copy when required safety checks pass, even if it differs. Local-only or unsynchronized data could be permanently lost.',
      );
    }
    return const DriftQuarantinePresentationCopy(
      'Local data needs attention',
      'Inter Galactic found older protected local data. It is checking whether recovery is safe. After 720 hours (30 full days) of trusted elapsed time, it will automatically remove the older copy when required safety checks pass, even if it differs. Local-only or unsynchronized data could be permanently lost.',
    );
  }
}

typedef DriftQuarantineNoticeAcknowledger =
    Future<DriftQuarantineAcknowledgementResult> Function({
      required String caseId,
      required int expectedRevision,
      required String acknowledgementToken,
      required DriftQuarantineNoticeKind notice,
    });

typedef DriftQuarantinePostFrameScheduler =
    void Function(FrameCallback callback);

/// An inert foreground notice. An owner must inject snapshot, lifecycle state,
/// and the IOS acknowledgement callback before it can be mounted in the app.
class DriftQuarantineForegroundNotice extends StatefulWidget {
  const DriftQuarantineForegroundNotice({
    required this.snapshot,
    required this.isForeground,
    this.isForegroundNow,
    this.schedulePostFrame,
    this.onAcknowledgeRenderedNotice,
    this.onReviewDetails,
    this.onDismiss,
    super.key,
  });

  final DriftQuarantinePresentationSnapshot snapshot;
  final bool isForeground;
  final bool Function()? isForegroundNow;
  final DriftQuarantinePostFrameScheduler? schedulePostFrame;
  final DriftQuarantineNoticeAcknowledger? onAcknowledgeRenderedNotice;
  final VoidCallback? onReviewDetails;
  final VoidCallback? onDismiss;

  @override
  State<DriftQuarantineForegroundNotice> createState() =>
      _DriftQuarantineForegroundNoticeState();
}

class _DriftQuarantineForegroundNoticeState
    extends State<DriftQuarantineForegroundNotice> {
  final Set<String> _queuedAcknowledgements = <String>{};
  final Set<String> _inFlightAcknowledgements = <String>{};
  final Set<String> _recordedAcknowledgements = <String>{};
  final Set<String> _rejectedAcknowledgements = <String>{};
  final Set<String> _dismissedNotices = <String>{};

  bool get _isForegroundNow =>
      widget.isForeground && (widget.isForegroundNow?.call() ?? true);

  @override
  void initState() {
    super.initState();
    _scheduleAcknowledgement();
  }

  @override
  void didUpdateWidget(covariant DriftQuarantineForegroundNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleAcknowledgement();
  }

  DriftQuarantinePresentationCase? get _noticeCase {
    if (widget.snapshot.isLoading || widget.snapshot.isUnavailable) return null;
    for (final item in widget.snapshot.cases) {
      if (item.isUnresolved && item.notice != DriftQuarantineNoticeKind.none) {
        return item;
      }
    }
    return null;
  }

  String _noticeKey(DriftQuarantinePresentationCase item) =>
      '${widget.snapshot.recordRevision}:${item.caseId}:${item.expectedRevision}:${item.acknowledgementToken}:${item.notice.name}';

  String _queuedAttemptKey(
    String noticeKey,
    DriftQuarantineNoticeAcknowledger acknowledge,
  ) => '$noticeKey:${identityHashCode(acknowledge)}';

  void _scheduleAcknowledgement() {
    final item = _noticeCase;
    final acknowledge = widget.onAcknowledgeRenderedNotice;
    if (!_isForegroundNow || item == null || acknowledge == null) return;
    final key = _noticeKey(item);
    final queuedAttemptKey = _queuedAttemptKey(key, acknowledge);
    if (_queuedAcknowledgements.contains(queuedAttemptKey) ||
        _inFlightAcknowledgements.contains(key) ||
        _recordedAcknowledgements.contains(key) ||
        _rejectedAcknowledgements.contains(key) ||
        _dismissedNotices.contains(key)) {
      return;
    }
    _queuedAcknowledgements.add(queuedAttemptKey);
    (widget.schedulePostFrame ?? WidgetsBinding.instance.addPostFrameCallback)((
      _,
    ) async {
      final current = _noticeCase;
      if (!mounted ||
          !_isForegroundNow ||
          current == null ||
          _noticeKey(current) != key ||
          _dismissedNotices.contains(key) ||
          !identical(widget.onAcknowledgeRenderedNotice, acknowledge)) {
        _queuedAcknowledgements.remove(queuedAttemptKey);
        return;
      }
      _queuedAcknowledgements.remove(queuedAttemptKey);
      _inFlightAcknowledgements.add(key);
      try {
        final result = await acknowledge(
          caseId: item.caseId,
          expectedRevision: item.expectedRevision,
          acknowledgementToken: item.acknowledgementToken,
          notice: item.notice,
        );
        if (result == DriftQuarantineAcknowledgementResult.recorded) {
          _recordedAcknowledgements.add(key);
        } else {
          _rejectedAcknowledgements.add(key);
        }
      } catch (_) {
        _rejectedAcknowledgements.add(key);
      } finally {
        _inFlightAcknowledgements.remove(key);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = _noticeCase;
    if (item == null || _dismissedNotices.contains(_noticeKey(item))) {
      return const SizedBox.shrink();
    }
    final copy = DriftQuarantinePresentationCopy.forCase(item);
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          minimum: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.error.withValues(alpha: 0.46),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: theme.colorScheme.error,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              copy.title,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(copy.description),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton(
                            onPressed: widget.onReviewDetails,
                            child: const Text('Review details'),
                          ),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _dismissedNotices.add(_noticeKey(item));
                              });
                              widget.onDismiss?.call();
                            },
                            child: const Text('Not now'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
