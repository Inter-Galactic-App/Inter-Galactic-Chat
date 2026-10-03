#!/usr/bin/env bash
# Offline controls for the tooltip ratchet's Material/house resolution.
#
# The gate counts Material tooltip sites. Until 2026-09-12 it read every bare
# `Tooltip(` as Material, which is only true when the file gets `Tooltip` from
# material.dart - a file importing `package:tiamat/tiamat.dart` unaliased gets
# OURS under the same bare name. `editable_label.dart` was booked as two
# Material sites from the day the gate landed, so the allowlist said two sites
# remained where none did.
#
# Each fixture below is a file with a decided answer. The second half re-runs
# the same table through the OLD predicate (every bare Tooltip is Material) and
# asserts the table separates them - otherwise these cases would pass equally
# against the bug they exist to catch, and would be evidence about nothing.
set -euo pipefail

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
gate="$script_dir/check-tooltip-component.sh"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/tooltip-gate-test.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

names=()
expected=()
bodies=()

case_add() {
  names+=("$1")
  expected+=("$2")
  bodies+=("$3")
}

# --- counted: the site really is Material ---------------------------------
case_add 'bare Tooltip, material unaliased' 1 \
"import 'package:flutter/material.dart';
Widget b() => Tooltip(message: 'x', child: Container());"

case_add 'aliased material.Tooltip' 1 \
"import 'package:flutter/material.dart' as material;
import 'package:tiamat/tiamat.dart';
Widget b() => material.Tooltip(message: 'x', child: Container());"

case_add 'nonstandard Material alias with unaliased house import' 1 \
"import 'package:flutter/material.dart' as flutter_material;
import 'package:tiamat/tiamat.dart';
Widget b() => flutter_material.Tooltip(message: 'x', child: Container());"

# An unaliased tiamat import that does NOT export Tooltip must not launder a
# bare Material site - this is the shape call_view.dart has.
case_add 'bare Tooltip, tiamat aliased + unrelated tiamat import' 1 \
"import 'package:flutter/material.dart';
import 'package:tiamat/atoms/avatar.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
Widget b() => Tooltip(message: 'x', child: Container());"

# --- not counted: the bare name is the house component --------------------
case_add 'bare Tooltip, tiamat.dart unaliased' 0 \
"import 'package:flutter/widgets.dart';
import 'package:tiamat/tiamat.dart';
Widget b() => Tooltip(text: 'x', child: Container());"

case_add 'bare Tooltip, atoms/tooltip.dart unaliased' 0 \
"import 'package:flutter/widgets.dart';
import 'package:tiamat/atoms/tooltip.dart';
Widget b() => Tooltip(text: 'x', child: Container());"

count_for() {
  # Runs the real gate over a throwaway repo containing one file, with an
  # empty allowlist, and reads the count out of its failure report.
  local body="$1"
  local root="$tmpdir/repo"
  rm -rf "$root"
  mkdir -p "$root/intergalactic/lib" "$root/scripts/ci"
  printf '%s\n' "$body" > "$root/intergalactic/lib/subject.dart"
  cp "$gate" "$root/scripts/ci/check-tooltip-component.sh"
  printf '# empty\n' > "$root/scripts/ci/tooltip-allowlist.txt"

  local out status=0 count
  out="$(REPO_ROOT="$root" bash "$root/scripts/ci/check-tooltip-component.sh" 2>&1)" || status=$?
  if [[ "$status" -eq 0 ]] &&
     grep -q '\[ok\] Tooltip gate passed with 0 grandfathered site(s)' <<<"$out"; then
    echo 0
    return
  fi
  count="$(sed -n 's/.*introduces \([0-9][0-9]*\) Material tooltip.*/\1/p' <<<"$out" | head -1)"
  if [[ "$status" -eq 1 ]] && [[ "$count" =~ ^[1-9][0-9]*$ ]]; then
    echo "$count"
    return
  fi
  printf '[fail] tooltip gate returned unexpected status/output (%s):\n%s\n' "$status" "$out" >&2
  return 1
}

failures=0
for i in "${!names[@]}"; do
  got="$(count_for "${bodies[$i]}")"
  if [[ "$got" != "${expected[$i]}" ]]; then
    echo "[fail] ${names[$i]}: expected ${expected[$i]}, got $got"
    failures=1
  else
    echo "[ok]   ${names[$i]} -> $got"
  fi
done

# --- vacuity control ------------------------------------------------------
# Under the OLD predicate every bare Tooltip counted, so both zero-cases would
# have returned 1. If the table contains no such case it cannot detect the
# regression, and a green run above would mean nothing.
separating=0
for i in "${!names[@]}"; do
  if [[ "${expected[$i]}" == "0" ]] && grep -q 'Tooltip(' <<<"${bodies[$i]}"; then
    separating=$((separating + 1))
  fi
done
if [[ "$separating" -lt 2 ]]; then
  echo "[fail] the table no longer separates the old predicate from the new one"
  echo "       ($separating bare-Tooltip case(s) expected to be uncounted)"
  failures=1
else
  echo "[ok]   $separating case(s) would have been miscounted by the old predicate"
fi

if [[ "$failures" -ne 0 ]]; then
  echo '[fail] tooltip gate resolution tests failed.'
  exit 1
fi

echo '[ok] Tooltip gate resolution tests passed.'
