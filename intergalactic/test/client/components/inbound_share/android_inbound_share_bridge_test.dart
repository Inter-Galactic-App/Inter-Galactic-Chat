import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/inbound_share/android_inbound_share_bridge.dart';
import 'package:receive_intent/receive_intent.dart' as receive_intent;

void main() {
  test(
    'classifies text and ordered content streams without accepting file URIs',
    () {
      final parsed = AndroidInboundShareBridge.tryParse(
        _Intent(AndroidInboundShareBridge.actionSendMultiple, {
          AndroidInboundShareBridge.extraText: 'caption',
          AndroidInboundShareBridge.extraStream: [
            'content://provider/one',
            'content://provider/two',
          ],
        }, type: 'image/*'),
      );
      expect(parsed?.text, 'caption');
      expect(parsed?.mimeType, 'image/*');
      expect(parsed?.streams.map((item) => item.path), ['/one', '/two']);
      expect(
        AndroidInboundShareBridge.tryParse(
          _Intent(AndroidInboundShareBridge.actionSend, {
            AndroidInboundShareBridge.extraStream: 'file:///tmp/unsafe',
          }),
        ),
        isNull,
      );
    },
  );

  test('accepts a receive_intent share without a MIME-type property', () {
    final parsed = AndroidInboundShareBridge.tryParse(
      const receive_intent.Intent(
        isNull: false,
        action: AndroidInboundShareBridge.actionSend,
        extra: {AndroidInboundShareBridge.extraText: 'shared note'},
      ),
    );

    expect(parsed?.text, 'shared note');
    expect(parsed?.streams, isEmpty);
    expect(parsed?.mimeType, isNull);
  });

  test(
    'leaves existing non-share intents untouched and rejects empty shares',
    () {
      expect(
        AndroidInboundShareBridge.tryParse(_Intent('SELECT_NOTIFICATION', {})),
        isNull,
      );
      expect(
        AndroidInboundShareBridge.tryParse(
          _Intent(AndroidInboundShareBridge.actionSend, {}),
        ),
        isNull,
      );
    },
  );

  test('rejects a malformed intent instead of throwing out of tryParse', () {
    // Every field here is supplied by whichever app invoked the share sheet, so
    // a wrong type is a malformed share to reject - not an exception that
    // terminates inbound-share handling. These used to be unchecked casts.
    expect(
      AndroidInboundShareBridge.tryParse(
        _Intent(AndroidInboundShareBridge.actionSend, {
          AndroidInboundShareBridge.extraText: 42,
        }),
      ),
      isNull,
    );
    expect(
      AndroidInboundShareBridge.tryParse(
        _LooseIntent(
          AndroidInboundShareBridge.actionSend,
          {
            AndroidInboundShareBridge.extraStream: ['content://provider/one'],
          },
          type: const <String>['image/png'],
        ),
      ),
      isNull,
    );
  });
}

/// Mirrors [_Intent] but leaves `type` untyped, so a non-String MIME value is
/// expressible - the platform channel hands `tryParse` a `dynamic`.
class _LooseIntent {
  const _LooseIntent(this.action, this.extra, {this.type});
  final String action;
  final Map<String, Object?> extra;
  final Object? type;
}

class _Intent {
  const _Intent(this.action, this.extra, {this.type});
  final String action;
  final Map<String, Object?> extra;
  final String? type;
}
