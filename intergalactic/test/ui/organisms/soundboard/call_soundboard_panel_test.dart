import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/ui/organisms/soundboard/call_soundboard_panel.dart';

import '../../../client/components/soundboard/soundboard_pack_test_fakes.dart';

void main() {
  Future<FakePackSoundboardComponent> pumpMenu(
    WidgetTester tester, {
    List<SoundboardSound> played = const [],
  }) async {
    final component = FakePackSoundboardComponent();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 620,
            height: 520,
            child: CallSoundboardMenu(
              soundboard: component,
              onSoundPressed: (_, sound) => played.add(sound),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return component;
  }

  testWidgets(
    'creator sees their own pack sounds without any enablement write (AE1)',
    (tester) async {
      await pumpMenu(tester);

      expect(find.text('My horn'), findsOneWidget);
      // The other member's discoverable-but-inactive pack stays out of the
      // main picker.
      expect(find.text('Air raid'), findsNothing);
      expect(find.text('Party pack'), findsNothing);
    },
  );

  testWidgets('enabling a pack adds its sounds; disabling removes them (R8)', (
    tester,
  ) async {
    final component = await pumpMenu(tester);

    component.activeOverrides['party-pack'] = true;
    component.emitChanged();
    await tester.pumpAndSettle();

    expect(find.text('Air raid'), findsOneWidget);
    expect(find.text('Party pack'), findsOneWidget);

    component.activeOverrides['party-pack'] = false;
    component.emitChanged();
    await tester.pumpAndSettle();

    expect(find.text('Air raid'), findsNothing);
    expect(find.text('Party pack'), findsNothing);
    // Disabling never deletes content.
    expect(component.soundsInPack('party-pack'), isNotEmpty);
  });

  testWidgets('packs render as sections in the body, not rail buttons', (
    tester,
  ) async {
    final component = await pumpMenu(tester);
    component.activeOverrides['party-pack'] = true;
    component.emitChanged();
    await tester.pumpAndSettle();

    // The rail keeps the space; packs are body sections beneath it.
    expect(
      find.byKey(const ValueKey('soundboard-space-source-rail')),
      findsOneWidget,
    );
    expect(find.text('Party pack'), findsOneWidget);
    expect(find.text('Legacy sounds'), findsOneWidget);
    expect(find.text('My horn'), findsOneWidget);
    expect(find.text('Air raid'), findsOneWidget);
  });

  testWidgets('numbered captions distinguish two derived legacy packs', (
    tester,
  ) async {
    final component = await pumpMenu(tester);
    final otherLegacyId = SoundboardPack.legacyIdForUploader(fakeOtherUser);
    component.sounds2.add(
      fakeSound(
        'other-legacy',
        name: 'Other legacy sound',
        uploadedBy: fakeOtherUser,
      ),
    );
    component.activeOverrides[otherLegacyId] = true;
    component.emitChanged();
    await tester.pumpAndSettle();

    expect(find.text('Legacy sounds 1'), findsOneWidget);
    expect(find.text('Legacy sounds 2'), findsOneWidget);
    expect(find.text('Legacy sounds'), findsNothing);
  });

  testWidgets('collapsing a pack section hides only its own sounds', (
    tester,
  ) async {
    final component = await pumpMenu(tester);
    component.activeOverrides['party-pack'] = true;
    component.emitChanged();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Party pack'));
    await tester.pumpAndSettle();

    // The header stays so the section can be reopened; its sounds are hidden
    // while the other pack is untouched.
    expect(find.text('Party pack'), findsOneWidget);
    expect(find.text('Air raid'), findsNothing);
    expect(find.text('My horn'), findsOneWidget);

    await tester.tap(find.text('Party pack'));
    await tester.pumpAndSettle();

    expect(find.text('Air raid'), findsOneWidget);
  });

  testWidgets('search reveals matches inside a collapsed pack', (tester) async {
    final component = await pumpMenu(tester);
    component.activeOverrides['party-pack'] = true;
    component.emitChanged();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Party pack'));
    await tester.pumpAndSettle();
    expect(find.text('Air raid'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Air');
    await tester.pumpAndSettle();

    // A search force-expands matching sections, and non-matching packs drop
    // out rather than leaving empty headers.
    expect(find.text('Air raid'), findsOneWidget);
    expect(find.text('Party pack'), findsOneWidget);
    expect(find.text('Legacy sounds'), findsNothing);
  });

  testWidgets('same-named sounds in different packs stay distinct', (
    tester,
  ) async {
    final component = await pumpMenu(tester);
    component.activeOverrides['party-pack'] = true;
    component.sounds2.add(
      fakeSound('dup-1', name: 'Fanfare', uploadedBy: fakeSelfUser),
    );
    component.sounds2.add(
      fakeSound(
        'dup-2',
        name: 'Fanfare',
        uploadedBy: fakeOtherUser,
        packId: 'party-pack',
      ),
    );
    component.emitChanged();
    await tester.pumpAndSettle();

    expect(find.text('Fanfare'), findsNWidgets(2));
  });

  testWidgets('search filters active sounds', (tester) async {
    await pumpMenu(tester);

    await tester.enterText(find.byType(TextField), 'horn');
    await tester.pump();
    expect(find.text('My horn'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('My horn'), findsNothing);
    expect(find.text('No matching sounds'), findsOneWidget);
  });

  testWidgets(
    'no active packs shows the pack-discovery empty state, not the legacy '
    'no-sounds message',
    (tester) async {
      final component = await pumpMenu(tester);
      component.activeOverrides[SoundboardPack.legacyIdForUploader(
            fakeSelfUser,
          )] =
          false;
      component.emitChanged();
      await tester.pumpAndSettle();

      expect(find.textContaining('No active sound packs'), findsOneWidget);
      // pumpMenu passes no onAddSoundPressed, so hasAddAction is false and this
      // menu shows no + button: the empty state must not tell the user to
      // "Use +" (regression guard for the pack-discovery message).
      expect(find.textContaining('+'), findsNothing);
    },
  );

  testWidgets('tapping a tile reports the sound', (tester) async {
    final played = <SoundboardSound>[];
    await pumpMenu(tester, played: played);

    await tester.tap(find.text('My horn'));
    await tester.pump();

    expect(played.map((sound) => sound.id), ['self-horn']);
  });
}
