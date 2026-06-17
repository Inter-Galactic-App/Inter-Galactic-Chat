import 'dart:async';

import 'package:intergalactic/utils/notifying_list.dart';
import 'package:flutter/widgets.dart';

enum AlertType { info, warning, critical }

class Alert {
  late String Function() _messageGetter;
  late String Function() _titleGetter;
  late void Function(BuildContext context)? action;
  final String? id;
  final bool dismissible;
  final Duration? autoClearAfter;
  AlertType type;

  String get title => _titleGetter();
  String get message => _messageGetter();

  Alert(this.type,
      {required String Function() messageGetter,
      required String Function() titleGetter,
      this.id,
      this.dismissible = true,
      this.autoClearAfter,
      this.action}) {
    _messageGetter = messageGetter;
    _titleGetter = titleGetter;
  }
}

class AlertManager {
  final NotifyingList<Alert> _alerts = NotifyingList.empty(growable: true);

  Stream<int> get onAlertAdded => _alerts.onAdd;

  Stream<int> get onAlertRemoved => _alerts.onRemove;

  List<Alert> get alerts => _alerts;

  void addAlert(Alert alert) {
    if (alert.id != null) {
      clearAlertsById(alert.id!);
    }
    _alerts.add(alert);

    final autoClearAfter = alert.autoClearAfter;
    if (autoClearAfter != null) {
      Timer(autoClearAfter, () => clearAlert(alert));
    }
  }

  void clearAlert(Alert alert) {
    _alerts.remove(alert);
  }

  void clearAlertsById(String id) {
    _alerts.removeWhere((alert) => alert.id == id);
  }
}
