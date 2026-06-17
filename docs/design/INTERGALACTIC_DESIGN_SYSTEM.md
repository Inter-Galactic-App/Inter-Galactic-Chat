# Inter Galactic Design System

Status: active design reference
Owner: DESIGN
Last updated: 2026-05-13

## Purpose

This document defines the product design language for Inter Galactic. It is a
reference for new UI, settings work, theme work, reviews, and future refactors.
It describes the app as it exists after the recent settings, mobile composer,
theme workshop, contextual settings, and desktop overlay passes.

This is not a redesign brief. It captures the current direction so future work
can extend it consistently.

## Product Feel

Inter Galactic should feel like a calm sci-fi utility: capable, layered, and a
little atmospheric, but never noisy. The UI should make Matrix concepts feel
approachable without hiding important risk or permission boundaries.

Core principles:

- Content first: messages, rooms, calls, settings values, and media should be
  easier to scan than the surfaces around them.
- Layered depth: use surface layers, soft blur, borders, and shadows to show
  where interaction lives.
- Lightweight hierarchy: prefer spacing, grouping, and surface level over heavy
  typography.
- Desktop productivity: desktop layouts should use available width, show
  related panes together, and keep scroll ownership predictable.
- Mobile immersion: mobile can use glass, rounded panels, and swipe or segmented
  navigation, but input and content must stay reachable.
- Playful, not childish: icons, emoji, badges, reactions, soundboards, and
  activity can be expressive while the layout stays composed.
- Clear risk: privacy, encryption, account deletion, server-affecting settings,
  and developer diagnostics need plain explanations.

## Visual Language

The visual language is based on Material color tokens with Inter Galactic
surface layering.

Primary layers:

- Foundation or page background: the deepest app backdrop.
- `surface`: normal app page background.
- `surfaceContainer`: main overlay or right-side settings pane.
- `surfaceContainerLow`: sidebars and panel cards.
- `surfaceContainerLowest`: deepest small controls, inputs, and selected rows
  when the design needs a recessed feel.
- `surfaceContainerHigh` / `surfaceContainerHighest`: hover, emphasis, raised
  controls, and preview highlights.

Use elevation sparingly. Cards should usually be flat layered surfaces with a
visible outline. Shadows are for modal frames, profile previews, floating
popups, and mobile glass surfaces.

Desktop edge highlights and small active frames on composer, picker, menu, and
account-popup surfaces should use `ColorScheme.outline` with adjusted alpha.
Avoid deriving those highlight strokes from `onSurface`, accent colors, or
hard-coded black so custom themes can adapt the chrome consistently.

## Typography

Settings use `RobotoCustom` regular weight through `SettingsTypography`.
Settings headings should not be bold by default.

Recommended settings scale:

- Page title: about 18px, regular.
- Section title: about 18px, regular.
- Setting title: about 15px, regular.
- Description/help text: about 12px, regular, line height near 1.25.

Avoid negative letter spacing. Avoid viewport-scaled text. Use emphasis through
placement, color, and spacing before adding weight.

## Shape

Common radii:

- Desktop settings overlay: 24px outer frame.
- Desktop cards and repeated settings blocks: usually 8-16px depending on the
  existing component family.
- Mobile section cards: 28px.
- Mobile panels: 32px.
- Pills and small toggle-like actions: 999px.

Do not nest card-looking surfaces inside other card-looking surfaces unless the
inner card is a real repeated item or a collapsible group with its own meaning.

## Motion

Motion should clarify state, not perform. Current preferred patterns:

- Desktop settings overlay: quick fade/scale, about 180ms in and 140ms out.
- Mobile settings route: slide up with ease-out cubic, about 500ms.
- Popups and menus: short fade/scale or anchored expansion.
- Keyboard/composer transitions: follow platform movement when possible and
  avoid independent lag.

Avoid animations that change reading position unexpectedly.

## Interaction Standards

Normal click or tap should select or open the most likely next task. Secondary
actions should live in hover toolbars, trailing controls, context menus, or
explicit buttons.

Examples:

- Photo room tile click opens comments; full-size viewing uses explicit toolbar
  affordance.
- Message double click/tap can apply the configured first quick reaction.
- Mobile plus and slash-command menus use popup tiles rather than expanding the
  composer height.
- Settings risky actions require clear labels and confirmation.

## Platform Treatment

Desktop:

- Use adaptive overlays for settings and similar app-level panels.
- Prefer two-pane layouts when edit and preview are connected.
- Keep scrollbars on the outer edge of the active popout/pane when practical.
- Use hover affordances where they reduce clutter.

Mobile:

- Use mobile section cards and glass edge highlights for grouped settings.
- Keep primary actions reachable above the keyboard and safe areas.
- Composer chrome should let messages remain visible behind clear surrounding
  areas; blur should apply to the input pill or intentional glass surface, not
  the whole surrounding card by default.
- Use swipeable or segmented panes when one-column space is too tight.

## Implementation Map

Important implementation anchors:

- Settings shell: `intergalactic/lib/ui/pages/settings/`
- Settings typography: `settings_typography.dart`
- Settings rows and sections: `setting_row.dart`
- Mobile settings visuals: `intergalactic/lib/ui/mobile/mobile_visuals.dart`
- Mobile section/glass surfaces: `intergalactic/lib/ui/mobile/mobile_surface.dart`
- Chat and composer: `intergalactic/lib/ui/organisms/chat/`
- Main side rail: `intergalactic/lib/ui/organisms/side_navigation_bar/side_navigation_bar.dart`
- Theme definitions: `tiamat/lib/config/style/`
- Tiamat tiles/buttons/inputs: `tiamat/lib/atoms/`

See the companion files in this directory for specific UI, theme, spacing, and
component guidance.

## Related Architecture Docs

- `docs/architecture/features/settings-ui-map.md`
- `docs/architecture/features/settings-information-architecture.md`
- `docs/design/THEME_GUIDELINES.md`
- `docs/architecture/features/desktop-small-window-mode.md`
