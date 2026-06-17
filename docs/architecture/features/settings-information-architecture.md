# Settings Information Architecture

Date: 2026-05-10
Agent: DESIGN
Source map: `docs/architecture/features/settings-ui-map.md`

This document records phase 1 of the Settings UI overhaul. It is an
information-architecture decision pass only. It does not change routes, tab
ordering, UI behavior, preferences, Matrix state writes, or platform behavior.

## Summary

The current Settings shell stays intact for the next overhaul phase:

- `AppSettingsPage` continues to compose Account, App, Help, and About
  categories.
- `RoomSettingsPage` remains the contextual settings surface for a room.
- `SpaceSettingsPage` remains the contextual settings surface for a space.
- Developer-only tabs stay behind the existing developer-mode gates.
- Pre-login Settings continues to expose only client-safe App, Help, and About
  content because the Account category is conditional on having clients.

Later visual and component work should use the grouping and risk tiers below
as the target organization, even when the first implementation keeps existing
category and tab locations.

## Target Settings Groups

### Everyday App Settings

These are normal user preferences and should be the easiest settings to scan:

- General
- Appearance
- Activity
- Notifications
- Voice and Video
- Emoticons
- Soundboard
- Shortcuts
- Desktop Companion

These settings may still contain platform-specific sections, but the top-level
copy should frame them as everyday app/device configuration rather than
diagnostics. The former Window Behaviour tab is now a General section rather
than a separate top-level tab.

### Account Settings

These settings are scoped to the selected Matrix account or local account
profile behavior:

- Account & Profile
- Security

Security remains user-facing, but it should receive high-risk treatment in
later phases because encryption, session verification, key backup, and recovery
can affect access to encrypted history.

Implementation update, 2026-06-11: App Settings now has one shared settings
account selector in the settings chrome instead of separate account dropdowns
inside each account-aware tab. The selector initializes from the focused
account stored in `filter_client_id`, falling back to the first signed-in
account only when no focused account is available. Account & Profile, Security,
App General account privacy controls, App Emoticons, Help & Safety report/block
tools, and developer account diagnostics all read that shared selected account.
Changing the selector chooses which account the open settings surface edits; it
does not change the main-shell focused account.

Implementation update, 2026-06-11: Account Security combines password
management and account recovery codes in one Account security section, using
direct settings rows instead of nested background cards. Encryption health keeps
its detailed desktop status chips but uses compact mobile labels to avoid
multi-line chip wrapping. Biometric recovery-key storage is hidden on desktop
because it is an iOS/Android-only helper. The former separate repair and
decryption retry actions now live behind one **Encrypted message tools** chooser
with copy that distinguishes missing-key delivery repair from retrying
decryption with keys already present on the session.

Implementation update, 2026-05-12: Account management and profile editing are
now combined as **Account & Profile**, account deletion lives in Security, and
the old Privacy tab's read receipts, typing indicators, and DM lock controls
are presented through App General. Emoticons moved from Account settings into
App settings during the Phase 3 migration so quick reactions, favorite packs,
and room/space packs sit with other app-wide communication preferences. The
underlying emoticon data still belongs to the selected Matrix account or joined
rooms/spaces.

Implementation update, 2026-05-12: Shortcuts now includes local custom
navigation entries for user-entered room/space IDs, aliases, or Matrix links.
The shortcut definition is a local app preference with optional account scope,
while the actual keybind stays in the existing system-wide hotkey storage.
App-level Soundboard discovery remains read/preview oriented, but each visible
space card can now open that space's contextual Soundboard settings tab for
management.

Implementation update, 2026-05-29: Shortcuts also owns the local composer
bracket typing toggle and the desktop shortcut for wrapping the current
composer selection in brackets. Bracket auto-close is off by default and stays
local to the message composer; the desktop shortcut has no default keybind and
only acts on the focused composer selection.

Implementation update, 2026-06-10: Custom room shortcuts now let users pick
from the currently joined rooms in the shortcut dialog. The dropdown uses the
room's user-facing display name as the primary label and includes account plus
room ID details to distinguish duplicate names. The stored shortcut target
remains the room ID with optional account scope, so existing manual room IDs,
aliases, Matrix links, and space targets continue to work.

### Support And About

These settings are support, policy, tutorial, and app identity surfaces:

- Help & Safety
- FAQ
- Policies
- Tutorial
- About

Logs stay developer-only and now belong under the Developer area rather than
everyday Help/About surfaces.

Implementation update, 2026-05-17: App Settings > Help now includes **FAQ**.
The FAQ is sectioned into General, Security, and Features; each question is a
card that opens a popup answer. The FAQ tab exports row-level settings search
entries for each question so users can search by question, answer summary, and
common aliases such as recovery key, decryption, spaces, GIFs, emoticons, and
voice/video.

### Advanced And Developer

These surfaces should be treated as expert/debug areas:

