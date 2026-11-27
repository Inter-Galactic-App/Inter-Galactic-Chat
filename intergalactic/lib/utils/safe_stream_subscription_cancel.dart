import 'dart:async';

import 'package:intergalactic/debug/log.dart';

Future<void> safeCancelStreamSubscription(
  StreamSubscription? subscription, {
  required String content,
  required LogCategory category,
  required String source,
}) async {
  if (subscription == null) {
    return;
  }

  try {
    await subscription.cancel();
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: content,
      category: category,
      source: source,
    );
  }
}
