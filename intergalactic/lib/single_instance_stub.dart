class SingleInstance {
  static Future<bool> tryConnectToMainInstance(List<String> args) async {
    return false;
  }

  static void becomeMainInstance() {}
}
