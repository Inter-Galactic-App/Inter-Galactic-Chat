# Component Patterns

Status: active design reference
Owner: DESIGN
Last updated: 2026-06-29

## Purpose

This file maps visible design patterns to current code anchors. Use it when
deciding whether a new component should reuse an existing primitive or whether a
shared primitive should be extracted.

## Core Primitives

| Pattern | Preferred implementation | Purpose |
| --- | --- | --- |
| Surface tile | `tiamat/lib/atoms/tile.dart` | Semantic surface layers for app panels, cards, and rows. |
| Glass surface | `tiamat/lib/atoms/glass_tile.dart` | Backdrop blur surface for focused glass treatments. |
| Primary/secondary/success/danger buttons | `tiamat/lib/atoms/button.dart` and app settings buttons | Standard action styling and loading behavior using theme token pairs rather than literal success/error hues. |
| Icon buttons and toggles | `tiamat/lib/atoms/icon_button.dart`, `circle_button.dart`, `icon_toggle.dart`, app-local `intergalactic/lib/ui/atoms/icon_button.dart` where already used | Compact tool and rail actions with semantic labels, tooltips, keyboard activation, visible focus, and larger-target support. Toggle state must expose On/Off semantics and a non-color visual cue. |
| Text styles | `tiamat/lib/atoms/text.dart`, `SettingsTypography` | App text and settings regular-weight override; shared Tiamat text respects the resolved `MediaQuery.boldText` signal. |
| Link text | `intergalactic/lib/ui/atoms/rich_text/spans/link.dart` | Shared message/rich-text links use resolved accessibility link tokens and underline behavior. |
| Switches | `tiamat/lib/atoms/switch.dart` and settings preference wrappers | Binary controls with optional semantic labels, On/Off values, and shared settings-row activation. |
| Sliders | `tiamat/lib/atoms/slider.dart`, settings slider helpers | Numeric local preferences. |
| Dropdown selectors | `tiamat/lib/atoms/dropdown_selector.dart` and settings option pickers | Enum/string choices. |
| Motion tokens | `intergalactic/lib/ui/motion/inter_galactic_motion.dart` | Shared durations, curves, and reduced-motion helpers for UI transitions. |
| Accessibility resolver/tokens | `intergalactic/lib/ui/accessibility/` | Shared effective settings, platform accessibility signals, semantic colors, focus, motion, density, and text-scale resolution. |
| Accessible interactive region | `intergalactic/lib/ui/accessibility/accessible_interactive_region.dart` | Shared keyboard activation, semantics, focus rings, and optional larger-target constraints for custom tappable regions. |
| Notification badge | `intergalactic/lib/ui/atoms/notification_badge.dart` | Theme-token unread, mention, invitation, and alert count badges with shared count-change motion. |
| Settings status components | `intergalactic/lib/ui/pages/settings/settings_status_components.dart` | Shared settings status chips and empty/loading/error panels. |
| Settings search anchors | `intergalactic/lib/ui/pages/settings/settings_search_anchor.dart` | Optional row and chrome targets for search-result scroll/highlight feedback. |
| Adaptive dialogs | `intergalactic/lib/ui/navigation/adaptive_dialog.dart`, `tiamat/lib/atoms/popup_dialog.dart` | Shared desktop popup and mobile bottom-sheet dialog frame with route semantics, meaningful barrier labels, request-focus behavior, focus traversal grouping, and reduced-motion-safe presentation. |
| Floating/detached surface boundary | Local transparent `Material`, `Overlay.wrap(...)` for secondary views, explicit media sizing | Prevents Flutter white debug error chrome and blank popouts on custom room, favorites, media, call, and detached-window surfaces that use ink, tooltip, menu, or overlay controls. |
| Reduce-transparency surface bridge | `settings_navigation.dart`, `mobile_surface.dart` | App-owned blur/glass wrappers that read `AccessibilityScope` and switch to solid theme-token surfaces when reduced transparency is active. |
| Desktop window chrome | `intergalactic/lib/ui/windows/desktop_window_chrome.dart` | Windows desktop-only custom title bar and frame wrapper. Uses the space-rail surface token, keeps non-button title-bar space draggable/resizable through `window_manager`, exposes Back/Forward/FAQ/window controls, and leaves mobile/web/macOS/Linux native chrome unchanged. |
| State and recovery matrix | `docs/design/STATE_AND_RECOVERY_PATTERNS.md` | Copy, action, layout, accessibility, and motion rules for empty, loading, offline, reconnecting, and error states. |

