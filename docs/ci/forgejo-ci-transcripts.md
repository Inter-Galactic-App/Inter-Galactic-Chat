# Forgejo CI Transcripts

Status: current
Scope: The self-service command transcript that `.forgejo/workflows/forgejo-ci.yml`
publishes for every run, why it exists, where to find it, and what it does not
contain.

## Why this exists

Forgejo exposes **no readable job log** to a token-authenticated caller on the
version this project runs. Every log API route returns `404`, and the web route
wants a browser session cookie that an API token does not satisfy. The runner's
own working directory is not readable either. So a red run could report *that*
something failed and nothing more, and diagnosing it meant asking the maintainer
to export the log by hand from the web UI.

The transcript closes that gap without widening any permission: the workflow
tees the output of **its own commands** into a file and publishes that file to a
directory a reader can actually open.

## Where the transcript lands

```text
$CI_TRANSCRIPT_DIR/<run_id>-<attempt>-<job>.log
```

`CI_TRANSCRIPT_DIR` is set per runner in each job's `env:` block. The concrete
destination on this project's own runner is deliberately not recorded here — see
"Host provisioning" below.

- `<run_id>` — `GITHUB_RUN_ID` for the run.
- `<attempt>` — `GITHUB_RUN_ATTEMPT`; a re-run writes a new file rather than
  overwriting the first attempt.
- `<job>` — `GITHUB_JOB`, reduced to `A-Za-z0-9._-` (any other character becomes
  `-`). For this workflow that is `dart-gates` or `repo-checks`.

All three components are sanitized the same way, so nothing in the run context
can steer the write outside that directory.

Files are published mode `0644`. The directory is overridable per runner with
the `CI_TRANSCRIPT_DIR` environment variable, set in each job's `env:` block.

## Retention

**14 days.** After a successful publish the step prunes files in the same
directory older than `CI_TRANSCRIPT_MAX_AGE_DAYS` (default `14`, set explicitly
in the workflow). The prune is restricted to the `<run_id>-<attempt>-<job>.log`
shape, so anything else an operator leaves in the directory is left alone.

Transcripts are diagnostic scratch, not an archive. If a run matters beyond two
weeks, copy what you need into the relevant report.

## Host provisioning

The publish step does not create the directory tree with elevated rights; it
only writes into a directory that already exists and is writable by the runner
account. On a new runner host, provision `CI_TRANSCRIPT_DIR` once with
`install -d`, owned by the account the Forgejo runner service runs as, and
group-owned by a group containing the accounts that need to read published
transcripts (mode `0755`). Readers also need traverse permission on its parent.

This repository has a public mirror, so the concrete path, service account and
group for this project's runner are **not** recorded here. They live with the
rest of the runner provisioning in the private workspace documentation, per the
public-release hygiene rules in `docs/README.md`. Operators of this project:
see the workspace `docs/agent-control/ci/` notes.

If the directory is missing or unwritable, the publish step prints `::error::`
annotations naming the exact problem and the provisioning command — **and the
run keeps its real result.** See "This never fails the build" below.

## What the transcript contains — and the caveat that matters most

**Repo-owned commands only.**

The workflow wraps its own gate commands (`ci_capture` / `ci_capture_script` in
`scripts/ci/forgejo-transcript.sh`). Each captured block is delimited like this:

```text
===== Check code style =====
started=2026-08-03T20:33:33Z
<the command's merged stdout and stderr>
exit=0
```

Deliberately **not** captured:

- `actions/checkout` and every other action's output;
- Forgejo/act runner internals, container and cache setup, step orchestration;
- environment dumps and runner host detail.

The practical consequence, stated plainly because it will otherwise read as a
bug: **an agent debugging a checkout failure, a runner-provisioning failure, or
a job that died before the first repo-owned command will find nothing about it
in the transcript.** That is expected. An empty or absent transcript for a red
run is itself the finding — it says the run failed *outside* the repo's own
commands, and diagnosis moves to the runner host or to a maintainer export of
the web-UI log.

This boundary is the point of the design, not a limitation to be fixed by
copying raw runner logs in.

## Redaction

Everything written to the transcript passes through `ci_transcript_scrub` before
`tee`. This is defence in depth, not a response to a known leak: as of this
writing no step prints a secret (no `set -x`, no environment dumps, no `curl`,
and checkout runs with `persist-credentials: false`).

It matters anyway, because the Forgejo/act runner masks `secrets.*` values as
`***` **in its own log stream only** — that masking does not apply to a file the
job writes itself. Without the scrubber the published transcript would be
strictly less protected than the runner log it replaces, at `0644` in a shared
directory for two weeks.

Redacted, mirroring the pattern set in `scripts/ci/check-security-docs.sh`:

| Pattern | Replaced with |
| --- | --- |
| `syt_…` Matrix access tokens | `<redacted matrix access token>` |
| `syr_…` Matrix refresh tokens | `<redacted matrix refresh token>` |
| `Authorization: Bearer …` (any case) | prefix kept, value `<redacted>` |
| `access_token=…` / `access_token: …` (any case) | prefix kept, value `<redacted>` |
| PEM `-----BEGIN … PRIVATE KEY-----` blocks | `<redacted private key material>` |
| Credential-bearing URLs, `scheme://user:pass@host` | `scheme://<redacted>@host` |

Each rule keeps its identifying prefix, so a reader can still tell *what* was
removed. Ordinary URLs — including `ssh://git@host:2222/...` remotes — are left
intact.

**If you add a step that emits new output, do not add a `tee` that bypasses the
scrubber.**

## This never fails the build

Transcript publishing is an observability sidecar and must never gate a result.
The publish step runs with `if: always()` under `set -euo pipefail`, so a
non-zero return there would report *every* run — including green ones — as
failed, with an error about log handling rather than about the code.

Accordingly, `ci_publish_transcript` returns success on every failure path
(directory missing, directory unwritable, copy failed, prune failed) after
emitting the annotation that tells an operator what to fix. The workflow adds a
second guard at the call site. A missing transcript directory is an operator
task, not a red branch.

The only status this machinery propagates is the wrapped command's own, from
`ci_capture` / `ci_capture_script` — a failing gate still fails its step, and
its full output still reaches both the transcript and the job log.

## Related

- `.forgejo/workflows/forgejo-ci.yml` — the workflow, and the boundary of what
  this pipeline does and does not gate.
- `scripts/ci/forgejo-transcript.sh` — the capture, redaction and publish
  helpers, with the two rules that govern edits to them.
