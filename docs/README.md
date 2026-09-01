# Inter Galactic Documentation

This folder is part of the public source repository. Keep it useful to anyone
who downloads or clones the repo: contributors, beta testers, maintainers, and
curious operators should be able to understand how the app is shaped, how
changes should be made, and which templates or checklists to start from.

## Public-Safe Doc Types

- `architecture/` explains stable app behavior, package boundaries, data flow,
  and safe modification guidance.
- `ci/` documents the repository's own continuous-integration surface: what the
  workflows gate, and how to get the output of a run. Start with
  `ci/forgejo-ci-transcripts.md` when a Forgejo run is red and you need to see
  why.
- `design/` documents the app design system and UI implementation patterns.
- `testing/` describes validation expectations that contributors can reproduce
  or adapt locally.
- `product/` contains beta-facing templates, feedback triage guidance, and
  known-issue wording that should be understandable without internal tracker
  access.
- `policies/` contains public policy, privacy, support, source-offer, and store
  review notes.
- `adr/` records public architectural decisions.
- `release/` contains portable release expectations, validation checklists,
  versioning rules, artifact hygiene, and rollback guidance. It should explain
  what a correct release proves without depending on one maintainer's local
  workspace automation.

## Public Release Hygiene

Before public release, docs in this repository should avoid:

- workstation-local absolute paths, local artifact folders, synced private
  mirrors, or personal helper-script paths;
- private server internals or unpublished infrastructure details;
- tokens, passwords, signing keys, recovery codes, private room IDs, private
  user IDs, or full diagnostic logs;
- internal agent handoff state or coordination-ledger details in user-facing
  product docs;
- stale links to files that are not present in this repository.

Keep personal release-machine setup, private sync details, and local helper
script notes in private workspace docs outside this repository.

## Internal Tracking

Public docs may describe user-visible behavior and known limitations. Internal
bug IDs, integration queues, agent ownership notes, and private operational
ledgers belong in maintainer-only tracking systems or workspace coordination
docs, not in beta-facing templates.

Maintainer-only workflow details can live in workspace-level docs that sync
across the maintainer's machines. Do not make ordinary app-repo docs depend on
those private files.
