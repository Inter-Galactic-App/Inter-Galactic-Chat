import 'package:flutter/material.dart';

class StalePeerInfo {
  int index;
  String? displayName;
  String? identifier;
  String? localClientId;
  ImageProvider? avatar;
  StalePeerInfo({
    required this.index,
    this.displayName,
    this.identifier,
    this.localClientId,
    this.avatar,
  });
}

class StaleSpaceInfo {
  int index;
  String? name;
  ImageProvider? avatar;
  ImageProvider? userAvatar;
  StaleSpaceInfo(
      {required this.index, this.name, this.avatar, this.userAvatar});
}

class StaleRoomInfo {
  String? name;
  String? topic;
  ImageProvider? avatar;

  StaleRoomInfo({this.name, this.avatar, this.topic});
}
