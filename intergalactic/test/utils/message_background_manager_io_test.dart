import 'dart:io';
import 'dart:typed_data';

import 'package:intergalactic/utils/message_background/message_background_manager_io.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'message_background_manager_io_test_',
    );
  });

  tearDown(() async {
    MessageBackgroundManager.debugBackgroundDirectoryOverride = null;
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('resolves a legacy absolute path after support directory changes',
      () async {
    final oldDirectory = Directory(
      path.join(tempRoot.path, 'old-container', 'message_backgrounds'),
    );
    final newDirectory = Directory(
      path.join(tempRoot.path, 'new-container', 'message_backgrounds'),
    );

    MessageBackgroundManager.debugBackgroundDirectoryOverride =
        () async => oldDirectory;

    final storedPath = await MessageBackgroundManager.importBackground(
      Uint8List.fromList(const [1, 2, 3, 4]),
      storageKey: 'default',
    );
    final fileName = path.basename(storedPath);
    final rehomedFile = File(path.join(newDirectory.path, fileName));
    await newDirectory.create(recursive: true);
    await File(storedPath).copy(rehomedFile.path);
    await File(storedPath).delete();

    MessageBackgroundManager.debugBackgroundDirectoryOverride =
        () async => newDirectory;

    expect(MessageBackgroundManager.imageProvider(storedPath), isNull);

    final resolvedFile =
        await MessageBackgroundManager.resolveBackgroundFile(storedPath);
    expect(resolvedFile?.path, rehomedFile.path);
    expect(
      await MessageBackgroundManager.resolveImageProvider(storedPath),
      isNotNull,
    );
    expect(MessageBackgroundManager.imageProvider(storedPath), isNotNull);
  });

  test('recognizes old and current paths for the same stored background',
      () async {
    final oldDirectory = Directory(
      path.join(tempRoot.path, 'old-container', 'message_backgrounds'),
    );
    final newDirectory = Directory(
      path.join(tempRoot.path, 'new-container', 'message_backgrounds'),
    );

    MessageBackgroundManager.debugBackgroundDirectoryOverride =
        () async => oldDirectory;
    final oldPath = await MessageBackgroundManager.importBackground(
      Uint8List.fromList(const [5, 6, 7, 8]),
      storageKey: 'room:!room:example.org',
    );
    final fileName = path.basename(oldPath);
    final newPath = path.join(newDirectory.path, fileName);
    await newDirectory.create(recursive: true);
    await File(oldPath).copy(newPath);
    await File(oldPath).delete();

    MessageBackgroundManager.debugBackgroundDirectoryOverride =
        () async => newDirectory;

    expect(
      await MessageBackgroundManager.referencesSameBackground(oldPath, newPath),
      isTrue,
    );
    expect(
      await MessageBackgroundManager.referencesSameBackground(
        oldPath,
        path.join(newDirectory.path, 'other.png'),
      ),
      isFalse,
    );
  });

  test('delete removes a rehomed legacy background file', () async {
    final oldDirectory = Directory(
      path.join(tempRoot.path, 'old-container', 'message_backgrounds'),
    );
    final newDirectory = Directory(
      path.join(tempRoot.path, 'new-container', 'message_backgrounds'),
    );

    MessageBackgroundManager.debugBackgroundDirectoryOverride =
        () async => oldDirectory;
    final storedPath = await MessageBackgroundManager.importBackground(
      Uint8List.fromList(const [9, 10, 11, 12]),
      storageKey: 'default',
    );
    final rehomedFile = File(
      path.join(newDirectory.path, path.basename(storedPath)),
    );
    await newDirectory.create(recursive: true);
    await File(storedPath).copy(rehomedFile.path);
    await File(storedPath).delete();

    MessageBackgroundManager.debugBackgroundDirectoryOverride =
        () async => newDirectory;

    await MessageBackgroundManager.deleteBackground(storedPath);

    expect(await rehomedFile.exists(), isFalse);
  });
}
