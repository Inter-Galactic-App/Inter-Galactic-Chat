import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/url_preview/url_preview_component.dart';
import 'package:intergalactic/client/matrix/components/url_preview/matrix_url_preview_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_mxc_image_provider.dart';
import 'package:intergalactic/config/app_globals.dart' as globals;
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';

/// The homeserver's `preview_url` response gives us a URL *string*. Building a
/// [NetworkImage] from it does not reuse that request - it makes the CLIENT
/// open its own connection to fbcdn/tiktokcdn/Instagram, disclosing the user's
/// IP, TLS fingerprint and default User-Agent to a third party, including for
/// a preview rendered inside an end-to-end encrypted room.
///
/// So the invariant pinned here is structural rather than per-host: no preview
/// built from a server response may carry an image the client would fetch
/// itself. Only an `mxc://` value renders, because that is served by the
/// homeserver's own media/thumbnail endpoint.

const _fbImage =
    'https://scontent.xx.fbcdn.net/v/t39/demo.jpg?_nc_cat=1&oh=s&oe=6700';

const _igImage =
    'https://scontent.cdninstagram.com/v/t51/demo.jpg?oh=hash&oe=exp';

const _tiktokImage =
    'https://p16-sign.tiktokcdn-us.com/obj/demo.jpeg?x-expires=1757';

const _plainCdnImage = 'https://cdn.example.test/real-thumbnail.jpg';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.applyUrlPreviewE2EEConsentChoice(allow: true);
  });

  UrlPreviewData? build(Map<String, Object?> response) {
    return MatrixUrlPreviewComponent(
      _FakeMatrixClient('client-a'),
    ).buildPreviewFromResponse(
      _FakeSdkClient(),
      Uri.parse('https://example.test/post/1'),
      response,
    );
  }

  group('a server preview never renders a directly fetched image', () {
    // The unsigned CDN entry is the one that matters most: a fix that only
    // dropped "volatile" signed social URLs would still leak on it.
    final thirdPartyImages = <String, String>{
      'facebook': _fbImage,
      'instagram': _igImage,
      'tiktok': _tiktokImage,
      'unsigned-cdn': _plainCdnImage,
    };

    for (final entry in thirdPartyImages.entries) {
      test('${entry.key} CDN image is dropped, not fetched', () {
        final result = build({
          'og:site_name': 'Example',
          'og:title': 'A post',
          'og:image': entry.value,
        });

        expect(result, isNotNull, reason: 'the text card still renders');
        expect(
          result?.image,
          isNull,
          reason:
              'an ImageProvider here is fetched by the client, so '
              '${entry.key} would see the user directly',
        );
        expect(
          result?.imageUri,
          isNull,
          reason:
              'imageUri alone is enough to render after a cache restore, so '
              'it has to be dropped too',
        );
        expect(
          result?.volatileImageOmitted,
          isTrue,
          reason:
              'dropping arms the missing-image refresh path for the hosts '
              'already allowlisted for a direct fetch',
        );
      });
    }

    test('no image key can smuggle a client-fetched provider through', () {
      // Every key buildPreviewFromResponse reads, all pointing at a third
      // party at once. A partial fix guarding only `og:image` is red here.
      final result = build({
        'og:title': 'A post',
        'og:image:secure_url': 'https://cdn.example.test/a.jpg',
        'og:image:url': 'https://cdn.example.test/b.jpg',
        'og:image': 'https://cdn.example.test/c.jpg',
        'twitter:image': 'https://cdn.example.test/d.jpg',
        'twitter:image:src': 'https://cdn.example.test/e.jpg',
        'image_url': 'https://cdn.example.test/f.jpg',
        'imageUrl': 'https://cdn.example.test/g.jpg',
        'image': 'https://cdn.example.test/h.jpg',
      });

      expect(result?.image, isNull);
      expect(result?.imageUri, isNull);
    });

    test('an http image URL is dropped as well as an https one', () {
      final result = build({
        'og:title': 'A post',
        'og:image': 'http://cdn.example.test/plain.jpg',
      });

      expect(result?.image, isNull);
      expect(result?.imageUri, isNull);
    });
  });

  group('homeserver media still renders', () {
    test('an mxc image is routed through the homeserver', () {
      final mxc = Uri.parse('mxc://example.org/abc123');
      final result = build({'og:title': 'A post', 'og:image': mxc.toString()});

      final image = result?.image;
      expect(
        image,
        isA<MatrixMxcImage>(),
        reason:
            'MatrixMxcImage loads via getContentThumbnailFromUri / '
            'getContentFromUri, which are homeserver endpoints',
      );
      expect((image as MatrixMxcImage).identifier, mxc);
      expect(result?.imageUri, mxc);
      expect(
        result?.volatileImageOmitted,
        isFalse,
        reason: 'nothing was dropped, so the refresh path stays disarmed',
      );
    });

    test('an mxc value wins over an earlier https image key', () {
      // The homeserver rewrites `og:image` to mxc but leaves scraped keys
      // such as `og:image:secure_url` as the origin's own URL. Reading
      // strictly in key order would take the https one and discard the mxc we
      // can actually serve from the homeserver.
      final mxc = Uri.parse('mxc://example.org/abc123');
      final result = build({
        'og:title': 'A post',
        'og:image:secure_url': 'https://cdn.example.test/origin.jpg',
        'og:image': mxc.toString(),
      });

      expect(result?.imageUri, mxc);
      expect(result?.image, isA<MatrixMxcImage>());
    });
  });

  test('the whole component path drops a third-party image', () async {
    // buildPreviewData, not just the response builder: this is the path the
    // timeline calls, and facebook.com is not a direct-fetch provider, so
    // nothing downstream may reintroduce an image either.
    final sdkClient = _FakeSdkClient();
    var siteIconCalls = 0;
    final subject = MatrixUrlPreviewComponent(
      _FakeMatrixClient('client-a'),
      responseFetcher: (_, __) async => {
        'og:site_name': 'Facebook',
        'og:title': 'Facebook post',
        'og:image': _fbImage,
      },
      directFetcher: (_) async => null,
      siteIconFetcher: (_) async {
        siteIconCalls += 1;
        return null;
      },
      uriNormalizer: (uri) async => uri,
      matrixClientProvider: (_) => sdkClient,
    );

    final result = await subject.buildPreviewData(
      sdkClient,
      Uri.parse('https://www.facebook.com/some/post/1234'),
      roomIsE2EE: false,
    );

    expect(result?.title, 'Facebook post');
    expect(result?.image, isNull);
    expect(result?.imageUri, isNull);
    expect(
      siteIconCalls,
      0,
      reason: 'facebook.com is outside the direct-fetch provider allowlist',
    );
  });

  test('no NetworkImage ever leaves the server response builder', () {
    // The mutation guard: if the dropped branch is ever restored to
    // `image = NetworkImage(...)` this fails regardless of which host or
    // response key the value arrived on.
    final responses = <Map<String, Object?>>[
      {'og:title': 't', 'og:image': _plainCdnImage},
      {'og:title': 't', 'twitter:image': _igImage},
      {'og:title': 't', 'image': 'http://cdn.example.test/c.jpg'},
      {
        'og:title': 't',
        'og:image': _plainCdnImage,
        'og:image:type': 'image/jpeg',
      },
    ];

    for (final response in responses) {
      final result = build(response);
      expect(
        result?.image,
        isNot(isA<NetworkImage>()),
        reason: 'a NetworkImage is a client-side fetch of $response',
      );
      expect(result?.imageUri?.scheme, isNot(anyOf('http', 'https')));
    }
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
