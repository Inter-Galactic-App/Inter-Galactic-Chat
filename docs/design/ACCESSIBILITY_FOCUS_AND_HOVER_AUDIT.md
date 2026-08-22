# Accessibility Focus And Hover Audit

Status: active audit and QA smoke checklist
Owner: DESIGN
Last updated: 2026-06-23
Source backlog item: P19 in the workspace UX/UI polish backlog

## Scope

This audit covers selected UX/UI polish domains where desktop hover affordances,
context menus, compact labels, and async state panels can drift away from
keyboard and mobile use.

No production UI behavior changed in this pass. Findings below are intended to
guide the next full QA smoke and later owner-scoped fixes.

## Reviewed Anchors

- Settings shared status components:
  `intergalactic/lib/ui/pages/settings/settings_status_components.dart`
- Settings shells and account header:
  `intergalactic/lib/ui/pages/settings/desktop_settings_page.dart`,
  `mobile_settings_page.dart`, and `settings_account_header.dart`
- Discover settings:
  `intergalactic/lib/ui/pages/settings/categories/discover/`
- Room creation chooser:
  `intergalactic/lib/ui/pages/get_or_create_room/`
- Space categories and room list:
  `intergalactic/lib/ui/atoms/space_list.dart`,
  `intergalactic/lib/ui/atoms/room_text_button.dart`, and
  `intergalactic/lib/ui/organisms/space_summary/`
- Timeline/media affordances:
  `intergalactic/lib/ui/molecules/timeline_events/` and
  `intergalactic/lib/ui/organisms/chat/`
- Notification snooze controls:
  app and room notification settings pages.

## Findings

| ID | Surface | Finding | QA smoke requirement | Follow-up owner |
| --- | --- | --- | --- | --- |
| A11Y-01 | Settings state panels | Shared `SettingsStatePanel` gives Discover a consistent inline recovery pattern, but older settings pages still mix plain error text, snackbars, and modal errors. | Tab through panels and confirm retry/refresh actions are reachable, focus remains predictable, and mobile action wrapping does not hide the button. | DESIGN for pattern migration, feature owner for behavior-specific errors |
| A11Y-02 | Settings account header | The shared settings account selector moved account scope out of individual tabs. The header now needs routine keyboard and screen-reader smoke because it is a high-value clickable control. | Open settings with multiple accounts, use keyboard to reach the account header, change accounts, and confirm the selected account is announced and applied. | DESIGN / FEATURES only if account-scope behavior changes |
| A11Y-03 | Discover result cards | Discover uses shared chips and state panels, but result cards include dense metadata, running actions, and inline outcomes that can crowd on mobile. | Keyboard through search, filters, result cards, Join/Request buttons, load more, and retry. On mobile, confirm actions remain visible without relying on hover. | DESIGN / QA |
| A11Y-04 | Room creation chooser | The chooser now has clearer copy and layout, but it is a modal decision point with selectable rows/cards and a primary `Next` action. | Tab through existing room, each room type, back/next/cancel. Confirm selected state is not color-only and mobile tap targets are large enough. | DESIGN |
| A11Y-05 | Space categories | Category headers visually use text and tapered rules; expand/collapse motion is reduced-motion aware. The key accessibility risk is whether the header exposes a usable button-like target and expanded/collapsed state. | Use keyboard and mobile touch to collapse/expand categories with several rooms. Confirm no hidden child row can receive focus while collapsed. | DESIGN, FEATURES if category state behavior changes |
| A11Y-06 | Timeline hover actions | Desktop timeline and media surfaces still use hover/context affordances in several places. Mobile focused-media actions exist, but failed-send retry/cancel must remain reachable without hover. | Smoke normal message actions, focused image/video actions, failed media retry/cancel, and context menus by mouse, keyboard, and mobile long press. | DESIGN after FEATURES/QA clears media behavior |
| A11Y-07 | Snooze compact buttons | Snooze controls already use compact visible labels with fuller semantics labels. This should be treated as the pattern for dense controls. | Confirm `30 m` style visible labels do not clip and screen-reader labels still announce the full duration. | DESIGN |
| A11Y-08 | Settings search target highlight | Search opens matching settings surfaces, but row-level highlight/scroll remains backlog P07 rather than part of this audit. | During smoke, note any search result that opens a long tab without making the matching row obvious. | DESIGN / FEATURES for a later anchor contract |
| A11Y-09 | Calls and stories | Calls, PiP, story video, and platform permission flows are high-risk and were intentionally deferred from this broad audit. | Do not treat this pass as call/story accessibility clearance. | IOS / EXPERIMENTAL / FEATURES / DESIGN later |

## QA Smoke Pass Criteria

A full QA smoke should record pass/fail notes for:

- Visible keyboard focus on settings account header, settings sidebar/search,
  Discover cards, room creation choices, category headers, and timeline action
  menus.
- Mobile equivalents for every desktop hover-only action in the selected
  surfaces.
- Full semantics labels for compact visible controls such as snooze duration
  buttons and compact status chips.
- Non-color indicators for selected, failed, warning, disabled, and running
  states.
- Focus preservation after retry, refresh, clear search, account switch,
  category collapse/expand, and room creation back/next.
- Reduced-motion behavior for state/motion surfaces already using
  `InterGalacticMotion`.

## Later Fix Guidance

When later implementation work is approved:

- Prefer `InkWell`, Tiamat buttons, or existing selectable row primitives over
  bare `GestureDetector` for interactive controls.
- Add `Tooltip` plus `Semantics` for icon-only actions.
- Use `Semantics(selected: true)` or equivalent state when a row/card is
  selected and the state is not otherwise announced.
- Do not rely on hover to reveal the only retry, cancel, delete, or close path.
- Preserve mobile long-press or explicit action buttons for message/media
  actions that are hover-driven on desktop.
- Keep focus on the initiating control through running states unless the
  action intentionally moves the user to a new surface.
