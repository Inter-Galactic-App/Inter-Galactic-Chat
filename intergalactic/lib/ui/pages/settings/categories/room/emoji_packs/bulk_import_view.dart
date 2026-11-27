import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:tiamat/atoms/panel.dart';

import 'package:path/path.dart' as p;
import 'package:tiamat/tiamat.dart' as tiamat;

/// File extensions accepted from a ZIP or a multi-file selection. Kept in sync
/// with what the emoticon pack can display (static + animated).
const _supportedImageExtensions = <String>{
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'apng',
};

const _maxArchiveEntries = 256;
const _maxImageBytes = 16 * 1024 * 1024;
const _maxTotalImportBytes = 64 * 1024 * 1024;
const _maxZipBytes = 32 * 1024 * 1024;
const _previewCacheSize = 256;

class _BulkImportLimitException implements Exception {
  const _BulkImportLimitException(this.message);

  final String message;
}

class _BoundedOutputStream extends OutputStreamBase {
  _BoundedOutputStream(this.maxBytes, this.limitMessage);

  final int maxBytes;
  final String limitMessage;
  final BytesBuilder _bytes = BytesBuilder();

  @override
  int length = 0;

  void _checkAdditionalBytes(int count) {
    if (count < 0 || length + count > maxBytes) {
      throw _BulkImportLimitException(limitMessage);
    }
  }

  @override
  void flush() {}

  @override
  void writeByte(int value) {
    _checkAdditionalBytes(1);
    _bytes.addByte(value);
    length++;
  }

  @override
  void writeBytes(List<int> bytes, [int? len]) {
    final count = len ?? bytes.length;
    _checkAdditionalBytes(count);
    _bytes.add(bytes.take(count).toList(growable: false));
    length += count;
  }

  @override
  void writeInputStream(InputStreamBase stream) {
    final count = stream.length;
    _checkAdditionalBytes(count);
    _bytes.add(stream.toUint8List());
    length += count;
  }

  @override
  void writeUint16(int value) {
    writeByte(value);
    writeByte(value >> 8);
  }

  @override
  void writeUint32(int value) {
    writeUint16(value);
    writeUint16(value >> 16);
  }

  @override
  void writeUint64(int value) {
    writeUint32(value);
    writeUint32(value >> 32);
  }

  Uint8List takeBytes() => _bytes.takeBytes();
}

@visibleForTesting
List<String> resolveBulkImportShortcodes(Iterable<String> names) {
  final originalNames = names.toList();
  final reserved = originalNames.toSet();
  final used = <String>{};
  final resolved = <String>[];

  for (final baseName in originalNames) {
    if (used.add(baseName)) {
      resolved.add(baseName);
      continue;
    }

    var suffix = 1;
    var candidate = '${baseName}_$suffix';
    while (reserved.contains(candidate) || used.contains(candidate)) {
      suffix++;
      candidate = '${baseName}_$suffix';
    }
    used.add(candidate);
    resolved.add(candidate);
  }

  return resolved;
}

class EmoticonBulkImportDialog extends StatefulWidget {
  const EmoticonBulkImportDialog({super.key, this.importPack});
  final Function(
    String name,
    int avatarIndex,
    List<String> names,
    List<Uint8List> imageDatas,
  )?
  importPack;

  @override
  State<EmoticonBulkImportDialog> createState() =>
      _EmoticonBulkImportDialogState();
}

class _EmoticonBulkImportDialogState extends State<EmoticonBulkImportDialog> {
  final TextEditingController _packNameEditor = TextEditingController();
  final TextEditingController _emotePrefixEditor = TextEditingController();
  final TextEditingController _overrideNameEditor = TextEditingController();

  List<String>? names;
  List<Uint8List?>? datas;
  List<ImageProvider?>? images;

  int? avatarIndex;

  String? prefix;
  String? overrideName;
  bool loading = false;
  String? errorText;

  bool useAsEmoji = false;
  bool useAsSticker = true;

  @override
  void initState() {
    _emotePrefixEditor.addListener(onPrefixChanged);
    _overrideNameEditor.addListener(onOverrideChanged);
    super.initState();
  }

