import 'package:flutter/material.dart';
import 'package:intergalactic/client/components/voip/call_health.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class CallConnectionHealthIndicator extends StatefulWidget {
  const CallConnectionHealthIndicator({
    required this.snapshot,
    required this.developerMode,
    this.initiallyExpanded = false,
    super.key,
  });

  final CallHealthSnapshot snapshot;
  final bool developerMode;
  final bool initiallyExpanded;

  @override
  State<CallConnectionHealthIndicator> createState() =>
      _CallConnectionHealthIndicatorState();
}

class _CallConnectionHealthIndicatorState
    extends State<CallConnectionHealthIndicator> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  void didUpdateWidget(CallConnectionHealthIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initiallyExpanded != oldWidget.initiallyExpanded) {
      _expanded = widget.initiallyExpanded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = _statusColor(scheme, widget.snapshot.state);
    final tooltip = _expanded ? 'Hide call status' : 'Show call status';

    return Semantics(
      button: true,
      expanded: _expanded,
      label: widget.snapshot.summaryLabel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tiamat.Tooltip(
            text: tooltip,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _statusIcon(widget.snapshot.state),
                        size: 16,
                        color: statusColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          widget.snapshot.summaryLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: scheme.onSurface,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        size: 16,
                        color: scheme.secondary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(
              height: 8,
              color: scheme.outlineVariant.withValues(alpha: 0.32),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
              child: _CallHealthDetails(
                snapshot: widget.snapshot,
                developerMode: widget.developerMode,
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _statusIcon(CallConnectionHealthState state) {
    return switch (state) {
      CallConnectionHealthState.good => Icons.check_circle_outline,
      CallConnectionHealthState.fair => Icons.signal_cellular_alt,
      CallConnectionHealthState.poor => Icons.warning_amber_rounded,
      CallConnectionHealthState.connecting => Icons.sync,
      CallConnectionHealthState.reconnecting => Icons.sync,
      CallConnectionHealthState.disconnected => Icons.link_off,
      CallConnectionHealthState.appIssueSuspected => Icons.error_outline,
      CallConnectionHealthState.unknown => Icons.help_outline,
    };
  }

  Color _statusColor(ColorScheme scheme, CallConnectionHealthState state) {
    return switch (state) {
      CallConnectionHealthState.good => scheme.primary,
      CallConnectionHealthState.fair => scheme.tertiary,
      CallConnectionHealthState.poor ||
      CallConnectionHealthState.disconnected ||
      CallConnectionHealthState.appIssueSuspected => scheme.error,
      CallConnectionHealthState.connecting ||
      CallConnectionHealthState.reconnecting => scheme.secondary,
      CallConnectionHealthState.unknown => scheme.outline,
    };
  }
}

class _CallHealthDetails extends StatelessWidget {
  const _CallHealthDetails({
    required this.snapshot,
    required this.developerMode,
  });

  final CallHealthSnapshot snapshot;
  final bool developerMode;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      _CallHealthDetailRow(
        label: 'Your connection',
        value: snapshot.localParticipant?.connectionStatusLabel ?? 'Unknown',
      ),
      _CallHealthDetailRow(label: 'Room', value: snapshot.reconnectStatusLabel),
      _CallHealthDetailRow(
        label: 'Audio tracks',
        value: snapshot.audioStatusLabel,
      ),
      _CallHealthDetailRow(
        label: 'Volume',
        value: snapshot.volumeOverrideStatusLabel,
      ),
      for (final participant in snapshot.remoteParticipants)
        _CallHealthDetailRow(
          label: participant.label,
          value:
              '${participant.connectionStatusLabel}; '
              '${participant.audioStatusLabel}',
        ),
      if (developerMode && snapshot.issueCodes.isNotEmpty)
        _CallHealthDetailRow(
          label: 'Issue codes',
          value: snapshot.issueCodes.join(', '),
        ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

class _CallHealthDetailRow extends StatelessWidget {
  const _CallHealthDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 94,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                color: scheme.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
