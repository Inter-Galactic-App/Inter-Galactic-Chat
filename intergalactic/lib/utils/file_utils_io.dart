import 'dart:io';

import 'package:intergalactic/config/platform_utils.dart';

class FileUtils {
  static void navigateToFile(String file) {
    if (PlatformUtils.isLinux) {
      var fileUri = Uri.parse(file);
      fileUri = Uri.file(file);
      _navigateToFileLinux(fileUri);
    }
  }

  static Future<void> openDirectory(String directory) async {
    if (PlatformUtils.isWindows) {
      await Process.start(
        'explorer.exe',
        [directory],
        mode: ProcessStartMode.detached,
      );
      return;
    }

    if (Platform.isMacOS) {
      await Process.start(
        'open',
        [directory],
        mode: ProcessStartMode.detached,
      );
      return;
    }

    if (PlatformUtils.isLinux) {
      await Process.start(
        'xdg-open',
        [directory],
        mode: ProcessStartMode.detached,
      );
    }
  }
}

Future<void> _navigateToFileLinux(Uri file) async {
  if (await File.fromUri(file).exists()) {
    await Process.start(
      'dbus-send',
      [
        '--session',
        '--print-reply',
        '--dest=org.freedesktop.FileManager1',
        '--type=method_call',
        '/org/freedesktop/FileManager1',
        'org.freedesktop.FileManager1.ShowItems',
        'array:string:${file}',
        'string:""',
      ],
      runInShell: true,
      includeParentEnvironment: true,
      mode: ProcessStartMode.detached,
    );
  }
}
