import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/utils/image/lod_image.dart';

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
}

class _ProbeLODImageProvider extends LODImageProvider {
  _ProbeLODImageProvider({
    required String id,
    required this.cachedThumbnailProbe,
    Future<Uint8List?> Function()? loadThumbnail,
    bool autoLoadFullRes = true,
  }) : super(
          id: id,
          loadThumbnail: loadThumbnail,
          autoLoadFullRes: autoLoadFullRes,
        );

  final Future<bool> Function() cachedThumbnailProbe;

  @override
  Future<bool> hasCachedThumbnail() => cachedThumbnailProbe();
}
