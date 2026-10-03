import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/message_forwarding/matrix_forwarded_message.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_forwarded.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_reply.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owner design pass, 2026-09-05: "I would like forward to indicate more like
/// reply."
///
/// Forward and reply occupy the same slot above a message and answer the same
/// question, but forward drew a separate labelled box while reply draws an
/// elbow line into the text. They now share a shape per mode, with the forward
/// glyph as the thing that tells them apart.
const _label = 'Ankle Biter';
const _id = '@impurexchaos:ourgalaxy.space';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.layoutOverride.set('desktop');
  });

  const presentation = MatrixForwardedPresentation(
    originalAuthorId: _id,
    originalAuthorLabel: _label,
  );

  Widget subject({required bool bubbleMessages, bool alignRight = false}) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          child: TimelineEventViewForwarded(
            presentation: presentation,
            bubbleMessages: bubbleMessages,
            alignRight: alignRight,
          ),
        ),
      ),
    );
  }

  String plainTextOf(WidgetTester tester) {
    return tester
        .widgetList<RichText>(find.byType(RichText))
        .map((rich) => rich.text.toPlainText())
        .join('\n');
  }

  // The tinted capsule the bubble mode draws, in screen coordinates. It is the
  // only DecoratedBox this widget builds, so its rect is where the outer inset
  // ends up.
  Rect capsuleRect(WidgetTester tester) {
    return tester.getRect(
      find.descendant(
        of: find.byType(TimelineEventViewForwarded),
        matching: find.byType(DecoratedBox),
      ),
    );
  }

  bool hasReplyLine(WidgetTester tester) {
    return tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .any((paint) => paint.painter is ReplyLinePainter2);
  }

  testWidgets('outside bubbles it draws the reply elbow', (tester) async {
    await tester.pumpWidget(subject(bubbleMessages: false));
    await tester.pump();

    expect(
      hasReplyLine(tester),
      isTrue,
      reason:
          'the non-bubble forward is back to its own box shape instead of the '
          'reply elbow',
    );
  });

  testWidgets('the author and their Matrix ID are both on the line', (
    tester,
  ) async {
    await tester.pumpWidget(subject(bubbleMessages: false));
    await tester.pump();

    final text = plainTextOf(tester);
    expect(text, contains('Forwarded from'));
    expect(text, contains(_label));
    expect(
      text,
      contains(_id),
      reason:
          'the Matrix ID is what stops a chosen display name from passing as '
          'someone else, so it cannot be dropped for tidiness',
    );

    // ON THE LINE, not merely somewhere in the subtree. `plainTextOf` joins
    // every RichText, so the three assertions above hold just as well if the
    // prefix, the name and the ID are split into separate widgets stacked
    // vertically - which is the bubble shape, not this one. The inline shape's
    // contract is one single-line RichText carrying all three as spans, so
    // that a narrow row ellipsises the tail of the ID first
    // (timeline_event_view_forwarded.dart:90-95).
    final attribution = tester.widgetList<RichText>(
      find.descendant(
        of: find.byType(TimelineEventViewForwarded),
        matching: find.byType(RichText),
      ),
    );
    // The prefix is part of the line, not merely part of the subtree. Without
    // it in this predicate the shape "Forwarded from" in its own widget above
    // a second widget carrying the name and the ID satisfies every assertion
    // in this test - and that shape is a two-line attribution, which is what
    // the inline forward exists not to be.
    final carryingAll = attribution.where(
      (rich) =>
          rich.text.toPlainText().contains('Forwarded from') &&
          rich.text.toPlainText().contains(_label) &&
          rich.text.toPlainText().contains(_id),
    );
    expect(
      carryingAll,
      hasLength(1),
      reason:
          'the prefix, the name and the Matrix ID must share one text widget, '
          'or the ID wraps onto its own line instead of ellipsising',
    );
    expect(
      carryingAll.single.maxLines,
      1,
      reason: 'a multi-line attribution is a second line, not an ellipsis',
    );
    expect(carryingAll.single.overflow, TextOverflow.ellipsis);
  });

  testWidgets('the author name is coloured apart from the surrounding text', (
    tester,
  ) async {
    // A reply colours the name it credits. If the forward paints the whole
    // line one colour it reads as a system label rather than an attribution.
    await tester.pumpWidget(subject(bubbleMessages: false));
    await tester.pump();

    final rich = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere(
          (candidate) => candidate.text.toPlainText().contains(_label),
        );
    final colors = <Color?>{};
    rich.text.visitChildren((span) {
      if (span is TextSpan && (span.text?.isNotEmpty ?? false)) {
        colors.add(span.style?.color);
      }
      return true;
    });

    expect(
      colors.length,
      greaterThan(1),
      reason: 'the name is painted in the same colour as the rest of the line',
    );
  });

  testWidgets('inside bubbles it uses the capsule, not the elbow', (
    tester,
  ) async {
    await tester.pumpWidget(subject(bubbleMessages: true));
    await tester.pump();

    expect(hasReplyLine(tester), isFalse);
    expect(find.text('Forwarded from $_label'), findsOneWidget);
    expect(find.text(_id), findsOneWidget);
  });

  testWidgets('it is not tappable in either mode', (tester) async {
    // Deliberate: a reply resolves to a real event in this room and can jump
    // to it. A forward has no relation to a source event, and the named author
    // is the sender's claim rather than a verified one - an affordance would
    // say otherwise.
    for (final bubbles in [true, false]) {
      await tester.pumpWidget(subject(bubbleMessages: bubbles));
      await tester.pump();

      expect(find.byType(InkWell), findsNothing);
      expect(find.byType(GestureDetector), findsNothing);
    }
  });

  testWidgets('a right-aligned bubble keeps its own inset', (tester) async {
    // Measured, not just present. A left-aligned capsule is inset to clear the
    // avatar column beside it; a right-aligned one has no avatar to clear and
    // is held off the opposite edge instead. Asserting only that the text
    // renders passes with alignRight ignored entirely.
    await tester.pumpWidget(subject(bubbleMessages: true));
    await tester.pump();
    final leftAligned = capsuleRect(tester);

    await tester.pumpWidget(subject(bubbleMessages: true, alignRight: true));
    await tester.pump();
    final rightAligned = capsuleRect(tester);

    expect(find.text('Forwarded from $_label'), findsOneWidget);
    expect(
      rightAligned.left,
      lessThan(leftAligned.left),
      reason:
          'the left inset exists to clear the avatar column, which a '
          'right-aligned bubble does not have',
    );
    expect(
      rightAligned.right,
      lessThan(leftAligned.right),
      reason:
          'a right-aligned capsule is held off the trailing edge; without it '
          'the capsule sits flush against the bubble',
    );
  });
}
