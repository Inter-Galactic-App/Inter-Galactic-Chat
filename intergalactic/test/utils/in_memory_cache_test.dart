import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/utils/in_memory_cache.dart';

void main() {
  test('dispose cancels timer and prevents later cache writes', () async {
    final cache = InMemoryCache<int>(
      maxRetention: const Duration(milliseconds: 1),
      pollFrequency: const Duration(milliseconds: 10),
    );
    final removed = <String>[];
    final subscription = cache.onRemove.listen(removed.add);

    cache.put('before-dispose', 1);

    await cache.dispose();
    cache.put('after-dispose', 2);
    await cache.clean();
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(cache.get('before-dispose'), isNull);
    expect(cache.get('after-dispose'), isNull);
    expect(removed, isEmpty);
    await subscription.cancel();
  });
}
