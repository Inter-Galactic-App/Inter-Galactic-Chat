#!/usr/bin/env python3
"""Prepare and verify an isolated, pinned E8 wrapper source tree.

This intentionally never edits the live app checkout or the pub cache. The
Podfile and both Xcode targets invoke verify_ios_patch.py, which imports this
module; preparation remains an explicit step before those build gates.
"""

import argparse
import hashlib
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tomllib


HERE = pathlib.Path(__file__).resolve().parent
APP_REPO = HERE.parents[3]
MANIFEST = HERE / "manifest.json"


def fail(message):
    raise SystemExit(f"E8 preparation failed closed: {message}")


def run(*args, cwd=None, env=None):
    result = subprocess.run(args, cwd=cwd, env=env, text=True, capture_output=True)
    if result.returncode:
        detail = (result.stdout + "\n" + result.stderr).strip()
        fail(f"{' '.join(map(str, args[:3]))} exited {result.returncode}: {detail[-1600:]}")
    return result.stdout.strip()


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def require_equal(actual, expected, label):
    if actual != expected:
        fail(f"{label} mismatch: expected {expected}, got {actual}")


def package_entry(lock_text, package):
    in_packages = False
    current = None
    entries = []
    fields = []
    for line in lock_text.splitlines():
        if not in_packages:
            if line == "packages:":
                in_packages = True
            continue
        if line and not line.startswith(" "):
            break  # End of the packages section (normally `sdks:`).
        header = re.fullmatch(r"  ([A-Za-z0-9_+.-]+):", line)
        if header:
            if current == package:
                entries.append(fields)
            current = header.group(1)
            fields = []
        elif current == package:
            if not line.startswith("    "):
                fail(f"malformed {package} stanza in pubspec.lock")
            fields.append(line)
    if current == package:
        entries.append(fields)
    if len(entries) != 1:
        fail(f"expected exactly one {package} stanza in pubspec.lock")
    return entries[0]


def require_lock_field(entry, package, name, expected):
    # A pubspec lock entry has four-space top-level fields. Reject duplicate
    # keys even when one value is the expected one; YAML consumers may choose
    # a different occurrence from this recipe.
    matches = [line for line in entry
               if line.startswith("    ") and not line.startswith("     ")
               and line[4:].partition(":")[0].strip() == name]
    if matches != [f"    {name}: {expected}"]:
        fail(f"{package} has missing, duplicate, or unexpected {name} in pubspec.lock")


def assert_package_resolution(app, source):
    lock = app / "pubspec.lock"
    config = app / ".dart_tool/package_config.json"
    if not lock.is_file() or not config.is_file():
        fail("resolved pubspec.lock or package_config.json missing")
    lock_text = lock.read_text()
    package_config = json.loads(config.read_text())
    for package, subdir in (("flutter_vodozemac", "flutter"), ("vodozemac", "dart")):
        entry = package_entry(lock_text, package)
        require_lock_field(entry, package, "source", "path")
        require_lock_field(entry, package, "version", '"0.5.0"')
        records = [p for p in package_config["packages"] if p["name"] == package]
        if len(records) != 1:
            fail(f"expected exactly one resolved {package} package")
        from urllib.parse import unquote, urlparse

        uri = records[0]["rootUri"]
        parsed = urlparse(uri)
        actual = pathlib.Path(unquote(parsed.path) if parsed.scheme == "file" else uri)
        if not actual.is_absolute():
            actual = (config.parent / actual).resolve()
        require_equal(actual.resolve(), (source / subdir).resolve(), f"{package} path")
    # The two package roots must share the one checked post-patch parent.
    require_equal((source / "flutter").resolve().parent, (source / "dart").resolve().parent, "package tree")
    return {"pubspec_lock_sha256": sha256(lock), "package_config_sha256": sha256(config)}


