# Commet Asset Provenance Evidence

Status: release-ready provenance and license evidence for retained Commet
assets, plus superseded historical evidence for earlier Inter Galactic
sound/ringtone assets.

Reviewed by REVIEW on 2026-06-14. Updated by REVIEW on 2026-06-27 after the
current sound/ringtone assets were replaced with original Inter Galactic sounds
by Renzo Mayo aka Renzo!.

## Source

- Upstream repository: `https://github.com/commetchat/commet`
- Local fork notices: `LICENSE` and `FORK_NOTICE.md`
- Evidence scope: current `confetti.webp` provenance and superseded historical
  sound/ringtone provenance

The upstream Commet repository is an AGPL-3.0 project. The current
`confetti.webp` asset below is recorded as an inherited upstream Commet
repository asset. The sound/ringtone rows are retained only for historical
release traceability because the current shipped sounds were replaced on
2026-06-27. Their original creators are not documented upstream, so historical
release records must retain that provenance note.

## Release Decision

User/owner direction on 2026-06-14 accepted the provided Commet repository
asset evidence as release-ready for the current release evidence gate. Treat
the retained `confetti.webp` row as covered by the Commet AGPL/fork/source-offer
notice path. On 2026-06-27, the shipped sound/ringtone assets were replaced by
an original Inter Galactic sound pack from Renzo Mayo aka Renzo!, with current
evidence recorded in `../renzo-sounds/SOURCE.md`. The sound/ringtone rows below
are no longer current shipped-byte evidence.

## Asset Records

| Shipped asset | Upstream file | First observed | Commit title | Author/date | License interpretation | Original creator |
| --- | --- | --- | --- | --- | --- | --- |
| `intergalactic/assets/sound/ringtone_in.ogg` | `commet/assets/sound/ringtone_in.ogg` | `584252a` | `Implement 1:1 Calls (#209)` | Airyzz, 2025-07-08 13:49:54 +0000 | Superseded historical evidence; current shipped asset uses `../renzo-sounds/SOURCE.md` | Unknown upstream |
| `intergalactic/assets/sound/ringtone_out.ogg` | `commet/assets/sound/ringtone_out.ogg` | `584252a` | `Implement 1:1 Calls (#209)` | Airyzz, 2025-07-08 13:49:54 +0000 | Superseded historical evidence; current shipped asset uses `../renzo-sounds/SOURCE.md` | Unknown upstream |
| `intergalactic/assets/sound/joined_call.ogg` | `commet/assets/sound/joined_call.ogg` | `91aff36` | `Initial Support for Element Call / Livekit (#476)` | Airyzz, 2025-10-25 16:36:27 +1030 | Superseded historical evidence; current shipped asset uses `../renzo-sounds/SOURCE.md` | Unknown upstream |
| `intergalactic/assets/sound/left_call.ogg` | `commet/assets/sound/left_call.ogg` | `91aff36` | `Initial Support for Element Call / Livekit (#476)` | Airyzz, 2025-10-25 16:36:27 +1030 | Superseded historical evidence; current shipped asset uses `../renzo-sounds/SOURCE.md` | Unknown upstream |
| `intergalactic/assets/sound/message.ogg` | `commet/assets/sound/message.ogg` | `9f3887b` | `Add notification sound and more settings (#848)` | Airyzz, 2026-03-18 22:05:59 +1030 | Superseded historical evidence; current shipped asset uses `../renzo-sounds/SOURCE.md` | Unknown upstream |
| `intergalactic/assets/sound/muted.ogg` | `commet/assets/sound/muted.ogg` | `b30cfb2` | `System wide Hotkeys (#580)` | Airyzz, 2026-02-08 04:36:57 +0000 | Superseded historical evidence; current shipped asset uses `../renzo-sounds/SOURCE.md` | Unknown upstream |
| `intergalactic/assets/sound/unmuted.ogg` | `commet/assets/sound/unmuted.ogg` | `b30cfb2` | `System wide Hotkeys (#580)` | Airyzz, 2026-02-08 04:36:57 +0000 | Superseded historical evidence; current shipped asset uses `../renzo-sounds/SOURCE.md` | Unknown upstream |
| `intergalactic/assets/images/effects/particles/confetti.webp` | `commet/assets/images/effects/particles/confetti.webp` | `3d39f25` | `implement message effects (#401)` | Airyzz, 2025-02-16 11:14:08 +1030 | Inherited from upstream Commet project as an AGPL repository asset | Unknown upstream |

## Notice Requirements

The final release notice surface or release package must include Commet fork
attribution, AGPL-3.0 license/source-offer details, and this asset provenance
note for retained Commet assets such as `confetti.webp`. Current sound/ringtone
notice and credit requirements are recorded in `../renzo-sounds/SOURCE.md`.
