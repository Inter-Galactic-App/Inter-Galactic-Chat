# Component Patterns

Status: active design reference
Owner: DESIGN
Last updated: 2026-05-13

## Purpose

This file maps visible design patterns to current code anchors. Use it when
deciding whether a new component should reuse an existing primitive or whether a
shared primitive should be extracted.

## Core Primitives

| Pattern | Preferred implementation | Purpose |
| --- | --- | --- |
| Surface tile | `tiamat/lib/atoms/tile.dart` | Semantic surface layers for app panels, cards, and rows. |
| Glass surface | `tiamat/lib/atoms/glass_tile.dart` | Backdrop blur surface for focused glass treatments. |
| Primary/secondary/danger buttons | `tiamat/lib/atoms/button.dart` and app settings buttons | Standard action styling and loading behavior. |
| Icon buttons | `tiamat/lib/atoms/icon_button.dart`, `circle_button.dart` | Compact tool and rail actions. |
| Text styles | `tiamat/lib/atoms/text.dart`, `SettingsTypography` | App text and settings regular-weight override. |
| Switches | `tiamat/lib/atoms/switch.dart` and settings preference wrappers | Binary controls. |
| Sliders | `tiamat/lib/atoms/slider.dart`, settings slider helpers | Numeric local preferences. |
| Dropdown selectors | `tiamat/lib/atoms/dropdown_selector.dart` and settings option pickers | Enum/string choices. |

## Settings Patterns

| Pattern | File/class | Use |
| --- | --- | --- |
| Desktop overlay route | `intergalactic/lib/ui/pages/settings/settings_navigation.dart` | Adaptive modal desktop settings frame with blurred backdrop. |
| Desktop shell | `intergalactic/lib/ui/pages/settings/desktop_settings_page.dart` | Sidebar, search, account header, close button, and content pane. |
| Mobile shell | `intergalactic/lib/ui/pages/settings/mobile_settings_page.dart` | Mobile grouped settings index and subpage navigation. |
| Settings typography | `settings_typography.dart` | Roboto regular settings text treatment. |
| Settings sections/rows | `categories/app/setting_row.dart` | Standard title, description, trailing control, and divider treatment. |
| Settings search | `settings_search.dart` | Row-level search and aliases for moved settings. |
| Category/tab model | `settings_category.dart` | Shared app/account/help/context settings navigation metadata. |

Settings pages should reuse these before inventing custom list rows.

## Mobile Surface Patterns

| Pattern | File/class | Use |
| --- | --- | --- |
| Mobile visual tokens | `intergalactic/lib/ui/mobile/mobile_visuals.dart` | Mobile spacing, radius, blur, and highlight constants. |
| Section card | `MobileSectionCard` in `mobile_surface.dart` | Rounded mobile settings and grouped controls. |
| Pill action | `MobilePillButton` in `mobile_surface.dart` | Touch-friendly mobile list actions. |
| Glass edge highlight | `MobileGlassEdgeHighlight` in `mobile_surface.dart` | Mobile liquid-glass-style edge treatment translated to Flutter. |

## Chat Patterns

| Pattern | File/class | Use |
| --- | --- | --- |
| Chat view layout | `intergalactic/lib/ui/organisms/chat/chat_view.dart` | Timeline, background, composer placement, mobile bottom insets. |
| Message input | `intergalactic/lib/ui/molecules/message_input.dart` | Composer, attachment menu, slash commands, emoji/sticker/GIF panels. |
| Room side panel | `intergalactic/lib/ui/organisms/room_side_panel/room_side_panel.dart` | Thread/details side-panel surfaces. |
| Side navigation rail | `intergalactic/lib/ui/organisms/side_navigation_bar/side_navigation_bar.dart` | Space/room rail actions, tooltips, alert badges. |

Chat changes should be tested against bottom anchoring, keyboard behavior, and
message visibility behind the composer.

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
