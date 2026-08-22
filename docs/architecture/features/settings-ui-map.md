# Settings UI Map

Static review snapshot: 2026-06-11
Agent: DESIGN
Base repo path: `intergalactic-app/inter-galactic`

This map tracks the current Settings architecture, navigation, visible settings
areas, persistence, and risk points after the implemented settings chrome,
account-scope, Account Security, and Matrix encryption updates.

Phase 1 information-architecture decisions are recorded in
`docs/architecture/features/settings-information-architecture.md`. That addendum keeps
the current Settings routes/shells intact while defining target groups, risk
tiers, developer separation, and room/space copy policy for later overhaul
phases.

The staged app-settings migration plan has been archived after implementation.
Use this map, `docs/architecture/features/settings-information-architecture.md`, and the
design-system settings guidance for current contributor-facing orientation.

Implementation update, 2026-06-11: App Settings account selection now lives in
the settings chrome instead of repeated tab-level account dropdowns. Desktop
uses the existing top-left account header as a clickable account menu; mobile
settings and mobile subpages expose the same selector in their header area. The
shared settings account controller initializes from `filter_client_id`, so
multi-account settings default to the focused account when one is active, while
header changes only affect which account settings edit and do not mutate the
main-shell focus preference.

Implementation update, 2026-06-11: Account Security now groups password
management and account recovery codes under one Account security section without
nested background cards. Matrix encryption health keeps the fuller desktop chip
set, switches to compact chips on mobile, hides biometric recovery-key storage
on desktop, and combines encrypted-message repair/retry behind one **Encrypted
message tools** chooser with distinct repair-vs-retry explanations.

Implementation update, 2026-05-10: desktop App, Room, and Space settings now
open through `SettingsNavigation.show(...)`, which presents an adaptive overlay
route over the live app. Mobile settings keep the existing full-page flow. The
desktop shell still uses the same `SettingsCategory` / `SettingsTab` model, but
renders inside overlay chrome with a close action, account header, search, and
centered content width.

Implementation update, 2026-05-12: the staged App Settings reorganization has
folded the former Window Behaviour tab into General, moved Account Emoticons
into App Settings, added App-level Soundboard discovery, and split the Windows
Desktop Companion controls out of Notifications. A follow-up added
user-defined room/space navigation shortcuts and lets Soundboard discovery
cards open the matching contextual Space Settings soundboard tab.

Implementation update, 2026-05-12: App Settings **Advanced** is now labeled
**Developer**. Account Developer JSON moved out of the Account category into a
collapsible Developer panel, and Notifications now keeps user-facing mode,
appearance, sound, and override controls while push transport/gateway setup and
registered pusher diagnostics live under Developer.

Implementation update, 2026-05-12: Developer diagnostics are organized as
collapsible panels for Account JSON, Notification Developer Settings, and Voice
and Video Developer Settings. The migrated Emoticons, Soundboard,
Notifications, Desktop Companion, and Developer diagnostic cards use
`surfaceContainerLow`, and RNNoise diagnostics/Audio Processing now render as
status cards instead of loose diagnostic text.

Implementation update, 2026-05-12: Phase 6 developer consolidation moved Logs
out of About and Developer Utils out of the main settings navigation. Both now
live as collapsible panels inside App Settings > Developer, with Developer
Utils broken into described utility groups. The Voice and Video call/stream
stats toggle moved into the Voice and Video developer panel.

Implementation update, 2026-05-13: Developer now uses the existing Developer
localization key instead of the stale Advanced key. The Developer panel order
starts with Logs, then Account state JSON. Help & Safety and Account Security
received a visual alignment pass: Help cards use the current settings card
treatment with a deeper red Block User action, and Security moved the Sessions
heading outside its session list while aligning Cross Signing & Backup rows and
Account Deletion to the current section rhythm.

Implementation update, 2026-05-13: Settings search now supports row-level
`SettingsSearchEntry` metadata on each `SettingsTab`. The shared filter returns
matching row entries when row names/descriptions/aliases match, while preserving
tab fallback matches for category names, tab labels, and legacy keywords. The
desktop and mobile shells display row hits with their parent tab/section, and
the app/account metadata keeps moved labels such as Privacy, Advanced, Manage
Accounts, and Window Behaviour searchable.

Implementation update, 2026-05-13: contextual Room and Space Settings now follow
the proposed room/space IA. Notifications owns push rules, read receipts, typing
indicators, and desktop sound overrides; Room Security owns encryption, room
visibility, and room history visibility; Admin Settings owns room/space
identity, addresses, and room events where supported.
Room Appearance is now focused on room-local message background and bubble
styling. General and Appearance remain searchable legacy aliases where their
controls moved.

Implementation update, 2026-05-28: Room Settings exposes Security as a visible
tab. Permissions still exposes the power-level requirement for "History
Visibility", while Security -> Room History owns the current room-history
visibility value used by invite history sharing.

Implementation update, 2026-05-13: Room Settings now includes a **Nicknames**
tab for Matrix rooms. It surfaces the current user's room nickname, member
display names, existing room nicknames, and permission-gated edit actions for
other members. The outside-settings Room Members side panel includes a pinned
Nicknames action that opens Room Settings directly to this tab.

Implementation update, 2026-05-17: App Settings > Help now includes a **FAQ**
tab. The FAQ page groups question cards by General, Security, and Features;
clicking a card opens a popup answer. Each FAQ item is also represented as a
row-level settings search entry with question, summary, and support keywords so
search can find the FAQ content directly.

Implementation update, 2026-06-14: App Settings > General now exposes separate
**Message effects** and **Automatic message effects** local toggles. The
automatic toggle defaults off, has its own row-level search entry, and only
enables trigger-based sends when the parent message-effects preference is also
enabled. Manual message-effect commands and the composer effects menu remain
separate from the automatic-send toggle.

Implementation update, 2026-06-24: Settings search row results can now carry an
optional route anchor. `SettingsControlRow` derives a stable default anchor from
its visible title, non-row targets can opt in with
`SettingsSearchHighlightTarget`, and desktop/mobile settings shells trigger a
shared highlight controller after selecting or pushing the owning tab. The
highlight scrolls the nearest settings scroll owner to the matched target and
briefly paints a theme-token outline/fill; reduced-motion settings collapse the
scroll animation. This is a presentation/navigation affordance only and does
not change settings persistence, Matrix writes, account selection, or search
matching semantics.

