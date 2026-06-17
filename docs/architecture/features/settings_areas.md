# Settings Areas Overview

Status: historical planning snapshot. The current implemented Settings IA is
documented in `settings-information-architecture.md`, `settings-ui-map.md`, and
the design-system settings guidance. Do not treat the section map below as
the current source of truth: Window Behaviour, Advanced, Account Privacy,
Account Emoticons, companion controls, Voice/Video diagnostics, Soundboard,
and room/space contextual settings have moved in the May 2026 Settings
overhaul.

## General

### General
Controls:
- GIF search
- URL previews in E2EE rooms
- delete confirmations
- composer autofocus
- auto-open space
- small window mode
- offline demo login
- message effects
- media preview defaults
- mobile media rotation

Storage:
- Local `Preferences` / `SharedPreferences`

Side Effects:
- Updates composer, media, and room behavior after rebuild

Notes:
- Some settings are platform-gated

---

## Appearance & Layout

### Appearance
Controls:
- theme/system theme
- app colors
- app icon mode
- message background
- bubble mode/alignment/colors
- app/text scale
- room preview/avatar display

Storage:
- Local preferences
- Theme widgets/files

Side Effects:
- `ThemeChanger.setTheme`
- `AppIconUtils`
- live layout/theme updates

Notes:
- Some changes may require restart/rebuild
- Custom theme editor is high complexity

### Window Behaviour
Controls:
- minimize on close

Storage:
- Local preferences

Side Effects:
- Alters desktop close behavior

Notes:
- Desktop only

Proposed edits:
- collapse into general

### Advanced
Controls:
- developer mode
- sticker compatibility
- layout override

Storage:
- Local preferences

Side Effects:
- Enables developer tabs
- Alters responsive shell/layout behavior

Notes:
- Layout override may require restart/relogin

Proposed edits:
- Move sticker compatibility to general
- Move override layout to appearence
- Advanced tab becomes developer tab Move down to bottom section

### Experiments
Controls:
- experiment opt-in/out

Storage:
- Local experiment registry/preferences

Side Effects:
- Enables guarded experimental features

Notes:
- Restart commonly required
- Not currently visable

---

## Activity & Presence

### Activity
Controls:
- local activity display
- hide current app
- basic status publishing
- iOS media controls
- Spotify integration
- Steam/game activity
- mock activity source

Storage:
- Local preferences
- activity/presence components

Side Effects:
- publishes activity/presence
- connects/disconnects Spotify
- enables media/game detection

Notes:
- provider-specific behavior
- mock source is developer-only

---

## Voice, Video & Streaming

### Voice and Video
Controls:
- TURN fallback
- soundboard volume
- screen-share profile
- stream override
- codec/FPS/bitrate/resolution
- device defaults
- Windows noise suppression

Storage:
- Local preferences

Side Effects:
- Updates `NoiseSuppressionService`
- affects future calls/streams
- affects local mic tests

Notes:
- Windows-only and developer-gated settings exist
- High-risk performance area

Proposed edits:
- Needs camera settings
- Move TURN fallback to advanced

---

## Input & Shortcuts

### Shortcuts
Controls:
- outsource/keyboard hook shortcuts
- composer bracket auto-close toggle
- wrap selected composer text in brackets shortcut

Storage:
- Platform shortcut storage/components
- Local `composer_bracket_typing` preference
- Existing `system_wide_hotkey.*` storage for assigned hotkeys

Side Effects:
- Updates keyboard hook behavior
- Updates local composer text transforms when enabled or when the desktop
  shortcut is pressed in the focused composer

Notes:
- System hotkeys are Linux/Windows only; bracket auto-close is a local composer
  behavior and defaults off

Proposed edits:
- Hot keys to get certain settings pages
- Assigning hotkeys to switch to certain rooms

---

## Notifications

### Notifications
Controls:
- notification enablement
- focus suppression
- notification media/body/URL previews
- custom sounds
- push gateway
- companion overlay
- web push state

Storage:
- Local preferences
- push/notifier components

Side Effects:
- requests OS permissions
- updates push gateway
- previews sounds
- updates Windows companion overlay behavior

Notes:
- Strong platform divergence
- Push changes can affect delivery reliability

Proposed edits:
- Too many gated settings

---

## Account Settings

### Account Management
Controls:
- add/logout/remove clients
- account-management URL
- developer client prefix

Storage:
- Client manager/session storage

Side Effects:
- removes sessions
- opens homeserver account management

Notes:
- Account deletion handled by homeserver

### Account Profile
Controls:
- display name
- avatar

Storage:
- Matrix profile APIs

Side Effects:
- updates Matrix profile

Proposed Edits:
- Story like photo adds
- Don't know what badges do
- Settings shouldn't be hidden in ... menu

