import 'dart:async';

import 'package:intergalactic/client/components/voip/audio/participant_loudness/participant_loudness_monitor.dart';
import 'package:intergalactic/client/components/voip/audio/participant_loudness/participant_loudness_state.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/main.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Developer-only comparison table for receiver-side participant loudness.
///
/// Shows every measured participant side by side so their levels can actually
/// be compared, which is the point of the slice. Nothing here changes
/// playback — the "Auto" column is a recommendation that no code applies.
class ParticipantLoudnessDiagnosticsView extends StatefulWidget {
  const ParticipantLoudnessDiagnosticsView({super.key, this.monitor});

  /// Injectable for tests; defaults to the shared monitor.
  final ParticipantLoudnessMonitor? monitor;

  @override
  State<ParticipantLoudnessDiagnosticsView> createState() =>
      _ParticipantLoudnessDiagnosticsViewState();
}

class _ParticipantLoudnessDiagnosticsViewState
    extends State<ParticipantLoudnessDiagnosticsView> {
  static const Duration _refreshInterval = Duration(milliseconds: 250);

  Timer? _refreshTimer;
  String? _lastExportPath;
  bool _exporting = false;

  ParticipantLoudnessMonitor get _monitor =>
      widget.monitor ?? ParticipantLoudnessMonitor.instance;

  @override
  void initState() {
    super.initState();
    // Redraw only. Attachment reconciliation moved to the monitor's own follow
    // timer when measurement stopped being scoped to this view; this timer no
    // longer drives it. The monitor samples at its own (faster) rate; the table
    // does not need to.
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    // Deliberately does NOT detach. The monitor follows the call from
    // CallManager, so measurement outlives this view — closing the settings
    // page mid-call used to throw away the rest of the session.
    super.dispose();
  }

  VoipSession? _activeSession() {
    final sessions = clientManager?.callManager.currentSessions;
    if (sessions == null) {
      return null;
    }

    for (final session in sessions) {
      if (session.state == VoipState.connected) {
        return session;
      }
    }

    return null;
  }

  Future<void> _exportReport() async {
    setState(() => _exporting = true);
    final path = await _monitor.exportReport();
    if (!mounted) {
      return;
    }

    setState(() {
      _exporting = false;
      _lastExportPath = path;
    });

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        content: Text(
          path == null
              ? 'Measurement session export is unavailable on this platform.'
              : 'Measurement session written to $path',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_monitor.isEnabled) {
      return _StatusText(
        'Enable participant loudness measurement to collect receive-side '
        'levels. Measurement only — playback is never changed.',
      );
    }

    final states = _monitor.states;
    final session = _activeSession();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (session == null)
          _StatusText(
            'Waiting for a connected call. Join a call with at least one '
            'other participant to start measuring.',
          )
        else if (states.isEmpty)
          _StatusText(
            'Connected. No subscribed remote microphone tracks are being '
            'measured yet.',
          )
        else
          _ParticipantLoudnessTable(states: states),
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(
              width: 220,
              child: tiamat.Button.secondary(
                text: 'Export measurement session',
                isLoading: _exporting,
                onTap: states.isEmpty || _exporting
                    ? null
                    : () => unawaited(_exportReport()),
              ),
            ),
          ],
        ),
        if (_lastExportPath != null) ...[
          const SizedBox(height: 8),
          Text(
            'Last export: $_lastExportPath',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}

class _ParticipantLoudnessTable extends StatelessWidget {
  const _ParticipantLoudnessTable({required this.states});

  final List<ParticipantLoudnessState> states;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface,
    );
    final rowStyle = theme.textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      fontSize: 11,
      color: theme.colorScheme.onSurfaceVariant,
    );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_headerRow(), style: headerStyle),
          const SizedBox(height: 4),
          for (final state in states) ...[
            Text(_dataRow(state), style: rowStyle),
            const SizedBox(height: 2),
          ],
        ],
      ),
    );
  }

  static String _headerRow() {
    return '${'Participant/track'.padRight(19)}'
        '${'Speech'.padRight(10)}'
        '${'Level'.padRight(18)}'
        '${'Peak'.padRight(10)}'
        '${'Auto'.padRight(9)}'
        '${'Manual'.padRight(9)}'
        '${'Combined'.padRight(10)}'
        '${'Conf'.padRight(6)}'
        '${'Samples'.padRight(12)}'
        'Source';
  }

  static String _dataRow(ParticipantLoudnessState state) {
    final linear = state.smoothedLevel.toStringAsFixed(3);
    final levelDb = _db(state.smoothedLevelDb);
    // The track suffix is what separates one person's two devices, which now
    // occupy two rows instead of fighting over one estimator.
    final track = state.trackKey.length > 4
        ? state.trackKey.substring(0, 4)
        : state.trackKey;
    return '${'${state.participantKey}/$track'.padRight(19)}'
        '${state.speechState.label.padRight(10)}'
        '${'$linear/$levelDb'.padRight(18)}'
        '${_db(state.peakLevelDb).padRight(10)}'
        '${_db(state.suggestedAutoGainDb).padRight(9)}'
        '${_db(state.manualOverrideDb).padRight(9)}'
        '${_db(state.futureCombinedGainDb).padRight(10)}'
        '${state.speechConfidence.toStringAsFixed(2).padRight(6)}'
        '${'${state.speechSampleCount}/${state.sampleCount}'.padRight(12)}'
        '${state.measurementSource.label}'
        '${state.muted ? '  [muted]' : ''}';
  }

  static String _db(double? value) {
    if (value == null || !value.isFinite) {
      return '--';
    }

    return value.toStringAsFixed(1);
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontSize: 12,
        height: 1.35,
      ),
    );
  }
}