Implementation update, 2026-06-29: App Settings now includes an
**Accessibility** tab after Appearance. The tab owns local app-level
accessibility preferences for contrast, color-safe mode, non-color cues, link
underlines, focus indicators, On/Off labels, text size, bold text, transparency,
UI separation, reduced motion, animated media pause, larger targets, and
persistent action labels. Its settings-search metadata covers the reset preset
and each MVP control row so row-level search can open and highlight the
matching Accessibility setting. `AccessibilityScope` resolves those stored
overrides with Flutter platform signals and exposes semantic tokens consumed by shared
settings/status/navigation primitives. The scope also publishes effective text
scaling and bold text through descendant `MediaQuery` data, and the shared
Tiamat text atom consumes that signal for heavier readable text weights without
importing app-only accessibility state. `AccessibleInteractiveRegion` extends
that foundation to custom room/space/rail and composer presentation controls so
they expose consistent action semantics, keyboard activation, theme-token focus
rings, larger-target constraints, and opt-in short visible labels for important
icon-only actions when requested. Shared rich-text links now use the resolved
accessibility link token and underline setting through `LinkSpan`, so plain URL
and Matrix HTML links are not color-only when color-safe/high-contrast or
underline-link preferences require stronger cues. Main-shell rail visible
labels, call runtime, media playback runtime, and story editor runtime behavior
remain lane-owned follow-ups where they need more than shared presentation
tokens.

Implementation update, 2026-06-29: Favorites settings moved out of App
Settings > Appearance into a contextual **Favorites Settings** surface opened
from the Favorites virtual-space gear. The surface uses the shared settings
shell with **Appearance** and **Categories** tabs. Appearance continues to edit
local Favorites icon/banner preference data, while Categories uses the existing
space-room category model under the local virtual Favorites id so favorite
rooms from multiple signed-in accounts and homeservers can be grouped without
writing Matrix space state.

## 1. Executive Summary

Settings are built from a small shared metadata model:

- `SettingsPage` chooses the desktop or mobile shell based on `Layout`.
- `SettingsCategory` supplies groups such as Account, App, Room, Space, Help,
  and About.
- `SettingsTab` supplies each visible tab label, icon, page builder, optional
  scroll behavior, optional tab keywords, and row-level search entries.
- `DesktopSettingsPage` renders a two-pane settings surface with search and a
  category/tab/sidebar row-results list.
- `MobileSettingsPage` renders a mobile list of categories, tabs, and row
  search results; tapping a result opens the owning `SettingsSubPage`.

The shell is shared, but the tab bodies are not yet visually unified. Some
pages use newer mobile cards and pill buttons, while others still rely on
Tiamat `Tile`, raw `Column` layouts, Material list tiles, `ExpansionTile`,
bespoke dialogs, and page-local helper widgets.

Most app-level settings persist locally through `SharedPreferences` via
`Preferences` and `Preference<T>`. Account, room, and space settings often call
Matrix APIs or component abstractions, especially profile, room state, room
power levels, notifications, custom emoji, E2EE, soundboard, and presence.

The highest-risk areas before a redesign are Matrix security and encryption,
room permissions/power levels, notification/push configuration, account
logout/deletion flows, VoIP diagnostics, custom themes, and soundboard state.

## 2. Current Settings Architecture Map

### Shared Shell

| Area | Widget/class | File/location | Purpose | Surface |
| --- | --- | --- | --- | --- |
| Settings router | `SettingsPage` | `intergalactic/lib/ui/pages/settings/settings_page.dart:9` | Chooses desktop or mobile settings shell from `Layout` | Shared |
| Settings navigation | `SettingsNavigation` | `intergalactic/lib/ui/pages/settings/settings_navigation.dart` | Opens desktop settings in an adaptive non-opaque overlay route; keeps mobile on the slide-in page route | Shared entry helper |
| Desktop shell | `DesktopSettingsPage`, `DesktopSettingsPageState` | `intergalactic/lib/ui/pages/settings/desktop_settings_page.dart:11-19` | Overlay-contained two-pane desktop settings UI with account header, search, category headers, sidebar tabs, top close action, and optional right-pane scroll | Desktop |
| Mobile shell | `MobileSettingsPage` | `intergalactic/lib/ui/pages/settings/mobile_settings_page.dart:14` | Mobile settings index with search, category sections, and navigation to subpages | Mobile |
| Mobile subpage | `SettingsSubPage` | `intergalactic/lib/ui/pages/settings/mobile_settings_page.dart:309` | Per-tab mobile destination with back affordance and tab body | Mobile |
| Category model | `SettingsCategory` | `intergalactic/lib/ui/pages/settings/settings_category.dart:3` | Title plus tab list | Shared |
| Tab model | `SettingsTab`, `SettingsSearchEntry` | `intergalactic/lib/ui/pages/settings/settings_tab.dart:3` | Optional stable tab id, label, icon, page builder, scroll flag, tab-level keywords, and row-level search metadata | Shared |
| Extra button model | `SettingsButton` | `intergalactic/lib/ui/pages/settings/settings_button.dart:3` | Header-level settings action button model | Shared |
| Search filter | `filterSettingsCategories` | `intergalactic/lib/ui/pages/settings/settings_search.dart:4-26` | Filters categories/tabs by title, label, legacy `searchKeywords`, and row-level `SettingsSearchEntry` metadata | Shared |

### Route Pages

| Visible UI name | Widget/class | File/location | Navigation entry | Dependencies | Surface | Visibility |
| --- | --- | --- | --- | --- | --- | --- |
| App Settings | `AppSettingsPage` | `intergalactic/lib/ui/pages/settings/app_settings_page.dart:10-19` | Opened from desktop main view and login settings button; uses `NavigationUtils.navigateTo` | `clientManager`, `SettingsCategoryAccount`, `SettingsCategoryApp`, `SettingsCategoryHelp`, `SettingsCategoryAbout` | Shared shell | User-facing; Account category appears only when at least one client exists |
| Room Settings | `RoomSettingsPage` | `intergalactic/lib/ui/pages/settings/room_settings_page.dart:9-34` | Opened from main page room settings route and space summary room action | `Room`, optional `CalendarRoomComponent`, `SettingsCategoryRoom` | Shared shell | User-facing for rooms |
| Space Settings | `SpaceSettingsPage` | `intergalactic/lib/ui/pages/settings/space_settings_page.dart:9-31` | Opened from space summary space action | `Space`, `SettingsCategorySpace` | Shared shell | User-facing for spaces |
| Favorites Settings | `FavoritesSettingsPage` | `intergalactic/lib/ui/pages/settings/favorites_settings_page.dart` | Opened from Favorites virtual-space gear | `ClientManager`, `SettingsCategoryFavorites`, local Favorites preferences and category store | Shared shell | User-facing for the local virtual Favorites space |

## 3. Settings Route/Navigation Map

