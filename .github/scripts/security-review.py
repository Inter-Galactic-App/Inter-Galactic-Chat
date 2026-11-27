#!/usr/bin/env python3
"""Repo-local security gates for Inter Galactic release work.

The checks are intentionally high-signal and dependency-free so they can run in
GitHub Actions and from a local checkout without printing secret values.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import zipfile
from dataclasses import dataclass
from pathlib import Path


EXCLUDED_DIRS = {
    ".git",
    ".codex_appdata",
    ".codex_localappdata",
    ".dart_tool",
    ".vodozemac",
    ".vscode",
    "archive",
    "build",
    "coverage",
    "coderabbit",
    "dist",
    "releases",
}

ALLOWED_SECRET_LIKE_FILES = {
    ".env.example",
}

PUBLIC_CONFIG_FILES = {
    "google-services.json",
    "GoogleService-Info.plist",
}

DISALLOWED_EXACT_NAMES = {
    ".env",
    "key.jks",
    "key.properties",
    "firebase_options.dart",
    "bot-storage.json",
}

DISALLOWED_SUFFIXES = {
    ".p8",
    ".p12",
    ".pfx",
}

TEXT_SUFFIXES = {
    ".bat",
    ".cfg",
    ".conf",
    ".dart",
    ".env",
    ".gradle",
    ".html",
    ".iss",
    ".js",
    ".json",
    ".kt",
    ".lock",
    ".plist",
    ".properties",
    ".ps1",
    ".py",
    ".sh",
    ".swift",
    ".toml",
    ".ts",
    ".txt",
    ".xml",
    ".yaml",
    ".yml",
}

SKIP_CONTENT_DIRS = {
    "docs",
    ".github",
}

HIGH_CONFIDENCE_PATTERNS = {
    "private key block": re.compile(rb"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    "matrix access token": re.compile(rb"\bsyt_[A-Za-z0-9._=-]{24,}"),
    "matrix refresh token": re.compile(rb"\bsyr_[A-Za-z0-9._=-]{24,}"),
    "jwt": re.compile(
        rb"\beyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}"
    ),
    "bearer token literal": re.compile(
        rb"(?i)\bAuthorization\s*:\s*Bearer\s+[A-Za-z0-9._=-]{24,}"
    ),
    "literal access token": re.compile(
        rb"(?i)\baccess_token\s*[:=]\s*['\"][A-Za-z0-9._=-]{24,}['\"]"
    ),
    "literal refresh token": re.compile(
        rb"(?i)\brefresh_token\s*[:=]\s*['\"][A-Za-z0-9._=-]{24,}['\"]"
    ),
}


@dataclass
class Finding:
    severity: str
    path: str
    message: str


def relative(path: Path, root: Path) -> str:
    return path.relative_to(root).as_posix()


def should_skip_path(path: Path, root: Path) -> bool:
    rel_parts = path.relative_to(root).parts
    return any(part in EXCLUDED_DIRS for part in rel_parts)


def iter_walk_files(root: Path):
    for current_root, dir_names, file_names in os.walk(root):
        dir_names[:] = [
            name
            for name in dir_names
            if name not in EXCLUDED_DIRS
            and not (Path(current_root) / name).is_symlink()
        ]
        current = Path(current_root)
        for file_name in file_names:
            path = current / file_name
            if path.is_file() and not path.is_symlink():
                yield path


def git_visible_files(root: Path) -> list[Path] | None:
    try:
        result = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-co", "--exclude-standard"],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return None

    files: list[Path] = []
    for line in result.stdout.splitlines():
        path = root / line
        if path.is_file() and not path.is_symlink() and not should_skip_path(path, root):
            files.append(path)
    return files


def iter_repo_files(root: Path, artifact_roots: list[Path] | None = None):
    seen: set[Path] = set()
    git_files = git_visible_files(root)
    source_files = git_files if git_files is not None else list(iter_walk_files(root))

    for path in source_files:
        resolved = path.resolve()
        if resolved not in seen:
            seen.add(resolved)
            yield path

    for artifact_root in artifact_roots or []:
        if not artifact_root.exists():
            continue
        for path in iter_walk_files(artifact_root):
            resolved = path.resolve()
            if resolved not in seen:
                seen.add(resolved)
                yield path


def is_disallowed_secret_path(path: Path) -> str | None:
    name = path.name
    lower_name = name.lower()

    if name in ALLOWED_SECRET_LIKE_FILES:
        return None

    if lower_name in DISALLOWED_EXACT_NAMES:
        return f"disallowed secret-bearing filename `{name}`"

    if lower_name.startswith(".env."):
        return f"disallowed environment filename `{name}`"

    if any(lower_name.endswith(suffix) for suffix in DISALLOWED_SUFFIXES):
        return f"disallowed private signing/key filename `{name}`"

    if re.search(r"service[-_]?account.*\.json$", lower_name):
        return f"disallowed service-account JSON filename `{name}`"

    if lower_name.endswith(".pem") and "public" not in lower_name:
        return f"possible private PEM file `{name}`"

    return None


def scan_paths(root: Path, artifact_roots: list[Path]) -> list[Finding]:
    findings: list[Finding] = []
    for path in iter_repo_files(root, artifact_roots):

        rel = relative(path, root)
        reason = is_disallowed_secret_path(path)
        if reason:
            findings.append(Finding("fail", rel, reason))
        elif path.name in PUBLIC_CONFIG_FILES:
            findings.append(
                Finding(
                    "note",
                    rel,
                    "public platform config found; verify it targets the intended app",
                )
            )

        if path.suffix.lower() == ".zip":
            findings.extend(scan_zip_members(path, root))

    return findings


def scan_zip_members(path: Path, root: Path) -> list[Finding]:
    findings: list[Finding] = []
    try:
        with zipfile.ZipFile(path) as archive:
            for member in archive.namelist():
                member_name = Path(member).name
                if not member_name:
                    continue
                reason = is_disallowed_secret_path(Path(member_name))
                if reason:
                    findings.append(
                        Finding(
                            "fail",
                            relative(path, root),
                            f"zip member `{member}` has {reason}",
                        )
                    )
    except zipfile.BadZipFile:
        findings.append(Finding("note", relative(path, root), "zip file could not be inspected"))
    return findings


def should_scan_content(path: Path, root: Path) -> bool:
    if path.stat().st_size > 2_000_000:
        return False
    rel_parts = path.relative_to(root).parts
    if any(part in SKIP_CONTENT_DIRS for part in rel_parts):
        return False
    return path.suffix.lower() in TEXT_SUFFIXES or path.name in {"pubspec.lock", "pubspec.yaml"}


def scan_content(root: Path, artifact_roots: list[Path]) -> list[Finding]:
    findings: list[Finding] = []
    for path in iter_repo_files(root, artifact_roots):
        if not should_scan_content(path, root):
            continue
        try:
            data = path.read_bytes()
        except OSError as error:
            findings.append(Finding("fail", relative(path, root), f"could not read: {error}"))
            continue
        if b"\0" in data:
            continue
        for label, pattern in HIGH_CONFIDENCE_PATTERNS.items():
            if pattern.search(data):
                findings.append(
                    Finding(
                        "fail",
                        relative(path, root),
                        f"high-confidence secret pattern detected: {label}",
                    )
                )
    return findings


def require_doc_contains(path: Path, needles: list[str]) -> list[Finding]:
    findings: list[Finding] = []
    try:
        content = path.read_text(encoding="utf-8")
    except OSError as error:
        return [Finding("fail", path.as_posix(), f"could not read: {error}")]

    for needle in needles:
        if needle not in content:
            findings.append(
                Finding("fail", path.as_posix(), f"release gate reference missing: `{needle}`")
            )
    return findings


def check_release_gate_docs(root: Path) -> list[Finding]:
    return [
        *require_doc_contains(
            root / "docs" / "release" / "release-checklist.md",
            [
                "security-checklist.md",
                "dependency-review.md",
                "runtime-privacy-review.md",
                "security-review.py",
                "LiveKit/WebRTC",
            ],
        ),
        *require_doc_contains(
            root / "docs" / "release" / "release-artifact-checklist.md",
            [
                "security-review.py",
                "service-account JSON",
                "LiveKit JWT",
                "bot storage",
            ],
        ),
    ]


def check_dependency_inventory(root: Path) -> list[Finding]:
    findings: list[Finding] = []
    required = [
        root / "pubspec.yaml",
        root / "pubspec.lock",
        root / "intergalactic" / "pubspec.yaml",
    ]
    for path in required:
        if not path.exists():
            findings.append(
                Finding(
                    "fail",
                    relative(path, root),
                    "required dependency manifest/lockfile is missing",
                )
            )

    pubspecs = sorted(
        relative(path, root)
        for path in iter_repo_files(root)
        if path.name == "pubspec.yaml"
    )
    if pubspecs:
        findings.append(
            Finding(
                "note",
                "dependency inventory",
                "pubspec files reviewed by path gate: " + ", ".join(pubspecs),
            )
        )
    return findings


def print_findings(findings: list[Finding]) -> int:
    failures = [finding for finding in findings if finding.severity == "fail"]
    notes = [finding for finding in findings if finding.severity != "fail"]

    for finding in notes:
        print(f"[note] {finding.path}: {finding.message}")
    for finding in failures:
        print(f"[fail] {finding.path}: {finding.message}")

    if failures:
        print(f"Security review failed with {len(failures)} finding(s).")
        return 1

    print("Security review passed.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", default=".", help="Repository root to scan")
    parser.add_argument(
        "--artifact-root",
        action="append",
        default=[],
        help="Optional release artifact directory to scan, such as dist",
    )
    args = parser.parse_args()

    root = Path(args.repo_root).resolve()
    if not (root / ".github").exists():
        print(f"Repository root does not look like Inter Galactic app repo: {root}")
        return 1

    artifact_roots = [
        (root / artifact_root).resolve()
        for artifact_root in args.artifact_root
    ]

    findings: list[Finding] = []
    findings.extend(scan_paths(root, artifact_roots))
    findings.extend(scan_content(root, artifact_roots))
    findings.extend(check_release_gate_docs(root))
    findings.extend(check_dependency_inventory(root))
    return print_findings(findings)


if __name__ == "__main__":
    sys.exit(main())
