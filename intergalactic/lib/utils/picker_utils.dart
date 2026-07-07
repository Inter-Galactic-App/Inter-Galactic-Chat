import 'dart:typed_data';
import 'dart:ui';

import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:intergalactic/utils/image_utils.dart';
import 'package:crop_image/crop_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class PickerUtils {
  static Future<PickerResult?> pickImage() async {
    if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
      var picker = ImagePicker();
      final result = await picker.pickImage(source: ImageSource.gallery);
      if (result != null) {
        return PickerResultXFile(result);
      }
    } else {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['bmp', 'gif', 'jpg', 'jpeg', 'png', 'webp', 'apng'],
      );

      var file = result?.xFiles.firstOrNull;
      if (file != null) {
        return PickerResultXFile(file);
      }
    }

    return null;
  }

  static Future<Uint8List?> pickImageAndCrop(
    BuildContext context, {
    double? aspectRatio,
  }) async {
    var image = await pickImage();
    if (image == null) return null;

    var bytes = await image.readAsBytes();

    final controller = CropController(
      aspectRatio: aspectRatio,
      defaultCrop: Rect.fromLTRB(0.05, 0.05, 0.95, 0.95),
    );

    var imageProvider = Image.memory(bytes).image;

    var uiImage = await ImageUtils.imageProviderToImage(imageProvider);
    var ratio = uiImage.width.toDouble() / uiImage.height.toDouble();

    var result = await tiamat.PopupDialog.show<Uint8List>(
      context,
      content: ImageCropView(
        bytes,
        controller,
        ratio,
        onImageSubmitted: (data) => Navigator.of(context).pop(data),
      ),
    );

    return result;
  }
}

class ImageCropView extends StatefulWidget {
  const ImageCropView(
    this.imageBytes,
    this.controller,
    this.imageAspectRatio, {
    this.onImageSubmitted,
    super.key,
  });

  final CropController controller;
  final Uint8List imageBytes;

  final double imageAspectRatio;

  final Function(Uint8List data)? onImageSubmitted;

  final double width = 1000;

  @override
  State<ImageCropView> createState() => _ImageCropViewState();
}

class _ImageCropViewState extends State<ImageCropView> {
  bool _submitting = false;

  String get useWithoutCroppingPrompt => Intl.message(
    "Use Without Cropping",
    name: "useWithoutCroppingPrompt",
    desc: "Button text for using an image without cropping it",
  );

  Future<void> _submitOriginal() async {
    if (_submitting) {
      return;
    }
    setState(() => _submitting = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }
    widget.onImageSubmitted?.call(widget.imageBytes);
  }

  Future<void> _submitCrop() async {
    if (_submitting) {
      return;
    }
    setState(() => _submitting = true);
    await WidgetsBinding.instance.endOfFrame;
    try {
      var image = await widget.controller.croppedBitmap();

      var data = await image.toByteData(format: ImageByteFormat.png);
      if (data == null || !mounted) return;

      var bytes = Uint8List.sublistView(data);
      widget.onImageSubmitted?.call(bytes);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    var buttons = [
      Expanded(
        flex: Layout.desktop ? 1 : 0,
        child: tiamat.Button.secondary(
          text: useWithoutCroppingPrompt,
          isLoading: _submitting,
          onTap: _submitOriginal,
        ),
      ),
      Expanded(
        flex: Layout.desktop ? 1 : 0,
        child: tiamat.Button(
          text: CommonStrings.promptSubmit,
          isLoading: _submitting,
          onTap: _submitCrop,
        ),
      ),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SizedBox(
            width: 1000,
            child: AspectRatio(
              aspectRatio: widget.imageAspectRatio,
              child: Container(
                child: CropImage(
                  image: Image.memory(widget.imageBytes),
                  controller: widget.controller,
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: 20),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  SizedBox(
                    height: 50,
                    width: 50,
                    child: tiamat.IconButton(
                      icon: Icons.rotate_90_degrees_ccw,
                      onPressed: _submitting
                          ? null
                          : () => widget.controller.rotateLeft(),
                      size: 30,
                    ),
                  ),
                  SizedBox(
                    height: 50,
                    width: 50,
                    child: tiamat.IconButton(
                      icon: Icons.rotate_90_degrees_cw,
                      size: 30,
                      onPressed: _submitting
                          ? null
                          : () => widget.controller.rotateRight(),
                    ),
                  ),
                ],
              ),
            ),
            if (Layout.desktop)
              Row(
                spacing: 8,
                mainAxisSize: MainAxisSize.max,
                children: buttons,
              ),
            if (Layout.mobile)
              Column(
                spacing: 8,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: buttons,
              ),
          ],
        ),
      ],
    );
  }
}

abstract class PickerResult {
  Future<Uint8List> readAsBytes();

  String get name;

  String? get mimeType;
}

class PickerResultXFile implements PickerResult {
  final XFile file;

  PickerResultXFile(this.file);

  @override
  Future<Uint8List> readAsBytes() {
    return file.readAsBytes();
  }

  @override
  String get name => file.name;

  @override
  String? get mimeType => file.mimeType;
}
