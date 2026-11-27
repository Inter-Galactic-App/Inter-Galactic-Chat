import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiamat/atoms/popup_dialog.dart';

void main() {
  testWidgets('popup dialog accepts LayoutBuilder content', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                PopupDialog.show<void>(
                  context,
                  title: 'Add event',
                  content: LayoutBuilder(
                    builder: (context, constraints) {
                      return SizedBox(
                        width: constraints.maxWidth.isFinite
                            ? constraints.maxWidth
                            : 320,
                        height: 160,
                        child: const Text('Calendar editor content'),
                      );
                    },
                  ),
                );
              },
              child: const Text('Open dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Calendar editor content'), findsOneWidget);
  });

  testWidgets('popup dialog exposes a meaningful barrier label',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                PopupDialog.show<void>(
                  context,
                  title: 'Delete room',
                  barrierLabel: 'Dismiss delete room dialog',
                  content: const Text('This action removes the room.'),
                );
              },
              child: const Text('Open dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ModalBarrier &&
            widget.semanticsLabel == 'Dismiss delete room dialog',
      ),
      findsOneWidget,
    );
    expect(find.text('This action removes the room.'), findsOneWidget);
  });

  testWidgets('popup dialog skips slide transition when motion is disabled',
      (tester) async {
    Duration? routeTransitionDuration;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () {
                  PopupDialog.show<void>(
                    context,
                    title: 'Reduced motion dialog',
                    content: Builder(
                      builder: (context) {
                        routeTransitionDuration =
                            ModalRoute.of(context)?.transitionDuration;
                        return const Text('No slide transition');
                      },
                    ),
                  );
                },
                child: const Text('Open dialog'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open dialog'));
    await tester.pump();

    expect(find.text('No slide transition'), findsOneWidget);
    expect(routeTransitionDuration, Duration.zero);
  });

  testWidgets('popup dialog accepts an app-level reduced motion override',
      (tester) async {
    Duration? routeTransitionDuration;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                PopupDialog.show<void>(
                  context,
                  title: 'App reduced motion dialog',
                  reduceMotion: true,
                  content: Builder(
                    builder: (context) {
                      routeTransitionDuration =
                          ModalRoute.of(context)?.transitionDuration;
                      return const Text('Override skips transition');
                    },
                  ),
                );
              },
              child: const Text('Open dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open dialog'));
    await tester.pump();

    expect(find.text('Override skips transition'), findsOneWidget);
    expect(routeTransitionDuration, Duration.zero);
  });
}
