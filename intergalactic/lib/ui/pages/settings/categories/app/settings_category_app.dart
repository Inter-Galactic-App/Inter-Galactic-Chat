import 'package:intergalactic/client/components/voip/voip_component.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/experiments.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/activity_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/advanced_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/appearance_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/desktop_companion_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/emoticons_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/experiments_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/general_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/shortcut_settings/shortcut_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/soundboard_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/voip_settings/voip_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/notification_settings/notification_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/settings_category.dart';
import 'package:intergalactic/ui/pages/settings/settings_tab.dart';
import 'package:flutter/material.dart' as m;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class SettingsCategoryApp implements SettingsCategory {
  SettingsCategoryApp({
    this.overrideClientManager,
    this.includeTutorialPreviewTabs = false,
  });

  static const tabIdGeneral = 'app.general';
  static const tabIdAppearance = 'app.appearance';
  static const tabIdActivity = 'app.activity';
  static const tabIdVoiceAndVideo = 'app.voice_video';
  static const tabIdEmoticons = 'app.emoticons';
  static const tabIdSoundboard = 'app.soundboard';
  static const tabIdShortcuts = 'app.shortcuts';
  static const tabIdNotifications = 'app.notifications';
  static const tabIdDesktopCompanion = 'app.desktop_companion';
  static const tabIdDeveloper = 'app.developer';
  static const tabIdExperiments = 'app.experiments';

  final ClientManager? overrideClientManager;
  final bool includeTutorialPreviewTabs;

  String get labelSettingsAppGeneral => Intl.message(
        "General",
        name: "labelSettingsAppGeneral",
        desc: "Label for the App General settings page",
      );

  String get labelSettingsAppAppearance => Intl.message(
        "Appearance",
        name: "labelSettingsAppAppearance",
        desc: "Label for the App Appearance settings page",
      );

  String get labelSettingsAppActivity => Intl.message(
        "Activity",
        name: "labelSettingsAppActivity",
        desc: "Label for the App Activity settings page",
      );

  String get labelSettingsWindowBehaviour => Intl.message(
        "Window Behaviour",
        name: "labelSettingsWindowBehaviour",
        desc: "Label for the Window Behaviour settings page",
      );

  String get labelSettingsAppAdvanced => Intl.message(
        "Developer",
        name: "labelSettingsTabDeveloper",
        desc: "Label for the App Developer settings page",
      );

  String get labelSettingsAppExperiments => Intl.message(
        "Experiments",
        name: "labelSettingsAppExperiments",
        desc: "Label for the App Experiments settings page",
      );

  String get labelSettingsAppNotifications => Intl.message(
        "Notifications",
        name: "labelSettingsAppNotifications",
        desc: "Label for the App notifications settings page",
      );

  String get labelSettingsAppDesktopCompanion => Intl.message(
        "Desktop Companion",
        name: "labelSettingsAppDesktopCompanion",
        desc: "Label for the desktop notification companion settings page",
      );

  String get labelSettingsAppEmoticons => Intl.message(
        "Emoticons",
        name: "labelSettingsAppEmoticons",
        desc: "Label for the app emoticons settings page",
      );

  String get labelSettingsAppSoundboard => Intl.message(
        "Soundboard",
        name: "labelSettingsAppSoundboard",
        desc: "Label for the app soundboard settings page",
      );

  String get labelSettingsShortcuts => Intl.message(
        "Shortcuts",
        name: "labelSettingsShortcuts",
        desc: "Label for the Keyboard shortcuts settings page",
      );

  String get labelSettingsCategoryApp => Intl.message(
        "App Settings",
        name: "labelSettingsCategoryApp",
        desc: "Label for the settings category of the overall App settings/",
      );

  String get labelSettingsCategoryVoiceAndVideo => Intl.message(
        "Voice and Video",
        name: "labelSettingsCategoryVoiceAndVideo",
        desc:
            "Label for the settings category related to voice and video calls",
      );

  @override
  String get title => labelSettingsCategoryApp;

  @override
  List<SettingsTab> get tabs {
    final manager = overrideClientManager ?? clientManager;

    return List.from([
      SettingsTab(
        id: tabIdGeneral,
        label: labelSettingsAppGeneral,
        icon: m.Icons.settings,
        searchKeywords: const [
          "startup",
          "updates",
          "gif",
          "gif api key",
          "gif relay",
          "klipy relay",
          "media",
          "media previews",
          "url previews",
          "sticker compatibility",
          "direct message lock",
          "dm lock",
          "pin",
          "privacy",
          "read receipts",
          "typing indicator",
          "window",
          "close",
          "minimize",
          "window behaviour",
          "offline demo",
        ],
        searchEntries: const [
          SettingsSearchEntry(
            title: "Check for updates",
            section: "Updates",
            keywords: ["updates", "version", "new version"],
          ),
          SettingsSearchEntry(
            title: "GIF search",
            section: "Media",
            description:
                "Enable GIF search with an approved relay URL or locally saved API key.",
            keywords: [
              "gif",
              "klipy",
              "api key",
              "relay",
              "approved relay",
              "user setup",
              "public build",
              "media",
            ],
          ),
          SettingsSearchEntry(
            title: "URL Preview in Encrypted Chats",
            section: "Media",
            description:
                "Choose whether encrypted-chat URLs can be sent to a homeserver or configured preview service for link previews.",
            keywords: [
              "url previews",
              "link previews",
              "encrypted chats",
              "privacy",
              "e2ee",
              "preview service",
              "homeserver preview",
              "direct fetch",
              "consent",
            ],
          ),
          SettingsSearchEntry(
            title: "Media previews",
            section: "Media",
            keywords: [
              "images",
              "videos",
              "private chats",
              "all chats",
              "privacy",
            ],
          ),
          SettingsSearchEntry(
            title: "Sticker compatibility",
            section: "Media",
            keywords: ["stickers", "compatibility", "advanced"],
          ),
          SettingsSearchEntry(
            title: "Direct Message Lock",
            section: "Direct Message Lock",
            keywords: ["dm lock", "pin", "locked dms", "privacy"],
          ),
          SettingsSearchEntry(
            title: "Ask before deleting messages",
            section: "App Behaviour",
            keywords: ["delete", "confirmation", "messages"],
          ),
          SettingsSearchEntry(
            title: "Read receipts",
            section: "App Behaviour",
            keywords: ["privacy", "account privacy", "seen"],
          ),
          SettingsSearchEntry(
            title: "Typing indicator",
            section: "App Behaviour",
            keywords: ["typing indicators", "privacy", "account privacy"],
          ),
          SettingsSearchEntry(
            title: "Autofocus message input",
            section: "App Behaviour",
            keywords: ["composer", "message input", "focus"],
          ),
          SettingsSearchEntry(
            title: "Always open space",
            section: "App Behaviour",
            keywords: ["spaces", "navigation"],
          ),
          SettingsSearchEntry(
            title: "Message effects",
            section: "App Behaviour",
            keywords: ["animations", "effects"],
          ),
          SettingsSearchEntry(
            title: "Automatic message effects",
            section: "App Behaviour",
            keywords: [
              "auto effects",
              "automatic effects",
              "congratulations",
              "pride",
              "snow day",
            ],
          ),
          SettingsSearchEntry(
            title: "Show offline demo sign-in",
            section: "App Behaviour",
            keywords: ["offline demo", "demo login", "startup"],
          ),
          SettingsSearchEntry(
            title: "Minimize on close",
            section: "Window Behaviour",
            keywords: [
              "window behaviour",
              "window behavior",
              "close",
              "minimize",
              "tray",
            ],
          ),
        ],
        pageBuilder: (context) {
          return const GeneralSettingsPage();
        },
      ),
      SettingsTab(
        id: tabIdAppearance,
        label: labelSettingsAppAppearance,
        icon: m.Icons.style,
        searchKeywords: const [
          "theme",
          "themes",
          "custom theme",
          "import theme",
          "export theme",
          "bubbles",
          "background",
          "app icon",
          "message style",
          "scale",
          "app scale",
          "text scale",
          "small-window",
          "small window",
          "layout override",
          "room avatars",
          "placeholder avatars",
        ],
        searchEntries: const [
          SettingsSearchEntry(
            title: "Follow system brightness",
            section: "Style",
            keywords: ["light", "dark", "theme"],
          ),
          SettingsSearchEntry(
            title: "Follow system colors",
            section: "Style",
            keywords: ["system colors", "accent", "material you"],
          ),
          SettingsSearchEntry(
            title: "App icon",
            section: "App Icon",
            keywords: ["icon", "light icon", "dark icon"],
          ),
          SettingsSearchEntry(
            title: "Theme",
            section: "Theme",
            keywords: ["themes", "sol", "nebula", "eclipse", "aurora"],
          ),
          SettingsSearchEntry(
            title: "Create custom theme",
            section: "Theme",
            keywords: ["custom theme", "theme workshop"],
          ),
          SettingsSearchEntry(
            title: "Import theme",
            section: "Theme",
            keywords: ["import", "theme json"],
          ),
          SettingsSearchEntry(
            title: "Export theme",
            section: "Theme",
            keywords: ["export", "theme json"],
          ),
          SettingsSearchEntry(
            title: "Background",
            section: "Message Appearance",
            keywords: ["room background", "message background"],
          ),
          SettingsSearchEntry(
            title: "Background transparency",
            section: "Message Appearance",
            keywords: ["opacity", "background opacity"],
          ),
          SettingsSearchEntry(
            title: "Use bubble messages",
            section: "Message Appearance",
            keywords: ["bubbles", "message bubbles"],
          ),
          SettingsSearchEntry(
            title: "Align sent messages right",
            section: "Message Appearance",
            keywords: ["align messages right", "message alignment"],
          ),
          SettingsSearchEntry(
            title: "App scale",
            section: "Scaling",
            keywords: ["zoom", "scale"],
          ),
          SettingsSearchEntry(
            title: "Text scale",
            section: "Scaling",
            keywords: ["font size", "text size"],
          ),
          SettingsSearchEntry(
            title: "Desktop small-window mode",
            section: "Other Options",
            keywords: ["small window", "compact desktop"],
          ),
          SettingsSearchEntry(
            title: "Show unjoined rooms in sidebar",
            section: "Other Options",
            keywords: ["sidebar", "unjoined rooms"],
          ),
          SettingsSearchEntry(
            title: "Use room avatars",
            section: "Other Options",
            keywords: ["room avatars", "avatars"],
          ),
          SettingsSearchEntry(
            title: "Use placeholder avatars",
            section: "Other Options",
            keywords: ["placeholder avatars", "avatars"],
          ),
          SettingsSearchEntry(
            title: "Override layout",
            section: "Other Options",
            keywords: ["layout override", "advanced", "desktop layout"],
          ),
        ],
        pageBuilder: (context) {
          return const AppearanceSettingsPage();
        },
      ),
      if (!BuildConfig.MOBILE || BuildConfig.IOS || BuildConfig.ANDROID)
        SettingsTab(
          id: tabIdActivity,
          label: labelSettingsAppActivity,
          icon: m.Icons.music_note,
          searchKeywords: const [
            "presence",
            "status",
            "spotify",
            "steam",
            "game",
            "local media",
          ],
          searchEntries: const [
            SettingsSearchEntry(
              title: "Spotify connection",
              section: "Connections",
              keywords: ["spotify", "music", "presence"],
            ),
            SettingsSearchEntry(
              title: "Steam connection",
              section: "Connections",
              keywords: ["steam", "game", "games", "presence"],
            ),
            SettingsSearchEntry(
              title: "Playback controls",
              section: "Activity Cards",
              keywords: ["local media", "media controls"],
            ),
            SettingsSearchEntry(
              title: "Publish to status",
              section: "Activity Cards",
              keywords: ["status", "presence"],
            ),
            SettingsSearchEntry(
              title: "Show activity locally",
              section: "Activity Privacy",
              keywords: ["privacy", "presence"],
            ),
            SettingsSearchEntry(
              title: "Hide current activity",
              section: "Activity Privacy",
              keywords: ["privacy", "presence"],
            ),
            SettingsSearchEntry(
              title: "Demo activity",
              section: "Activity Developer Tools",
              keywords: ["developer", "debug", "mock activity"],
            ),
          ],
          pageBuilder: (context) {
            return const ActivitySettingsPage();
          },
        ),
      if (includeTutorialPreviewTabs ||
          manager?.clients.any(
                (e) => e.getComponent<VoipComponent>() != null,
              ) ==
              true)
        SettingsTab(
          id: tabIdVoiceAndVideo,
          label: labelSettingsCategoryVoiceAndVideo,
          icon: m.Icons.call,
          searchKeywords: const [
            "calls",
            "microphone",
            "camera",
            "camera test",
            "screen share",
            "screenshare",
            "audio",
            "speaker volume",
            "microphone volume",
            "mic test",
            "push to talk",
            "rnnoise",
          ],
          searchEntries: const [
            SettingsSearchEntry(
              title: "Microphone",
              section: "Voice",
              keywords: ["default audio input", "audio input", "mic"],
            ),
            SettingsSearchEntry(
              title: "Speaker",
              section: "Voice",
              keywords: ["audio output", "speaker", "output device"],
            ),
            SettingsSearchEntry(
              title: "Microphone volume",
              section: "Voice",
              keywords: ["mic volume", "input volume"],
            ),
            SettingsSearchEntry(
              title: "Speaker volume",
              section: "Voice",
              keywords: ["output volume"],
            ),
            SettingsSearchEntry(
              title: "Mic test",
              section: "Voice",
              keywords: ["microphone test", "test devices"],
            ),
            SettingsSearchEntry(
              title: "Camera",
              section: "Video",
              keywords: ["camera selection", "video input"],
            ),
            SettingsSearchEntry(
              title: "Camera test",
              section: "Video",
              keywords: ["preview camera", "test devices"],
            ),
            SettingsSearchEntry(
              title: "Push to Talk",
              section: "Voice",
              keywords: ["ptt", "shortcut", "keybind"],
            ),
            SettingsSearchEntry(
              title: "Screen share quality",
              section: "Stream Settings",
              keywords: ["screenshare", "screen sharing", "stream"],
            ),
            SettingsSearchEntry(
              title: "Noise suppression",
              section: "Stream Settings",
              keywords: ["rnnoise", "noise reduction"],
            ),
            SettingsSearchEntry(
              title: "Noise suppression preset",
              section: "Stream Settings",
              keywords: ["rnnoise preset", "audio processing"],
            ),
          ],
          pageBuilder: (context) {
            return const VoipSettingsPage();
          },
        ),
      if (includeTutorialPreviewTabs || manager?.clients.isNotEmpty == true)
        SettingsTab(
          id: tabIdEmoticons,
          label: labelSettingsAppEmoticons,
          icon: m.Icons.emoji_emotions,
          searchKeywords: const [
            "emoji",
            "emoticons",
            "stickers",
            "packs",
            "custom emoji",
            "quick reactions",
            "favorite packs",
            "available packs",
            "room emoji",
            "space emoji",
          ],
          searchEntries: const [
            SettingsSearchEntry(
              title: "Customize Reactions",
              section: "Quick Reactions",
              keywords: ["quick reactions", "emoji", "react"],
            ),
            SettingsSearchEntry(
              title: "Favorite Packs",
              section: "Packs",
              keywords: ["favorite packs", "stickers", "emoji packs"],
            ),
            SettingsSearchEntry(
              title: "Available Packs",
              section: "Packs",
              keywords: [
                "joined rooms",
                "joined spaces",
                "room emoji",
                "space emoji",
                "custom emoji",
              ],
            ),
          ],
          pageBuilder: (context) {
            return EmoticonsSettingsPage(
              clientManager: Provider.of<ClientManager>(context),
            );
          },
        ),
      if (includeTutorialPreviewTabs || manager?.clients.isNotEmpty == true)
        SettingsTab(
          id: tabIdSoundboard,
          label: labelSettingsAppSoundboard,
          icon: m.Icons.graphic_eq,
          searchKeywords: const [
            "soundboard",
            "sounds",
            "call sounds",
            "join sound",
            "soundboard volume",
            "space soundboard",
          ],
          searchEntries: const [
            SettingsSearchEntry(
              title: "Soundboard volume",
              section: "Soundboard",
              keywords: ["volume", "call sounds"],
            ),
            SettingsSearchEntry(
              title: "Joined space soundboards",
              section: "Soundboards",
              keywords: ["space soundboard", "manage soundboard"],
            ),
          ],
          pageBuilder: (context) {
            return SoundboardSettingsPage(
              clientManager: Provider.of<ClientManager>(context),
            );
          },
        ),
      if (PlatformUtils.isLinux || PlatformUtils.isWindows)
        SettingsTab(
          id: tabIdShortcuts,
          label: labelSettingsShortcuts,
          icon: m.Icons.keyboard_alt_outlined,
          searchKeywords: const [
            "keyboard",
            "hotkey",
            "hotkeys",
            "push to talk",
            "desktop companion shortcut",
            "brackets",
            "auto close brackets",
            "wrap selection",
          ],
          searchEntries: const [
            SettingsSearchEntry(
              title: "Configure shortcuts",
              section: "Shortcuts",
              keywords: ["keyboard", "hotkey", "hotkeys"],
            ),
            SettingsSearchEntry(
              title: "Auto-close brackets",
              section: "Composer Typing",
              keywords: [
                "brackets",
                "parentheses",
                "auto close",
                "composer typing",
              ],
            ),
            SettingsSearchEntry(
              title: "Wrap Selection in Brackets",
              section: "Shortcuts",
              keywords: [
                "brackets",
                "parentheses",
                "wrap selected text",
                "composer shortcut",
              ],
            ),
            SettingsSearchEntry(
              title: "Room shortcut",
              section: "Custom Navigation",
              keywords: ["room id", "room alias", "navigate room"],
            ),
            SettingsSearchEntry(
              title: "Space shortcut",
              section: "Custom Navigation",
              keywords: ["space id", "space alias", "navigate space"],
            ),
            SettingsSearchEntry(
              title: "Toggle Desktop Companion",
              section: "Shortcuts",
              keywords: ["desktop companion shortcut", "companion"],
            ),
            SettingsSearchEntry(
              title: "Push to Talk",
              section: "Shortcuts",
              keywords: ["ptt", "voice", "keybind"],
            ),
          ],
          pageBuilder: (context) {
            return const ShortcutSettingsPage();
          },
        ),
      // We really only need to configure on unified push
      if (BuildConfig.LINUX ||
          BuildConfig.WINDOWS ||
          BuildConfig.ANDROID ||
          BuildConfig.IOS ||
          BuildConfig.WEB)
        SettingsTab(
          id: tabIdNotifications,
          label: labelSettingsAppNotifications,
          icon: m.Icons.notifications,
          searchKeywords: const [
            "push",
            "notification mode",
            "mentions",
            "keywords",
            "mute",
            "alerts",
            "sound",
            "sounds",
            "ringtone",
            "volume",
            "overrides",
            "room notification overrides",
            "space notification overrides",
          ],
          searchEntries: const [
            SettingsSearchEntry(
              title: "Notification mode",
              section: "Notifications",
              keywords: ["all", "mentions", "keywords", "mute"],
            ),
            SettingsSearchEntry(
              title: "Hide notifications for current room",
              section: "Notifications",
              keywords: ["mute room", "current room"],
            ),
            SettingsSearchEntry(
              title: "Message body formatting",
              section: "Appearance",
              keywords: ["body", "formatting", "preview text"],
            ),
            SettingsSearchEntry(
              title: "Show images",
              section: "Appearance",
              keywords: ["images", "notification images"],
            ),
            SettingsSearchEntry(
              title: "Preview URLs",
              section: "Appearance",
              keywords: ["url previews", "link previews"],
            ),
            SettingsSearchEntry(
              title: "Notification volume",
              section: "Sounds",
              keywords: ["volume", "notification sound"],
            ),
            SettingsSearchEntry(
              title: "Notification sound",
              section: "Sounds",
              keywords: ["sound", "alert sound"],
            ),
            SettingsSearchEntry(
              title: "Ringtone",
              section: "Sounds",
              keywords: ["call sound", "ringtone"],
            ),
            SettingsSearchEntry(
              title: "Room and space overrides",
              section: "Overrides",
              keywords: [
                "overrides",
                "room notification overrides",
                "space notification overrides",
              ],
            ),
          ],
          pageBuilder: (context) {
            return const NotificationSettingsPage();
          },
        ),
      if (includeTutorialPreviewTabs || PlatformUtils.isWindows)
        SettingsTab(
          id: tabIdDesktopCompanion,
          label: labelSettingsAppDesktopCompanion,
          icon: m.Icons.desktop_windows,
          searchKeywords: const [
            "companion",
            "desktop companion",
            "notification companion",
            "avatar",
            "previews",
            "screen sharing",
            "reduced motion",
          ],
          searchEntries: const [
            SettingsSearchEntry(
              title: "Show companion",
              section: "Notification Companion",
              keywords: ["desktop companion", "notification companion"],
            ),
            SettingsSearchEntry(
              title: "Companion avatar",
              section: "Notification Companion",
              keywords: ["avatar", "light avatar", "dark avatar"],
            ),
            SettingsSearchEntry(
              title: "Show companion previews",
              section: "Behavior",
              keywords: ["previews", "notification previews"],
            ),
            SettingsSearchEntry(
              title: "Hide previews while sharing",
              section: "Behavior",
              keywords: ["screen sharing", "privacy"],
            ),
            SettingsSearchEntry(
              title: "Click companion to open room",
              section: "Behavior",
              keywords: ["open room", "click companion"],
            ),
            SettingsSearchEntry(
              title: "Reduced companion motion",
              section: "Behavior",
              keywords: ["reduced motion", "animation"],
            ),
          ],
          pageBuilder: (context) {
            return const DesktopCompanionSettingsPage();
          },
        ),
      SettingsTab(
        id: tabIdDeveloper,
        label: labelSettingsAppAdvanced,
        icon: m.Icons.code,
        searchKeywords: const [
          "proxy",
          "push transport",
          "registered pushers",
          "notification diagnostics",
          "account state",
          "account json",
          "turn",
          "advanced",
          "developer",
          "voice",
          "video",
          "webrtc",
          "stun",
          "rnnoise diagnostics",
          "advanced stream override",
          "adaptive fallback",
          "call stats",
          "stream stats",
          "logs",
          "app logs",
          "developer utils",
          "benchmarks",
          "performance diagnostics",
          "window size",
          "show repaints",
          "background tasks",
        ],
        searchEntries: const [
          SettingsSearchEntry(
            title: "Developer mode",
            section: "Developer",
            keywords: ["advanced", "debug", "developer"],
          ),
          SettingsSearchEntry(
            title: "Logs",
            section: "Logs",
            keywords: [
              "app logs",
              "developer logs",
              "diagnostics",
              "open log folder",
              "copy recent logs",
              "clear logs",
            ],
          ),
          SettingsSearchEntry(
            title: "Account State JSON",
            section: "Logs",
            keywords: [
              "account json",
              "account developer json",
              "account state",
            ],
          ),
          SettingsSearchEntry(
            title: "Push transport",
            section: "Notification Developer Settings",
            keywords: ["notifications", "push", "gateway"],
          ),
          SettingsSearchEntry(
            title: "Registered pushers",
            section: "Notification Developer Settings",
            keywords: ["pushers", "notification diagnostics"],
          ),
          SettingsSearchEntry(
            title: "Voice and Video Developer Settings",
            section: "Voice and Video",
            keywords: ["advanced", "webrtc", "call diagnostics"],
          ),
          SettingsSearchEntry(
            title: "Use STUN fallback",
            section: "Voice and Video",
            keywords: ["stun", "turn", "call connection"],
          ),
          SettingsSearchEntry(
            title: "Test TURN server",
            section: "Voice and Video",
            keywords: ["turn", "webrtc debug menu"],
          ),
          SettingsSearchEntry(
            title: "Show call/stream stats",
            section: "Voice and Video",
            keywords: ["call stats", "stream stats", "diagnostics"],
          ),
          SettingsSearchEntry(
            title: "RNNoise Diagnostics",
            section: "Voice and Video",
            keywords: ["rnnoise", "noise suppression diagnostics"],
          ),
          SettingsSearchEntry(
            title: "Audio Processing",
            section: "Voice and Video",
            keywords: ["rnnoise", "audio processing"],
          ),
          SettingsSearchEntry(
            title: "Advanced Stream Override",
            section: "Voice and Video",
            keywords: ["stream override", "bitrate", "fps", "codec"],
          ),
          SettingsSearchEntry(
            title: "Adaptive Stream Fallback",
            section: "Voice and Video",
            keywords: ["adaptive fallback", "stream fallback"],
          ),
          SettingsSearchEntry(
            title: "Developer Utils",
            section: "Developer Utils",
            keywords: ["debug tools", "advanced", "utilities"],
          ),
          SettingsSearchEntry(
            title: "Performance diagnostics",
            section: "Developer Utils",
            keywords: ["performance", "initial load database"],
          ),
          SettingsSearchEntry(
            title: "Benchmarks",
            section: "Developer Utils",
            keywords: ["timeline viewer", "benchmark"],
          ),
          SettingsSearchEntry(
            title: "Window size tools",
            section: "Developer Utils",
            keywords: ["window size", "small window"],
          ),
          SettingsSearchEntry(
            title: "Show repaints",
            section: "Developer Utils",
            keywords: ["rendering", "repaints"],
          ),
          SettingsSearchEntry(
            title: "Background tasks",
            section: "Developer Utils",
            keywords: ["debug tasks", "async task"],
          ),
          SettingsSearchEntry(
            title: "Timeline diagnostics",
            section: "Developer Utils",
            keywords: ["show timeline diagnostics", "debug timeline"],
          ),
        ],
        pageBuilder: (context) {
          return const AdvancedSettingsPage();
        },
      ),
      if (Experiments.hasVisibleExperiments(
        developerMode: preferences.developerMode.value,
      ))
        SettingsTab(
          id: tabIdExperiments,
          label: labelSettingsAppExperiments,
          icon: m.Icons.science,
          searchKeywords: const ["labs", "experimental"],
          searchEntries: const [
            SettingsSearchEntry(
              title: "Experiments",
              section: "Experiments",
              keywords: ["labs", "experimental", "feature flags"],
            ),
          ],
          pageBuilder: (context) {
            return const ExperimentsSettingsPage();
          },
        ),
    ]);
  }
}
