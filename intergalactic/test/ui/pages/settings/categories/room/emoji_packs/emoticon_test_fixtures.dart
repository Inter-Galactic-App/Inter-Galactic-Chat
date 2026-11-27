import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:intergalactic/client/components/emoticon/emoticon_draft_store_models.dart';
import 'package:intergalactic/client/components/emoticon/image_cutout_service.dart';
import 'package:intergalactic/utils/picker_utils.dart';

/// Shared fakes for the emoticon-creator redesign tests.

Uint8List redSquareOnWhitePng() {
  final image = img.Image(width: 64, height: 64, numChannels: 4)
    ..clear(img.ColorRgba8(255, 255, 255, 255));

  for (var y = 20; y < 44; y++) {
    for (var x = 20; x < 44; x++) {
      image.setPixelRgba(x, y, 230, 30, 20, 255);
    }
  }

  return Uint8List.fromList(img.encodePng(image));
}

CutoutMask centerSubjectMask() {
  final alpha = Uint8List(64 * 64);
  for (var y = 20; y < 44; y++) {
    for (var x = 20; x < 44; x++) {
      alpha[y * 64 + x] = 255;
    }
  }
  return CutoutMask(width: 64, height: 64, alpha: alpha);
}

CutoutResult syntheticCutoutResult(Uint8List bytes) {
  return CutoutResult(
    pngBytes: bytes,
    thumbnailBytes: bytes,
    mask: centerSubjectMask(),
    backend: ImageCutoutBackendType.localEdgeSegmentation,
    subjectBounds: const CutoutIntRect(
      left: 20,
      top: 20,
      right: 43,
      bottom: 43,
    ),
    cropBounds: const CutoutIntRect(left: 0, top: 0, right: 63, bottom: 63),
    sourceWidth: 64,
    sourceHeight: 64,
    width: 64,
    height: 64,
    processingDuration: Duration.zero,
  );
}

class RecordingCutoutBackend implements ImageCutoutBackend {
  RecordingCutoutBackend(this.result);

  final CutoutResult result;
  final renderMasks = <CutoutMask>[];
  int generateCount = 0;

  @override
  ImageCutoutBackendType get type =>
      ImageCutoutBackendType.localEdgeSegmentation;

  @override
  Future<CutoutResult> generate({
    required Uint8List imageBytes,
    required CutoutSettings settings,
  }) async {
    generateCount++;
    return result;
  }

  @override
  Future<CutoutResult> render({
    required Uint8List imageBytes,
    required CutoutMask mask,
    required CutoutSettings settings,
  }) async {
    renderMasks.add(mask);
    return result.copyWith(mask: mask);
  }
}

class FakeDraftStore implements EmoticonDraftStore {
  FakeDraftStore([List<EmoticonDraft>? drafts]) : drafts = drafts ?? [];

  final List<EmoticonDraft> drafts;
  final deletedIds = <String>[];
  final savedShortcodes = <String>[];

  @override
  Future<List<EmoticonDraft>> listDrafts() async => List.of(drafts);

  @override
  Future<Uint8List?> readDraftPng(String id) async => redSquareOnWhitePng();

  @override
  Future<Uint8List?> readDraftThumbnail(String id) async =>
      redSquareOnWhitePng();

  @override
  Future<EmoticonDraftData?> loadDraft(String id) async {
    for (final draft in drafts) {
      if (draft.id == id) {
        return EmoticonDraftData(
          draft: draft,
          pngBytes: redSquareOnWhitePng(),
          thumbnailBytes: redSquareOnWhitePng(),
        );
      }
    }
    return null;
  }

  @override
  Future<void> deleteDraft(String id) async {
    deletedIds.add(id);
    drafts.removeWhere((draft) => draft.id == id);
  }

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
    savedShortcodes.add(shortcode);
    final draft = EmoticonDraft(
      id: 'saved-${savedShortcodes.length}',
      shortcode: shortcode,
      outputPngPath: 'saved.png',
      thumbnailPath: 'saved-thumb.png',
      backend: backend,
      createdAt: DateTime.utc(2026, 7, 12),
      width: width,
      height: height,
      fileSize: pngBytes.length,
    );
    drafts.add(draft);
    return draft;
  }
}

class FakePickerResult implements PickerResult {
  const FakePickerResult(this.bytes, {required this.name});

  final Uint8List bytes;

  @override
  final String name;

  @override
  String? get mimeType => 'image/png';

  @override
  Future<Uint8List> readAsBytes() async => bytes;
}

EmoticonDraft sampleDraft({String id = 'draft-1', String shortcode = 'party'}) {
  return EmoticonDraft(
    id: id,
    shortcode: shortcode,
    outputPngPath: '$id.png',
    thumbnailPath: '$id-thumb.png',
    backend: ImageCutoutBackendType.localEdgeSegmentation,
    createdAt: DateTime.utc(2026, 7, 5, 12),
    width: 64,
    height: 64,
    fileSize: 128,
  );
}
