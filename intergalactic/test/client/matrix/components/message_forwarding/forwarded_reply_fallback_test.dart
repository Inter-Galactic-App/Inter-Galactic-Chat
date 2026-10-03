import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/message_forwarding/matrix_message_forwarder.dart';

/// A plain-text reply leaked its quoted author's MXID through a forward.
///
/// READ FROM THE SDK SOURCE at matrix-dart-sdk-58e0bd24, not measured:
/// `formattedText` is `content['formatted_body'] ?? ''`, and `plaintextBody`
/// returns `body` VERBATIM when that is empty. So a reply WITH `formatted_body`
/// was already safe - `HtmlToText.convert` strips `<mx-reply>`, and the SDK's
/// own comment says it does that to prevent impersonation - but a reply WITHOUT
/// one carried its legacy `> <@alice:example.org> quoted text` fallback into
/// the destination room.
///
/// The forwarder could already see that content. The quoted author's MXID is
/// the new part: the destination room may have no idea who they are, and
/// ForwardedMessagePayload states it carries no source references.
void main() {
  Map<String, Object?> replyContent() => {
    'msgtype': 'm.text',
    'body': '',
    'm.relates_to': {
      'm.in_reply_to': {'event_id': r'$quoted:example.org'},
    },
  };

  group('the legacy reply fallback never reaches a destination room', () {
    test('a plain-text reply drops the quoted author and their MXID', () {
      final body = MatrixMessageForwarder.forwardedVisibleBody(
        content: replyContent(),
        plaintextBody:
            '> <@alice:example.org> the original question\n\nmy answer',
      );

      expect(body, 'my answer');
      expect(body, isNot(contains('@alice:example.org')));
    });

    test('a multi-line quote block is dropped whole', () {
      final body = MatrixMessageForwarder.forwardedVisibleBody(
        content: replyContent(),
        plaintextBody:
            '> <@alice:example.org> first line\n'
            '> second line\n'
            '> third line\n'
            '\n'
            'my answer',
      );

      expect(body, 'my answer');
      expect(body, isNot(contains('@alice:example.org')));
    });

    test('a reply whose own text starts with a quote keeps that text', () {
      final body = MatrixMessageForwarder.forwardedVisibleBody(
        content: replyContent(),
        plaintextBody:
            '> <@alice:example.org> the original question\n'
            '\n'
            '> quoting them back at them\n'
            'and my point',
      );

      expect(body, '> quoting them back at them\nand my point');
      expect(body, isNot(contains('@alice:example.org')));
    });

    test('a reply with no fallback block is unchanged', () {
      final body = MatrixMessageForwarder.forwardedVisibleBody(
        content: replyContent(),
        plaintextBody: 'my answer',
      );

      expect(body, 'my answer');
    });

    // The gate, not just the strip. An ordinary message is not a reply and
    // never carries a fallback, so its own quoting is the message.
    test('an ordinary message beginning with a quote is left alone', () {
      const quoted = '> a line I am quoting on purpose\n\nand my point';

      expect(
        MatrixMessageForwarder.forwardedVisibleBody(
          content: const {'msgtype': 'm.text', 'body': quoted},
          plaintextBody: quoted,
        ),
        quoted,
      );
    });

    test('a thread relation without a reply is not treated as a reply', () {
      const quoted = '> not a fallback\n\ntext';

      expect(
        MatrixMessageForwarder.forwardedVisibleBody(
          content: const {
            'msgtype': 'm.text',
            'body': quoted,
            'm.relates_to': {
              'rel_type': 'm.thread',
              'event_id': r'$root:example.org',
            },
          },
          plaintextBody: quoted,
        ),
        quoted,
      );
    });

    // A reply WITH formatted_body already arrives here stripped, because
    // plaintextBody went through HtmlToText. Nothing should be removed twice.
    //
    // forwardedVisibleBody reads no HTML, so there is no formatted branch to
    // enter and asserting on a bare `plaintextBody: 'my answer'` only repeats
    // the "no fallback block" case above. What is unique to the HTML case is
    // the input SHAPE: `body` still carries the raw fallback the SDK left
    // alone, and the already-stripped plaintextBody is the only safe source.
    // Reaching for `body` here - "the SDK handled it, so the original is
    // fine" - forwards the quoted author's MXID.
    test('an html reply body, already stripped by the SDK, is unchanged', () {
      final body = MatrixMessageForwarder.forwardedVisibleBody(
        content: {
          ...replyContent(),
          'body': '> <@alice:example.org> the original question\n\nmy answer',
          'format': 'org.matrix.custom.html',
          'formatted_body':
              '<mx-reply><blockquote>'
              '<a href="https://matrix.to/#/@alice:example.org">'
              '@alice:example.org</a> the original question'
              '</blockquote></mx-reply>my answer',
        },
        plaintextBody: 'my answer',
      );

      expect(body, 'my answer');
      expect(body, isNot(contains('@alice:example.org')));
    });

    test('a fallback with no message after it yields an empty body', () {
      final body = MatrixMessageForwarder.forwardedVisibleBody(
        content: replyContent(),
        plaintextBody: '> <@alice:example.org> the original question',
      );

      expect(body, isEmpty);
    });
  });
}
