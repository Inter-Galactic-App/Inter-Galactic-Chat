import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix_background/matrix_background_client.dart';

void main() {
  group('hasUsableMatrixBackgroundAccount', () {
    test('rejects an absent or incomplete persisted account', () {
      expect(hasUsableMatrixBackgroundAccount(null), isFalse);
      expect(
        hasUsableMatrixBackgroundAccount(const {
          'homeserver_url': 'https://matrix.example.org',
        }),
        isFalse,
      );
      expect(
        hasUsableMatrixBackgroundAccount(const {'token': 'access-token'}),
        isFalse,
      );
    });

    // The cases above only need the KEYS to be present, so a check that stops
    // at `containsKey` passes all of them. An empty homeserver or token is
    // just as unusable - `Uri.parse('')` is a valid Uri and the background
    // client would go on to build an api against it - so the emptiness half
    // of the guard needs a case of its own.
    test('rejects an empty homeserver or token', () {
      expect(
        hasUsableMatrixBackgroundAccount(const {
          'homeserver_url': '',
          'token': 'access-token',
        }),
        isFalse,
      );
      expect(
        hasUsableMatrixBackgroundAccount(const {
          'homeserver_url': 'https://matrix.example.org',
          'token': '',
        }),
        isFalse,
      );
    });

    // The half that was left open when the empty-string cases landed, because
    // pinning the old behaviour would have cemented something wrong: this used
    // to test `isNotEmpty`, so '   ' read as a usable credential and the
    // background client built an api against a homeserver of spaces.
    test('rejects whitespace-only credentials', () {
      expect(
        hasUsableMatrixBackgroundAccount(const {
          'homeserver_url': '   ',
          'token': 'access-token',
        }),
        isFalse,
      );
      expect(
        hasUsableMatrixBackgroundAccount(const {
          'homeserver_url': 'https://matrix.example.org',
          'token': '  \t ',
        }),
        isFalse,
      );
    });

    test('rejects credentials of the wrong type', () {
      // The guard is `is String`, not a null check: a persisted document that
      // stored a number or a nested map must not be read as credentials.
      expect(
        hasUsableMatrixBackgroundAccount(const {
          'homeserver_url': 42,
          'token': 'access-token',
        }),
        isFalse,
      );
      // Both halves, because the guard is two independent `is String` checks
      // and `matrix_background_client.dart:126` casts the token with `as
      // String`. Testing only the homeserver leaves `accessToken is String`
      // free to be deleted: every other case here has a String token, so the
      // suite stays green while a persisted number reaches that cast and
      // throws inside a background isolate.
      expect(
        hasUsableMatrixBackgroundAccount(const {
          'homeserver_url': 'https://matrix.example.org',
          'token': 42,
        }),
        isFalse,
      );
      expect(
        hasUsableMatrixBackgroundAccount(const {
          'homeserver_url': 'https://matrix.example.org',
          'token': {'access_token': 'access-token'},
        }),
        isFalse,
      );
    });

    test(
      'accepts the persisted credentials needed by the background client',
      () {
        expect(
          hasUsableMatrixBackgroundAccount(const {
            'homeserver_url': 'https://matrix.example.org',
            'token': 'access-token',
          }),
          isTrue,
        );
      },
    );
  });

  test('missing background rooms are ignored instead of throwing', () {
    final client = MatrixBackgroundClient(databaseId: 'test');

    expect(client.getRoom('!missing:example.org'), isNull);
  });
}
