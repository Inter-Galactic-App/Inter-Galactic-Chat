import 'package:intergalactic/client/components/push_notification/notifier.dart';
import 'package:intergalactic/client/components/push_notification/platform_notifier_factory_stub.dart'
    if (dart.library.io)
        'package:intergalactic/client/components/push_notification/platform_notifier_factory_io.dart'
    as platform_notifier_factory;

Notifier? getPlatformNotifier({bool isBackgroundService = false}) {
  return platform_notifier_factory.getPlatformNotifier(
      isBackgroundService: isBackgroundService);
}

