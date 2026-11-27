import 'dart:typed_data';

import 'package:intergalactic/client/components/emoticon/emoticon_draft_store_models.dart';
import 'package:intergalactic/client/components/emoticon/image_cutout_service.dart';

EmoticonDraftStore createEmoticonDraftStore() => _UnsupportedDraftStore();

class _UnsupportedDraftStore implements EmoticonDraftStore {
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
    throw const ImageCutoutException(
      ImageCutoutFailureCode.unsupportedPlatform,
      'Local emoticon drafts are not available on this platform yet.',
    );
  }

  @override
  Future<List<EmoticonDraft>> listDrafts() async => const [];

  @override
  Future<EmoticonDraftData?> loadDraft(String id) async => null;

  @override
  Future<Uint8List?> readDraftPng(String id) async => null;

  @override
  Future<Uint8List?> readDraftThumbnail(String id) async => null;

  @override
  Future<void> deleteDraft(String id) async {}
}