| Source | Destination | File/location | Notes |
| --- | --- | --- | --- |
| Desktop main settings button | `AppSettingsPage` | `intergalactic/lib/ui/pages/main/main_page_view_desktop.dart:370` and `:787` | Primary in-app desktop entry points; routed through `SettingsNavigation.show(...)` |
| Login page settings/about action | `AppSettingsPage` | `intergalactic/lib/ui/pages/login/login_page_view.dart:184-185` | Pre-login entry; Account category is omitted when no clients exist; routed through `SettingsNavigation.show(...)` |
| Main page room settings action | `RoomSettingsPage` | `intergalactic/lib/ui/pages/main/main_page.dart:502-504` | Uses current selected room; routed through `SettingsNavigation.show(...)` |
| Space summary space settings | `SpaceSettingsPage` | `intergalactic/lib/ui/organisms/space_summary/space_summary.dart:90` | Space summary action; routed through `SettingsNavigation.show(...)` |
| App Soundboard card manage action | `SpaceSettingsPage(initialTabId: SettingsCategorySpace.tabIdSoundboard)` | `intergalactic/lib/ui/pages/settings/categories/app/soundboard_settings_page.dart` | Opens the selected space's contextual Soundboard settings from App Soundboard discovery |
| Space summary room settings | `RoomSettingsPage` | `intergalactic/lib/ui/organisms/space_summary/space_summary.dart:94-96` | Room action from space summary; routed through `SettingsNavigation.show(...)` |
| Favorites virtual-space gear | `FavoritesSettingsPage(initialTabId: SettingsCategoryFavorites.tabIdAppearance)` | `intergalactic/lib/ui/molecules/favorite_rooms_list.dart` | Opens contextual Favorites settings; App Appearance no longer owns Favorites icon/banner rows |
| Mobile tab tap | `SettingsSubPage` | `intergalactic/lib/ui/pages/settings/mobile_settings_page.dart:182` | Opens selected tab body with mobile transition |
| Generic navigation helper | `NavigationUtils.navigateTo` | `intergalactic/lib/ui/navigation/navigation_utils.dart:3-10` | Pushes a `PageRouteBuilder` with slide transition |

## 4. File/Class Inventory

### App Settings Category

Category owner class: `SettingsCategoryApp`
File: `intergalactic/lib/ui/pages/settings/categories/app/settings_category_app.dart:21`

| Visible UI name | Widget/class | File/location | Route/navigation entry | Dependencies | Surface | Visibility |
| --- | --- | --- | --- | --- | --- | --- |
| General | `GeneralSettingsPage` | `categories/app/general_settings_page.dart:12` | `settings_category_app.dart:91-115` | `preferences`, `BuildConfig`, `PlatformUtils`, chat privacy and DM lock helpers | Shared tab body | User-facing |
| Appearance | `AppearanceSettingsPage` | `categories/app/appearance_settings_page.dart:18` | `settings_category_app.dart:118-141` | `preferences`, `ThemeChanger`, `AppIconUtils`, theme widgets | Shared tab body with desktop/mobile branches | User-facing |
| Accessibility | `AccessibilitySettingsPage` | `categories/app/accessibility_settings_page.dart` | `settings_category_app.dart` | `preferences`, `AccessibilityScope`, `AccessibilityTokens`, Flutter `MediaQuery` accessibility signals | Shared tab body with live preview | User-facing |
| Activity | `ActivitySettingsPage` | `categories/app/activity_settings_page.dart:19` | `settings_category_app.dart:144-158` | `preferences`, activity/presence components, Spotify/Steam setup flows | Shared tab body with platform gates | User-facing where condition passes |
| Voice and Video | `VoipSettingsPage` | `categories/app/voip_settings/voip_settings_page.dart:22` | `settings_category_app.dart:161-179` | `VoipComponent`, `preferences`, `NoiseSuppressionService`, device pickers, mic/camera test, local voice volume, push-to-talk toggle | Shared tab body | User-facing only when any client has VoIP component |
| Emoticons | `EmoticonsSettingsPage` | `categories/app/emoticons_settings_page.dart` | `settings_category_app.dart:177-195` | Selected `Client`, account/room/space `EmoticonComponent`, `RecentEmoticonComponent` | Shared tab body | User-facing when signed in |
| Soundboard | `SoundboardSettingsPage` | `categories/app/soundboard_settings_page.dart` | `settings_category_app.dart:198-212` | `preferences.soundboardVolume`, joined-space `SoundboardComponent`, contextual `SpaceSettingsPage` jump | Shared tab body | User-facing when signed in |
| Shortcuts | `ShortcutSettingsPage` | `categories/app/shortcut_settings/shortcut_settings_page.dart:9` | `settings_category_app.dart:215-228` | Platform shortcut components, desktop companion shortcut action, custom room/space navigation shortcuts, composer bracket typing preference and wrap-selection shortcut | Shared tab body | Linux/Windows only |
| Notifications | `NotificationSettingsPage` | `categories/app/notification_settings/notification_settings_page.dart:32` | `settings_category_app.dart:233-245` | Notification components, custom sound manager, push gateway prefs, platform permission APIs | Shared tab body with platform gates | User-facing on supported platforms |
| Desktop Companion | `DesktopCompanionSettingsPage` | `categories/app/desktop_companion_settings_page.dart:8` | `settings_category_app.dart:248-260` | `preferences.notificationCompanion*` | Shared tab body | Windows only |
| Developer | `AdvancedSettingsPage` | `categories/app/advanced_settings_page.dart:9` | `settings_category_app.dart:263-274` | `developerMode`, `AccountStateTab`, `NotificationDeveloperSettings`, `VoipDeveloperSettings`, `LogPage`, `DeveloperSettingsPage`, account JSON, push transport/pusher diagnostics, advanced call/stream diagnostics, logs, developer utilities | Shared tab body | User-facing; developer/diagnostic panels appear here when Developer mode is enabled |
| Experiments | `ExperimentsSettingsPage` | `categories/app/experiments_settings_page.dart:6` | `settings_category_app.dart:277-285` | `Experiments`, preference-backed opt-in list | Shared tab body | Hidden unless experiments exist |

### Account Settings Category

Category owner class: `SettingsCategoryAccount`
File: `intergalactic/lib/ui/pages/settings/categories/account/settings_category_account.dart:16`

| Visible UI name | Widget/class | File/location | Route/navigation entry | Dependencies | Surface | Visibility |
| --- | --- | --- | --- | --- | --- | --- |
| Account & Profile | `AccountProfileSettingsTab` | `categories/account/account_profile/account_profile_settings_tab.dart:23` | `settings_category_account.dart:40-63` | `ClientManager`, selected clients, Matrix profile APIs, account-management URLs | Shared tab body with two-pane desktop layout | User-facing when logged in |
| Security | `SecuritySettingsTab` | `categories/account/security/security_tab.dart:9` | `settings_category_account.dart:66-82` | Account recovery, password management, Matrix client encryption, cross-signing, backup/session widgets, account deletion handoff | Shared tab body with direct Account security rows and Matrix-specific sections | User-facing when logged in |
| Account Developer JSON | `AccountStateTab` | `categories/account/account_state/account_state_tab.dart:8` | Rendered from `AdvancedSettingsPage` | Matrix account state | Shared collapsible panel inside App Developer | Developer-mode only; no longer a separate Account tab |

