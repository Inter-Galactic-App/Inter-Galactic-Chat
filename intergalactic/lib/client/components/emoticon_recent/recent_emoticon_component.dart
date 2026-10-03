import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';

abstract class RecentEmoticonComponent<T extends Client>
    implements Component<T> {
  static const int quickReactionCount = 8;

  List<Emoticon> getRecentTypedEmoticon(Room? room);

  /// Stickers selected from the picker on this device for this account.
  ///
  /// Unlike typed emoji, sticker recents are intentionally device-local:
  /// Matrix has no interoperable recent-sticker account-data event.
  List<Emoticon> getRecentStickerEmoticon(Room? room);

  List<Emoticon> getRecentReactionEmoticon(Room room);

  List<Emoticon> getQuickReactionEmoticon(Room? room);

  Future<void> typedEmoticon(Room room, Emoticon emoticon);

  Future<void> stickerEmoticon(Room room, Emoticon emoticon);

  Future<void> reactedEmoticon(Room room, Emoticon emoticon);

  Future<void> setQuickReactionEmoticon(
    int index,
    Emoticon emoticon, {
    Room? room,
  });

  Future<void> clear();
}
