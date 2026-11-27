#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="${REPO_ROOT:-$(cd "$script_dir/../.." && pwd)}"
cd "$repo_root"

required_files=(
  "SECURITY.md"
  "docs/policies/SECURITY_RELEASE_CHECKLIST.md"
  "docs/policies/PRIVACY_POLICY.md"
  "docs/policies/LOG_REDACTION_POLICY.md"
  "docs/policies/URL_PREVIEW_PRIVACY_REVIEW.md"
  "docs/policies/PUSH_PRIVACY_REVIEW.md"
  "docs/policies/policy.config.json"
)

missing=0
for rel in "${required_files[@]}"; do
  if [[ ! -f "$rel" ]]; then
    echo "[fail] Missing required security/privacy doc: $rel"
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
    echo "[fail] $file is missing required security/privacy reference: $needle"
    return 1
  fi
}

fail=0
require_contains "SECURITY.md" "Please report security issues privately" || fail=1
require_contains "SECURITY.md" "Matrix access tokens" || fail=1
require_contains "docs/policies/SECURITY_RELEASE_CHECKLIST.md" "No secrets" || fail=1
require_contains "docs/policies/SECURITY_RELEASE_CHECKLIST.md" "Log redaction" || fail=1
require_contains "docs/policies/PRIVACY_POLICY.md" "RNNoise WAV/audio diagnostics remain local-only" || fail=1
require_contains "docs/policies/LOG_REDACTION_POLICY.md" "Matrix access tokens" || fail=1
require_contains "docs/policies/LOG_REDACTION_POLICY.md" "push tokens" || fail=1

python3 - "$repo_root" <<'PYCHECKSECURITY'
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1]).resolve()
failures = []

try:
    json.loads((root / "docs" / "policies" / "policy.config.json").read_text(encoding="utf-8"))
except Exception as exc:
    failures.append(f"docs/policies/policy.config.json: {exc}")

scan_roots = [root / "SECURITY.md", root / "docs" / "policies"]
scan_roots.extend(root / rel for rel in ["docs/release/README.md", "docs/release/release-checklist.md", "docs/release/release-artifact-checklist.md", "docs/release/versioning-policy.md", "docs/release/rollback-plan.md", "docs/release/test-matrix.md"])
patterns = {
    "workspace path Z": re.compile(r"Z:\\Matrix_Dev"),
    "workspace path srv": re.compile(r"/srv/Matrix_Dev"),
    "personal Windows profile path": re.compile(r"C:\\Users\\[^\\\s]+"),
    "private key block": re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    "Matrix access token": re.compile(r"\bsyt_[A-Za-z0-9._=-]{24,}"),
    "Matrix refresh token": re.compile(r"\bsyr_[A-Za-z0-9._=-]{24,}"),
    "bearer token literal": re.compile(r"(?i)\bAuthorization\s*:\s*Bearer\s+[A-Za-z0-9._=-]{24,}"),
    "literal access token": re.compile(r"(?i)\baccess_token\s*[:=]\s*['\"][A-Za-z0-9._=-]{24,}['\"]"),
}

paths = []
for item in scan_roots:
    if item.is_file():
        paths.append(item)
    elif item.is_dir():
        paths.extend(path for path in item.rglob("*") if path.is_file() and path.suffix.lower() in {".md", ".json", ".txt"})

for path in sorted(set(paths)):
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue
    for line_number, line in enumerate(text.splitlines(), start=1):
        if line.startswith("<<<<<<< ") or line.startswith(">>>>>>> ") or line == "=======":
            failures.append(f"{path.relative_to(root).as_posix()}:{line_number}: merge conflict marker")
        for label, pattern in patterns.items():
            if pattern.search(line):
                failures.append(f"{path.relative_to(root).as_posix()}:{line_number}: {label}")

if failures:
    for failure in failures:
        print(f"[fail] {failure}")
    sys.exit(1)

print("Security docs passed required-file, policy JSON, reference, conflict-marker, and sensitive-literal checks.")
PYCHECKSECURITY

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi
