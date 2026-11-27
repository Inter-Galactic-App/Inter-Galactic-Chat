import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/utils/local_file.dart';

void main() {
  test(
    'bounded local-file reads reject files at the configured limit',
    () async {
      final directory = await Directory.systemTemp.createTemp('bounded-file-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}${Platform.pathSeparator}photo.bin');
      final data = Uint8List.fromList([1, 2, 3, 4]);
      await file.writeAsBytes(data);

      expect(
        await readLocalFileBytesWithinLimit(file.path, maxBytes: data.length),
        isNull,
      );
      expect(
        await readLocalFileBytesWithinLimit(
          file.path,
          maxBytes: data.length + 1,
        ),
        orderedEquals(data),
      );
    },
  );

  test('local-file header reads stay within the requested prefix', () async {
    final directory = await Directory.systemTemp.createTemp('file-header-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}photo.bin');
    await file.writeAsBytes([1, 2, 3, 4]);

    expect(await readLocalFileHeader(file.path, maxBytes: 3), [1, 2, 3]);
  });
}
