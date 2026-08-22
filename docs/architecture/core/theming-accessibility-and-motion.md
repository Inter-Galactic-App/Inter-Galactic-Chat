# Theming, Accessibility Tokens, And Motion

Status: active architecture map
Maintenance: DESIGN
Last reviewed: 2026-08-19

This document maps the runtime systems behind Inter Galactic's visual and
accessibility feel: theme resolution and storage, the accessibility-derived
color/contrast tokens, and the shared motion/duration system. It complements
the visual guidance in `docs/design/` without replacing it - use `docs/design/`
to decide what a surface should look like, and this page to find the code that
actually resolves and stores those decisions. It does not duplicate the shell
composition covered by `core/ui-shell-and-responsive-navigation.md`, which
owns navigation, responsive layout, and the `AccessibilityScope` wiring point.

## Theme Catalog And Resolution

Built-in `ThemeData` are defined one file per theme under
`tiamat/lib/config/style/theme_<name>.dart`, each pairing a `Theme<Name>Colors`
constant class with a `Theme<Name>` class exposing `static ThemeData get theme`.
All of them build through the shared `ThemeBase.theme(ColorScheme)` factory
(`tiamat/lib/config/style/theme_base.dart`).

| Design name (`docs/design/THEME_GUIDELINES.md`) | File | Class |
| --- | --- | --- |
| Sol | `theme_light.dart` | `ThemeLight` |
| Dark Matter (default dark) | `theme_dark_matter.dart` | `ThemeDarkMatter` |
| Nebula | `theme_dark.dart` | `ThemeDark` |
| Eclipse | `theme_amoled.dart` | `ThemeAmoled` |
| Aurora | `theme_aurora.dart` | `ThemeAurora` |
| Cosmic Stardust | `theme_cosmic_stardust.dart` | `ThemeCosmicStardust` |
| Grand Master | `theme_grand_master.dart` | `ThemeGrandMaster` |
| Dark Lord | `theme_dark_lord.dart` | `ThemeDarkLord` |

There is no single master registry keyed by id. Sol/Dark Matter/Nebula/
Eclipse/Aurora/Cosmic Stardust are wired directly in `Preferences.resolveTheme`
(`intergalactic/lib/config/preferences.dart`) by string-id `switch`. Grand
Master and Dark Lord are **not** dispatched from their compiled classes at
runtime - they ship as JSON assets (`assets/themes/jedi.json`,
`assets/themes/sith.json`) loaded through `ThemeJsonConverter.fromJson` behind
a `bundled:` id namespace; their compiled classes exist only as base-theme
snapshots for custom-theme derivation. Legacy id aliasing (`sol` -> `light`,
`nebula` -> `dark`, `eclipse` -> `amoled`, and so on) lives in
`tiamat/lib/config/style/theme_json_converter.dart` and is mirrored in
`preferences.dart`.

`Preferences.resolveTheme` resolves, in order:

1. A namespaced custom selection (`custom:<id>`) via
   `ThemeConfig.loadThemeByName` (disk read) -> `ThemeJsonConverter.fromJson`.
2. A legacy/unprefixed custom id, for selections saved before the `custom:`
   namespace existed.
3. Id normalization, then the `bundled:` asset load for Grand Master/Dark Lord.
4. A second custom-theme resolution attempt if still unresolved.
5. A `theme_token_debug` special case.
6. **System dynamic color wins over the saved theme's actual colors, with one
   exception**: if `shouldFollowSystemColors` is on, the saved built-in theme
   id is used only to derive a target brightness (dark_matter/dark/aurora/
   cosmic_stardust -> `Brightness.dark`, Sol -> `Brightness.light`), and that
   brightness feeds `ThemeYou.theme(brightness)` (Material You dynamic color)
   instead of the saved theme's own compiled colors - a real precedence
   point, not just a fallback. **Eclipse (`amoled`) is not in that brightness
   switch**, so `overrideBrightness` stays null for it, the `ThemeYou` branch
   is skipped, and it falls through to its own compiled `ThemeAmoled.theme`
   unaffected by dynamic color - not a general "all dark themes" rule.
   `shouldFollowSystemTheme` (a separate preference) can also supply the
   platform's live brightness directly, before this step runs.
7. Otherwise, the explicit `themeId` switches to a compiled `ThemeData`
   getter - separately keyed for a forced dark/light `overrideBrightness`
   versus none - defaulting to `ThemeDarkMatter.theme`.

