import 'package:intergalactic/utils/custom_uri.dart';

class AndroidIntentHelper {
  static CustomURI? getUriFromIntent(dynamic intent) {
    var key = 'flutter_shortcuts_new';

    if (intent?.action == 'SELECT_NOTIFICATION') {
      key = 'payload';
    }

    final extra = intent?.extra;
    if (extra?.containsKey(key) == true) {
      return CustomURI.parse(extra[key]);
    }

    return null;
  }
}
