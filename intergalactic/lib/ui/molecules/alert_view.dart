import 'dart:async';

import 'package:intergalactic/client/alert.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class AlertView extends StatelessWidget {
  final Alert alert;
  final VoidCallback? onDismiss;
  const AlertView(this.alert, {super.key, this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: alert.action == null ? null : () => alert.action?.call(context),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Icon(
                getIcon(),
                color: getColor(context),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    tiamat.Text.labelEmphasised(alert.title),
                    tiamat.Text.labelLow(alert.message),
                  ],
                ),
              ),
            ),
            if (alert.dismissible && onDismiss != null)
              IconButton(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                icon: const Icon(Icons.close),
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                onPressed: onDismiss,
              ),
          ],
        ),
      ),
    );
  }

  IconData getIcon() {
    switch (alert.type) {
      case AlertType.info:
        return Icons.info;
      case AlertType.warning:
        return Icons.warning;
      case AlertType.critical:
        return Icons.dangerous;
    }
  }

  Color? getColor(BuildContext context) {
    switch (alert.type) {
      case AlertType.warning:
        return Colors.amber;
      case AlertType.critical:
        return Theme.of(context).colorScheme.error;
      default:
        return null;
    }
  }
}

class AlertListView extends StatefulWidget {
  const AlertListView(
    this.alertManager, {
    super.key,
    this.padding = const EdgeInsets.all(8),
    this.shrinkWrap = true,
    this.physics,
  });

  final AlertManager alertManager;
  final EdgeInsetsGeometry padding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  State<AlertListView> createState() => _AlertListViewState();
}

class _AlertListViewState extends State<AlertListView> {
  late final List<StreamSubscription<int>> _subscriptions;

  @override
  void initState() {
    super.initState();
    _subscriptions = [
      widget.alertManager.onAlertAdded.listen((_) => _onAlertsChanged()),
      widget.alertManager.onAlertRemoved.listen((_) => _onAlertsChanged()),
    ];
  }

  void _onAlertsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alerts = widget.alertManager.alerts.toList(growable: false);
    return ListView(
      shrinkWrap: widget.shrinkWrap,
      padding: widget.padding,
      physics: widget.physics,
      children: [
        for (final alert in alerts)
          AlertView(
            alert,
            onDismiss: () => widget.alertManager.clearAlert(alert),
          ),
      ],
    );
  }
}
