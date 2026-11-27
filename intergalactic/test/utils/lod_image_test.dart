import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/cache/file_cache.dart';
import 'package:intergalactic/client/matrix/matrix_mxc_image_provider.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/utils/image/lod_image.dart';
import 'package:matrix/matrix.dart';

void main() {
  testWidgets('full-resolution load errors stay on the image stream',
      (tester) async {
    final zoneErrors = <Object>[];
    final streamErrors = <Object>[];

    await runZonedGuarded(
      () async {
        final provider = LODImageProvider(
          id: 'missing-media',
          loadFullRes: () async => throw StateError('missing media'),
        );
        final stream = provider.resolve(ImageConfiguration.empty);
        final listener = ImageStreamListener(
          (_, __) {},
          onError: (error, stackTrace) {
            streamErrors.add(error);
          },
        );

        stream.addListener(listener);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
        stream.removeListener(listener);
      },
      (error, stackTrace) {
        zoneErrors.add(error);
      },
    );

    expect(zoneErrors, isEmpty);
    expect(streamErrors, hasLength(1));
    expect(streamErrors.single, isA<StateError>());
  });

  testWidgets('thumbnail load errors stay on the image stream', (tester) async {
    final zoneErrors = <Object>[];
    final streamErrors = <Object>[];

    await runZonedGuarded(
      () async {
        final provider = LODImageProvider(
          id: 'missing-thumbnail',
          loadThumbnail: () async => throw StateError('missing thumbnail'),
          loadFullRes: () async => Uint8List.fromList(const <int>[]),
          autoLoadFullRes: false,
        );
        final stream = provider.resolve(ImageConfiguration.empty);
        final listener = ImageStreamListener(
          (_, __) {},
          onError: (error, stackTrace) {
            streamErrors.add(error);
          },
        );

        stream.addListener(listener);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
        stream.removeListener(listener);
      },
      (error, stackTrace) {
        zoneErrors.add(error);
      },
    );

    expect(zoneErrors, isEmpty);
    expect(streamErrors, hasLength(1));
    expect(streamErrors.single, isA<StateError>());
  });

  testWidgets('cache probe errors still allow fallback image loads',
      (tester) async {
    final zoneErrors = <Object>[];
    final streamErrors = <Object>[];
    var thumbnailLoads = 0;

    await runZonedGuarded(
      () async {
        final provider = _ProbeLODImageProvider(
          id: 'cache-probe-miss',
          cachedThumbnailProbe: () async =>
              throw StateError('cache unavailable'),
          loadThumbnail: () async {
            thumbnailLoads++;
            throw StateError('fallback thumbnail failed');
          },
          autoLoadFullRes: false,
        );
        final stream = provider.resolve(ImageConfiguration.empty);
        final listener = ImageStreamListener(
          (_, __) {},
          onError: (error, stackTrace) {
            streamErrors.add(error);
          },
        );

        stream.addListener(listener);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 1));
        stream.removeListener(listener);
      },
      (error, stackTrace) {
        zoneErrors.add(error);
      },
    );

    expect(zoneErrors, isEmpty);
    expect(thumbnailLoads, 1);
    expect(streamErrors, isNotEmpty);
    expect(streamErrors, contains(isA<StateError>()));
  });

  testWidgets('cached thumbnails still autoload full-resolution images',
      (tester) async {
    var thumbnailLoads = 0;
    var fullResLoads = 0;

    final provider = _ProbeLODImageProvider(
      id: 'cached-thumbnail-autoloads-fullres',
      cachedThumbnailProbe: () async => true,
      loadThumbnail: () async {
        thumbnailLoads++;
        return null;
      },
      loadFullRes: () async {
        fullResLoads++;
        return null;
      },
    );

    final stream = provider.resolve(ImageConfiguration.empty);
    final listener = ImageStreamListener((_, __) {});

    stream.addListener(listener);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    stream.removeListener(listener);

    expect(thumbnailLoads, 1);
    expect(fullResLoads, 1);
  });

  test('Matrix MXC images report cached full-resolution files', () async {
    final previousCache = globals.fileCache;
    globals.fileCache = _MemoryFileCache({
      MatrixMxcImage.getIdentifier(Uri.parse('mxc://example.org/banner')),
    });
    addTearDown(() {
      globals.fileCache = previousCache;
    });

    final provider = MatrixMxcImage(
      Uri.parse('mxc://example.org/banner'),
      Client('test', database: _FakeMatrixDatabase()),
    );

    expect(await provider.hasCachedFullres(), isTrue);
    expect(await provider.hasCachedThumbnail(), isFalse);
  });
}

class _ProbeLODImageProvider extends LODImageProvider {
  _ProbeLODImageProvider({
    required String id,
    required this.cachedThumbnailProbe,
    Future<Uint8List?> Function()? loadThumbnail,
    Future<Uint8List?> Function()? loadFullRes,
    bool autoLoadFullRes = true,
  }) : super(
          id: id,
          loadThumbnail: loadThumbnail,
          loadFullRes: loadFullRes,
          autoLoadFullRes: autoLoadFullRes,
        );

  final Future<bool> Function() cachedThumbnailProbe;

  @override
  Future<bool> hasCachedThumbnail() => cachedThumbnailProbe();
}

class _MemoryFileCache implements FileCache {
  _MemoryFileCache(Iterable<String> identifiers) : files = identifiers.toSet();

  final Set<String> files;

  @override
  Future<void> init() async {}

  @override
  Future<void> close() async {}

  @override
  Future<bool> hasFile(String identifier) async => files.contains(identifier);

  @override
  Future<Uri?> getFile(String identifier) async {
    return files.contains(identifier) ? Uri.file(identifier) : null;
  }

  @override
  Future<Uri> putFile(String identifier, Uint8List bytes) async {
    files.add(identifier);
    return Uri.file(identifier);
  }

  @override
  Future<Uri> fetchFile(
    String identifier,
    Future<Uint8List> Function() getter,
  ) async {
    files.add(identifier);
    return Uri.file(identifier);
  }

  @override
  Future<void> clean() async {}
}

class _FakeMatrixDatabase implements DatabaseApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
