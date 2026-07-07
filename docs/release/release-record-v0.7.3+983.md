# Release Record: Inter Galactic v0.7.3+983

Status: release-readiness evidence packet opened - not a release candidate yet
Review date: 2026-06-09
Reviewer: Release Pipeline
Release scope: Windows desktop, Android direct APK download, and iPhone/TestFlight; macOS/Linux remain future-demand architecture targets
Artifact checklist: `docs/release/release-artifact-checklist.md`
Readiness tracker: `docs/policies/PUBLIC_RELEASE_READINESS_TRACKER.md`

## Release Pipeline Summary

This record accepts the REVIEW public-release-readiness handoff for
Release Pipeline-owned evidence. It does not approve a release and does not
close any tracker checkbox.

Packet-open blocker summary, recorded 2026-06-09:

- No submitted binary had been identified for `v0.7.3+983`.
- No frozen release source commit had been selected.
- No public source archive had been generated from a frozen tracked commit.
- Current release scope is confirmed as Windows desktop, Android direct APK,
  and iPhone/TestFlight. macOS and Linux are architecture-capable future-demand
  targets only and should not block this release unless scope expands.
- No public source archive URL or checksum existed for this build.
- No release artifact secret/material scan evidence existed for this build.
- The submission packet in `PUBLIC_RELEASE_READINESS_TRACKER.md` remains
  evidence-gated and should stay incomplete until the exact build is submitted.

## Candidate Identity

| Gate | Result | Evidence |
| --- | --- | --- |
| Pubspec identity | Observed | `intergalactic/pubspec.yaml` reports `version: 0.7.3+983`. |
| Source commit | Not frozen | Packet-open app repo snapshot was `15f27960fcf7661e8d65a5c3f553d42617e262a3`, but no final release source commit has been selected. |
| Release scope | Confirmed | User confirmed current release scope as Windows desktop, Android direct APK download, and iPhone/TestFlight. macOS and Linux remain architecture-capable future-demand targets only. |
| Submitted binary | Blocked | No Windows installer, Android APK, or TestFlight upload evidence has been provided for `v0.7.3+983`. |
| Source archive | Blocked | Must be generated from the final tracked source commit after release freeze. |
| Artifact hygiene | Blocked | Must run against final release artifacts and source archive before publication. |
| Submission packet | Blocked | Must be populated only after source URL, checksums, policy URLs, App Store evidence, and artifact scan evidence exist. |

## Source Archive Requirements

The AGPL source archive for the submitted binary must be created from tracked
source only. Do not zip the working directory.

Required evidence before closing the source-archive tracker item:

- submitted version/build number;
- final release commit SHA;
- archive name, expected format `intergalactic-0.7.3+983-source.zip`;
- archive SHA-256;
- public source archive URL;
- confirmation that Commet/fork attribution remains present;
- confirmation that the archive excludes local secrets, signing material,
  build outputs not needed for source distribution, and private workspace state.

## Artifact Hygiene Requirements

Run artifact hygiene checks only after the release dry run creates final
artifacts.

Required evidence before closing the artifact-hygiene tracker item:

- final artifact list, including Windows installer, Android APK, and
  iPhone/TestFlight build evidence when in release scope;
- checksum file generated after final signing or unsigned-consent decision;
- local security gate result for the final artifact set;
- scan result confirming no `.env`, `key.properties`, JKS/PFX/P12 files, SSH
  keys, API tokens, service-account credentials, signing passwords, local sync
  credentials, or private diagnostic bundles are present;
- explicit note whether Windows is using trusted Authenticode signing or the
  approved checksum-verified unsigned consent path.

## Submission Packet Status

| Field | Status | Evidence |
| --- | --- | --- |
| Submitted app version and build number | Pending | No submitted binary yet. |
| Git commit | Pending | Final release source commit not frozen. |
| PR | Pending | No final release PR recorded in this packet. |
| Source archive URL | Pending | Not generated or published. |
| Source archive checksum | Pending | Not generated. |
| Privacy Policy URL | Pending | Hosted public URL not recorded here. |
| Terms/EULA URL | Pending | Hosted public URL not recorded here. |
| Support URL/email | Pending | Hosted URL and monitored inbox evidence still required. |
| Abuse report URL/email | Pending | Hosted URL and monitored inbox evidence still required. |
| Security contact | Pending | Monitored inbox evidence still required. |
| App Store privacy-label evidence | Pending | Owned by IOS/S&C before final release closeout. |
| Encryption export evidence | Pending | Owned by S&C/IOS before final release closeout. |
| Privacy manifest validation evidence | Pending | Owned by IOS before final release closeout. |
| Artifact secret-scan evidence | Pending | Release Pipeline/S&C coordination required after final artifacts exist. |
| Third-party notices bundle | Pending | Documentation/S&C evidence required. |
| Asset provenance inventory | Pending | Documentation/S&C evidence required. |
| Counsel/legal review note | Pending | Do not infer; record only if supplied by the owner. |

## Release Pipeline Next Steps

1. Wait for release source freeze on the confirmed platform scope.
2. Build/package the selected Windows desktop and Android APK artifacts through
   the release checklist, and record iPhone/TestFlight build/upload evidence
   from the iOS lane.
3. Generate the source archive from the final release commit.
4. Generate checksums after final signing or unsigned-consent decision.
5. Coordinate artifact hygiene criteria with S&C, then scan final artifacts.
6. Record source URL/checksum, artifact scan evidence, and build identity in
   `PUBLIC_RELEASE_READINESS_TRACKER.md`.
7. Leave tracker boxes unchecked until the above evidence exists.