  @override
  void dispose() {
    _packNameEditor.dispose();
    _emotePrefixEditor.dispose();
    _overrideNameEditor.dispose();
    super.dispose();
  }

  void onPrefixChanged() {
    setState(() {
      prefix = _emotePrefixEditor.text;
    });
  }

  void onOverrideChanged() {
    setState(() {
      overrideName = _overrideNameEditor.text;
    });
  }

  String getFinalName(int index) {
    String name = names![index];
    if (overrideName != null && overrideName!.isNotEmpty) {
      name = overrideName!;
    }

    if (prefix != null) {
      name = "$prefix$name";
    }

    if (overrideName != null && overrideName!.isNotEmpty) {
      name = "${name}_$index";
    }

    return name;
  }

  void _clearLoadedEntries() {
    avatarIndex = null;
    names = null;
    datas = null;
    images = null;
  }

  void reset() {
    _packNameEditor.text = "";
    _overrideNameEditor.text = "";
    _emotePrefixEditor.text = "";
    _clearLoadedEntries();
    errorText = null;
  }

  /// Turns a raw filename into a valid emote shortcode: strips the extension,
  /// lowercases, and replaces anything outside `[a-z0-9_]` with underscores.
  String _shortcodeFromFilename(String filename) {
    final base = p.basenameWithoutExtension(filename).toLowerCase();
    final sanitized = base
        .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return sanitized.isEmpty ? 'emote' : sanitized;
  }

  bool _isSupportedImageName(String name) {
    final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
    return _supportedImageExtensions.contains(ext);
  }

  String _fileLimitMessage(String name, int remainingTotalBytes) {
    if (remainingTotalBytes < _maxImageBytes) {
      return 'These images are too large together. Import at most 64 MB at once.';
    }
    return '$name is too large. Each image must be 16 MB or smaller.';
  }

