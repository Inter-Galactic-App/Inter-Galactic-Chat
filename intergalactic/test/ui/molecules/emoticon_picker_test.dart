import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/gif/gif_component.dart';
import 'package:intergalactic/client/components/gif/gif_search_result.dart';
import 'package:intergalactic/ui/molecules/emoticon_picker.dart';

void main() {
  // The picker rebuilds its TabController in didUpdateWidget whenever the tab
  // set changes. `controller` is private state, so selection is read back off
  // the TabBarView the picker always renders, and the captions are read off the
  // TabBar so every index assertion is anchored to a label rather than a bare
  // number.
  int selectedTabIndex(WidgetTester tester) =>
      tester.widget<TabBarView>(find.byType(TabBarView)).controller!.index;

  List<String> tabLabels(WidgetTester tester) => tester
      .widgetList<Tab>(
        find.descendant(of: find.byType(TabBar), matching: find.byType(Tab)),
      )
      .map((tab) => tab.text!)
      .toList(growable: false);

  String selectedTabLabel(WidgetTester tester) =>
      tabLabels(tester)[selectedTabIndex(tester)];

  Widget buildPicker({
    required bool allowGifSearch,
    required List<EmoticonPack> stickers,
    GifComponent? gifComponent,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 480,
          child: EmoticonPicker(
            emoji: const [],
            stickers: stickers,
            allowGifSearch: allowGifSearch,
            gifComponent: gifComponent,
          ),
        ),
      ),
    );
  }

  testWidgets('recreates tabs when GIF search becomes available', (
    tester,
  ) async {
    final gifComponent = _FakeGifComponent();

    await tester.pumpWidget(
      buildPicker(
        allowGifSearch: false,
        stickers: const [],
        gifComponent: gifComponent,
      ),
    );
    expect(find.text('GIFs'), findsNothing);

    await tester.pumpWidget(
      buildPicker(
        allowGifSearch: true,
        stickers: const [],
        gifComponent: gifComponent,
      ),
    );
    await tester.pump();

    expect(find.text('GIFs'), findsOneWidget);
    await tester.tap(find.text('GIFs'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the selected tab when another tab is added', (
    tester,
  ) async {
    final gifComponent = _FakeGifComponent();
    final stickers = <EmoticonPack>[_FakeStickerPack()];

    // Desktop tab order without GIFs: [Stickers, Emoji].
    await tester.pumpWidget(
      buildPicker(
        allowGifSearch: false,
        stickers: stickers,
        gifComponent: gifComponent,
      ),
    );
    expect(tabLabels(tester), ['Stickers', 'Emoji']);

    await tester.tap(find.text('Stickers'));
    await tester.pumpAndSettle();
    expect(selectedTabIndex(tester), 0);

    // Adding GIFs prepends a tab on desktop, so Stickers shifts from index 0 to
    // index 1. Rebuilding the controller at the default index would silently
    // drop the user back onto Emoji here.
    await tester.pumpWidget(
      buildPicker(
        allowGifSearch: true,
        stickers: stickers,
        gifComponent: gifComponent,
      ),
    );
    await tester.pump();

    expect(tabLabels(tester), ['GIFs', 'Stickers', 'Emoji']);
    expect(selectedTabLabel(tester), 'Stickers');
    expect(selectedTabIndex(tester), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'falls back to a valid tab when the selected GIF tab is removed',
    (tester) async {
      final gifComponent = _FakeGifComponent();
      final stickers = <EmoticonPack>[_FakeStickerPack()];

      await tester.pumpWidget(
        buildPicker(
          allowGifSearch: true,
          stickers: stickers,
          gifComponent: gifComponent,
        ),
      );
      expect(tabLabels(tester), ['GIFs', 'Stickers', 'Emoji']);

      await tester.tap(find.text('GIFs'));
      // Bounded pumps rather than pumpAndSettle: the GIF tab shows a loading
      // indicator that animates forever, so the tree never reaches quiescence
      // and pumpAndSettle times out. The other two cases in this file tap
      // Stickers and Emoji, which do settle - which is why only this one
      // needed it. 400ms clears the tab indicator animation.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(selectedTabIndex(tester), 0);

      // The selected tab type disappears entirely, so there is nothing to
      // restore. Carrying the old index across would leave Stickers selected -
      // in range, so it fails silently rather than asserting.
      await tester.pumpWidget(
        buildPicker(
          allowGifSearch: false,
          stickers: stickers,
          gifComponent: gifComponent,
        ),
      );
      await tester.pump();

      expect(tabLabels(tester), ['Stickers', 'Emoji']);
      expect(selectedTabLabel(tester), 'Emoji');
      expect(selectedTabIndex(tester), 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('restores the selected tab when an earlier tab is removed', (
    tester,
  ) async {
    final gifComponent = _FakeGifComponent();

    await tester.pumpWidget(
      buildPicker(
        allowGifSearch: true,
        stickers: <EmoticonPack>[_FakeStickerPack()],
        gifComponent: gifComponent,
      ),
    );
    expect(tabLabels(tester), ['GIFs', 'Stickers', 'Emoji']);

    await tester.tap(find.text('Emoji'));
    await tester.pumpAndSettle();
    expect(selectedTabIndex(tester), 2);

    // Dropping the last sticker pack removes the middle tab while Emoji is
    // selected at index 2, which is past the end of the two-tab list that
    // follows. Selection has to be re-resolved by tab type, not by index.
    await tester.pumpWidget(
      buildPicker(
        allowGifSearch: true,
        stickers: const [],
        gifComponent: gifComponent,
      ),
    );
    await tester.pump();

    expect(tabLabels(tester), ['GIFs', 'Emoji']);
    expect(selectedTabLabel(tester), 'Emoji');
    expect(selectedTabIndex(tester), 1);
    expect(tester.takeException(), isNull);
  });
}

class _FakeGifComponent implements GifComponent {
  @override
  String get searchPlaceholder => 'Search GIFs';

  @override
  Future<List<GifSearchResult>> search(String query) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// An emote-free pack: the picker only needs `stickers` to be non-empty for the
/// sticker tab to exist, and an empty pack keeps the page cheap to paint.
class _FakeStickerPack implements EmoticonPack {
  @override
  String get identifier => 'fake-stickers';

  @override
  String get displayName => 'Fake stickers';

  @override
  String get attribution => '';

  @override
  String get ownerId => '@user:example.org';

  @override
  String get ownerDisplayName => 'Fake owner';

  @override
  String get orderKey => '$ownerId\u0000$identifier';

  @override
  bool get isGloballyAvailable => false;

  @override
  List<Emoticon> get emotes => const [];

  @override
  List<Emoticon> get emoji => const [];

  @override
  List<Emoticon> get stickers => const [];

  @override
  List<String> getShortcodes() => const [];

  @override
  ImageProvider? get image => null;

  @override
  IconData? get icon => Icons.emoji_emotions_rounded;

  @override
  EmoticonUsage get usage => EmoticonUsage.sticker;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