`resolveTheme` is `Future<ThemeData>` and re-reads custom-theme JSON from disk
on every call; there is no cache in `Preferences` or `ThemeConfig`. The
de-facto cache is `ThemeChangerState`
(`tiamat/lib/config/style/theme_changer.dart`), which holds the last-resolved
`ThemeData` in `State`, set synchronously from `initialTheme` at startup
(`app_shell.dart`, defaulting to `ThemeDarkMatter.theme`) and re-resolved only
on `didChangePlatformBrightness` or an explicit `ThemeChanger.setTheme` /
`setThemeFromFile` call from the settings UI.

## Custom Theme Storage And Editor

Custom themes live on disk under
`<app support dir>/theme/custom/<id>/theme.json`
(`intergalactic/lib/config/theme_config_io.dart`), one directory per theme. The
class also handles a legacy `<id>.intergalactic-theme` folder-suffix form for
migration, zip export/import with path-traversal guards on every archive
entry, and id collision resolution (`uniqueThemeId`).

`CustomThemeDefinition`/`CustomThemeDraft`
(`intergalactic/lib/config/custom_theme_definition.dart`) define the schema.
A saved theme is **not a diff**: on save, `toJson()` snapshots the entire base
theme's `ColorScheme` (around 40 tokens, including Fixed/FixedDim variants)
plus the `ExtraColors` theme extension, then overlays the 20 fields a user can
actually edit (`editableThemeColorFields`): 9 Accent tokens, 2 Extras (links,
code highlight), 8 Surfaces tokens, and one Background field
(`foundationColor`, tied to the `FoundationSettings` theme extension). There are
no glass/transparency/blur fields in a custom theme - see
`docs/design/THEME_GUIDELINES.md` for what glass/transparency tokens exist and
how they are computed instead. The base theme reference is a normalized string
id covering all eight built-ins, defaulting to `dark_matter`.

The editor (`custom_theme_editor.dart`, `showCustomThemeEditor`) is a
responsive modal: a bottom sheet under 960px width, otherwise a centered
dialog capped at 1680x980 / 92%x90% of the screen. Its own open/close
transition hardcodes `Duration(milliseconds: 260)` and `Curves.easeOutCubic`
rather than going through the shared motion tokens below - a known
inconsistency, not an intentional exception.

`theme_settings_widget_io.dart` and `_html.dart` share an identical
`ThemeListWidget` shape but diverge exactly where the platform diverges:

- **io**: applies a custom theme via `ThemeChanger.setThemeFromFile`, watches
  the custom-themes directory with `Directory.watch()` for live external
  edits, exports via `FilePicker.platform.saveFile`, and supports zip import.
- **html**: has no `dart:io`, so it applies `ThemeData` directly via
  `ThemeJsonConverter.fromJson` + `ThemeChanger.setTheme`, exports via an
  `html.Blob` + `AnchorElement` browser download, and has import **disabled
  entirely** ("Import is not available in the web build") because the web
  build has no persistent filesystem to unzip into or watch.

## Accessibility Tokens

`AccessibilityScope` (`intergalactic/lib/ui/accessibility/accessibility_scope.dart`)
is the wiring point described in `core/ui-shell-and-responsive-navigation.md`;
this section covers what it actually computes.

`EffectiveAccessibilitySettings.resolve`
(`intergalactic/lib/ui/accessibility/accessibility_resolver.dart`) merges two
inputs per toggle: the user's saved preference
(`AppAccessibilityPreferences`, each field is `system` / `off` / `on` or an
equivalent tri-state) and live OS platform signals
(`AccessibilityPlatformSignals`, sourced from `MediaQuery` - high contrast,
bold text, disable animations, accessible navigation, invert colors, on/off
switch labels). A `system`-mode toggle resolves from platform signals; other
values override them outright. Several derived toggles use a platform signal
as their own `system` default even when no directly corresponding preference
exists - for example `strongFocusIndicators` and `reduceTransparency` both
default to "on" when the OS reports `accessibleNavigation`, and
`pauseAnimatedMedia` defaults on when either the OS or the resolved
`reduceMotion` value is true. Reduced motion and "disable animations" are
resolved separately: `reduceMotion` is true for both `reduced` and `none`
motion preferences, while `disableAnimations` (which feeds `MediaQuery`) is
true only for `none`.

