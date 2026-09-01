#!/usr/bin/env bash
#
# Capture Forgejo CI-owned command output into a bounded self-service
# transcript. This deliberately records only the commands this workflow owns,
# not raw runner caches, environment dumps, or Forgejo/act internals.
#
# Two rules govern every change to this file.
#
# RULE 1 - THIS IS AN OBSERVABILITY SIDECAR AND MUST NOT GATE THE BUILD.
# Publishing and pruning run under `set -euo pipefail` in an `if: always()`
# step, so any non-zero return there reports an otherwise-green run as failed,
# with an error about log handling rather than about the code. Every
# publish/prune failure path therefore emits an annotation and returns 0. The
# only status this file may propagate is the WRAPPED COMMAND's, from
# ci_capture / ci_capture_script - never the plumbing's.
#
# RULE 2 - EVERYTHING WRITTEN TO THE TRANSCRIPT IS SCRUBBED FIRST.
# The Forgejo/act runner masks `secrets.*` values as `***` in ITS OWN log
# stream, but that substitution does not apply to a file this job writes with
# `tee`. The published transcript is mode 0644 in a shared directory with a
# retention window, so an unscrubbed transcript would be strictly LESS
# protected than the runner log it replaces. Do not add a `tee` that bypasses
# ci_transcript_scrub.

# Reduce an untrusted-ish identifier to path-safe characters. Applied to the
# run id, attempt and job name so nothing can escape the transcript directory
# or collide with the staging files used during publish.
ci_transcript_slug() {
  printf '%s' "${1-}" | tr -c 'A-Za-z0-9._-' '-'
}

# The `<run_id>-<attempt>-<job>.log` convention documented in
# docs/ci/forgejo-ci-transcripts.md. Used for both the staging path under the
# runner temp directory and the published path.
ci_transcript_basename() {
  local run_id attempt job
  run_id="$(ci_transcript_slug "${GITHUB_RUN_ID:-manual}")"
  attempt="$(ci_transcript_slug "${GITHUB_RUN_ATTEMPT:-1}")"
  job="$(ci_transcript_slug "${GITHUB_JOB:-job}")"
  printf '%s-%s-%s.log\n' "$run_id" "$attempt" "$job"
}

ci_transcript_file() {
  if [[ -n "${CI_TRANSCRIPT_FILE:-}" ]]; then
    printf '%s\n' "$CI_TRANSCRIPT_FILE"
    return 0
  fi

  local temp
  if [[ -n "${RUNNER_TEMP:-}" ]]; then
    temp="$RUNNER_TEMP"
  else
    # Manual or local invocation. Do not drop a predictable filename directly
    # into a world-writable /tmp; scope it to a directory this uid owns (mode
    # 0700, set in ci_transcript_init). Deliberately NOT a hard failure: per
    # rule 1 a missing runner variable must not fail the build.
    temp="${TMPDIR:-/tmp}/forgejo-ci-$(id -u 2>/dev/null || printf '%s' unknown)"
  fi

  printf '%s\n' "$temp/forgejo-ci-$(ci_transcript_basename)"
}

ci_transcript_init() {
  local transcript dir
  transcript="$(ci_transcript_file)"
  dir="$(dirname "$transcript")"
  # Non-fatal by rule 1: a transcript we cannot stage must not fail the step
  # that was only trying to run a gate.
  mkdir -p "$dir" 2>/dev/null || true
  if [[ -z "${RUNNER_TEMP:-}" && -z "${CI_TRANSCRIPT_FILE:-}" ]]; then
    # Only tighten the fallback directory we created ourselves; never chmod a
    # runner-provided RUNNER_TEMP.
    chmod 0700 "$dir" 2>/dev/null || true
  fi
  touch "$transcript" 2>/dev/null || true
  chmod 0600 "$transcript" 2>/dev/null || true
  # Write once, before any captured command output. Route even this fixed-format
  # metadata through the scrubber: the transcript boundary has no exceptions.
  if [[ ! -s "$transcript" ]]; then
    ci_transcript_identity | ci_transcript_scrub >> "$transcript" 2>/dev/null || true
  fi
}

