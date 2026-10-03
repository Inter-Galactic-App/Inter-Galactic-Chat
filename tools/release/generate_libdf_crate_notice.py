#!/usr/bin/env python3
"""Compose the recipient notice for the DeepFilterNet libDF Rust tree.

The libDF source-roster capture is deliberately self-contained: it holds the
selected package/version pairs and exact licence-text files under tracked
evidence.  This generator reads only that capture (plus the separately
captured Rust standard-library texts), so regenerating the app asset cannot
silently depend on a mutable cargo registry or toolchain installation.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def package_directory(texts_root: Path, package: dict) -> Path:
    return texts_root / f"{package['name']}-{package['version']}"


def platform_scope(platforms: list[str]) -> str:
    names = []
    if any(value.startswith("windows-") for value in platforms):
        names.append("Windows")
    if any(value.startswith("android-") for value in platforms):
        names.append("Android")
    return ", ".join(names) or ", ".join(platforms)


def add_text(
    blocks: dict[str, tuple[str, list[str]]], data: bytes, user: str
) -> str:
    key = digest(data)
    if key not in blocks:
        blocks[key] = (data.decode("utf-8"), [])
    blocks[key][1].append(user)
    return key


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--roster", required=True)
    parser.add_argument("--texts-root", required=True)
    parser.add_argument("--std-license-root", required=True)
    parser.add_argument("--std-version", required=True)
    parser.add_argument("--std-commit", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    roster = json.loads(Path(args.roster).read_text(encoding="utf-8"))
    packages = roster.get("packages")
    if not isinstance(packages, list) or not packages:
        raise SystemExit("Roster has no non-empty 'packages' list.")

    texts_root = Path(args.texts_root)
    std_root = Path(args.std_license_root)
    blocks: dict[str, tuple[str, list[str]]] = {}
    index_rows: list[tuple[str, str, str, str, list[str]]] = []
    qualified: list[tuple[str, str, str]] = []

    for package in sorted(packages, key=lambda item: (item["name"], item["version"])):
        directory = package_directory(texts_root, package)
        if not directory.is_dir():
            raise SystemExit(f"Missing captured text directory: {directory}")

        text_ids: list[str] = []
        for evidence in package.get("license_files", []):
            path = directory / evidence["file"]
            if not path.is_file():
                raise SystemExit(f"Missing captured licence file: {path}")
            data = path.read_bytes()
            if len(data) != evidence["bytes"] or digest(data) != evidence["sha256"]:
                raise SystemExit(
                    f"Captured text does not match roster evidence: {path}"
                )
            suffix = ""
            if evidence.get("role") == "canonical_spdx_mit_text_mapped_to_exact_package_declaration":
                suffix = " [qualified SPDX MIT mapping; see LICENSE-SOURCE.md]"
                qualified.append((package["name"], package["version"], str(path)))
            text_ids.append(
                add_text(
                    blocks,
                    data,
                    f"{package['name']} {package['version']} ({evidence['file']}){suffix}",
                )
            )

        if not text_ids:
            raise SystemExit(
                f"No captured licence text is available for {package['name']} {package['version']}"
            )
        index_rows.append(
            (
                package["name"],
                package["version"],
                package["declared_license"],
                platform_scope(package.get("platforms", [])),
                text_ids,
            )
        )

    standard_ids: list[str] = []
    for filename in ("Apache-2.0.txt", "MIT.txt"):
        path = std_root / filename
        if not path.is_file():
            raise SystemExit(f"Missing captured Rust standard-library text: {path}")
        standard_ids.append(
            add_text(blocks, path.read_bytes(), f"Rust standard library ({filename})")
        )

    block_ids = {key: f"T{number:02d}" for number, key in enumerate(blocks, 1)}
    lines: list[str] = []
    write = lines.append
    write("DEEPFILTERNET libDF RUST COMPONENTS LINKED INTO THE APPLICATION")
    write("=" * 79)
    write("")
    write("The DeepFilterNet native C API runtime used by this application is")
    write("implemented in Rust. Windows distributes it as df.dll; Android")
    write("distributes it as libdf.so for arm64-v8a and armeabi-v7a. These are")
    write("native payloads, so automatic package-notice surfaces do not enumerate")
    write("the Rust crates compiled into them. This document is the notice that")
    write("travels with those native payloads and is rendered on the app's open")
    write("source licences screen.")
    write("")
    write("The selected dependency closures contain 95 Windows packages, 105")
    write("Android packages, and 109 unique package/version pairs. Each row names")
    write("the exact captured version, its declared licence expression, delivered")
    write("platform scope, and every captured licence text. Identical text is")
    write("printed once and referenced by block identifier. This deduplicates bytes")
    write("only: it does not elect a licence arm for a multi-licensed package.")
    write("")
    write("The Rust standard library is also linked into these binaries. It was")
    write(f"built with rustc {args.std_version}, commit {args.std_commit}, and its")
    write("Apache-2.0 and MIT texts are included below.")
    write("")
    write("SECTION 1 - COMPONENTS")
    write("=" * 79)
    write("")
    write("COMPONENT  VERSION  DECLARED LICENCE  PLATFORMS  TEXTS")
    write("---------  -------  -----------------  ---------  -----")
    for name, version, declared, platforms, text_ids in index_rows:
        write(
            f"{name}  {version}  {declared}  {platforms}  "
            + ",".join(block_ids[text_id] for text_id in text_ids)
        )
    write(
        "Rust standard library  "
        f"{args.std_version}  Apache-2.0 OR MIT  Windows, Android  "
        + ",".join(block_ids[text_id] for text_id in standard_ids)
    )
    write("")
    if qualified:
        write("QUALIFIED SPDX MIT MAPPINGS")
        write("-" * 79)
        write("")
        write("The following exact crate archives and matching upstream source trees")
        write("declare MIT but contain no licence/notice text file. Their listed MIT")
        write("block is the canonical SPDX MIT text mapped to that exact declaration;")
        write("it is not presented as a file the crate itself shipped.")
        for name, version, _ in qualified:
            write(f"  {name} {version}: see its tracked LICENSE-SOURCE.md receipt.")
        write("")
    write("SECTION 2 - LICENCE TEXTS")
    write("=" * 79)
    for key, (text, users) in blocks.items():
        write("")
        write("-" * 79)
        write(f"{block_ids[key]} - applies to:")
        for user in users:
            write(f"  {user}")
        write("-" * 79)
        write("")
        write(text.rstrip("\n"))
    output = "\n".join(lines) + "\n"
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(output, encoding="utf-8", newline="\n")
    print(f"wrote {out}")
    print(f"  components: {len(index_rows)} + Rust standard library")
    print(f"  distinct licence texts: {len(blocks)}")
    print(f"  bytes: {len(output.encode('utf-8'))}")
    print(f"  sha256: {digest(output.encode('utf-8'))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
