import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/top_level_space_order.dart';

void main() {
  test('only an exact account-data echo settles a pending rank', () {
    expect(
      TopLevelSpaceOrderStore.pendingOrderMatchesRemote(
        '000000000A',
        '000000000A',
      ),
      isTrue,
    );
    expect(
      TopLevelSpaceOrderStore.pendingOrderMatchesRemote(
        '000000000A',
        '0000000009',
      ),
      isFalse,
    );
    expect(
      TopLevelSpaceOrderStore.pendingOrderMatchesRemote('000000000A', null),
      isFalse,
    );
  });

  test('a changed remote rank supersedes the pre-write cache baseline', () {
    expect(
      TopLevelSpaceOrderStore.pendingOrderShouldYieldToRemote(
        '0000000009',
        '0000000009',
      ),
      isFalse,
    );
    expect(
      TopLevelSpaceOrderStore.pendingOrderShouldYieldToRemote(
        '0000000009',
        '000000000B',
      ),
      isTrue,
    );
  });

  test('base-36 ranks preserve a gap only when one exists', () {
    expect(
      TopLevelSpaceOrderStore.rankBetweenForTesting('0000000000', '000000000A'),
      '0000000005',
    );
    expect(
      TopLevelSpaceOrderStore.rankBetweenForTesting('0000000009', '000000000A'),
      isNull,
    );
    expect(TopLevelSpaceOrderStore.rankBetweenForTesting('bad', null), isNull);
  });

  test('initial base-36 ranks are ordered and fixed width', () {
    final ranks = [
      for (var index = 0; index < 3; index++)
        TopLevelSpaceOrderStore.initialRankForTesting(index, 3),
    ];

    expect(ranks[0].compareTo(ranks[1]), lessThan(0));
    expect(ranks[1].compareTo(ranks[2]), lessThan(0));
    expect(ranks.every((rank) => rank.length == 10), isTrue);
  });

  test('moved-space detection identifies one moved id only', () {
    expect(
      TopLevelSpaceOrderStore.movedSpaceIdForTesting(
        ['a', 'b', 'c'],
        ['b', 'c', 'a'],
      ),
      'a',
    );
    expect(
      TopLevelSpaceOrderStore.movedSpaceIdForTesting(
        ['a', 'b', 'c', 'd'],
        ['a', 'c', 'd', 'b'],
      ),
      'b',
    );
    expect(
      TopLevelSpaceOrderStore.movedSpaceIdForTesting(
        ['a', 'b'],
        ['a', 'b', 'c'],
      ),
      isNull,
    );
  });
}
