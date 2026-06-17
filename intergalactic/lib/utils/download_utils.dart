import 'dart:async';
import 'dart:typed_data';

import 'package:intergalactic/cache/file_provider.dart';
import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/background_tasks/background_task_manager.dart';
import 'package:intergalactic/utils/file_utils.dart';
import 'package:intergalactic/utils/mime.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class DownloadFileTask implements BackgroundTaskWithOptionalProgress {
  static const MethodChannel _iosMediaSaverChannel =
      MethodChannel('chat.intergalactic.app/media_saver');
  static const Set<String> _iosPhotosImageMimeTypes = {
    ...Mime.imageTypes,
    'image/heic',
    'image/heif',
    'image/heic-sequence',
    'image/heif-sequence',
  };

  FileProvider file;
  late String filename;
  final String? mimeType;

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

  DownloadFileTask(this.file, String? fileName, {this.mimeType}) {
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
      final amount = downloadProgress.downloaded.toDouble() /
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
        savedToPhotos = await _saveImageBytesToPhotos(bytes);
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
          bytes: bytes);

      return byteBackedSaveCompletedForPlatform(
        destinationPath: destinationPath,
        isWeb: kIsWeb,
      );
    }

    destinationPath = await FilePicker.platform.saveFile(
        fileName: filename,
        initialDirectory: preferences.lastDownloadLocation.value);

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

  Future<bool> _saveImageBytesToPhotos(Uint8List bytes) async {
    try {
      final saved = await _iosMediaSaverChannel.invokeMethod<bool>(
        'saveImageToPhotos',
        {
          'bytes': bytes,
          'filename': filename,
          'mimeType': _effectiveMimeType(mimeType, filename),
        },
      );
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
    final extension =
        nameParts.length > 1 ? nameParts.last.toLowerCase() : null;
    return switch (extension) {
      'heic' => 'image/heic',
      'heif' => 'image/heif',
      _ => null,
    };
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
  static Future<void> downloadAttachment(Attachment attachment) async {
    FileProvider? file;
    String name = "untitled";

    if (attachment is FileAttachment) {
      file = attachment.file;
      name = attachment.name;
    } else {
      return;
    }

    final task = DownloadFileTask(file, name, mimeType: attachment.mimeType);
    backgroundTaskManager.addTask(task);
    await task.run();
  }
}
