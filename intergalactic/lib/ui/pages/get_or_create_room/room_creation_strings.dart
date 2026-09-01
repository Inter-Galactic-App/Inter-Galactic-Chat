import 'package:intl/intl.dart';

class RoomCreationStrings {
  static String get labelCreateRoom =>
      Intl.message("Create new room", name: "labelCreateRoom");

  static String get labelPickExistingRoom => Intl.message(
        "Add existing",
        name: "labelPickExistingRoom",
      );

  static String get labelJoinRoom => Intl.message(
        "Join by address",
        name: "labelJoinRoom",
      );

  static String get labelRoomTypeTextChat => Intl.message("Text Chat",
      name: "labelRoomTypeTextChat",
      desc: "Label for creating a regular text based chat room");

  static String get labelRoomTypeVoiceChat => Intl.message(
        "Voice Chat",
        name: "labelRoomTypeVoiceChat",
      );

  static String get labelRoomTypePhotoAlbum => Intl.message(
        "Photo Album",
        name: "labelRoomTypePhotoAlbum",
      );

  static String get labelRoomTypeCalendar => Intl.message(
        "Calendar",
        name: "labelRoomTypeCalendar",
      );

  static String get labelRoomTypeSpace => Intl.message(
        "Space",
        name: "labelRoomTypeSpace",
      );

  static String get labelRoomTypeForum => Intl.message(
        "Forum",
        name: "labelRoomTypeForum",
        desc: "Label for creating a Forum room type",
      );

  static String get labelCreateRoomSection => Intl.message(
        "Create a new room",
        name: "labelCreateRoomSection",
      );

  static String get summaryPickExistingRoom => Intl.message(
        "Add a room you already have access to.",
        name: "summaryPickExistingRoom",
      );

  static String get summaryJoinRoom => Intl.message(
        "Join a room by Matrix address or invite link.",
        name: "summaryJoinRoom",
      );

  static String get summaryRoomTypeTextChat => Intl.message(
        "Talk with messages, media, stickers, and GIFs.",
        name: "summaryRoomTypeTextChat",
      );

  static String get summaryRoomTypeVoiceChat => Intl.message(
        "Keep a voice room ready for live hangouts.",
        name: "summaryRoomTypeVoiceChat",
      );

  static String get summaryRoomTypePhotoAlbum => Intl.message(
        "Collect photos and videos in one shared place.",
        name: "summaryRoomTypePhotoAlbum",
      );

  static String get summaryRoomTypeCalendar => Intl.message(
        "Plan events and availability together.",
        name: "summaryRoomTypeCalendar",
      );

  static String get summaryRoomTypeSpace => Intl.message(
        "Organize a community with rooms and categories.",
        name: "summaryRoomTypeSpace",
      );

  static String get summaryRoomTypeForum => Intl.message(
        "Organize longer discussions with posts and replies.",
        name: "summaryRoomTypeForum",
      );

  static String labelCreatingRoomType(String roomType) => Intl.message(
        "Creating $roomType...",
        name: "labelCreatingRoomType",
        args: [roomType],
        desc: "Progress label shown while creating a room type",
      );
}
