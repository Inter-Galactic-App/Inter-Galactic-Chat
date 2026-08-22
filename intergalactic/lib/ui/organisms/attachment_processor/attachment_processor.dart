import 'dart:async';
import 'dart:typed_data';

import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/config/app_globals.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/ui/atoms/scaled_safe_area.dart';
import 'package:intergalactic/ui/molecules/file_preview.dart';
import 'package:intergalactic/ui/molecules/video_player/video_player_controller.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/utils/local_file.dart';
import 'package:intergalactic/utils/mime.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img;
import 'package:tiamat/tiamat.dart' as tiamat;

String? resolveAttachmentMimeType(
  PendingFileAttachment attachment, {
  Uint8List? data,
}) {
  // An attachment's declared type and filename are advisory. When bytes are
  // available, an image signature is the authoritative type for preparation:
  // otherwise a GIF renamed to `.png`, for example, would miss its GIF
  // metadata sanitizer.
  final detectedImageType = _normalizeAttachmentMimeType(
    data == null && attachment.data == null
        ? null
        : Mime.lookupType('', data: data ?? attachment.data),
  );
  if (Mime.imageTypes.contains(detectedImageType)) {
    return detectedImageType;
  }

  final suppliedType = _normalizeAttachmentMimeType(attachment.mimeType);
  if (suppliedType != null && !_isGenericAttachmentMimeType(suppliedType)) {
    return suppliedType;
  }

  return _normalizeAttachmentMimeType(
    Mime.lookupType(
      attachment.name ?? attachment.path ?? '',
      data: data ?? attachment.data,
    ),
  );
}

bool _isGenericAttachmentMimeType(String mimeType) {
  return const {
    'application/octet-stream',
    'application/unknown',
    'binary/octet-stream',
  }.contains(mimeType);
}

String? _normalizeAttachmentMimeType(String? mimeType) {
  final normalized = mimeType?.trim().toLowerCase();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }

  return switch (normalized) {
    'image/jpg' => 'image/jpeg',
    'image/x-png' => 'image/png',
    'image/x-ms-bmp' => 'image/bmp',
    _ => normalized,
  };
}

bool isPhotoAttachment(PendingFileAttachment attachment) {
  return Mime.imageTypes.contains(resolveAttachmentMimeType(attachment));
}

/// Resolves the type used by composer attachment preparation.
///
/// Path-backed attachments have no bytes at selection time. A bounded header
/// read recognizes images whose picker type or extension is misleading without
/// materializing their full payload.
Future<String?> resolveAttachmentMimeTypeForComposer(
  PendingFileAttachment attachment,
) async {
  var mimeType = resolveAttachmentMimeType(attachment);
  if (!Mime.imageTypes.contains(mimeType) &&
      attachment.data == null &&
      attachment.path != null) {
    final header = await readLocalFileHeader(attachment.path!);
    mimeType = resolveAttachmentMimeType(attachment, data: header);
    if (Mime.imageTypes.contains(mimeType)) {
      attachment.mimeType = mimeType;
    }
  }
  return mimeType;
}

bool areAttachedPhotosHidden(Iterable<PendingFileAttachment> attachments) {
  final photos = attachments.where(isPhotoAttachment);
  return photos.isNotEmpty && photos.every((attachment) => attachment.spoiler);
}

void toggleAttachedPhotoSpoilers(Iterable<PendingFileAttachment> attachments) {
  final hidePhotos = !areAttachedPhotosHidden(attachments);
  for (final attachment in attachments.where(isPhotoAttachment)) {
    attachment.spoiler = hidePhotos;
  }
}

/// Applies the composer preparation flow for a selected attachment.
///
/// Photos are prepared automatically, while other attachment types retain the
/// existing confirmation dialog.
Future<PendingFileAttachment?> prepareAttachmentForComposer(
  BuildContext context,
  PendingFileAttachment attachment,
) async {
  final mimeType = await resolveAttachmentMimeTypeForComposer(attachment);

  if (Mime.imageTypes.contains(mimeType)) {
    return preparePhotoAttachmentForSend(
      attachment,
      removeMetadata: preferences.removePhotoMetadataBeforeSending.value,
    );
  }

  // The MIME resolution above is a bounded file read, so the context can be
  // gone by the time a path-backed non-image attachment reaches the dialog.
  // The callers in chat.dart check `mounted` only AFTER this function returns,
  // which does not protect this call.
  if (!context.mounted) return null;

  return AdaptiveDialog.show<PendingFileAttachment>(
    context,
    scrollable: false,
    builder: (context) => AttachmentProcessor(attachment: attachment),
  );
}