### Room Settings Category

Category owner class: `SettingsCategoryRoom`
File: `intergalactic/lib/ui/pages/settings/categories/room/settings_category_room.dart:20`

| Visible UI name | Widget/class | File/location | Route/navigation entry | Dependencies | Surface | Visibility |
| --- | --- | --- | --- | --- | --- | --- |
| Notifications | `RoomNotificationsSettingsPage` | `categories/room/notifications/room_notifications_settings_page.dart:16` | `settings_category_room.dart` | `Room`, push rules, read receipts, typing indicators, local per-room sound prefs | Shared tab body | User-facing |
| Appearance | `RoomAppearanceSettingsPage` | `categories/room/appearance/room_appearance_settings_page.dart:11` | `settings_category_room.dart` | `Room`, local room background and bubble-color prefs | Shared tab body | User-facing |
| Security | `RoomSecuritySettingsPage` | `categories/room/security/room_security_settings_page.dart` | `settings_category_room.dart` | `Room`, Matrix room encryption, visibility, history visibility | Shared tab body | User-facing |
| Emoticons | `RoomEmojiPackSettingsPage` | `categories/room/emoji_packs/room_emoji_pack_settings_page.dart:7` | `settings_category_room.dart:133-136` | `RoomEmoticonComponent`, permissions/owned packs | Shared tab body | Conditional user-facing |
| Members | `RoomMembersSettingsPage` | `categories/room/members/room_members_settings_page.dart:17` | `settings_category_room.dart:141-145` | `MatrixRoom`, member roles, room permissions | Shared tab body, owns scroll | Matrix rooms only |
| Nicknames | `RoomNicknamesSettingsPage` | `categories/room/nicknames/room_nicknames_settings_page.dart` | `settings_category_room.dart` and pinned Room Members side-panel action | `MatrixRoom`, room display-name state, `canChangeOwnNickname`, `canChangeOtherNicknames` | Shared tab body | Matrix rooms only |
| Admin Settings | `RoomAdminSettingsPage` | `categories/room/admin/room_admin_settings_page.dart` | `settings_category_room.dart` | `Room`, profile/icon/name/topic callbacks, Matrix address settings, room events | Shared tab body | User-facing |
| Permissions | `MatrixRoomPermissionsPage` | `categories/room/permissions/matrix/matrix_room_permissions_page.dart:40` | `settings_category_room.dart:150-153` | `MatrixRoom`, `m.room.power_levels`, calendar permissions if applicable | Shared tab body, owns scroll | Matrix rooms only |
| Calendar | `RoomCalendarSettingsPage` | `categories/room/calendar/room_calendar_settings_page.dart:11` | `settings_category_room.dart:163-165` | `CalendarRoomComponent`, local synced calendar URL prefs | Shared tab body | Calendar rooms only |
| Developer | `RoomDeveloperSettingsView` | `categories/room/developer/room_developer_settings_view.dart:7` | `settings_category_room.dart:170-172` | Room debug data | Shared tab body | Developer-mode only |

### Space Settings Category

Category owner class: `SettingsCategorySpace`
File: `intergalactic/lib/ui/pages/settings/categories/space/settings_category_space.dart:21`

| Visible UI name | Widget/class | File/location | Route/navigation entry | Dependencies | Surface | Visibility |
| --- | --- | --- | --- | --- | --- | --- |
| Notifications | `SpaceNotificationsSettingsPage` | `categories/space/space_notifications_settings_page.dart` | `settings_category_space.dart` | `Space`, Matrix-space room wrapper when available, push rules, read receipts, typing indicators, local desktop sound prefs | Shared tab body | User-facing |
| Emoticons | `SpaceEmojiPackSettings` | `categories/space/space_emoji_pack_settings.dart` | `settings_category_space.dart:107-110` | `RoomEmoticonComponent`, permissions/owned packs | Shared tab body | Conditional user-facing |
| Soundboard | `SpaceSoundboardSettingsPage` | `categories/space/space_soundboard_settings_page.dart:23` | `settings_category_space.dart` | `SoundboardComponent`, Matrix space, file picker/audio upload, join sound settings | Shared tab body | Matrix spaces only |
| Categories | `SpaceCategoriesSettingsPage` | `categories/space/space_categories_settings_page.dart` | `settings_category_space.dart` | `SpaceRoomCategoryStore`, custom Matrix category state, local collapse state, joined room display names, Matrix/admin permission check | Shared tab body | User-facing; management admin-gated |
| Members | `RoomMemberList` | `intergalactic/lib/ui/molecules/user_list.dart:22` | `settings_category_space.dart` | Matrix space room members | Shared tab body, owns scroll | Matrix spaces only |
| Admin Settings | `SpaceAdminSettingsPage` | `categories/space/space_admin_settings_page.dart` | `settings_category_space.dart` | Space profile/banner editing, Matrix address settings, Matrix-space visibility | Shared tab body | User-facing |
| Permissions | `MatrixRoomPermissionsPage` | `categories/room/permissions/matrix/matrix_room_permissions_page.dart:40` | `settings_category_space.dart:122-125` | Matrix space room power levels | Shared tab body, owns scroll | Matrix spaces only |
| Developer | `SpaceDeveloperSettingsView` | `categories/space/space_developer_settings_view.dart:6` | `settings_category_space.dart:131-134` | Space debug data | Shared tab body | Developer-mode only |

### Favorites Settings Category

Category owner class: `SettingsCategoryFavorites`
File: `intergalactic/lib/ui/pages/settings/categories/favorites/settings_category_favorites.dart`

| Visible UI name | Widget/class | File/location | Route/navigation entry | Dependencies | Surface | Visibility |
| --- | --- | --- | --- | --- | --- | --- |
| Appearance | `FavoritesAppearanceSettingsPage` | `categories/favorites/favorites_appearance_settings_page.dart` | `settings_category_favorites.dart` | `preferences.favoritesIconImageData`, `preferences.favoritesBannerImageData`, image picker/crop helpers | Shared tab body | User-facing; local virtual-space presentation only |
| Categories | `FavoritesCategoriesSettingsPage` | `categories/favorites/favorites_categories_settings_page.dart` | `settings_category_favorites.dart` | `ClientManager`, favorite room preferences, `SpaceRoomCategoryStore`, local Favorites category id | Shared tab body | User-facing; local grouping across signed-in accounts/homeservers |

### Help and About Categories

