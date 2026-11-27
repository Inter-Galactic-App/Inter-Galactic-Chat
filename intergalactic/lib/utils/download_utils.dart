import 'dart:async';

import 'package:intergalactic/cache/file_provider.dart';
import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/background_tasks/background_task_manager.dart';
import 'package:intergalactic/utils/file_utils.dart';
import 'package:intergalactic/utils/mime.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart' as mime_lookup;

class DownloadFileTask implements BackgroundTaskWithOptionalProgress {
  static const MethodChannel _mediaSaverChannel = MethodChannel(
    'chat.intergalactic.app/media_saver',
  );
  static const Set<String> _iosPhotosImageMimeTypes = {
    ...Mime.imageTypes,
    'image/heic',
    'image/heif',
    'image/heic-sequence',
    'image/heif-sequence',
  };
  static const Set<String> _photosMediaMimeTypes = {
    ..._iosPhotosImageMimeTypes,
    ...Mime.videoTypes,
  };

  FileProvider file;
  late String filename;
  final String? mimeType;
  final Room? room;

  String? destinationPath;

  @override
  void Function()? action;

  @override
  bool get canCallAction => destinationPath != null && PlatformUtils.isLinux;

  @override
  void dispose() {
    sub?.cancel();
  }

  @override
  late String label;

  @override
  double? progress = 0;

  @override
  bool shouldRemoveTask = false;

  StreamSubscription? sub;

  @override
  BackgroundTaskStatus status = BackgroundTaskStatus.running;

  StreamController controller = StreamController.broadcast();
  @override
  Stream<void> get statusChanged => controller.stream;

  DownloadFileTask(this.file, String? fileName, {this.mimeType, this.room}) {
    filename = fileName ?? "unnamed";

    this.label = "Downloading '$filename'...";

    action = navigateToFile;
  }

  void navigateToFile() {
    if (destinationPath != null) {
      FileUtils.navigateToFile(destinationPath!);
    }
  }

  Future<void> run() async {
    try {
      var result = await _doDownload();
      status = switch (result) {
        true => BackgroundTaskStatus.completed,
        false => BackgroundTaskStatus.failed,
      };
    } catch (exception, trace) {
      Log.onError(exception, trace);
      status = BackgroundTaskStatus.failed;
    }

    controller.add(());

    Timer(const Duration(seconds: 5), () {
      shouldRemoveTask = true;
      controller.add(null);
    });
  }

  Future<bool> _doDownload() async {
    sub = file.onProgressChanged?.listen((downloadProgress) {
      final amount =
          downloadProgress.downloaded.toDouble() /
          downloadProgress.total.toDouble();
      progress = amount;

      controller.add(());
    });

    Uint8List? bytes;
    if (_saveImageToPhotos) {
      bytes = await file.getFileData();
      if (bytes == null) {
        return false;
      }

      var savedToPhotos = false;
      try {
        savedToPhotos = await saveImageBytesToPhotos(
          bytes: bytes,
          filename: filename,
          mimeType: mimeType,
        );
      } catch (error, stack) {
        Log.onError(
          error,
          stack,
          content: 'Failed to save image to Photos before file fallback',
        );
      }
      if (savedToPhotos) {
        return true;
      }
      Log.w(
        'Falling back to file save after Photos save failed.',
        category: LogCategory.media,
        source: 'download-utils',
      );
    }

    if (_saveFileRequiresBytes) {
      bytes ??= await file.getFileData();
      if (bytes == null) {
        return false;
      }

      destinationPath = await FilePicker.platform.saveFile(
        fileName: filename,
        initialDirectory: preferences.lastDownloadLocation.value,
        bytes: bytes,
      );

      return byteBackedSaveCompletedForPlatform(
        destinationPath: destinationPath,
        isWeb: kIsWeb,
      );
    }

    final preferredExtension = preferredSaveExtension(
      mimeType: mimeType,
      filename: filename,
    );
    destinationPath = await FilePicker.platform.saveFile(
      fileName: filename,
      initialDirectory: preferences.lastDownloadLocation.value,
      type: preferredExtension == null ? FileType.any : FileType.custom,
      allowedExtensions: preferredExtension == null
          ? null
          : [preferredExtension],
    );
    destinationPath = ensurePreferredSaveExtension(
      destinationPath,
      preferredExtension,
    );

    if (destinationPath != null) {
      await file.save(destinationPath!);
      return true;
    } else {
      return false;
    }
  }

  bool get _saveFileRequiresBytes => saveFileRequiresBytesForPlatform(
    isAndroid: PlatformUtils.isAndroid,
    isIOS: PlatformUtils.isIOS,
    isWeb: kIsWeb,
  );

