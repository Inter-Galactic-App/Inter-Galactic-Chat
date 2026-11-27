import 'package:intergalactic/debug/log.dart';

typedef CallLocalPlaybackAsyncOperation = Future<void> Function();
typedef CallLocalPlaybackSyncOperation = void Function();

class CallLocalPlaybackOperationGuard {
  const CallLocalPlaybackOperationGuard._();

  static Future<void> runAsync({
    required CallLocalPlaybackAsyncOperation operation,
    required String content,
    required String source,
  }) async {
    try {
      await operation();
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

  static void runSync({
    required CallLocalPlaybackSyncOperation operation,
    required String content,
    required String source,
  }) {
    try {
      operation();
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
