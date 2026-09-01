import 'dart:io';

import 'dart:typed_data';
import 'package:intergalactic/config/app_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:dart_ipc/dart_ipc.dart';
import 'dart:convert';

import 'package:window_manager/window_manager.dart';

class SingleInstance {
  static const String _devInstanceIdEnvironment =
      "INTERGALACTIC_DEV_INSTANCE_ID";

  static Future<String> _socketPath() async {
    final path = await AppConfig.getSocketPath();
    if (!PlatformUtils.isWindows) {
      return path;
    }

    final instanceId = Platform.environment[_devInstanceIdEnvironment]?.trim();
    if (instanceId == null || instanceId.isEmpty) {
      return path;
    }

    final safeInstanceId = instanceId.replaceAll(
      RegExp(r"[^A-Za-z0-9_.-]"),
      "_",
    );
    return "$path.$safeInstanceId";
  }

  static Future<bool> tryConnectToMainInstance(List<String> args) async {
    var path = await _socketPath();

    print("Connecting to socket... $path");
    try {
      var socket = await connect(path).timeout(Duration(seconds: 3));
      print("Connected to socket: $socket");

      var msg = await socket.first;

      var data = jsonDecode(utf8.decode(msg));

      if (data["type"] == "hello") {
        socket.write(jsonEncode({"type": "new_instance_started"}));
      }

      return true;
    } catch (e, s) {
      Log.onError(e, s);

      if (e is SocketException) {
        if (PlatformUtils.isLinux) {
          if (e.osError?.errorCode == 111) {
            Log.i(
              "Socket exists but did not respond, the main instance either closed or crashed, so it should be fine to remove the socket",
            );
            await File(path).delete();
            return false;
          }

          if (e.osError?.errorCode == 2) {
            Log.i("Socket does not exist!");

            return false;
          }
        }
      }

      return false;
    }
  }

  static void becomeMainInstance() async {
    var path = await _socketPath();

    print("Connecting to socket... $path");

    var serverSocket = await bind(path);

    serverSocket.listen((socket) {
      handleSocket(socket, serverSocket);
    });
  }

  static void handleSocket(Socket socket, ServerSocket serverSocket) {
    socket.write(jsonEncode({"type": "hello"}));

    socket.listen(
      (data) {
        try {
          handleSocketMessageReceived(data);
        } catch (e, s) {
          Log.onError(e, s);
        }
      },
      onDone: () {
        print("Client Done");
      },
      onError: (e) {
        print("Client Error: $e");
      },
    );
  }

  static void handleSocketMessageReceived(Uint8List data) {
    var message = jsonDecode(utf8.decode(data));

    if (message["type"] == "new_instance_started") {
      Log.i("Bringing to front");
      windowManager.show();
    } else if (message["type"] == "stream_lab_open_room") {
      final room = message["room"];
      if (room is! String || room.trim().isEmpty) {
        return;
      }
      final clientId = message["client_id"];
      final requestNonce = _streamLabMetadataValue(message["request_nonce"]);
      final roomHash = _streamLabMetadataValue(message["room_hash"]);
      Log.i(
        "Stream-lab open-room IPC request received.",
        category: LogCategory.livekit,
        source: "stream-lab-open-room",
      );
      EventBus.openRoomFromStreamLab(
        (
          room.trim(),
          clientId is String && clientId.trim().isNotEmpty
              ? clientId.trim()
              : null,
        ),
        requestNonce: requestNonce,
        roomHash: roomHash,
      );
      windowManager.show();
    }
  }

  static String? _streamLabMetadataValue(dynamic value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty ||
        !RegExp(r'^[A-Za-z0-9_.-]{1,128}$').hasMatch(trimmed)) {
      return null;
    }
    return trimmed;
  }
}
