# Asset Provenance

Publication status: release evidence generated; current release notice/access
surface verified.

The current asset provenance inventory lives under `docs/release/`:

- `../release/ASSET_PROVENANCE.md`
- `../release/THIRD_PARTY_LICENSES.json`
- `../release/LICENSE_AUDIT_REPORT.md`
- `../release/LICENSE_RELEASE_CHECKLIST.md`

## Current Status

The last submitted public binary remains `0.7.3+984`, but the current bundled
asset inventory has advanced to the `0.7.4+985` release-evidence boundary under
`docs/release/`. The release inventory records project-owner evidence for the
Inter Galactic app icon, local evidence for bundled font families, local
evidence for Tiamat Kenney placeholders, regenerated Emojibase evidence,
ClearURLs source notes, Animated Fluent Emojis notes, and Commet-inherited
sound/confetti evidence mirrored into `../release/evidence/license-sources/`.

The 2026-06-16 release-owner closeout accepts the current asset provenance and
notice/access surface for the `0.7.4+985` rollout. Re-open the tracker if asset
bytes, source, bundled dependencies, notice routing, or release SDK state
change.

## Future Recheck Gates

- Keep retained unknown-upstream-creator provenance notes for Commet-inherited
  sound/ringtone and `confetti.webp` assets in final notices unless the asset
  source changes or counsel requires stricter exact-creator provenance.
- Re-run the inventory after any future asset replacement or imported shader
  material.

Keep this page synchronized with `PUBLIC_RELEASE_READINESS_TRACKER.md` and
`THIRD_PARTY_NOTICES.md` whenever Release Pipeline or REVIEW changes release
notice gates, bundled assets, notice routing, or dependency evidence.