`AccessibilityTokens.fromColorScheme`
(`intergalactic/lib/ui/accessibility/accessibility_tokens.dart`) derives a set
of accessibility-safe colors from the active theme's `ColorScheme` plus the
resolved settings - it does not add new base colors, it constrains existing
theme colors to a minimum WCAG-style contrast ratio against `surface`. Status
colors (online/busy/offline/unknown, story-seen states) start from fixed seed
colors and are pushed toward black or white in HSL lightness until they clear
the minimum; other tokens (focus ring, link text, danger, warning, success)
prefer the matching theme color and fall back to `onSurface` or a computed
black/white when the theme color itself cannot clear contrast.
The default minimum is 3:1 for most tokens (focus ring, danger, warning,
success, status indicators), except link text, which defaults to 4.5:1;
`extraHighContrast` raises every one of these to 7:1. `colorSafe`
swaps which theme color a token prefers (for example link text prefers
`secondary` instead of `primary`) rather than changing the algorithm.
`minimumInteractiveDimension` is 48 when `largerTouchTargets` is on, else 40.

`AccessibilityScope` publishes both `EffectiveAccessibilitySettings` and the
derived `AccessibilityTokens` as inherited state, and separately copies bold
text / high contrast / disable animations / the resolved `TextScaler` onto
`MediaQuery` for descendants - so a widget can read either the semantic
settings (`AccessibilityScope.of`), the derived visual tokens
(`AccessibilityScope.tokensOf`), or rely on ordinary `MediaQuery` behavior
picking up the resolved values automatically.

## Motion

`InterGalacticMotion` (`intergalactic/lib/ui/motion/inter_galactic_motion.dart`)
is the shared duration/curve token set: named durations (`instant`, `short`,
`shortEmphasis`, `standard`, `settingsOverlayIn`/`Out`, `long`,
`dropTarget`/`mobileRoute`) and curve tokens (`standardOut`, `standardIn`,
`emphasis`). `shouldReduce(context)` checks
`AccessibilityScope.of(context).reduceMotion`, `MediaQuery.disableAnimations`,
and `TickerMode`; `duration(context, value)` returns `Duration.zero` when
reduced-motion applies, otherwise the requested token.

This is an opt-in helper, not an enforced interceptor - nothing stops a widget
from writing a raw `Duration(milliseconds: ...)` literal instead. At last
measurement, of the files in `lib/ui/` that touch motion at all, roughly
as many use a raw `Duration(milliseconds:` literal as import
`InterGalacticMotion` (47 vs. 35) - not a small exception, close to half of
motion-touching code bypasses the shared tokens, including the theme
editor's own transition noted above.
Correct usage looks like `navigation_utils.dart` (route transitions),
`space_list.dart` (switcher transitions), and
`ui/atoms/shader/constellation_background.dart` (`shouldReduce` gates the
per-frame shader animation entirely rather than just shortening it). Treat a
new animation that skips `InterGalacticMotion` as a reduced-motion gap to fix,
not an established pattern to follow.

## Shader And Particle Backgrounds

`constellation_background.dart` loads
`FragmentProgram.fromAsset('assets/shader/constellation.frag')` once per app
run into a static cache; on load failure, or before load completes, it falls
back to a static gradient built from the active `ColorScheme`, so both the
shader and its fallback are theme-aware. It self-throttles - a frame-rate
watcher disables the animation after ten consecutive sub-30fps frames - and is
fully frozen by `InterGalacticMotion.shouldReduce` for accessibility. See
`docs/agent-control/design-handoff.md` ("Replace Shadertoy-Derived Shader
Material") for why this asset was replaced.

`particle_system_confetti.dart`
(`intergalactic/lib/ui/organisms/particle_player/`) is a separate system built
on the `starfield` package's particle engine, driven by a sprite sheet asset
rather than a shader. Its color palette is a **hardcoded static list** - it is
not theme-aware, unlike the constellation background.

## What This Page Does Not Cover

- Visual guidance (which token means what, when to use it, theme naming) -
  `docs/design/THEME_GUIDELINES.md`, `docs/design/INTERGALACTIC_DESIGN_SYSTEM.md`.
- Accessibility QA checklists and audit findings -
  `docs/design/ACCESSIBILITY_FOCUS_AND_HOVER_AUDIT.md`. This page does not
  claim every surface has completed accessibility QA.
- `AccessibilityScope`'s wiring position in the main shell, and the routing
  table for which doc owns which kind of change -
  `core/ui-shell-and-responsive-navigation.md`.
- Glass/transparency compositing tokens and their theme integration -
  `docs/design/THEME_GUIDELINES.md`.