- Developer
- Experiments
- Developer / Developer Utils
- Developer / Logs
- Account Developer
- Room Developer
- Space Developer

`Developer` remains visible because it contains the Developer mode toggle and
collapsible expert panels. Everyday settings should stay outside this area
unless they are diagnostic, low-level, or risky enough to need explicit
separation.

Implementation update, 2026-05-12: the old **Advanced** tab label changed to
**Developer** while preserving "advanced" search compatibility. Account
Developer JSON and Notification push transport/registered pusher diagnostics
now live as Developer panels instead of separate Account or Notifications
surfaces.

Implementation update, 2026-05-12: Logs and Developer Utils also moved into
collapsible App Settings > Developer panels. Developer Utils is the final
Developer panel and is grouped into described utility dropdowns.

### Context Settings

Room and space settings remain separate contextual pages:

- Room Settings
- Space Settings

They can share implementation widgets where that is the cleanest technical
path, but the user-facing IA should treat room and space settings as distinct
contexts.

Implementation update, 2026-05-13: contextual Room and Space Settings now use
the proposed context IA. Notifications owns notification mode, read receipts,
typing indicators, and desktop sound overrides. Room Security owns encryption,
room visibility, and room history visibility. Admin Settings owns identity,
addresses, and room events. Appearance is now room-local message
background/bubble styling, while Space Settings keeps soundboard management as
its own contextual tab. General remains a searchable legacy alias rather than a
visible contextual tab.

Implementation update, 2026-05-28: Room Settings exposes Security as a visible
tab so admins can change the current Room History value directly. The
Permissions tab still controls who is allowed to change
`m.room.history_visibility`.

Implementation update, 2026-06-11: Space Settings now includes **Categories**
for shared Inter Galactic room grouping inside a space. Category definitions
are stored in a custom Matrix state event on the space room, but they do not
write or reorder Matrix space children. Creation and management controls are
available only when the current user meets the space-admin management gate;
collapse/expand state remains local per viewer.

## Risk Tiers

Future Settings rows, sections, search results, and warnings should classify
settings by the highest applicable tier.

| Tier | Meaning | Examples | Future UI treatment |
| --- | --- | --- | --- |
| Local-only preferences | Stored on this device/profile and reversible without server writes | Theme, message bubbles, backgrounds, app scale, local sound volume | Plain row treatment; optional "local only" copy where helpful |
| Device/platform preferences | Affect OS integrations or hardware behavior | Notification permissions, custom notification sounds, camera/mic devices, keyboard shortcuts, window behavior | Mention device/platform dependency and permission requirements |
| Matrix account/server-affecting settings | Write to account data, profile APIs, pushers, or homeserver-linked account flows | Account & Profile, General read receipts/typing, account security, push setup, logout/account management | Clarify Matrix server boundary and avoid promising server-side account deletion |
| Room/space state or power-level settings | Write Matrix room state or affect other members | Room security, space security, members, permissions, room/space emoji packs, soundboard state | Strong explanatory copy, permission context, and confirmations for destructive/high-impact writes |
| Developer/debug diagnostics | Expose debug state, experimental switches, logs, or low-level overrides | Developer Utils, Logs, Account/Room/Space Developer, stream diagnostics, experiments | Keep gated or clearly separated from everyday settings |

## Developer Separation Policy

Developer and diagnostic surfaces should stay discoverable for power users
without making everyday settings feel like a debug console.

- Keep the current developer-mode gates in this phase.
- Developer Utils, Logs, and Account Developer are collapsible App Developer
  panels. Room Developer and Space Developer remain separate contextual gated
  surfaces for now.
- Later navigation work may introduce a dedicated Developer area, but only
  after the shared settings row/section primitives exist.
- Search should continue to find developer tabs only when they are visible.
- Settings that turn on developer surfaces, such as Developer Mode, should
  explain that they reveal diagnostics and expert controls.

## Room And Space Copy Policy

Spaces are implemented on top of Matrix rooms in several places, but that
technical detail should not dominate the user-facing settings UI.

- Keep shared room-backed widgets where they already reduce duplication.
- Space settings should use space-specific labels and descriptions when shown
  inside `SpaceSettingsPage`.
- If a shared widget must expose Matrix room behavior, explain it once in plain
  language, for example: "This space is backed by a Matrix room, so these
  access rules use Matrix room permissions."
- Do not rename space settings to room settings just because the underlying
  Matrix object is a room.
- Do not fork shared security, permissions, or member widgets until the visual
  primitives and high-risk copy patterns are ready.

## Phase Boundaries

This phase intentionally does not:

- Move tabs between categories.
- Add new settings routes.
- Restyle desktop or mobile Settings.
- Add shared settings primitives.
- Extend search to setting-row labels.
- Change preference keys or Matrix event/account-data behavior.
- Add warning dialogs or confirmations.

The next phase should build shared row and section primitives that can express
the group and risk metadata above without changing Matrix-write behavior.
