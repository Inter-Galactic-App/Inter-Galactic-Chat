import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_component.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/emoticons_settings_page.dart';

void main() {
  // The control is optimistic: it reorders locally, persists to Matrix account
  // data, and rolls back if that write fails. Order is read back off the
  // rendered ListTile titles so the assertions describe what a user sees.
  List<String> visibleOrder(WidgetTester tester) => tester
      .widgetList<ListTile>(find.byType(ListTile))
      .map((tile) => (tile.title! as Text).data!)
      .toList(growable: false);

  // `find.byTooltip` resolves to the Tooltip IconButton builds beneath itself,
  // so the button carrying `onPressed` is its ancestor.
  bool moveEnabled(WidgetTester tester, String tooltip) =>
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip(tooltip),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed !=
      null;

  Future<void> pumpOrderList(
    WidgetTester tester,
    EmoticonComponent component,
    List<EmoticonPack> packs,
  ) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PickerPackOrderList(component: component, initialPacks: packs),
        ),
      ),
    );
  }

  testWidgets('submits the reordered pack keys', (tester) async {
    final component = _RecordingEmoticonComponent();
    final packs = <EmoticonPack>[
      _OrderPack('Alpha'),
      _OrderPack('Beta'),
      _OrderPack('Gamma'),
    ];

    await pumpOrderList(tester, component, packs);
    expect(visibleOrder(tester), ['Alpha', 'Beta', 'Gamma']);

    await tester.tap(find.byTooltip('Move Beta up'));
    await tester.pump();

    // The persisted payload must be the NEW order, keyed by orderKey rather
    // than by display name or list index.
    expect(component.calls, hasLength(1));
    expect(component.calls.single, ['key:Beta', 'key:Alpha', 'key:Gamma']);
    expect(visibleOrder(tester), ['Beta', 'Alpha', 'Gamma']);
  });

  testWidgets('disables the move controls while a save is in flight', (
    tester,
  ) async {
    final component = _RecordingEmoticonComponent(defer: true);
    final packs = <EmoticonPack>[
      _OrderPack('Alpha'),
      _OrderPack('Beta'),
      _OrderPack('Gamma'),
    ];

    await pumpOrderList(tester, component, packs);
    expect(moveEnabled(tester, 'Move Beta up'), isTrue);

    await tester.tap(find.byTooltip('Move Beta up'));
    await tester.pump();

    // Order is now [Beta, Alpha, Gamma]. Both of these would be enabled on
    // position alone, so their being disabled is the in-flight guard and not
    // the first/last-row guard.
    expect(moveEnabled(tester, 'Move Alpha up'), isFalse);
    expect(moveEnabled(tester, 'Move Beta down'), isFalse);

    // A second tap while saving must not queue another write.
    await tester.tap(find.byTooltip('Move Gamma up'), warnIfMissed: false);
    await tester.pump();
    expect(component.calls, hasLength(1));

    component.completer.complete();
    await tester.pump();
    expect(moveEnabled(tester, 'Move Alpha up'), isTrue);
  });

  testWidgets('rolls back and reports when the save fails', (tester) async {
    final component = _RecordingEmoticonComponent(
      error: Exception('account data write rejected'),
    );
    final packs = <EmoticonPack>[
      _OrderPack('Alpha'),
      _OrderPack('Beta'),
      _OrderPack('Gamma'),
    ];

    await pumpOrderList(tester, component, packs);

    await tester.tap(find.byTooltip('Move Gamma up'));
    await tester.pump();
    await tester.pump();

    expect(component.calls, hasLength(1));
    expect(visibleOrder(tester), ['Alpha', 'Beta', 'Gamma']);
    expect(find.text('Could not save picker order.'), findsOneWidget);

    // The control has to be usable again after a failure, not stuck saving.
    expect(moveEnabled(tester, 'Move Gamma up'), isTrue);
  });
}

class _RecordingEmoticonComponent implements EmoticonComponent {
  _RecordingEmoticonComponent({this.defer = false, this.error});

  final bool defer;
  final Object? error;
  final List<List<String>> calls = [];
  final Completer<void> completer = Completer<void>();

  @override
  Future<void> setPackOrder(List<String> orderKeys) async {
    calls.add(orderKeys);
    if (defer) {
      await completer.future;
    }
    final error = this.error;
    if (error != null) {
      throw error;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _OrderPack implements EmoticonPack {
  _OrderPack(this.displayName);

  @override
  final String displayName;

  @override
  String get identifier => displayName.toLowerCase();

  @override
  String get attribution => '';

  @override
  String get ownerId => '@user:example.org';

  @override
  String get ownerDisplayName => 'Fake owner';

  @override
  String get orderKey => 'key:$displayName';

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
  EmoticonUsage get usage => EmoticonUsage.emoji;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
