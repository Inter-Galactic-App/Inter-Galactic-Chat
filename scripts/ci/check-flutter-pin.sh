#!/usr/bin/env bash
#
# Fail if any CI workflow pins a Flutter version that disagrees with the
# tracked .flutter-version file.
#
# WHY: the pin was hardcoded independently in six places across two forges
# (.github/workflows/{build,build-web,integration-test,static-analysis}.yml and
# .forgejo/workflows/forgejo-ci.yml). Nothing tied them together, so a bump
# could land in some and not others, and the resulting analyzer noise on a
# mismatched SDK gets blamed on the branch rather than on the pin. Starship
# solves this with a tracked version file its CI verifies against; this is the
# same idea.
#
# This does NOT rewrite the workflows to read the file at runtime -
# `subosito/flutter-action` needs a literal, and a `${{ }}` indirection would
# just move the drift. It asserts the literals agree instead, which is the part
# that actually needs to be true.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${REPO_ROOT:-$(cd "$script_dir/../.." && pwd)}"

version_file="$repo_root/.flutter-version"
if [[ ! -f "$version_file" ]]; then
  echo "[fail] $version_file is missing. It is the single source of truth for the Flutter pin."
  exit 1
fi

# Strip comments, blanks and trailing whitespace/CR.
pinned="$(sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$version_file" | grep -v '^$' | head -1)"

if [[ ! "$pinned" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "[fail] .flutter-version does not contain a bare X.Y.Z version: '$pinned'"
  exit 1
fi

echo "Tracked pin: $pinned"

failures=0
found=0

# `flutter-version: '3.41.1'` in GitHub workflows, and `FLUTTER_PIN: '3.41.1'`
# in the Forgejo workflow, which installs Flutter on the runner rather than
# through an action.
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  found=$((found + 1))
  file="${hit%%:*}"
  rest="${hit#*:}"
  line="${rest%%:*}"
  value="$(printf '%s' "$hit" | sed -E "s/.*:[[:space:]]*['\"]?([0-9]+\.[0-9]+\.[0-9]+)['\"]?[[:space:]]*$/\1/")"
  if [[ "$value" != "$pinned" ]]; then
    echo "[fail] $file:$line pins Flutter $value but .flutter-version says $pinned"
    failures=$((failures + 1))
  else
    echo "[ok]   $file:$line -> $value"
  fi
done < <(
  cd "$repo_root"
  grep -rnE "^[[:space:]]*(flutter-version|FLUTTER_PIN):[[:space:]]*['\"]?[0-9]+\.[0-9]+\.[0-9]+" \
    .github/workflows .forgejo/workflows 2>/dev/null || true
)

if [[ "$found" -eq 0 ]]; then
  # A silent zero-match is how this check would rot into a no-op if the
  # workflows are ever restructured. Treat it as a failure, not a pass.
  echo "[fail] No Flutter pins found in .github/workflows or .forgejo/workflows."
  echo "[fail] Either the workflows moved or this check's pattern is stale; fix one of them."
  exit 1
fi

if [[ "$failures" -gt 0 ]]; then
  echo "Flutter pin check failed: $failures of $found pin(s) disagree with .flutter-version."
  exit 1
fi

echo "Flutter pin check passed: all $found pin(s) agree with .flutter-version ($pinned)."
