# Theme Guidelines

Status: active design reference
Last updated: 2026-07-02

## Theme Philosophy

Themes should preserve Inter Galactic's hierarchy while changing mood. Accent
colors can vary widely, but surface relationships, outlines, disabled states,
and readable contrast must remain stable.

Default theme names:

- Sol
- Dark Matter
- Nebula
- Eclipse
- Aurora
- Cosmic Stardust
- Grand Master
- Dark Lord

Dark Matter is the default dark theme for new installs. Nebula remains
available under its existing stable `dark` theme ID so saved user selections
and custom theme bases continue to resolve without migration churn.

Custom theme selections must use `Preferences.customThemeSelectionId` so they
persist as `custom:<id>` instead of raw theme IDs. Future built-in theme IDs
must keep using that namespace boundary so custom themes survive built-in ID
additions.

Custom themes must remain compatible with the existing saved `theme.json`
schema unless a future migration explicitly changes it.

## Semantic Tokens

Use theme tokens by meaning, not by the color they currently produce.

Surface tokens:

- `surface`: page background.
- `surfaceContainer`: primary overlay or main settings content surface.
- `surfaceContainerLow`: grouped panel cards, side panes, and secondary
  surfaces.
- `surfaceContainerLowest`: recessed controls, selected low-depth rows, and
  inputs when appropriate.
- `surfaceContainerHigh` / `surfaceContainerHighest`: hover, emphasis, and
  raised feedback.

Outline tokens:

- `outline`: desktop edge highlights, active picker/menu frames, composer
  highlight strokes, and account-popup highlight strokes. Use alpha to tune
  strength rather than substituting accent colors, `onSurface`, or black.
- `outlineVariant`: quieter dividers and low-emphasis separators.

Accent tokens:

- `primary`: main brand action and active states.
- `secondary`: secondary emphasis.
- `tertiary`: occasional tertiary accent.
- Container and foreground pairs must stay readable together.

Feedback tokens:

- `error` is for destructive or blocking states.
- Warning/success styling should use existing app patterns or local semantic
  helpers; do not invent one-off colors in feature code.

## Theme Workshop Rules

The Theme Workshop previews unsaved edits locally. It must not apply draft theme
changes globally, write preferences, or call global theme-changing side effects
until the user saves.

Theme previews should:

- Show enough app-like UI to reveal token usage.
- Use local mock data, not Matrix room state.
- Highlight which tokens appear in a selected preview region.
- Let users start from all default themes.
- Keep token labels user-friendly. For example, prefer "Primary accents" over
  "On Primary" in editor-facing copy when the label describes usage.

## Custom Themes

Custom themes should store only currently supported editable theme fields.
Message bubbles, app-specific layout choices, and future per-surface overrides
should not be written into theme files until a formal schema decision exists.

Backwards compatibility rules:

- Keep old theme IDs or alias mappings when user-facing names change.
- Do not rename persisted preference keys casually.
- Import/export behavior should remain stable across UI redesigns.

## Contrast And Readability

Before adding a new theme or token mapping, check:

- Text on each surface layer.
- Text on primary/secondary/tertiary actions.
- Disabled controls.
- Destructive controls.
- Badges and notification counts.
- Message bubbles and composer surfaces.
- Sidebar/space rail selected and hover states.

If a token looks right in one preview but wrong in another, prefer preserving
the semantic layer relationship over forcing a literal color match.

## Glass And Transparency

Glass should reveal depth without obscuring content.

Use glass for:

- Mobile composer/input pill treatments.
- Floating popup tiles.
- Desktop overlays when the app behind the overlay should remain present.
- Mobile cards that benefit from edge highlights.

Avoid:

- Transparent menus that make text unreadable.
- Large solid scrims behind small popup tiles unless the interaction is modal.
- Applying blur to a whole surrounding card when only the input pill or focused
  control should be glass.

## What Not To Do

- Do not use hard-coded purple, blue, gray, or red values in app UI unless a
  token cannot represent the state and the decision is documented.
- Do not rely on a theme's current darkness to decide layout.
- Do not make one-off gradients for standard settings cards.
- Do not use theme preview output as persisted state.
- Do not ship custom theme changes that only work in the editor preview.
