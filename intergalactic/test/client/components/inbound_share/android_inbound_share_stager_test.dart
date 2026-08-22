import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/inbound_share/android_inbound_share_bridge.dart';
import 'package:intergalactic/client/components/inbound_share/android_inbound_share_stager.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_payload.dart';

class _FakeStagingPlatform implements AndroidInboundShareStagingPlatform {
  _FakeStagingPlatform(this.entries);
  final List<AndroidInboundShareStageEntry> entries;
  final List<Uri> requestedUris = [];

  @override
  Future<List<AndroidInboundShareStageEntry>> stage(List<Uri> uris) async {
    requestedUris.addAll(uris);
    return entries;
  }

  @override
  Future<AndroidInboundShareGrantSnapshot?> grantSnapshot(
    List<Uri> uris,
  ) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Android share grant diagnostics', () {
    test('answers null when native cannot produce a snapshot', () async {
      // Native returns null when its own probe threw. Parsing that as a
      // snapshot raised a FormatException out of a diagnostic-only call, on
      // the path that then had to stage the share.
      const channel = MethodChannel('chat.intergalactic.app/inbound_share');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      // Recorded, because an UNHANDLED channel also resolves to null in
      // flutter_test: without this the test would keep passing if the channel
      // or method name ever drifted from the native side, while exercising
      // nothing.
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      const staging = MethodChannelAndroidInboundShareStaging();

      expect(
        await staging.grantSnapshot([Uri.parse('content://provider/1')]),
        isNull,
      );
      expect(calls, ['inboundShareGrantSnapshot']);
    });

