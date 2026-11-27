import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/soundboard_settings_page.dart';

void main() {
  SoundboardSound sound(String name) => SoundboardSound(
    id: 'air-raid',
    name: name,
    emoji: '🔊',
    mxcUri: Uri.parse('mxc://example.org/air-raid'),
    mimeType: 'audio/ogg',
    uploadedBy: '@nick:example.org',
    createdAt: DateTime.utc(2026, 8, 11),
    sizeBytes: 100,
  );

  testWidgets('preview tile is an accessible in-call-style play button', (
    tester,
  ) async {
    var playCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: SoundboardPreviewTile(
              sound: sound('Air raid'),
              emojiPacks: const [],
              onPressed: () => playCount++,
            ),
          ),
        ),
      ),
    );

    final playSemantics = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label == 'Play Air raid' &&
          widget.properties.button == true,
    );
    expect(playSemantics, findsOneWidget);
    expect(
      tester.widget<Text>(find.text('Air raid')).style?.fontWeight,
      FontWeight.w700,
    );

    await tester.tap(find.byType(InkWell));
    expect(playCount, 1);
  });
}
