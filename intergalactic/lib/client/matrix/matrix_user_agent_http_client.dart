import 'package:flutter/foundation.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:http/http.dart' as http;

class MatrixUserAgentHttpClient extends http.BaseClient {
  MatrixUserAgentHttpClient([http.Client? inner])
    : _inner = inner ?? http.Client();

  /// How long to wait before logging the same endpoint/failure pair again. The
  /// SDK retries aggressively, so an outage would otherwise emit one line per
  /// attempt per request.
  static const Duration failureLogInterval = Duration(seconds: 30);

  final http.Client _inner;
  final Map<String, DateTime> _lastFailureLog = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    request.headers.putIfAbsent(
      'User-Agent',
      () => BuildConfig.matrixUserAgent,
    );
    try {
      return await _inner.send(request);
    } catch (error) {
      // The zone-level handler only sees the error object, and the two most
      // common transient failures never name the endpoint in their message: a
      // host lookup fails before any connection exists, and Dart drops the URI
      // when a connection dies before response headers arrive. Both therefore
      // log as an unattributed socket error. The request is still in scope
      // here, so the failing endpoint is recorded before the original error is
      // rethrown untouched for the SDK's own retry handling.
      _logFailure(request, error);
      rethrow;
    }
  }

  void _logFailure(http.BaseRequest request, Object error) {
    // Classify from the URL rather than the error text, so these labels match
    // the request_path values the zone handler emits for errors that do carry
    // a URI.
    final endpoint = Log.matrixRequestPathHint(request.url.toString());
    final summary = errorSummary(error);
    final key = '$endpoint|$summary';
    final now = DateTime.now();
    final lastLogged = _lastFailureLog[key];
    if (lastLogged != null && now.difference(lastLogged) < failureLogInterval) {
      return;
    }

    _lastFailureLog[key] = now;
    Log.w(
      'Matrix request failed request_path=$endpoint method=${request.method} '
      'error=$summary',
      category: LogCategory.matrix,
      source: 'matrix-http',
    );
  }

  /// The error's leading clause only. The full text can carry the homeserver
  /// address and query parameters, and this line exists to attribute an
  /// endpoint, not to restate the error the zone handler already logs.
  @visibleForTesting
  static String errorSummary(Object error) {
    final text = error.toString();
    final separator = text.indexOf(':');
    final head = separator == -1 ? text : text.substring(0, separator);
    return head.trim();
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
