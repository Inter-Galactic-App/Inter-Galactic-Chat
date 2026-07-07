# Release Documentation Boundary

The files in this folder are public release references: versioning policy,
artifact expectations, validation checklists, signing concepts, update-manifest
requirements, and rollback guidance. They should help someone who downloads the
repo understand what a correct Inter Galactic release needs to prove.

Repo docs should not assume one maintainer's private workspace automation,
local artifact directories, synced deployment mirror, signing-machine layout, or
release helper scripts. Those details belong in the maintainer's workspace docs
outside this repository.

GitHub Actions in this repository are validation and smoke-build surfaces, not
the public distribution pipeline. Release publication currently remains a
maintainer-operated process because signing material, Android Firebase client
configuration, update-manifest publication, and TestFlight/App Store steps must
stay outside public source control. If release publication moves to GitHub in
the future, add a tag-triggered workflow with signed artifacts and update these
docs at the same time.

Release pipeline coordination is version specific. Use the semantic version
`X.Y.Z` as the release-cycle boundary and keep candidate/rebuild attempts inside
that cycle as build-specific ledger rows. Exact artifacts, update manifests,
checksums, source archives, TestFlight/App Store uploads, and public downloads
remain `X.Y.Z+build` scoped because users and stores consume exact builds.
When a release candidate fix bumps the build number, continue the same
`release-record-vX.Y.Z.md` cycle record and rerun only the validation gates
invalidated by the changed source, assets, dependencies, signing path,
manifest, or artifacts.

Android release APK builds should refresh Gradle/Maven license evidence for the
shipped dependency graph. The workspace `build_android.bat` release path now
collects that evidence under `docs/release/evidence/android-gradle/<version>/`
after the APK is built and before the shared Google Services state is restored.
FCM builds also collect Firebase/FlutterFire package evidence under
`docs/release/evidence/android-fcm/<version>/` and run Google's OSS licenses
plugin baseline into `docs/release/evidence/android-oss-licenses/<version>/`.
Debug builds skip this evidence refresh, and release rebuilds may use
`--skip-license-evidence` only when the maintainer intentionally wants a local
rebuild without refreshing release documentation evidence.

Public-release rules for this folder:

- never document secrets, signing keys, passwords, tokens, `.env` contents,
  private sync credentials, or local machine paths;
- describe portable release requirements before maintainer-local automation;
- keep historical release records free of private local path details, or store
  the full maintainer-local record outside the public app repo;
- keep ordinary contributor setup in the root `README.md` and
  `CONTRIBUTING.md`.
