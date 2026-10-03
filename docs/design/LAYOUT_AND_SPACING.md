# Layout And Spacing

Status: active design reference
Last updated: 2026-05-13

## Layout Principles

Inter Galactic layouts should feel spacious without wasting working area. The
app has two main density modes:

- Desktop: productive, multi-pane, hover-capable, and width-aware.
- Mobile: grouped, touch-friendly, glass-forward, and safe-area aware.

## Desktop Settings

Desktop settings use an adaptive overlay, not a full-window route.

Current standard:

- Overlay safe margin: 24px.
- Overlay preferred width: about 79-88 percent of available width depending on
  large desktop breakpoints.
- Overlay preferred height: about 90 percent of available height.
- Minimum useful frame: about 760px wide and 560px tall.
- Sidebar width: about 250px.
- Header height: about 48px.
- Content max width: about 960px unless a page intentionally uses a two-pane
  layout.
- Main content padding: about 44px left/right/top with 36px bottom.

Use two-pane desktop layouts for edit/preview flows, account/profile editing,
theme editing, and other surfaces where feedback is immediate.

## Mobile Settings

Mobile settings use grouped cards and safe-area padding.

Current mobile visual tokens:

- Screen padding: 16px.
- Section spacing: 16px.
- Card radius: 28px.
- Panel radius: 32px.
- Pill radius: 999px.
- Mobile list item height: about 52px.
- Grouped section padding: 14px horizontal, 12px vertical.
- Mobile blur radius: about 26px.

Keep unscrollable headers compact. If a page has long controls, let the content
area own the scroll or use segmented/swipeable panes.

## Rows And Controls

Settings rows:

- Horizontal padding: about 16px.
- Vertical padding: about 10px.
- Stack trailing controls below content below about 520px width.
- Keep title, description, and control alignment consistent.

Sliders:

- Use two-column label/value slider layouts where the value and control need to
  be compared.
- Apply preference changes as the slider settles when the setting is safe to
  preview live.
- Avoid apply buttons for simple local scale sliders.

Toggles:

- Use the existing toggle design rather than bespoke switches.
- Inline toggles are appropriate for simple binary local preferences.

Dropdowns:

- Use darker/dropdown-style controls for settings that already use that visual
  family.
- Avoid light unthemed dropdowns on dark surfaces.

## Cards And Surfaces

Panel cards should usually use `surfaceContainerLow`. The surrounding main pane
should usually be `surfaceContainer`. Sidebars should usually be
`surfaceContainerLow`.

Use `surfaceContainer` for collapsible developer group containers when inner
cards need `surfaceContainerLow` contrast.

Do not place scrollbars in the visual gap between two panes unless that gap is
the actual scroll owner. Prefer the right edge of the popout or content pane.

## Chat Layout

Chat must preserve the bottom neutral position:

- On room open, the latest message sits above the composer.
- Opening the keyboard keeps the latest message in the same relative position
  above the composer.
- Sending a message returns to neutral.
- When users scroll up, messages may pass behind the composer.

Composer popup menus should float above the input and not expand the composer
height.

## Compact Desktop

Small-window desktop remains desktop UI, not mobile UI. Use compact desktop
patterns:

- Preserve room navigation, timeline, and composer.
- Shorten headers and chrome.
- Use hover-reveal panels.
- Keep side rails available but compact.
- Avoid switching to mobile route architecture on desktop windows.

## Spacing Anti-Patterns

- Giant unscrollable mobile headers above long forms.
- Desktop dialogs that stay narrow while the window has useful width.
- Side-by-side panes with inner scrollbars fighting the outer scroll.
- Cards inside cards where surfaces are only decorative.
- Text that wraps inside buttons because action containers are too narrow.
