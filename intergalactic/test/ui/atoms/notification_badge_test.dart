import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/atoms/notification_badge.dart';

void main() {
  testWidgets(
    'notification badge displays count text and clamps large counts',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                NotificationBadge(2),
                NotificationBadge(12),
                NotificationBadge(100, maxDisplayCount: 99),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('9+'), findsOneWidget);
      expect(find.text('99+'), findsOneWidget);
    },
  );

  testWidgets(
    'badge width grows with every extra character, not just the third',
    (tester) async {
      // The rule used to be `length > 2 ? size * 1.7 : size`, so one and two
      // characters got the SAME box and three jumped 70% at once - a two-digit
      // count sat in a circle sized for a single digit. That is the common case
      // anywhere maxDisplayCount is raised above 9.
      Future<double> widthOf(int count, int max) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: NotificationBadge(
                  count,
                  size: 18,
                  maxDisplayCount: max,
                  animateChanges: false,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        return tester.getSize(find.byType(NotificationBadge)).width;
      }

      final one = await widthOf(5, 99);
      final two = await widthOf(42, 99);
      final three = await widthOf(100, 99);

      expect(one, 18.0, reason: 'a single digit stays a circle');
      expect(
        two,
        greaterThan(one),
        reason: 'two digits need more room than one',
      );
      expect(
        three,
        greaterThan(two),
        reason: 'three characters need more still',
      );
    },
  );

  testWidgets('a four-character label is wider than a three-character one', (
    tester,
  ) async {
    // maxDisplayCount is caller-chosen and has no upper bound, so `999+` is
    // reachable. Every bucketed width rule this widget has had lumped three
    // characters and everything longer into one box, which clipped the label.
    // Kept separate from the test above so a regression names the length that
    // broke rather than failing an omnibus case.
    Future<double> widthOf(int max) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: NotificationBadge(
                max + 1,
                size: 18,
                maxDisplayCount: max,
                animateChanges: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('$max+'), findsOneWidget);
      return tester.getSize(find.byType(NotificationBadge)).width;
    }

    final three = await widthOf(99);
    final four = await widthOf(999);

    expect(
      four,
      greaterThan(three),
      reason: '"999+" must not be squeezed into the box sized for "99+"',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the widest supported label is still sized for its length', (
    tester,
  ) async {
    // The width rule was briefly `.clamp(0, 8)`, which is the same defect as
    // the buckets it replaced at a politer threshold: anything past nine
    // characters silently got a shorter label's box. The clamp is gone and the
    // ceiling now sits on `maxDisplayCount` instead, so the widest label the
    // widget accepts still has to be measured correctly.
    Future<double> widthOf(int max) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: NotificationBadge(
                max + 1,
                size: 18,
                maxDisplayCount: max,
                animateChanges: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.getSize(find.byType(NotificationBadge)).width;
    }

    final four = await widthOf(999);
    final five = await widthOf(NotificationBadge.maxSupportedDisplayCount);

    expect(find.text('9999+'), findsOneWidget);
    expect(
      five,
      greaterThan(four),
      reason: 'the widest accepted label must not reuse a shorter box',
    );
    expect(tester.takeException(), isNull);
  });

  test('a count above the supported ceiling is rejected, not mis-drawn', () {
    // Rejecting is the point. A ceiling on the WIDTH mis-draws a label the
    // caller legitimately asked for and says nothing; a ceiling on the COUNT
    // tells them the value is unsupported while every accepted label stays
    // correctly sized.
    expect(
      () => NotificationBadge(
        1,
        maxDisplayCount: NotificationBadge.maxSupportedDisplayCount + 1,
      ),
      throwsAssertionError,
    );
    expect(
      () => NotificationBadge(1, maxDisplayCount: 0),
      throwsAssertionError,
    );
  });

  test('release builds still get a ceiling, by clamping the count', () {
    // The assert above is DEBUG-ONLY. On its own it left release builds with no
    // ceiling at all and the unbounded width rule running free, which is what
    // `effectiveMaxDisplayCount` closes. Tested as a pure function because the
    // assert fires before a widget test could ever pump an out-of-range value.
    //
    // Clamping the count is not the width-clamp mistake this widget keeps
    // making: the label becomes the ceiling and the width still measures that
    // label, so box and label agree. A width clamp mis-draws a label the caller
    // legitimately asked for.
    expect(
      NotificationBadge.effectiveMaxDisplayCount(999999999),
      NotificationBadge.maxSupportedDisplayCount,
    );
    expect(NotificationBadge.effectiveMaxDisplayCount(0), 1);
    expect(NotificationBadge.effectiveMaxDisplayCount(-5), 1);
    expect(
      NotificationBadge.effectiveMaxDisplayCount(99),
      99,
      reason: 'a supported count must pass through untouched',
    );

    // The label, not just the number. `effectiveMaxDisplayCount` alone proved
    // the clamp existed, not that the rendered text went through it - the first
    // version of this fix kept the formatting inline in `build`, and a mutation
    // that made `build` read the raw field again passed this group. The label
    // is formed in exactly one place now, and this is that place.
    expect(
      NotificationBadge.displayLabelFor(
        count: 1000000,
        maxDisplayCount: 999999999,
        exclamation: false,
      ),
      '9999+',
      reason:
          'an out-of-range cap must render the ceiling label, which is the '
          'only label the unbounded width rule can still size correctly',
    );
    expect(
      NotificationBadge.displayLabelFor(
        count: 100,
        maxDisplayCount: 99,
        exclamation: false,
      ),
      '99+',
    );
    expect(
      NotificationBadge.displayLabelFor(
        count: 5,
        maxDisplayCount: 99,
        exclamation: false,
      ),
      '5',
    );
    expect(
      NotificationBadge.displayLabelFor(
        count: 5,
        maxDisplayCount: 99,
        exclamation: true,
      ),
      '!',
    );
  });

  test('build forms its label through the single clamped site', () {
    // The one thing no widget test in this file can reach. `build` bypassing
    // the clamp only changes behaviour in RELEASE - in debug the constructor
    // assert rejects the out-of-range count first - and widget tests run in
    // debug. A mutation that reinstates the old inline `count > maxDisplayCount`
    // in `build` therefore passes every other test here, which is exactly how
    // the first version of this fix shipped with the hole still open.
    //
    // So this reads the source. It is coarse and it pins a call rather than a
    // behaviour, but the behaviour it stands for is unobservable from a test,
    // and an uncovered path is worse than a blunt gate over it.
    final source = File(
      'lib/ui/atoms/notification_badge.dart',
    ).readAsStringSync();
    final build = source.substring(source.indexOf('Widget build(BuildContext'));

    expect(
      build,
      contains('displayLabelFor('),
      reason: 'build must form its label through the clamped helper',
    );
    expect(
      build.contains('count > maxDisplayCount'),
      isFalse,
      reason:
          'build is comparing against the RAW maxDisplayCount again, which has '
          'no ceiling in release builds',
    );
  });

  testWidgets('notification badge displays room-wide mention exclamation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NotificationBadge(
            1,
            exclamation: true,
            tone: NotificationBadgeTone.warning,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('!'), findsOneWidget);
  });
}
