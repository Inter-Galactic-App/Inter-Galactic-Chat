import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/ui/pages/settings/categories/space/space_soundboard_settings_page.dart';

import '../../../../../client/components/soundboard/soundboard_pack_test_fakes.dart';

void main() {
  Future<FakePackSoundboardComponent> pumpPage(
    WidgetTester tester, {
    bool admin = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final component = FakePackSoundboardComponent()..admin = admin;
    (component.space as FakePackSpace).soundboard = component;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 760,
              child: SpaceSoundboardSettingsPage(space: component.space),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return component;
  }

  testWidgets('packs start collapsed and expand independently', (tester) async {
    await pumpPage(tester);

    // Own derived legacy pack and the other member's explicit pack. The legacy
    // name shows twice: its pack-list section header and the upload
    // destination dropdown's default option.
    expect(find.text('Legacy sounds'), findsNWidgets(2));
    expect(find.text('Party pack'), findsOneWidget);
    expect(find.text('Yours'), findsOneWidget);
    expect(find.text('My horn'), findsNothing);
    expect(find.text('Air raid'), findsNothing);

    final partyPackToggle = find.byKey(
      const ValueKey('soundboard-pack-toggle-party-pack'),
    );
    await tester.ensureVisible(partyPackToggle);
    await tester.pump();
    await tester.tap(partyPackToggle);
    await tester.pumpAndSettle();

    expect(find.text('Air raid'), findsOneWidget);
    expect(find.text('My horn'), findsNothing);

    final legacyPackToggle = find.byKey(
      ValueKey(
        'soundboard-pack-toggle-${SoundboardPack.legacyIdForUploader(fakeSelfUser)}',
      ),
    );
    await tester.ensureVisible(legacyPackToggle);
    await tester.pump();
    await tester.tap(legacyPackToggle);
    await tester.pumpAndSettle();

    expect(find.text('My horn'), findsOneWidget);
    expect(find.text('Air raid'), findsOneWidget);

    await tester.tap(partyPackToggle);
    await tester.pumpAndSettle();

    expect(find.text('Air raid'), findsNothing);
    expect(find.text('My horn'), findsOneWidget);

    final switches = tester
        .widgetList<Switch>(find.byType(Switch))
        .map((widget) => widget.value)
        .toList();
    // Own legacy pack active, other member's pack inactive by default (R7).
    expect(switches, containsAll([true, false]));
  });

  testWidgets('numbered captions distinguish two derived legacy packs', (
    tester,
  ) async {
    final component = await pumpPage(tester);
    component.sounds2.add(
      fakeSound(
        'other-legacy',
        name: 'Other legacy sound',
        uploadedBy: fakeOtherUser,
      ),
    );
    component.emitChanged();
    await tester.pumpAndSettle();

    expect(find.text('Legacy sounds 1'), findsWidgets);
    expect(find.text('Legacy sounds 2'), findsWidgets);
    expect(find.text('Legacy sounds'), findsNothing);
  });

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
  }

  testWidgets('creates a pack from the name field and rejects empty names', (
    tester,
  ) async {
    final component = await pumpPage(tester);

    await tapVisible(
      tester,
      find.byKey(const ValueKey('soundboard-create-pack')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(component.createdPackNames, isEmpty);
    expect(find.text('Add a name for this pack.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('soundboard-create-pack-name')),
      '  Meme drawer  ',
    );
    await tapVisible(
      tester,
      find.byKey(const ValueKey('soundboard-create-pack')),
    );
    await tester.pumpAndSettle();

    expect(component.createdPackNames, ['Meme drawer']);
    expect(find.text('Meme drawer'), findsOneWidget);
  });

  testWidgets('activation switch writes only personal state (R8)', (
    tester,
  ) async {
    final component = await pumpPage(tester);

    // The other member's pack switch is the inactive one.
    final partySwitch = find.byWidgetPredicate(
      (widget) => widget is Switch && widget.value == false,
    );
    await tapVisible(tester, partySwitch);
    await tester.pumpAndSettle();

    expect(component.activeOverrides['party-pack'], isTrue);
    // Shared pack state untouched.
    expect(component.explicitPacks['party-pack']!.enabled, isTrue);
  });

  testWidgets('manage menu is hidden without permission and shown for admins', (
    tester,
  ) async {
    await pumpPage(tester);
    // Non-admin: only own packs get a menu; the other member's pack none.
    expect(
      find.byKey(const ValueKey('soundboard-pack-menu-party-pack')),
      findsNothing,
    );

    await pumpPage(tester, admin: true);
    expect(
      find.byKey(const ValueKey('soundboard-pack-menu-party-pack')),
      findsOneWidget,
    );
  });

  testWidgets(
    'deleting a pack requires the counted destructive confirmation (AE7)',
    (tester) async {
      final component = await pumpPage(tester, admin: true);

      await tapVisible(
        tester,
        find.byKey(const ValueKey('soundboard-pack-menu-party-pack')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete pack…'));
      await tester.pumpAndSettle();

      // Confirmation names the contained-sound count.
      expect(find.textContaining('1 sound'), findsWidgets);

      // Canceling preserves the pack and its contents; it remains visually
      // collapsed until its own disclosure control is activated.
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(component.deletedPackIds, isEmpty);
      expect(component.soundsInPack('party-pack'), isNotEmpty);
      expect(find.text('Air raid'), findsNothing);

      // Confirming removes the pack and its sounds.
      await tapVisible(
        tester,
        find.byKey(const ValueKey('soundboard-pack-menu-party-pack')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete pack…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete pack'));
      await tester.pumpAndSettle();

      expect(component.deletedPackIds, ['party-pack']);
      expect(find.text('Party pack'), findsNothing);
      expect(find.text('Air raid'), findsNothing);
    },
  );

  testWidgets('moving a sound reuses the existing audio (R3)', (tester) async {
    final component = await pumpPage(tester);
    await component.createPack('Target pack');
    await tester.pumpAndSettle();

    // Move own sound from the legacy pack into the new pack.
    await tapVisible(
      tester,
      find.byKey(
        ValueKey(
          'soundboard-pack-toggle-${SoundboardPack.legacyIdForUploader(fakeSelfUser)}',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byTooltip('Move to pack').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Target pack'));
    await tester.pumpAndSettle();

    expect(component.moves, [('self-horn', 'pack-1')]);
    expect(
      component.sounds.singleWhere((sound) => sound.id == 'self-horn').packId,
      'pack-1',
    );
  });

  testWidgets('upload destination picker offers manageable packs', (
    tester,
  ) async {
    final component = await pumpPage(tester);
    await component.createPack('Target pack');
    await tester.pumpAndSettle();

    expect(find.text('Add to pack'), findsOneWidget);
    // Default destination is the uploader's own legacy bucket, shown by its
    // current name (consistent with the pack list) rather than a fixed label.
    // Appears twice: section header + dropdown default.
    expect(find.text('Legacy sounds'), findsNWidgets(2));
  });

  testWidgets('renaming the legacy pack updates the upload destination label', (
    tester,
  ) async {
    final component = await pumpPage(tester);

    // Regression: the default "add to pack" option used to be a hardcoded
    // label, so renaming the uploader's legacy pack never showed here. After
    // rename the new name replaces the old one in both the section header and
    // the upload dropdown.
    final legacyPack = component.packs.firstWhere((pack) => pack.isLegacy);
    await component.renamePack(legacyPack, 'My Faves');
    component.emitChanged();
    await tester.pumpAndSettle();

    expect(find.text('My Faves'), findsNWidgets(2));
    expect(find.text('Legacy sounds'), findsNothing);
  });

  testWidgets('pack manage menu offers set/remove icon and clears it', (
    tester,
  ) async {
    final component = await pumpPage(tester, admin: true);

    // Give the other member's (admin-manageable) pack an icon so both the
    // "Change icon…" and "Remove icon" actions are present.
    component.explicitPacks['party-pack'] = component
        .explicitPacks['party-pack']!
        .copyWith(emoji: ':star:');
    component.emitChanged();
    await tester.pumpAndSettle();

    await tapVisible(
      tester,
      find.byKey(const ValueKey('soundboard-pack-menu-party-pack')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Change icon…'), findsOneWidget);
    await tester.tap(find.text('Remove icon'));
    await tester.pumpAndSettle();

    expect(component.packEmojiWrites, contains(('party-pack', null)));
  });
}
