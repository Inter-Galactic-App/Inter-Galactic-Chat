import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_component.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/members/room_members_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/permissions/matrix/matrix_room_permissions_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/space/space_admin_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/space/space_categories_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/space/space_developer_settings_view.dart';
import 'package:intergalactic/ui/pages/settings/categories/space/space_emoji_pack_settings.dart';
import 'package:intergalactic/ui/pages/settings/categories/space/space_matrix_room_builder.dart';
import 'package:intergalactic/ui/pages/settings/categories/space/space_notifications_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/space/space_soundboard_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/settings_category.dart';
import 'package:intergalactic/ui/pages/settings/settings_tab.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SettingsCategorySpace implements SettingsCategory {
  SettingsCategorySpace(this.space);
  static const String tabIdNotifications = 'space.general';
  static const String tabIdGeneral = tabIdNotifications;
  static const String tabIdEmoticons = 'space.emoticons';
  static const String tabIdAdmin = 'space.admin';
  static const String tabIdSoundboard = 'space.soundboard';
  static const String tabIdCategories = 'space.categories';
  Space space;

  String get labelSpaceSettingsGeneral => Intl.message(
    "General",
    name: "labelSpaceSettingsGeneral",
    desc: "Label for general space settings",
  );

  String get labelSpaceAppearanceSettings => Intl.message(
    "Appearance",
    name: "labelSpaceAppearanceSettings",
    desc: "Label for space appearance settings",
  );

  String get labelSpaceEmoticonSettings => Intl.message(
    "Emoticons",
    name: "labelSpaceEmoticonSettings",
    desc: "Label for space emoticon settings",
  );

  String get labelSpaceSoundboardSettings => Intl.message(
    "Soundboard",
    name: "labelSpaceSoundboardSettings",
    desc: "Label for space soundboard settings",
  );

  String get labelSpaceCategorySettings => Intl.message(
    "Categories",
    name: "labelSpaceCategorySettings",
    desc: "Label for space room category settings",
  );

  String get labelSpacePermissionSettings => Intl.message(
    "Permissions",
    name: "labelSpacePermissionSettings",
    desc: "Label for space permission settings",
  );

  String get labelSpaceDeveloperSettings => Intl.message(
    "Developer",
    name: "labelSpaceDeveloperSettings",
    desc: "Label for space developer settings",
  );

  String get labelSettingsCategorySpace => Intl.message(
    "Space Settings",
    name: "labelSettingsCategorySpace",
    desc: "Label for the overall space settings category",
  );

  String get labelSpaceSettingsSecurity => Intl.message(
    "Security",
    name: "labelSpaceSettingsSecurity",
    desc: "Label for space security settings",
  );

  String get labelSpaceSettingsNotifications => Intl.message(
    "Notifications",
    name: "labelSpaceSettingsNotifications",
    desc: "Label for space notification settings",
  );

  String get labelSpaceSettingsAdmin => Intl.message(
    "Admin Settings",
    name: "labelSpaceSettingsAdmin",
    desc: "Label for space admin settings",
  );

  String get labelSpaceSettingsMembers => Intl.message(
    "Members",
    name: "labelSpaceSettingsMembers",
    desc: "Label for space member settings",
  );

  @override
  String get title => labelSettingsCategorySpace;

  @override
  List<SettingsTab> get tabs => getTabs();

  List<SettingsTab> getTabs() {
    SpaceEmoticonComponent? emoticons = space
        .getComponent<SpaceEmoticonComponent>();
    final soundboard = space.getComponent<SoundboardComponent>();
    return List.from([
      SettingsTab(
        id: tabIdNotifications,
        label: labelSpaceSettingsNotifications,
        icon: Icons.notifications_outlined,
        searchKeywords: const [
          'general',
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
          return SpaceNotificationsSettingsPage(space: space);
        },
      ),
      if (emoticons != null &&
          (space.permissions.canEditRoomEmoticons ||
              emoticons.ownedPacks.isNotEmpty))
        SettingsTab(
          id: tabIdEmoticons,
          label: labelSpaceEmoticonSettings,
          icon: Icons.emoji_emotions,
          searchKeywords: const ['emoji', 'emote', 'stickers', 'packs'],
          pageBuilder: (context) {
            return SpaceEmojiPackSettings(space);
          },
        ),
      if (soundboard != null)
        SettingsTab(
          id: tabIdSoundboard,
          label: labelSpaceSoundboardSettings,
          icon: Icons.graphic_eq,
          searchKeywords: const [
            'soundboard',
            'call soundboard',
            'join sound',
            'sounds',
          ],
          searchEntries: const [
            SettingsSearchEntry(
              title: 'Call Soundboard',
              section: 'Soundboard',
              keywords: ['sounds', 'call sounds', 'uploads'],
            ),
            SettingsSearchEntry(
              title: 'Join Sound',
              section: 'Soundboard',
              keywords: ['join sound', 'voice room'],
            ),
          ],
          pageBuilder: (context) {
            return SpaceSoundboardSettingsPage(space: space);
          },
        ),
      SettingsTab(
        id: tabIdCategories,
        label: labelSpaceCategorySettings,
        icon: Icons.folder_copy_outlined,
        searchKeywords: const [
          'categories',
          'channels',
          'rooms',
          'groups',
          'server layout',
          'space layout',
          'shared layout',
          'inter galactic layout',
        ],
        searchEntries: const [
          SettingsSearchEntry(
            title: 'Room Categories',
            section: 'Categories',
            keywords: [
              'channels',
              'rooms',
              'groups',
              'collapse',
              'server layout',
              'space layout',
              'shared layout',
              'inter galactic layout',
            ],
          ),
        ],
        pageBuilder: (context) {
          return SpaceCategoriesSettingsPage(space: space);
        },
      ),
      if (space case MatrixSpace s)
        SettingsTab(
          label: labelSpaceSettingsMembers,
          icon: Icons.people,
          searchKeywords: const ['members', 'users', 'moderation'],
          pageBuilder: (context) {
            return SpaceMatrixRoomBuilder(
              space: s,
              builder: (context, room) => RoomMembersSettingsPage(room: room),
            );
          },
        ),
      SettingsTab(
        id: tabIdAdmin,
        label: labelSpaceSettingsAdmin,
        icon: Icons.admin_panel_settings_outlined,
        searchKeywords: const [
          'general',
          'appearance',
          'security',
          'icon',
          'avatar',
          'banner',
          'name',
          'topic',
          'room addresses',
          'space addresses',
          'aliases',
          'visibility',
          'discover',
          'server discovery',
          'space directory',
        ],
        searchEntries: const [
          SettingsSearchEntry(
            title: 'Icon, name, and topic',
            section: 'Space Profile',
            keywords: ['avatar', 'name', 'topic', 'appearance', 'general'],
          ),
          SettingsSearchEntry(
            title: 'Space banner',
            section: 'Banner',
            keywords: ['banner', 'appearance'],
          ),
          SettingsSearchEntry(
            title: 'Room Addresses',
            section: 'Addresses',
            keywords: ['aliases', 'address', 'general', 'space addresses'],
          ),
          SettingsSearchEntry(
            title: 'Space Visibility',
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
            title: 'Discover listing',
            section: 'Discover',
            keywords: [
              'discover',
              'server discovery',
              'space directory',
              'publish space',
              'unpublish space',
            ],
          ),
        ],
        pageBuilder: (context) {
          return SpaceAdminSettingsPage(space: space);
        },
      ),
      if (space is MatrixSpace)
        SettingsTab(
          label: labelSpacePermissionSettings,
          icon: Icons.admin_panel_settings,
          searchKeywords: const [
            'permissions',
            'power levels',
            'roles',
            'admin',
          ],
          pageBuilder: (context) {
            return MatrixRoomPermissionsPage((space as MatrixSpace).matrixRoom);
          },
        ),
      if (preferences.developerMode.value)
        SettingsTab(
          label: labelSpaceDeveloperSettings,
          icon: Icons.code,
          makeScrollable: true,
          pageBuilder: (context) {
            return SpaceDeveloperSettingsView(space);
          },
        ),
    ]);
  }
}
