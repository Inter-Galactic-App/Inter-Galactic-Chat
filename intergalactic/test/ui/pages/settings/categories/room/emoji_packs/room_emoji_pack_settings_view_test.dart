import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/room_emoji_pack_settings_view.dart';

void main() {
  testWidgets('disables item moves while the previous reorder is saving', (
    tester,
  ) async {
    final pack = _DeferredReorderPack([
      const _FakeEmoticon('first'),
      const _FakeEmoticon('second'),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EmoticonPackEditor(pack: pack, editable: true)),
      ),
    );

    await tester.tap(find.byTooltip('Move second up'));
    await tester.pump();
    await tester.tap(find.byTooltip('Move first up'));

    expect(pack.reorderCalls, hasLength(1));
    pack.completeReorder();
    await tester.pump();
  });
}

class _DeferredReorderPack implements EmoticonPack {
  _DeferredReorderPack(this._emotes);

  final List<Emoticon> _emotes;
  final List<List<String>> reorderCalls = [];
  final Completer<void> _reorderCompleter = Completer<void>();

  // Unmodifiable on purpose, matching the real packs: DemoEmoticonPack.emotes
  // is List.unmodifiable(_emotes), and the Matrix packs expose their backing
  // list the same way. A mutable list here let the view mutate the pack's own
  // collection in place, so the reorder crash this file covers could not
  // reproduce - the fake was more permissive than anything in production.
  @override
  List<Emoticon> get emotes => List.unmodifiable(_emotes);

  @override
  List<String> getShortcodes() => _emotes
      .map((emoticon) => emoticon.shortcode ?? emoticon.slug)
      .toList(growable: false);

  @override
  Future<void> reorderEmoticons(List<String> shortcodes) {
    reorderCalls.add(shortcodes);
    return _reorderCompleter.future;
  }

  void completeReorder() => _reorderCompleter.complete();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeEmoticon implements Emoticon {
  const _FakeEmoticon(this.shortcode);

  @override
  final String shortcode;

  @override
  ImageProvider? get image => null;

  @override
  bool get isEmoji => true;

  @override
  bool get isSticker => false;

  @override
  String get key => shortcode;

  @override
  String get slug => shortcode;

  @override
  EmoticonUsage get usage => EmoticonUsage.emoji;
}
