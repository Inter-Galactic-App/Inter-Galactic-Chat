import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/config/app_globals.dart' as app_globals;
import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/ui/organisms/attachment_processor/'
    'attachment_processor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('photo metadata removal defaults on and persists', () async {
    SharedPreferences.setMockInitialValues({});

    final preferences = Preferences();
    await preferences.init();

    expect(preferences.removePhotoMetadataBeforeSending.value, isTrue);

    await preferences.removePhotoMetadataBeforeSending.set(false);

    final reloadedPreferences = Preferences();
    await reloadedPreferences.init();

    expect(reloadedPreferences.removePhotoMetadataBeforeSending.value, isFalse);
  });

  testWidgets('composer preparation honors disabled photo metadata removal', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await app_globals.preferences.init();
    await app_globals.preferences.removePhotoMetadataBeforeSending.set(false);
    addTearDown(
      () => app_globals.preferences.removePhotoMetadataBeforeSending.set(true),
    );

    final source = PendingFileAttachment(
      name: 'photo.jpg',
      mimeType: 'image/jpeg',
      data: Uint8List.fromList([0xff, 0xd8, 0xff]),
    );
    late BuildContext context;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (buildContext) {
            context = buildContext;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final prepared = await prepareAttachmentForComposer(context, source);

    expect(prepared, same(source));
  });

  testWidgets(
    'composer preparation uses the default metadata removal setting',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await app_globals.preferences.init();

      final source = PendingFileAttachment(
        name: 'photo.jpg',
        mimeType: 'image/jpeg',
        data: _photoWithExifOrientation(),
      );
      final sourceImage = img.bakeOrientation(
        img.findDecoderForData(source.data!)!.decode(source.data!)!,
      );
      late BuildContext context;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (buildContext) {
              context = buildContext;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final prepared = await tester.runAsync(
        () => prepareAttachmentForComposer(context, source),
      );
      final decoded = img
          .findDecoderForData(prepared!.data!)!
          .decode(prepared.data!)!;

      expect(prepared, isNot(same(source)));
      expect(_hasOrientationSixExifApp1(source.data!), isTrue);
      expect(sourceImage.width, 1);
      expect(sourceImage.height, 2);
      expect(_hasOrientationSixExifApp1(prepared.data!), isFalse);
      expect(decoded.width, 1);
      expect(decoded.height, 2);
    },
  );

  test('composer identifies a path-backed photo from its header', () async {
    final directory = await Directory.systemTemp.createTemp('photo-header-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}photo.txt');
    final data = _photoWithExifOrientation();
    await file.writeAsBytes(data);
    final source = PendingFileAttachment(
      name: 'photo.txt',
      path: file.path,
      size: data.lengthInBytes,
    );

    final mimeType = await resolveAttachmentMimeTypeForComposer(source);

    expect(mimeType, 'image/jpeg');
    expect(source.mimeType, 'image/jpeg');
    expect(source.data, isNull);
  });
}

Uint8List _photoWithExifOrientation() {
  final image = img.Image(width: 2, height: 1, numChannels: 3)
    ..clear(img.ColorRgb8(20, 120, 230));
  final encoded = img.encodeJpg(image, quality: 95);

  // `encodeJpg` does not serialize image.exif, so add a minimal big-endian
  // APP1 EXIF block with Orientation=6 after the JPEG SOI marker.
  return Uint8List.fromList([
    ...encoded.take(2),
    ..._orientationSixExifApp1,
    ...encoded.skip(2),
  ]);
}

const _orientationSixExifApp1 = <int>[
  0xff,
  0xe1,
  0x00,
  0x22,
  0x45,
  0x78,
  0x69,
  0x66,
  0x00,
  0x00,
  0x4d,
  0x4d,
  0x00,
  0x2a,
  0x00,
  0x00,
  0x00,
  0x08,
  0x00,
  0x01,
  0x01,
  0x12,
  0x00,
  0x03,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x06,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
];

bool _hasOrientationSixExifApp1(Uint8List data) {
  if (data.length < 2 + _orientationSixExifApp1.length) {
    return false;
  }
  for (var index = 0; index < _orientationSixExifApp1.length; index++) {
    if (data[index + 2] != _orientationSixExifApp1[index]) {
      return false;
    }
  }
  return true;
}
