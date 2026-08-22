# UI Shell And Responsive Navigation

Status: active architecture map

This document maps the runtime composition of Inter Galactic's main UI shell.
It complements the visual guidance in `docs/design/` without replacing it. Use
this page when a change affects navigation, responsive surfaces, accessibility
context, or the relationship between the desktop and mobile shells.

## Boundaries

The shell composes presentation surfaces around state selected by the app and
Matrix layers. It does not define Matrix event semantics, account/session
restore, room permissions, notification delivery, or call/media protocols.
Those behaviors remain documented by their domain architecture pages and owned
by the relevant implementation areas.

The design-system documents remain the source for visual decisions:

- `docs/design/INTERGALACTIC_DESIGN_SYSTEM.md` - product feel, layers, motion,
  platform treatment, and implementation anchors.
- `docs/design/UI_GUIDELINES.md` - responsive, accessibility, settings, chat,
  and error-state guidance.
- `docs/design/COMPONENT_PATTERNS.md` - reusable component composition.
- `docs/design/LAYOUT_AND_SPACING.md` - spacing and responsive layout rules.
- `docs/design/ACCESSIBILITY_FOCUS_AND_HOVER_AUDIT.md` - selected-surface
  keyboard, semantics, hover-parity, and reduced-motion checks.

This page answers **where the runtime composition lives**; those documents
answer **how the surfaces should look and behave visually**.

## Runtime Entry Point

`MainPage` is the main authenticated application shell. Its state owns the
selected app-level view and the current space/room context, while its view
classes compose the appropriate desktop or mobile presentation:

```text
MainPageState
  ├── MainPageViewDesktop (desktop presentation)
  │     ├── SideNavigationBar
  │     ├── room picker / space or Favorites list
  │     ├── primary room or home view
  │     └── auxiliary activity, account, call, and soundboard surfaces
  └── MainPageViewMobile (mobile presentation)
        └── OverlappingPanels
              ├── left: navigation and room/space selection
              ├── main: current home, space, Favorites, or room view
              └── right: room-side and contextual panels
```

Runtime anchors:

- `intergalactic/lib/ui/pages/main/main_page.dart` - `MainPage` and
  `MainPageState`; selects the desktop/mobile view and owns selection callbacks.
- `intergalactic/lib/ui/pages/main/main_page_view_desktop.dart` - desktop shell
  composition, desktop rail, room picker, primary view, and auxiliary panels.
- `intergalactic/lib/ui/pages/main/main_page_view_mobile.dart` - mobile shell
  composition, overlapping panels, mobile navigation, safe areas, and back
  handling.
- `intergalactic/lib/ui/pages/main/room_primary_view.dart` - primary room/home
  content hosted by both shell presentations.
- `intergalactic/lib/ui/organisms/side_navigation_bar/side_navigation_bar.dart`
  - shared navigation rail/list callbacks for spaces, Home, Favorites, direct
  messages, and call-related entries.
- `intergalactic/lib/ui/molecules/overlapping_panels.dart` - mobile left,
  main, and right reveal state and gesture/keyboard navigation.

## Layout Selection

`intergalactic/lib/config/layout_config.dart` provides the `Layout.desktop` and
`Layout.mobile` decisions consumed by the shell.

The selection order is:

1. An explicit user layout override, when present.
2. The build target (`BuildConfig.DESKTOP` or `BuildConfig.MOBILE`).
3. On web, a cached browser user-agent classification; mobile Android/iPhone
   and mobile user agents select the mobile presentation, while desktop browser
   agents select the desktop presentation.
4. An otherwise unknown web agent defaults to desktop.

This is a presentation choice, not a Matrix capability or protocol decision.
Do not replace it with ad hoc width checks in individual shell children unless
that surface has a documented local breakpoint contract.

## Desktop Composition

`MainPageViewDesktop` uses a persistent horizontal composition:

- `SideNavigationBar` is the left navigation surface.
- The room picker or space/Favorites list sits beside the rail when the current
  desktop layout keeps it visible.
- `RoomPrimaryView` hosts the selected Home, Favorites, space, or room content.
- Account, local-activity, call, and soundboard panels are composed in the
  shell's lower/auxiliary area when their state requires them.
- Desktop small-window mode can reduce the visible room-picker width and reveal
  it as a hover/compact panel. This is still the desktop navigation model; it
  is not the mobile shell.

