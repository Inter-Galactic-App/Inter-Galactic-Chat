import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/message_forwarding/forwarded_message_payload.dart';

void main() {
  group('ForwardedMessagePayload', () {
    test('builds a readable non-mention forwarding envelope', () {
      const payload = ForwardedMessagePayload(
        originalAuthorId: '@sam:example.org',
        originalAuthorDisplayName: 'Sam',
        body: 'A message worth sharing',
        formattedBody: '<em>A message worth sharing</em>',
      );

      expect(payload.header, 'Forwarded from Sam (@sam:example.org)');
      expect(
        payload.textContent,
        isNot(containsPair('m.relates_to', anything)),
      );
      expect(payload.textContent, isNot(containsPair('m.mentions', anything)));
      expect(payload.presentationEnvelope, {
        'v': 1,
        'original_sender': '@sam:example.org',
        'original_sender_label': 'Sam',
      });
      expect(
        payload.textContent['body'],
        'Forwarded from Sam (@sam:example.org)\n\nA message worth sharing',
      );
    });

    test('allow-lists visible content and strips source Matrix metadata', () {
      final payload = ForwardedMessagePayload.fromVisibleContent(
        originalAuthorId: '@sam:example.org',
        originalAuthorDisplayName: 'Sam',
        visibleContent: {
          'body': 'Visible message',
          'format': 'org.matrix.custom.html',
          'formatted_body': '<strong>Visible message</strong>',
          'm.relates_to': {
            'event_id': r'$source-event',
            'room_id': '!source:example.org',
          },
          'm.mentions': {
            'user_ids': ['@sam:example.org'],
          },
          'event_id': r'$source-event',
          'room_id': '!source:example.org',
          'file': {'url': 'mxc://example.org/source'},
          'ciphertext': 'not portable',
        },
      );

      expect(payload.body, 'Visible message');
      expect(payload.formattedBody, 'Visible message');
      expect(
        payload.textContent,
        isNot(containsPair('m.relates_to', anything)),
      );
      expect(payload.textContent, isNot(containsPair('m.mentions', anything)));
      expect(payload.textContent.values, isNot(contains(r'$source-event')));
      expect(
        payload.textContent.values,
        isNot(contains('!source:example.org')),
      );
    });

    // The case above asserts what textContent does NOT contain, and it cannot
    // fail: textContent is a fixed literal built from scratch, so those keys
    // were never candidates. _sanitizeVisibleContent could be mutated to spread
    // the WHOLE source content - relations, mentions, ciphertext - and it would
    // still pass, because nothing reads a key off the sanitized result: only
    // content['body'] is used.
    //
    // The property actually holding the line is that the SENT content is
    // exactly this key set. Pin that instead, so the day someone spreads the
    // sanitized map into textContent - making the allow-list the only defence -
    // its removal is caught here.
    test('the sent content is exactly the fixed key set', () {
      final payload = ForwardedMessagePayload.fromVisibleContent(
        originalAuthorId: '@sam:example.org',
        originalAuthorDisplayName: 'Sam',
        visibleContent: {
          'body': 'Visible message',
          'formatted_body': '<strong>Visible message</strong>',
          'm.relates_to': {'event_id': r'$source-event'},
          'm.mentions': {
            'user_ids': ['@sam:example.org'],
          },
          'ciphertext': 'not portable',
          'file': {'url': 'mxc://example.org/source'},
          'event_id': r'$source-event',
          'room_id': '!source:example.org',
        },
      );

      expect(payload.textContent.keys, <String>{
        'msgtype',
        'body',
        'format',
        'formatted_body',
        ForwardedMessagePayload.presentationKey,
      });
    });

    // The envelope is the other half of what goes on the wire, and it is the
    // half that names a person. It must carry the author and nothing else.
    test('the presentation envelope carries no source reference', () {
      final payload = ForwardedMessagePayload.fromVisibleContent(
        originalAuthorId: '@sam:example.org',
        originalAuthorDisplayName: 'Sam',
        visibleContent: {
          'body': 'Visible message',
          'm.relates_to': {'event_id': r'$source-event'},
          'room_id': '!source:example.org',
        },
      );

      expect(payload.presentationEnvelope.keys, <String>{
        'v',
        'original_sender',
        'original_sender_label',
      });
    });
  });
}
