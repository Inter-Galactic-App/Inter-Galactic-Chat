# Public Release Artifact Hygiene

Publication status: mandatory release checklist for public artifacts and source
handoff packages. Keep unresolved verification state synchronized with
`PUBLIC_RELEASE_READINESS_TRACKER.md`.

## Rule

Public source archives and handoff artifacts must be created from tracked source files only. Do not zip the working directory.

## Must Exclude

- `.env` files;
- Android `key.properties`;
- Android keystores;
- PFX/P12 certificates;
- SSH keys;
- API tokens;
- OAuth secrets;
- Apple signing files not intended for public release;
- local sync scripts containing credentials;
- generated build outputs that embed secrets;
- crash/log bundles with user data.

## Verification

For every public artifact:

- record the command used to create it;
- record the commit and build number;
- inspect archive contents before upload;
- search for secret-like names and file extensions;
- verify AGPL source archive matches the submitted binary;
- verify artifact signatures, notarization, or approved unsigned-consent
  records match the release record;
- validate update-manifest version, artifact URL, checksum, and signature
  entries against the submitted artifact set;
- confirm rollback artifact availability, checksum/signature integrity, and the
  documented rollback command or operator process;
- publish checksums.

## Rotation

If any secret exposure is uncertain, rotate the secret before release and record the rotation in private operator notes.
