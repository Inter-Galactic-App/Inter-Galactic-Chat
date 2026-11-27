import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/utils/notifying_list.dart';

void main() {
  group('NotifyingList', () {
    test('removeWhere removes adjacent matching items', () {
      final list = NotifyingList<int>.empty(growable: true);
      list.addAll([1, 2, 4, 5, 6]);

      list.removeWhere((value) => value.isEven);

      expect(list.toList(growable: false), [1, 5]);
    });
  });
}
