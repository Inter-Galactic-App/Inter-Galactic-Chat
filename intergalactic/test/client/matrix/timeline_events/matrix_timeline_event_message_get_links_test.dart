import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_message.dart';
import 'package:matrix/matrix.dart' as matrix;

// Owner-reported, 2026-09-11: getLinks read the HTML formatted body directly.
// HTML entity-encodes `&` as `&amp;`, and the URL regex does not match `;`,
// so a query string containing `&` (routine on TikTok, YouTube, and most
// tracking links) truncated at `&amp` - the preview request that followed
// was for a URL that was never the real one.
//
// This exercises MatrixTimelineEventMessage.getLinks directly, on a real
// matrix.Event, rather than only the unescape-then-findUrls sequence
// text_utils_test.dart pins - REVIEW pointed at
// matrix_background_events_test.dart's fake-DatabaseApi client and
// matrix_room_decrypt_retry_test.dart's real matrix.Event construction as
// the pattern to follow.
void main() {
  test('getLinks recovers the real URL from an HTML-entity-encoded query '
      'string', () {
    const realUrl = 'https://www.tiktok.com/@u/video/1?a=1&b=2';
    const formattedBody =
        '<a href="https://www.tiktok.com/@u/video/1?a=1&amp;b=2">'
        'https://www.tiktok.com/@u/video/1?a=1&amp;b=2</a>';

    final mxClient = matrix.Client(
      'link-only-html-amp-test',
      database: _FakeMatrixDatabase(),
    );
    final room = matrix.Room(id: '!room:example.org', client: mxClient);
    final mxEvent = matrix.Event(
      content: const {
        'msgtype': 'm.text',
        'body': realUrl,
        'format': 'org.matrix.custom.html',
        'formatted_body': formattedBody,
      },
      type: 'm.room.message',
      eventId: r'$amp-truncation-event',
      senderId: '@alice:example.org',
      originServerTs: DateTime.utc(2026, 9, 11),
      room: room,
    );

    final message = MatrixTimelineEventMessage(
      mxEvent,
      client: _FakeMatrixClient(),
    );

    final links = message.getLinks();

    expect(links, isNotNull);
    expect(
      links!.map((uri) => uri.toString()).toSet(),
      {realUrl},
      reason:
          'without HtmlUnescape().convert before findUrls, this returns '
          'the truncated https://www.tiktok.com/@u/video/1?a=1&amp - the '
          'preview request itself would be for the wrong URL',
    );
  });
}

class _FakeMatrixDatabase implements matrix.DatabaseApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMatrixClient implements MatrixClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