    test('keeps only safe grant and shape fields from the native snapshot', () {
      final snapshot = AndroidInboundShareGrantSnapshot.fromPlatformMap({
        'action': 'send',
        'intent_read_grant': true,
        'activity_stream_count': 1,
        'clip_item_count': 1,
        'requested_stream_count': 1,
        'requested_stream_hash': '0123456789ab',
        'requested_read_grant_count': 1,
        // Native-only values must never be carried into diagnostic logs.
        'uri': 'content://private.provider/secret',
        'display_name': 'private-file.jpg',
        'authority': 'private.provider',
      });

      expect(
        snapshot.toLogFields(),
        'action=send intent_read_grant=true activity_stream_count=1 '
        'clip_item_count=1 requested_stream_count=1 '
        'requested_stream_hash=0123456789ab requested_read_grant_count=1',
      );
    });
  });

  group('staging failures are classified for the user', () {
    // The real detail string native sends, from the 2026-08-05 device capture
    // where Chrome's FileProvider refused the read grant.
    const chromeRefusal =
        'reason=permission_denied kind=FileNotFoundException '
        'read_grant=false scheme=content authority_hash=2aef04f91854 '
        'uri_hash=00c6fde9c1e7';

    test('a refused read grant is reported as permission denied', () {
      expect(
        androidInboundShareFailureFromDetails(chromeRefusal),
        InboundShareFailure.permissionDenied,
      );
    });

    test('a size refusal is reported as too large', () {
      expect(
        androidInboundShareFailureFromDetails(
          'reason=too_large kind=InboundShareTooLargeException '
          'read_grant=true scheme=content',
        ),
        InboundShareFailure.tooLarge,
      );
    });

    test('permission denied wins when a share failed several ways', () {
      // Most actionable answer first: sharing a link recovers the refused item,
      // and nothing the user can do recovers the oversized one.
      expect(
        androidInboundShareFailureFromDetails(
          'reason=too_large kind=InboundShareTooLargeException | '
          '$chromeRefusal',
        ),
        InboundShareFailure.permissionDenied,
      );
    });

    test('an unrecognised or absent detail falls back to unreadable', () {
      expect(
        androidInboundShareFailureFromDetails(null),
        InboundShareFailure.unreadable,
      );
      expect(
        androidInboundShareFailureFromDetails(42),
        InboundShareFailure.unreadable,
      );
      expect(
        androidInboundShareFailureFromDetails(
          'reason=unreadable kind=IOException',
        ),
        InboundShareFailure.unreadable,
      );
    });

    test('a message-shaped detail is not mistaken for a reason', () {
      // Guards the choice to read `reason=` rather than the prose: the
      // all-failed message never varies, so matching on it would misclassify.
      expect(
        androidInboundShareFailureFromDetails(
          'No shared content could be staged.',
        ),
        InboundShareFailure.unreadable,
      );
    });
  });

  const token = '123e4567-e89b-12d3-a456-426614174000';

  test(
    'preserves text, ordered files, metadata, and a failed staged item',
    () async {
      final payload =
          await AndroidInboundShareStager(
            _FakeStagingPlatform([
              const AndroidInboundShareStageEntry(
                displayName: 'one.jpg',
                path: '/staging/one',
                size: 12,
                sessionToken: token,
                mimeType: 'image/jpeg',
              ),
              const AndroidInboundShareStageEntry(
                displayName: 'two.jpg',
                size: 0,
                sessionToken: token,
                failure: 'The provider revoked access.',
              ),
            ]),
          ).stage(
            AndroidInboundShareIntent(
              text: 'Look at these',
              streams: [
                Uri(scheme: 'content', path: '/one'),
                Uri(scheme: 'content', path: '/two'),
              ],
              mimeType: 'image/*',
            ),
          );

      expect(payload?.body, 'Look at these');
      expect(payload?.stagingToken, token);
      expect(payload?.items.map((item) => item.kind), [
        InboundShareItemKind.text,
        InboundShareItemKind.file,
        InboundShareItemKind.file,
      ]);
      expect(payload?.pendingAttachments.single.name, 'one.jpg');
      expect(payload?.items.last.status, InboundShareItemStatus.failed);
    },
  );

  test(
    'does not create a destination payload when every staged item failed',
    () async {
      final payload =
          await AndroidInboundShareStager(
            _FakeStagingPlatform([
              const AndroidInboundShareStageEntry(
                displayName: 'document',
                size: 0,
                sessionToken: token,
                failure: 'The provider revoked access.',
              ),
            ]),
          ).stage(
            AndroidInboundShareIntent(
              text: null,
              streams: [Uri(scheme: 'content', path: '/document')],
            ),
          );

      expect(payload, isNull);
    },
  );

  test('rejects an incomplete native staging response', () async {
    final platform = _FakeStagingPlatform([
      const AndroidInboundShareStageEntry(
        displayName: 'first',
        path: '/staging/first',
        size: 1,
        sessionToken: token,
      ),
    ]);
    final discarded = <String>[];
    final intent = AndroidInboundShareIntent(
      text: null,
      streams: [
        Uri(scheme: 'content', path: '/first'),
        Uri(scheme: 'content', path: '/second'),
      ],
    );

    final payload = await AndroidInboundShareStager(
      platform,
      onDiscard: (sessionToken) async => discarded.add(sessionToken),
    ).stage(intent);

    expect(payload, isNull);
    expect(platform.requestedUris, intent.streams);
    // Native already created and filled the session, so a rejection here has to
    // release it or the staged bytes stay in the app cache forever.
    expect(discarded, [token]);
  });

  test('rejects a native response from different staging sessions', () async {
    final platform = _FakeStagingPlatform([
      const AndroidInboundShareStageEntry(
        displayName: 'first',
        path: '/staging/first',
        size: 1,
        sessionToken: token,
      ),
      const AndroidInboundShareStageEntry(
        displayName: 'second',
        path: '/staging/second',
        size: 1,
        sessionToken: '123e4567-e89b-12d3-a456-426614174001',
      ),
    ]);
    final discarded = <String>[];
    final intent = AndroidInboundShareIntent(
      text: null,
      streams: [
        Uri(scheme: 'content', path: '/first'),
        Uri(scheme: 'content', path: '/second'),
      ],
    );

    final payload = await AndroidInboundShareStager(
      platform,
      onDiscard: (sessionToken) async => discarded.add(sessionToken),
    ).stage(intent);

    expect(payload, isNull);
    expect(platform.requestedUris, intent.streams);
    expect(discarded, [token]);
  });

  test('releases the staging session when nothing usable was staged', () async {
    final discarded = <String>[];

    final payload =
        await AndroidInboundShareStager(
          _FakeStagingPlatform([
            const AndroidInboundShareStageEntry(
              displayName: 'document',
              size: 0,
              sessionToken: token,
              failure: 'The provider revoked access.',
            ),
          ]),
          onDiscard: (sessionToken) async => discarded.add(sessionToken),
        ).stage(
          AndroidInboundShareIntent(
            text: null,
            streams: [Uri(scheme: 'content', path: '/document')],
          ),
        );

    expect(payload, isNull);
    expect(discarded, [token]);
  });
}
