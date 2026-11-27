import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Preferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = Preferences();
    await preferences.init();
  });

  test(
    'room message background overrides do not replace the default',
    () async {
      const roomLocalId = 'test-client:!room:example.org';

      expect(preferences.messageBackgroundImagePath.value, isNull);
      expect(preferences.getRoomMessageBackgroundPath(roomLocalId), isNull);

      await preferences.messageBackgroundImagePath.set('/local/default.png');
      await preferences.setRoomMessageBackgroundPath(
        roomLocalId,
        '/local/room.png',
      );

      expect(
        preferences.messageBackgroundImagePath.value,
        '/local/default.png',
      );
      expect(
        preferences.getRoomMessageBackgroundPath(roomLocalId),
        '/local/room.png',
      );

      await preferences.setRoomMessageBackgroundPath(roomLocalId, null);

      expect(preferences.getRoomMessageBackgroundPath(roomLocalId), isNull);
      expect(
        preferences.messageBackgroundImagePath.value,
        '/local/default.png',
      );
    },
  );

  test(
    'message background opacity defaults follow bubble mode until set',
    () async {
      expect(preferences.bubbleMessages.value, isFalse);
      expect(preferences.getDefaultMessageBackgroundOpacity(), 0.45);

      await preferences.bubbleMessages.set(true);

      expect(preferences.getDefaultMessageBackgroundOpacity(), 1.0);

      await preferences.setDefaultMessageBackgroundOpacity(0.72);

      expect(preferences.getDefaultMessageBackgroundOpacity(), 0.72);

      await preferences.clearDefaultMessageBackgroundOpacity();

      expect(preferences.getDefaultMessageBackgroundOpacity(), 1.0);
    },
  );

  test('room message appearance overrides fall back to defaults', () async {
    const roomLocalId = 'test-client:!room:example.org';

    await preferences.setDefaultMessageBackgroundOpacity(0.55);
    await preferences.sentMessageBubbleColor.set('#ff223344');
    await preferences.receivedMessageBubbleColor.set('#ff334455');

    expect(preferences.getRoomMessageBackgroundOpacity(roomLocalId), isNull);
    expect(preferences.getEffectiveMessageBackgroundOpacity(roomLocalId), 0.55);
    expect(
      preferences.getEffectiveSentMessageBubbleColor(roomLocalId),
      '#ff223344',
    );
    expect(
      preferences.getEffectiveReceivedMessageBubbleColor(roomLocalId),
      '#ff334455',
    );

    await preferences.setRoomMessageBackgroundOpacity(roomLocalId, 0.8);
    await preferences.setRoomSentMessageBubbleColor(roomLocalId, '#ff556677');
    await preferences.setRoomReceivedMessageBubbleColor(
      roomLocalId,
      '#ff667788',
    );

    expect(preferences.getRoomMessageBackgroundOpacity(roomLocalId), 0.8);
    expect(preferences.getEffectiveMessageBackgroundOpacity(roomLocalId), 0.8);
    expect(
      preferences.getEffectiveSentMessageBubbleColor(roomLocalId),
      '#ff556677',
    );
    expect(
      preferences.getEffectiveReceivedMessageBubbleColor(roomLocalId),
      '#ff667788',
    );

    await preferences.setRoomMessageBackgroundOpacity(roomLocalId, null);
    await preferences.setRoomSentMessageBubbleColor(roomLocalId, null);
    await preferences.setRoomReceivedMessageBubbleColor(roomLocalId, null);

    expect(preferences.getRoomMessageBackgroundOpacity(roomLocalId), isNull);
    expect(preferences.getEffectiveMessageBackgroundOpacity(roomLocalId), 0.55);
    expect(
      preferences.getEffectiveSentMessageBubbleColor(roomLocalId),
      '#ff223344',
    );
    expect(
      preferences.getEffectiveReceivedMessageBubbleColor(roomLocalId),
      '#ff334455',
    );
  });

  test('legacy single bubble color remains a fallback', () async {
    const roomLocalId = 'test-client:!room:example.org';

    await preferences.messageBubbleColor.set('#ff998877');

    expect(
      preferences.getEffectiveSentMessageBubbleColor(roomLocalId),
      '#ff998877',
    );
    expect(
      preferences.getEffectiveReceivedMessageBubbleColor(roomLocalId),
      '#ff998877',
    );
  });

  test('room notification sounds are local overrides of app default', () async {
    const roomLocalId = 'test-client:!room:example.org';

    expect(preferences.customNotificationSoundPath.value, isNull);
    expect(preferences.getRoomNotificationSoundPath(roomLocalId), isNull);

    await preferences.customNotificationSoundPath.set('/local/default.ogg');
    await preferences.setRoomNotificationSoundPath(
      roomLocalId,
      '/local/room.ogg',
    );

    expect(preferences.customNotificationSoundPath.value, '/local/default.ogg');
    expect(
      preferences.getRoomNotificationSoundPath(roomLocalId),
      '/local/room.ogg',
    );

    await preferences.setRoomNotificationSoundPath(roomLocalId, null);

    expect(preferences.getRoomNotificationSoundPath(roomLocalId), isNull);
    expect(preferences.customNotificationSoundPath.value, '/local/default.ogg');
  });

  test('screen-share audio volumes are keyed by room and sender', () async {
    const roomA = 'test-client:!room-a:example.org';
    const roomB = 'test-client:!room-b:example.org';
    const userA = '@alice:example.org';
    const userB = '@bob:example.org';

    await preferences.setScreenShareAudioVolume(
      roomLocalId: roomA,
      streamUserId: userA,
      volume: 0.25,
    );
    await preferences.setScreenShareAudioVolume(
      roomLocalId: roomA,
      streamUserId: userB,
      volume: 1.5,
    );
    await preferences.setScreenShareAudioVolume(
      roomLocalId: roomB,
      streamUserId: userA,
      volume: 2.5,
    );

    expect(
      Preferences.screenShareAudioVolumeKey(
        roomLocalId: roomA,
        streamUserId: userA,
      ),
      '$roomA|$userA|screenshareAudio',
    );
    expect(
      preferences.getScreenShareAudioVolume(
        roomLocalId: roomA,
        streamUserId: userA,
      ),
      0.25,
    );
    expect(
      preferences.getScreenShareAudioVolume(
        roomLocalId: roomA,
        streamUserId: userB,
      ),
      1.5,
    );
    expect(
      preferences.getScreenShareAudioVolume(
        roomLocalId: roomB,
        streamUserId: userA,
      ),
      2.0,
    );

    await preferences.removeScreenShareAudioVolume(
      roomLocalId: roomA,
      streamUserId: userA,
    );
    expect(
      preferences.getScreenShareAudioVolume(
        roomLocalId: roomA,
        streamUserId: userA,
      ),
      isNull,
    );
  });

  test('encrypted URL previews wait for first-use consent', () async {
    expect(preferences.urlPreviewInE2EEChat.value, isFalse);
    expect(preferences.shouldAllowUrlPreviewInE2EEChat, isFalse);

    await preferences.applyUrlPreviewE2EEConsentChoice(allow: true);

    expect(preferences.urlPreviewInE2EEChat.value, isTrue);
    expect(preferences.shouldAllowUrlPreviewInE2EEChat, isTrue);
  });
}