### Account Privacy
Controls:
- public read receipts
- typing indicators
- DM lock

Storage:
- Matrix presence/privacy components
- local DM lock preferences

Side Effects:
- publishes privacy changes

Notes:
- DM lock is local-only and does not sync
### Account Security
Controls:
- cross-signing
- encrypted backup
- session verification
- retry decryption

Storage:
- Matrix E2EE/session APIs

Side Effects:
- affects encrypted trust/recovery state

Notes:
- High-risk security area

### Account Emoticons
Controls:
- emoji/sticker packs
- quick reactions

Storage:
- account data/emoticon components

Side Effects:
- updates emoji/sticker picker behavior

Notes:
- Depends on component/account availability

### Account Developer
Controls:
- account state inspection

Storage:
- Matrix account state

Notes:
- Developer-only

Proposed edits:
- Move to comprehensive developer tab

---

## Room Settings

### Room General
Controls:
- room push rule
- room read receipts
- room typing indicators
- room event settings

Storage:
- Matrix push rules/components

Side Effects:
- updates room privacy/notification behavior

Notes:
- Permission-gated

### Room Notifications
Controls:
- room push rule
- custom sound/volume

Storage:
- Matrix push rules
- local room preferences

Side Effects:
- alters room notification behavior

Notes:
- Sounds are local-only

### Room Appearance
Controls:
- avatar
- room name
- topic
- room backgrounds/bubbles

Storage:
- Matrix room state
- local room preferences

Side Effects:
- updates room rendering/profile

Notes:
- Permission-dependent

### Room Security
Controls:
- encryption
- join/history/security controls

Storage:
- Matrix room security APIs

Side Effects:
- changes room access semantics

Notes:
- High-risk area
- Permission-dependent

Proposed edits:
- Combine security with privacy controls from general
- Combine security with permissions

### Room Emoticons
Controls:
- room emoji/sticker packs
- import/bulk import

Storage:
- Matrix room state/components

Side Effects:
- updates room pack availability

Notes:
- Requires edit permission

### Room Members
Controls:
- member roles

Storage:
- Matrix power levels/member state

Side Effects:
- changes moderation/permission structure

Notes:
- Permission-dependent

### Room Permissions
Controls:
- power-level requirements
- call/calendar/soundboard permissions

Storage:
- Matrix `m.room.power_levels`

Side Effects:
- changes allowed room actions

Notes:
- High-risk admin area

### Room Calendar
Controls:
- synced calendar URLs/settings

Storage:
- local preferences
- calendar components

Side Effects:
- adds/removes external feeds

Notes:
- Calendar rooms only

Proposed edits:
- Move out of settings and onto calendar as a button

### Room Developer
Controls:
- room debug data

Storage:
- Matrix debug state

Notes:
- Developer-only

Proposed edits:
- Provide info on what buttons do

---

## Space Settings

### Space General
Controls:
- push rules
- Matrix address settings

Storage:
- Matrix push/address state

Side Effects:
- changes notification/address behavior

### Space Appearance
Controls:
- profile/topic/banner display

Storage:
- Matrix profile APIs

Side Effects:
- updates visible space profile

Notes:
- Permission-dependent

### Space Security
Controls:
- security settings
- encryption toggle hidden

Storage:
- Matrix space room state

Side Effects:
- changes access/security semantics

Notes:
- High-risk
- Matrix-space only

Proposed edits:
- Combine security and permissions

### Space Soundboard
Controls:
- uploads
- names
- volumes
- join/default sounds

Storage:
- `SoundboardComponent`
- Matrix space state
- local soundboard prefs

Side Effects:
- uploads and shares audio

Notes:
- Power-level gated
- Matrix-space only

### Space Permissions
Controls:
- space power levels

Storage:
- Matrix `m.room.power_levels`

Notes:
- High-risk admin area


### Space Members
Controls:
- member roles/list

Storage:
- Matrix member state/power levels

Notes:
- Permission-dependent

---

## Safety & Support

### Help & Safety
Controls:
- reports
- blocks
- help copy

Storage:
- Matrix report/block APIs

Side Effects:
- sends abuse reports
- updates ignored users

Notes:
- Avoid overpromising safety/privacy guarantees

### Tutorial
Controls:
- replay onboarding

Storage:
- local onboarding preferences

Side Effects:
- opens onboarding flow

Notes:
- Should not reset completion state

### About
Controls:
- app/device/build info

Storage:
- runtime/package/device info

Notes:
- Display-only

### Logs
Controls:
- logs/device diagnostics

Storage:
- app log/runtime systems

Side Effects:
- copy/save/export logs

Notes:
- Developer-only

Proposed edits:
- Combine on Developer tab