/// Removes photo metadata before the file enters the composer send queue.
///
/// GIF animation blocks stay byte-for-byte intact. Comment and non-loop
/// application blocks are removed without decoding or re-encoding frames. If a
/// GIF cannot be parsed safely, the original attachment is preserved.
const maxPhotoMetadataPreparationBytes = 50 * 1000 * 1000;
const maxPhotoMetadataPreparationPixels = 64 * 1024 * 1024;

Future<PendingFileAttachment> preparePhotoAttachmentForSend(
  PendingFileAttachment attachment, {
  required bool removeMetadata,
}) async {
  final mimeType = resolveAttachmentMimeType(attachment);
  if (!Mime.imageTypes.contains(mimeType) || !removeMetadata) {
    return attachment;
  }

  // Do this before `compute`: otherwise an oversized in-memory attachment is
  // copied to the isolate before it can be rejected. Path-backed attachments
  // without a known length also fail closed to the documented original-file
  // fallback rather than being read without a bound.
  final dataLength = attachment.data?.lengthInBytes;
  final declaredSize = attachment.size;
  if ((dataLength == null && declaredSize == null) ||
      (dataLength != null && dataLength >= maxPhotoMetadataPreparationBytes) ||
      (declaredSize != null &&
          declaredSize >= maxPhotoMetadataPreparationBytes)) {
    return attachment;
  }

  try {
    return await compute(_removePhotoMetadata, attachment);
  } catch (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content:
          'photo_metadata event=preparation_failed result=error '
          'reason=compute_failed fallback=original',
      category: LogCategory.media,
      source: 'photo-metadata',
    );
    return attachment;
  }
}

Future<PendingFileAttachment> _removePhotoMetadata(
  PendingFileAttachment attachment,
) async {
  try {
    final filePath = attachment.path;
    final data =
        attachment.data ??
        (filePath == null
            ? null
            : await readLocalFileBytesWithinLimit(
                filePath,
                maxBytes: maxPhotoMetadataPreparationBytes,
              ));
    if (data == null ||
        data.lengthInBytes >= maxPhotoMetadataPreparationBytes) {
      return attachment;
    }

    // A path-backed attachment has no bytes until this point, so resolve its
    // actual file signature after the bounded read rather than trusting the
    // picker-provided name or type.
    final mimeType = resolveAttachmentMimeType(attachment, data: data);

    if (mimeType == 'image/gif') {
      final processedData = _stripGifMetadata(data);
      if (processedData == null) {
        return attachment;
      }

      return _carryingSendMetadata(
        PendingFileAttachment(
          // The sanitized bytes remain GIF data even when a source picker gave
          // them a misleading extension. Keep the filename, MIME type, and
          // payload aligned for Matrix clients and downloaded attachments.
          name: path.setExtension(attachment.name ?? 'untitled', '.gif'),
          data: processedData,
          size: processedData.lengthInBytes,
          mimeType: mimeType,
          spoiler: attachment.spoiler,
        ),
        attachment,
        // A comment/application-extension strip touches neither the frame
        // grid nor the frame delays, so both still describe these bytes.
        dimensions: attachment.dimensions,
        length: attachment.length,
      );
    }

    if (mimeType == 'image/webp') {
      final processedData = _stripWebpMetadata(data);
      if (processedData == null) {
        return attachment;
      }

      return _carryingSendMetadata(
        PendingFileAttachment(
          name: path.setExtension(attachment.name ?? 'untitled', '.webp'),
          data: processedData,
          size: processedData.lengthInBytes,
          mimeType: mimeType,
          spoiler: attachment.spoiler,
        ),
        attachment,
        // Chunk removal only; the VP8/VP8L payload and ANIM timing are the
        // source's, so its dimensions and duration still hold.
        dimensions: attachment.dimensions,
        length: attachment.length,
      );
    }

    final decoder = img.findDecoderForData(data);
    final info = decoder?.startDecode(data);
    if (info == null ||
        _exceedsPhotoMetadataPixelLimit(info.width, info.height) ||
        info.numFrames > 1) {
      return attachment;
    }

    final decodedImage = decoder?.decodeFrame(0);
    if (decodedImage == null || decodedImage.hasAnimation) {
      return attachment;
    }

    var image = decodedImage;
    image = img.bakeOrientation(image);
    image.exif.clear();
    image.textData = null;
    image.iccProfile = null;

    final Uint8List processedData;
    final String name;
    switch (mimeType) {
      case 'image/jpeg':
        // Make the intentional re-encode quality explicit. The image package
        // currently defaults to 100, but that is not a durable privacy-path
        // contract. Preserve the resolved JPEG type rather than an incorrect
        // filename extension supplied by a picker.
        processedData = img.encodeJpg(image, quality: 100);
        name = _photoNameWithExtension(attachment.name, '.jpg');
      case 'image/png':
        processedData = img.encodePng(image);
        name = _photoNameWithExtension(attachment.name, '.png');
      default:
        // Only the formats with a deliberate, type-preserving encoder are
        // compatible with this decode/re-encode path. Retain all others.
        return attachment;
    }

    return _carryingSendMetadata(
      PendingFileAttachment(
        name: name,
        data: processedData,
        size: processedData.lengthInBytes,
        mimeType: mimeType,
        spoiler: attachment.spoiler,
      ),
      attachment,
      // Measured off the BAKED image, not copied from the source. This path
      // applies `bakeOrientation`, which transposes width and height for the
      // quarter-turn EXIF orientations - the source's own dimensions would be
      // the pre-rotation ones and would arrive at the recipient sideways.
      dimensions: Size(image.width.toDouble(), image.height.toDouble()),
      // Single frame: `numFrames > 1` returned above, so there is no duration.
      length: null,
    );
  } catch (_) {
    return attachment;
  }
}

