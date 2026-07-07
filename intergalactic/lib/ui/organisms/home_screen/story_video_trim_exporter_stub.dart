import 'dart:async';

class StoryVideoTrimExportResult {
  const StoryVideoTrimExportResult._({
    required this.status,
    this.path,
    this.name,
    this.sizeBytes,
    this.message,
  });

  factory StoryVideoTrimExportResult.success({
    required String path,
    required String name,
    required int sizeBytes,
  }) =>
      StoryVideoTrimExportResult._(
        status: StoryVideoTrimExportStatus.success,
        path: path,
        name: name,
        sizeBytes: sizeBytes,
      );

  factory StoryVideoTrimExportResult.unsupported([String? message]) =>
      StoryVideoTrimExportResult._(
        status: StoryVideoTrimExportStatus.unsupported,
        message: message,
      );

  factory StoryVideoTrimExportResult.failed([String? message]) =>
      StoryVideoTrimExportResult._(
        status: StoryVideoTrimExportStatus.failed,
        message: message,
      );

  final StoryVideoTrimExportStatus status;
  final String? path;
  final String? name;
  final int? sizeBytes;
  final String? message;

  bool get isSuccess => status == StoryVideoTrimExportStatus.success;
}

enum StoryVideoTrimExportStatus {
  success,
  unsupported,
  failed,
}

class StoryVideoTrimExporter {
  const StoryVideoTrimExporter();

  Future<StoryVideoTrimExportResult> exportTrim({
    required String sourcePath,
    required Duration trimStart,
    required Duration trimEnd,
    required String sourceName,
  }) async {
    return StoryVideoTrimExportResult.unsupported(
      'Story video trim export is not available on this platform.',
    );
  }
}

class StoryVideoFfmpegTools {
  const StoryVideoFfmpegTools();

  Future<StoryVideoFfmpegToolchain?> findToolchain() async => null;
}

class StoryVideoFfmpegToolchain {
  const StoryVideoFfmpegToolchain({
    required this.ffmpegPath,
    required this.ffprobePath,
  });

  final String ffmpegPath;
  final String ffprobePath;
}

List<String> storyVideoTrimExportArguments({
  required String sourcePath,
  required Duration trimStart,
  required Duration selectedDuration,
  required String outputPath,
}) {
  return const [];
}

Map<String, Object?> storyVideoMobileTrimExportArguments({
  required String sourcePath,
  required String sourceName,
  required Duration trimStart,
  required Duration trimEnd,
}) {
  return <String, Object?>{
    'sourcePath': sourcePath,
    'sourceName': sourceName,
    'trimStartMs': trimStart.inMilliseconds,
    'trimEndMs': trimEnd.inMilliseconds,
  };
}
