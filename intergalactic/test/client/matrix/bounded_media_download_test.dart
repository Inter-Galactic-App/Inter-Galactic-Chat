import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intergalactic/client/matrix/components/stories/matrix_story_component.dart';
import 'package:intergalactic/client/matrix/matrix_mxc_file_provider.dart';

void main() {
  group('downloadBoundedMatrixStoryMediaResponse', () {
    test(
      'accepts a streamed response with no Content-Length below the cap',
      () async {
        final client = _RecordingClient(
          http.StreamedResponse(
            Stream<Uint8List>.fromIterable([
              Uint8List.fromList([1, 2]),
              Uint8List.fromList([3]),
            ]),
            200,
          ),
        );

        final bytes = await downloadBoundedMatrixStoryMediaResponse(
          client,
          Uri.parse('https://example.test/media'),
          accessToken: 'test-token',
          maxBytes: 3,
        );

        expect(bytes, [1, 2, 3]);
        expect(
          client.lastRequest!.headers['authorization'],
          'Bearer test-token',
        );
      },
    );

    test(
      'aborts a body that exceeds the cap despite a falsely small length',
      () async {
        final client = _RecordingClient(
          http.StreamedResponse(
            Stream<Uint8List>.fromIterable([
              Uint8List.fromList([1, 2]),
              Uint8List.fromList([3, 4]),
            ]),
            200,
            contentLength: 1,
          ),
        );

        await expectLater(
          downloadBoundedMatrixStoryMediaResponse(
            client,
            Uri.parse('https://example.test/media'),
            accessToken: null,
            maxBytes: 3,
          ),
          throwsA(isA<StateError>()),
        );
      },
    );
  });

  test(
    'event-backed MXC downloads close their short-lived HTTP client',
    () async {
      final client = _RecordingClient(
        http.StreamedResponse(
          Stream<Uint8List>.value(Uint8List.fromList([4, 5, 6])),
          200,
          contentLength: 3,
        ),
      );

      final bytes = await MxcFileProvider.downloadEventBackedMedia(
        Uri.parse('https://example.test/media'),
        accessToken: 'test-token',
        createClient: () => client,
      );

      expect(bytes, [4, 5, 6]);
      expect(client.closed, isTrue);
      expect(client.lastRequest!.headers['authorization'], 'Bearer test-token');
    },
  );
}

class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.response);

  final http.StreamedResponse response;
  bool closed = false;
  http.BaseRequest? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    return response;
  }

  @override
  void close() {
    closed = true;
  }
}
