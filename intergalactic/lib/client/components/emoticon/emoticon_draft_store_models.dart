import 'dart:typed_data';

import 'package:intergalactic/client/components/emoticon/image_cutout_service.dart';

class EmoticonDraft {
  const EmoticonDraft({
    required this.id,
    required this.shortcode,
    required this.outputPngPath,
    required this.thumbnailPath,
    required this.backend,
    required this.createdAt,
    required this.width,
    required this.height,
    required this.fileSize,
    this.sourceImageHash,
    this.packId,
    this.mxcUri,
  });

  final String id;
  final String shortcode;
  final String outputPngPath;
  final String thumbnailPath;
  final ImageCutoutBackendType backend;
  final DateTime createdAt;
  final int width;
  final int height;
  final int fileSize;
  final String? sourceImageHash;
  final String? packId;
  final String? mxcUri;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'shortcode': shortcode,
      'output_png_path': outputPngPath,
      'thumbnail_path': thumbnailPath,
      'backend': backend.name,
      'created_at': createdAt.toUtc().toIso8601String(),
      'width': width,
      'height': height,
      'file_size': fileSize,
      if (sourceImageHash != null) 'source_image_hash': sourceImageHash,
      if (packId != null) 'pack_id': packId,
      if (mxcUri != null) 'mxc_uri': mxcUri,
    };
  }

  factory EmoticonDraft.fromJson(Map<String, Object?> json) {
    return EmoticonDraft(
      id: json['id']?.toString() ?? '',
      shortcode: json['shortcode']?.toString() ?? '',
      outputPngPath: json['output_png_path']?.toString() ?? '',
      thumbnailPath: json['thumbnail_path']?.toString() ?? '',
      backend: ImageCutoutBackendType.values.firstWhere(
        (value) => value.name == json['backend'],
        orElse: () => ImageCutoutBackendType.unsupported,
      ),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      fileSize: (json['file_size'] as num?)?.toInt() ?? 0,
      sourceImageHash: json['source_image_hash']?.toString(),
      packId: json['pack_id']?.toString(),
      mxcUri: json['mxc_uri']?.toString(),
    );
  }
}

class EmoticonDraftData {
  const EmoticonDraftData({
    required this.draft,
    required this.pngBytes,
    required this.thumbnailBytes,
  });

  final EmoticonDraft draft;
  final Uint8List pngBytes;
  final Uint8List thumbnailBytes;
}

abstract class EmoticonDraftStore {
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
  });

  Future<List<EmoticonDraft>> listDrafts();

  Future<EmoticonDraftData?> loadDraft(String id);

  Future<Uint8List?> readDraftPng(String id);

  Future<Uint8List?> readDraftThumbnail(String id);

  Future<void> deleteDraft(String id);
}