# Each job must start with a fresh transcript. Some Forgejo runner versions can
# reuse a transcript pathname across runs, so "append if non-empty" alone can
# attach current gate output to an older commit's record. The workflow invokes
# this once, immediately after checkout, before any ci_capture call.
ci_transcript_reset() {
  local transcript
  transcript="$(ci_transcript_file)"
  ci_transcript_init
  if ! : > "$transcript" 2>/dev/null; then
    echo "::warning::Cannot initialize CI transcript: $transcript"
    return 0
  fi
  chmod 0600 "$transcript" 2>/dev/null || true
  if ! ci_transcript_identity | ci_transcript_scrub >> "$transcript" 2>/dev/null; then
    echo "::warning::Cannot write CI transcript identity line."
  fi
  return 0
}

# Redaction pass. Every byte that reaches the transcript passes through here.
#
# The pattern set mirrors scripts/ci/check-security-docs.sh - the repo's
# existing definition of a sensitive literal - plus credential-bearing URLs.
# Each rule keeps its identifying prefix so a reader can still tell WHAT was
# removed. As of this commit no step in .forgejo/workflows/forgejo-ci.yml
# prints a secret (no `set -x`, no env dumps, no curl, and checkout uses
# `persist-credentials: false`), so this is defence in depth against a future
# step, not a fix for an active leak.
#
# NOTE FOR ANY FUTURE EDIT: this stage sits in the MIDDLE of the capture
# pipeline (`command | scrub | tee`), which is why `PIPESTATUS[0]` still holds
# the wrapped command's status. Never move it ahead of the command, and never
# read PIPESTATUS after any other command has run.
ci_transcript_scrub() {
  local -a sed_cmd
  # `-u` keeps the transcript current for a step killed by the job timeout or
  # superseded by `cancel-in-progress`; fall back cleanly if unsupported.
  if printf '' | sed -u -E '' >/dev/null 2>&1; then
    sed_cmd=(sed -u -E)
  else
    sed_cmd=(sed -E)
  fi

  "${sed_cmd[@]}" \
    -e '/-----BEGIN [A-Z ]*PRIVATE KEY-----/,/-----END [A-Z ]*PRIVATE KEY-----/s/.*/<redacted private key material>/' \
    -e 's/syt_[A-Za-z0-9._=+-]{8,}/<redacted matrix access token>/g' \
    -e 's/syr_[A-Za-z0-9._=+-]{8,}/<redacted matrix refresh token>/g' \
    -e 's/(authorization[[:space:]]*:[[:space:]]*bearer[[:space:]]+)[^[:space:]]+/\1<redacted>/Ig' \
    -e 's/(access_token[[:space:]]*[:=][[:space:]]*["'\'']?)[^[:space:]"'\'',;&]{8,}/\1<redacted>/Ig' \
    -e 's#(://)[^/@[:space:]]*:[^/@[:space:]]*@#\1<redacted>@#g'
}

# The transcript consumer needs a stable identity it can compare to the full
# commit SHA it resolved from Forgejo. A ref is mutable and is not a suitable
# substitute. Keep the invalid form deliberately non-identity-shaped: readers
# must return provenance-unverified rather than guessing from surrounding text.
ci_transcript_identity() {
  local sha="${GITHUB_SHA:-}"
  if [[ "$sha" =~ ^[0-9A-Fa-f]{40}$ ]]; then
    printf 'Commit SHA: %s\n' "$(printf '%s' "$sha" | tr 'A-F' 'a-f')"
  else
    printf 'Commit SHA: provenance-unverified\n'
  fi
}

ci_transcript_header() {
  local label="$1"
  local transcript
  transcript="$(ci_transcript_file)"
  ci_transcript_init
  {
    printf '\n===== %s =====\n' "$label"
    date -u '+started=%Y-%m-%dT%H:%M:%SZ'
  } >> "$transcript" 2>/dev/null || true
}

ci_capture() {
  local label="$1"
  shift
  local transcript status had_errexit
  case "$-" in
    *e*) had_errexit=1 ;;
    *) had_errexit=0 ;;
  esac
  transcript="$(ci_transcript_file)"
  ci_transcript_header "$label"
  set +e
  "$@" 2>&1 | ci_transcript_scrub | tee -a "$transcript"
  status="${PIPESTATUS[0]}"
  if [[ "$had_errexit" == 1 ]]; then
    set -e
  else
    set +e
  fi
  printf 'exit=%s\n' "$status" >> "$transcript" 2>/dev/null || true
  return "$status"
}