  bool get _saveImageToPhotos => shouldSaveImageToPhotosForPlatform(
    isIOS: PlatformUtils.isIOS,
    mimeType: mimeType,
    filename: filename,
  );

  static Future<bool> saveImageBytesToPhotos({
    required Uint8List bytes,
    required String filename,
    String? mimeType,
  }) async {
    try {
      final saved = await _mediaSaverChannel
          .invokeMethod<bool>('saveImageToPhotos', {
            'bytes': bytes,
            'filename': filename,
            'mimeType': _effectiveMimeType(mimeType, filename),
          });
      return saved == true;
    } on PlatformException catch (error) {
      Log.w(
        'Failed to save image to iOS Photos: ${error.code}',
        category: LogCategory.media,
        source: 'download-utils',
      );
      return false;
    } on MissingPluginException catch (error) {
      Log.w(
        'iOS Photos media saver bridge unavailable: $error',
        category: LogCategory.media,
        source: 'download-utils',
      );
      return false;
    }
  }

  static Future<bool> saveMediaToPhotos({
    Uint8List? bytes,
    String? path,
    required String filename,
    String? mimeType,
  }) async {
    if (bytes == null && (path == null || path.trim().isEmpty)) {
      return false;
    }

    // The guard above only rejects a blank path when there are no bytes, so a
    // blank path could still be forwarded alongside bytes. Both natives
    // tolerate that today; normalise it here so the channel contract stays
    // "a path key means there is a usable path".
    final normalizedPath = path?.trim();

    try {
      final saved = await _mediaSaverChannel
          .invokeMethod<bool>('saveMediaToPhotos', {
            if (bytes != null) 'bytes': bytes,
            if (normalizedPath != null && normalizedPath.isNotEmpty)
              'path': normalizedPath,
            'filename': filename,
            'mimeType': _effectiveMimeType(mimeType, filename),
          });
      return saved == true;
    } on PlatformException catch (error) {
      Log.w(
        'Failed to save media to Photos: ${error.code}',
        category: LogCategory.media,
        source: 'download-utils',
      );
      return false;
    } on MissingPluginException catch (error) {
      Log.w(
        'Photos media saver bridge unavailable: $error',
        category: LogCategory.media,
        source: 'download-utils',
      );
      return false;
    }
  }

  @visibleForTesting
  static bool saveFileRequiresBytesForPlatform({
    required bool isAndroid,
    required bool isIOS,
    required bool isWeb,
  }) {
    return isAndroid || isIOS || isWeb;
  }

  @visibleForTesting
  static bool shouldSaveImageToPhotosForPlatform({
    required bool isIOS,
    required String? mimeType,
    required String filename,
  }) {
    if (!isIOS) {
      return false;
    }

    final effectiveMimeType = _effectiveMimeType(mimeType, filename);
    if (effectiveMimeType == null) {
      return false;
    }

    return _iosPhotosImageMimeTypes.contains(effectiveMimeType);
  }

  @visibleForTesting
  static bool shouldSaveMediaToPhotosForPlatform({
    required bool isAndroid,
    required bool isIOS,
    required String? mimeType,
    required String filename,
  }) {
    if (!isAndroid && !isIOS) {
      return false;
    }

    final effectiveMimeType = _effectiveMimeType(mimeType, filename);
    return effectiveMimeType != null &&
        _photosMediaMimeTypes.contains(effectiveMimeType);
  }

  static String? _effectiveMimeType(String? mimeType, String filename) {
    final normalizedMimeType = mimeType?.trim().toLowerCase();
    if (normalizedMimeType != null && normalizedMimeType.isNotEmpty) {
      return normalizedMimeType;
    }

    final detectedMimeType = Mime.lookupType(filename)?.toLowerCase();
    if (detectedMimeType != null) {
      return detectedMimeType;
    }

    final nameParts = filename.split('.');
    final extension = nameParts.length > 1
        ? nameParts.last.toLowerCase()
        : null;
    return switch (extension) {
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      _ => null,
    };
  }

