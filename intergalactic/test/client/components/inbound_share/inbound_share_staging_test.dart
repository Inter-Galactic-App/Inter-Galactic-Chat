import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_staging.dart';

void main() {
  test(
    'staging uses opaque files and sanitizes unsafe display names',
    () async {
      final root = await Directory.systemTemp.createTemp('ig_inbound_staging_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      final staging = InboundShareStaging(root);
      final manifest = await staging.createSession();
      final file = await staging.stageBytes(
        manifest,
        Uint8List.fromList([1, 2]),
        name: '../a\u202E.jpg',
      );
      expect(file.displayName, isNot(contains('..')));
      expect(file.stagingPath, isNot(contains(file.displayName)));
      expect(await File(file.stagingPath).exists(), isTrue);
      await staging.release(manifest);
      await staging.release(manifest);
      expect(await Directory(manifest.sessionRoot).exists(), isFalse);
    },
  );

  test('claims and releases an existing opaque native session', () async {
    final root = await Directory.systemTemp.createTemp('ig_inbound_staging_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    const token = '123e4567-e89b-12d3-a456-426614174000';
    final nativeSession = Directory(
      '${root.path}${Platform.pathSeparator}$token',
    );
    await nativeSession.create();
    final staging = InboundShareStaging(root);

    final manifest = await staging.claimExistingSession(token);

    expect(manifest.token, token);
    expect(manifest.sessionRoot, nativeSession.path);
    await staging.release(manifest);
    expect(await nativeSession.exists(), isFalse);
  });
}
