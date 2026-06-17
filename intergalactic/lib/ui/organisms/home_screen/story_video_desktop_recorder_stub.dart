class StoryDesktopVideoRecordStartResult {
  const StoryDesktopVideoRecordStartResult._({
    required this.status,
    this.message,
  });

  factory StoryDesktopVideoRecordStartResult.unsupported([String? message]) =>
      StoryDesktopVideoRecordStartResult._(
        status: StoryDesktopVideoRecordStatus.unsupported,
        message: message,
      );

  final StoryDesktopVideoRecordStatus status;
  final StoryDesktopVideoRecordingSession? session = null;
  final String? message;

  bool get isSuccess => status == StoryDesktopVideoRecordStatus.success;
}

class StoryDesktopVideoRecordResult {
  const StoryDesktopVideoRecordResult._({
    required this.status,
    this.message,
  });

  factory StoryDesktopVideoRecordResult.failed([String? message]) =>
      StoryDesktopVideoRecordResult._(
        status: StoryDesktopVideoRecordStatus.failed,
        message: message,
      );

  final StoryDesktopVideoRecordStatus status;
  final String? path = null;
  final String? name = null;
  final int? sizeBytes = null;
  final String? message;

  bool get isSuccess => status == StoryDesktopVideoRecordStatus.success;
}

enum StoryDesktopVideoRecordStatus {
  success,
  unsupported,
  failed,
}

class StoryDesktopVideoRecordingSession {
  const StoryDesktopVideoRecordingSession();

  Future<StoryDesktopVideoRecordResult> stop() async {
    return StoryDesktopVideoRecordResult.failed(
      'Desktop story video recording is not available on this platform.',
    );
  }

  Future<void> cancel() async {}
}

class StoryDesktopVideoRecorder {
  const StoryDesktopVideoRecorder();

  Future<StoryDesktopVideoRecordStartResult> start({
    required String deviceLabel,
    String? sourceName,
  }) async {
    return StoryDesktopVideoRecordStartResult.unsupported(
      'Desktop story video recording is not available on this platform.',
    );
  }
}

List<String> storyDesktopVideoRecordArguments({
  required String deviceLabel,
  required String outputPath,
  Duration maxDuration = const Duration(seconds: 30),
}) {
  return const [];
}
