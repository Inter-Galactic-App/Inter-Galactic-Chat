#!/usr/bin/env bash
# Offline controls for the web-build trigger resolver.
#
# The gate this covers is only useful when it ARMS, and a gate that skips looks
# exactly like a gate that passed. So each row below is a change set with a
# decided answer, and the second half of this file re-runs the same table
# through the PREVIOUS predicate to prove the table is not vacuous: if these
# cases could not tell the old wrong-scoped gate from the new one, they would
# not be evidence about anything.
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
resolver="$script_dir/web-build-triggers.sh"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/web-build-triggers-test.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

# name | expected decision | changed-file list (newline separated, may be empty)
names=()
expected=()
bodies=()

case_add() {
  names+=("$1")
  expected+=("$2")
  bodies+=("$3")
}

# --- should RUN -----------------------------------------------------------
case_add 'app lib Dart'            run  'intergalactic/lib/main.dart'
case_add 'generated lib Dart'      run  'intergalactic/lib/generated/l10n.dart'
case_add 'generated .g.dart'       run  'intergalactic/lib/model/thing.g.dart'
# Both generated shapes, because `legacy_decide` strips BOTH and the table only
# tested one: a future filter that skipped only Freezed output would have
# separated from legacy on no row and still passed this suite.
case_add 'generated .freezed.dart' run  'intergalactic/lib/model/thing.freezed.dart'
case_add 'workspace pkg lib'       run  'tiamat/lib/atoms/tile.dart'
case_add 'widget pkg lib'          run  'widgets/calendar/lib/calendar.dart'
case_add 'plugin pkg lib'          run  'plugins/intergalactic_windows_share/lib/share.dart'
case_add 'web app shell'           run  'intergalactic/web/index.html'
case_add 'root pubspec.yaml'       run  'pubspec.yaml'
case_add 'root pubspec.lock'       run  'pubspec.lock'
case_add 'member pubspec.yaml'     run  'intergalactic/pubspec.yaml'
case_add 'other member pubspec'    run  'tiamat/pubspec.yaml'
case_add 'flutter pin'             run  '.flutter-version'
case_add 'the gate itself'         run  '.forgejo/workflows/forgejo-ci.yml'
case_add 'this resolver'           run  'scripts/ci/web-build-triggers.sh'
case_add 'docs plus one lib file'  run  'docs/CHANGE_LOG.md
intergalactic/lib/main.dart'

# --- should SKIP ----------------------------------------------------------
case_add 'test only'               skip 'intergalactic/test/foo_test.dart'
case_add 'docs only'               skip 'docs/CHANGE_LOG.md
README.md'
case_add 'empty change set'        skip ''
case_add 'android only'            skip 'intergalactic/android/app/build.gradle'
case_add 'windows native only'     skip 'intergalactic/windows/runner/main.cpp'
case_add 'near miss libfoo'        skip 'intergalactic/libfoo/x.dart'
case_add 'near miss web_extra'     skip 'intergalactic/web_extra/x.html'
case_add 'near miss nested lib'    skip 'docs/intergalactic/lib/x.dart'
case_add 'near miss pubspec.bak'   skip 'intergalactic/pubspec.yaml.bak'
case_add 'near miss lock in tools' skip 'tools/release/pubspec.lock'
case_add 'non-member pubspec'      skip 'tools/pubspec.yaml'

decide() { # decide <list-file> -> prints run|skip, exits 1 on resolver error
  local rc=0
  bash "$resolver" "$1" >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0)  printf 'run\n' ;;
    10) printf 'skip\n' ;;
    *)  printf 'error(%d)\n' "$rc" ;;
  esac
}

legacy_decide() { # the predicate this change replaces, for the vacuity control
  local list="$1" dart f
  dart="$(grep '\.dart$' "$list" \
    | grep -vE '(^|/)lib/generated/' \
    | grep -vE '\.(g|freezed)\.dart$' || true)"
  [[ -z "$dart" ]] && { printf 'skip\n'; return; }
  while IFS= read -r f; do
    if [[ "$f" == intergalactic/lib/* ]]; then printf 'run\n'; return; fi
  done <<< "$dart"
  printf 'skip\n'
}

printf '%-24s %-8s %-8s %-8s %s\n' CASE EXPECT ACTUAL LEGACY RESULT
printf '%-24s %-8s %-8s %-8s %s\n' ------------------------ -------- -------- -------- ------
failures=0
separated=0
for i in "${!names[@]}"; do
  list="$tmpdir/case-$i.txt"
  if [[ -n "${bodies[$i]}" ]]; then printf '%s\n' "${bodies[$i]}" > "$list"; else : > "$list"; fi

  actual="$(decide "$list")"
  legacy="$(legacy_decide "$list")"
  result=ok
  if [[ "$actual" != "${expected[$i]}" ]]; then result=FAIL; failures=$((failures + 1)); fi
  if [[ "$legacy" != "$actual" ]]; then separated=$((separated + 1)); fi
  printf '%-24s %-8s %-8s %-8s %s\n' "${names[$i]}" "${expected[$i]}" "$actual" "$legacy" "$result"
done

# A missing list is not a skip. The caller must fail the run instead of
# reporting a green that means "the question could not be asked".
missing_rc=0
bash "$resolver" "$tmpdir/does-not-exist.txt" >/dev/null 2>&1 || missing_rc=$?
printf '%-24s %-8s %-8s %-8s %s\n' 'missing list file' 'error' \
  "$([[ "$missing_rc" -eq 1 ]] && echo error || echo "rc=$missing_rc")" '-' \
  "$([[ "$missing_rc" -eq 1 ]] && echo ok || echo FAIL)"
[[ "$missing_rc" -eq 1 ]] || failures=$((failures + 1))

no_arg_rc=0
bash "$resolver" >/dev/null 2>&1 || no_arg_rc=$?
[[ "$no_arg_rc" -eq 1 ]] || { echo "no-argument invocation returned $no_arg_rc, expected 1"; failures=$((failures + 1)); }

echo
# VACUITY CONTROL. The old predicate must disagree with the new one on the
# cases this change exists to fix. If that count is zero, the table above is
# passing against a gate it cannot distinguish from the broken one.
minimum_separated=8
echo "Cases where the previous predicate decided differently: $separated"
if [[ "$separated" -lt "$minimum_separated" ]]; then
  echo "::error::Only $separated case(s) separate the new predicate from the old one;"
  echo "::error::expected at least $minimum_separated. This table would pass against the bug."
  failures=$((failures + 1))
fi

if [[ "$failures" -ne 0 ]]; then
  echo "web build trigger resolver controls: $failures FAILED"
  exit 1
fi
echo 'web build trigger resolver controls: pass'
