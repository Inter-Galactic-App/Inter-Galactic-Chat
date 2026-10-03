import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/cache/file_provider.dart';
import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/matrix/components/message_forwarding/matrix_message_forwarder.dart';

/// Reports the bytes it was built with, and counts how often it was asked.
class _FakeFileProvider implements FileProvider {
  _FakeFileProvider(this._data);

  final Uint8List? _data;
  int reads = 0;

  @override
  String get fileIdentifier => 'forward-size-cap-fixture';

  @override
  Future<Uint8List?> getFileData() async {
    reads++;
    return _data;
  }

  @override
  Stream<DownloadProgress>? get onProgressChanged => null;

  @override
  Future<Uri?> resolve() async => null;

  @override
  Future<void> save(String filepath) async {}
}

/// Refuses to hand over any bytes. Used where the point is that the download
/// never starts: a provider returning oversized bytes cannot tell a guard that
/// skipped the load apart from one that loaded and then rejected.
class _NeverReadFileProvider implements FileProvider {
  @override
  String get fileIdentifier => 'forward-size-cap-never-read';

  @override
  Future<Uint8List?> getFileData() async =>
      fail('the attachment was downloaded despite declaring an oversize');

  @override
  Stream<DownloadProgress>? get onProgressChanged => null;

  @override
  Future<Uri?> resolve() async => null;

  @override
  Future<void> save(String filepath) async {}
}

const _cap = MatrixMessageForwarder.maxForwardAttachmentBytes;

/// A forward re-uploads the file, so the whole attachment is held here and
/// again per destination. Nothing bounded that: forwarding a multi-gigabyte
/// file was an allocation the size of the file.
///
/// The cases below are written against
/// [MatrixMessageForwarder.maxForwardAttachmentBytes] rather than against the
/// number typed out a second time, so what they hold is the guard itself. A
/// test that only compared the constant to 100 MiB would pass with every
/// check deleted, so the one case here that does that says so.
void main() {
  FileAttachment attachmentOf(FileProvider file, {int? fileSize}) =>
      FileAttachment(
        file,
        name: 'payload.bin',
        mimeType: 'application/octet-stream',
        fileSize: fileSize,
      );

  group('the forward attachment bound', () {
    test(
      'an attachment declaring more than the cap is never downloaded',
      () async {
        // The declared size is the only check that can run before the bytes
        // exist, so this is the one that actually stops the allocation.
        final attachment = attachmentOf(
          _NeverReadFileProvider(),
          fileSize: _cap + 1,
        );

        final loaded = await MatrixMessageForwarder.forwardableAttachmentBytes(
          attachment,
        );

        expect(loaded.bytes, isNull);
        expect(loaded.refusal, MatrixForwardRefusal.attachmentTooLarge);
      },
    );

    test(
      'an attachment declaring exactly the cap is still forwarded',
      () async {
        // The boundary, so a guard flipped to `>=` is caught rather than
        // quietly refusing files that were always allowed.
        final file = _FakeFileProvider(Uint8List.fromList([1, 2, 3]));

        final loaded = await MatrixMessageForwarder.forwardableAttachmentBytes(
          attachmentOf(file, fileSize: _cap),
        );

        expect(loaded.bytes, isNotNull);
        expect(loaded.refusal, isNull);
        expect(file.reads, 1);
      },
    );

    test('bytes over the cap are refused even with no declared size', () async {
      // info.size is absent on some events and free to lie on any, so the
      // declared-size check cannot be the only one. This is the case that
      // keeps an oversized file out of the per-destination upload loop.
      final file = _FakeFileProvider(Uint8List(_cap + 1));

      final loaded = await MatrixMessageForwarder.forwardableAttachmentBytes(
        attachmentOf(file),
      );

      expect(loaded.bytes, isNull);
      expect(loaded.refusal, MatrixForwardRefusal.attachmentTooLarge);
      expect(
        file.reads,
        1,
        reason: 'the refusal must come from the loaded length, not a re-read',
      );
    });

    test('an attachment under the cap is returned as loaded', () async {
      final file = _FakeFileProvider(Uint8List.fromList([9, 8, 7]));

      final loaded = await MatrixMessageForwarder.forwardableAttachmentBytes(
        attachmentOf(file),
      );

      expect(loaded.bytes, [9, 8, 7]);
      expect(loaded.refusal, isNull);
    });

    // The cases above hold the MECHANISM: they are written against the
    // constant, so they stay green if it is raised to a gigabyte. This one
    // pins the owner's chosen number, and only that - it is worth nothing on
    // its own and is not a substitute for any of them.
    test('the bound is the 100 MiB the owner chose', () {
      expect(_cap, 100 * 1024 * 1024);
    });

    test('an empty attachment is still refused', () async {
      // Pre-existing behaviour the bound must not swallow: an attachment that
      // resolves to nothing is not a forwardable one, and nothing about it is
      // a size problem - so it keeps reporting the unavailable refusal.
      final file = _FakeFileProvider(Uint8List(0));

      final loaded = await MatrixMessageForwarder.forwardableAttachmentBytes(
        attachmentOf(file),
      );

      expect(loaded.bytes, isNull);
      expect(loaded.refusal, MatrixForwardRefusal.unavailable);
    });
  });

  group('the forward refusal reason', () {
    // The bound alone was already enforced above. What these hold is that the
    // refusal it produces is DISTINGUISHABLE, which is the whole reason the
    // reason exists: an oversize file told the member the message was no
    // longer available, and it sent them away from one they could still act
    // on by sending the file another way.
    test(
      'an oversize attachment does not report as an unavailable one',
      () async {
        final declared =
            await MatrixMessageForwarder.forwardableAttachmentBytes(
              attachmentOf(_NeverReadFileProvider(), fileSize: _cap + 1),
            );
        final measured =
            await MatrixMessageForwarder.forwardableAttachmentBytes(
              attachmentOf(_FakeFileProvider(Uint8List(_cap + 1))),
            );
        final unavailable =
            await MatrixMessageForwarder.forwardableAttachmentBytes(
              attachmentOf(_FakeFileProvider(Uint8List(0))),
            );

        // All three are refusals; the point is that they are not the SAME
        // refusal. Asserted as an inequality as well as by value, so that
        // collapsing the enum to one member cannot pass either.
        expect(declared.bytes, isNull);
        expect(measured.bytes, isNull);
        expect(unavailable.bytes, isNull);
        expect(declared.refusal, isNot(unavailable.refusal));
        expect(measured.refusal, isNot(unavailable.refusal));
        expect(declared.refusal, MatrixForwardRefusal.attachmentTooLarge);
        expect(measured.refusal, MatrixForwardRefusal.attachmentTooLarge);
        expect(unavailable.refusal, MatrixForwardRefusal.unavailable);
      },
    );

    test('the outcome carries a message or a refusal, never both', () {
      // prepare() no longer returns a bare null, so this pins the invariant
      // the caller reads: a null message is what makes it check the refusal.
      const refused = MatrixForwardPrepareOutcome.refused(
        MatrixForwardRefusal.attachmentTooLarge,
      );

      expect(refused.message, isNull);
      expect(refused.refusal, MatrixForwardRefusal.attachmentTooLarge);
    });
  });
}
