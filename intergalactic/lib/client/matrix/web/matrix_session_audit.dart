import 'dart:collection';

import 'package:intergalactic/debug/log.dart';

class MatrixSessionAudit {
  static const int _maxEntries = 100;
  static final ListQueue<String> _events = ListQueue();

  static String? lastRestoreDecision;

  static void record(String message, {bool restoreDecision = false}) {
    final safeMessage = Log.redactSensitiveInfo(message);
    final entry = '${DateTime.now().toUtc().toIso8601String()} $safeMessage';
    if (_events.length >= _maxEntries) {
      _events.removeFirst();
    }
    _events.addLast(entry);
    Log.i(entry);

    if (restoreDecision) {
      lastRestoreDecision = safeMessage;
    }
  }

  static List<String> get recentEvents => List.unmodifiable(_events.toList());
}
