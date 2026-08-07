# Third-Party Notices

Publication status: release evidence generated; current release notice/access
surface verified.

The current third-party notice evidence lives under `docs/release/`:

- `../release/THIRD_PARTY_NOTICES.md`
- `../release/THIRD_PARTY_LICENSES.json`
- `../release/LICENSE_AUDIT_REPORT.md`
- `../release/LICENSE_RELEASE_CHECKLIST.md`

## Current Status

The last submitted public binary remains `0.7.3+984`, but the current
third-party notice inventory has advanced to the `0.7.4+985` release-evidence
boundary under `docs/release/`. The inventory accounts for the Commet
fork/AGPL notice, Dart/Flutter package licenses, Flutter SDK rows, iOS pod
acknowledgements, patched WebRTC/RNNoise evidence, FFmpeg evidence, and
mirrored font/asset/source evidence under
`../release/evidence/license-sources/`.

The 2026-06-16 release-owner closeout accepts the current evidence and
notice/access surface for the `0.7.4+985` rollout. The rebuilt Windows FFmpeg
story-export smoke is deferred to the next release because the current runtime
test fails with `video could not be recorded.` This does not reopen the current
license/provenance evidence.

## Required Project Notices

- Inter Galactic is a modified fork of Commet and remains distributed with the
  project AGPL license text in `LICENSE`.
- `FORK_NOTICE.md` preserves upstream Commet attribution and must remain part of
  release/source notice surfaces.
- The app icon family is project-owner-created per owner confirmation on
  2026-06-12.

Keep this page synchronized with `PUBLIC_RELEASE_READINESS_TRACKER.md` and
`ASSET_PROVENANCE.md` whenever Release Pipeline or REVIEW changes release
notice gates, bundled assets, notice routing, or dependency evidence.
