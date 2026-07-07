import 'dart:async';

import 'package:intergalactic/debug/log.dart';

typedef CallPreferenceOperation = FutureOr<void> Function();

class CallPreferenceOperationGuard {
  const CallPreferenceOperationGuard._();

  static Future<void> run({
    required CallPreferenceOperation operation,
    required String content,
    required String source,
  }) async {
    try {
      await Future<void>.sync(operation);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: content,
        category: LogCategory.webrtc,
        source: source,
      );
    }
  }
}
