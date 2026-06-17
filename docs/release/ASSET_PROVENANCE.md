# Asset Provenance

Status: PASS FOR CURRENT RELEASE SCOPE

Inventory date: 2026-06-13

This file records bundled or release-adjacent asset provenance for the current
Inter Galactic `0.7.4+985` release-evidence inventory. It is evidence for
S&C/release review, not legal sign-off. The 2026-06-16 release-owner closeout
accepts the current asset provenance and notice/access surface for this release
scope. Re-open the gate if asset bytes, source, bundled dependencies, notice
routing, or release SDK state change.

## Summary

| Asset family | Paths | Source or creator | License evidence | Release status | Notes |
| --- | --- | --- | --- | --- | --- |
| Inter Galactic app icon | `intergalactic/assets/images/app_icon/**`; generated platform icon variants | Project owner | User confirmed on 2026-06-12 that the app Inter Galactic icon was drawn by them | OK | Keep this note with any future public asset provenance export. |
| Notification companion icons | `intergalactic/assets/images/notification_companion/**` | Derived from Inter Galactic icon family | Covered by owner-created app icon evidence if generated from the same source | OK | Reconfirm if future variants use external artwork. |
| Roboto fonts | `intergalactic/assets/font/roboto/**`; Tiamat RobotoCustom files | Google/Roboto | Local Apache-2.0 text exists under app and Tiamat font folders | OK | Include notice text in generated bundle. |
| Jellee font | `intergalactic/assets/font/jellee/**` | Jellee font project | Local OFL text exists as `Jellee-OFL.txt` | OK | Include OFL notice. |
| JetBrains Mono | `intergalactic/assets/font/code/**` | JetBrains Mono project | Local OFL text exists as `OFL.txt` | OK | Include OFL notice. |
| Nunito Sans | `intergalactic/assets/font/nunito/**` | Nunito Sans font family | Mirrored app-repo evidence exists in `docs/release/evidence/license-sources/nunito/`, including `SOURCE.md` | OK WITH NOTICE SURFACE | Release-ready evidence normalized by REVIEW on 2026-06-14. Include OFL/source evidence in the generated notice surface. |
| App emoji font | `intergalactic/assets/font/emoji-font/**` | TwemojiCOLR source noted in README | Mirrored Twemoji-derived license/source evidence exists in `docs/release/evidence/license-sources/twemoji-colr/`, including `SOURCE.md` | OK WITH NOTICE SURFACE | REVIEW accepted attribution/source evidence on 2026-06-14. Include TwemojiCOLR/Twemoji attribution, applicable license links, change indication where applicable, and Noto Color Emoji OFL notice in the final app/release notice surface. |
| Tiamat emoji font | `tiamat/assets/font/emoji-font/**` | Noto Color Emoji | Local OFL text exists | OK | Include notice if Tiamat ships this font. |
| Sound and ringtone assets | `intergalactic/assets/sound/**`; Android raw sound copies | Commet repository assets | `docs/release/evidence/license-sources/commet/commetassets.md` records first-observed Commet commits, AGPL repository-asset inheritance, unknown upstream original creators, and 2026-06-14 user/owner acceptance | OK WITH NOTICE SURFACE | Release-ready evidence for this release pass. Include Commet AGPL/fork/source notices and keep the Commet asset evidence with release records. |
| Placeholder avatars | `intergalactic/assets/images/placeholders/avatar*.jpg` | Commet-created per user confirmation on 2026-06-13 | User confirmation | OK WITH OWNER CONFIRMATION | Keep this note with any future public asset provenance export. |
| Placeholder photos | `intergalactic/assets/images/placeholders/photos/pexels-*.jpg` | Pexels-named files | Pexels license page reviewed on 2026-06-13: free use, attribution not required, modifications allowed; restrictions still apply | OK WITH PEXELS LICENSE EVIDENCE | Keep the Pexels license URL with release evidence; exact download URLs remain nice-to-have, not a release blocker for this pass. |
| Tiamat generic placeholders | `tiamat/assets/images/placeholder/generic/**` | Kenney Prototype Textures | Local CC0 license file exists | OK | Keep local license file with source. |
| Fluent emoji particles | `intergalactic/assets/images/effects/particles/fluent-emoji-*` | Animated Fluent Emojis repository | Local source note says MIT as of 2025-02-16; particle files match `references/commet-main` by SHA-256 | OK WITH NOTICE SURFACE | REVIEW accepted MIT attribution evidence on 2026-06-13. Include Animated Fluent Emojis source attribution and MIT notice in the final app/release notice surface. |
| Confetti particle image | `intergalactic/assets/images/effects/particles/confetti.webp` | Commet repository asset; Element Web supports the same `nic.custom.confetti` effect type through canvas-generated particles | `docs/release/evidence/license-sources/commet/commetassets.md` records first-observed Commet commit `3d39f25`, AGPL repository-asset inheritance, unknown upstream original creator, and 2026-06-14 user/owner acceptance | OK WITH NOTICE SURFACE | Release-ready evidence for this release pass. Element confirms interoperability only; Commet evidence covers release provenance. Include Commet AGPL/fork/source notices. |
| Theme/config/l10n JSON | `intergalactic/assets/themes/**`; `intergalactic/assets/config/**`; `intergalactic/assets/l10n/**` | Project/app data and localization data | No third-party media license issue identified in static pass | OK WITH REVIEW | Recheck if imported translations or theme imagery are added. |
| Emoji metadata and shortcodes | `intergalactic/assets/emoji_data/**` | `emojibase-data@17.0.0` | `intergalactic/assets/emoji_data/SOURCE.md`; `docs/release/evidence/license-sources/emojibase/SOURCE.md`; MIT license evidence in `docs/release/evidence/license-sources/emojibase/LICENSE.txt` | OK WITH NOTICE SURFACE | REVIEW regenerated `data.json` from `package/en/data.json` and `shortcodes/en.json` from `package/en/shortcodes/emojibase.json` on 2026-06-13, removed the stale Commet-era readme, and recorded package tarball, gitHead, integrity, generation command, project links, and shipped file hashes. Include Emojibase MIT attribution/source details in the final notice surface. |
| URL/data rules | `intergalactic/assets/data/clearurls.json`; `sources.txt`; `url_handlers.json` | ClearURLs Rules source pin for `clearurls.json` | Source pin and mirrored LGPL/source evidence exist in `docs/release/evidence/license-sources/clearurls/`, including `SOURCE.md` | OK WITH SOURCE OFFER | REVIEW accepted current `ClearURLs/Rules @ 9317c06` handling on 2026-06-14. Include LGPL-3.0 notice and source-offer/source-link details in the final app/release notice surface. |
| JS package directory | `intergalactic/assets/js/package/**` | Empty placeholder directory in static pass | Only `.gitkeep` found | OK | Re-audit if JS/WASM files are added. |
| Vodozemac asset directory | `intergalactic/assets/vodozemac/**` | Empty placeholder directory in static pass | Only `.gitkeep` found | OK | Re-audit if crypto/WASM assets are added. |
| App shaders | `intergalactic/assets/shader/**`; Tiamat shader assets | Inter Galactic-authored active login shader; Tiamat local shader assets | Active pubspec-listed login shader is `constellation.frag` | OK WITH REVIEW | Re-audit if imported shader material is added later. |
| Fastlane/store images | `intergalactic/fastlane/metadata/**` and store screenshots/images if present | Copied Commet store-page images | Removed from the repo on 2026-06-13 by user direction | REMOVED | Future store images should be current Inter Galactic-owned/listing material before store submission. |