## Settings Patterns

| Pattern | File/class | Use |
| --- | --- | --- |
| Desktop overlay route | `intergalactic/lib/ui/pages/settings/settings_navigation.dart` | Adaptive modal desktop settings frame with blurred backdrop. |
| Desktop shell | `intergalactic/lib/ui/pages/settings/desktop_settings_page.dart` | Sidebar, search, account header, close button, and content pane. |
| Mobile shell | `intergalactic/lib/ui/pages/settings/mobile_settings_page.dart` | Mobile grouped settings index and subpage navigation. |
| Settings typography | `settings_typography.dart` | Roboto regular settings text treatment. |
| Settings sections/rows | `categories/app/setting_row.dart` | Standard title, description, trailing control, and divider treatment. |
| Settings search | `settings_search.dart` | Row-level search and aliases for moved settings. |
| Search anchor/highlight | `settings_search_anchor.dart` plus `SettingsSearchEntry.anchorId` | Scroll and briefly highlight the exact row or chrome control opened from a row-level search hit. |
| Category/tab model | `settings_category.dart` | Shared app/account/help/context settings navigation metadata. |
| Status chip | `settings_status_components.dart` / `SettingsStatusChip` | Compact text+icon state pills for metadata, success, warning, and blocking states. |
| State panel | `settings_status_components.dart` / `SettingsStatePanel` | Settings empty, loading, retry, and "more results" panels with responsive action placement. |
| Action chooser card | `settings_status_components.dart` / `SettingsActionChoiceCard` | High-risk utility choices where users need plain-language differences before choosing an action. |

Settings pages should reuse these before inventing custom list rows.

Accessibility settings live under App Settings > Accessibility. New controls
should prefer `AccessibilityScope.of(context)` for effective behavior and
`AccessibilityScope.tokensOf(context)` for semantic colors and density instead
of reading raw preference strings. Defaults follow platform signals where
Flutter exposes them; app overrides persist through `Preferences`; reset returns
new accessibility preferences to `system`.
`AccessibilityScope` publishes resolved text scaling and bold text back through
descendant `MediaQuery` data so shared app and Tiamat text primitives can follow
the same platform-compatible signal rather than importing app-only settings.
Shared rich-text links should use `LinkSpan.create(...)` so color-safe,
high-contrast, and underline-link settings flow through one tokenized path.

Shared app-owned overlay, glass, or translucent mobile surfaces must honor
`AccessibilityScope.of(context).reduceTransparency` by removing backdrop blur,
glass edge highlights, and translucent gradients in favor of solid theme-token
surfaces. Tiamat-only primitives cannot read app scope directly, so app wrappers
should bridge the setting before rendering glass or tile layers.

Use semantic state tokens (`success`, `warning`, `danger`, `statusOnline`,
`statusBusy`, `focusRing`, `linkText`) instead of raw red/green/orange values.
Status, alert, unread, and call/story preview states must include non-color
cues when `nonColorStateCues` is active. Existing settings switches should use
the shared app settings toggle helper so On/Off labels, row-level state
semantics, and keyboard activation appear when the platform or app
accessibility setting asks for them.

Row-level search entries can set `anchorId` when the searchable label differs
from the visible target. Otherwise `SettingsControlRow` derives a stable anchor
from its title and participates automatically. Use
`SettingsSearchHighlightTarget` for non-row controls such as shared settings
chrome. Desktop and mobile settings shells should trigger the shared highlight
controller after opening the target tab, so `Scrollable.ensureVisible` can find
the nearest scroll owner. The highlight uses semantic primary/outline tokens
and shared motion durations, with reduced motion collapsing scroll animation.

Status chips should always include both an icon and text. Use compact labels
for mobile when the full label is long, but keep the semantic label aligned
with the full meaning. State panels should use the same surface, outline, and
regular-weight settings typography as settings rows, with actions stacked below
the copy on narrow widths.

Action chooser cards should use semantic tone tokens, an icon, concise title,
clear description, and a separate detail line that distinguishes what the
choice does not do. Keep the action at least 150px wide on desktop and stacked
below the copy on compact widths so high-risk labels do not clip.

