import 'package:intergalactic/config/subplatforms/subplatforms.dart';

class SteamdeckSubplatform implements Subplatform {
  @override
  Future<void> init() async {}

  @override
  String get name => "unsupported";

  static Future<bool> isSteamdeck() async {
    return false;
  }
}

