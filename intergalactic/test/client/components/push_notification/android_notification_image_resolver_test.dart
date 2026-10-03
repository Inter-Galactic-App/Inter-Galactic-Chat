import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/push_notification/android/android_notification_image_resolver.dart';
import 'package:intergalactic/utils/image/lod_image.dart';

void main() {
  test('notification image resolution prefers LOD full resolution', () async {
    final calls = <String>[];
    final fullRes = Uint8List.fromList(<int>[1, 2, 3]);
    final provider = _ProbeLodImageProvider(calls, fullResBytes: fullRes);

    final result = await resolveAndroidNotificationImage<String>(provider, (
      resolvedProvider,
    ) async {
      calls.add('resolve');
      expect(resolvedProvider, isA<MemoryImage>());
      expect((resolvedProvider as MemoryImage).bytes, orderedEquals(fullRes));
      return 'resolved';
    });

    expect(result, 'resolved');
    expect(calls, <String>['fullres', 'resolve']);
  });

  test('non-LOD notification image resolves immediately', () async {
    final calls = <String>[];
    final provider = MemoryImage(Uint8List.fromList(<int>[1]));

    await resolveAndroidNotificationImage<void>(provider, (
      resolvedProvider,
    ) async {
      calls.add('resolve');
      expect(resolvedProvider, same(provider));
    });

    expect(calls, <String>['resolve']);
  });

  test('LOD provider without full resolution waits for a thumbnail', () async {
    final calls = <String>[];
    final provider = _ProbeLodImageProvider(calls, hasFullRes: false);

    await resolveAndroidNotificationImage<void>(provider, (_) async {
      calls.add('resolve');
    });

    expect(calls, <String>['thumbnail', 'resolve']);
  });

  test('empty full-resolution bytes fall back to the thumbnail', () async {
    final calls = <String>[];
    final provider = _ProbeLodImageProvider(calls, fullResBytes: Uint8List(0));

    final result = await resolveAndroidNotificationImage<String>(provider, (
      resolvedProvider,
    ) async {
      calls.add('resolve');
      expect(resolvedProvider, isA<MemoryImage>());
      expect(
        (resolvedProvider as MemoryImage).bytes,
        orderedEquals(<int>[4, 5, 6]),
      );
      return 'thumbnail';
    });

    expect(result, 'thumbnail');
    expect(calls, <String>['fullres', 'thumbnail', 'resolve']);
  });

  test('LOD image timeout omits the optional notification preview', () async {
    final calls = <String>[];
    final provider = _ProbeLodImageProvider(calls, neverCompletes: true);

    final result = await resolveAndroidNotificationImage<Object>(
      provider,
      (_) async => Object(),
      mediaLoadTimeout: Duration.zero,
    );

    expect(result, isNull);
    expect(calls, <String>['fullres']);
  });

  test('full-resolution timeout still tries a ready thumbnail', () async {
    final calls = <String>[];
    final provider = _ProbeLodImageProvider(calls, fullResNeverCompletes: true);

    final result = await resolveAndroidNotificationImage<String>(provider, (
      resolvedProvider,
    ) async {
      calls.add('resolve');
      expect((resolvedProvider as MemoryImage).bytes, orderedEquals([4, 5, 6]));
      return 'thumbnail';
    }, mediaLoadTimeout: const Duration(milliseconds: 90));

    expect(result, 'thumbnail');
    expect(calls, <String>['fullres', 'thumbnail', 'resolve']);
  });
}

class _ProbeLodImageProvider extends LODImageProvider {
  _ProbeLodImageProvider(
    this.calls, {
    bool hasThumbnail = true,
    bool hasFullRes = true,
    Uint8List? fullResBytes,
    this.neverCompletes = false,
    this.fullResNeverCompletes = false,
  }) : super(
         id: 'notification-preview-probe',
         loadThumbnail: hasThumbnail
             ? () async {
                 calls.add('thumbnail');
                 if (neverCompletes) await Completer<void>().future;
                 return Uint8List.fromList(<int>[4, 5, 6]);
               }
             : null,
         loadFullRes: hasFullRes
             ? () async {
                 calls.add('fullres');
                 if (neverCompletes || fullResNeverCompletes) {
                   await Completer<void>().future;
                 }
                 return fullResBytes ?? Uint8List.fromList(<int>[1, 2, 3]);
               }
             : null,
         autoLoadFullRes: false,
       );

  final List<String> calls;
  final bool neverCompletes;
  final bool fullResNeverCompletes;
}
