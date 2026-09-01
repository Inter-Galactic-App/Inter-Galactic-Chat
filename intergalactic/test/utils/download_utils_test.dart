import 'package:intergalactic/utils/download_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DownloadFileTask', () {
    test(
      'passes bytes on platforms where FilePicker saveFile requires them',
      () {
        expect(
          DownloadFileTask.saveFileRequiresBytesForPlatform(
            isAndroid: true,
            isIOS: false,
            isWeb: false,
          ),
          isTrue,
        );
        expect(
          DownloadFileTask.saveFileRequiresBytesForPlatform(
            isAndroid: false,
            isIOS: true,
            isWeb: false,
          ),
          isTrue,
        );
        expect(
          DownloadFileTask.saveFileRequiresBytesForPlatform(
            isAndroid: false,
            isIOS: false,
            isWeb: true,
          ),
          isTrue,
        );
      },
    );

    test('keeps desktop saves on the path-based FilePicker flow', () {
      expect(
        DownloadFileTask.saveFileRequiresBytesForPlatform(
          isAndroid: false,
          isIOS: false,
          isWeb: false,
        ),
        isFalse,
      );
    });

    test('routes iOS image downloads to Photos', () {
      expect(
        DownloadFileTask.shouldSaveImageToPhotosForPlatform(
          isIOS: true,
          mimeType: 'image/jpeg',
          filename: 'photo.jpg',
        ),
        isTrue,
      );

      expect(
        DownloadFileTask.shouldSaveImageToPhotosForPlatform(
          isIOS: true,
          mimeType: null,
          filename: 'photo.png',
        ),
        isTrue,
      );

      expect(
        DownloadFileTask.shouldSaveImageToPhotosForPlatform(
          isIOS: true,
          mimeType: 'image/heic',
          filename: 'photo.heic',
        ),
        isTrue,
      );
    });

    test('keeps non-iOS and non-image downloads out of Photos', () {
      expect(
        DownloadFileTask.shouldSaveImageToPhotosForPlatform(
          isIOS: false,
          mimeType: 'image/jpeg',
          filename: 'photo.jpg',
        ),
        isFalse,
      );

      expect(
        DownloadFileTask.shouldSaveImageToPhotosForPlatform(
          isIOS: true,
          mimeType: 'application/pdf',
          filename: 'guide.pdf',
        ),
        isFalse,
      );
    });

    test('routes mobile image and video exports to Photos or gallery', () {
      expect(
        DownloadFileTask.shouldSaveMediaToPhotosForPlatform(
          isAndroid: true,
          isIOS: false,
          mimeType: 'video/mp4',
          filename: 'capture.mp4',
        ),
        isTrue,
      );
      expect(
        DownloadFileTask.shouldSaveMediaToPhotosForPlatform(
          isAndroid: false,
          isIOS: true,
          mimeType: 'image/png',
          filename: 'cutout.png',
        ),
        isTrue,
      );
      expect(
        DownloadFileTask.shouldSaveMediaToPhotosForPlatform(
          isAndroid: false,
          isIOS: false,
          mimeType: 'image/png',
          filename: 'cutout.png',
        ),
        isFalse,
      );
      expect(
        DownloadFileTask.shouldSaveMediaToPhotosForPlatform(
          isAndroid: true,
          isIOS: false,
          mimeType: 'application/pdf',
          filename: 'document.pdf',
        ),
        isFalse,
      );
    });

    test('treats completed web byte-backed save dispatch as success', () {
      expect(
        DownloadFileTask.byteBackedSaveCompletedForPlatform(
          destinationPath: null,
          isWeb: true,
        ),
        isTrue,
      );
    });

    test('keeps native byte-backed save cancellation detection', () {
      expect(
        DownloadFileTask.byteBackedSaveCompletedForPlatform(
          destinationPath: null,
          isWeb: false,
        ),
        isFalse,
      );

      expect(
        DownloadFileTask.byteBackedSaveCompletedForPlatform(
          destinationPath: 'saved-file.txt',
          isWeb: false,
        ),
        isTrue,
      );
    });

    test('uses the known MIME type as the desktop save extension', () {
      expect(
        DownloadFileTask.preferredSaveExtension(
          mimeType: 'video/mp4',
          filename: 'clip',
        ),
        'mp4',
      );
    });

    test(
      'adds the recognized extension only when the saved name lacks one',
      () {
        expect(
          DownloadFileTask.ensurePreferredSaveExtension(
            'C:/Downloads/renamed-video',
            'mp4',
          ),
          'C:/Downloads/renamed-video.mp4',
        );
        expect(
          DownloadFileTask.ensurePreferredSaveExtension(
            'C:/Downloads/renamed-video.webm',
            'mp4',
          ),
          'C:/Downloads/renamed-video.webm',
        );
      },
    );

    test('treats leading- and trailing-dot names as extensionless', () {
      // `contains('.')` called both of these "already extended", so a desktop
      // user got a file with no usable type suffix.
      expect(
        DownloadFileTask.ensurePreferredSaveExtension(
          'C:/Downloads/.video',
          'mp4',
        ),
        'C:/Downloads/.video.mp4',
      );
      expect(
        DownloadFileTask.ensurePreferredSaveExtension(
          'C:/Downloads/video.',
          'mp4',
        ),
        'C:/Downloads/video.mp4',
      );
    });
  });

  group('media saver method channel', () {
    const channel = MethodChannel('chat.intergalactic.app/media_saver');
    final calls = <MethodCall>[];

    void handleWith(Future<Object?> Function(MethodCall call) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) {
            calls.add(call);
            return handler(call);
          });
    }

    setUp(calls.clear);

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'invokes the saveMediaToPhotos method the platforms implement',
      () async {
        handleWith((_) async => true);

        final saved = await DownloadFileTask.saveMediaToPhotos(
          bytes: Uint8List.fromList([1, 2, 3]),
          filename: 'cutout.png',
          mimeType: 'image/png',
        );

        expect(saved, isTrue);
        expect(calls.single.method, 'saveMediaToPhotos');
        final arguments = calls.single.arguments as Map;
        expect(arguments['filename'], 'cutout.png');
        expect(arguments['mimeType'], 'image/png');
        expect(arguments['bytes'], isNotNull);
        expect(arguments.containsKey('path'), isFalse);
      },
    );

    test('forwards a file path for media that is already on disk', () async {
      handleWith((_) async => true);

      final saved = await DownloadFileTask.saveMediaToPhotos(
        path: '/tmp/story-video.mp4',
        filename: 'story-video.mp4',
        mimeType: 'video/mp4',
      );

      expect(saved, isTrue);
      final arguments = calls.single.arguments as Map;
      expect(arguments['path'], '/tmp/story-video.mp4');
      expect(arguments['mimeType'], 'video/mp4');
      expect(arguments.containsKey('bytes'), isFalse);
    });

    test(
      'reports failure instead of throwing when the platform errors',
      () async {
        handleWith(
          (_) async => throw PlatformException(code: 'photo_permission_denied'),
        );

        await expectLater(
          DownloadFileTask.saveMediaToPhotos(
            bytes: Uint8List.fromList([1]),
            filename: 'cutout.png',
            mimeType: 'image/png',
          ),
          completion(isFalse),
        );
      },
    );

    test(
      'reports failure when no platform implementation is registered',
      () async {
        // No mock handler installed: this is the shape of a missing native
        // handler, which is what an unimplemented channel method looks like.
        await expectLater(
          DownloadFileTask.saveMediaToPhotos(
            bytes: Uint8List.fromList([1]),
            filename: 'cutout.png',
            mimeType: 'image/png',
          ),
          completion(isFalse),
        );
      },
    );

    test('refuses a call with neither bytes nor a path', () async {
      handleWith((_) async => true);

      expect(
        await DownloadFileTask.saveMediaToPhotos(filename: 'empty.png'),
        isFalse,
      );
      expect(calls, isEmpty);
    });
  });

  group('captured media auto-save', () {
    test('saves camera captures on mobile once the user opts in', () {
      expect(
        DownloadUtils.shouldAutoSaveCapturedMedia(
          enabled: true,
          isAndroid: true,
          isIOS: false,
          mimeType: 'image/jpeg',
          filename: 'capture.jpg',
        ),
        isTrue,
      );
      expect(
        DownloadUtils.shouldAutoSaveCapturedMedia(
          enabled: true,
          isAndroid: false,
          isIOS: true,
          mimeType: 'video/mp4',
          filename: 'capture.mp4',
        ),
        isTrue,
      );
    });

    test('stays off until the user opts in', () {
      expect(
        DownloadUtils.shouldAutoSaveCapturedMedia(
          enabled: false,
          isAndroid: true,
          isIOS: false,
          mimeType: 'image/jpeg',
          filename: 'capture.jpg',
        ),
        isFalse,
      );
    });

    test('does nothing on platforms without a device gallery', () {
      expect(
        DownloadUtils.shouldAutoSaveCapturedMedia(
          enabled: true,
          isAndroid: false,
          isIOS: false,
          mimeType: 'image/jpeg',
          filename: 'capture.jpg',
        ),
        isFalse,
      );
    });

    test('skips capture types the gallery cannot hold', () {
      expect(
        DownloadUtils.shouldAutoSaveCapturedMedia(
          enabled: true,
          isAndroid: true,
          isIOS: false,
          mimeType: 'audio/mp4',
          filename: 'voice-note.m4a',
        ),
        isFalse,
      );
    });

    test('never throws when the save itself is impossible', () async {
      await expectLater(
        DownloadUtils.autoSaveCapturedMediaIfEnabled(
          filename: 'capture.jpg',
          bytes: Uint8List.fromList([1]),
          mimeType: 'image/jpeg',
          enabled: true,
        ),
        completion(isFalse),
      );
    });
  });
}