For empty, loading, offline, reconnecting, permission, retry, and partial
content states, first choose the state type and user-available action from
`STATE_AND_RECOVERY_PATTERNS.md`. Do not add local one-off empty/error cards
when `SettingsStatePanel` or an existing surface-specific equivalent can carry
the state.

For focus and hover parity, use
`ACCESSIBILITY_FOCUS_AND_HOVER_AUDIT.md` as the current selected-domain smoke
checklist. Required actions must have keyboard and mobile paths, not only
desktop hover controls. Custom clickable regions that are not already native
Material controls should use `AccessibleInteractiveRegion` so focus rings,
keyboard activation, action semantics, and larger-touch-target mode stay
consistent across rail buttons, room rows, space icons, composer icon controls,
and virtual-space rows.
Use its `persistentLabel` option only for genuinely icon-only actions where a
visible label helps; keep the semantic label descriptive and the persistent
label short enough for compact desktop/mobile layouts.

App-local icon-only controls should either use a Tiamat/material icon button
that already exposes labels and focus, or the app-local `IconButton` wrapper,
which routes legacy compact controls through `AccessibleInteractiveRegion`.
Tiamat `IconButton` and `CircleButton` expose native semantics, tooltip,
Enter/Space activation, visible focus rings, and optional minimum target sizes
without depending on app-only accessibility scope. Tiamat `IconToggle` adds
toggle semantics, On/Off values, and default off-state icon variants for common
icons such as favorite/public so enabled state is not conveyed by color alone.
Tiamat `Switch` can opt into explicit semantic labels, On/Off values, and
toggle actions for standalone switch surfaces; settings toggles should still
prefer the shared app settings row helper.
Prefer an explicit `semanticLabel`; fallback icon labels are only for legacy
callers.

Dialogs and picker sheets should use `AdaptiveDialog` unless a surface has a
documented custom route requirement. The desktop path uses `PopupDialog`; the
mobile path uses a bottom sheet. Both paths should keep route titles semantic,
use title- or action-specific barrier labels, request focus when opened, group
focus traversal inside the dialog, and honor platform/app reduced-motion
signals. Do not add local dialog animations or unlabeled barriers for standard
confirmation, picker, text-prompt, image, recovery, invite, or settings flows.

Floating media, detached-window, and custom room/list surfaces need their own
Flutter boundary primitives when they use ink, tooltip, menu, or overlay
controls. Add a local transparent `Material` before custom `InkWell`/tooltip
families and add `Overlay.wrap(...)` inside secondary Flutter views such as
`ViewAnchor` hosts. Keep media tiles explicitly sized in shrink-wrapped popout
frames, start new call/video popouts opaque, and make transparent chrome an
in-memory per-window state. This is the durable fix pattern for the recurring
white Flutter error chrome seen in detached call popouts, Favorites section
toggles, and other custom popout/video surfaces.

## Mobile Surface Patterns

| Pattern | File/class | Use |
| --- | --- | --- |
| Mobile visual tokens | `intergalactic/lib/ui/mobile/mobile_visuals.dart` | Mobile spacing, radius, blur, and highlight constants. |
| Section card | `MobileSectionCard` in `mobile_surface.dart` | Rounded mobile settings and grouped controls; uses solid surfaces when reduced transparency is active. |
| Pill action | `MobilePillButton` in `mobile_surface.dart` | Touch-friendly mobile list actions; removes translucent gradients when reduced transparency is active. |
| Glass edge highlight | `MobileGlassEdgeHighlight` in `mobile_surface.dart` | Mobile liquid-glass-style edge treatment translated to Flutter; suppresses decorative highlights when reduced transparency is active. |

## Chat Patterns

| Pattern | File/class | Use |
| --- | --- | --- |
| Chat view layout | `intergalactic/lib/ui/organisms/chat/chat_view.dart` | Timeline, background, composer placement, mobile bottom insets. |
| Message input | `intergalactic/lib/ui/molecules/message_input.dart` | Composer, attachment menu, slash commands, emoji/sticker/GIF panels. |
| Room side panel | `intergalactic/lib/ui/organisms/room_side_panel/room_side_panel.dart` | Thread/details side-panel surfaces. |
| Side navigation rail | `intergalactic/lib/ui/organisms/side_navigation_bar/side_navigation_bar.dart` | Space/room rail actions, tooltips, alert badges. |

