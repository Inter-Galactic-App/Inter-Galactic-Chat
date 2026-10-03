import 'dart:io';

import 'dart:typed_data';
import 'package:flutter/foundation.dart' show visibleForTesting;
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
  static const String _startupLockFileName = '.intergalactic-startup.lock';
  static RandomAccessFile? _startupLock;

  /// The suffix that keeps two dev instances apart, or an empty string outside
  /// a dev run. Windows only: the named pipe name is fixed, while every other
  /// platform puts the socket under the application support directory that
  /// `INTERGALACTIC_DEV_PROFILE_DIR` already separates.
  ///
  /// Both the socket path and the startup lock name are derived from this, so
  /// the two cannot separate one instance without separating the other.
  static String _devInstanceSuffix() {
    if (!PlatformUtils.isWindows) {
      return "";
    }

    final instanceId = Platform.environment[_devInstanceIdEnvironment]?.trim();
    if (instanceId == null || instanceId.isEmpty) {
      return "";
    }

    final safeInstanceId = instanceId.replaceAll(
      RegExp(r"[^A-Za-z0-9_.-]"),
      "_",
    );
    return ".$safeInstanceId";
  }

  static Future<String> _socketPath() async {
    final path = await AppConfig.getSocketPath();
    return "$path${_devInstanceSuffix()}";
  }

  /// Atomically either joins the already-running app or becomes its owner.
  ///
  /// A connect-then-unawaited-bind sequence has a startup gap: two processes
  /// can both fail the connect before either has bound the socket, then both
  /// continue into Matrix database initialization. A Windows named-pipe server
  /// name also permits more than one server instance, so it cannot arbitrate
  /// ownership by itself. A retained exclusive file lock in the database root
  /// is the ownership gate; only its holder starts the IPC server.
  ///
  /// Returns true when another instance owns the socket and has been notified;
  /// returns false only after this process has bound and started the server.
  static Future<bool> startOrConnectToMainInstance(List<String> args) async {
    if (_startupLock != null) {
      return false;
    }

    final path = await _socketPath();
    RandomAccessFile? acquiredLock;
    return _claimOrNotifyExisting(
      tryConnect: () => _tryConnectToMainInstance(path),
      tryClaimOwnership: () async {
        acquiredLock = await _tryAcquireStartupLock();
        return acquiredLock != null;
      },
      waitForOwner: () => _waitForMainInstance(path),
      becomeOwner: () async {
        await _becomeMainInstance(path);
        _startupLock = acquiredLock;
      },
      releaseOwnership: () async {
        final lock = acquiredLock;
        acquiredLock = null;
        if (lock != null) {
          await lock.close();
        }
      },
    );
  }

  static Future<RandomAccessFile?> _tryAcquireStartupLock() async {
    final databaseDirectory = Directory(await AppConfig.getDatabasePath());
    await databaseDirectory.create(recursive: true);
    // Carries the same instance suffix as the socket. Two dev instances that
    // share one lock cannot both own their own socket: the loser of the lock
    // then waits on a socket path that no process ever binds.
    final lock = await File(
      '${databaseDirectory.path}${Platform.pathSeparator}'
      '$_startupLockFileName${_devInstanceSuffix()}',
    ).open(mode: FileMode.append);

    try {
      await lock.lock(FileLock.exclusive);
      return lock;
    } on FileSystemException {
      await lock.close();
      return null;
    }
  }

  static Future<bool> _tryConnectToMainInstance(
    String path, {
    Duration timeout = const Duration(seconds: 3),
    bool reportFailure = true,
    bool removeStaleSocket = true,
  }) async {
    print("Connecting to socket... $path");
    try {
      var socket = await connect(path).timeout(timeout);
      print("Connected to socket: $socket");

      var msg = await socket.first.timeout(timeout);

      var data = jsonDecode(utf8.decode(msg));

      if (data["type"] == "hello") {
        socket.write(jsonEncode({"type": "new_instance_started"}));
      }

      return true;
    } catch (e, s) {
      if (reportFailure) {
        Log.onError(e, s);
      }

      if (e is SocketException) {
        if (PlatformUtils.isLinux) {
          if (e.osError?.errorCode == 111) {
            if (reportFailure) {
              Log.i(
                "Socket exists but did not respond, the main instance either closed or crashed, so it should be fine to remove the socket",
              );
            }
            if (removeStaleSocket) {
              try {
                await File(path).delete();
              } on FileSystemException catch (error) {
                // Best effort, and it has to be: a throw inside a catch block
                // is not caught by that block, so this would escape
                // `_tryConnectToMainInstance`, escape
                // `startOrConnectToMainInstance`, and land on the
                // fatal-error page in `appMain`. Two processes reaching the
                // connect together is the startup gap the lock exists to
                // close, so both can see errno 111 and both delete; the loser
                // gets PathNotFoundException. A socket path this process may
                // not remove ends the same way. Neither is a reason to refuse
                // to start: if the path really is unusable, `bind` says so
                // later, with the reason.
                if (reportFailure) {
                  Log.i(
                    "Could not remove the stale socket, continuing: $error",
                  );
                }
              }
            }
            return false;
          }

          if (e.osError?.errorCode == 2) {
            if (reportFailure) {
              Log.i("Socket does not exist!");
            }

            return false;
          }
        }
      }

      return false;
    }
  }

  static Future<bool> _waitForMainInstance(String path) async {
    const retryDelay = Duration(milliseconds: 100);
    const retries = 30;
    for (var attempt = 0; attempt < retries; attempt++) {
      if (await _tryConnectToMainInstance(
        path,
        timeout: retryDelay,
        reportFailure: false,
        // The wait only runs while another process holds the startup lock, so
        // a refused connection means the owner is not accepting yet, not that
        // the socket is stale. Deleting it here would unbind the live owner.
        removeStaleSocket: false,
      )) {
        return true;
      }
      await Future<void>.delayed(retryDelay);
    }
    return false;
  }

  static Future<void> _becomeMainInstance(String path) async {
    print("Connecting to socket... $path");

    final serverSocket = await bind(path);

    serverSocket.listen((socket) {
      handleSocket(socket, serverSocket);
    });
  }

  static Future<bool> _claimOrNotifyExisting({
    required Future<bool> Function() tryConnect,
    required Future<bool> Function() tryClaimOwnership,
    required Future<bool> Function() waitForOwner,
    required Future<void> Function() becomeOwner,
    required Future<void> Function() releaseOwnership,
  }) async {
    if (await tryConnect()) {
      return true;
    }

    if (!await tryClaimOwnership()) {
      if (await waitForOwner()) {
        return true;
      }
      // The wait ending has two causes and they need opposite answers. Either
      // the owner is alive and slower than the budget, or it stopped being an
      // owner while we waited - the OS drops its exclusive lock when the
      // process exits, and `becomeOwner` failing releases it explicitly while
      // that process stays alive on its own error page. One more claim tells
      // the two apart: it can only succeed if nobody holds the lock any more.
      //
      // Claiming here rather than continuing without the lock is deliberate.
      // Returning false would break what this function promises - false means
      // this process bound the socket - and it would put two processes into
      // Matrix database initialization, which is the whole condition the
      // lock closes.
      if (!await tryClaimOwnership()) {
        throw StateError(
          'Another Inter Galactic process holds startup ownership but did not '
          'become ready.',
        );
      }

      // Holding the lock is not the same as holding a usable socket path. The
      // owner that stopped being one can have bound and then died without
      // unlinking: on Linux the socket file outlives the process, nothing here
      // removes it on shutdown, and a killed process never closes its
      // `ServerSocket`. `waitForOwner` leaves that file alone on purpose -
      // deleting it there would unbind a live owner - so no step between the
      // failed first claim and `becomeOwner` removes it, and `bind` then fails
      // with "Address already in use" on the fatal-error page in `appMain`.
      //
      // One more connect settles it, and only here, because only here has this
      // process earned the right to delete: it holds the lock, so no live
      // owner can be starting. This is the connect wired with stale-socket
      // removal enabled, so a dead socket is cleared. It answering true means
      // an owner did come up after all, in which case it has now been notified
      // and the lock goes back rather than being held by a process that exits.
      //
      // It cannot notify twice. Reaching here means the first connect returned
      // false and every connect inside the wait returned false, and either
      // returning true would have returned from this function already.
      if (await tryConnect()) {
        await releaseOwnership();
        return true;
      }
    }

    try {
      await becomeOwner();
      return false;
    } catch (_) {
      await releaseOwnership();
      rethrow;
    }
  }

  @visibleForTesting
  static Future<bool> debugClaimOrNotifyExistingForTesting({
    required Future<bool> Function() tryConnect,
    required Future<bool> Function() tryClaimOwnership,
    required Future<bool> Function() waitForOwner,
    required Future<void> Function() becomeOwner,
    required Future<void> Function() releaseOwnership,
  }) {
    return _claimOrNotifyExisting(
      tryConnect: tryConnect,
      tryClaimOwnership: tryClaimOwnership,
      waitForOwner: waitForOwner,
      becomeOwner: becomeOwner,
      releaseOwnership: releaseOwnership,
    );
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
