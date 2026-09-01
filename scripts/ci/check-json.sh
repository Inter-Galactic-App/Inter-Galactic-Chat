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

python3 - "$repo_root" "$matrix_dev_root" <<'PYCHECKJSON'
import json
import pathlib
import subprocess
import sys

repo_root = pathlib.Path(sys.argv[1]).resolve()
matrix_dev_root = pathlib.Path(sys.argv[2]).resolve() if sys.argv[2] else None
failures = []
checked = 0
skipped = []

SKIP_REPO_PARTS = {".vscode", ".dart_tool", "build", "dist", "runtime", "archive"}
SKIP_WORKSPACE_NAMES = {"active-commiter.json"}


def git_json_files(root: pathlib.Path):
    try:
        result = subprocess.run(
            [
                "git",
                "-c",
                f"safe.directory={root}",
                "-C",
                str(root),
                "ls-files",
                "-z",
                "--",
                "*.json",
                "*.jsonl",
            ],
            check=True,
            capture_output=True,
        )
        for raw in result.stdout.split(b"\0"):
            if raw:
                yield root / raw.decode("utf-8")
    except (OSError, subprocess.CalledProcessError):
        for path in root.rglob("*"):
            if path.is_file() and path.suffix.lower() in {".json", ".jsonl"}:
                yield path


def workspace_json_files(root: pathlib.Path):
    agent_control = root / "docs" / "agent-control"
    if not agent_control.exists():
        return []
    return sorted(
        path
        for path in agent_control.glob("*.json*")
        if path.suffix.lower() in {".json", ".jsonl"}
    )


def should_skip_repo_path(path: pathlib.Path, label_root: pathlib.Path) -> bool:
    rel_parts = path.relative_to(label_root).parts
    return any(part in SKIP_REPO_PARTS for part in rel_parts)


def check_json(path: pathlib.Path, label_root: pathlib.Path):
    global checked
    rel = path.relative_to(label_root).as_posix()
    if not path.exists():
        skipped.append(f"{rel}: missing in dirty checkout")
        return
    checked += 1
    try:
        json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        failures.append(f"{rel}: {exc}")


def check_jsonl(path: pathlib.Path, label_root: pathlib.Path):
    global checked
    rel = path.relative_to(label_root).as_posix()
    if not path.exists():
        skipped.append(f"{rel}: missing in dirty checkout")
        return
    checked += 1
    current_line = 0
    try:
        with path.open("r", encoding="utf-8") as handle:
            for current_line, line in enumerate(handle, start=1):
                if line.strip():
                    json.loads(line)
    except Exception as exc:
        failures.append(f"{rel}:{current_line or '?'}: {exc}")


seen = set()
for file_path in git_json_files(repo_root):
    if file_path in seen or should_skip_repo_path(file_path, repo_root):
        continue
    seen.add(file_path)
    if file_path.suffix.lower() == ".jsonl":
        check_jsonl(file_path, repo_root)
    else:
        check_json(file_path, repo_root)

if matrix_dev_root and matrix_dev_root.exists():
    for file_path in workspace_json_files(matrix_dev_root):
        if file_path.name in SKIP_WORKSPACE_NAMES:
            skipped.append(f"{file_path.relative_to(matrix_dev_root).as_posix()}: non-JSON coordination marker")
            continue
        if file_path.suffix.lower() == ".jsonl":
            check_jsonl(file_path, matrix_dev_root)
        else:
            check_json(file_path, matrix_dev_root)
else:
    print("[notice] MATRIX_DEV_ROOT not available; workspace agent-control JSON checks skipped.")

for item in skipped:
    print(f"[notice] Skipped {item}")

if failures:
    for failure in failures:
        print(f"[fail] {failure}")
    print(f"JSON validation failed with {len(failures)} issue(s).")
    sys.exit(1)

print(f"JSON validation passed for {checked} JSON/JSONL file(s).")
PYCHECKJSON