The source-controlled feature map for compact windows is
`docs/architecture/features/desktop-small-window-mode.md`. Keep compact
window work aligned with that document rather than adding a second shell mode.

## Mobile Composition

`MainPageViewMobile` uses `OverlappingPanels` to keep the current content in a
single main surface while allowing navigation and contextual room panels to be
revealed from the left and right.

- The left reveal contains the navigation rail and the current room/space
  selector.
- The main reveal contains the selected Home, Favorites, space, or room view.
- The right reveal contains the room-side/contextual panel when available.
- `PopScope` and the panel state coordinate back actions: a contextual panel
  closes before the main view changes, and the main view returns toward
  navigation in the expected order.
- Safe-area handling and the mobile visual helpers keep navigation, account
  controls, call controls, and the composer reachable around system insets.
- Selecting a direct message from the mobile navigation returns the panel to
  the main surface after the shell updates the selected room.

Mobile presentation is not a smaller desktop tree. Do not port desktop hover
assumptions or persistent side-by-side panes into the mobile composition.

## Accessibility Context

`AccessibilityScope` resolves effective accessibility preferences and platform
signals near the UI tree. It publishes both effective settings and derived
`AccessibilityTokens`, and copies the relevant text, contrast, animation, and
scaling values into `MediaQuery` for descendants.

Important runtime anchors:

- `intergalactic/lib/ui/accessibility/accessibility_scope.dart` - preference
  subscription, effective settings, tokens, and descendant `MediaQuery` values.
- `intergalactic/lib/ui/accessibility/accessible_interactive_region.dart` -
  semantics and interaction wrapper for controls that need a larger or clearer
  accessible target.
- `intergalactic/lib/ui/accessibility/accessibility_tokens.dart` - derived
  accessibility-aware visual values.
- `intergalactic/lib/ui/motion/inter_galactic_motion.dart` - shared durations
  and reduced-motion decisions.

Icon-only and hover-revealed controls must retain a keyboard, touch, and
semantics path when the action is necessary for selection, recovery, retry,
close, cancel, or deletion. Use the selected-surface checklist in
`docs/design/ACCESSIBILITY_FOCUS_AND_HOVER_AUDIT.md` for validation; this map
does not claim that every surface has completed accessibility QA.

## Navigation And Motion Contracts

`intergalactic/lib/ui/navigation/navigation_utils.dart` is the shared route
helper for the mobile slide transition. It uses `InterGalacticMotion` and
returns an immediate transition when reduced motion is active.

`OverlappingPanels` uses the same motion contract for mobile panel reveals and
supports keyboard navigation through its focused panel state. The shell must
preserve focus and panel state when navigation changes unless the destination
intentionally replaces the current surface.

The design-system motion rules remain in
`docs/design/INTERGALACTIC_DESIGN_SYSTEM.md`; this page only identifies the
runtime owners of those rules.

## Change Routing

Use this map to route a proposed change:

| Change | Start with | Keep out of scope unless assigned |
| --- | --- | --- |
| Desktop/mobile shell selection | `layout_config.dart`, `main_page.dart` | Matrix restore and protocol behavior |
| Desktop rail, room picker, or compact shell | `main_page_view_desktop.dart`, `side_navigation_bar/`, `desktop-small-window-mode.md` | Mobile panel routing |
| Mobile navigation or panel reveal | `main_page_view_mobile.dart`, `overlapping_panels.dart` | Desktop rail behavior |
| Shared room/home content | `room_primary_view.dart` and the relevant feature map | Shell ownership and route policy |
| Semantics, focus, text scale, contrast, or reduced motion | `ui/accessibility/`, `inter_galactic_motion.dart`, the accessibility audit | Feature-specific domain behavior |
| New route transition | `navigation_utils.dart`, `inter_galactic_motion.dart` | One-off motion constants without a design decision |
| Global visual tokens or primitives | `docs/design/` and `tiamat/` implementation anchors | Main-shell state and Matrix behavior |

Before editing, check current ownership and the relevant domain architecture
page. The architecture index is maintained as a navigation aid; feature and
subsystem documents remain maintained by their domain owners.

## Validation Boundary

For documentation changes, validate source anchors, Markdown structure, and
public-safe wording. This document does not provide Flutter, device, or
runtime proof. UI behavior changes require the focused tests and platform
smoke appropriate to the affected shell or accessibility surface.
