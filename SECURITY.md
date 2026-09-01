# Security Policy

Inter Galactic is an active beta Matrix client. Security reports are taken seriously, especially issues involving account recovery, authentication, end-to-end encryption handling, update manifests, release artifacts, and private user data.

## Supported Versions

| Release channel | Security support |
| --- | --- |
| Latest public beta | Supported |
| Older beta builds | Best-effort only when needed to reproduce a current issue |
| Unreleased local builds | Not supported unless requested by maintainers for investigation |

Users should update to the latest public beta before reporting a fixed issue as still active.

## Reporting A Vulnerability

Please report security issues privately.

Preferred path:

- Open a GitHub Security Advisory for this repository.

Alternate contact:

- Email `intergalactic@ourgalaxy.space` with a short summary and a safe way to
  contact you.

Please include:

- Affected platform and app version.
- Clear reproduction steps.
- Expected impact.
- Whether the issue affects Inter Galactic app code, release/update infrastructure, or an Inter Galactic-operated service.
- Minimal logs or screenshots needed to understand the issue.

Do not include:

- Matrix access tokens.
- Passwords, recovery codes, one-time codes, private keys, or session secrets.
- Full diagnostic bundles in a public place.
- Private homeserver hostnames, private room IDs, or private user identifiers unless maintainers request them through a private channel.

## Scope

In scope:

- Inter Galactic app code in this repository.
- Release manifests, desktop update flow, and release artifact integrity checks.
- Account recovery, authentication, session verification, and end-to-end encryption integration defects.
- Security-sensitive behavior in Inter Galactic-operated beta services.

Out of scope:

- Vulnerabilities that only affect upstream Matrix, Flutter, LiveKit, or Commet projects without an Inter Galactic-specific integration issue.
- Social engineering, spam, denial-of-service against public infrastructure, or physical attacks.
- Reports that require accessing accounts, rooms, or systems you do not own or have permission to test.

## Response Expectations

Maintainers aim to acknowledge valid private reports within 7 days and provide an initial triage result within 14 days. Fix timelines depend on severity, exploitability, beta release timing, and whether the issue is in Inter Galactic code or an upstream dependency.

Security fixes may ship before detailed public notes are published.

## Public Issues

Use public issues for ordinary bugs and beta feedback. If a report may expose a
security weakness, account data, private infrastructure, or update integrity
problem, use the private reporting paths above instead. For non-security
support or account-model questions, use [docs/policies/SUPPORT.md](docs/policies/SUPPORT.md).
