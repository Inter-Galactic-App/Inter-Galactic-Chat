#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${REPO_ROOT:-$(cd "$script_dir/../.." && pwd)}"
cd "$repo_root"

required_files=(
  "PUBLIC_CHANGELOG.md"
  "docs/release/README.md"
  "docs/release/release-checklist.md"
  "docs/release/release-artifact-checklist.md"
  "docs/release/versioning-policy.md"
  "docs/release/rollback-plan.md"
  "docs/release/test-matrix.md"
  "docs/release/THIRD_PARTY_LICENSES.json"
  "docs/release/THIRD_PARTY_NOTICES.md"
)

missing=0
for rel in "${required_files[@]}"; do
  if [[ ! -f "$rel" ]]; then
    echo "[fail] Missing required release doc: $rel"
    missing=1
  fi
done
if [[ "$missing" -ne 0 ]]; then
  exit 1
fi

require_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq "$needle" "$file"; then
    echo "[fail] $file is missing required release reference: $needle"
    return 1
  fi
}

fail=0
require_contains "docs/release/release-checklist.md" "security-checklist.md" || fail=1
require_contains "docs/release/release-checklist.md" "dependency-review.md" || fail=1
require_contains "docs/release/release-checklist.md" "runtime-privacy-review.md" || fail=1
require_contains "docs/release/release-checklist.md" "security-review.py" || fail=1
require_contains "docs/release/release-artifact-checklist.md" "service-account JSON" || fail=1
require_contains "docs/release/release-artifact-checklist.md" "LiveKit JWT" || fail=1
require_contains "docs/release/release-artifact-checklist.md" "bot storage" || fail=1
require_contains "docs/release/versioning-policy.md" "version: X.Y.Z+build" || fail=1
require_contains "docs/release/versioning-policy.md" "release-record-vX.Y.Z.md" || fail=1

python3 - "$repo_root" <<'PYCHECKRELEASE'
import json
import os
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1]).resolve()
failures = []

try:
    json.loads((root / "docs" / "release" / "THIRD_PARTY_LICENSES.json").read_text(encoding="utf-8"))
except Exception as exc:
    failures.append(f"docs/release/THIRD_PARTY_LICENSES.json: {exc}")

pubspec = root / "intergalactic" / "pubspec.yaml"
version_match = re.search(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$", pubspec.read_text(encoding="utf-8"), re.MULTILINE)
if not version_match:
    failures.append("intergalactic/pubspec.yaml: version must use X.Y.Z+build")
else:
    semantic_version = version_match.group(1)
    release_record = root / "docs" / "release" / f"release-record-v{semantic_version}.md"
    if not release_record.exists():
        message = f"No current semantic release record found at {release_record.relative_to(root).as_posix()}."
        if "MINIPC_RELEASE_STRICT" in os.environ:
            failures.append(message)
        else:
            print(f"[notice] {message}")

for path in [root / rel for rel in [
    "PUBLIC_CHANGELOG.md",
    "docs/release/README.md",
    "docs/release/release-checklist.md",
    "docs/release/release-artifact-checklist.md",
    "docs/release/versioning-policy.md",
    "docs/release/rollback-plan.md",
    "docs/release/test-matrix.md",
]]:
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if line.startswith("<<<<<<< ") or line.startswith(">>>>>>> ") or line == "=======":
            failures.append(f"{path.relative_to(root).as_posix()}:{line_number}: merge conflict marker")

if failures:
    for failure in failures:
        print(f"[fail] {failure}")
    sys.exit(1)

print("Release docs passed required-file, reference, JSON, version-shape, and conflict-marker checks.")
PYCHECKRELEASE

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
