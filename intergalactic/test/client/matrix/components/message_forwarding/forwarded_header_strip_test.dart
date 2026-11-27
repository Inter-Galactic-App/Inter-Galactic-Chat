import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/message_forwarding/forwarded_message_payload.dart';
import 'package:intergalactic/client/matrix/components/message_forwarding/matrix_forwarded_message.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_message.dart';

/// Owner screen grab, 2026-09-05: a forwarded message showed its attribution
/// twice - once as the label above the message and again as the message body.
///
/// A forward carries the attribution in two places on purpose. The presentation
/// envelope is what this client draws; the header line inside `body` is the
/// fallback for a client that cannot read the envelope. Rendering the body
/// verbatim therefore printed the same sentence twice, and a forward with no
/// text of its own had the header as its entire message.
const _label = 'Ankle Biter';
const _id = '@impurexchaos:ourgalaxy.space';

void main() {
  const presentation = MatrixForwardedPresentation(
    originalAuthorId: _id,
    originalAuthorLabel: _label,
  );

  ForwardedMessagePayload payloadFor(String body) => ForwardedMessagePayload(
    originalAuthorId: _id,
    originalAuthorDisplayName: _label,
    body: body,
    formattedBody: body.isEmpty ? null : body,
  );

  group('the stripper is tied to the writer', () {
    // The load-bearing pair. Everything else here asserts a rule; these two
    // assert that the rule is still the SAME rule the sending side follows.
    // A stripper that spells the header out for itself keeps passing its own
    // tests on the day the writer's wording changes, and the symptom is
    // exactly the bug this fixes.
    test('stripping what the payload writes leaves the original body', () {
      final payload = payloadFor('have you seen this');

      expect(
        presentation.stripFallbackHeader(payload.fallbackBody),
        'have you seen this',
      );
    });

    test('stripping the formatted body leaves the original markup', () {
      final payload = payloadFor('have you seen this');

      expect(
        presentation.stripFallbackHeaderHtml(payload.fallbackFormattedBody),
        'have you seen this',
      );
    });

    test('a forward with no text of its own strips to nothing', () {
      // The screen-grab case: an attachment forward, whose whole body is the
      // header. This is what makes the header render as the message.
      final payload = payloadFor('');

      expect(presentation.stripFallbackHeader(payload.fallbackBody), isEmpty);
      expect(
        presentation.stripFallbackHeaderHtml(payload.fallbackFormattedBody),
        isEmpty,
      );
    });
  });

  group('plain bodies', () {
    test('the header and the blank line after it are removed', () {
      expect(
        presentation.stripFallbackHeader(
          'Forwarded from $_label ($_id)\n\nthe message',
        ),
        'the message',
      );
    });

    test('a body that does not start with the header is untouched', () {
      // Deliberately not a fuzzy match. A forward that was edited, or written
      // by another client wording its attribution differently, must lose
      // nothing: printing the line twice is a blemish, deleting the first line
      // of someone's message is not.
      const body = 'Forwarded from someone else\n\nthe message';

      expect(presentation.stripFallbackHeader(body), body);
    });

    test('a header for a different author is untouched', () {
      const body = 'Forwarded from Other (@other:example.org)\n\nthe message';

      expect(presentation.stripFallbackHeader(body), body);
    });

    test('a body that merely contains the header keeps it', () {
      const body = 'look: Forwarded from $_label ($_id)';

      expect(presentation.stripFallbackHeader(body), body);
    });
  });

  group('formatted bodies', () {
    test('the header element and its line breaks are removed', () {
      expect(
        presentation.stripFallbackHeaderHtml(
          '<strong>Forwarded from $_label ($_id)</strong><br><br>'
          '<em>the message</em>',
        ),
        '<em>the message</em>',
      );
    });

    test('self-closing and spaced break tags are handled', () {
      expect(
        presentation.stripFallbackHeaderHtml(
          '<strong>Forwarded from $_label ($_id)</strong><br /><br/>text',
        ),
        'text',
      );
    });

    test('markup that does not start with the header is untouched', () {
      const html = '<p>Forwarded from someone</p>';

      expect(presentation.stripFallbackHeaderHtml(html), html);
    });
  });

  group('the render branches share one rule', () {
    // buildFormattedContent has three render branches - formatted, plain, and
    // the plain one that runs before the room is loaded - and each used to be
    // free to strip or not. They now all call this, so the choice between the
    // HTML rule and the plain rule is the only thing that can be wrong, and it
    // is the thing under test.
    //
    // HONEST GAP: what each branch PASSES to it is still unguarded. Driving
    // buildFormattedContent needs a real MatrixClient, which no test in this
    // repository builds. Deleting one of the three call sites would leave this
    // file green.
    test('a message that is not a forward is returned unchanged', () {
      expect(
        MatrixTimelineEventMessage.visibleForwardedBody(
          null,
          'Forwarded from $_label ($_id)\n\nnot actually a forward',
          html: false,
        ),
        'Forwarded from $_label ($_id)\n\nnot actually a forward',
        reason: 'without the envelope the header is just text the author wrote',
      );
    });

    test('the plain rule is used for plain bodies', () {
      expect(
        MatrixTimelineEventMessage.visibleForwardedBody(
          presentation,
          'Forwarded from $_label ($_id)\n\nthe message',
          html: false,
        ),
        'the message',
      );
    });

    test('the HTML rule is used for formatted bodies', () {
      expect(
        MatrixTimelineEventMessage.visibleForwardedBody(
          presentation,
          '<strong>Forwarded from $_label ($_id)</strong><br><br>the message',
          html: true,
        ),
        'the message',
      );
    });

    test('the plain rule does not strip a formatted header', () {
      // The two rules are not interchangeable: the wrong one leaves the whole
      // header on screen wrapped in its markup.
      const html =
          '<strong>Forwarded from $_label ($_id)</strong><br><br>the message';

      expect(
        MatrixTimelineEventMessage.visibleForwardedBody(
          presentation,
          html,
          html: false,
        ),
        html,
      );
    });
  });

  group('escaping', () {
    // A display name is user-controlled. If the writer escapes it and the
    // stripper does not, the two strings stop matching for exactly the users
    // whose names need escaping most.
    const awkward = MatrixForwardedPresentation(
      originalAuthorId: '@a&b:example.org',
      originalAuthorLabel: '<script> & "friends"',
    );

    test('an escaped display name still round-trips', () {
      final payload = ForwardedMessagePayload(
        originalAuthorId: '@a&b:example.org',
        originalAuthorDisplayName: '<script> & "friends"',
        body: 'hello',
        formattedBody: 'hello',
      );

      expect(awkward.stripFallbackHeader(payload.fallbackBody), 'hello');
      expect(
        awkward.stripFallbackHeaderHtml(payload.fallbackFormattedBody),
        'hello',
      );
    });
  });
}
