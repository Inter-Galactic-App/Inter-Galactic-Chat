import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/url_preview/url_preview_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/components/url_preview/matrix_url_preview_component.dart';
import 'package:intergalactic/client/matrix/components/url_preview/url_preview_durable_cache.dart';
import 'package:intergalactic/client/matrix/components/url_preview/url_preview_fallback_fetcher.dart';
import 'package:intergalactic/config/app_globals.dart' as globals;
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';

/// Owner decision, 2026-09-09 (url-preview-privacy-routing).
///
/// The homeserver/service path is now preferred unconditionally, in both
/// room types - direct fetch to a third-party CDN only ever runs as a
/// FALLBACK, and only when the service result was insufficient. These cases
/// pin the part `matrix_url_preview_component_test.dart` grants by default in
/// its own `setUp` (so its existing fallback-mechanics coverage stays
/// meaningful): that the fallback does NOT run at all without that grant,
/// that encrypted and unencrypted consent are independent - granting one
/// must not leak into the other - and that this is a genuine ROUTING
/// decision, not merely which data wins a merge, by using a host
/// (`instagram.com`) where the server answer is deliberately insufficient
/// and the fallback is the only way an image or description could appear.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
  });

  Uri previewUrl() => Uri.parse('https://www.instagram.com/p/example');

  MatrixUrlPreviewComponent componentWithDirectFetcher(
    void Function() onDirectCall,
  ) {
    return MatrixUrlPreviewComponent(
      _FakeMatrixClient('client-a'),
      // Insufficient on its own (score < 4): only a title, no image or
      // description. If the fallback is genuinely reachable, this alone
      // would not explain a preview carrying "Direct description".
      responseFetcher: (_, __) async => {'og:title': 'Instagram'},
      directFetcher: (uri) {
        onDirectCall();
        return Future<UrlPreviewData?>.value(
          UrlPreviewData(
            uri,
            siteName: 'Instagram',
            title: 'Instagram post',
            description: 'Direct description',
          ),
        );
      },
      uriNormalizer: (uri) async => uri,
    );
  }

  test(
    'the default (no consent) blocks the fallback in an unencrypted room',
    () async {
      var directCalls = 0;
      final component = componentWithDirectFetcher(() => directCalls++);

      final result = await component.buildPreviewData(
        _FakeSdkClient(),
        previewUrl(),
        roomIsE2EE: false,
      );

      expect(
        directCalls,
        0,
        reason: 'opt-in defaults false; nothing has been granted yet',
      );
      expect(result?.description, isNull);
    },
  );

  test(
    'the default (no consent) blocks the fallback in an encrypted room',
    () async {
      var directCalls = 0;
      final component = componentWithDirectFetcher(() => directCalls++);

      final result = await component.buildPreviewData(
        _FakeSdkClient(),
        previewUrl(),
        roomIsE2EE: true,
      );

      expect(directCalls, 0);
      expect(result?.description, isNull);
    },
  );

  test('granting the UNENCRYPTED preference does not unlock the fallback for '
      'an encrypted room', () async {
    await globals.preferences.allowDirectUrlPreviewFallbackInUnencryptedChat
        .set(true);
    var directCalls = 0;
    final component = componentWithDirectFetcher(() => directCalls++);

    final result = await component.buildPreviewData(
      _FakeSdkClient(),
      previewUrl(),
      roomIsE2EE: true,
    );

    expect(
      directCalls,
      0,
      reason:
          'the two settings are independent per the owner\'s decision - '
          'the disclosure argument differs by room type, so consent for '
          'one must not leak into the other',
    );
    expect(result?.description, isNull);
  });

  test('granting the ENCRYPTED preference does not unlock the fallback for an '
      'unencrypted room', () async {
    await globals.preferences.allowDirectUrlPreviewFallbackInE2EEChat.set(true);
    var directCalls = 0;
    final component = componentWithDirectFetcher(() => directCalls++);

    final result = await component.buildPreviewData(
      _FakeSdkClient(),
      previewUrl(),
      roomIsE2EE: false,
    );

    expect(directCalls, 0);
    expect(result?.description, isNull);
  });

  test('granting the matching preference unlocks the fallback for an '
      'unencrypted room', () async {
    await globals.preferences.allowDirectUrlPreviewFallbackInUnencryptedChat
        .set(true);
    var directCalls = 0;
    final component = componentWithDirectFetcher(() => directCalls++);

    final result = await component.buildPreviewData(
      _FakeSdkClient(),
      previewUrl(),
      roomIsE2EE: false,
    );

    expect(directCalls, 1);
    expect(result?.description, 'Direct description');
  });

  test('granting the matching preference unlocks the fallback for an '
      'encrypted room', () async {
    await globals.preferences.allowDirectUrlPreviewFallbackInE2EEChat.set(true);
    var directCalls = 0;
    final component = componentWithDirectFetcher(() => directCalls++);

    final result = await component.buildPreviewData(
      _FakeSdkClient(),
      previewUrl(),
      roomIsE2EE: true,
    );

    expect(directCalls, 1);
    expect(result?.description, 'Direct description');
  });

  // REVIEW, 2026-09-09: `_withProviderSiteIcon` fetches the provider's own
  // site icon (apple-touch-icon etc, on instagram.com/tiktok.com/reddit.com
  // itself) whenever the assembled preview has no image, and it used to run
  // unconditionally off `shouldPreferDirectFetch` alone - a third bypass of
  // the same consent gate, on a third entry path, found by REVIEW while
  // answering an unrelated owner question rather than by a test failing.
  test('the default (no consent) blocks the site-icon fetch, not just the '
      'direct preview fetch', () async {
    var siteIconCalls = 0;
    final component = MatrixUrlPreviewComponent(
      _FakeMatrixClient('client-a'),
      // No image or description either - shouldUseSiteIconFallback would
      // say yes, so only the consent gate can be stopping this.
      responseFetcher: (_, __) async => {'og:title': 'Instagram'},
      siteIconFetcher: (uri) {
        siteIconCalls++;
        return Future<UrlPreviewSiteIcon?>.value(null);
      },
      uriNormalizer: (uri) async => uri,
    );

    await component.buildPreviewData(
      _FakeSdkClient(),
      previewUrl(),
      roomIsE2EE: false,
    );

    expect(
      siteIconCalls,
      0,
      reason:
          'a site-icon request still reaches the provider\'s own origin; '
          'declining the fallback must block it exactly like the direct '
          'preview fetch',
    );
  });

  // REVIEW, 2026-09-09: the durable-cache-hit path returns BEFORE control
  // ever reaches _buildPreviewData, so a gate placed only in the build chain
  // is bypassed entirely on a second view of the same URL. Worse, the
  // bypass is armed BY a correct decline: a first view that honours the
  // user's refusal caches a preview with image/imageUri null and
  // volatileImageOmitted true - exactly the shape
  // `_isMissingImageRefreshCandidate` looks for - so the refusal itself
  // becomes the trigger for the second view's unconsented fetch.
  test(
    'a durable-cache hit does not fire the direct fetch the user declined',
    () async {
      final previewUri = Uri.parse(
        'https://www.instagram.com/p/declined-then-cached',
      );
      final durableCache = UrlPreviewDurableCache(
        preferences: await SharedPreferences.getInstance(),
        prefix: 'url-preview-decline-bypass-test',
      );
      // Exactly what a correctly-declined first view leaves behind.
      await durableCache.put(
        previewUri,
        UrlPreviewData(
          previewUri,
          siteName: 'Instagram',
          title: 'Instagram post',
          volatileImageOmitted: true,
        ),
      );

      var directCalls = 0;
      final component = MatrixUrlPreviewComponent(
        _FakeMatrixClient('client-a'),
        responseFetcher: (_, __) async => null,
        directFetcher: (uri) {
          directCalls++;
          return Future<UrlPreviewData?>.value(
            UrlPreviewData(
              uri,
              siteName: 'Instagram',
              title: 'Instagram post',
              imageUri: Uri.parse('https://scontent.cdninstagram.com/img'),
            ),
          );
        },
        uriNormalizer: (uri) async => uri,
        matrixClientProvider: (_) => _FakeSdkClient(),
        durableCache: durableCache,
      );
      final room = _FakeRoom(
        identifier: '!room:example.org',
        client: _FakeMatrixClient('client-a'),
      );

      final result = await component.getPreviewForUrl(room, previewUri);

      expect(
        directCalls,
        0,
        reason:
            'consent was never granted, so the cached image-missing state '
            'must not arm a direct fetch on a later view either',
      );
      expect(result?.image, isNull);
      expect(result?.imageUri, isNull);
    },
  );

  test('preferences.shouldAllowDirectUrlPreviewFallback reads the right '
      'preference for each room state', () async {
    expect(
      globals.preferences.shouldAllowDirectUrlPreviewFallback(
        roomIsE2EE: false,
      ),
      isFalse,
    );
    expect(
      globals.preferences.shouldAllowDirectUrlPreviewFallback(roomIsE2EE: true),
      isFalse,
    );

    await globals.preferences.allowDirectUrlPreviewFallbackInUnencryptedChat
        .set(true);

    expect(
      globals.preferences.shouldAllowDirectUrlPreviewFallback(
        roomIsE2EE: false,
      ),
      isTrue,
    );
    expect(
      globals.preferences.shouldAllowDirectUrlPreviewFallback(roomIsE2EE: true),
      isFalse,
      reason: 'still independent - only the unencrypted grant was made',
    );
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

class _FakeRoom implements Room {
  _FakeRoom({required this.identifier, required this.client});

  @override
  final String identifier;

  @override
  final Client client;

  @override
  bool get isE2EE => false;

  @override
  bool get shouldPreviewMedia => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
