import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/space_component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_library_component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/ui/organisms/soundboard/call_soundboard_panel.dart';

/// U7 call-picker integration: a pack enabled globally from space A has to be
/// offered inside a call hosted by space B, and playing it has to go through
/// space A's component - that is where the cross-space authorization is minted.
///
/// Without this the rest of U7 is unreachable from the app: the protocol works
/// but nothing can invoke it.

const _destinationSpaceId = '!destination:example.org';
const _sourceSpaceId = '!source:example.org';
const _selfUser = '@alice:example.org';

SoundboardSound _sound(String id, {required String name, String? packId}) =>
    SoundboardSound(
      id: id,
      name: name,
      emoji: 'x',
      mxcUri: Uri.parse('mxc://example.org/$id'),
      mimeType: 'audio/ogg',
      uploadedBy: _selfUser,
      createdAt: DateTime.utc(2026, 7, 1),
      sizeBytes: 1000,
      packId: packId,
    );

SoundboardPack _pack(String id, String name) => SoundboardPack(
  id: id,
  name: name,
  createdBy: _selfUser,
  createdAt: DateTime.utc(2026, 7, 1),
  updatedAt: DateTime.utc(2026, 7, 1),
);

void main() {
  late _FakeClient client;
  late _FakeSoundboard destination;
  late _FakeSoundboard source;
  late _FakeLibrary library;

  setUp(() {
    client = _FakeClient();
    destination =
        _FakeSoundboard(
          client,
          _FakeSpace(_destinationSpaceId, 'Destination Space'),
        )..configure(
          packs: [_pack('local-pack', 'Local pack')],
          sounds: [_sound('local-1', name: 'Local horn', packId: 'local-pack')],
        );
    source = _FakeSoundboard(client, _FakeSpace(_sourceSpaceId, 'Source Space'))
      ..configure(
        packs: [_pack('remote-pack', 'Remote pack')],
        sounds: [
          _sound('remote-1', name: 'Remote horn', packId: 'remote-pack'),
        ],
      );
    client.spaceList = [destination.space, source.space];
    (destination.space as _FakeSpace).soundboard = destination;
    (source.space as _FakeSpace).soundboard = source;
    library = _FakeLibrary(client);
  });

  List<SoundboardCallPack> collect() =>
      collectCallSoundboardPacks(destination: destination, library: library);

  SoundboardGlobalPackEntry entry({
    String sourceSpaceId = _sourceSpaceId,
    String packId = 'remote-pack',
    String? spaceName = 'Source Space',
    SoundboardPack? pack,
    List<SoundboardSound>? sounds,
  }) => SoundboardGlobalPackEntry(
    reference: SoundboardGlobalPackReference(
      sourceSpaceId: sourceSpaceId,
      packId: packId,
    ),
    sourceSpaceName: spaceName,
    pack: pack ?? _pack(packId, 'Remote pack'),
    sounds: sounds ?? [_sound('remote-1', name: 'Remote horn', packId: packId)],
  );

  group('pack collection', () {
    test('the destination space\'s own active packs are offered as before', () {
      library.entryList = [];

      final packs = collect();

      expect(packs, hasLength(1));
      expect(packs.single.pack.id, 'local-pack');
      expect(packs.single.isExternal, isFalse);
      expect(packs.single.owner, same(destination));
    });

    test('a globally enabled pack from another space is offered too', () {
      // The reported symptom: enabled in space A, allowed in space B, and yet
      // absent from the in-call picker.
      library.entryList = [entry()];

      final packs = collect();

      expect(packs.map((p) => p.pack.id), ['local-pack', 'remote-pack']);
      final external = packs.last;
      expect(external.isExternal, isTrue);
      expect(external.sourceSpaceName, 'Source Space');
      expect(external.sounds.single.id, 'remote-1');
    });

    test('the external pack is owned by the SOURCE component, not the '
        'destination', () {
      // The whole point: playing it must run through the space that can mint an
      // authorization for it.
      library.entryList = [entry()];

      expect(collect().last.owner, same(source));
    });

    test('a destination that blocks external packs offers none of them', () {
      // The administrator's switch has to bite on the sender side too, or the
      // picker composes a play every receiver would refuse.
      library.entryList = [entry()];
      destination.policy = const SoundboardDestinationPolicy(
        allowExternalPacks: false,
      );

      final packs = collect();

      expect(packs.map((p) => p.pack.id), ['local-pack']);
    });

    test('a stale reference is not offered', () {
      // Left space, deleted or disabled pack: the entry stays in the document
      // but must never reach the picker.
      library.entryList = [entry(pack: null, sounds: const [])];

      expect(collect().map((p) => p.pack.id), ['local-pack']);
    });

    test('a globally enabled pack from THIS space is not listed twice', () {
      library.entryList = [
        entry(
          sourceSpaceId: _destinationSpaceId,
          packId: 'local-pack',
          spaceName: 'Destination Space',
        ),
      ];

      final packs = collect();

      expect(packs, hasLength(1));
      expect(packs.single.isExternal, isFalse);
    });

    test('an entry whose source space is not joined is skipped', () {
      // Nothing to play through, so offering it would fail on tap instead.
      library.entryList = [entry(sourceSpaceId: '!gone:example.org')];

      expect(collect().map((p) => p.pack.id), ['local-pack']);
    });

    test('an entry with no available sounds is skipped', () {
      library.entryList = [entry(sounds: const [])];

      expect(collect().map((p) => p.pack.id), ['local-pack']);
    });

    test('a same-id pack from another space is offered alongside the local '
        'one, not dropped', () {
      // The reported symptom: an enabled LEGACY pack never appeared in the
      // picker. Pack ids are unique only within a space, and a legacy pack id
      // is deterministic (legacyIdForUploader), so the member's own legacy pack
      // here and their legacy pack in the source space share an id. Dropping
      // the foreign one on that collision hid it; both are distinct content
      // under distinct rail entries and both must be offered. (Modelled with an
      // explicit shared id; real collisions are always legacy ones.)
      library.entryList = [
        entry(
          packId: 'local-pack',
          sounds: [
            _sound('foreign-1', name: 'Foreign horn', packId: 'local-pack'),
          ],
        ),
      ];

      final packs = collect();

      expect(packs, hasLength(2));
      final local = packs.firstWhere((p) => !p.isExternal);
      final foreign = packs.firstWhere((p) => p.isExternal);
      expect(local.owner, same(destination));
      expect(local.sounds.single.id, 'local-1');
      expect(foreign.owner, same(source));
      expect(foreign.sounds.single.id, 'foreign-1');
      // Distinct identity keys keep their collapse state independent.
      expect(local.identityKey, isNot(foreign.identityKey));
    });

    test('no library at all leaves the picker exactly as it was', () {
      expect(
        collectCallSoundboardPacks(
          destination: destination,
        ).map((p) => p.pack.id),
        ['local-pack'],
      );
    });
  });

  group('source rail', () {
    test('the call\'s own space is always the first entry', () {
      library.entryList = [];

      final sources = collectCallSoundboardSources(
        destination: destination,
        packs: collect(),
      );

      expect(sources, hasLength(1));
      expect(sources.single.spaceId, _destinationSpaceId);
      expect(sources.single.isExternal, isFalse);
    });

    test('each contributing source space earns exactly one entry', () {
      // Two packs from the same space must not produce two rail buttons.
      library.entryList = [
        entry(),
        entry(
          packId: 'remote-pack-2',
          sounds: [
            _sound('remote-2', name: 'Second horn', packId: 'remote-pack-2'),
          ],
        ),
      ];

      final sources = collectCallSoundboardSources(
        destination: destination,
        packs: collect(),
      );

      expect(sources.map((s) => s.spaceId), [
        _destinationSpaceId,
        _sourceSpaceId,
      ]);
      expect(sources.last.name, 'Source Space');
      expect(sources.last.isExternal, isTrue);
    });

    test('a space whose packs were all filtered out earns no entry', () {
      // Otherwise the rail offers a button that selects an empty body.
      library.entryList = [entry()];
      destination.policy = const SoundboardDestinationPolicy(
        allowExternalPacks: false,
      );

      final sources = collectCallSoundboardSources(
        destination: destination,
        packs: collect(),
      );

      expect(sources.map((s) => s.spaceId), [_destinationSpaceId]);
    });
  });

  group('menu rendering', () {
    Future<List<(SoundboardComponent, SoundboardSound)>> pumpMenu(
      WidgetTester tester,
    ) async {
      final pressed = <(SoundboardComponent, SoundboardSound)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 620,
              height: 520,
              child: CallSoundboardMenu(
                soundboard: destination,
                library: library,
                onSoundPressed: (owner, sound) => pressed.add((owner, sound)),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      return pressed;
    }

    testWidgets('the rail separates each space; the body shows one at a time', (
      tester,
    ) async {
      library.entryList = [entry()];
      await pumpMenu(tester);

      // The reported symptom was every space's packs poured into one list. The
      // call's own space is selected first, so its sounds are what shows.
      expect(
        find.byKey(const ValueKey('soundboard-space-source-$_sourceSpaceId')),
        findsOneWidget,
      );
      expect(find.text('Local horn'), findsOneWidget);
      expect(find.text('Remote horn'), findsNothing);
    });

    testWidgets('selecting a source space swaps the body to its packs', (
      tester,
    ) async {
      library.entryList = [entry()];
      final pressed = await pumpMenu(tester);

      await tester.tap(
        find.byKey(const ValueKey('soundboard-space-source-$_sourceSpaceId')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Remote horn'), findsOneWidget);
      expect(find.text('from Source Space'), findsOneWidget);
      expect(find.text('Local horn'), findsNothing);

      await tester.tap(find.text('Remote horn'));
      await tester.pump();

      // Routed to the source component, which is what makes the play
      // authorizable at all.
      expect(pressed.single.$1, same(source));
      expect(pressed.single.$2.id, 'remote-1');
    });

    testWidgets('a search spans every space, not just the selected one', (
      tester,
    ) async {
      // A rail selection must never hide a match behind a button the member has
      // no reason to suspect.
      library.entryList = [entry()];
      await pumpMenu(tester);

      await tester.enterText(find.byType(TextField), 'horn');
      await tester.pumpAndSettle();

      expect(find.text('Local horn'), findsOneWidget);
      expect(find.text('Remote horn'), findsOneWidget);
    });

    testWidgets('the pre-U7 audibility hint shows only while an external pack '
        'is on screen', (tester) async {
      // Temporary sender-side notice: cross-space plays are inaudible to
      // pre-U7 receivers, so the sender is warned whenever the packs on screen
      // include an external one - the local space alone must not trip it.
      //
      // This test comes out in 0.8.2 with the hint it covers, NOT in 0.8.1.
      // Deleting it while the hint still ships would remove the only thing
      // proving the hint is scoped to external packs.
      const hint =
          'Sounds from other spaces may not be heard by everyone in '
          'the call yet.';
      library.entryList = [entry()];
      await pumpMenu(tester);

      // Local space is selected first: no external pack visible, no hint.
      expect(find.text('Local horn'), findsOneWidget);
      expect(find.text(hint), findsNothing);

      // Selecting the external space brings its packs - and the hint - forward.
      await tester.tap(
        find.byKey(const ValueKey('soundboard-space-source-$_sourceSpaceId')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Remote horn'), findsOneWidget);
      expect(find.text(hint), findsOneWidget);

      // A search surfaces the external match too, so the hint rides along.
      await tester.enterText(find.byType(TextField), 'horn');
      await tester.pumpAndSettle();
      expect(find.text(hint), findsOneWidget);
    });

    testWidgets('no hint when the call has no external packs at all', (
      tester,
    ) async {
      library.entryList = [];
      await pumpMenu(tester);

      expect(find.text('Local horn'), findsOneWidget);
      expect(find.textContaining('may not be heard by everyone'), findsNothing);
    });
  });
}

class _FakeClient implements Client {
  List<Space> spaceList = [];
  SoundboardLibraryComponent? library;

  @override
  List<Space> get spaces => spaceList;

  @override
  T? getComponent<T extends Component>() => library is T ? library as T : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSpace implements Space {
  _FakeSpace(this.identifier, this.displayName, {Client? client})
    : client = client ?? _FakeClient();

  @override
  final String identifier;

  @override
  final String displayName;

  @override
  final Client client;

  @override
  ImageProvider? get avatar => null;

  SoundboardComponent? soundboard;

  @override
  T? getComponent<T extends SpaceComponent>() =>
      soundboard is T ? soundboard as T : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSoundboard extends SoundboardComponent<Client, Space> {
  _FakeSoundboard(super.client, super.space);

  final List<SoundboardPack> _packs = [];
  final List<SoundboardSound> _sounds = [];
  final StreamController<void> _onChanged = StreamController.broadcast();
  SoundboardDestinationPolicy policy = SoundboardDestinationPolicy.allowed;

  void configure({
    required List<SoundboardPack> packs,
    required List<SoundboardSound> sounds,
  }) {
    _packs
      ..clear()
      ..addAll(packs);
    _sounds
      ..clear()
      ..addAll(sounds);
  }

  @override
  List<SoundboardPack> get packs => _packs;

  @override
  List<SoundboardSound> get sounds => _sounds;

  @override
  Set<String> get activePackIds => _packs.map((pack) => pack.id).toSet();

  @override
  SoundboardDestinationPolicy get destinationPolicy => policy;

  @override
  Stream<void> get onChanged => _onChanged.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLibrary extends SoundboardLibraryComponent<Client> {
  _FakeLibrary(super.client);

  List<SoundboardGlobalPackEntry> entryList = [];
  final StreamController<void> _onChanged = StreamController.broadcast();

  @override
  List<SoundboardGlobalPackEntry> get entries => entryList;

  @override
  Stream<void> get onChanged => _onChanged.stream;

  @override
  bool isEnabled(String sourceSpaceId, String packId) => true;

  @override
  bool canEnable(String sourceSpaceId, String packId) => true;

  @override
  Future<void> enablePack(String sourceSpaceId, String packId) async {}

  @override
  Future<void> disablePack(String sourceSpaceId, String packId) async {}

  @override
  Future<void> pruneStaleReferences() async {}
}
