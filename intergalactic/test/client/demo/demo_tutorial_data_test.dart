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
        soundboard.sounds.map((sound) => sound.id), contains('demo-sparkle'));
    expect(soundboard.getJoinSoundId(client.self!.identifier), 'demo-chime');
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
