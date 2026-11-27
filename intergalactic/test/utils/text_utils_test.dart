import 'package:flutter_test/flutter_test.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:intergalactic/utils/text_utils.dart';

// Owner-reported, 2026-09-11: MatrixTimelineEventMessage.getLinks runs
// TextUtils.findUrls directly on the HTML formatted body. HTML entity-encodes
// `&` as `&amp;`, and the URL regex `findUrls` uses does not match `;`, so a
// query string containing `&` (routine on TikTok, YouTube, and most tracking
// links) truncates at `&amp` when read from HTML. getLinks now unescapes the
// formatted body first - `HtmlUnescape().convert(text)`, the same call this
// codebase already uses in matrix_room.dart and matrix_profile_component.dart
// - before calling findUrls, so this pins that exact sequence rather than the
// real getLinks method.
//
// This is deliberately NOT a test of MatrixTimelineEventMessage.getLinks
// itself: that class requires a real matrix.Event/Room/Client from the SDK,
// which in turn requires a real DatabaseApi - no test in this repo
// constructs that chain for a focused unit test, and doing so here would be
// disproportionate to a two-line fix. The TimelineEventViewMessage-level
// widget test (timeline_event_view_message_url_preview_wiring_test.dart)
// covers the other half of this same bug - _messageIsOnlyPreviewLinks - with
// a fake TimelineEventMessage whose getLinks and plainTextBody deliberately
// disagree, the shape this real bug actually produced.
void main() {
  test('a raw (unescaped) query string with & is found in full', () {
    const url = 'https://www.tiktok.com/@u/video/1?a=1&b=2';
    expect(TextUtils.findUrls(url), [Uri.parse(url)]);
  });

  test('an HTML-entity-encoded query string with &amp; truncates at findUrls '
      'without unescaping first - this is the bug, pinned so the fix below '
      'reads as a fix rather than a coincidence', () {
    const html =
        '<a href="https://www.tiktok.com/@u/video/1?a=1&amp;b=2">'
        'https://www.tiktok.com/@u/video/1?a=1&amp;b=2</a>';

    final found = TextUtils.findUrls(html);

    expect(found, isNotNull);
    expect(
      found!.first.toString(),
      isNot('https://www.tiktok.com/@u/video/1?a=1&b=2'),
      reason:
          'findUrls on raw HTML does not recover the real URL - '
          'unescaping first is what getLinks now does',
    );
  });

  test('unescaping the HTML body before findUrls recovers the real, '
      'untruncated URL', () {
    const html =
        '<a href="https://www.tiktok.com/@u/video/1?a=1&amp;b=2">'
        'https://www.tiktok.com/@u/video/1?a=1&amp;b=2</a>';
    const realUrl = 'https://www.tiktok.com/@u/video/1?a=1&b=2';

    final found = TextUtils.findUrls(HtmlUnescape().convert(html));

    expect(
      found?.map((uri) => uri.toString()).toSet(),
      {realUrl},
      reason:
          'this is the exact sequence getLinks now runs: unescape the '
          'formatted body, then findUrls',
    );
  });
}
