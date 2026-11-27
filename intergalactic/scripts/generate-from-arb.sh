#!/usr/bin/env bash
#
# Regenerate the Intl message catalogues.
#
# THIS IS THE SECOND CODEGEN STEP AND build_runner DOES NOT DO IT. A fresh
# worktree needs `flutter pub get` at the CHECKOUT ROOT (it is a pub
# workspace), then `dart run build_runner build`, then this. Skip it and the
# app fails to compile on `lib/generated/intl/messages_all.dart`, which reads
# as a missing file rather than a missing build step.
#
# Corrected 2026-08-19. This script previously wrote to `lib/generated/l10n`
# while `lib/main.dart` imports `generated/intl/messages_all.dart`, so running
# it produced output the app never loads and left the real directory stale.
# It also passed every .dart file under lib/, which on Windows exceeds the
# command-line length limit.
#
# Inputs are the files that actually declare messages, not all of lib/. A
# message must be declared EXACTLY ONCE across them: two declarations sharing
# an explicit `name:` emit duplicate `static mN(...)` symbols and the generated
# library will not compile.

set -euo pipefail
cd "$(dirname "$0")/.."

OUT_DIR="lib/generated/intl"
mkdir -p "$OUT_DIR"

# Files declaring Intl messages, excluding previously generated output.
mapfile -t SOURCES < <(
  grep -rl --include='*.dart' -E 'Intl\.(message|plural|select|gender)' lib \
    | grep -v '^lib/generated/' \
    | sort
)

if [ "${#SOURCES[@]}" -eq 0 ]; then
  echo "error: no Intl message sources found - the layout changed" >&2
  exit 1
fi

# `nullglob` is what makes the guard below able to fire at all. Without it an
# unmatched glob stays in the array as the literal string `assets/l10n/*.arb`,
# so the count is 1, the guard is skipped, and the pattern is handed to the
# generator as an input path - a confusing generator error instead of the
# message here. The `SOURCES` guard needs no equivalent: `mapfile` produces a
# genuinely empty array.
shopt -s nullglob
ARBS=(assets/l10n/*.arb)
shopt -u nullglob
if [ "${#ARBS[@]}" -eq 0 ]; then
  echo "error: no .arb catalogues found under assets/l10n" >&2
  exit 1
fi

echo "generating ${OUT_DIR} from ${#SOURCES[@]} source(s) and ${#ARBS[@]} catalogue(s)"

dart run intl_translation:generate_from_arb \
  --output-dir="$OUT_DIR" \
  --no-use-deferred-loading \
  "${SOURCES[@]}" \
  "${ARBS[@]}"

# Generating is not succeeding: a duplicate message name still writes files,
# and only compiling reveals it.
if [ ! -f "$OUT_DIR/messages_all.dart" ]; then
  echo "error: ${OUT_DIR}/messages_all.dart was not produced" >&2
  exit 1
fi

echo "done - now compile (e.g. flutter test) to confirm the output is valid"
