import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_ipc/dart_ipc.dart' as ipc;

Future<void> writeReceiverProbeCredentialEnvelope({
  required String controlPipe,
  required Map<String, Object?> envelope,
}) async {
  final pipeName = controlPipe.trim();
  if (pipeName.isEmpty) {
    throw ArgumentError.value(controlPipe, 'controlPipe', 'must not be empty');
  }

  final path = Platform.isWindows ? r'\\.\pipe\' + pipeName : pipeName;
  final connectFuture = ipc.connect(path);
  Socket? socket;
  try {
    final connectedSocket = await connectFuture.timeout(
      const Duration(seconds: 15),
    );
    socket = connectedSocket;
    connectedSocket.add(utf8.encode(jsonEncode(envelope)));
    await connectedSocket.flush().timeout(const Duration(seconds: 15));
    await connectedSocket.close().timeout(const Duration(seconds: 15));
  } on TimeoutException {
    unawaited(
      connectFuture.then<void>(
        (lateSocket) => lateSocket.destroy(),
        onError: (_) {},
      ),
    );
    rethrow;
  } finally {
    socket?.destroy();
  }
}
