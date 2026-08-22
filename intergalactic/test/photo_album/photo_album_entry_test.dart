import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/components/photo_album_room/photo.dart';
import 'package:intergalactic/client/components/photo_album_room/photo_album_entry.dart';
import 'package:intergalactic/client/timeline.dart';
import 'package:test/test.dart';

void main() {
  group('photo album entries', () {
    test('legacy individual photos render as individual entries', () {
      final entries = buildPhotoAlbumEntries([
        _FakePhoto('a'),
        _FakePhoto('b'),
      ]);

      expect(entries, hasLength(2));
      expect(entries.every((entry) => !entry.isStack), isTrue);
      expect(entries.map((entry) => entry.id), ['a', 'b']);
    });

    test('stack metadata groups photos and sorts by stack index', () {
      final entries = buildPhotoAlbumEntries([
        _FakePhoto(
          'second',
          stack: const PhotoStackMetadata(id: 'stack-1', index: 1, count: 3),
        ),
        _FakePhoto('single'),
        _FakePhoto(
          'first',
          stack: const PhotoStackMetadata(id: 'stack-1', index: 0, count: 3),
        ),
        _FakePhoto(
          'third',
          stack: const PhotoStackMetadata(id: 'stack-1', index: 2, count: 3),
        ),
      ]);

      expect(entries, hasLength(2));
      expect(entries.first, isA<PhotoStackAlbumEntry>());
      expect(entries.first.photos.map((photo) => photo.id),
          ['first', 'second', 'third']);
      expect(entries.first.rootPhoto.id, 'first');
      expect(entries.last.id, 'single');
    });

    test('incomplete stack metadata falls back to individual entries', () {
      final entries = buildPhotoAlbumEntries([
        _FakePhoto(
          'first',
          stack: const PhotoStackMetadata(id: 'stack-1', index: 0, count: 3),
        ),
        _FakePhoto(
          'second',
          stack: const PhotoStackMetadata(id: 'stack-1', index: 1, count: 3),
        ),
      ]);

      expect(entries, hasLength(2));
      expect(entries.every((entry) => !entry.isStack), isTrue);
    });

    test('thread replies are excluded from the album grid', () {
      final entries = buildPhotoAlbumEntries([
        _FakePhoto('root'),
        _FakePhoto('comment-attachment', isThreadReply: true),
      ]);

      expect(entries, hasLength(1));
      expect(entries.single.id, 'root');
    });
  });

  group('photo stack metadata', () {
    test('parses valid Matrix event content', () {
      final stack = PhotoStackMetadata.fromContent({
        'id': 'stack-1',
        'index': 1,
        'count': 2,
      });

      expect(stack?.id, 'stack-1');
      expect(stack?.index, 1);
      expect(stack?.count, 2);
    });

    test('rejects malformed Matrix event content', () {
      expect(
        PhotoStackMetadata.fromContent({
          'id': 'stack-1',
          'index': 2,
          'count': 2,
        }),
        isNull,
      );
      expect(
        PhotoStackMetadata.fromContent({
          'id': '',
          'index': 0,
          'count': 2,
        }),
        isNull,
      );
    });

    test('upload helper writes stack metadata only for stack uploads', () {
      expect(
        PhotoStackMetadata.eventContentForUpload(
          mode: PhotoAlbumUploadMode.individual,
          stackId: 'stack-1',
          index: 0,
          count: 2,
        ),
        isNull,
      );

      expect(
        PhotoStackMetadata.eventContentForUpload(
          mode: PhotoAlbumUploadMode.stack,
          stackId: 'stack-1',
          index: 0,
          count: 2,
        ),
        {
          PhotoStackMetadata.eventContentKey: {
            'id': 'stack-1',
            'index': 0,
            'count': 2,
          },
        },
      );
    });
  });
}

class _FakePhoto implements Photo {
  _FakePhoto(
    this.id, {
    this.stack,
    this.isThreadReply = false,
  });

  @override
  final String id;

  @override
  final PhotoStackMetadata? stack;

  @override
  final bool isThreadReply;

  @override
  Attachment? get attachment => null;

  @override
  double? get height => 100;

  @override
  TimelineEventStatus get status => TimelineEventStatus.synced;

  @override
  int get threadReplyCount => 0;

  @override
  double? get width => 100;
}
