import 'dart:typed_data';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_controller.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_payload.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_staging.dart';

void main() {
  late Directory temp;
  late InboundShareStaging staging;
  late InboundShareController controller;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ig_inbound_share_');
    staging = InboundShareStaging(temp);
    controller = InboundShareController(staging);
  });
  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test(
    'text-only and URL-only shares are reviewable without an attachment',
    () async {
      final text = await _session(staging);
      final result = await controller.accept(
        text.$1,
        const InboundSharePayload(
          items: [InboundShareItem.text('hello')],
          body: 'hello',
        ),
      );
      expect(result.admission, InboundShareAdmission.active);
      expect(result.session!.payload.pendingAttachments, isEmpty);
      await controller.finishActive(InboundShareSessionState.cancelled);
      final url = await _session(staging);
      expect(
        (await controller.accept(
          url.$1,
          InboundSharePayload(
            items: [InboundShareItem.url(Uri.parse('https://example.test'))],
          ),
        )).admission,
        InboundShareAdmission.active,
      );
    },
  );

  test(
    'ordered attachments retain a text body and map to pending attachments',
    () async {
      final entry = await _session(staging);
      final first = await staging.stageBytes(
        entry.$1,
        Uint8List.fromList([1]),
        name: 'first.jpg',
        mimeType: 'image/jpeg',
      );
      final second = await staging.stageBytes(
        entry.$1,
        Uint8List.fromList([2]),
        name: 'second.jpg',
        mimeType: 'image/jpeg',
      );
      final result = await controller.accept(
        entry.$1,
        InboundSharePayload(
          body: 'caption',
          items: [
            const InboundShareItem.text('caption'),
            InboundShareItem.file(first),
            InboundShareItem.file(second),
          ],
        ),
      );
      expect(
        result.session!.payload.pendingAttachments.map((item) => item.name),
        ['first.jpg', 'second.jpg'],
      );
    },
  );

  test(
    'a failed file stays out of attachments without discarding usable text',
    () async {
      final entry = await _session(staging);
      final failed = await staging.stageBytes(
        entry.$1,
        Uint8List(0),
        name: 'unavailable.jpg',
        failure: 'Provider read failed.',
      );
      final result = await controller.accept(
        entry.$1,
        InboundSharePayload(
          body: 'keep this',
          items: [
            const InboundShareItem.text('keep this'),
            InboundShareItem.file(failed),
          ],
        ),
      );
      expect(result.admission, InboundShareAdmission.active);
      expect(result.session!.payload.pendingAttachments, isEmpty);
    },
  );
  test('empty and over-budget payloads are rejected and released', () async {
    final empty = await _session(staging);
    expect(
      (await controller.accept(
        empty.$1,
        const InboundSharePayload(items: []),
      )).admission,
      InboundShareAdmission.rejected,
    );
    expect(await Directory(empty.$1.sessionRoot).exists(), isFalse);
    final large = await _session(staging);
    final file = await staging.stageBytes(
      large.$1,
      Uint8List.fromList([1]),
      name: 'large.bin',
    );
    final restrictive = InboundShareController(staging, maxItemBytes: 0);
    expect(
      (await restrictive.accept(
        large.$1,
        InboundSharePayload(items: [InboundShareItem.file(file)]),
      )).admission,
      InboundShareAdmission.rejected,
    );
    expect(await Directory(large.$1.sessionRoot).exists(), isFalse);
  });

  test(
    'second share queues and terminal cleanup promotes it exactly once',
    () async {
      final first = await _session(staging);
      final second = await _session(staging);
      final third = await _session(staging);
      await controller.accept(
        first.$1,
        const InboundSharePayload(items: [InboundShareItem.text('first')]),
      );
      expect(
        (await controller.accept(
          second.$1,
          const InboundSharePayload(items: [InboundShareItem.text('second')]),
        )).admission,
        InboundShareAdmission.queued,
      );
      expect(
        (await controller.accept(
          third.$1,
          const InboundSharePayload(items: [InboundShareItem.text('third')]),
        )).admission,
        InboundShareAdmission.rejected,
      );
      // The queue-full branch must release the staged session too, not just
      // report the rejection.
      expect(await Directory(third.$1.sessionRoot).exists(), isFalse);
      await controller.finishActive(InboundShareSessionState.completed);
      expect(controller.active!.payload.items.single.text, 'second');
      await controller.finishActive(InboundShareSessionState.failed);
      expect(await Directory(first.$1.sessionRoot).exists(), isFalse);
      expect(await Directory(second.$1.sessionRoot).exists(), isFalse);
    },
  );
}

Future<(dynamic, InboundShareStaging)> _session(
  InboundShareStaging staging,
) async => (await staging.createSession(), staging);