def generate_app_sources(app):
    package = app / "intergalactic"
    run("dart", "run", "build_runner", "build", "--delete-conflicting-outputs", cwd=package)
    # The repository's generate-from-arb.sh uses Bash mapfile, unavailable in
    # the macOS system Bash. Invoke the same generator with bounded inputs.
    sources = sorted(
        str(path.relative_to(package))
        for path in (package / "lib").rglob("*.dart")
        if "generated" not in path.relative_to(package / "lib").parts
        and re.search(r"Intl\.(message|plural|select|gender)", path.read_text())
    )
    arbs = sorted(str(path.relative_to(package)) for path in (package / "assets/l10n").glob("*.arb"))
    if not sources or not arbs:
        fail("Intl source or ARB set missing")
    (package / "lib/generated/intl").mkdir(parents=True, exist_ok=True)
    run("dart", "run", "intl_translation:generate_from_arb",
        "--output-dir=lib/generated/intl", "--no-use-deferred-loading",
        *sources, *arbs, cwd=package)
    required = (
        "lib/generated/intl/messages_all.dart",
        "lib/cache/drift_file_cache.g.dart",
        "lib/utils/emoji/unicode_emoji_data_groups.g.dart",
    )
    for relative in required:
        if not (package / relative).is_file():
            fail(f"required generated source missing: {relative}")
    return {relative: sha256(package / relative) for relative in required}


