import 'dart:async';

class ExternalLivekitReceiverProbeRuntime {
  static bool isInvocation(List<String> args) => false;

  static Future<int> run(List<String> args) async => 2;
}
