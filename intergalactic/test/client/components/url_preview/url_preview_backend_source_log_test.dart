import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/components/url_preview/matrix_url_preview_component.dart';
import 'package:intergalactic/config/app_globals.dart' as globals;
import 'package:intergalactic/debug/log.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';

/// The resolved log line has to name WHICH backend answered.
///
/// `server_used=true` means only that some server answered, and
/// `fetchConfiguredPreviewResponse` falls back from the Inter Galactic
/// service to the homeserver's native preview silently on every failure mode.
/// The owner's 2026-09-11 capture was taken to measure the service with the
/// direct-fetch fallback deliberately off; at least 21 of its responses were
/// provably Synapse's instead, and nothing in the capture said so.
///
/// These cases assert the line itself, not an internal field, because the
/// capture is the artefact anyone reads.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    Log.log.clear();
  });

  Uri previewUrl() => Uri.parse('https://example.com/article');

  String resolvedLine() {
    final resolved = Log.log
        .where((entry) => entry.content.contains('URL preview resolved'))
        .toList();
    // Arming: a missing line would make every `contains` below vacuous, and
    // Log.d is silent unless verbose diagnostics are on.
    expect(
      resolved,
      hasLength(1),
      reason: 'the resolved line must be logged exactly once per build',
    );
    return resolved.single.content;
  }

  test('source=intergalactic when the preview service answers', () async {
    final component = MatrixUrlPreviewComponent(
      _FakeMatrixClient('client-a'),
      intergalacticPreviewFetcher: (_) async => {
        'og:title': 'Service title',
        'og:description': 'Service description',
      },
      responseFetcher: (_, _) async =>
          fail('the homeserver must not be asked once the service answered'),
      uriNormalizer: (uri) async => uri,
    );

    await component.buildPreviewData(
      _FakeSdkClient(),
      previewUrl(),
      roomIsE2EE: false,
    );

    expect(resolvedLine(), contains('source=intergalactic'));
  });

  test('source=synapse when the service returns null and the homeserver '
      'answers', () async {
    final component = MatrixUrlPreviewComponent(
      _FakeMatrixClient('client-b'),
      intergalacticPreviewFetcher: (_) async => null,
      responseFetcher: (_, _) async => {
        'og:title': 'Homeserver title',
        'og:description': 'Homeserver description',
      },
      uriNormalizer: (uri) async => uri,
    );

    await component.buildPreviewData(
      _FakeSdkClient(),
      previewUrl(),
      roomIsE2EE: false,
    );

    final line = resolvedLine();
    expect(line, contains('source=synapse'));
    // The pair is the point: this is exactly the shape the capture could not
    // distinguish, because server_used reads the same either way.
    expect(line, contains('server_used=true'));
  });

  test('source=none when neither backend answers', () async {
    final component = MatrixUrlPreviewComponent(
      _FakeMatrixClient('client-c'),
      intergalacticPreviewFetcher: (_) async => null,
      responseFetcher: (_, _) async => null,
      uriNormalizer: (uri) async => uri,
    );

    await component.buildPreviewData(
      _FakeSdkClient(),
      previewUrl(),
      roomIsE2EE: false,
    );

    expect(resolvedLine(), contains('source=none'));
  });
}

class _FakeMatrixClient implements MatrixClient {
  _FakeMatrixClient(this.identifier);

  @override
  final String identifier;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSdkClient implements matrix.Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