/// Copies the send-path metadata that survives sanitization onto [rebuilt].
///
/// [preparePhotoAttachmentForSend] returns a NEW [PendingFileAttachment], and
/// the fields below are settable rather than constructor arguments, so every
/// rebuild silently dropped them. Downstream send and preview code reads
/// `dimensions` to lay a bubble out before the image decodes; losing it makes
/// the timeline reflow on arrival.
///
/// Two fields are deliberately NOT carried:
///
/// * `path` - it addresses the file on disk, which still holds the metadata
///   that was just removed. `SystemFileProvider` reads through it, so carrying
///   it forward would hand the unsanitized original to the send path and undo
///   the whole operation.
/// * `thumbnailFile`/`thumbnailMime` - a separately encoded image derived from
///   the original, carrying its own EXIF. Sanitizing the main payload while
///   uploading an unsanitized thumbnail alongside it leaks exactly what the
///   caller asked to strip. They are dropped so the send path regenerates
///   them from the sanitized bytes.
PendingFileAttachment _carryingSendMetadata(
  PendingFileAttachment rebuilt,
  PendingFileAttachment source, {
  required Size? dimensions,
  required Duration? length,
}) {
  rebuilt.dimensions = dimensions;
  rebuilt.length = length;
  return rebuilt;
}

String _photoNameWithExtension(String? originalName, String requiredExtension) {
  final name = originalName ?? 'untitled';
  final extension = path.extension(name).toLowerCase();
  if (requiredExtension == '.jpg' &&
      (extension == '.jpg' || extension == '.jpeg')) {
    return name;
  }
  if (extension == requiredExtension) {
    return name;
  }
  return path.setExtension(name, requiredExtension);
}