## Remaining File/Use Inventory

### Sounds

Commet asset provenance evidence reviewed on 2026-06-13 and accepted for this
release evidence gate on 2026-06-14:
`docs/release/evidence/license-sources/commet/commetassets.md` records these sound files as
upstream Commet repository assets inherited under the Commet AGPL repository
asset umbrella, with original creator unknown upstream. First-observed commits:
`ringtone_in.ogg` and `ringtone_out.ogg` in `584252a`; `joined_call.ogg` and
`left_call.ogg` in `91aff36`; `message.ogg` in `9f3887b`; `muted.ogg` and
`unmuted.ogg` in `b30cfb2`. Android raw sound resources should stay tied to the
matching Commet sound evidence unless replaced or regenerated from a different
source.

| File | Use |
| --- | --- |
| `intergalactic/assets/sound/message.ogg` | Default app and room notification sound via `CustomSoundManager`; used by desktop notification playback paths. |
| `intergalactic/assets/sound/ringtone_in.ogg` | Default incoming-call ringtone via `CustomSoundManager`. |
| `intergalactic/assets/sound/ringtone_out.ogg` | Default outgoing-call ringtone via `CustomSoundManager`. |
| `intergalactic/assets/sound/joined_call.ogg` | Played by `CallManager` when joining a call. |
| `intergalactic/assets/sound/left_call.ogg` | Played by `CallManager` when leaving or ending a call. |
| `intergalactic/assets/sound/muted.ogg` | Played by `CallManager` for mute and push-to-talk end feedback. |
| `intergalactic/assets/sound/unmuted.ogg` | Played by `CallManager` for unmute and push-to-talk start feedback. |
| `intergalactic/android/app/src/main/res/raw/message.wav` | Android raw resource for message/story notification channel sound. |
| `intergalactic/android/app/src/main/res/raw/ringtone_in.wav` | Android raw resource for incoming-call notification channel sound. |

