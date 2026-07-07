#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${REPO_ROOT:-$(cd "$script_dir/../.." && pwd)}"

matrix_dev_root="${MATRIX_DEV_ROOT:-}"
if [[ -z "$matrix_dev_root" ]]; then
  candidate="$(cd "$repo_root/../.." 2>/dev/null && pwd || true)"
  if [[ -n "$candidate" && -f "$candidate/AGENTS.md" && -d "$candidate/docs/agent-control" ]]; then
    matrix_dev_root="$candidate"
  fi
fi

if [[ -z "$matrix_dev_root" || ! -d "$matrix_dev_root/docs/agent-control" ]]; then
  echo "[notice] Matrix_Dev agent-control docs are not present in this checkout; skipping workspace agent-doc checks."
  echo "[notice] For local scheduled checks, set MATRIX_DEV_ROOT=/srv/Matrix_Dev."
  exit 0
fi

required_files=(
  "AGENTS.md"
  "docs/agent-control/active-work.json"
  "docs/agent-control/active-work.md"
  "docs/agent-control/ownership-map.json"
  "docs/agent-control/ownership-map.md"
  "docs/agent-control/integration-queue.json"
  "docs/agent-control/integration-queue.md"
  "docs/agent-control/conflict-log.json"
  "docs/agent-control/conflict-log.md"
  "docs/agent-control/directory.md"
  "docs/agent-control/workspace-layout-guide.md"
  "docs/agent-control/architecture_documentation.md"
  "docs/agent-control/cleanup.md"
)

missing=0
for rel in "${required_files[@]}"; do
  if [[ ! -f "$matrix_dev_root/$rel" ]]; then
    echo "[fail] Missing required agent-control file: $rel"
    missing=1
  fi
done
if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

MATRIX_DEV_ROOT="$matrix_dev_root" "$repo_root/scripts/ci/check-json.sh"

python3 - "$matrix_dev_root" <<'PYCHECKAGENT'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1]).resolve()
scan_paths = [root / "AGENTS.md"]
scan_paths.extend((root / "docs" / "agent-control").glob("*.md"))
scan_paths.extend((root / "docs" / "agent-control").glob("*.json"))
scan_paths.extend((root / "docs" / "agent-control").glob("*.jsonl"))

failures = []
for path in sorted(scan_paths):
    if not path.is_file():
        continue
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if line.startswith("<<<<<<< ") or line.startswith(">>>>>>> ") or line == "=======":
            failures.append(f"{path.relative_to(root).as_posix()}:{line_number}: merge conflict marker")

ownership = json.loads((root / "docs" / "agent-control" / "ownership-map.json").read_text(encoding="utf-8"))
ci_sections = [section for section in ownership.get("sections", []) if section.get("title") == "CI / Developer Infrastructure"]
if not ci_sections:
    failures.append("docs/agent-control/ownership-map.json: missing CI / Developer Infrastructure section")
else:
    files = set(ci_sections[0].get("files", []))
    for expected in [
        "intergalactic-app/inter-galactic/.github/workflows/minipc-ci.yml",
        "intergalactic-app/inter-galactic/scripts/ci/",
    ]:
        if expected not in files:
            failures.append(f"docs/agent-control/ownership-map.json: CI ownership missing {expected}")

if failures:
    for failure in failures:
        print(f"[fail] {failure}")
    sys.exit(1)

print("Agent-control docs passed required-file, JSON, ownership, and conflict-marker checks.")
PYCHECKAGENT

renderer="$matrix_dev_root/tools/agent-docs/sync-agent-coordination-docs-macos.sh"
if [[ -x "$renderer" ]]; then
  "$renderer" --workspace-root "$matrix_dev_root" --target active-work --check
else
  echo "[notice] Active-work drift check skipped; native renderer not found at $renderer."
fi