  @visibleForTesting
  static String? preferredSaveExtension({
    required String? mimeType,
    required String filename,
  }) {
    final effectiveMimeType = _effectiveMimeType(mimeType, filename);
    final extension = effectiveMimeType == null
        ? null
        : mime_lookup.extensionFromMime(effectiveMimeType);
    if (extension != null && extension.isNotEmpty) {
      return extension;
    }

    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex == filename.length - 1) {
      return null;
    }
    return filename.substring(dotIndex + 1).toLowerCase();
  }

  @visibleForTesting
  static String? ensurePreferredSaveExtension(
    String? destinationPath,
    String? extension,
  ) {
    if (destinationPath == null || extension == null || extension.isEmpty) {
      return destinationPath;
    }

    final fileNameStart = destinationPath.lastIndexOf(RegExp(r'[\\/]')) + 1;
    final fileName = destinationPath.substring(fileNameStart);
    // `.video` is a dotfile and `video.` is a name someone stopped typing;
    // neither carries an extension, but `contains('.')` called both extended
    // and left the file with no usable type suffix on desktop.
    final dot = fileName.lastIndexOf('.');
    if (dot > 0 && dot < fileName.length - 1) {
      return destinationPath;
    }

    final normalized = destinationPath.endsWith('.')
        ? destinationPath.substring(0, destinationPath.length - 1)
        : destinationPath;
    return '$normalized.$extension';
  }

  @visibleForTesting
  static bool byteBackedSaveCompletedForPlatform({
    required String? destinationPath,
    required bool isWeb,
  }) {
    if (isWeb) {
      return true;
    }

    return destinationPath != null;
  }
}

class DownloadUtils {
  /// Whether a freshly captured photo/video should be mirrored into the device
  /// gallery. Split out from the save itself so the policy can be tested
  /// without a live method channel.
  @visibleForTesting
  static bool shouldAutoSaveCapturedMedia({
    required bool enabled,
    required bool isAndroid,
    required bool isIOS,
    required String? mimeType,
    required String filename,
  }) {
    if (!enabled) {
      return false;
    }

    return DownloadFileTask.shouldSaveMediaToPhotosForPlatform(
      isAndroid: isAndroid,
      isIOS: isIOS,
      mimeType: mimeType,
      filename: filename,
    );
  }

  /// Saves media the user just captured with an in-app camera to their gallery,
  /// when they have opted in.
  ///
  /// Deliberately never throws and never surfaces UI: this runs alongside a
  /// capture the user asked for, and a gallery-save failure must not derail
  /// sending the attachment or building the story draft. [enabled] defaults to
  /// the stored preference and exists for tests.
  static Future<bool> autoSaveCapturedMediaIfEnabled({
    required String filename,
    Uint8List? bytes,
    String? path,
    String? mimeType,
    bool? enabled,
  }) async {
    if (!shouldAutoSaveCapturedMedia(
      enabled: enabled ?? preferences.autoSaveCapturedMedia.value,
      isAndroid: PlatformUtils.isAndroid,
      isIOS: PlatformUtils.isIOS,
      mimeType: mimeType,
      filename: filename,
    )) {
      return false;
    }

    try {
      return await DownloadFileTask.saveMediaToPhotos(
        bytes: bytes,
        path: path,
        filename: filename,
        mimeType: mimeType,
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to auto-save captured media to the gallery',
        category: LogCategory.media,
        source: 'download-utils',
      );
      return false;
    }
  }

  static Future<bool> saveMediaToPhotosIfSupported({
    Uint8List? bytes,
    String? path,
    required String filename,
    String? mimeType,
  }) {
    if (!DownloadFileTask.shouldSaveMediaToPhotosForPlatform(
      isAndroid: PlatformUtils.isAndroid,
      isIOS: PlatformUtils.isIOS,
      mimeType: mimeType,
      filename: filename,
    )) {
      return Future.value(false);
    }

    return DownloadFileTask.saveMediaToPhotos(
      bytes: bytes,
      path: path,
      filename: filename,
      mimeType: mimeType,
    );
  }

  static Future<bool> saveImageBytesToPhotosIfSupported({
    required Uint8List bytes,
    required String filename,
    String? mimeType,
  }) {
    if (!DownloadFileTask.shouldSaveMediaToPhotosForPlatform(
      isAndroid: PlatformUtils.isAndroid,
      isIOS: PlatformUtils.isIOS,
      mimeType: mimeType,
      filename: filename,
    )) {
      return Future.value(false);
    }

    return DownloadFileTask.saveMediaToPhotos(
      bytes: bytes,
      filename: filename,
      mimeType: mimeType,
    );
  }

  static Future<void> downloadAttachment(
    Attachment attachment, {
    Room? room,
  }) async {
    FileProvider? file;
    String name = "untitled";

    if (attachment is FileAttachment) {
      file = attachment.file;
      name = attachment.name;
    } else {
      return;
    }

    final task = DownloadFileTask(
      file,
      name,
      mimeType: attachment.mimeType,
      room: room,
    );
    backgroundTaskManager.addTask(task);
    await task.run();
  }
}
