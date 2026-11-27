import 'package:flutter/material.dart';
import 'package:intergalactic/ui/organisms/drift_quarantine_foreground_notice.dart';
import 'package:intergalactic/ui/pages/settings/settings_status_components.dart';

/// Account Security presentation for IOS-owned B3 recovery state.
///
/// This component receives already-sanitized data. It neither opens storage nor
/// writes preferences, recovery state, time trust, or cleanup capability.
class DriftQuarantineRecoveryPanel extends StatelessWidget {
  const DriftQuarantineRecoveryPanel({
    required this.snapshot,
    this.onReviewDetails,
    super.key,
  });

  final DriftQuarantinePresentationSnapshot snapshot;
  final VoidCallback? onReviewDetails;

  @override
  Widget build(BuildContext context) {
    if (snapshot.isLoading) {
      return const SettingsStatePanel(
        icon: Icons.hourglass_top_rounded,
        title: 'Checking protected local data',
        description:
            'Inter Galactic is checking whether any local-data recovery needs attention.',
        tone: SettingsStatusTone.neutral,
      );
    }
    if (snapshot.isUnavailable) {
      return const SettingsStatePanel(
        icon: Icons.info_outline_rounded,
        title: 'Local-data recovery status unavailable',
        description:
            'Inter Galactic cannot currently read the protected recovery status. No automatic cleanup can be started from this screen.',
        tone: SettingsStatusTone.warning,
      );
    }

    final unresolved = snapshot.cases
        .where((item) => item.isUnresolved)
        .toList();
    if (unresolved.isEmpty) return const SizedBox.shrink();
    final selected = unresolved.first;
    final copy = DriftQuarantinePresentationCopy.forCase(selected);
    final accountLabel = unresolved.length == 1
        ? selected.verifiedAssociatedAccountLabel
        : null;
    final summary = unresolved.length > 1
        ? '${unresolved.length} protected local-data items need attention. '
        : '';
    final description = accountLabel == null || accountLabel.isEmpty
        ? '$summary${copy.description}'
        : '$summary${copy.description}\nAssociated account: $accountLabel';
    return SettingsStatePanel(
      icon: Icons.warning_amber_rounded,
      title: copy.title,
      description: description,
      tone: SettingsStatusTone.warning,
      action: OutlinedButton(
        onPressed: onReviewDetails,
        child: const Text('Review details'),
      ),
    );
  }
}
