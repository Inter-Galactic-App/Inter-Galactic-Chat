import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/url_preview/url_preview_component.dart';
import 'package:intergalactic/client/matrix/components/url_preview/url_preview_fallback_fetcher.dart';

/// Guards the site-icon fallback CALL SITE, not just its predicate.
///
/// REVIEW measured the gap at the merge of PR #282: deleting
/// `_withSiteIconFallback` from `fetchPreview` entirely - so the fallback never
/// runs in production - left the url_preview suite 50/50 green. The predicate
/// had six tests; the call that invokes it had none, because it sits behind two
/// real HTTP fetches that no test could reach.
///
/// These tests inject through `fetchPreview` itself rather than around it, so
/// they exercise the real call site. Removing the call turns them red.
void main() {
  final providerUri = Uri.parse('https://www.instagram.com/p/example');
  final iconUri = Uri.parse('https://www.instagram.com/apple-touch-icon.png');

  Future<UrlPreviewSiteIcon?> icon(Uri uri) async => UrlPreviewSiteIcon(
    provider: const NetworkImage('https://www.instagram.com/icon.png'),
    uri: iconUri,
    width: 180,
    height: 180,
  );

  Future<UrlPreviewSiteIcon?> noIcon(Uri uri) async => null;

  test('a preview with no image comes back carrying the site icon', () async {
    final result = await UrlPreviewFallbackFetcher.fetchPreview(
      providerUri,
      providerFetcher: (uri) async =>
          UrlPreviewData(uri, siteName: 'Instagram', title: 'Blocked thumb'),
      siteIconFetcher: icon,
    );

    expect(result, isNotNull);
    expect(
      result!.imageUri,
      iconUri,
      reason:
          'this is the assertion that fails if the fallback call is removed '
          'from fetchPreview',
    );
    expect(result.image, isNotNull);
    expect(result.imageWidth, 180);
    expect(result.title, 'Blocked thumb', reason: 'the card is not replaced');
  });

  test('a preview that already has an image is returned untouched', () async {
    final realImage = Uri.parse('https://cdn.test/real-thumbnail.jpg');
    final result = await UrlPreviewFallbackFetcher.fetchPreview(
      providerUri,
      providerFetcher: (uri) async => UrlPreviewData(
        uri,
        siteName: 'Instagram',
        imageUri: realImage,
        image: NetworkImage(realImage.toString()),
      ),
      siteIconFetcher: icon,
    );

    expect(
      result!.imageUri,
      realImage,
      reason: 'the site icon must never displace a real thumbnail',
    );
  });

  test('a preview survives the icon lookup returning nothing', () async {
    final result = await UrlPreviewFallbackFetcher.fetchPreview(
      providerUri,
      providerFetcher: (uri) async =>
          UrlPreviewData(uri, siteName: 'Instagram', title: 'No icon either'),
      siteIconFetcher: noIcon,
    );

    expect(result, isNotNull);
    expect(result!.title, 'No icon either');
    expect(result.imageUri, isNull);
  });

  test(
    'a null provider preview stays null rather than becoming an icon card',
    () async {
      final result = await UrlPreviewFallbackFetcher.fetchPreview(
        providerUri,
        providerFetcher: (uri) async => null,
        siteIconFetcher: icon,
      );

      expect(
        result,
        isNull,
        reason:
            'a site icon alone is not a preview - there is no title or source to '
            'attach it to',
      );
    },
  );

  test('the host gates still run before any injected fetcher', () async {
    var providerCalled = false;
    final result = await UrlPreviewFallbackFetcher.fetchPreview(
      Uri.parse('https://example.test/some/article'),
      providerFetcher: (uri) async {
        providerCalled = true;
        return UrlPreviewData(uri, siteName: 'Example');
      },
      siteIconFetcher: icon,
    );

    expect(result, isNull);
    expect(
      providerCalled,
      isFalse,
      reason:
          'the test seams must not become a way around shouldPreferDirectFetch; '
          'that gate is what 90f75c96 closed on 2026-05-20',
    );
  });
}