Chat changes should be tested against bottom anchoring, keyboard behavior, and
message visibility behind the composer.

Navigation badges should use `NotificationBadge` rather than local red, orange,
or count-pill treatments. Pick `accent` for invitations or selected attention,
`warning` for room-wide mentions and non-destructive alerts, `danger` for
highlighted unread counts, and `neutral` for count overlays inside an already
toned attention button. Count changes use `InterGalacticMotion.short` with an
instant reduced-motion fallback, and large counts keep the existing compact
`9+` clamp.

## Space And Room List Patterns

| Pattern | File/class | Use |
| --- | --- | --- |
| Space summary room row | `intergalactic/lib/ui/atoms/room_panel.dart` | Room rows in wide selected-space and virtual-space summary panes, including last-message preview. |
| Space sidebar room row | `intergalactic/lib/ui/atoms/room_text_button.dart` | Compact room rows inside sidebars and narrow selected-space panels. |
| Space reorder affordance | `ReorderableListView` plus save/undo actions in `space_summary_view.dart` | Drag/drop room ordering where the surface presents a selected-space room list. |
| Virtual Favorites space | `intergalactic/lib/ui/molecules/favorite_rooms_list.dart` | Favorites behaves as a local virtual selected space, reusing the same wide/sidebar row primitives, local categories, and local-only icon/banner presentation preferences. |
| Favorites settings | `intergalactic/lib/ui/pages/settings/favorites_settings_page.dart` | Contextual Favorites settings surface with Appearance and Categories tabs, opened from the Favorites virtual-space gear rather than App Appearance. |

Do not invent separate Favorites room-list rows. The wide Favorites pane should
match selected-space summary behavior (`RoomPanel` rows, preview text, reorder
save/undo), while compact Favorites panes should match space sidebars
(`RoomTextButton` rows, tapered category header, rail-safe density). Favorites
icon/banner controls and Favorites categories are local preferences, not Matrix
room or space state. Use `FavoritesSettingsPage` for Favorites-specific
appearance and category management so multi-account and multi-homeserver users
have one contextual place to organize their virtual Favorites space.

## Theme Patterns

| Pattern | File/class | Use |
| --- | --- | --- |
| Built-in theme data | `tiamat/lib/config/style/theme_*.dart` | Default theme definitions. |
| Theme extensions | `tiamat/lib/config/style/theme_extensions.dart` | Extra app theme values beyond Material defaults. |
| Custom theme model | `intergalactic/lib/config/custom_theme_definition.dart` | Persisted custom theme schema and editable fields. |
| Theme settings | `intergalactic/lib/ui/pages/settings/categories/app/theme_settings/` | Theme selection, import/export, custom theme editor. |

When a visual bug appears only in custom-theme previews, compare the preview
resolver with the built-in theme resolver before changing token values.

## Context Settings Patterns

Room and space settings now mirror app-level settings where possible.

| Pattern | Area | Guidance |
| --- | --- | --- |
| Notification modes | Room, space, app notifications | Use selectable mode cards consistently. |
| Privacy overrides | Room and space privacy settings | Use compact dropdown selectors. |
| Soundboard rows | Space and app soundboard settings | Use card rows with emoji/icon, sound name, and destination action. |
| Emoticon packs | App, room, and space emoticons | Reserve uniform collapsed space and show placeholders when no image exists. |
| Members/permissions | Room and space members/admin settings | Use stable cards, readable permission bubbles, and edge-aligned scrollbars. |

## Developer Patterns

Developer settings belong under Developer and should use collapsible groups.

Recommended order:

- Logs.
- Account State JSON.
- Notification developer settings.
- Voice and Video developer settings.
- Experiments.
- Developer Utils.

Developer group containers should be `surfaceContainer` when they contain
`surfaceContainerLow` cards.

## Standardization Gaps

These are not immediate bugs, but they are good candidates for future cleanup:

- Some feature pages still define one-off cards instead of shared settings row
  primitives.
- Voice/call diagnostics have unique layout needs and should keep explicit
  ownership checks before major visual refactors.
- Mobile and desktop versions sometimes share state but not layout primitives;
  keep responsive behavior intentional.
- Theme preview fidelity should remain under review when built-in theme
  snapshots or token mappings change.
