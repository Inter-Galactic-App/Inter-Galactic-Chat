import 'dart:ui' show Size;
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/ui/organisms/attachment_processor/attachment_processor.dart';

void main() {
  test(
    'photo preparation strips metadata when the privacy setting is enabled',
    () async {
      final source = PendingFileAttachment(
        name: 'photo.jpg',
        mimeType: 'image/jpeg',
        data: _photoWithExifOrientation(),
        spoiler: true,
      );
      final sourceImage = img.bakeOrientation(
        img.findDecoderForData(source.data!)!.decode(source.data!)!,
      );

      final prepared = await preparePhotoAttachmentForSend(
        source,
        removeMetadata: true,
      );
      final decoded = img
          .findDecoderForData(prepared.data!)!
          .decode(prepared.data!)!;

      expect(prepared, isNot(same(source)));
      expect(_containsBytes(source.data!, _orientationSixExifApp1), isTrue);
      expect(sourceImage.width, 1);
      expect(sourceImage.height, 2);
      expect(_containsBytes(prepared.data!, _orientationSixExifApp1), isFalse);
      expect(decoded.width, 1);
      expect(decoded.height, 2);
      // Orientation=6 rotates the original left-to-right pixels clockwise.
      // Distinct source values make this assert the actual pixel direction,
      // rather than only the rotated dimensions.
      expect(decoded.getPixel(0, 0).r, lessThan(32));
      expect(decoded.getPixel(0, 1).r, greaterThan(223));
      expect(prepared.mimeType, 'image/jpeg');
      expect(prepared.name, source.name);
      expect(prepared.spoiler, isTrue);
      expect(prepared.size, prepared.data!.lengthInBytes);
    },
  );

  test('photo preparation preserves the selected file when disabled', () async {
    final source = PendingFileAttachment(
      name: 'photo.jpg',
      mimeType: 'image/jpeg',
      data: _photoWithExifOrientation(),
    );

    final prepared = await preparePhotoAttachmentForSend(
      source,
      removeMetadata: false,
    );

    expect(prepared, same(source));
  });

  test('photo detection normalizes a supplied MIME type', () {
    final source = PendingFileAttachment(
      name: 'photo.jpg',
      mimeType: ' IMAGE/JPG ',
      data: Uint8List(1),
    );

    expect(resolveAttachmentMimeType(source), 'image/jpeg');
    expect(isPhotoAttachment(source), isTrue);
  });

  test('photo detection resolves a generic supplied MIME type from bytes', () {
    final source = PendingFileAttachment(
      name: 'dropped-file',
      mimeType: 'application/octet-stream',
      data: _photoWithExifOrientation(),
    );

    expect(resolveAttachmentMimeType(source), 'image/jpeg');
    expect(isPhotoAttachment(source), isTrue);
  });

  test(
    'photo preparation resolves a missing JPEG MIME type from bytes',
    () async {
      final source = PendingFileAttachment(
        name: 'dropped-file',
        data: _photoWithExifOrientation(),
      )..mimeType = null;

      expect(resolveAttachmentMimeType(source), 'image/jpeg');
      expect(isPhotoAttachment(source), isTrue);

      final prepared = await preparePhotoAttachmentForSend(
        source,
        removeMetadata: true,
      );

      expect(prepared, isNot(same(source)));
      expect(_containsBytes(prepared.data!, _orientationSixExifApp1), isFalse);
      expect(prepared.name, 'dropped-file.jpg');
      expect(prepared.mimeType, 'image/jpeg');
    },
  );

  test(
    'photo preparation resolves a missing GIF MIME type from bytes',
    () async {
      final source = PendingFileAttachment(
        name: 'dropped-file',
        data: _animatedGifWithMetadata(loopCount: 0x1234),
      )..mimeType = null;

      expect(resolveAttachmentMimeType(source), 'image/gif');
      expect(isPhotoAttachment(source), isTrue);

      final prepared = await preparePhotoAttachmentForSend(
        source,
        removeMetadata: true,
      );

      expect(prepared.mimeType, 'image/gif');
      expect(_containsAscii(prepared.data!, 'location=private'), isFalse);
      _expectGifLoopExtension(prepared.data!, 'NETSCAPE2.0', 0x1234);
    },
  );

  test('photo preparation corrects a sanitized GIF filename', () async {
    final source = PendingFileAttachment(
      name: 'photo.png',
      mimeType: 'image/gif',
      data: _animatedGifWithMetadata(loopCount: 0x1234),
    );

    final prepared = await preparePhotoAttachmentForSend(
      source,
      removeMetadata: true,
    );

    expect(prepared.name, 'photo.gif');
    expect(prepared.mimeType, 'image/gif');
    expect(_containsAscii(prepared.data!, 'location=private'), isFalse);
    _expectGifLoopExtension(prepared.data!, 'NETSCAPE2.0', 0x1234);
  });

  test(
    'photo preparation uses image bytes over a mismatched filename',
    () async {
      final source = PendingFileAttachment(
        name: 'photo.png',
        data: _animatedGifWithMetadata(loopCount: 0x1234),
      );

      expect(source.mimeType, 'image/png');
      expect(resolveAttachmentMimeType(source), 'image/gif');

      final prepared = await preparePhotoAttachmentForSend(
        source,
        removeMetadata: true,
      );

      expect(prepared.name, 'photo.gif');
      expect(prepared.mimeType, 'image/gif');
      expect(_containsAscii(prepared.data!, 'location=private'), isFalse);
      _expectGifLoopExtension(prepared.data!, 'NETSCAPE2.0', 0x1234);
    },
  );

  test('photo preparation matches the detected encoded format', () async {
    final source = PendingFileAttachment(
      name: 'photo.png',
      mimeType: 'image/jpeg',
      data: _photoWithExifOrientation(),
    );

    final prepared = await preparePhotoAttachmentForSend(
      source,
      removeMetadata: true,
    );

    expect(prepared.name, 'photo.jpg');
    expect(prepared.mimeType, 'image/jpeg');
    expect(img.findDecoderForData(prepared.data!), isA<img.JpegDecoder>());
  });

  test('photo preparation gives an untyped JPEG a matching name', () async {
    final source = PendingFileAttachment(
      name: 'photo.invalid',
      mimeType: 'image/jpeg',
      data: _photoWithExifOrientation(),
    );

    final prepared = await preparePhotoAttachmentForSend(
      source,
      removeMetadata: true,
    );

    expect(prepared.name, 'photo.jpg');
    expect(prepared.mimeType, 'image/jpeg');
    expect(img.findDecoderForData(prepared.data!), isA<img.JpegDecoder>());
  });

  test(
    'photo preparation removes PNG text and color profile metadata',
    () async {
      final source = PendingFileAttachment(
        name: 'photo.png',
        mimeType: 'image/png',
        data: _photoWithTextAndColorProfile(),
      );
      final sourceImage = img
          .findDecoderForData(source.data!)!
          .decode(source.data!)!;

      expect(sourceImage.textData!['location'], 'private');
      expect(sourceImage.iccProfile, isNotNull);

      final prepared = await preparePhotoAttachmentForSend(
        source,
        removeMetadata: true,
      );
      final preparedImage = img
          .findDecoderForData(prepared.data!)!
          .decode(prepared.data!)!;

      expect(preparedImage.textData, isNull);
      expect(preparedImage.iccProfile, isNull);
    },
  );

  test(
    'photo preparation strips removable metadata from an animated GIF',
    () async {
      final source = PendingFileAttachment(
        name: 'photo.gif',
        mimeType: 'image/gif',
        data: _animatedGifWithMetadata(loopCount: 0x1234),
      );

      final prepared = await preparePhotoAttachmentForSend(
        source,
        removeMetadata: true,
      );

      expect(prepared, isNot(same(source)));
      expect(prepared.mimeType, 'image/gif');
      expect(_containsAscii(prepared.data!, 'location=private'), isFalse);
      expect(_containsAscii(prepared.data!, 'XMP DataXMP'), isFalse);
      expect(_containsAscii(prepared.data!, 'NETSCAPE2.0'), isTrue);
      _expectGifLoopExtension(prepared.data!, 'NETSCAPE2.0', 0x1234);
      final decoded = img
          .findDecoderForData(prepared.data!)!
          .decode(prepared.data!);
      expect(decoded, isNotNull);
      expect(decoded!.numFrames, 2);
    },
  );

  test('photo preparation handles an empty GIF comment extension', () async {
    final source = PendingFileAttachment(
      name: 'photo.gif',
      mimeType: 'image/gif',
      data: _animatedGifWithMetadata(includeEmptyComment: true),
    );

    final prepared = await preparePhotoAttachmentForSend(
      source,
      removeMetadata: true,
    );
    final decoded = img
        .findDecoderForData(prepared.data!)!
        .decode(prepared.data!);

    expect(_containsAscii(prepared.data!, 'location=private'), isFalse);
    expect(decoded, isNotNull);
    expect(decoded!.numFrames, 2);
  });

  test('photo preparation preserves ANIMEXTS GIF loop metadata', () async {
    final source = PendingFileAttachment(
      name: 'photo.gif',
      mimeType: 'image/gif',
      data: _animatedGifWithMetadata(
        loopApplication: 'ANIMEXTS1.0',
        loopCount: 0x4321,
      ),
    );

    final prepared = await preparePhotoAttachmentForSend(
      source,
      removeMetadata: true,
    );

    expect(_containsAscii(prepared.data!, 'location=private'), isFalse);
    expect(_containsAscii(prepared.data!, 'XMP DataXMP'), isFalse);
    expect(_containsAscii(prepared.data!, 'ANIMEXTS1.0'), isTrue);
    _expectGifLoopExtension(prepared.data!, 'ANIMEXTS1.0', 0x4321);
    final decoded = img
        .findDecoderForData(prepared.data!)!
        .decode(prepared.data!);
    expect(decoded, isNotNull);
    expect(decoded!.numFrames, 2);
  });

  test(
    'photo preparation strips metadata appended to a GIF loop extension',
    () async {
      final source = PendingFileAttachment(
        name: 'photo.gif',
        mimeType: 'image/gif',
        data: _animatedGifWithMetadata(loopTrailerMetadata: 'location=private'),
      );

      final prepared = await preparePhotoAttachmentForSend(
        source,
        removeMetadata: true,
      );

      expect(prepared, isNot(same(source)));
      expect(_containsAscii(prepared.data!, 'NETSCAPE2.0'), isTrue);
      expect(_containsAscii(prepared.data!, 'location=private'), isFalse);
      final decoded = img
          .findDecoderForData(prepared.data!)!
          .decode(prepared.data!);
      expect(decoded, isNotNull);
      expect(decoded!.numFrames, 2);
    },
  );

  test('photo preparation preserves a metadata-free GIF unchanged', () async {
    final source = PendingFileAttachment(
      name: 'photo.gif',
      mimeType: 'image/gif',
      data: _animatedGifWithMetadata(includeMetadata: false),
    );

    final prepared = await preparePhotoAttachmentForSend(
      source,
      removeMetadata: true,
    );

    expect(prepared.name, source.name);
    expect(prepared.mimeType, source.mimeType);
    expect(prepared.size, source.size);
    expect(prepared.data!, orderedEquals(source.data!));
  });

  test('photo preparation preserves animated WebP bytes', () async {
    final source = PendingFileAttachment(
      name: 'photo.webp',
      mimeType: 'image/webp',
      data: _animatedWebp(),
    );
    final sourceImage = img
        .findDecoderForData(source.data!)!
        .decode(source.data!);

    expect(sourceImage!.hasAnimation, isTrue);

    final prepared = await preparePhotoAttachmentForSend(
      source,
      removeMetadata: true,
    );

    expect(prepared.name, source.name);
    expect(prepared.mimeType, source.mimeType);
    expect(prepared.data!, orderedEquals(source.data!));
  });

  test(
    'a GIF with a malformed application header is preserved unchanged',
    () async {
      // GIF89a fixes the application extension block size at 11. A shorter one
      // means the file is malformed, so the sub-block walk past it is no longer
      // known to be aligned and any "sanitized" output could be a corrupt GIF.
      // The parser used to fall through to the loop-extension check, which
      // rejects any header that is not exactly NETSCAPE2.0 or ANIMEXTS1.0 - so
      // the block was silently DROPPED and the file re-emitted as sanitized.
      // The documented fallback for unparseable input is to preserve the
      // original, and that is what must happen here.
      final source = PendingFileAttachment(
        name: 'photo.gif',
        mimeType: 'image/gif',
        data: _gifWithShortApplicationHeader(),
      );

      final prepared = await preparePhotoAttachmentForSend(
        source,
        removeMetadata: true,
      );

      // Byte equality, not identity: preparePhotoAttachmentForSend runs the
      // sanitizer through `compute`, so the returned attachment is an isolate
      // copy even on the preserve path.
      _expectPreservedAttachment(prepared, source);
      expect(
        prepared.data,
        orderedEquals(source.data!),
        reason: 'a malformed GIF was rewritten instead of being preserved',
      );
    },
  );

  test(
    'sanitization carries the metadata that still describes the bytes',
    () async {
      // The rebuilt attachment is a NEW PendingFileAttachment and `dimensions`,
      // `length`, `thumbnailFile` and `thumbnailMime` are settable fields rather
      // than constructor arguments, so every rebuild used to drop all four.
      // Downstream layout reads `dimensions` before the image decodes; losing it
      // reflows the timeline when the picture arrives.
      final source =
          PendingFileAttachment(
              name: 'photo.gif',
              mimeType: 'image/gif',
              data: _animatedGifWithMetadata(),
            )
            ..dimensions = const Size(320, 240)
            ..length = const Duration(milliseconds: 900)
            ..thumbnailFile = Uint8List.fromList(<int>[1, 2, 3])
            ..thumbnailMime = 'image/jpeg';

      final prepared = await preparePhotoAttachmentForSend(
        source,
        removeMetadata: true,
      );

      expect(prepared, isNot(same(source)));
      expect(
        prepared.dimensions,
        const Size(320, 240),
        reason: 'a comment strip does not change the frame grid',
      );
      expect(
        prepared.length,
        const Duration(milliseconds: 900),
        reason: 'a comment strip does not change the frame delays',
      );
      expect(
        prepared.path,
        isNull,
        reason:
            'path addresses the unsanitized file on disk; carrying it forward '
            'lets the send path read the original back',
      );
      expect(
        prepared.thumbnailFile,
        isNull,
        reason:
            'the thumbnail was encoded from the original and carries its own '
            'EXIF; uploading it alongside sanitized bytes leaks what was stripped',
      );
      expect(prepared.thumbnailMime, isNull);
    },
  );

  test('a re-encode reports the dimensions of the sanitized image', () async {
    // The fixture is a 2x1 JPEG carrying EXIF Orientation=6, so the picture a
    // viewer should see is 1x2. A picker that recorded the stored grid rather
    // than the displayed one hands us `Size(2, 1)`; copying that onto the
    // sanitized bytes - whose orientation has been resolved and whose EXIF is
    // gone - would lay the bubble out sideways with no tag left to correct it.
    final source = PendingFileAttachment(
      name: 'photo.jpg',
      mimeType: 'image/jpeg',
      data: _photoWithExifOrientation(),
    )..dimensions = const Size(2, 1);

    final prepared = await preparePhotoAttachmentForSend(
      source,
      removeMetadata: true,
    );

    expect(
      prepared.dimensions,
      const Size(1, 2),
      reason:
          'the dimensions must describe the sanitized pixels, not the '
          'pre-rotation grid the source reported',
    );
  });

  test('WebP metadata is stripped even when it precedes VP8X', () async {
    final source = PendingFileAttachment(
      name: 'photo.webp',
      mimeType: 'image/webp',
      data: _animatedWebpWithLeadingMetadata(),
    );
    expect(_containsAscii(source.data!, 'location=private'), isTrue);

    final prepared = await preparePhotoAttachmentForSend(
      source,
      removeMetadata: true,
    );

    expect(prepared, isNot(same(source)));
    expect(_containsAscii(prepared.data!, 'location=private'), isFalse);

    // The RIFF size must describe the shortened container.
    expect(
      _readLittleEndianUint32(prepared.data!, 4),
      prepared.data!.length - 8,
    );

    // VP8X is first again once the metadata chunk is gone, and its XMP feature
    // bit must be cleared - a container advertising metadata it no longer
    // carries is malformed.
    expect(String.fromCharCodes(prepared.data!.sublist(12, 16)), 'VP8X');
    expect(prepared.data![20] & 0x04, 0);

    // Animation survives: decodable, still two frames.
    final preparedImage = img
        .findDecoderForData(prepared.data!)!
        .decode(prepared.data!);
    expect(preparedImage!.hasAnimation, isTrue);
    expect(preparedImage.numFrames, 2);
  });

  test(
    'photo preparation strips animated WebP metadata without flattening frames',
    () async {
      final source = PendingFileAttachment(
        name: 'photo.webp',
        mimeType: 'image/webp',
        data: _animatedWebpWithMetadata(),
      );
      final sourceImage = img
          .findDecoderForData(source.data!)!
          .decode(source.data!);

      expect(sourceImage!.hasAnimation, isTrue);
      expect(sourceImage.numFrames, 2);
      expect(_containsAscii(source.data!, 'location=private'), isTrue);

      final prepared = await preparePhotoAttachmentForSend(
        source,
        removeMetadata: true,
      );
      final preparedImage = img
          .findDecoderForData(prepared.data!)!
          .decode(prepared.data!);

      expect(prepared, isNot(same(source)));
      expect(prepared.name, 'photo.webp');
      expect(prepared.mimeType, 'image/webp');
      expect(_containsAscii(prepared.data!, 'location=private'), isFalse);
      expect(preparedImage, isNotNull);
      expect(preparedImage!.hasAnimation, isTrue);
      expect(preparedImage.numFrames, 2);
    },
  );

  test(
    'photo preparation preserves a declared oversized source unchanged',
    () async {
      final source = PendingFileAttachment(
        name: 'photo.jpg',
        mimeType: 'image/jpeg',
        data: _photoWithExifOrientation(),
        size: maxPhotoMetadataPreparationBytes,
      );

      final prepared = await preparePhotoAttachmentForSend(
        source,
        removeMetadata: true,
      );

      _expectPreservedAttachment(prepared, source);
      expect(_containsBytes(prepared.data!, _orientationSixExifApp1), isTrue);
    },
  );

  test(
    'photo preparation preserves a decoded-pixel-limit source unchanged',
    () async {
      final source = PendingFileAttachment(
        name: 'oversized.bmp',
        mimeType: 'image/bmp',
        data: _oversizedBmpHeader(),
      );

      final prepared = await preparePhotoAttachmentForSend(
        source,
        removeMetadata: true,
      );

      _expectPreservedAttachment(prepared, source);
    },
  );

  test(
    'photo preparation preserves malformed image data instead of throwing',
    () async {
      final source = PendingFileAttachment(
        name: 'photo.jpg',
        mimeType: 'image/jpeg',
        data: Uint8List.fromList([0xff, 0xd8, 0xff, 0x00]),
      );

      final prepared = await preparePhotoAttachmentForSend(
        source,
        removeMetadata: true,
      );

      _expectPreservedAttachment(prepared, source);
    },
  );

  test(
    'photo preparation preserves malformed GIF data instead of throwing',
    () async {
      final source = PendingFileAttachment(
        name: 'photo.gif',
        mimeType: 'image/gif',
        data: Uint8List.fromList('GIF89a'.codeUnits),
      );

      final prepared = await preparePhotoAttachmentForSend(
        source,
        removeMetadata: true,
      );

      _expectPreservedAttachment(prepared, source);
    },
  );

  test('photo spoiler toggle changes only photos and handles mixed state', () {
    final alreadyHiddenPhoto = PendingFileAttachment(
      name: 'photo.jpg',
      mimeType: 'image/jpeg',
      data: Uint8List(1),
      spoiler: true,
    );
    final visiblePhoto = PendingFileAttachment(
      name: 'photo.png',
      mimeType: 'image/png',
      data: Uint8List(1),
    );
    final inferredPhoto = PendingFileAttachment(
      name: 'photo-from-name.jpg',
      data: Uint8List(1),
    )..mimeType = null;
    final video = PendingFileAttachment(
      name: 'clip.mp4',
      mimeType: 'video/mp4',
      data: Uint8List(1),
      spoiler: true,
    );

    final attachments = [
      alreadyHiddenPhoto,
      visiblePhoto,
      inferredPhoto,
      video,
    ];
    expect(areAttachedPhotosHidden(attachments), isFalse);

    toggleAttachedPhotoSpoilers(attachments);

    expect(alreadyHiddenPhoto.spoiler, isTrue);
    expect(visiblePhoto.spoiler, isTrue);
    expect(inferredPhoto.spoiler, isTrue);
    expect(video.spoiler, isTrue);
    expect(areAttachedPhotosHidden(attachments), isTrue);

    toggleAttachedPhotoSpoilers(attachments);

    expect(alreadyHiddenPhoto.spoiler, isFalse);
    expect(visiblePhoto.spoiler, isFalse);
    expect(inferredPhoto.spoiler, isFalse);
    expect(video.spoiler, isTrue);
  });
}