| Visible UI name | Widget/class | File/location | Route/navigation entry | Dependencies | Surface | Visibility |
| --- | --- | --- | --- | --- | --- | --- |
| Help & Safety | `HelpSafetyPage` | `categories/help/help_safety_page.dart:8` | `settings_category_help.dart:30-39` | Matrix client/room selectors, report/block flows, support copy | Shared tab body | User-facing |
| Policies | `HelpPoliciesPage` | `categories/help/help_safety_page.dart:576` | `settings_category_help.dart:42-50` | Policy content/config | Shared tab body | User-facing |
| Tutorial | `HelpTutorialPage` | `categories/help/help_tutorial_page.dart:7` | `settings_category_help.dart:53-61` | `OnboardingService`, `OnboardingPage(replay: true)` | Shared tab body | User-facing |
| About | `_AppInfo` | `categories/about/settings_category_about.dart:35-44` | `SettingsCategoryAbout` tab | Build, source, license, device, encryption info | Shared tab body, no shell scroll | User-facing |

## 5. Reusable Component Inventory

| Component | File/location | Purpose | Current visual pattern | Reuse count | Problems or inconsistencies |
| --- | --- | --- | --- | --- | --- |
| `SettingsPage` | `settings_page.dart:9` | Desktop/mobile shell switch | Delegates to desktop/mobile layout | 4 route pages | Shell is shared, but tab bodies are visually inconsistent |
| `SettingsNavigation` | `settings_navigation.dart` | Settings route helper | Desktop uses centered adaptive non-opaque overlay; mobile keeps slide route | App, room, space, and Favorites settings entry points | Desktop overlay is shared, but individual tab bodies still vary visually |
| `DesktopSettingsPage` | `desktop_settings_page.dart:11` | Desktop settings surface | Overlay chrome, account header, sidebar search/tab list, top close action, centered content pane | All settings routes on desktop | Sidebar/list selection is local state; no deep link per tab |
| `MobileSettingsPage` | `mobile_settings_page.dart:14` | Mobile settings index | Gradient background, mobile cards, search field | All settings routes on mobile | Inner pages often revert to desktop-like content widgets |
| `SettingsSubPage` | `mobile_settings_page.dart:309` | Mobile tab destination | Tiamat `Tile`, custom header/back affordance | All mobile tab opens | Header/spacing differs from many newer mobile app surfaces |
| `SettingsCategory` / `SettingsTab` | `settings_category.dart:3`, `settings_tab.dart:3` | Metadata model | Plain Dart model classes | All settings categories/tabs | Availability, labels, search keywords, and scroll ownership are scattered |
| `filterSettingsCategories` | `settings_search.dart:26` | Search categories/tabs | Query against category title, tab label, keywords | Desktop and mobile shell | Does not index actual setting labels/body text |
| `BooleanPreferenceToggle` | `categories/app/boolean_toggle.dart:8` | Local bool preference row | Title/description plus Material `Switch` | Many app tabs | Only local preference based; similar Matrix toggles are custom per page |
| `NullableBooleanPreferenceToggle` | `categories/app/boolean_toggle.dart:97` | Nullable local bool preference row | Same as bool toggle | Notification/platform flows | Nullable semantics not obvious without page-specific copy |
| `DoublePreferenceSlider` | `categories/app/double_preference_slider.dart:7` | Local numeric preference slider | Label/description plus slider | Appearance, notifications, VoIP | Visual density and reset affordance vary by page |
| `StringPreferenceOptionsPicker` | `categories/app/string_preference_options.dart:6` | Local string preference dropdown | Label/description plus dropdown | Layout/theme/VoIP option rows | Uses dropdown styling that differs from newer mobile controls |
| `MessageBackgroundSettings` | `intergalactic/lib/ui/molecules/message_background_settings.dart:8` | Background image/opacity controls | Reused setting block | App and room appearance | Cross-cuts global and room-level behavior with similar but separate storage |
| `ThemeListWidget` | `theme_settings_widget_io.dart:23`, html `:16`, stub `:4` | Theme selection/import/edit | Platform-specific theme list | Appearance tab | Platform split complicates unified overhaul |
| `CustomThemeEditor` | `theme_settings/custom_theme_editor.dart` | Custom theme creation/editing | Bespoke color/editor UI | Appearance tab | High complexity, should not be redesigned casually |
| `RoomNotificationsSettingsView` | `categories/room/notifications/room_notifications_settings_view.dart:7` | Room push rule selector | Shared room notification row/card | Room and space general notification sections | Separate from global notification visual patterns |
| `RoomAppearanceSettingsView` | `categories/room/appearance/room_appearance_settings_view.dart:17` | Avatar/name/topic/profile controls | Reusable profile editing layout | Room and space appearance | Mixes Matrix profile controls with local background controls nearby |
| `MatrixRoomPermissionsView` | `categories/room/permissions/matrix/matrix_room_permissions_view.dart:11` | Power-level editor rows | Bespoke permission list | Room and space permissions | Risky Matrix state, needs stronger explanations/confirmations |
| `RoomEmojiPackSettingsView` | `categories/room/emoji_packs/room_emoji_pack_settings_view.dart:16` | Emoji/sticker pack editor | Bespoke pack list/import/edit UI | Room and space emoticons | Complex permissions and pack ownership are only partly surfaced |
| `RoomMemberList` | `intergalactic/lib/ui/molecules/user_list.dart:22` | Member list/role editing | Shared member list | Room members and space members | Scroll ownership must be supplied by settings shell metadata |
| `ChatPrivacyPreferences` | `categories/account/preferences/preferences_chat_privacy.dart:8` | Read receipt and typing privacy | Custom preference rows | App General | Similar room-level privacy settings use separate widgets |
| `DmLockPreferences` | `categories/account/preferences/preferences_dm_lock.dart:10` | Local DM lock setup | Custom PIN/lock card | App General | Local-only security behavior needs clear copy in overhaul |
| `MatrixSecurityTab` | `categories/account/security/matrix/matrix_security_tab.dart:13` | E2EE/cross-signing/backup/session security | Account security rows, compact mobile health chips, and encrypted-message tools chooser | Account security | High-risk flows with Matrix-specific terminology |
| `AccountQuickReactionsView` | `categories/account/account_emoji/account_quick_reactions_view.dart:16` | Custom quick reaction slots | Settings-section card with bordered quick-reaction slot buttons | App Emoticons | Shared with double-click reaction behavior; file path remains under the older account folder for now |
| `SettingsButton` | `settings_button.dart:3` | Optional header action | Icon/text button metadata | Limited | Not heavily used; decide whether to keep in overhaul |

## 6. Data/Persistence Map

### Local Preference Layer

Core preference storage is `Preferences` in
`intergalactic/lib/config/preferences.dart:23`. It initializes
`SharedPreferences` at `preferences.dart:87` and exposes typed wrappers for
local app state. Most app-level settings are stored locally and do not sync
through Matrix account data.

