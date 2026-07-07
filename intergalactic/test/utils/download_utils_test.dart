import 'package:intergalactic/utils/download_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DownloadFileTask', () {
    test('passes bytes on platforms where FilePicker saveFile requires them',
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
    });

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
  });
}
