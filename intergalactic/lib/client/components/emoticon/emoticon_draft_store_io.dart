import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:intergalactic/client/components/emoticon/emoticon_draft_store_models.dart';
import 'package:intergalactic/client/components/emoticon/image_cutout_service.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

EmoticonDraftStore createEmoticonDraftStore({Directory? rootDirectory}) {
  return _IoEmoticonDraftStore(rootDirectory: rootDirectory);
}

class _IoEmoticonDraftStore implements EmoticonDraftStore {
  _IoEmoticonDraftStore({Directory? rootDirectory})
    : _rootDirectoryOverride = rootDirectory;

  static const _uuid = Uuid();

  final Directory? _rootDirectoryOverride;

  @override
  Future<EmoticonDraft> saveDraft({
    required String shortcode,
    required Uint8List pngBytes,
    required Uint8List thumbnailBytes,
    required ImageCutoutBackendType backend,
    required int width,
    required int height,
    String? sourceImageHash,
    String? packId,
    Uri? mxcUri,
  }) async {
    final root = await _rootDirectory();
    await root.create(recursive: true);
    final id = _uuid.v4();
    final safeShortcode = _safeName(shortcode);
    final outputFile = File(path.join(root.path, '$id-$safeShortcode.png'));
    final thumbnailFile = File(
      path.join(root.path, '$id-$safeShortcode-thumb.png'),
    );
    final metadataFile = File(path.join(root.path, '$id.json'));

    await outputFile.writeAsBytes(pngBytes, flush: true);
    await thumbnailFile.writeAsBytes(thumbnailBytes, flush: true);

    final draft = EmoticonDraft(
      id: id,
      shortcode: shortcode,
      outputPngPath: outputFile.path,
      thumbnailPath: thumbnailFile.path,
      backend: backend,
      createdAt: DateTime.now().toUtc(),
      width: width,
      height: height,
      fileSize: pngBytes.length,
      sourceImageHash: sourceImageHash,
      packId: packId,
      mxcUri: mxcUri?.toString(),
    );

    await metadataFile.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(draft.toJson())}\n',
      flush: true,
    );

    return draft;
  }

  @override
  Future<List<EmoticonDraft>> listDrafts() async {
    final root = await _rootDirectory();
    if (!await root.exists()) {
      return const [];
    }

    final drafts = <EmoticonDraft>[];
    await for (final entity in root.list()) {
      if (entity is! File || path.extension(entity.path) != '.json') {
        continue;
      }
      try {
        final json = jsonDecode(await entity.readAsString());
        if (json is Map<String, Object?>) {
          drafts.add(EmoticonDraft.fromJson(json));
        } else if (json is Map) {
          drafts.add(EmoticonDraft.fromJson(Map<String, Object?>.from(json)));
        }
      } catch (_) {
        // Ignore corrupt draft records; the editor should remain usable.
      }
    }

    drafts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return drafts;
  }

  @override
  Future<EmoticonDraftData?> loadDraft(String id) async {
    final draft = await _findDraft(id);
    if (draft == null) {
      return null;
    }

    final pngBytes = await _readDraftFile(draft.outputPngPath);
    final thumbnailBytes = await _readDraftFile(draft.thumbnailPath);
    if (pngBytes == null || thumbnailBytes == null) {
      return null;
    }

    return EmoticonDraftData(
      draft: draft,
      pngBytes: pngBytes,
      thumbnailBytes: thumbnailBytes,
    );
  }

  @override
  Future<Uint8List?> readDraftPng(String id) async {
    final draft = await _findDraft(id);
    if (draft == null) {
      return null;
    }
    return _readDraftFile(draft.outputPngPath);
  }

  @override
  Future<Uint8List?> readDraftThumbnail(String id) async {
    final draft = await _findDraft(id);
    if (draft == null) {
      return null;
    }
    return _readDraftFile(draft.thumbnailPath);
  }

  @override
  Future<void> deleteDraft(String id) async {
    if (!_isSafeId(id)) {
      return;
    }

    final root = await _rootDirectory();
    if (!await root.exists()) {
      return;
    }

    await for (final entity in root.list()) {
      final basename = path.basename(entity.path);
      if (entity is File &&
          (basename == '$id.json' || basename.startsWith('$id-'))) {
        await entity.delete();
      }
    }
  }

  Future<EmoticonDraft?> _findDraft(String id) async {
    if (!_isSafeId(id)) {
      return null;
    }

    for (final draft in await listDrafts()) {
      if (draft.id == id) {
        return draft;
      }
    }
    return null;
  }

  Future<Uint8List?> _readDraftFile(String filePath) async {
    final root = await _rootDirectory();
    final resolvedRoot = path.normalize(path.absolute(root.path));
    final resolvedFile = path.normalize(path.absolute(filePath));
    if (resolvedRoot != resolvedFile &&
        !path.isWithin(resolvedRoot, resolvedFile)) {
      return null;
    }

    final file = File(resolvedFile);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  Future<Directory> _rootDirectory() async {
    final override = _rootDirectoryOverride;
    if (override != null) {
      return override;
    }

    final support = await getApplicationSupportDirectory();
    return Directory(path.join(support.path, 'emoticon_drafts'));
  }

  static String _safeName(String shortcode) {
    final cleaned = shortcode
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return cleaned.isEmpty ? 'emoticon' : cleaned;
  }

  static bool _isSafeId(String id) {
    return RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id);
  }
}