Important local keys appear in `preferences.dart:1036-1377`, including:

- Theme/system color/window/developer flags.
- GIF search, sticker compatibility, URL preview in E2EE rooms, message
  effects, automatic message effects, message bubbles, room avatars, media
  previews.
- Favorites icon/banner image data and local virtual Favorites room categories.
- Notification enablement, desktop companion settings, custom notification
  sounds, volume, web push state.
- Message backgrounds and bubble colors.
- VoIP TURN, stream quality, codec, FPS, bitrate, device defaults, Windows
  noise suppression preferences.
- Activity/presence display and provider settings.
- Onboarding completion and version.
- Calendar default view and last download location.

### Settings Areas

| Settings area | Values changed | Storage/persistence | Side effects | Permissions/restart notes |
| --- | --- | --- | --- | --- |
| General | GIF search, URL previews in E2EE rooms, delete confirmation, composer autofocus, auto-open space, minimize-on-close, read receipts, typing indicators, DM lock, offline demo login, message effects, automatic message effects, media preview defaults, mobile media rotation | Local `Preferences` / `SharedPreferences`; Matrix/account privacy components for read receipts and typing | Changes composer/media/room/privacy behavior after next rebuild or component update; automatic message effects require both the parent message-effects toggle and the automatic toggle | Some flags are platform-gated; DM lock remains local-only; automatic message effects default off |
| Appearance | Theme, system theme/colors, app icon mode, global message background, bubble mode/alignment/colors, app/text scale, room preview/avatar display | Local preferences; theme widgets may read/write theme files | `ThemeChanger.setTheme`, `AppIconUtils`; scale/layout updates | Some visual changes may need restart/rebuild; custom theme editor is complex |
| Activity | Local activity display, hide current app, basic status publishing, iOS media controls, Spotify, game/Steam ID, mock source | Local preferences plus activity/presence components | Spotify connect/disconnect, presence/activity publication, media/game detection | Provider-specific; mock source developer-only |
| Voice and Video | Screen-share profile, device defaults, microphone/speaker volume, mic check, camera test, push-to-talk toggle, Windows noise suppression toggle and normal preset | Local preferences | Applies `NoiseSuppressionService` settings, affects future calls/streams and local mic/camera tests; push-to-talk uses the shortcut registry | Some settings are Windows-only or best-effort depending on WebRTC/device support |
| Emoticons | Quick reaction slots, personal packs, favorite packs, available room/space pack discovery | Selected account emoticon/recent-emoticon components; Matrix room/space image-pack state; Matrix account data for global favorites | Updates emoji picker, sticker picker, quick reactions, and favorite pack availability | Requires signed-in selected client; room/space packs are read/discoverable here but managed in their contextual settings |
| Soundboard | Local soundboard volume and joined-space soundboard discovery | Local `preferences.soundboardVolume`; Matrix space soundboard state through `SoundboardComponent` | Preview local sound playback, show available shared call sounds, and open the matching Space Soundboard settings tab | Upload/delete/shared-volume management remains in Space Settings; app page is local volume plus discovery |
| Shortcuts | Outsource/keyboard hook shortcuts, desktop companion toggle shortcut, custom room/space navigation shortcuts, composer bracket auto-close toggle, composer selection wrap shortcut | Platform shortcut storage/components plus local `custom_navigation_shortcuts`, `composer_bracket_typing`, and existing `system_wide_hotkey.*` hotkey storage | Updates keyboard hook/outsource shortcuts, Windows companion enablement, composer text transforms, and app navigation through `EventBus.openRoom` / `EventBus.openSpace` | Linux/Windows only for system hotkeys; composer bracket typing is local and defaults off |
| Notifications | Local `notification_mode`, global notification enablement, focus suppression, media/body/URL preview in notifications, custom sounds, room/space override discovery, web/iOS permission requests | Local preferences plus push/notifier components; Matrix room/space push rules for overrides | Requests permissions, filters local Matrix message notifications in mentions-only mode, previews sounds, opens contextual room/space notification settings | Strong platform divergence; Android/Web server push behavior still depends on platform push transport |
| Desktop Companion | Windows companion enablement, avatar, screen-share preview, reduced motion | Local notification companion preferences | Updates the opt-in always-on-top companion surface | Windows only |
| Developer | Developer mode, Account Developer JSON, push transport/gateway setup, registered pushers, STUN fallback, RNNoise diagnostics/custom tuning, stream override, adaptive fallback, manual stream codec/FPS/bitrate/resolution, WebRTC debug tools, Logs, Developer Utils | Local preferences plus Matrix account-state/debug APIs, push/notifier components, app log storage, and platform/debug APIs | Reveals developer panels; exposes account JSON, pusher diagnostics, expert call connection, stream diagnostics, logs, database dump, window sizing, and debug display controls while preserving existing preference keys | Developer mode required for moved Account, Notification, Voice and Video, Logs, and Developer Utils diagnostics |
| Experiments | Experiment opt-in/out | Local preferences/experiment registry | Enables guarded experimental behavior | Restart often required |
| Account & Profile | Add/logout/remove clients, account-management URL, display name, avatar, banner, pronouns, status, bio, badges, profile color | Client manager/session storage, Matrix logout/account URLs, Matrix profile APIs | Logs out/removes local sessions, opens server account-management link, updates Matrix profile | Account deletion moved to Security; requires selected logged-in client |
| Account security | Password change, account recovery codes, cross-signing, backup, session verification, encrypted-message tools | Matrix account password API, account recovery API, and Matrix E2EE/backup/session APIs | Can affect account password access, encrypted message recovery, and trust state | High-risk security area |
| Account developer | Account state inspection | Matrix account state | Read/debug account state | Developer-mode only |
| Favorites | Favorite virtual-space icon/banner, local favorite room categories, local per-category collapse/order | Local `Preferences` / `SharedPreferences` and `SpaceRoomCategoryStore` under the virtual Favorites id | Updates the local Favorites rail/virtual-space presentation and grouping only | Does not write Matrix room or space state; spans all signed-in accounts/homeservers |
| Room general | Room push rule, room read receipts/typing, room event settings | Matrix push rules and room/client component settings | Updates room notification/privacy/event behavior | Event settings gated by room permissions |
| Room notifications | Room push rule, local custom sound/volume | Matrix push rule plus local prefs keyed by room local ID | Notification delivery and local sound behavior | Custom sounds are local to install |
| Room appearance | Avatar, name, topic, room background/bubble overrides | Matrix room state/profile plus local prefs keyed by room local ID | Updates room profile and local rendering | Avatar/name/topic gated by room permissions |
| Room security | Encryption/join/history/security controls | Matrix room state and room security APIs | Can affect encryption and room access semantics | High-risk; permissions-dependent |
| Room emoticons | Room emoji/sticker packs, import/bulk import | Room emoticon component/Matrix state | Updates room pack availability | Requires edit permission or owned packs |
| Room members | Member roles | Matrix room power levels/member state | Changes permissions and room moderation ability | Requires role-change permission |
| Room permissions | Power-level requirements for room, call, calendar, soundboard actions | Matrix `m.room.power_levels`; write at `matrix_room_permissions_page.dart:526` | Changes who can perform room actions | High-risk; needs clear confirmation |
| Room calendar | Synced calendar URLs and calendar settings | Local preferences via `getSyncedCalendarUrls` / `setSyncedCalendarUrls`; calendar component | Adds/removes external calendar feeds | Calendar rooms only |
| Room developer | Room debug data | Room/Matrix debug state | Read/debug room details | Developer-mode only |
| Space general | Space push rule and Matrix address settings | Matrix push rule/address state | Changes space notification/address behavior | Matrix spaces only for address settings |
| Space appearance | Space profile/topic/banner-ish display fields | Space profile APIs and shared appearance view callbacks | Updates visible space profile | Permission-dependent |
| Space security | Room security page applied to Matrix space room with encryption toggle hidden | Matrix space room state | Changes access/security semantics | Matrix spaces only; high-risk |
| Space soundboard | Sound uploads, names, shared volumes, default/join sounds | `SoundboardComponent` / Matrix space state | Uploads audio, updates shared soundboard | Matrix spaces only; power-level gated |
| Space categories | Shared Inter Galactic room groups for a space sidebar | Custom `chat.intergalactic.space.categories` Matrix state event for category definitions; local `SharedPreferences` only for collapse state keyed by `Space.localId` | Changes Inter Galactic sidebar grouping for users in the space; does not create, remove, or reorder `m.space.child` | Creation and management default to Matrix space admins; viewing/collapse is local |
| Space permissions | Matrix space room power levels | Matrix `m.room.power_levels` | Changes space permissions | High-risk |
| Space members | Matrix space room member list/roles | Matrix member state/power levels | Changes space membership/roles | Permission-dependent |
| Help & Safety | Reports, blocks, help copy | Matrix report/block APIs and local UI state | Sends abuse reports, updates ignored users | Must avoid overpromising safety/privacy |
| Tutorial | Replay onboarding | Local onboarding preferences and route | Opens `OnboardingPage(replay: true)` | Replay should not reset completion |
| About | App/device/build info | Runtime/package/device info | Copy/display only | User-facing |

