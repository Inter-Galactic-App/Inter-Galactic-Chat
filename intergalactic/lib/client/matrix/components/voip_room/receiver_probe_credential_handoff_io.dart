import 'dart:async';
import 'dart:convert';

import 'package:dart_ipc/dart_ipc.dart' as ipc;
import 'package:intergalactic/config/platform_utils.dart';

Future<void> writeReceiverProbeCredentialEnvelope({
  required String controlPipe,
  required Map<String, Object?> envelope,
}) async {
  // Developer-mode diagnostic IPC only: callers must generate a protected,
  // high-entropy local pipe name and keep it out of persisted reports. The
  // receiver gets short-lived credentials over this loopback/pipe handoff.
  final pipePath = _receiverProbeControlPipePath(controlPipe);
  final server = await ipc.bind(pipePath).timeout(
        const Duration(seconds: 10),
      );
  try {
    final socket = await server.first.timeout(
      const Duration(seconds: 30),
    );
    try {
      socket.write(jsonEncode(envelope));
      await socket.flush().timeout(const Duration(seconds: 5));
      await socket.close().timeout(const Duration(seconds: 5));
    } finally {
      socket.destroy();
    }
  } finally {
    await server.close();
  }
}

String _receiverProbeControlPipePath(String controlPipe) {
  if (!PlatformUtils.isWindows) {
    return controlPipe;
  }
  if (controlPipe.startsWith(r'\\.\pipe\')) {
    return controlPipe;
  }
  return r'\\.\pipe\' + controlPipe;
}
