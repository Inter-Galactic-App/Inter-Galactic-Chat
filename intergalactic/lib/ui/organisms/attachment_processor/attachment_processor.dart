import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/ui/atoms/scaled_safe_area.dart';
import 'package:intergalactic/ui/molecules/file_preview.dart';
import 'package:intergalactic/ui/molecules/video_player/video_player_controller.dart';
import 'package:intergalactic/utils/local_file.dart';
import 'package:intergalactic/utils/mime.dart';
import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:image/image.dart' as img;
import 'package:tiamat/tiamat.dart' as tiamat;

class AttachmentProcessor extends StatefulWidget {
  const AttachmentProcessor({required this.attachment, super.key});
  final PendingFileAttachment attachment;

  @override
  State<AttachmentProcessor> createState() => _AttachmentProcessorState();
}

class _AttachmentProcessorState extends State<AttachmentProcessor> {
  String get promptAttachmentProcessingSendOriginal => Intl.message(
      'Send Original',
      name: 'promptAttachmentProcessingSendOriginal',
      desc:
          'Prompt text for the option to send a file in its original state, without any further processing such as removing metadata');

  String get promptAttachmentProcessingSpoiler => Intl.message(
      'Mark as spoiler',
      name: 'promptAttachmentProcessingSpoiler',
      desc:
          'Prompt text for the option to hide an attached image behind a spoiler reveal');

  String get labelImageContainsLocationInfo => Intl.message(
      'Warning: This image contains location metadata',
      name: 'labelImageContainsLocationInfo',
      desc:
          'Prompt text for the option to send a file in its original state, without any further processing such as removing metadata');

  Map<String, IfdTag>? exifData;
  late IconData icon;
  VideoPlayerController? videoController;

  bool canProcessData = false;
  bool containsGpsData = false;
  bool sendOriginalFile = false;
  bool spoilerAttachment = false;

  bool processing = false;

  FocusNode focusNode = FocusNode();

  @override
  void initState() {
    icon = Mime.toIcon(widget.attachment.mimeType);
    if (Mime.imageTypes.contains(widget.attachment.mimeType)) {
      loadExif();
      canProcessData = true;

      if (widget.attachment.mimeType == 'image/gif') {
        canProcessData = false;
      }
    } else if (Mime.videoTypes.contains(widget.attachment.mimeType)) {
      videoController = VideoPlayerController();
      canProcessData = true;
    }
    super.initState();
  }

  @override
  void dispose() {
    videoController?.pause();
    super.dispose();
  }

  void loadExif() async {
    Map<String, IfdTag> data;
    if (widget.attachment.data != null) {
      data = await readExifFromBytes(widget.attachment.data!);
    } else {
      final bytes = await readLocalFileBytes(widget.attachment.path!);
      data = bytes == null ? {} : await readExifFromBytes(bytes);
    }

    setState(() {
      if (data.keys.any((e) => e.toLowerCase().contains('gps'))) {
        containsGpsData = true;
      }

      exifData = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ScaledSafeArea(
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
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: ConstrainedBox(
                          constraints:
                              BoxConstraints.loose(const Size(500, 500)),
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
                    ),
                    if (canProcessData)
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: buildFileProcessingSwitch(),
                      ),
                    if (canMarkSpoiler)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        child: buildSpoilerSwitch(),
                      ),
                    if (sendOriginalFile || !canProcessData)
                      buildMetadataDisplay(),
                    buildConfirmButton(),
                  ],
                ),
              ),
            ),
          ),
          if (processing) const CircularProgressIndicator()
        ],
      ),
    );
  }

  Widget buildFileProcessingSwitch() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        tiamat.Text.label(promptAttachmentProcessingSendOriginal),
        tiamat.Switch(
          state: sendOriginalFile,
          onChanged: (value) => setState(() {
            sendOriginalFile = value;
          }),
        ),
      ],
    );
  }

  bool get canMarkSpoiler =>
      Mime.imageTypes.contains(widget.attachment.mimeType);

  Widget buildSpoilerSwitch() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        tiamat.Text.label(promptAttachmentProcessingSpoiler),
        tiamat.Switch(
          state: spoilerAttachment,
          onChanged: (value) => setState(() {
            spoilerAttachment = value;
          }),
        ),
      ],
    );
  }

  Widget buildMetadataDisplay() {
    return Column(
      children: [
        if (containsGpsData) tiamat.Text.error(labelImageContainsLocationInfo)
      ],
    );
  }

  Widget buildConfirmButton() {
    return tiamat.Button(
      text: 'Add File',
      onTap: submit,
    );
  }

  void submit() async {
    widget.attachment.spoiler = spoilerAttachment;
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
    late PendingFileAttachment processedFile;

    if (Mime.imageTypes.contains(widget.attachment.mimeType)) {
      processedFile = await processImage();
    } else if (Mime.videoTypes.contains(widget.attachment.mimeType)) {
      processedFile = await processVideo();
    }

    return processedFile;
  }

  Future<PendingFileAttachment> processImage() async {
    return await compute((PendingFileAttachment attachment) async {
      var data = attachment.data ?? await readLocalFileBytes(attachment.path!);

      var decoder = img.findDecoderForData(data!);
      var image = decoder!.decode(data)!;

      image.exif.clear();

      Uint8List? processedData;
      String? name = attachment.name;
      String mime = attachment.mimeType!;
      if (attachment.name != null) {
        processedData = img.encodeNamedImage(attachment.name!, image);
      }

      if (processedData == null) {
        processedData = img.encodePng(image);
        mime = 'image/png';
        var fileName = attachment.name ?? 'untitled.png';
        var rawName = path.basenameWithoutExtension(fileName);
        name = '$rawName.png';
      }

      return PendingFileAttachment(
          name: name,
          data: processedData,
          size: processedData.lengthInBytes,
          mimeType: mime,
          spoiler: attachment.spoiler);
    }, widget.attachment);
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
