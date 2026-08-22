import 'dart:typed_data';

import 'package:intergalactic/cache/file_provider.dart';
import 'package:intergalactic/utils/local_file.dart';
import 'package:intergalactic/utils/mime.dart';
import 'package:flutter/material.dart';

import 'package:mime/mime.dart' as mime;

abstract class Attachment {
  late String name;
}

abstract class ProcessedAttachment {}

class PendingFileAttachment {
  String? name;
  String? path;
  Uint8List? data;
  String? mimeType;
  int? size;

  Uint8List? thumbnailFile;
  String? thumbnailMime;
  Size? dimensions;
  Duration? length;
  bool spoiler;

  PendingFileAttachment(
      {this.name,
      this.path,
      this.data,
      this.mimeType,
      this.size,
      this.spoiler = false}) {
    assert(path != null || data != null);

    mimeType ??= Mime.lookupType(path ?? name ?? '', data: data);
  }

  Future<void> resolve() async {
    if (data != null) return;

    if (path != null && await localFileExists(path!)) {
      data = await readLocalFileBytes(path!);
      mimeType ??= mime.lookupMimeType(path!, headerBytes: data);
    }
  }

  ImageProvider? getAsImage() {
    if (Mime.imageTypes.contains(mimeType)) {
      if (data != null) {
        return Image.memory(data!).image;
      } else if (path != null) {
        return buildLocalFileImage(path!);
      }
    }

    return null;
  }
}

class FileAttachment implements Attachment {
  @override
  String name;
  int? fileSize;
  String? mimeType;
  FileProvider file;
  bool spoiler;
  FileAttachment(this.file,
      {required this.name, this.fileSize, this.mimeType, this.spoiler = false});
}

class AudioAttachment extends FileAttachment {
  final Duration? duration;

  AudioAttachment(super.file,
      {required super.name,
      required super.mimeType,
      this.duration,
      super.fileSize,
      super.spoiler});
}

class ImageAttachment extends FileAttachment {
  final ImageProvider image;
  final double? width;
  final double? height;

  double get aspectRatio =>
      (width != null && height != null) ? (width! / height!) : 1;

  ImageAttachment(
    this.image,
    super.file, {
    required super.name,
    required super.mimeType,
    super.fileSize,
    super.spoiler,
    this.width,
    this.height,
  });
}

class VideoAttachment extends FileAttachment {
  final ImageProvider? thumbnail;
  final double? width;
  final double? height;
  final Duration? duration;

  double get aspectRatio =>
      (width != null && height != null) ? (width! / height!) : 1;

  VideoAttachment(super.file,
      {required super.name,
      required super.mimeType,
      this.thumbnail,
      this.width,
      this.height,
      this.duration,
      super.spoiler,
      super.fileSize});
}
