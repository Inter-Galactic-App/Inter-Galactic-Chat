# Messaging Composer Drafts

## Purpose

Unsent plain-text room and thread messages remain available when a user opens a
different conversation and returns. This prevents navigation from discarding
in-progress writing without turning an unsent message into Matrix data.

## Flow

`ChatView` gives the regular room composer a key built from the local client,
room identifier, and optional thread identifier. `MessageInput` records the
current `TextEditingValue` in `ComposerDraftCache` whenever it changes and
restores that value, including cursor position, when a new composer is created
for the same key.

The cache is local process memory only. It keeps at most 100 non-empty drafts,
expires entries after seven days, and removes an entry when the composer is
emptied after an accepted send. It never serializes drafts to preferences,
Matrix account data, or disk, because a draft may contain sensitive text from
an encrypted room.

## Boundaries

- Attachments, reply/edit state, and inbound-share payloads are not cached.
- Reply and edit composers do not use the room draft cache because their
  interaction context is not reconstructed on a later room open.
- A full app restart clears the cache; durable cross-device drafts are out of
  scope and would require a separate privacy and synchronization design.

## Primary Files

- `intergalactic/lib/ui/molecules/message_input.dart` - cache contract and
  capture/restore implementation.
- `intergalactic/lib/ui/organisms/chat/chat_view.dart` - regular room/thread
  cache-key routing.
- `intergalactic/test/ui/molecules/message_input/message_input_emoticon_test.dart`
  - room isolation, selection, expiry, and explicit-clear coverage.