  Future<Uint8List> _readPlatformFileBytes(
    PlatformFile file, {
    required int maxBytes,
    required String limitMessage,
  }) async {
    if (file.size > maxBytes) {
      throw _BulkImportLimitException(limitMessage);
    }
    final stream = file.readStream;
    if (stream == null) {
      throw const FormatException('File stream was unavailable.');
    }

    final bytes = BytesBuilder();
    var length = 0;
    await for (final chunk in stream) {
      length += chunk.length;
      if (length > maxBytes) {
        throw _BulkImportLimitException(limitMessage);
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  Uint8List _extractArchiveEntry(
    ArchiveFile entry, {
    required String name,
    required int remainingTotalBytes,
  }) {
    final maxBytes = remainingTotalBytes < _maxImageBytes
        ? remainingTotalBytes
        : _maxImageBytes;
    final limitMessage = _fileLimitMessage(name, remainingTotalBytes);
    if (maxBytes <= 0 || entry.size > maxBytes) {
      throw _BulkImportLimitException(limitMessage);
    }
    if (entry.compressionType != ArchiveFile.STORE &&
        entry.compressionType != ArchiveFile.DEFLATE) {
      throw const FormatException('Unsupported ZIP compression method.');
    }

    final output = _BoundedOutputStream(maxBytes, limitMessage);
    entry.clear();
    entry.decompress(output);
    final bytes = output.takeBytes();
    if (bytes.length != entry.size) {
      throw const FormatException('ZIP entry size did not match its metadata.');
    }
    return bytes;
  }

  Future<bool> _canDecodeImage(Uint8List bytes) async {
    ui.Codec? codec;
    ui.Image? decodedImage;
    try {
      codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: _previewCacheSize,
        targetHeight: _previewCacheSize,
        allowUpscaling: false,
      );
      final frame = await codec.getNextFrame();
      decodedImage = frame.image;
      return decodedImage.width > 0 && decodedImage.height > 0;
    } catch (_) {
      return false;
    } finally {
      decodedImage?.dispose();
      codec?.dispose();
    }
  }

  /// Populates the review grid from a list of (filename, bytes) entries and
  /// seeds a pack name. Shared by the ZIP and multi-file sources.
  Future<void> _loadEntries(
    List<({String name, Uint8List bytes})> entries, {
    String? packName,
  }) async {
    final validEntries = <({String name, Uint8List bytes})>[];
    for (final entry in entries) {
      if (await _canDecodeImage(entry.bytes)) {
        validEntries.add(entry);
      }
    }
    if (!mounted) {
      return;
    }

    setState(() {
      reset();
      if (validEntries.isEmpty) {
        loading = false;
        errorText =
            'No valid supported images were found. Add PNG, JPG, GIF, WebP, or APNG files.';
        return;
      }

      datas = validEntries.map((e) => e.bytes).toList();
      images = validEntries
          .map(
            (e) => ResizeImage(
              MemoryImage(e.bytes),
              width: _previewCacheSize,
              height: _previewCacheSize,
              policy: ResizeImagePolicy.fit,
            ),
          )
          .toList();
      names = resolveBulkImportShortcodes(
        validEntries.map((e) => _shortcodeFromFilename(e.name)).toList(),
      );
      avatarIndex = 0;
      if (packName != null && packName.trim().isNotEmpty) {
        _packNameEditor.text = packName.trim();
      }
      loading = false;
    });
  }

  Future<void> pickZip() async {
    setState(() {
      loading = true;
      errorText = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        withReadStream: true,
      );
      if (!mounted) {
        return;
      }
      if (result == null) {
        setState(() => loading = false);
        return;
      }

      final file = result.files.firstOrNull;
      if (file == null) {
        throw const FormatException('ZIP file was unavailable.');
      }
      final bytes = await _readPlatformFileBytes(
        file,
        maxBytes: _maxZipBytes,
        limitMessage:
            'This ZIP is too large. Choose an archive smaller than 32 MB.',
      );
      final archive = ZipDecoder().decodeBuffer(InputStream(bytes));
      if (archive.length > _maxArchiveEntries) {
        throw const _BulkImportLimitException(
          'This ZIP has too many entries. Import at most 256 files at once.',
        );
      }

      final entries = <({String name, Uint8List bytes})>[];
      var totalBytes = 0;
      for (final entry in archive) {
        if (!entry.isFile) {
          continue;
        }
        final entryName = entry.name;
        // Skip directories, macOS resource-fork junk, and hidden files.
        final baseName = p.basename(entryName);
        if (entryName.startsWith('__MACOSX/') ||
            baseName.startsWith('.') ||
            !_isSupportedImageName(baseName)) {
          continue;
        }

        final content = _extractArchiveEntry(
          entry,
          name: baseName,
          remainingTotalBytes: _maxTotalImportBytes - totalBytes,
        );
        if (content.isEmpty) {
          continue;
        }
        totalBytes += content.length;
        entries.add((name: baseName, bytes: content));
      }

      entries.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      await _loadEntries(
        entries,
        packName: p.basenameWithoutExtension(file.name),
      );
    } on _BulkImportLimitException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _clearLoadedEntries();
        loading = false;
        errorText = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _clearLoadedEntries();
        loading = false;
        errorText =
            'This ZIP could not be read. Make sure it is a valid archive of images.';
      });
    }
  }

  Future<void> pickFolder() async {
    setState(() {
      loading = true;
      errorText = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withReadStream: true,
        allowMultiple: true,
      );
      if (!mounted) {
        return;
      }
      if (result == null) {
        setState(() => loading = false);
        return;
      }
      if (result.files.length > _maxArchiveEntries) {
        throw const _BulkImportLimitException(
          'Too many files were selected. Import at most 256 images at once.',
        );
      }

      final entries = <({String name, Uint8List bytes})>[];
      var totalBytes = 0;
      for (final file in result.files) {
        if (!_isSupportedImageName(file.name)) {
          continue;
        }
        final remainingTotalBytes = _maxTotalImportBytes - totalBytes;
        final bytes = await _readPlatformFileBytes(
          file,
          maxBytes: remainingTotalBytes < _maxImageBytes
              ? remainingTotalBytes
              : _maxImageBytes,
          limitMessage: _fileLimitMessage(file.name, remainingTotalBytes),
        );
        if (bytes.isEmpty) {
          continue;
        }
        totalBytes += bytes.length;
        entries.add((name: file.name, bytes: bytes));
      }
      await _loadEntries(entries);
    } on _BulkImportLimitException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _clearLoadedEntries();
        loading = false;
        errorText = error.message;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _clearLoadedEntries();
        loading = false;
        errorText = 'These files could not be loaded.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    bool loadingFinished = images?.any((element) => element == null) == false;
    return ConstrainedBox(
      constraints: const BoxConstraints.expand(width: 800, height: 800),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.max,
        children: [
          sourceSelection(),
          if (loading)
            const Expanded(child: Center(child: CircularProgressIndicator())),
          if (loading == false && names != null)
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: MasonryGridView.extent(
                    itemCount: names!.length,
                    maxCrossAxisExtent: 200,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    itemBuilder: entryBuilder,
                  ),
                ),
              ),
            ),
          if (loading == false && names != null) packEdit(),
          if (images != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
              child: tiamat.Button(
                isLoading: !loadingFinished,
                text: "Import ${names!.length} Emoticons!",
                onTap: () {
                  if (canCreatePack()) {
                    var finalNames = names!
                        .mapIndexed((_, index) => getFinalName(index))
                        .toList();
                    widget.importPack?.call(
                      _packNameEditor.text,
                      avatarIndex!,
                      finalNames,
                      datas!.map((e) => e!).toList(),
                    );
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  bool canCreatePack() {
    return _packNameEditor.text.isNotEmpty;
  }

  Widget packEdit() {
    return Panel(
      mode: tiamat.TileType.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: avatarIndex != null && images?[avatarIndex!] != null
                  ? tiamat.Avatar(image: images![avatarIndex!], radius: 50)
                  : const Center(child: CircularProgressIndicator()),
            ),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tiamat.TextInput(
                    controller: _packNameEditor,
                    label: "Pack Name",
                    maxLines: 1,
                  ),
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: tiamat.Text.labelLow("Optional:"),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: tiamat.TextInput(
                          controller: _emotePrefixEditor,
                          label: "Prefix",
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: tiamat.TextInput(
                          controller: _overrideNameEditor,
                          label: "Override Name",
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget sourceSelection() {
    return Panel(
      header: "Select pack source",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: tiamat.Text.labelLow(
              "Import a .zip of images, or pick images directly. Supported: "
              "PNG, JPG, GIF, WebP, APNG. Each file name becomes an emote "
              "shortcode.",
            ),
          ),
          tiamat.Button(
            text: "Import from ZIP",
            onTap: loading ? null : pickZip,
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 100,
                  height: 10,
                  child: tiamat.Seperator(),
                ),
                tiamat.Text.labelLow(CommonStrings.labelOr),
                const SizedBox(
                  width: 100,
                  height: 10,
                  child: tiamat.Seperator(),
                ),
              ],
            ),
          ),
          tiamat.Button.secondary(
            text: "Select Images",
            onTap: loading ? null : pickFolder,
          ),
          if (errorText != null) ...[
            const SizedBox(height: 8),
            tiamat.Text.error(errorText!),
          ],
        ],
      ),
    );
  }

  Widget entryBuilder(BuildContext context, int index) {
    var background = index % 2 == 0
        ? Theme.of(context).colorScheme.surfaceContainerLow
        : Theme.of(context).colorScheme.surfaceContainerHigh;

    var loading = images?[index] != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 150, minWidth: 150),
          child: loading
              ? Column(
                  children: [
                    Image(
                      filterQuality: FilterQuality.medium,
                      fit: BoxFit.fill,
                      image: images![index]!,
                    ),
                    tiamat.Text.tiny(getFinalName(index)),
                  ],
                )
              : const SizedBox(
                  width: 15,
                  height: 15,
                  child: Center(child: CircularProgressIndicator()),
                ),
        ),
      ),
    );
  }
}