/// Removes GIF comment and non-loop application extensions while retaining the
/// original image data, frame control, palettes, and animation loop metadata.
/// A malformed or metadata-free GIF returns null so its caller can preserve the
/// selected attachment unchanged.
Uint8List? _stripGifMetadata(Uint8List data) {
  final input = _GifInput(data);
  final output = BytesBuilder(copy: false);
  var removedMetadata = false;

  try {
    final header = input.read(6);
    final signature = String.fromCharCodes(header);
    if (header.length != 6 ||
        (signature != 'GIF87a' && signature != 'GIF89a')) {
      return null;
    }
    output.add(header);

    final logicalScreenDescriptor = input.read(7);
    output.add(logicalScreenDescriptor);
    if ((logicalScreenDescriptor[4] & 0x80) != 0) {
      output.add(input.read(_gifColorTableSize(logicalScreenDescriptor[4])));
    }

    while (true) {
      final blockStart = input.offset;
      switch (input.readByte()) {
        case 0x3b:
          output.addByte(0x3b);
          return input.atEnd && removedMetadata ? output.takeBytes() : null;
        case 0x2c:
          final descriptor = input.read(9);
          if ((descriptor[8] & 0x80) != 0) {
            input.skip(_gifColorTableSize(descriptor[8]));
          }
          input.readByte(); // LZW minimum code size.
          input.skipSubBlocks();
          output.add(data.sublist(blockStart, input.offset));
          continue;
        case 0x21:
          final label = input.readByte();
          final applicationHeader = input.readSubBlocksHeader();
          // GIF89a fixes the application extension's block size at 11. A
          // shorter one is a malformed file, not an unrecognised application:
          // the sub-block walk past it is no longer known to be aligned, so a
          // "sanitized" result built from here could be a corrupt GIF. Fail
          // closed to the documented fallback - preserve the original - rather
          // than dropping the block and returning a file we cannot vouch for.
          // Previously this fell through to the loop-extension check, which
          // rejects any header that is not exactly NETSCAPE2.0 or
          // ANIMEXTS1.0, so a short header was silently REMOVED and the GIF
          // was re-emitted as sanitized.
          if (label == 0xff && applicationHeader.length != 11) {
            return null;
          }
          if (applicationHeader.isNotEmpty) {
            input.skipSubBlocks();
          }
          final extension = data.sublist(blockStart, input.offset);

          if (label == 0xfe) {
            removedMetadata = true;
          } else if (label == 0xff) {
            final loopExtension = _sanitizeGifLoopExtension(
              extension,
              applicationHeader,
            );
            if (loopExtension == null) {
              removedMetadata = true;
            } else {
              // A loop extension has one defined three-byte payload. Preserve
              // that payload but strip any later sub-blocks: they are not part
              // of the loop contract and can carry the metadata this setting
              // promises to remove.
              if (loopExtension.length != extension.length) {
                removedMetadata = true;
              }
              output.add(loopExtension);
            }
          } else {
            output.add(extension);
          }
          continue;
        default:
          return null;
      }
    }
  } on FormatException {
    return null;
  }
}

bool _exceedsPhotoMetadataPixelLimit(int width, int height) {
  return width <= 0 ||
      height <= 0 ||
      width > maxPhotoMetadataPreparationPixels ~/ height;
}

/// Removes WebP ICC, EXIF, and XMP chunks without decoding or re-encoding
/// animation frames. Malformed, metadata-free, and non-extended WebP inputs
/// return null so callers preserve the original attachment unchanged.
Uint8List? _stripWebpMetadata(Uint8List data) {
  if (data.length < 12 ||
      String.fromCharCodes(data.sublist(0, 4)) != 'RIFF' ||
      String.fromCharCodes(data.sublist(8, 12)) != 'WEBP' ||
      _readLittleEndianUint32(data, 4) != data.length - 8) {
    return null;
  }

  final output = <int>[...data.sublist(0, 12)];
  var offset = 12;
  var removedMetadataFlags = 0;
  int? vp8xFlagsOffset;

  while (offset < data.length) {
    if (offset + 8 > data.length) {
      return null;
    }

    final chunkSize = _readLittleEndianUint32(data, offset + 4);
    final payloadEnd = offset + 8 + chunkSize;
    final chunkEnd = payloadEnd + (chunkSize.isOdd ? 1 : 0);
    if (payloadEnd > data.length || chunkEnd > data.length) {
      return null;
    }

    final chunkName = String.fromCharCodes(data.sublist(offset, offset + 4));
    final metadataFlag = switch (chunkName) {
      'ICCP' => 0x20,
      'EXIF' => 0x08,
      'XMP ' => 0x04,
      _ => 0,
    };
    if (metadataFlag != 0) {
      removedMetadataFlags |= metadataFlag;
      offset = chunkEnd;
      continue;
    }

    if (chunkName == 'VP8X') {
      if (chunkSize != 10 || vp8xFlagsOffset != null) {
        return null;
      }
      vp8xFlagsOffset = output.length + 8;
    }

    output.addAll(data.sublist(offset, chunkEnd));
    offset = chunkEnd;
  }

  // Metadata chunks require the extended container. Refuse malformed input
  // instead of emitting a container whose feature flags cannot be corrected.
  if (removedMetadataFlags == 0 || vp8xFlagsOffset == null) {
    return null;
  }

  output[vp8xFlagsOffset] &= ~removedMetadataFlags;
  _writeLittleEndianUint32(output, 4, output.length - 8);
  return Uint8List.fromList(output);
}

