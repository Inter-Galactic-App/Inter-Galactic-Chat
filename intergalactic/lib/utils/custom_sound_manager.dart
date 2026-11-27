import 'dart:io';
import 'dart:convert';

import 'package:intergalactic/main.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

enum CustomSoundSlot {
  notification,
  ringtone;

  String get defaultAssetUri => switch (this) {
        CustomSoundSlot.notification => "asset:///assets/sound/message.ogg",
        CustomSoundSlot.ringtone => "asset:///assets/sound/ringtone_in.ogg",
      };

  String get defaultOutgoingAssetUri => switch (this) {
        CustomSoundSlot.notification => defaultAssetUri,
        CustomSoundSlot.ringtone => "asset:///assets/sound/ringtone_out.ogg",
      };

  String get defaultLabel => switch (this) {
        CustomSoundSlot.notification => "Default notification sound",
        CustomSoundSlot.ringtone => "Default ringtone",
      };

  String get fileStem => switch (this) {
        CustomSoundSlot.notification => "notification_sound",
        CustomSoundSlot.ringtone => "ringtone_sound",
      };
}

class CustomSoundManager {
  static const List<String> allowedExtensions = [
    'aac',
    'flac',
    'm4a',
    'mp3',
    'ogg',
    'wav',
    'webm',
  ];

  static String notificationSoundUri({String? roomLocalId}) {
    final defaultUri = _resolveStoredOrDefault(
      preferences.customNotificationSoundPath.value,
      CustomSoundSlot.notification.defaultAssetUri,
    );
    if (roomLocalId != null) {
      return _resolveStoredOrDefault(
        preferences.getRoomNotificationSoundPath(roomLocalId),
        defaultUri,
      );
    }

    return defaultUri;
  }

  static String roomNotificationSoundLabel(String roomLocalId) {
    return _displayLabel(
      preferences.getRoomNotificationSoundPath(roomLocalId),
      "Use app notification sound",
    );
  }

  static bool hasRoomNotificationSound(String roomLocalId) {
    final storedPath = preferences.getRoomNotificationSoundPath(roomLocalId);
    return storedPath != null && storedPath.trim().isNotEmpty;
  }

  static String notificationSoundLabel() {
    return _displayLabel(
      preferences.customNotificationSoundPath.value,
      CustomSoundSlot.notification.defaultLabel,
    );
  }

  static String ringtoneSoundUri({bool outgoing = false}) {
    final defaultUri = outgoing
        ? CustomSoundSlot.ringtone.defaultOutgoingAssetUri
        : CustomSoundSlot.ringtone.defaultAssetUri;
    return _resolveStoredOrDefault(
      preferences.customRingtoneSoundPath.value,
      defaultUri,
    );
  }

  static String ringtoneSoundLabel() {
    return _displayLabel(
      preferences.customRingtoneSoundPath.value,
      CustomSoundSlot.ringtone.defaultLabel,
    );
  }

  static Future<String> importCustomSound(
    String sourcePath, {
    required CustomSoundSlot slot,
  }) async {
    final soundsDir = await _customSoundsDirectory();
    await soundsDir.create(recursive: true);

    final extension = path.extension(sourcePath).toLowerCase();
    final fileName =
        "${slot.fileStem}${extension.isEmpty ? ".ogg" : extension}";
    final destination = path.join(soundsDir.path, fileName);
    return _copyImportedFile(
      sourcePath: sourcePath,
      destinationPath: destination,
    );
  }

  static Future<String> importRoomNotificationSound(
    String sourcePath, {
    required String roomLocalId,
  }) async {
    final soundsDir = await _customSoundsDirectory();
    await soundsDir.create(recursive: true);

    final extension = path.extension(sourcePath).toLowerCase();
    final fileName =
        "${_roomNotificationFileStem(roomLocalId)}${extension.isEmpty ? ".ogg" : extension}";
    final destination = path.join(soundsDir.path, fileName);
    return _copyImportedFile(
      sourcePath: sourcePath,
      destinationPath: destination,
    );
  }

  static Future<void> deleteImportedSound(String? storedPath) async {
    if (storedPath == null || storedPath.isEmpty) {
      return;
    }

    final file = File(storedPath);
    if (!file.existsSync()) {
      return;
    }

    final soundsDir = await _customSoundsDirectory();
    final normalizedDir = path.normalize(soundsDir.path);
    final normalizedFile = path.normalize(file.path);

    if (!path.isWithin(normalizedDir, normalizedFile) &&
        normalizedDir != normalizedFile) {
      return;
    }

    await file.delete();
  }

  static String _resolveStoredOrDefault(String? storedPath, String defaultUri) {
    if (storedPath == null || storedPath.isEmpty) {
      return defaultUri;
    }

    final file = File(storedPath);
    if (!file.existsSync()) {
      return defaultUri;
    }

    return Uri.file(file.path).toString();
  }

  static String _displayLabel(String? storedPath, String defaultLabel) {
    if (storedPath == null || storedPath.isEmpty) {
      return defaultLabel;
    }

    final file = File(storedPath);
    if (!file.existsSync()) {
      return defaultLabel;
    }

    return path.basename(file.path);
  }

  static Future<Directory> _customSoundsDirectory() async {
    final dir = await getApplicationSupportDirectory();
    return Directory(path.join(dir.path, "custom_sounds"));
  }

  static Future<String> _copyImportedFile({
    required String sourcePath,
    required String destinationPath,
  }) async {
    final source = File(sourcePath);
    final destination = File(destinationPath);

    if (await destination.exists() &&
        await FileSystemEntity.identical(source.path, destination.path)) {
      return destinationPath;
    }

    if (await destination.exists()) {
      await destination.delete();
    }

    await source.copy(destinationPath);
    return destinationPath;
  }

  static String _roomNotificationFileStem(String roomLocalId) {
    final encoded = base64Url.encode(utf8.encode(roomLocalId));
    return "room_notification_${encoded.replaceAll("=", "")}";
  }
}