## 7. Platform Differences

- Desktop uses `DesktopSettingsPage` with a fixed-width sidebar and right
  content pane; mobile uses `MobileSettingsPage` plus `SettingsSubPage`.
- Window behavior controls are currently folded into General on desktop.
- `ShortcutSettingsPage` is Linux/Windows only.
- `NotificationSettingsPage` has the widest platform spread: Linux, Windows,
  Android, iOS, and web, with many platform-specific controls in one file.
- Windows-specific notification companion controls now live in the dedicated
  Desktop Companion app settings tab instead of global notification settings.
- Windows-specific normal RNNoise/noise-suppression controls live inside Voice
  and Video; diagnostics and custom tuning now live behind Advanced/Developer.
- Camera test and camera selection are shared settings, but camera support still
  depends on platform WebRTC availability and call-backend behavior.
- Some activity controls are platform-specific: local media controls are iOS
  gated, game/Steam presence is non-mobile, and mock source is developer-only.
- App-level Soundboard settings discover soundboards from joined Matrix spaces;
  shared sound upload/delete management remains in contextual Space Settings,
  and discovery cards can open the corresponding Space Soundboard tab.
- Custom room/space shortcut definitions are local-only and versionless for
  now; the target is a user-entered Matrix ID, alias, or link plus optional
  account scope, while the actual hotkey remains in the existing system hotkey
  preference namespace.
- Theme list implementation is split between IO, HTML, and stub files.
- Developer settings have IO and stub implementations.
- Room and space settings reuse the same desktop/mobile shell, but their page
  bodies often assume larger surfaces and use manual scroll ownership.

## 8. Current UX Pain Points

- Search can open and highlight a matching row when the result has a route
  anchor. Coverage remains uneven across Help, About, Room, and Space Settings.
- Search keywords and row entries are manually maintained; app/account tabs
  have better row coverage than help/about, room, and space tabs.
- The desktop and mobile shells are coordinated, but tab content uses many
  visual idioms: Tiamat tiles, Material list tiles, raw columns, custom cards,
  expansion panels, bespoke dialogs, and newer mobile cards.
- Some pages still mix safe everyday choices with risky or expert choices.
  Voice and Video and Notifications have moved diagnostics behind Developer,
  but room/space contextual settings still need the same risk-tier treatment.
- Developer/debug surfaces are mostly gated and consolidated under Developer,
  but visual/runtime review with Developer mode on/off is still required.
- Room and space permissions are high-impact Matrix state editors with limited
  progressive explanation.
- Room and space reuse is technically efficient, but labels and copy sometimes
  expose room concepts while editing a space-backed room.
- App General and room privacy are separate implementations, so consistent copy
  and control placement must be checked during redesign.
- Mobile received more recent shell polish than many inner pages; several
  settings bodies still read like desktop forms inside a mobile route.
- `makeScrollable` is a manual per-tab contract. Overhaul work can accidentally
  create nested scroll, clipped lists, or inconsistent mobile behavior.

## 9. Risk Areas Before Overhaul

- Account security, cross-signing, session verification, and key backup.
- Room encryption, join rules, history visibility, and security toggles.
- Matrix room/space power levels and member role editing.
- Notification push setup, web/iOS permission handling, Android/desktop
  notification delivery, and Windows companion settings.
- Account logout, local client removal, and homeserver account-management copy.
- Custom theme import/editing and runtime theme switching.
- VoIP device selection, local volume controls, camera test, push-to-talk,
  TURN fallback, stream overrides, and Windows noise-suppression diagnostics.
- Soundboard upload/state, especially shared Matrix space sounds and power
  level gates.
- Help & Safety report/block behavior and public support/legal copy.
- Pre-login settings access from the login screen; app/help/about must stay
  safe without a client.

## 10. Recommended Overhaul Phases

1. **Information architecture pass**
   - Completed as a documentation-only decision pass in
     `docs/architecture/features/settings-information-architecture.md`.
   - Current routes stay intact: App, Account, Help, About, Room Settings, and
     Space Settings remain the structural shells.
   - Future UI work should use the recorded everyday, account, support/about,
     advanced/developer, and contextual groupings; apply risk-tier copy and
     keep space-specific labels even when sharing room-backed widgets.

