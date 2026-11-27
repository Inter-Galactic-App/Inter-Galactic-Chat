import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/calendar_room/calendar_room_component.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_component.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/admin/room_admin_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/appearance/room_appearance_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/calendar/room_calendar_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/developer/room_developer_settings_view.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/room_emoji_pack_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/general/room_general_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/members/room_members_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/nicknames/room_nicknames_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/notifications/room_notifications_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/permissions/matrix/matrix_room_permissions_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/security/room_security_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/settings_category.dart';
import 'package:intergalactic/ui/pages/settings/settings_tab.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SettingsCategoryRoom implements SettingsCategory {
  SettingsCategoryRoom(this.room, this.contextSpace);
  static const String tabIdGeneral = 'room.general';
  static const String tabIdNotifications = 'room.notifications';
  static const String tabIdAppearance = 'room.appearance';
  static const String tabIdEmoticons = 'room.emoticons';
  static const String tabIdNicknames = 'room.nicknames';
  static const String tabIdMembers = 'room.members';
  static const String tabIdSecurity = 'room.security';
  static const String tabIdAdmin = 'room.admin';
  Room room;
  Space? contextSpace;

  String get labelRoomSettingsGeneral => Intl.message(
    "General",
    name: "labelRoomSettingsGeneral",
    desc: "Label for general room settings",
  );

  String get labelRoomSettingsAppearance => Intl.message(
    "Appearance",
    name: "labelRoomSettingsAppearance",
    desc: "Label for room appearance settings",
  );

  String get labelRoomSettingsNotificationsTab => Intl.message(
    "Notifications",
    name: "labelRoomSettingsNotificationsTab",
    desc: "Label for room notification settings",
  );

  String get labelRoomSettingsSecurity => Intl.message(
    "Security",
    name: "labelRoomSettingsSecurity",
    desc: "Label for room security settings",
  );

  String get labelRoomSettingsAdmin => Intl.message(
    "Admin Settings",
    name: "labelRoomSettingsAdmin",
    desc: "Label for room admin settings",
  );

  String get labelRoomSettingsEmoticons => Intl.message(
    "Emoticons",
    name: "labelRoomSettingsEmoticons",
    desc: "Label for room Emoticon settings",
  );

  String get labelRoomSettingsDeveloper => Intl.message(
    "Developer",
    name: "labelRoomSettingsDeveloper",
    desc: "Label for room developer settings",
  );

  String get labelRoomSettingsCategory => Intl.message(
    "Room Settings",
    name: "labelRoomSettingsCategory",
    desc: "Label for the overall settings category of a room",
  );

  String get labelRoomSettingsPermissions => Intl.message(
    "Permissions",
    name: "labelRoomSettingsPermissions",
    desc: "Label for room permission settings",
  );

  String get labelRoomSettingsMembers => Intl.message(
    "Members",
    name: "labelRoomSettingsMembers",
    desc: "Label for room member settings",
  );

  String get labelRoomSettingsNicknames => Intl.message(
    "Nicknames",
    name: "labelRoomSettingsNicknames",
    desc: "Label for room nickname settings",
  );

  String get labelRoomSettingsCalendar => Intl.message(
    "Calendar",
    name: "labelRoomSettingsCalendar",
    desc: "Label for room calendar settings",
  );

  @override
  String get title => labelRoomSettingsCategory;

  @override
  List<SettingsTab> get tabs => getTabs();

  List<SettingsTab> getTabs() {
    RoomEmoticonComponent? emoticons = room
        .getComponent<RoomEmoticonComponent>();

    CalendarRoom? calendar = room.getComponent<CalendarRoom>();

    return List.from([
      SettingsTab(
        id: tabIdGeneral,
        label: labelRoomSettingsGeneral,
        icon: Icons.info_outline,
        // The Addresses terms are gated on the same condition
        // `RoomGeneralSettingsPage` renders that section under. Search names a
        // control and then scrolls to it, so indexing one the page will not
        // build sends the user to a tab where the promised row is simply
        // absent - which reads as a broken search rather than an absent
        // feature.
        searchKeywords: [
          'general',
          'icon',
          'avatar',
          'name',
          'topic',
          'description',
          if (room is MatrixRoom) ...[
            'room addresses',
            'addresses',
            'aliases',
            'address',
          ],
        ],
        searchEntries: [
          const SettingsSearchEntry(
            title: 'Icon, name, and topic',
            section: 'Room Profile',
            keywords: [
              'avatar',
              'name',
              'topic',
              'description',
              'appearance',
              'general',
            ],
          ),
          if (room is MatrixRoom)
            const SettingsSearchEntry(
              title: 'Room Addresses',
              section: 'Addresses',
              keywords: ['aliases', 'address', 'general'],
            ),
        ],
        pageBuilder: (context) {
          return RoomGeneralSettingsPage(room: room);
        },
      ),
      SettingsTab(
        id: tabIdNotifications,
        label: labelRoomSettingsNotificationsTab,
        icon: Icons.notifications_outlined,
        searchKeywords: const [
          'general',
          'privacy',
          'read receipts',
          'typing indicators',
          'notification sound',
          'desktop sound',
          'mute',
          'mentions',
        ],
        searchEntries: const [
          SettingsSearchEntry(
            title: 'Notification mode',
            section: 'Notifications',
            keywords: ['all messages', 'mentions', 'keywords', 'mute'],
          ),
          SettingsSearchEntry(
            title: 'Read receipts',
            section: 'Privacy',
            keywords: ['privacy', 'general', 'seen'],
          ),
          SettingsSearchEntry(
            title: 'Typing indicators',
            section: 'Privacy',
            keywords: ['privacy', 'general', 'typing'],
          ),
          SettingsSearchEntry(
            title: 'Desktop Sound',
            section: 'Desktop Sound',
            keywords: ['notification sound', 'volume'],
          ),
        ],
        pageBuilder: (context) {
          return RoomNotificationsSettingsPage(room: room);
        },
      ),
      SettingsTab(
        id: tabIdAppearance,
        label: labelRoomSettingsAppearance,
        icon: Icons.style,
        searchKeywords: const [
          'background',
          'room background',
          'message bubbles',
          'bubbles',
        ],
        searchEntries: const [
          SettingsSearchEntry(
            title: 'Room background',
            section: 'Appearance',
            keywords: ['background', 'wallpaper'],
          ),
          SettingsSearchEntry(
            title: 'Room bubble settings',
            section: 'Appearance',
            keywords: ['bubbles', 'message bubbles', 'sent bubbles'],
          ),
        ],
        pageBuilder: (context) {
          return RoomAppearanceSettingsPage(room: room);
        },
      ),
      SettingsTab(
        id: tabIdSecurity,
        label: labelRoomSettingsSecurity,
        icon: Icons.lock_outline,
        searchKeywords: const [
          'security',
          'access',
          'encryption',
          'encrypted',
          'e2ee',
          'visibility',
          'history',
          'history visibility',
          'room history',
          'shared history',
          'full history',
        ],
        searchEntries: const [
          SettingsSearchEntry(
            title: 'Enable Encryption',
            section: 'Access',
            keywords: ['security', 'e2ee', 'encrypted'],
          ),
          SettingsSearchEntry(
            title: 'Room Visibility',
            section: 'Access',
            keywords: [
              'security',
              'public',
              'private',
              'restricted',
              'knock',
              'knock restricted',
            ],
          ),
          SettingsSearchEntry(
            title: 'Room History',
            section: 'Access',
            keywords: [
              'history visibility',
              'shared history',
              'full history',
              'members full history',
              'encrypted history',
            ],
          ),
        ],
        pageBuilder: (context) {
          return RoomSecuritySettingsPage(
            room: room,
            contextSpace: contextSpace,
          );
        },
      ),
      if (emoticons != null &&
          (room.permissions.canEditRoomEmoticons ||
              emoticons.ownedPacks.isNotEmpty))
        SettingsTab(
          id: tabIdEmoticons,
          label: labelRoomSettingsEmoticons,
          icon: Icons.emoji_emotions,
          searchKeywords: const ['emoji', 'emote', 'stickers', 'packs'],
          pageBuilder: (context) {
            return RoomEmojiPackSettingsPage(room);
          },
        ),
      if (room is MatrixRoom)
        SettingsTab(
          id: tabIdMembers,
          label: labelRoomSettingsMembers,
          icon: Icons.people,
          searchKeywords: const ['members', 'users', 'moderation'],
          pageBuilder: (context) {
            return RoomMembersSettingsPage(room: room);
          },
        ),
      if (room is MatrixRoom)
        SettingsTab(
          id: tabIdNicknames,
          label: labelRoomSettingsNicknames,
          icon: Icons.badge_outlined,
          searchKeywords: const [
            'nicknames',
            'nickname',
            'room display name',
            'display name',
            'members',
            'profile',
          ],
          searchEntries: const [
            SettingsSearchEntry(
              title: 'Your nickname',
              section: 'Nicknames',
              keywords: ['room display name', 'display name', 'profile'],
            ),
            SettingsSearchEntry(
              title: 'Member nicknames',
              section: 'Nicknames',
              keywords: ['members', 'moderation', 'other users'],
            ),
          ],
          pageBuilder: (context) {
            return RoomNicknamesSettingsPage(room: room as MatrixRoom);
          },
        ),
      SettingsTab(
        id: tabIdAdmin,
        label: labelRoomSettingsAdmin,
        icon: Icons.admin_panel_settings_outlined,
        searchKeywords: const [
          'room events',
          'join events',
          'leave events',
          'invite events',
          'profile updates',
          'discover',
          'server discovery',
          'room directory',
          'conversation type',
          'direct message',
          'group room',
          'room version',
          'room migration',
        ],
        searchEntries: const [
          SettingsSearchEntry(
            title: 'Room Events',
            section: 'Room Events',
            keywords: [
              'join events',
              'leave events',
              'invite events',
              'profile updates',
              'general',
            ],
          ),
          SettingsSearchEntry(
            title: 'Conversation type',
            section: 'Conversation type',
            keywords: ['direct message', 'group room', 'convert room'],
          ),
          SettingsSearchEntry(
            title: 'Matrix room version',
            section: 'Matrix room version',
            keywords: ['matrix room version', 'room migration', 'tombstone'],
          ),
          SettingsSearchEntry(
            title: 'Discover listing',
            section: 'Discover',
            keywords: [
              'discover',
              'server discovery',
              'room directory',
              'publish room',
              'unpublish room',
            ],
          ),
        ],
        pageBuilder: (context) {
          return RoomAdminSettingsPage(room: room);
        },
      ),
      if (room is MatrixRoom)
        SettingsTab(
          label: labelRoomSettingsPermissions,
          icon: Icons.admin_panel_settings,
          searchKeywords: const [
            'permissions',
            'power levels',
            'roles',
            'admin',
          ],
          pageBuilder: (context) {
            return MatrixRoomPermissionsPage(
              (room as MatrixRoom).matrixRoom,
              showCalendarPermissions: calendar?.hasCalendar == true,
            );
          },
        ),
      if (calendar?.hasCalendar == true)
        SettingsTab(
          icon: Icons.calendar_month,
          label: labelRoomSettingsCalendar,
          pageBuilder: (context) {
            return RoomCalendarSettingsPage(calendar!);
          },
        ),
      if (preferences.developerMode.value)
        SettingsTab(
          label: labelRoomSettingsDeveloper,
          icon: Icons.code,
          pageBuilder: (context) {
            return RoomDeveloperSettingsView(room);
          },
        ),
    ]);
  }
}
