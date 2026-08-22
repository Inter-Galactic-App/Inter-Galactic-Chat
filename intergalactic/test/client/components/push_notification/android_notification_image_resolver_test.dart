import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/push_notification/android/android_notification_image_resolver.dart';
import 'package:intergalactic/utils/image/lod_image.dart';

void main() {
  test('notification image resolution waits for LOD thumbnail', () async {
    final calls = <String>[];
    final provider = _ProbeLodImageProvider(calls);

    final result = await resolveAndroidNotificationImage<String>(provider, (
      resolvedProvider,
    ) async {
      calls.add('resolve');
      expect(resolvedProvider, same(provider));
      return 'resolved';
    });

    expect(result, 'resolved');
    expect(calls, <String>['thumbnail', 'resolve']);
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

  test('LOD provider without thumbnail waits for full resolution', () async {
    final calls = <String>[];
    final provider = _ProbeLodImageProvider(calls, hasThumbnail: false);

    await resolveAndroidNotificationImage<void>(provider, (_) async {
      calls.add('resolve');
    });

    expect(calls, <String>['fullres', 'resolve']);
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
    expect(calls, <String>['thumbnail']);
  });
}

class _ProbeLodImageProvider extends LODImageProvider {
  _ProbeLodImageProvider(
    this.calls, {
    bool hasThumbnail = true,
    this.neverCompletes = false,
  }) : super(
         id: 'notification-preview-probe',
         loadThumbnail: hasThumbnail ? () async => null : null,
         loadFullRes: () async => null,
         autoLoadFullRes: false,
       );

  final List<String> calls;
  final bool neverCompletes;

  @override
  Future<void> fetchThumbnail() async {
    calls.add('thumbnail');
    if (neverCompletes) await Completer<void>().future;
  }

  @override
  Future<void> fetchFullRes() async {
    calls.add('fullres');
  }
}
