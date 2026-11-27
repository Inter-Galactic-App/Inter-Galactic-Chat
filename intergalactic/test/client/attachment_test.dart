import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/attachment.dart';

void main() {
  test('file resolution preserves an explicit recorder mime type', () async {
    final temp = await Directory.systemTemp.createTemp('ig_attachment_test_');
    addTearDown(() async {
      if (await temp.exists()) {
        await temp.delete(recursive: true);
      }
    });

    final file = File('${temp.path}${Platform.pathSeparator}voice-message.mp4');
    await file.writeAsBytes(const [0, 0, 0, 0]);

    final attachment = PendingFileAttachment(
      name: 'voice-message.m4a',
      path: file.path,
      mimeType: 'audio/mp4',
    );

    await attachment.resolve();

    expect(attachment.data, isNotNull);
    expect(attachment.mimeType, 'audio/mp4');
  });
}
