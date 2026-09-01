#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "$ROOT_DIR"

scan_paths=(
  "CHANGE_LOG.md"
  "docs/"
)

declare -a files_to_check=()
declare -a changed_files=()

collect_changed_files() {
  local base_ref="$1"
  local head_ref="$2"

  if ! git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
    echo "Base ref not available: $base_ref" >&2
    return 1
  fi
  if ! git rev-parse --verify "$head_ref" >/dev/null 2>&1; then
    echo "Head ref not available: $head_ref" >&2
    return 1
  fi

  while IFS= read -r path; do
    changed_files+=("$path")
  done < <(git diff --name-only --diff-filter=ACMRT "$base_ref...$head_ref")
}

if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" ]]; then
  base_ref="${GITHUB_BASE_SHA:-}"
  head_ref="${GITHUB_HEAD_SHA:-}"

  if [[ -n "$base_ref" && -n "$head_ref" ]]; then
    collect_changed_files "$base_ref" "$head_ref" || true
  fi

  if [[ ${#changed_files[@]} -eq 0 ]] && [[ -n "${GITHUB_BASE_REF:-}" && -n "${GITHUB_HEAD_REF:-}" ]]; then
    base_ref="origin/${GITHUB_BASE_REF}"
    head_ref="origin/${GITHUB_HEAD_REF}"
    collect_changed_files "$base_ref" "$head_ref" || true
  fi
elif [[ "${GITHUB_EVENT_NAME:-}" == "push" ]]; then
  # Push events may include many single-file edits; fall back to latest commit
  # change set. If that commit base is unavailable, we will run a full docs pass.
  collect_changed_files "HEAD~1" "HEAD" || true
fi

if [[ ${#changed_files[@]} -gt 0 ]]; then
  for path in "${changed_files[@]}"; do
    files_to_check+=("$path")
  done
fi

candidate_paths=()
for candidate in "${files_to_check[@]}"; do
  for base in "${scan_paths[@]}"; do
    if [[ "$candidate" == "$base"* ]]; then
      candidate_paths+=("$candidate")
      break
    fi
  done
done

if [[ ${#candidate_paths[@]} -eq 0 ]]; then
  for base in "${scan_paths[@]}"; do
    if [[ -e "$base" ]]; then
      candidate_paths+=("$base")
    fi
  done
fi

pattern_file="$(mktemp)"
trap 'rm -f "$pattern_file"' EXIT
cat > "$pattern_file" <<'EOF'
(sk|pk)_(live|publishable|secret)_[A-Za-z0-9]{20,}
(sk|pk)_[A-Za-z0-9]{36,}
AKIA[0-9A-Z]{16}
AIza[0-9A-Za-z\-_]{35}
xox[baprs]-[0-9A-Za-z-]{10,}
gh[pousr]_[A-Za-z0-9]{36,}
BEGIN (RSA|EC|DSA|OPENSSH|ENCRYPTED) PRIVATE KEY
eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+
https?://[^ \t\n:]+:[^ \t\n@]+@
\b(secret|api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret)\b\s*[:=]\s*["']?[A-Za-z0-9_./+=-]{24,}
EOF

findings=0
for file in "${candidate_paths[@]}"; do
  [[ -f "$file" ]] || continue

  while IFS= read -r match; do
    if [[ -n "$match" ]]; then
      ((findings += 1))
      line_no="${match%%:*}"
      echo "[Potential secret found] ${file}:${line_no}"
    fi
  done < <(grep -n -E -i -f "$pattern_file" "$file" || true)
done

if [[ $findings -gt 0 ]]; then
  echo ""
  echo "Docs secret scan found ${findings} suspicious matches. Investigate these matches and rerun after redaction."
  exit 1
fi

echo "Docs secret scan passed: no suspicious secrets found in changelog/docs candidates."
