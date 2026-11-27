import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/log.dart';

typedef EmbeddedNtfyNotificationHandler = FutureOr<void> Function(
    Map<String, dynamic> notification);

class EmbeddedNtfySseListener {
  static const String _ntfyBase = BuildConfig.androidEmbeddedNtfyBaseUrl;

  http.Client? _httpClient;
  StreamSubscription<String>? _sseSubscription;
  int _listenerGeneration = 0;

  bool get isRunning => _httpClient != null;

  void start({
    required String topic,
    required EmbeddedNtfyNotificationHandler onNotification,
    String logPrefix = "EmbeddedNtfySseListener",
  }) {
    _cancelActiveStream();
    _listenerGeneration++;
    _httpClient = http.Client();

    unawaited(_subscribeToSse(
      generation: _listenerGeneration,
      client: _httpClient!,
      topic: topic,
      onNotification: onNotification,
      logPrefix: logPrefix,
    ));
  }

  void stop() {
    _cancelActiveStream();
    _listenerGeneration++;
    _httpClient = null;
  }

  void _cancelActiveStream() {
    final subscription = _sseSubscription;
    _sseSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
  }

  Future<void> _subscribeToSse({
    required int generation,
    required http.Client client,
    required String topic,
    required EmbeddedNtfyNotificationHandler onNotification,
    required String logPrefix,
  }) async {
    const retryDelays = [5, 10, 30, 60, 120];
    var retryIndex = 0;

    try {
      while (_listenerGeneration == generation) {
        try {
          final url = Uri.parse('$_ntfyBase/$topic/sse');
          final request = http.Request('GET', url);
          request.headers['Accept'] = 'text/event-stream';
          request.headers['Cache-Control'] = 'no-cache';

          Log.i("$logPrefix: connecting to SSE endpoint");
          final response = await client.send(request);

          if (response.statusCode != 200) {
            Log.e("$logPrefix: SSE responded ${response.statusCode}");
            throw Exception("SSE error: ${response.statusCode}");
          }

          retryIndex = 0;

          if (_listenerGeneration != generation) {
            return;
          }

          var pendingChunk = '';
          final streamDone = Completer<void>();
          final subscription = response.stream.transform(utf8.decoder).listen(
            (chunk) {
              pendingChunk += chunk;
              final lines = pendingChunk.split('\n');
              pendingChunk = lines.removeLast();
              for (final line in lines) {
                _handleSseLine(
                  line.trim(),
                  onNotification: onNotification,
                  logPrefix: logPrefix,
                );
              }
            },
            onError: (Object error, StackTrace stackTrace) {
              if (!streamDone.isCompleted) {
                streamDone.completeError(error, stackTrace);
              }
            },
            onDone: () {
              if (!streamDone.isCompleted) {
                streamDone.complete();
              }
            },
            cancelOnError: true,
          );
          _sseSubscription = subscription;

          try {
            await streamDone.future;
          } finally {
            if (identical(_sseSubscription, subscription)) {
              _sseSubscription = null;
            }
          }
        } catch (e, s) {
          if (_listenerGeneration != generation) {
            return;
          }

          Log.e("$logPrefix: SSE disconnected - $e");
          Log.onError(e, s);
        }

        if (_listenerGeneration != generation) {
          return;
        }

        final delay = retryDelays[retryIndex.clamp(0, retryDelays.length - 1)];
        retryIndex++;
        Log.i("$logPrefix: reconnecting in ${delay}s");
        await Future.delayed(Duration(seconds: delay));
      }
    } finally {
      if (identical(_httpClient, client)) {
        _httpClient = null;
      }
      client.close();
    }
  }

  void _handleSseLine(
    String line, {
    required EmbeddedNtfyNotificationHandler onNotification,
    required String logPrefix,
  }) {
    if (!line.startsWith('data:')) return;

    final jsonStr = line.substring('data:'.length).trim();
    if (jsonStr.isEmpty) return;

    try {
      final ntfyEvent = jsonDecode(jsonStr) as Map<String, dynamic>;
      final eventType = ntfyEvent['event'] as String? ?? 'message';
      if (eventType != 'message') return;

      final rawMessage = ntfyEvent['message'] as String?;
      if (rawMessage == null) return;

      final payload = jsonDecode(rawMessage) as Map<String, dynamic>;
      final notifData = payload['notification'] as Map<String, dynamic>?;
      if (notifData == null) {
        Log.w("$logPrefix: no 'notification' key in payload");
        return;
      }

      Log.i(
        "$logPrefix: received push payload "
        "${_embeddedNtfyPayloadSummary(notifData)}",
      );
      unawaited(
          Future<void>(() => onNotification(notifData)).catchError((e, s) {
        Log.e("$logPrefix: notification handler failed");
        Log.onError(e, s);
      }));
    } catch (e, s) {
      Log.e("$logPrefix: failed to parse SSE event");
      Log.onError(e, s);
    }
  }
}

String _embeddedNtfyPayloadSummary(Map<String, dynamic> data) {
  final keys = data.keys.map((key) => key.toString()).toList()..sort();
  return "keys=${keys.join(',')} "
      "hasRoom=${data.containsKey("room_id")} "
      "hasEvent=${data.containsKey("event_id")}";
}