2. **Shared settings row and section primitives**
   - Create reusable section, row, switch, slider, dropdown, warning/info, and
     permission-row primitives before restyling pages one by one.
   - Keep Matrix-write pages behaviorally unchanged while swapping visuals.

3. **Search index upgrade**
   - Implemented for migrated App and Account settings by extending
     `SettingsTab` with `SettingsSearchEntry`, route anchors, and row
     highlighting.
   - Next search step is broader row and route-anchor coverage across Help,
     About, Room, and Space Settings.

4. **Mobile shell and Liquid Glass-safe surfaces**
   - Good first mobile candidates: settings index, search header, subpage
     header, Help/About, Appearance preview containers, and non-destructive
     display settings.
   - Avoid applying glass-heavy treatment first to dense security,
     permissions, account removal, or push setup forms.

5. **High-risk settings review pass**
   - Add clearer explanations, confirmation where appropriate, and explicit
     local-vs-Matrix persistence copy for E2EE, power levels, DM lock,
     notification delivery, and account controls.

6. **Platform split cleanup**
   - Separate platform-specific notification, VoIP, theme, and developer
     sections into clearer sub-sections or pages while preserving discoverable
     search.

7. **Validation pass**
   - Static route and search map verification.
   - Manual desktop/mobile settings smoke pass.
   - Focused tests only after behavior changes begin in a later phase.

## 11. Files Likely Involved

### Shell and Model

- `intergalactic/lib/ui/pages/settings/settings_page.dart`
- `intergalactic/lib/ui/pages/settings/desktop_settings_page.dart`
- `intergalactic/lib/ui/pages/settings/mobile_settings_page.dart`
- `intergalactic/lib/ui/pages/settings/settings_category.dart`
- `intergalactic/lib/ui/pages/settings/settings_tab.dart`
- `intergalactic/lib/ui/pages/settings/settings_button.dart`
- `intergalactic/lib/ui/pages/settings/settings_search.dart`
- `intergalactic/lib/ui/navigation/navigation_utils.dart`

### Route Pages

- `intergalactic/lib/ui/pages/settings/app_settings_page.dart`
- `intergalactic/lib/ui/pages/settings/room_settings_page.dart`
- `intergalactic/lib/ui/pages/settings/space_settings_page.dart`

### App Settings

- `intergalactic/lib/ui/pages/settings/categories/app/settings_category_app.dart`
- `intergalactic/lib/ui/pages/settings/categories/app/general_settings_page.dart`
- `intergalactic/lib/ui/pages/settings/categories/app/appearance_settings_page.dart`
- `intergalactic/lib/ui/pages/settings/categories/app/activity_settings_page.dart`
- `intergalactic/lib/ui/pages/settings/categories/app/emoticons_settings_page.dart`
- `intergalactic/lib/ui/pages/settings/categories/app/soundboard_settings_page.dart`
- `intergalactic/lib/ui/pages/settings/categories/app/notification_settings/`
- `intergalactic/lib/ui/pages/settings/categories/app/voip_settings/`
- `intergalactic/lib/ui/pages/settings/categories/app/shortcut_settings/`
- `intergalactic/lib/ui/pages/settings/categories/app/theme_settings/`
- `intergalactic/lib/ui/pages/settings/categories/app/advanced_settings_page.dart`
- `intergalactic/lib/ui/pages/settings/categories/app/experiments_settings_page.dart`
- `intergalactic/lib/ui/pages/settings/categories/app/desktop_companion_settings_page.dart`

### Account Settings

- `intergalactic/lib/ui/pages/settings/categories/account/settings_category_account.dart`
- `intergalactic/lib/ui/pages/settings/categories/account/account_management/`
- `intergalactic/lib/ui/pages/settings/categories/account/profile/`
- `intergalactic/lib/ui/pages/settings/categories/account/preferences/`
- `intergalactic/lib/ui/pages/settings/categories/account/security/`
- `intergalactic/lib/ui/pages/settings/categories/account/account_emoji/`
- `intergalactic/lib/ui/pages/settings/categories/account/account_state/`

### Room and Space Settings

- `intergalactic/lib/ui/pages/settings/categories/room/settings_category_room.dart`
- `intergalactic/lib/ui/pages/settings/categories/room/general/`
- `intergalactic/lib/ui/pages/settings/categories/room/notifications/`
- `intergalactic/lib/ui/pages/settings/categories/room/appearance/`
- `intergalactic/lib/ui/pages/settings/categories/room/security/`
- `intergalactic/lib/ui/pages/settings/categories/room/permissions/`
- `intergalactic/lib/ui/pages/settings/categories/room/members/`
- `intergalactic/lib/ui/pages/settings/categories/room/emoji_packs/`
- `intergalactic/lib/ui/pages/settings/categories/room/calendar/`
- `intergalactic/lib/ui/pages/settings/categories/space/settings_category_space.dart`
- `intergalactic/lib/ui/pages/settings/categories/space/`

### Help, About, Developer

- `intergalactic/lib/ui/pages/settings/categories/help/settings_category_help.dart`
- `intergalactic/lib/ui/pages/settings/categories/help/help_safety_page.dart`
- `intergalactic/lib/ui/pages/settings/categories/help/help_tutorial_page.dart`
- `intergalactic/lib/ui/pages/settings/categories/about/settings_category_about.dart`
- `intergalactic/lib/ui/pages/settings/categories/developer/`

### Shared Config and Components

- `intergalactic/lib/config/preferences.dart`
- `intergalactic/lib/config/preferences/`
- `intergalactic/lib/ui/molecules/message_background_settings.dart`
- `intergalactic/lib/ui/molecules/user_list.dart`

## 12. Open Questions

- Phase 1 answered that the future settings IA should keep Account, App, Help,
  About, Room Settings, and Space Settings as the structural shells for now.
  See `docs/architecture/features/settings-information-architecture.md`.
- Phase 1 answered that room and space settings may continue sharing tab bodies
  where useful, but space pages need space-specific labels and explanatory copy
  when room-backed Matrix behavior is visible.
- Should search become a first-class settings registry with row-level keywords
  and route anchors, or remain a tab-level filter?
- Which settings must remain reachable from the pre-login settings entry?
- Should developer/debug settings move behind a separate Developer area instead
  of appearing inside App and About categories?
- Which settings should explicitly state "local only" versus "saved to your
  Matrix server"?
- Should notification settings be split further by delivery layer: in-app
  behavior, device/platform permissions, push gateway, and sounds?
- Should Voice and Video get a deeper runtime pass to refresh active capture
  immediately when microphone volume changes, or is next-capture application
  enough for this settings phase?
- Should the mobile overhaul use Liquid Glass treatment only for chrome and
  low-risk sections at first, with dense/risky forms staying more opaque?
- What minimum manual validation matrix is required before a visual-only
  settings overhaul lands across desktop, Android, iOS, and web?