int _readLittleEndianUint32(Uint8List data, int offset) {
  return data[offset] |
      (data[offset + 1] << 8) |
      (data[offset + 2] << 16) |
      (data[offset + 3] << 24);
}

void _writeLittleEndianUint32(List<int> data, int offset, int value) {
  data[offset] = value & 0xff;
  data[offset + 1] = (value >> 8) & 0xff;
  data[offset + 2] = (value >> 16) & 0xff;
  data[offset + 3] = (value >> 24) & 0xff;
}

bool _isGifLoopApplication(Uint8List header) {
  final identifier = String.fromCharCodes(header);
  return identifier == 'NETSCAPE2.0' || identifier == 'ANIMEXTS1.0';
}

/// Returns the standard GIF loop extension, excluding any extra application
/// sub-blocks after its one defined loop payload.
Uint8List? _sanitizeGifLoopExtension(
  Uint8List extension,
  Uint8List applicationHeader,
) {
  const loopPayloadOffset = 14;
  if (!_isGifLoopApplication(applicationHeader) ||
      extension.length < loopPayloadOffset + 4 ||
      extension[0] != 0x21 ||
      extension[1] != 0xff ||
      extension[2] != 0x0b ||
      extension[loopPayloadOffset] != 0x03 ||
      extension[loopPayloadOffset + 1] != 0x01) {
    return null;
  }

  return Uint8List.fromList([
    ...extension.sublist(0, loopPayloadOffset + 4),
    0x00,
  ]);
}

int _gifColorTableSize(int packed) => 3 * (1 << ((packed & 0x07) + 1));

class _GifInput {
  _GifInput(this.data);

  final Uint8List data;
  int offset = 0;

  bool get atEnd => offset == data.length;

  int readByte() {
    if (offset >= data.length) {
      throw const FormatException('Unexpected end of GIF data');
    }
    return data[offset++];
  }

  Uint8List read(int length) {
    if (length < 0 || offset + length > data.length) {
      throw const FormatException('Unexpected end of GIF data');
    }
    final value = Uint8List.sublistView(data, offset, offset + length);
    offset += length;
    return value;
  }

  void skip(int length) {
    read(length);
  }

  Uint8List readSubBlocksHeader() {
    final length = readByte();
    return read(length);
  }

  void skipSubBlocks() {
    while (true) {
      final length = readByte();
      if (length == 0) {
        return;
      }
      skip(length);
    }
  }
}

class AttachmentProcessor extends StatefulWidget {
  const AttachmentProcessor({required this.attachment, super.key});
  final PendingFileAttachment attachment;

  @override
  State<AttachmentProcessor> createState() => _AttachmentProcessorState();
}

class _AttachmentProcessorState extends State<AttachmentProcessor> {
  String get promptAttachmentProcessingSendOriginal => Intl.message(
    'Send original file',
    name: 'promptAttachmentProcessingSendOriginal',
    desc:
        'Prompt text for the option to send a file in its original state, without any further processing such as removing metadata',
  );

