# Top-level Space rail order

## Purpose

Inter Galactic synchronizes a user's top-level Matrix Space order between that
user's devices without changing the shared Space hierarchy or another account's
rail.

## Matrix contract

Each Matrix Space uses room account data with the MSC3230-compatible type
`m.space.order` and content `{ "order": "<rank>" }`. Reads also accept the
older `org.matrix.msc3230.space_order` event type. Room account data is private
to its owner and arrives through sync, so this affects neither other Space
members nor a second account signed in to the same app.

`m.space.child` is intentionally not used: it is shared hierarchy state and
would reorder the Space for everyone with permission to view it.

## Ordering and migration

`TopLevelSpaceOrderStore` reads ranks only within one Matrix account. The rail
keeps other accounts and non-Matrix Spaces in their existing positions.

Ranks are fixed-width base-36 strings. A normal drag computes a midpoint rank
and writes only the moved Space. If an older rank format has no midpoint, the
store re-spaces only that account's Spaces. This is the exceptional path because
a sequence of room-account-data writes is not atomic for another device.

The former `top_level_space_order` preference remains a local fallback and
initial migration source. Migration runs only after sync and only when the
account has no remote order event, preventing a cold cache from overwriting an
already synchronized rail.

## Important files

- `intergalactic/lib/client/top_level_space_order.dart`
- `intergalactic/lib/ui/organisms/side_navigation_bar/side_navigation_bar.dart`
- `intergalactic/lib/config/preferences.dart`

## Failure behavior

Matrix write failures leave preferences untouched and restore the pre-drag rail
order. A successful local write is optimistic until the next sync confirms or
supersedes it with the server's value.
