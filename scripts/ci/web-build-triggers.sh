#!/usr/bin/env bash
# Decide whether a change set can move the result of
# `flutter build web --release`.
#
# WHY THIS IS A SCRIPT AND NOT FOUR LINES OF INLINE YAML. The first version of
# the web gate (2026-09-08) tested the wrong list. It read the workflow's
# REVIEWABLE DART list - the one the formatter and analyzer steps use, which is
# deliberately filtered to `.dart` files with `lib/generated/`, `*.g.dart` and
# `*.freezed.dart` removed - and asked whether any entry started with
# `intergalactic/lib/`. Three consequences, all of them a silent green:
#
#   1. A change confined to `intergalactic/lib/generated/` is filtered out of
#      that list by construction, so the gate could never see it.
#   2. `pubspec.yaml` and `pubspec.lock` are not `.dart` files, so a dependency
#      bump that breaks dart2js skipped the compile and the step exited 0.
#   3. The gate's own definition was invisible to it, which is how its very
#      first CI run went green with the step skipped.
#
# Being a separate script means the predicate can be exercised offline against
# a table of change sets - see test-web-build-triggers.sh - instead of only
# being observable by watching whether a real CI run happened to compile.
#
# EXIT CODES. 0 = run the web compile. 10 = the change set cannot have moved
# the web build, skip it. 1 = the question could not be answered; the caller
# must fail the run rather than treat it as a skip.
set -euo pipefail

list="${1:-}"
if [[ -z "$list" ]]; then
  echo "usage: web-build-triggers.sh <changed-file-list>" >&2
  exit 1
fi
if [[ ! -f "$list" ]]; then
  echo "::error::Changed-file list '$list' does not exist." >&2
  exit 1
fi

# Each rule is an anchored ERE plus the reason it belongs here. Order is
# presentation only; any single match runs the build.
#
# Note what is deliberately NOT filtered to `.dart`: this reads the FULL
# changed-file list, so `lib/generated/`, manifests and lockfiles all reach it.
patterns=()
reasons=()

add_rule() {
  patterns+=("$1")
  reasons+=("$2")
}

# The app's own Dart, generated output included. Generated code is compiled by
# dart2js exactly like hand-written code; excluding it is only ever right for
# gates that review humans, and this gate reviews the compiler.
add_rule '^intergalactic/lib/' \
  'app Dart source (lib/generated included - dart2js compiles it too)'

# Every path dependency and pub-workspace member whose Dart the app imports.
# A break in tiamat/lib or widgets/*/lib reaches the web compile through
# intergalactic/lib without intergalactic/lib itself changing, which is the
# same two-hops-away shape that hid the original month-long regression.
add_rule '^(tiamat|widgets/[^/]+|plugins/[^/]+)/lib/' \
  'workspace or path-dependency Dart compiled into the web bundle'

# The web app shell. index.html, flutter_bootstrap.js, manifest.json and the
# service worker are build inputs; `flutter build web` reads and templates
# them, so a malformed one fails the build with no Dart change at all.
add_rule '^intergalactic/web/' \
  'web app shell templated by the web build'

# THE MANIFESTS THAT MATTER, and why these and not others. This is a pub
# workspace: `pubspec.lock` exists ONLY at the repo root and pins the resolved
# version of every dependency of every member, so it is the single file most
# able to change dart2js output without any source change. The root
# `pubspec.yaml` declares the member list itself. Each member's own
# `pubspec.yaml` still declares that member's dependency constraints, so it can
# move the resolution too - members are enumerated by shape rather than by
# name so a member added later is covered without anyone remembering.
add_rule '^pubspec\.(yaml|lock)$' \
  'pub workspace root manifest / the single shared lockfile'
add_rule '^(intergalactic|tiamat|widgets/[^/]+|plugins/[^/]+)/pubspec\.yaml$' \
  'workspace member manifest (its constraints feed the root resolution)'

# The toolchain. A different Flutter is a different dart2js.
add_rule '^\.flutter-version$' \
  'pinned Flutter toolchain, which is the web compiler'

# The gate's own definition, and this resolver. A change to either must
# exercise the build it controls; the alternative is what already happened
# once - shipping a web gate whose own CI run skipped the web build.
add_rule '^\.forgejo/workflows/forgejo-ci\.yml$' \
  "this gate's own definition"
add_rule '^scripts/ci/web-build-triggers\.sh$' \
  'this trigger resolver'

considered="$(grep -c '' "$list" || true)"
echo "Changed files considered: $considered"

matched=0
for i in "${!patterns[@]}"; do
  hits="$(grep -E "${patterns[$i]}" "$list" || true)"
  [[ -z "$hits" ]] && continue
  matched=1
  while IFS= read -r hit; do
    printf '  %s\n      -> %s\n' "$hit" "${reasons[$i]}"
  done <<< "$hits"
done

if [[ "$matched" -eq 1 ]]; then
  echo "Decision: RUN the web compile."
  exit 0
fi

echo "Nothing in this change set can reach the web build: no app or package"
echo "Dart, no web shell file, no manifest, no lockfile, no toolchain pin."
echo "Decision: SKIP the web compile."
exit 10
