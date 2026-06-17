import 'package:intergalactic/config/build_config.dart';
import 'package:http/http.dart' as http;

class MatrixUserAgentHttpClient extends http.BaseClient {
  MatrixUserAgentHttpClient([http.Client? inner])
      : _inner = inner ?? http.Client();

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers
        .putIfAbsent('User-Agent', () => BuildConfig.matrixUserAgent);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
