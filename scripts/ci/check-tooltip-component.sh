#!/usr/bin/env bash
#
# Tooltip component ratchet.
#
# WHY THIS EXISTS. The app ran two tooltip systems for months without anyone
# deciding to: `tiamat.Tooltip` (app surface, directional, OverlayEntry) and
# Flutter's Material `Tooltip` (stock colours, above/below only, OverlayPortal).
# At the fork the house component was 58% of tooltips; by 2026-08-18 it was 9%.
#
# Nothing chose that. `docs/DECISIONS.md` had no tooltip entry, and only two
# commits ever migrated away - one an architectural correction, one a crash
# workaround. The drift happened because **the choice is invisible at the call
# site**: writing `tooltip: "Mute"` on a button silently selected a different
# visual language, a different overlay mechanism and a different crash surface,
# and nothing told the author. It cost BUG-300, BUG-305 and BUG-306.
#
# Converting the sites without changing that would only restart the clock. This
# gate is the part that keeps the repair true. See DECISIONS.md 2026-08-18, D5.
#
# WHAT IT DOES. Counts Material tooltip constructions per file and compares
# against a ratchet allowlist. Counts may fall, never rise, and a file not on
# the list may have none. Existing sites are grandfathered so the gate could
# land before the migration finished; the list shrinks as they convert.
#
# WHAT IT DOES NOT CATCH, and do not let a green result imply otherwise:
#   - `tooltip:` parameters. Those now route through the button atoms to the
#     house component, so they are correct by construction - but a `tooltip:`
#     on a *Flutter* widget rather than one of ours is still Material and is
#     invisible here. Catching that needs type resolution, not grep.
#   - Whether a tooltip is placed sensibly, or announces itself once. Those are
#     widget tests, not a text scan.
#
# Regenerate the allowlist after converting sites:
#   bash scripts/ci/check-tooltip-component.sh --update

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${REPO_ROOT:-$(cd "$script_dir/../.." && pwd)}"
allowlist="$script_dir/tooltip-allowlist.txt"

scan_roots=("intergalactic/lib" "tiamat/lib")

# The house component's own definition and its widgetbook use case both name
# `Tooltip(` legitimately.
exclude_file="tiamat/lib/atoms/tooltip.dart"

# Counting is one `grep -rn` pass over the scan roots, not a loop over files.
# The per-file form took over two minutes on a network-mounted checkout, which
# is long enough that someone would be tempted to drop the gate.
count_sites() {
  cd "$repo_root"

  local roots=()
  local root
  for root in "${scan_roots[@]}"; do
    [[ -d "$root" ]] && roots+=("$root")
  done
  [[ ${#roots[@]} -eq 0 ]] && return 0

  # Aliases the repo actually uses for material.dart, collected in one pass.
  # `material.Tooltip(` and `m.Tooltip(` are Material; `tiamat.Tooltip(` is the
  # house component and must not be counted, so an allow-everything dot pattern
  # would be wrong here.
  local alias_pattern=""
  local alias
  while IFS= read -r alias; do
    [[ -z "$alias" ]] && continue
    alias_pattern="$alias_pattern|(^|[^A-Za-z0-9_.])${alias}\.Tooltip\("
  done < <(grep -rhoE "import 'package:flutter/material\.dart' as [A-Za-z_][A-Za-z0-9_]*" "${roots[@]}" 2>/dev/null              | awk '{print $NF}' | sort -u)

  local pattern="(^|[^A-Za-z0-9_.])Tooltip\(${alias_pattern}"

  grep -rnE "$pattern" --include='*.dart' "${roots[@]}" 2>/dev/null     | awk -F: -v excl="$exclude_file" '
        {
          file = $1
          sub(/^\.\//, "", file)
          if (file == excl) next
          # Drop comment lines: everything after the second colon is content.
          line = $0
          sub(/^[^:]*:[^:]*:/, "", line)
          gsub(/^[ 	]+/, "", line)
          if (line ~ /^(\/\/|\/\*|\*)/) next
          count[file]++
        }
        END { for (f in count) print count[f], f }
      ' | sort -k2
}

current="$(count_sites)"

if [[ "${1:-}" == "--update" ]]; then
  {
    echo "# Material tooltip sites, grandfathered. Counts may fall, never rise."
    echo "# Regenerate: bash scripts/ci/check-tooltip-component.sh --update"
    echo "# See scripts/ci/check-tooltip-component.sh for why this gate exists."
    # Trailing newline matters: `read` does not emit a final line that lacks
    # one, so writing it without would silently drop the last entry from the
    # budget and fail the gate on a clean tree. That happened.
    printf '%s
' "$current"
  } > "$allowlist"
  echo "[ok] Wrote $(printf '%s' "$current" | grep -c . || true) entries to $allowlist"
  exit 0
fi

if [[ ! -f "$allowlist" ]]; then
  echo "[fail] Missing allowlist: $allowlist"
  echo "[fail] Generate it with: bash scripts/ci/check-tooltip-component.sh --update"
  exit 1
fi

declare -A budget=()
while read -r n file || [[ -n "${n:-}" ]]; do
  [[ -z "${n:-}" || "$n" == \#* ]] && continue
  budget["$file"]="$n"
done < "$allowlist"

failed=0
improved=0

while read -r n file || [[ -n "${n:-}" ]]; do
  [[ -z "${n:-}" ]] && continue
  allowed="${budget[$file]:-0}"
  if [[ "$n" -gt "$allowed" ]]; then
    failed=1
    if [[ "$allowed" -eq 0 ]]; then
      echo "[fail] $file introduces $n Material tooltip(s)."
      echo "       Use tiamat.Tooltip instead - app surface, real directional"
      echo "       placement, and off the OverlayPortal path that caused BUG-300."
      echo "       On a button atom, prefer the tooltip: parameter, which already"
      echo "       routes to the house component."
    else
      echo "[fail] $file has $n Material tooltip(s), was allowed $allowed."
      echo "       This gate is a ratchet: counts may fall, never rise."
    fi
  elif [[ "$n" -lt "$allowed" ]]; then
    improved=1
    echo "[notice] $file is down to $n from $allowed - run --update to tighten."
  fi
done <<< "$current"

# A file that converted every site disappears from the scan entirely, so the
# loop above never sees it. Report those too, or the list can only ever be
# tightened for files that still have sites left.
for file in "${!budget[@]}"; do
  if ! printf '%s' "$current" | awk '{print $2}' | grep -qx "$file"; then
    improved=1
    echo "[notice] $file has no Material tooltips left - run --update to drop it."
  fi
done

if [[ "$failed" -ne 0 ]]; then
  echo "[fail] Tooltip component gate failed. See DECISIONS.md 2026-08-18, D5."
  exit 1
fi

total="$(printf '%s' "$current" | awk '{s+=$1} END {print s+0}')"
if [[ "$improved" -ne 0 ]]; then
  echo "[ok] Tooltip gate passed with $total grandfathered site(s); some counts fell."
else
  echo "[ok] Tooltip gate passed with $total grandfathered site(s)."
fi
exit 0
