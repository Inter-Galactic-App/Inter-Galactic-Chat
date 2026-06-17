# Space Room Categories

Date: 2026-06-10
Owner: FEATURES

## Scope

Space room categories are Discord-style UI groups for joined rooms inside a
Matrix space. They organize the Inter Galactic sidebar without changing Matrix
space topology. They do not create, remove, reorder, or mutate
`m.space.child` events, so other Matrix apps continue to see the normal Matrix
space structure.

Admin-defined category definitions are shared among Inter Galactic clients by a
custom Matrix state event on the Matrix space room:

```text
type: chat.intergalactic.space.categories
state_key: ""
```

Other Matrix clients that do not understand the event should ignore it as
unknown Matrix room state.

## Persistence

Shared category state contains:

- category id
- category name
- assigned room ids

Room ordering is not owned by the category event. Category displays preserve
the current Matrix space-child order within each category, so reordering rooms
continues to flow through normal `m.space.child` order state instead of through
category metadata.

It intentionally does not contain per-viewer collapse state. Collapse state for
each category and for Uncategorized is stored locally in `SharedPreferences`,
scoped by `Space.localId`, so each user/device can choose its own sidebar
expansion state without overwriting the shared layout.

Non-Matrix/demo spaces use the old local `SharedPreferences` category storage
as a fallback because there is no Matrix space room to carry shared state.

Missing rooms and duplicate room assignments are normalized when state is read
for display. A room can appear in only one category at a time. Deleting a
category does not remove any Matrix room; those rooms return to Uncategorized.

## Permissions

Creation and management controls are permission-gated in the UI. Matrix spaces
default to the space admin threshold and require the client to be able to send
the custom category state event:

```text
current user Matrix power level >= 100
and canChangeStateEvent("chat.intergalactic.space.categories")
```

Non-Matrix/demo spaces use `space.permissions.canEditChildren` as the closest
local capability. Collapse and expand interaction is local viewing state and is
not blocked for non-admin users.

## UI Flow

`SpaceList` renders the existing reorderable flat room list when a space has no
categories. Once at least one category exists, direct child rooms are rendered
inside category expanders and any unassigned rooms appear under Uncategorized.
Subspaces remain separate expandable children below the category groups.
Category expander headers render the category name centered between horizontal
rules using the same theme color as normal room names in the room list. The
rules fade at their outer edges, rather than using folder icons or hard-coded
category colors, so custom themes keep the sidebar readable.

The main space summary page shows the same categories on the existing room
order surface. Permitted users can drag rooms within a category and save the
change through the normal space-child reorder flow. The category event is not
rewritten for this; the saved order is the Matrix child order, and the sidebar
also mirrors that saved order through the local sidebar order preference.

`SpaceCategoriesSettingsPage` is exposed from contextual Space Settings. It lets
permitted users create, rename, delete, reorder, and assign joined rooms to
categories. Any user can locally collapse or expand visible categories. Room
rows show the user-facing display name first and the room id as secondary text
so duplicate names remain distinguishable.

## Tradeoffs And Follow-Up

This feature writes a Matrix-visible custom state event, but that event is
Inter Galactic metadata only. It must not be used as a substitute for Matrix
space child state, permissions, membership, or canonical room ordering.

Category membership and category order are managed from Space Settings.
Canonical room order remains the Matrix space-child order. The categorized
space summary lets users edit room order only within the currently visible
category groups; moving a room between categories remains a category assignment
operation.
