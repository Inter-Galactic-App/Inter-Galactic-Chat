import 'package:intergalactic/client/components/push_notification/android/android_notifier.dart';
import 'package:intergalactic/client/components/push_notification/android/embedded_ntfy_notifier.dart';
import 'package:intergalactic/client/components/push_notification/android/firebase_push_notifier.dart';
import 'package:intergalactic/client/components/push_notification/ios/ios_notifier.dart';
import 'package:intergalactic/client/components/push_notification/linux/linux_notifier.dart';
import 'package:intergalactic/client/components/push_notification/notifier.dart';
import 'package:intergalactic/client/components/push_notification/windows/windows_notifier.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/platform_utils.dart';

Notifier? getPlatformNotifier({bool isBackgroundService = false}) {
  if (PlatformUtils.isLinux) {
    return LinuxNotifier();
  }

  if (PlatformUtils.isWindows) {
    return WindowsNotifier();
  }

  if (PlatformUtils.isAndroid) {
    if (isBackgroundService) {
      return AndroidNotifier();
    }

    if (BuildConfig.ENABLE_GOOGLE_SERVICES) {
      return FirebasePushNotifier();
    }

    // Use embedded ntfy push — no external distributor app required.
    return EmbeddedNtfyNotifier();
  }

  if (PlatformUtils.isIOS) {
    return IosNotifier();
  }

  return null;
}
