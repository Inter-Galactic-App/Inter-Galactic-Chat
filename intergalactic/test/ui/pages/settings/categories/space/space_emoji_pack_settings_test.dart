import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_component.dart';
import 'package:intergalactic/client/components/space_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';
import 'package:intergalactic/client/permissions.dart';
import 'package:intergalactic/ui/pages/settings/categories/space/space_admin_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/space/space_emoji_pack_settings.dart';

void main() {
  testWidgets('repair action reports completed and skipped room links', (
    tester,
  ) async {
    final space = _Space();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SpaceImagePackAccessSettings(space: space),
          ),
        ),
      ),
    );

    expect(find.text('Repair links'), findsOneWidget);
    await tester.tap(find.text('Repair links'));
    await tester.pumpAndSettle();

    expect(space.repairCalls, 1);
    expect(find.textContaining('1 room links repaired'), findsOneWidget);
    expect(find.textContaining('1 kept another primary Space'), findsOneWidget);
  });

  testWidgets('non-admin cannot see the repair action', (tester) async {
    final space = _Space(isAdmin: false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SpaceImagePackAccessSettings(space: space)),
      ),
    );

    expect(find.text('Repair links'), findsNothing);
    expect(space.repairCalls, 0);
  });

  testWidgets('image-pack editor no longer exposes the repair action', (
    tester,
  ) async {
    final space = _Space();
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: SpaceEmojiPackSettings(space))),
    );

    expect(find.text('Repair links'), findsNothing);
  });
}

class _Space implements MatrixSpace {
  _Space({this.isAdmin = true});

  final bool isAdmin;
  final _component = _Emoticons();
  int repairCalls = 0;

  @override
  Permissions get permissions => _Permissions();

  @override
  bool get canRepairImagePackParentLinks => isAdmin;

  @override
  T? getComponent<T extends SpaceComponent>() => _component as T?;

  @override
  Future<SpaceImagePackRepairResult> repairImagePackParentLinks() async {
    repairCalls++;
    return SpaceImagePackRepairResult()
      ..repaired = 1
      ..otherCanonicalParent = 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Permissions extends Permissions {
  @override
  bool get canEditChildren => true;
}

class _Emoticons implements SpaceEmoticonComponent<MatrixClient, MatrixSpace> {
  final _updates = StreamController<void>.broadcast();

  @override
  List<EmoticonPack> get ownedPacks => const [];

  @override
  bool get canCreatePack => false;

  @override
  Stream<void> get onStateChanged => _updates.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
