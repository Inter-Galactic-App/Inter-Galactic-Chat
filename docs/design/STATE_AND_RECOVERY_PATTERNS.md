# State And Recovery Patterns

Status: active design reference
Last updated: 2026-06-23
Source backlog item: P18 in the workspace UX/UI polish backlog

## Purpose

Inter Galactic should handle empty, loading, offline, reconnecting, and error
states with one recognizable language. These states should help the user answer
three questions quickly:

- What is happening?
- Can I do anything about it?
- Is my account, room, or message still safe?

This guidance applies first to settings, Discover, room and space creation,
community navigation, account/profile/member surfaces, and future chat/media
recovery states. It does not change Matrix behavior by itself.

## Principles

- Prefer inline recovery over modal errors when the user can retry, refresh,
  switch account, change a filter, or keep using the surrounding surface.
- Preserve the user's context. Retrying should keep scroll position, focused
  input, selected account, selected tab, and entered form values when safe.
- Use plain state names. Avoid internal exception names, protocol details, raw
  hostnames, or private deployment names in user-facing copy.
- Keep layout stable. A spinner should not collapse the surface, shift nearby
  actions, or leave a blank unthemed area.
- Pair visual state with text and icon meaning. Color alone is not enough for
  success, warning, failed, blocked, or selected states.
- Keep compact mobile labels honest. A shorter visible label may be used, but
  the semantics label must preserve the full meaning.

## Copy Formula

Use this structure unless the surface has a stronger local pattern:

| Piece | Rule | Example |
| --- | --- | --- |
| Title | Name the state in human terms | `Could not load Discover` |
| Description | Explain what changed and what remains true | `Your homeserver did not return results. Existing rooms are unchanged.` |
| Primary action | Use a concrete verb | `Retry`, `Refresh`, `Switch account`, `Review settings` |
| Secondary action | Offer only when genuinely useful | `Clear search`, `Report issue`, `Open account settings` |

Avoid vague standalone copy such as `Something went wrong`, `Error`, `Failed`,
or `Try again later` unless the body gives the user a specific next step.

## State Matrix

| State | Use when | Title pattern | Body should say | Primary action | Layout |
| --- | --- | --- | --- | --- | --- |
| Initial loading | First load and no prior data is available | `Loading <surface>` | What is being loaded | None unless cancellation exists | Stable panel or skeleton at the expected content size |
| Refreshing | Prior data remains visible while updating | `Refreshing` only when a label is needed | The existing content is still usable | Usually none | Inline spinner or status chip; do not replace content |
| Loading more | Pagination or continuation load | `Loading more results` | Optional count/context | None unless retryable | Footer `SettingsStatePanel` or stable row |
| Empty no results | Search/filter returned nothing | `No <items> found` | Mention the active filter/search | `Clear search` or `Change filter` | Inline panel in the results area |
| Empty not configured | Feature is available but not set up | `<Feature> is not set up` | What setup enables and whether it is local/account/room scoped | `Set up`, `Add`, or `Choose` | Section-level panel near the related controls |
| Offline/reconnecting | Network or Matrix sync is temporarily unavailable | `Reconnecting` or `You're offline` | What can still be done locally and what will resume later | `Retry` only if manual retry exists | Persistent inline banner/panel, not a blocking modal |
| Permission blocked | User lacks power level, account scope, or platform permission | `Permission needed` or `Only admins can change this` | Who can act or where permission is granted | `Review permissions` when available | Inline warning panel near the disabled controls |
| Recoverable error | Retry, refresh, or another route may fix it | `Could not <verb>` | Whether data was changed and what retry does | `Retry` | `SettingsStatePanel` with danger tone only for blocking errors |
| Blocking error | The current task cannot continue safely | `Cannot continue` | What is blocked, what remains unchanged, and where to go next | Surface-specific safe exit or support action | Modal only when leaving the task is required |
| Partial content | Some items loaded and some failed | `Some <items> could not load` | What is visible, what is missing, and whether retry affects all or missing only | `Retry missing` or `Refresh` | Keep loaded content visible; add inline recovery row |
| Running action | A pressed action is in progress | Keep the button label concrete, such as `Publishing...` | Usually no body text unless the action is slow/risky | Disabled running button | Stable button width; preserve focus |
| Completed action | A state-changing action succeeded | `Updated`, `Request sent`, or surface-specific result | Confirm the result and next expectation | None or next obvious action | Inline outcome text or status chip |
| Local pending send | Sender-local media/message exists before Matrix send completes | `Preparing`, `Uploading`, `Sending` | Local-only status, not remote delivery | `Cancel` when available | Inline status near the local timeline item |

## Component Rules

Use `intergalactic/lib/ui/pages/settings/settings_status_components.dart` for
settings and settings-adjacent surfaces:

- `SettingsStatePanel` for loading, empty, retry, continuation, permission, and
  recoverable error panels.
- `SettingsStatusChip` for compact state, health, metadata, and action-result
  chips.
- `InterGalacticMotion` for optional state transitions; reduced motion must be
  instant and must not hide information.

Surface guidance:

- Use `surfaceContainerLow` for state panels inside settings content.
- Use `surfaceContainer` for the main settings pane or broad preview region.
- Use `surfaceContainerLowest` sparingly for recessed controls, inputs, and
  selected low-depth rows, not broad empty/error backgrounds.
- Actions stack below the body on narrow widths; desktop may keep the action on
  the trailing side when there is enough room.

## Action Availability Matrix

| User can do this | Prefer | Do not do |
| --- | --- | --- |
| Retry the same request | Inline `Retry` | Close the parent surface first |
| Change search/filter | `Clear search` or visible filter control | Hide the active filter in body copy |
| Switch account | Shared settings account selector or account-scoped action | Put separate account dropdowns in each tab |
| Configure missing setup | `Set up`, `Choose`, `Add`, or `Manage` | Send users to a vague settings page |
| Wait for sync/network | `Reconnecting` with honest local availability | Block the whole app if unrelated areas still work |
| Escalate/report | `Report issue` after local recovery options | Make support the first path for normal transient errors |
| No useful action | Calm explanation and stable layout | Add disabled buttons that look broken |

## Accessibility Requirements

- State panels need readable title/body text, not only icons or color.
- Retry, refresh, clear, and setup actions must be reachable by keyboard and
  touch.
- Focus should remain on the pressed action or return to a predictable related
  control after a retry.
- Important async results should be announced where the surrounding surface
  already supports semantic updates.
- Compact labels such as `30 m` or `Sent` must have full semantics labels when
  the visible label is shortened for layout.

## QA Smoke Checklist

For a rebuilt QA smoke, sample at least these transitions:

- Loading to content, loading to empty, and loading to error in Discover.
- Search/filter no-results and clear-search recovery.
- Load-more error and retry without losing existing results.
- Settings account switch while a state panel is visible.
- A permission-blocked room/space setting if available.
- Offline or reconnecting copy where the app exposes sync/network state.
- A failed send or failed upload local recovery state when FEATURES/QA has a
  suitable media-send scenario ready.
- Default, dark, and one custom theme to confirm surface layering and text
  contrast.
