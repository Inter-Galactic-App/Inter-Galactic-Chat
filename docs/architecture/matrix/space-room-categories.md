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
- optional explicit room-order ids for a category
- optional explicit room-order ids for Uncategorized

When no explicit category order exists, category displays preserve the current
Matrix space-child order within each category. When a permitted Inter Galactic
admin drags rooms within a category on the categorized space summary, the
resulting UI order is stored in the custom category event as Inter
Galactic-only metadata. This lets other Inter Galactic clients in the space see
the same category layout without rewriting Matrix `m.space.child` order or
changing how other Matrix clients see the space.

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
change into the custom category event. Flat uncategorized spaces without any
category definitions continue to use the existing Matrix space-child reorder
flow. Categorized room reordering intentionally does not create, remove, or
reorder Matrix `m.space.child` state.

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
Canonical Matrix room order remains the Matrix space-child order. Category
room order is Inter Galactic UI metadata, limited to the currently visible
category groups; moving a room between categories remains a category assignment
operation.