  String get promptAttachmentProcessingSendOriginalDescription {
    if (Mime.videoTypes.contains(widget.attachment.mimeType)) {
      return Intl.message(
        'Off prepares video preview details before sending. On sends the selected video as-is and may skip generated preview details.',
        name: 'promptAttachmentProcessingSendOriginalVideoDescription',
        desc:
            'Help text explaining the Send original file option for video uploads',
      );
    }

    return Intl.message(
      'Off lets Inter Galactic prepare the upload before sending. On sends the selected file as-is.',
      name: 'promptAttachmentProcessingSendOriginalGenericDescription',
      desc:
          'Help text explaining the Send original file option for file uploads',
    );
  }

  String get promptAttachmentProcessingAddFile => Intl.message(
    'Add File',
    name: 'promptAttachmentProcessingAddFile',
    desc: 'Button text for confirming and adding a processed attachment',
  );

  late IconData icon;
  VideoPlayerController? videoController;

  bool canProcessData = false;
  bool sendOriginalFile = false;

  bool processing = false;

  FocusNode focusNode = FocusNode();

  @override
  void initState() {
    icon = Mime.toIcon(widget.attachment.mimeType);
    if (Mime.videoTypes.contains(widget.attachment.mimeType)) {
      videoController = VideoPlayerController();
      canProcessData = true;
    }
    super.initState();
  }

  @override
  void dispose() {
    final controller = videoController;
    if (controller != null) {
      unawaited(controller.dispose());
    }
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Cap the sheet to the viewport so the scroll region below is always
    // bounded, even if the host bottom sheet hands down an unbounded height.
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.85;

    return ScaledSafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxSheetHeight),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: processing ? 0.5 : 1,
              child: IgnorePointer(
                ignoring: processing,
                child: KeyboardListener(
                  focusNode: focusNode,
                  autofocus: true,
                  onKeyEvent: (value) {
                    if (processing) return;

                    if (value.logicalKey == LogicalKeyboardKey.enter) {
                      submit();
                    }
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // The preview and video-processing controls scroll; a tall
                      // preview or the longer copy can no
                      // longer push the confirm button off the sheet or under
                      // the Android navigation bar.
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.attachment.name != null)
                                Row(
                                  children: [
                                    Icon(icon),
                                    Flexible(
                                      child: tiamat.Text.labelLow(
                                        widget.attachment.name!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxHeight: 500,
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: FilePreview(
                                      mimeType: widget.attachment.mimeType,
                                      path: widget.attachment.path,
                                      data: widget.attachment.data,
                                      videoController: videoController,
                                    ),
                                  ),
                                ),
                              ),
                              if (canProcessData)
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: buildFileProcessingSwitch(),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Pinned so it is always reachable regardless of content
                      // height.
                      buildConfirmButton(),
                    ],
                  ),
                ),
              ),
            ),
            if (processing) const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }

  Widget buildFileProcessingSwitch() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: tiamat.Text.label(promptAttachmentProcessingSendOriginal),
            ),
            tiamat.Switch(
              state: sendOriginalFile,
              onChanged: (value) => setState(() {
                sendOriginalFile = value;
              }),
            ),
          ],
        ),
        const SizedBox(height: 4),
        tiamat.Text.labelLow(promptAttachmentProcessingSendOriginalDescription),
      ],
    );
  }

  Widget buildConfirmButton() {
    return tiamat.Button(
      text: promptAttachmentProcessingAddFile,
      onTap: submit,
    );
  }

  void submit() async {
    if (canProcessData == false || sendOriginalFile) {
      Navigator.of(context).pop(widget.attachment);
    } else {
      setState(() {
        processing = true;
      });
      var file = await processFile();
      if (mounted) {
        Navigator.of(context).pop(file);
      }
    }
  }

  Future<PendingFileAttachment> processFile() async {
    if (Mime.videoTypes.contains(widget.attachment.mimeType)) {
      return processVideo();
    }

    return widget.attachment;
  }

  Future<PendingFileAttachment> processVideo() async {
    var file = widget.attachment;

    if (videoController != null) {
      file.thumbnailFile = await videoController!.screenshot();
      if (file.thumbnailFile != null) {
        file.thumbnailMime = Mime.lookupType('', data: file.thumbnailFile);
      }
    }

    file.length = await videoController!.getLength();
    file.dimensions = await videoController!.getSize();

    return file;
  }
}
