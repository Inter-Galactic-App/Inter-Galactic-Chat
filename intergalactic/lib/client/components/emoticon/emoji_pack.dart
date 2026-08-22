import 'dart:async';
import 'dart:typed_data';

import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:flutter/material.dart';

abstract class EmoticonPack {
  String get identifier;
  String get attribution;
  String get displayName;
  String get ownerId;
  String get ownerDisplayName;

  /// Stable per-account key used only for a user's picker ordering.
  ///
  /// A pack's Matrix state key is only unique within its owning room/account,
  /// so the owner identifier is included before persisting the order.
  String get orderKey => '$ownerId\u0000$identifier';

  bool get isGloballyAvailable;

  List<Emoticon> get emotes;

  List<Emoticon> get emoji;

  List<Emoticon> get stickers;

  List<String> getShortcodes();

  ImageProvider? get image;
  IconData? get icon;

  EmoticonUsage get usage;

  Future<void> deleteEmoticon(Emoticon emoticon);

  Future<void> setPackUsage(EmoticonUsage usage);

  Future<void> updatePack({
    EmoticonUsage? usage,
    String? name,
    Uint8List? imageData,
  });

  Emoticon? getByShortcode(String shortcode);

  bool get isStickerPack;

  bool get isEmojiPack;

  Future<void> updateEmoticon({
    String? slug,
    String? shortcode,
    Uint8List? data,
    String? mimeType,
    EmoticonUsage? usage,
    required Emoticon previous,
  });

  /// Reorders the existing items without renaming or re-uploading them.
  /// Implementations that cannot edit a pack fail explicitly rather than
  /// silently changing the picker only in memory.
  Future<void> reorderEmoticons(List<String> shortcodes) {
    throw UnsupportedError('This emoticon pack cannot be reordered.');
  }

  Future<void> addEmoticon({
    required String slug,
    String? shortcode,
    required Uint8List data,
    String? mimeType,
    EmoticonUsage usage,
  });

  Future<void> markAsGlobal(bool isGlobal);
}