ci_capture_script() {
  local label="$1"
  local script_file transcript status had_errexit
  case "$-" in
    *e*) had_errexit=1 ;;
    *) had_errexit=0 ;;
  esac
  script_file="$(mktemp "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/forgejo-ci-script.XXXXXX")"
  transcript="$(ci_transcript_file)"
  cat > "$script_file"
  ci_transcript_header "$label"
  set +e
  bash -euo pipefail "$script_file" 2>&1 | ci_transcript_scrub | tee -a "$transcript"
  status="${PIPESTATUS[0]}"
  if [[ "$had_errexit" == 1 ]]; then
    set -e
  else
    set +e
  fi
  rm -f "$script_file"
  printf 'exit=%s\n' "$status" >> "$transcript" 2>/dev/null || true
  return "$status"
}

ci_publish_transcript_hint() {
  # Account and group are intentionally placeholders: this repository has a
  # public mirror, and the concrete runner identities live in the private
  # workspace provisioning notes.
  echo "::error::Host setup needed, for example: sudo install -d -o <runner-account> -g <reader-group> -m 0755 $1"
  echo "[notice] Transcript publishing is non-fatal; the run result is unaffected."
}

ci_publish_transcript() {
  local transcript dest_dir dest tmp max_age
  transcript="$(ci_transcript_file)"
  dest_dir="${CI_TRANSCRIPT_DIR:-/srv/ci/ci-logs}"
  dest="$dest_dir/$(ci_transcript_basename)"
  max_age="${CI_TRANSCRIPT_MAX_AGE_DAYS:-14}"

  # Every exit path below returns 0 on purpose - see rule 1 in the header. The
  # `::error::` annotations carry the operator signal; the exit code must not.

  if [[ ! -s "$transcript" ]]; then
    echo "[notice] No CI transcript was captured; nothing to publish."
    return 0
  fi

  if ! mkdir -p "$dest_dir" 2>/dev/null; then
    echo "::error::Cannot create CI transcript directory: $dest_dir"
    ci_publish_transcript_hint "$dest_dir"
    return 0
  fi

  if [[ ! -w "$dest_dir" ]]; then
    echo "::error::CI transcript directory is not writable by this runner: $dest_dir"
    ci_publish_transcript_hint "$dest_dir"
    return 0
  fi

  # mktemp rather than "$dest.tmp.$$": the destination is a shared directory,
  # and a PID-derived name is guessable by anything else running on the host.
  if ! tmp="$(mktemp "$dest_dir/.tmp.XXXXXX" 2>/dev/null)"; then
    echo "::error::Cannot stage a temporary file in the CI transcript directory: $dest_dir"
    ci_publish_transcript_hint "$dest_dir"
    return 0
  fi

  if ! cp "$transcript" "$tmp" 2>/dev/null \
    || ! chmod 0644 "$tmp" 2>/dev/null \
    || ! mv "$tmp" "$dest" 2>/dev/null; then
    echo "::error::Failed to publish the CI transcript to: $dest"
    echo "[notice] Transcript publishing is non-fatal; the run result is unaffected."
    rm -f "$tmp" 2>/dev/null || true
    return 0
  fi

  echo "Published CI transcript: $dest"

  # Pruning is best-effort for the same reason: one stale file this uid cannot
  # unlink must not turn the run red. The glob is restricted to the published
  # `<run_id>-<attempt>-<job>.log` shape, so nothing else an operator leaves in
  # the directory is touched - and it deliberately does not match the
  # `.tmp.XXXXXX` staging files a concurrent job may be writing.
  if [[ "$max_age" =~ ^[0-9]+$ ]]; then
    if ! find "$dest_dir" -maxdepth 1 -type f -name '*-*-*.log' -mtime +"$max_age" -delete 2>/dev/null; then
      echo "::warning::Could not prune every CI transcript older than $max_age days in $dest_dir."
    fi
  else
    echo "::warning::CI_TRANSCRIPT_MAX_AGE_DAYS is not numeric; skipping age pruning."
  fi

  return 0
}