def capture_unsigned_apple_payload(app):
    ios = app / "intergalactic/ios"
    settings = run("xcodebuild", "-showBuildSettings", "-workspace", "Runner.xcworkspace",
                   "-scheme", "Runner", "-configuration", "Release", "-sdk", "iphoneos", cwd=ios)
    build_dirs = set(re.findall(r"(?m)^\s*BUILD_DIR = (.+)$", settings))
    if len(build_dirs) != 1:
        fail("cannot identify one Xcode build directory for CargoKit output")
    build_root = pathlib.Path(build_dirs.pop()).parent
    library = build_root / "Intermediates.noindex/Pods.build/Release-iphoneos/flutter_vodozemac.build/aarch64-apple-ios/release/libvodozemac_bindings_dart.a"
    pod_archive = app / "intergalactic/build/ios/Release-iphoneos/flutter_vodozemac/libvodozemac_bindings_dart.a"
    runner = app / "intergalactic/build/ios/iphoneos/Runner.app"
    extension = runner / "PlugIns/InterGalactic Notification Extension.appex/InterGalactic Notification Extension"
    binaries = {"cargokit_static_library": library, "xcode_pod_archive": pod_archive,
                "notification_extension_macho": extension,
                "notification_extension_info_plist": extension.parent / "Info.plist",
                "runner_macho": runner / "Runner"}
    for label, path in binaries.items():
        if not path.is_file():
            fail(f"unsigned {label} missing after build")
    symbols = ("_ios_decrypt_backup_event_v1", "_ios_backup_event_decrypt_result_free")
    for label in ("cargokit_static_library", "xcode_pod_archive", "notification_extension_macho"):
        exports = run("nm", "-g", str(binaries[label]))
        if any(not re.search(rf"(?m)^\S+\s+T\s+{symbol}$", exports) for symbol in symbols):
            fail(f"unsigned {label} does not export both combined ABI symbols")
    for label in ("xcode_pod_archive", "notification_extension_macho"):
        if "arm64" not in run("lipo", "-info", str(binaries[label])):
            fail(f"{label} is not arm64")
    return {label: {"sha256": sha256(path), "bytes": path.stat().st_size}
            for label, path in binaries.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=pathlib.Path, help="new, empty scratch directory")
    parser.add_argument("--resolve-app", action="store_true", help="clone app to scratch and run flutter pub get")
    parser.add_argument("--build-ios", action="store_true", help="after verified resolution, make an unsigned scratch iOS build")
    args = parser.parse_args()
    if args.build_ios and not args.resolve_app:
        fail("--build-ios requires --resolve-app")
    output = args.output.expanduser().resolve()
    if output == APP_REPO or APP_REPO in output.parents:
        fail("output must be outside the live app checkout")
    if output.exists() and any(output.iterdir()):
        fail("output must be new or empty")
    output.mkdir(parents=True, exist_ok=True)
    if args.build_ios and shutil.disk_usage(output).free < 10 * 1024**3:
        fail("unsigned iOS build requires at least 10 GiB free in scratch filesystem")
    manifest = json.loads(MANIFEST.read_text())
    patch = HERE / manifest["patch_file"]
    require_equal(sha256(patch), manifest["patch_sha256"], "patch bytes")

    source = output / "source"
    run("git", "clone", "--depth", "1", "--branch", "0.5.0", manifest["upstream_url"], str(source))
    require_equal(run("git", "rev-parse", "HEAD", cwd=source), manifest["baseline_commit"], "source commit")
    require_equal(run("git", "rev-parse", "HEAD^{tree}", cwd=source), manifest["baseline_tree"], "base tree")
    require_equal(run("git", "status", "--porcelain", cwd=source), "", "clean base")
    for relative, expected in manifest["baseline_files_sha256"].items():
        require_equal(sha256(source / relative), expected, f"base {relative}")
    run("git", "apply", "--check", str(patch), cwd=source)
    run("git", "apply", str(patch), cwd=source)
    run("git", "add", "--", *manifest["changed_files"], cwd=source)
    changed = run("git", "diff", "--cached", "--name-only", cwd=source).splitlines()
    require_equal(changed, sorted(manifest["changed_files"]), "changed-file set")
    run("git", "diff", "--cached", "--check", cwd=source)
    require_equal(run("git", "write-tree", cwd=source), manifest["patched_tree"], "post-patch tree")
    for relative, expected in manifest["patched_files_sha256"].items():
        require_equal(sha256(source / relative), expected, f"patched {relative}")
    cargo = tomllib.loads((source / "rust/Cargo.lock").read_text())
    for name, version in manifest["cargo_versions"].items():
        matches = [p for p in cargo["package"] if p["name"] == name]
        if (len(matches) != 1 or matches[0]["version"] != version
                or matches[0].get("checksum") != manifest["cargo_checksums"][name]):
            fail(f"Cargo resolution differs for {name}")
    root = next(p for p in cargo["package"] if p["name"] == "vodozemac_bindings_dart")
    if "serde_json" not in root["dependencies"]:
        fail("serde_json direct edge missing")

    override = output / "pubspec_overrides.yaml"
    override.write_text(
        "dependency_overrides:\n"
        f"  flutter_vodozemac:\n    path: {json.dumps(str(source / 'flutter'))}\n"
        f"  vodozemac:\n    path: {json.dumps(str(source / 'dart'))}\n"
    )
    evidence = {
        "baseline_commit": manifest["baseline_commit"],
        "baseline_tree": manifest["baseline_tree"],
        "patched_tree": manifest["patched_tree"],
        "patch_sha256": sha256(patch),
        "generated_override_sha256": sha256(override),
        "cargo_lock_sha256": sha256(source / "rust/Cargo.lock"),
        "rustc": run("rustc", "--version"),
        "cargo": run("cargo", "--version"),
        "app_resolution": "not run",
        "apple_payload": "not built; no candidate",
    }
    if args.resolve_app:
        app = output / "app"
        run("git", "clone", "--local", "--no-hardlinks", "--no-checkout", str(APP_REPO), str(app))
        app_commit = run("git", "rev-parse", "HEAD", cwd=APP_REPO)
        run("git", "checkout", "--detach", app_commit, cwd=app)
        if (app / "pubspec_overrides.yaml").exists():
            fail("scratch app already carries an override")
        shutil.copy2(override, app / "pubspec_overrides.yaml")
        run("flutter", "pub", "get", cwd=app)
        evidence["app_commit"] = app_commit
        evidence["flutter"] = run("flutter", "--version").splitlines()[0]
        evidence["xcode"] = run("xcodebuild", "-version").splitlines()
        evidence["app_resolution"] = assert_package_resolution(app, source)
        evidence["app_package_paths"] = {
            "flutter_vodozemac": str((source / "flutter").resolve()),
            "vodozemac": str((source / "dart").resolve()),
        }
        if args.build_ios:
            # This is the only build path in this recipe. It cannot reach pods
            # unless both resolved packages are verified against the patch.
            assert_package_resolution(app, source)
            evidence["generated_app_sources_sha256"] = generate_app_sources(app)
            assert_package_resolution(app, source)
            ios_env = os.environ.copy()
            ios_env.update({"IG_E8_PYTHON": sys.executable,
                            "IG_E8_SOURCE": str(source.resolve()),
                            "IG_E8_APP_COMMIT": app_commit})
            run(sys.executable, str(app / "intergalactic/ios/patches/dart-vodozemac/verify_ios_patch.py"),
                cwd=app, env=ios_env)
            run("flutter", "build", "ios", "--release", "--no-codesign", "--no-pub",
                cwd=app / "intergalactic", env=ios_env)
            assert_package_resolution(app, source)
            evidence["apple_payload"] = capture_unsigned_apple_payload(app)
            evidence["apple_payload_status"] = "unsigned scratch build only; no signed candidate"
    (output / "evidence.json").write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n")
    print(f"Prepared verified E8 source: {source}")
    print(f"Evidence: {output / 'evidence.json'}")


if __name__ == "__main__":
    main()
