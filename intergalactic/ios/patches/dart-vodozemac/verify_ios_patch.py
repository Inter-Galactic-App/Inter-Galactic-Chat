#!/usr/bin/env python3
"""Fail-closed product iOS gate for the pinned E8 source plus patch.

Called by Podfile and both Apple targets. It never resolves dependencies or
silently repairs a hosted lock; the isolated preparation recipe must do that.
"""

import json
import os
import pathlib
import tomllib

from prepare import APP_REPO, HERE, MANIFEST, assert_package_resolution, fail, require_equal, run, sha256


def expected_override(source):
    return (
        "dependency_overrides:\n"
        f"  flutter_vodozemac:\n    path: {json.dumps(str(source / 'flutter'))}\n"
        f"  vodozemac:\n    path: {json.dumps(str(source / 'dart'))}\n"
    )


def assert_override(app, source):
    override = app / "pubspec_overrides.yaml"
    if not override.is_file() or override.read_text() != expected_override(source):
        fail("iOS override missing or differs from verified patched tree")


def verify_ios_integration(app, source, expected_app_commit):
    app = pathlib.Path(app).resolve()
    source = pathlib.Path(source).resolve()
    require_equal(app, APP_REPO, "iOS app checkout")
    if not source.is_dir() or source == app or app in source.parents:
        fail("patched source must be a separate directory")
    if len(expected_app_commit) != 40:
        fail("full expected app commit is required")
    require_equal(run("git", "rev-parse", "HEAD", cwd=app), expected_app_commit, "app commit")

    manifest = json.loads(MANIFEST.read_text())
    patch = HERE / manifest["patch_file"]
    require_equal(sha256(patch), manifest["patch_sha256"], "patch bytes")
    require_equal(run("git", "rev-parse", "HEAD", cwd=source), manifest["baseline_commit"], "source commit")
    require_equal(run("git", "rev-parse", "HEAD^{tree}", cwd=source), manifest["baseline_tree"], "base tree")
    require_equal(run("git", "diff", "--name-only", cwd=source), "", "unstaged source changes")
    require_equal(run("git", "ls-files", "--others", "--exclude-standard", cwd=source), "", "untracked source files")
    require_equal(run("git", "diff", "--cached", "--name-only", cwd=source).splitlines(),
                  sorted(manifest["changed_files"]), "changed-file set")
    run("git", "diff", "--cached", "--check", cwd=source)
    require_equal(run("git", "write-tree", cwd=source), manifest["patched_tree"], "post-patch tree")
    for relative, digest in manifest["baseline_files_sha256"].items():
        if relative not in manifest["changed_files"]:
            require_equal(sha256(source / relative), digest, f"base {relative}")
    for relative, digest in manifest["patched_files_sha256"].items():
        require_equal(sha256(source / relative), digest, f"patched {relative}")
    cargo = tomllib.loads((source / "rust/Cargo.lock").read_text())
    for name, version in manifest["cargo_versions"].items():
        matches = [entry for entry in cargo["package"] if entry["name"] == name]
        if (len(matches) != 1 or matches[0]["version"] != version
                or matches[0].get("checksum") != manifest["cargo_checksums"][name]):
            fail(f"Cargo resolution differs for {name}")
    root = [entry for entry in cargo["package"] if entry["name"] == "vodozemac_bindings_dart"]
    if len(root) != 1 or "serde_json" not in root[0]["dependencies"]:
        fail("serde_json direct edge missing")

    assert_override(app, source)
    resolution = assert_package_resolution(app, source)
    if os.environ.get("IG_E8_REQUIRE_POD_LINK") == "1":
        pod_link = app / "intergalactic/ios/.symlinks/plugins/flutter_vodozemac"
        if not pod_link.is_symlink() or pod_link.resolve() != (source / "flutter").resolve():
            fail("CocoaPods flutter_vodozemac link differs from patched source")
    return resolution


def main():
    source = os.environ.get("IG_E8_SOURCE")
    expected_app_commit = os.environ.get("IG_E8_APP_COMMIT")
    if not source or not pathlib.Path(source).is_absolute() or not expected_app_commit:
        fail("IG_E8_SOURCE absolute path and IG_E8_APP_COMMIT are required")
    verify_ios_integration(APP_REPO, source, expected_app_commit)
    print("E8 iOS patched-source gate passed")


if __name__ == "__main__":
    main()
