import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/photo_album_room/photo_album_room_component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_component.dart';
import 'package:intergalactic/client/demo/demo_client.dart';

void main() {
  test('offline demo photo album seeds individual photos and stacks', () async {
    final client = DemoClient.createOfflineDemo();
    await client.init(false);
    addTearDown(client.close);

    final room = client.rooms.firstWhere(
      (room) => room.identifier == DemoClient.demoPhotoAlbumRoomId,
    );
    final component = room.getComponent<PhotoAlbumRoom>()!;
    final timeline = await component.getTimeline();

    expect(timeline.photos, hasLength(4));
    expect(timeline.entries, hasLength(2));

    final individual = timeline.entries.firstWhere((entry) => !entry.isStack);
    expect(individual.rootPhoto.threadReplyCount, 2);

    final stack = timeline.entries.firstWhere((entry) => entry.isStack);
    expect(stack.displayCount, 3);
    expect(stack.rootPhoto.id, r'$demo-photo-stack-1');
    expect(stack.rootPhoto.threadReplyCount, 3);
  });

  test('offline demo soundboard seeds sounds and join sound', () async {
    final client = DemoClient.createOfflineDemo();
    await client.init(false);
    addTearDown(client.close);

    final space = client.spaces.firstWhere(
      (space) => space.identifier == DemoClient.demoSpaceId,
    );
    final soundboard = space.getComponent<SoundboardComponent>()!;

    expect(soundboard.sounds.map((sound) => sound.id), contains('demo-launch'));
    expect(
      soundboard.sounds.map((sound) => sound.id),
      contains('demo-sparkle'),
    );
    expect(soundboard.getJoinSoundId(client.self!.identifier), 'demo-chime');

    // The demo account is the source of the marketing captures, so its pack
    // SHAPE matters and not just its sound ids. Every seeded sound must carry
    // the mission pack id: a sound without one falls into a per-uploader
    // legacy pack, and the fallback captions every one of those identically.
    // Two uploaders lacking a pack id previously rendered "Mission sounds",
    // "Legacy sounds" and "Legacy sounds" side by side, which reads as a bug
    // in a screenshot. This asserts the demo presents exactly one named pack.
    //
    // It does NOT assert the underlying caption collision is fixed - that is a
    // real presentation defect tracked separately, and seeding around it here
    // only stops the demo from being its loudest example.
    expect(
      soundboard.packs.map((pack) => pack.name),
      ['Mission sounds'],
      reason:
          'the demo must present exactly one named pack, not a mixture of '
          'named and identically-captioned legacy packs',
    );
    expect(
      soundboard.packs.where((pack) => pack.isLegacy),
      isEmpty,
      reason: 'no seeded demo sound may fall back to a legacy pack',
    );
  });

  test('offline demo advertises E2EE when encrypted room is seeded', () async {
    final client = DemoClient.createOfflineDemo();
    await client.init(false);
    addTearDown(client.close);

    final room = client.rooms.firstWhere(
      (room) => room.identifier == DemoClient.demoEncryptedRoomId,
    );

    expect(room.isE2EE, isTrue);
    expect(client.supportsE2EE, isTrue);
  });
}