Uint8List _photoWithExifOrientation() {
  final image = img.Image(width: 2, height: 1, numChannels: 3)
    ..setPixelRgb(0, 0, 0, 0, 0)
    ..setPixelRgb(1, 0, 255, 255, 255);
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

Uint8List _photoWithTextAndColorProfile() {
  final image = img.Image(width: 2, height: 2, numChannels: 3)
    ..clear(img.ColorRgb8(20, 120, 230))
    ..addTextData({'location': 'private'})
    ..iccProfile = img.IccProfile(
      'private-profile',
      img.IccProfileCompression.none,
      Uint8List.fromList([1, 2, 3]),
    );
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _animatedWebp() => Uint8List.fromList(
  base64Decode(
    'UklGRvgAAABXRUJQVlA4WAoAAAASAAAACQAACQAAQU5JTQYAAAD/////AABBTk1GYAAAAAAAAAAAAAkA'
    'AAkAAPQBAAJWUDhMSAAAAC8JQAIAYBBJUpy2iyTUDuSPA0ZtJDkyow13/N8ZUxlI2yZip+tOT/s/D4BE'
    'IVKpOigqJU7pQrbqBn/JTL9OWX7IyJXuycOjAkFOTUZkAAAAAAAAAwAACQAAAgAA9AEAAFZQOExMAAAA'
    'LwmAABBXQJBts6kf/NNQEABkQ4kX6lZQnq0EAwGIcMQDQwy2pA3tMP8BALT9550mVAkNK3tW8COQCVjI'
    '510IOVRQWYmI/k+A3lk5AA==',
  ),
);

/// A WebP whose metadata chunk sits BEFORE `VP8X` rather than after it.
///
/// `_stripWebpMetadata` accumulates the removed feature flags across the whole
/// chunk walk and applies them once `VP8X` has been located, so ordering does
/// not matter to it. That is not obvious from reading the loop, which is why
/// it is worth a fixture.
Uint8List _animatedWebpWithLeadingMetadata() {
  final data = _animatedWebp();
  final metadata = 'location=private'.codeUnits;
  final output = <int>[
    ...data.sublist(0, 12),
    ...'XMP '.codeUnits,
    ..._littleEndianUint32(metadata.length),
    ...metadata,
    if (metadata.length.isOdd) 0,
    ...data.sublist(12),
  ];

  // Mark the XMP feature bit in VP8X, which now follows the metadata chunk.
  final vp8xFlagsOffset =
      12 + 8 + metadata.length + (metadata.length.isOdd ? 1 : 0) + 8;
  output[vp8xFlagsOffset] |= 0x04;
  _writeLittleEndianUint32(output, 4, output.length - 8);
  return Uint8List.fromList(output);
}

/// A GIF whose application extension declares a block size other than the 11
/// bytes GIF89a fixes. Malformed, not merely unrecognised.
Uint8List _gifWithShortApplicationHeader() {
  return Uint8List.fromList([
    ...'GIF89a'.codeUnits,
    0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00,
    0x00, 0x00, 0x00, 0xff, 0xff, 0xff,
    // A comment extension, so there is metadata to remove and the sanitizer
    // would otherwise have a reason to emit a rewritten file.
    0x21, 0xfe, 0x10, ...'location=private'.codeUnits, 0x00,
    // Application extension with block size 5 instead of 11.
    0x21, 0xff, 0x05, ...'SHORT'.codeUnits, 0x00,
    ..._gifFrame(),
    0x3b,
  ]);
}

Uint8List _animatedWebpWithMetadata() {
  final data = _animatedWebp();
  final metadata = 'location=private'.codeUnits;
  final output = <int>[
    ...data,
    ...'XMP '.codeUnits,
    ..._littleEndianUint32(metadata.length),
    ...metadata,
    if (metadata.length.isOdd) 0,
  ];

  // The fixture starts with a VP8X chunk. Mark the appended XMP chunk in its
  // feature bits, then update the RIFF container length.
  output[20] |= 0x04;
  _writeLittleEndianUint32(output, 4, output.length - 8);
  return Uint8List.fromList(output);
}

Uint8List _oversizedBmpHeader() => Uint8List.fromList([
  ...'BM'.codeUnits,
  ..._littleEndianUint32(54),
  0,
  0,
  0,
  0,
  ..._littleEndianUint32(54),
  ..._littleEndianUint32(40),
  ..._littleEndianUint32(100000),
  ..._littleEndianUint32(100000),
  1,
  0,
  24,
  0,
  ...List<int>.filled(24, 0),
]);

int _readLittleEndianUint32(List<int> data, int offset) =>
    data[offset] |
    (data[offset + 1] << 8) |
    (data[offset + 2] << 16) |
    (data[offset + 3] << 24);

List<int> _littleEndianUint32(int value) => [
  value & 0xff,
  (value >> 8) & 0xff,
  (value >> 16) & 0xff,
  (value >> 24) & 0xff,
];

void _writeLittleEndianUint32(List<int> data, int offset, int value) {
  data[offset] = value & 0xff;
  data[offset + 1] = (value >> 8) & 0xff;
  data[offset + 2] = (value >> 16) & 0xff;
  data[offset + 3] = (value >> 24) & 0xff;
}

Uint8List _animatedGifWithMetadata({
  String loopApplication = 'NETSCAPE2.0',
  int loopCount = 0,
  String? loopTrailerMetadata,
  bool includeMetadata = true,
  bool includeEmptyComment = false,
}) {
  return Uint8List.fromList([
    ...'GIF89a'.codeUnits,
    0x01,
    0x00,
    0x01,
    0x00,
    0x80,
    0x00,
    0x00,
    0x00,
    0x00,
    0x00,
    0xff,
    0xff,
    0xff,
    if (includeEmptyComment) ...[0x21, 0xfe, 0x00],
    if (includeMetadata) ...[
      0x21,
      0xfe,
      0x10,
      ...'location=private'.codeUnits,
      0x00,
      0x21,
      0xff,
      0x0b,
      ...'XMP DataXMP'.codeUnits,
      0x00,
    ],
    0x21,
    0xff,
    0x0b,
    ...loopApplication.codeUnits,
    0x03,
    0x01,
    loopCount & 0xff,
    loopCount >> 8,
    if (loopTrailerMetadata != null) ...[
      loopTrailerMetadata.length,
      ...loopTrailerMetadata.codeUnits,
    ],
    0x00,
    ..._gifFrame(),
    ..._gifFrame(),
    0x3b,
  ]);
}

List<int> _gifFrame() => [
  0x21,
  0xf9,
  0x04,
  0x00,
  0x00,
  0x00,
  0x00,
  0x00,
  0x2c,
  0x00,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x01,
  0x00,
  0x00,
  0x02,
  0x02,
  0x4c,
  0x01,
  0x00,
];

bool _containsAscii(Uint8List data, String value) =>
    _containsBytes(data, value.codeUnits);

void _expectGifLoopExtension(Uint8List data, String application, int count) {
  expect(
    _containsBytes(data, [
      0x21,
      0xff,
      0x0b,
      ...application.codeUnits,
      0x03,
      0x01,
      count & 0xff,
      count >> 8,
      0x00,
    ]),
    isTrue,
  );
}

bool _containsBytes(Uint8List data, List<int> needle) {
  for (var index = 0; index <= data.length - needle.length; index++) {
    var matches = true;
    for (var offset = 0; offset < needle.length; offset++) {
      if (data[index + offset] != needle[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) {
      return true;
    }
  }
  return false;
}

void _expectPreservedAttachment(
  PendingFileAttachment actual,
  PendingFileAttachment expected,
) {
  expect(actual.data, orderedEquals(expected.data!));
  expect(actual.mimeType, expected.mimeType);
  expect(actual.name, expected.name);
  expect(actual.spoiler, expected.spoiler);
}
