#!/usr/bin/env bash
# Deterministic producer controls for the transcript provenance header.
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
helper="$script_dir/forgejo-transcript.sh"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/forgejo-transcript-test.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

valid_sha='0123456789ABCDEF0123456789ABCDEF01234567'

CI_TRANSCRIPT_FILE="$tmpdir/valid.log" GITHUB_SHA="$valid_sha" bash -c '
  source "$1"
  ci_capture valid printf "authorization: bearer syt_abcdefghijk\\n"
' _ "$helper" >/dev/null

CI_TRANSCRIPT_FILE="$tmpdir/absent.log" bash -c '
  source "$1"
  ci_capture absent printf "ok\\n"
' _ "$helper" >/dev/null

CI_TRANSCRIPT_FILE="$tmpdir/malformed.log" GITHUB_SHA='not-a-sha' bash -c '
  source "$1"
  ci_capture malformed printf "ok\\n"
' _ "$helper" >/dev/null

printf 'stale transcript content\n' > "$tmpdir/reset.log"
CI_TRANSCRIPT_FILE="$tmpdir/reset.log" GITHUB_SHA="$valid_sha" bash -c '
  source "$1"
  ci_transcript_reset
' _ "$helper" >/dev/null

test "$(head -n 1 "$tmpdir/valid.log")" = \
  'Commit SHA: 0123456789abcdef0123456789abcdef01234567'
test "$(head -n 1 "$tmpdir/absent.log")" = 'Commit SHA: provenance-unverified'
test "$(head -n 1 "$tmpdir/malformed.log")" = 'Commit SHA: provenance-unverified'
test "$(grep -c '^Commit SHA:' "$tmpdir/valid.log")" = 1
grep -F 'authorization: bearer <redacted>' "$tmpdir/valid.log" >/dev/null
test "$(head -n 1 "$tmpdir/reset.log")" = \
  'Commit SHA: 0123456789abcdef0123456789abcdef01234567'
! grep -F 'stale transcript content' "$tmpdir/reset.log" >/dev/null

echo 'forgejo transcript provenance producer controls: pass'
