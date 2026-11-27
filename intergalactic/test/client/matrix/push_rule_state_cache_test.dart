import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/push_rule_state_cache.dart';
import 'package:matrix/matrix.dart' as matrix;

void main() {
  group('PushRuleStateCache', () {
    late matrix.PushRuleState source;
    late int reads;
    late PushRuleStateCache cache;

    setUp(() {
      source = matrix.PushRuleState.notify;
      reads = 0;
      cache = PushRuleStateCache(() {
        reads++;
        return source;
      });
    });

    test('reads through once and then serves the cached value', () {
      expect(cache.value, matrix.PushRuleState.notify);
      expect(cache.value, matrix.PushRuleState.notify);

      expect(reads, 1, reason: 'the read is what was too expensive for the UI');
    });

    test('cachedValue distinguishes a cold cache from a populated one', () {
      expect(cache.cachedValue, isNull);

      cache.value;

      expect(cache.cachedValue, matrix.PushRuleState.notify);
      expect(reads, 1, reason: 'cachedValue must not read through');
    });

    test('assign records a local write without re-reading', () {
      cache.assign(matrix.PushRuleState.dontNotify);

      expect(cache.value, matrix.PushRuleState.dontNotify);
      expect(reads, 0);
    });

    // BUG-319: this is the case the old bare-field cache could not express.
    test('invalidate picks up a change made behind the cache', () {
      expect(cache.value, matrix.PushRuleState.notify);
      source = matrix.PushRuleState.dontNotify;

      expect(
        cache.value,
        matrix.PushRuleState.notify,
        reason: 'stale until invalidated - this is the defect being fixed',
      );

      expect(cache.invalidate(), isTrue);
      expect(cache.value, matrix.PushRuleState.dontNotify);
    });

    test('invalidate reports no change when the state is unchanged', () {
      cache.value;

      expect(
        cache.invalidate(),
        isFalse,
        reason: 'an unchanged sync must not notify listeners',
      );
    });

    test('invalidate leaves a cold cache cold and reports no change', () {
      source = matrix.PushRuleState.mentionsOnly;

      expect(
        cache.invalidate(),
        isFalse,
        reason: 'nothing has read it, so nothing is showing a stale value',
      );
      expect(reads, 0, reason: 'invalidating must not defeat the laziness');
      expect(cache.cachedValue, isNull);
      expect(cache.value, matrix.PushRuleState.mentionsOnly);
    });

    test('invalidate corrects a wrong assign from a failed write', () {
      cache.assign(matrix.PushRuleState.dontNotify);

      expect(cache.invalidate(), isTrue);
      expect(cache.value, matrix.PushRuleState.notify);
    });
  });
}