### Placeholder Avatars

User confirmation on 2026-06-13: `avatar1.jpg` and `avatar2.jpg` were created
by Commet.

| File | Use |
| --- | --- |
| `intergalactic/assets/images/placeholders/avatar1.jpg` | Sample avatar in text chat, voice room, and calendar room creation previews. |
| `intergalactic/assets/images/placeholders/avatar2.jpg` | Sample avatar in text chat, voice room, and calendar room creation previews. |

### Placeholder Photos

License evidence reviewed on 2026-06-13: the Pexels license page states Pexels
photos and videos are free to use, attribution is not required, and modification
is allowed. The listed Pexels restrictions still apply.

| File | Use |
| --- | --- |
| `intergalactic/assets/images/placeholders/photos/pexels-stijn-dijkstra-1306815-16747816.jpg` | Photo album creator sample grid; demo single-photo event fallback. |
| `intergalactic/assets/images/placeholders/photos/pexels-james-lee-932763-2017111.jpg` | Photo album creator sample grid; demo photo stack root. |
| `intergalactic/assets/images/placeholders/photos/pexels-kostiantyn-35582290.jpg` | Photo album creator sample grid; second demo photo stack item. |
| `intergalactic/assets/images/placeholders/photos/pexels-rdne-8474967.jpg` | Photo album creator sample grid; third demo photo stack item. |
| `intergalactic/assets/images/placeholders/photos/pexels-fr3nks-287229.jpg` | Photo album creator sample grid; demo photo fallback. |
| `intergalactic/assets/images/placeholders/photos/pexels-nivdex-796206.jpg` | Photo album creator sample grid. |
| `intergalactic/assets/images/placeholders/photos/pexels-mikhail-nilov-8221589.jpg` | Photo album creator sample grid. |
| `intergalactic/assets/images/placeholders/photos/pexels-krisof-1252873.jpg` | Photo album creator sample grid. |
| `intergalactic/assets/images/placeholders/photos/pexels-byrahul-2162909.jpg` | Photo album creator sample grid. |

### Confetti

Commet asset provenance evidence reviewed on 2026-06-13 and accepted for this
release evidence gate on 2026-06-14:
`docs/release/evidence/license-sources/commet/commetassets.md` records
`commet/assets/images/effects/particles/confetti.webp` as first observed in
Commet commit `3d39f25` (`implement message effects (#401)`) and inherited as
an upstream Commet AGPL repository asset, with original creator unknown
upstream.

| File | Use |
| --- | --- |
| `intergalactic/assets/images/effects/particles/confetti.webp` | 59-frame 64x64 sprite sheet loaded by `ParticleSystemConfetti` for the `MessageEffectConfetti` message effect. SHA-256 matches `references/commet-main/commet/assets/images/effects/particles/confetti.webp`; Element Web supports `nic.custom.confetti` using generated canvas particles, not this image file. |

### Store Images

Removed on 2026-06-13 by user direction: copied Commet Android Fastlane store
images under `fastlane/metadata/android/{en-US,jp-JP,zh-CN}/images/**`.
Fastlane text metadata remains, but future store listing images must be current
Inter Galactic-owned/listing material before store submission.

## Required Follow-Up Evidence

- Current release: user confirmed on 2026-06-16 that the notice/access surface
  is verified, including accepted attribution text for assets marked
  `OK WITH NOTICE SURFACE`.
- Keep the accepted Commet unknown-creator provenance notes with release records
  unless the assets are replaced or counsel requires stricter provenance.
- Remove or replace any future assets whose source/license cannot be verified or
  explicitly accepted.
- Re-run the static inventory after any asset replacement.
- Re-run the notice/access-surface check after any change to bundled assets,
  notice routing, dependency state, or release SDK state.

## Commet And Inherited Assets

Some assets may have been inherited from Commet. Treat inherited status as a
provenance lead, not final evidence by itself. For the retained sound/ringtone
assets and `confetti.webp`, cite
`docs/release/evidence/license-sources/commet/commetassets.md` as the accepted
Commet AGPL repository-asset evidence for this release pass. Future inherited
assets still need their own source/license evidence, replacement, or explicit
release acceptance before closure.
