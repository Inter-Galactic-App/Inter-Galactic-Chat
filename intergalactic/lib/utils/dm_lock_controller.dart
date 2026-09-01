import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/config/preferences.dart';

class DmLockController with WidgetsBindingObserver {
  static const int _pinIterations = 120000;
  static const int _pinBits = 256;
  static const int _saltLength = 16;

  final StreamController<void> _onChangedController =
      StreamController<void>.broadcast();
  final Set<String> _sessionUnlockedRooms = <String>{};
  final Random _random = Random.secure();

  late Preferences _preferences;
  bool _initialized = false;

  Stream<void> get onChanged => _onChangedController.stream;

  String get maskedPreviewText => "PIN locked";

  Future<void> init(Preferences preferences) async {
    if (_initialized) {
      return;
    }

    _preferences = preferences;
    WidgetsBinding.instance.addObserver(this);
    _initialized = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      return;
    }

    clearSessionUnlocks();
  }

  bool isRoomLockable(Room room) {
    final directMessages = room.client.getComponent<DirectMessagesComponent>();
    return directMessages?.isRoomDirectMessage(room) == true;
  }

  bool isPinConfiguredForClient(Client client) {
    return _pinMetadataForClient(client) != null;
  }

  bool isRoomLocked(Room room) {
    if (!isRoomLockable(room)) {
      return false;
    }

    return _preferences.getDmLockRoomIds().contains(room.localId);
  }

  bool isRoomUnlocked(Room room) {
    return _sessionUnlockedRooms.contains(room.localId);
  }

  bool shouldMaskRoomPreview(Room room) {
    return isRoomLocked(room) && !isRoomUnlocked(room);
  }

  List<String> getLockedRoomIdsForClient(Client client) {
    final prefix = "${client.identifier}:";
    return _preferences
        .getDmLockRoomIds()
        .where((roomId) => roomId.startsWith(prefix))
        .toList()
      ..sort();
  }

  List<Room> getLockedRoomsForClient(Client client) {
    final lockedIds = getLockedRoomIdsForClient(client).toSet();
    final rooms = client.rooms
        .where((room) => lockedIds.contains(room.localId))
        .toList(growable: false);

    return rooms.sorted(
      (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
    );
  }

  Future<void> setPinForClient(Client client, String pin) async {
    final salt = _createSalt();
    final hash = await _deriveHash(
      pin,
      saltBase64: salt,
      iterations: _pinIterations,
    );

    final metadata = _preferences.getDmLockPinMetadata();
    metadata[client.identifier] = <String, dynamic>{
      "salt": salt,
      "hash": hash,
      "iterations": _pinIterations,
      "updatedAt": DateTime.now().toIso8601String(),
    };

    await _preferences.setDmLockPinMetadata(metadata);
    _notify();
  }

  Future<bool> verifyPinForClient(Client client, String pin) async {
    final metadata = _pinMetadataForClient(client);
    if (metadata == null) {
      return false;
    }

    final salt = metadata["salt"] as String?;
    final expectedHash = metadata["hash"] as String?;
    final iterations =
        (metadata["iterations"] as num?)?.toInt() ?? _pinIterations;

    if (salt == null || expectedHash == null) {
      return false;
    }

    final actualHash = await _deriveHash(
      pin,
      saltBase64: salt,
      iterations: iterations,
    );

    final expectedBytes = utf8.encode(expectedHash);
    final actualBytes = utf8.encode(actualHash);
    if (expectedBytes.length != actualBytes.length) {
      return false;
    }

    var diff = 0;
    for (var i = 0; i < expectedBytes.length; i++) {
      diff |= expectedBytes[i] ^ actualBytes[i];
    }

    return diff == 0;
  }

  Future<bool> unlockRoomForSession(Room room, String pin) async {
    if (!isRoomLocked(room)) {
      return true;
    }

    final verified = await verifyPinForClient(room.client, pin);
    if (!verified) {
      return false;
    }

    _sessionUnlockedRooms.add(room.localId);
    _notify();
    return true;
  }

  Future<bool> unlockRoomForSessionWithBiometrics(Room room) async {
    if (!isRoomLocked(room)) {
      return true;
    }

    if (!isPinConfiguredForClient(room.client)) {
      return false;
    }

    _sessionUnlockedRooms.add(room.localId);
    _notify();
    return true;
  }

  Future<void> setRoomLocked(Room room, bool locked) async {
    if (!isRoomLockable(room)) {
      return;
    }

    final roomIds = List<String>.from(_preferences.getDmLockRoomIds());
    roomIds.removeWhere((roomId) => roomId == room.localId);

    if (locked) {
      roomIds.add(room.localId);
    } else {
      _sessionUnlockedRooms.remove(room.localId);
    }

    roomIds.sort();
    await _preferences.setDmLockRoomIds(roomIds);
    _notify();
  }

  Future<void> removePinForClient(Client client) async {
    final metadata = _preferences.getDmLockPinMetadata();
    metadata.remove(client.identifier);
    await _preferences.setDmLockPinMetadata(metadata);

    final prefix = "${client.identifier}:";
    final roomIds = _preferences
        .getDmLockRoomIds()
        .where((roomId) => !roomId.startsWith(prefix))
        .toList()
      ..sort();
    await _preferences.setDmLockRoomIds(roomIds);

    _sessionUnlockedRooms.removeWhere((roomId) => roomId.startsWith(prefix));
    _notify();
  }

  void clearSessionUnlocks() {
    if (_sessionUnlockedRooms.isEmpty) {
      return;
    }

    _sessionUnlockedRooms.clear();
    _notify();
  }

  Map<String, dynamic>? _pinMetadataForClient(Client client) {
    final metadata = _preferences.getDmLockPinMetadata()[client.identifier];
    if (metadata is Map<String, dynamic>) {
      return metadata;
    }

    if (metadata is Map) {
      return metadata.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    return null;
  }

  String _createSalt() {
    final bytes =
        List<int>.generate(_saltLength, (_) => _random.nextInt(256));
    return base64Encode(bytes);
  }

  Future<String> _deriveHash(
    String pin, {
    required String saltBase64,
    required int iterations,
  }) async {
    final algorithm = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: _pinBits,
    );

    final key = await algorithm.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: base64Decode(saltBase64),
    );

    return base64Encode(await key.extractBytes());
  }

  void _notify() {
    Preferences.onSettingChangedController.add(null);
    _onChangedController.add(null);
  }
}

extension DmLockSortedList<T> on List<T> {
  List<T> sorted(int Function(T a, T b) compare) {
    final copy = List<T>.from(this);
    copy.sort(compare);
    return copy;
  }
}
