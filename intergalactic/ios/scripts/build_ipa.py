#!/usr/bin/env python3
"""Prepare a pinned iOS build in isolation and retain its correspondence receipt."""

import argparse
import base64
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import zipfile
from types import MappingProxyType
from urllib.parse import urlparse
from xml.parsers.expat import ExpatError

REPO = Path(__file__).resolve().parents[3]
RECIPE = Path("intergalactic/ios/patches/dart-vodozemac")
OPTIONS = {
    "ENABLE_GOOGLE_SERVICES": "enable_google_services",
    "ENABLE_NATIVE_DETACHED_CALL_WINDOWS": "enable_native_detached_call_windows",
    "GIF_API_BASE_URL": "gif_api_base_url",
    "INTERGALACTIC_URL_PREVIEW_ENDPOINT": "intergalactic_url_preview_endpoint",
    "INTERGALACTIC_URL_PREVIEW_ALLOWED_HOMESERVERS": "intergalactic_url_preview_allowed_homeservers",
    "UPDATE_MANIFEST_URL": "update_manifest_url",
    "SPOTIFY_CLIENT_ID": "spotify_client_id",
    "SPOTIFY_REDIRECT_URI": "spotify_redirect_uri",
    "STEAM_ACTIVITY_API_BASE_URL": "steam_activity_api_base_url",
}
TOOL_KEYS = {"flutter_version", "flutter_revision", "dart_version", "xcode",
             "rustc", "cargo", "cocoapods"}
EXPORTS = ("_ios_decrypt_backup_event_v1", "_ios_backup_event_decrypt_result_free")
FLUTTER_DEFINES = {"FLUTTER_VERSION", "FLUTTER_CHANNEL", "FLUTTER_GIT_URL",
                   "FLUTTER_FRAMEWORK_REVISION", "FLUTTER_ENGINE_REVISION",
                   "FLUTTER_DART_VERSION", "FLUTTER_ENABLED_FEATURE_FLAGS"}
ROOT_OVERRIDES = {"OBJROOT", "SYMROOT", "BUILD_DIR", "CONFIGURATION_BUILD_DIR",
                  "BUILT_PRODUCTS_DIR", "PROJECT_TEMP_DIR", "TARGET_TEMP_DIR",
                  "TARGET_BUILD_DIR", "DSTROOT", "DERIVED_DATA_DIR", "SRCROOT",
                  "SOURCE_ROOT", "PROJECT_DIR", "PROJECT_FILE_PATH",
                  "CONFIGURATION_TEMP_DIR", "PODS_CONFIGURATION_BUILD_DIR"}


def fail(message):
    raise ValueError(message)


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            fail(f"duplicate JSON field: {key}")
        result[key] = value
    return result


def load_config(path):
    config = json.loads(Path(path).read_text(), object_pairs_hook=unique_object)
    if set(config) != {"schema", "toolchain", "defines"} or config["schema"] != 1:
        fail("config requires schema 1, toolchain and defines only")
    if set(config["toolchain"]) != TOOL_KEYS or set(config["defines"]) != set(OPTIONS):
        fail("config must explicitly state every toolchain pin and supported define")
    for value in config["toolchain"].values():
        if not isinstance(value, str) or not value.strip():
            fail("toolchain pins must be nonempty strings")
    for key, value in config["defines"].items():
        if not isinstance(value, str) or any(ord(c) < 32 for c in value):
            fail(f"invalid public define: {key}")
        if key.startswith("ENABLE_") and value not in ("true", "false"):
            fail(f"{key} must be true or false")
    if config["defines"]["ENABLE_GOOGLE_SERVICES"] != "false":
        fail("iOS does not enable Android Google Services")
    if not re.fullmatch(r"[0-9a-f]{40}", config["toolchain"]["flutter_revision"]):
        fail("Flutter revision must be a full commit")
    for key in ("GIF_API_BASE_URL", "INTERGALACTIC_URL_PREVIEW_ENDPOINT",
                "UPDATE_MANIFEST_URL", "STEAM_ACTIVITY_API_BASE_URL"):
        value = config["defines"][key]
        parsed = urlparse(value)
        if value and (parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment):
            fail(f"{key} must be a public HTTPS URL without credentials or query parameters")
    if (config["defines"]["INTERGALACTIC_URL_PREVIEW_ALLOWED_HOMESERVERS"]
            and not config["defines"]["INTERGALACTIC_URL_PREVIEW_ENDPOINT"]):
        fail("URL preview allowlist requires an endpoint")
    return config


def command(args, cwd=None, env=None):
    result = subprocess.run([str(a) for a in args], cwd=cwd, env=env,
                            text=True, capture_output=True)
    if result.returncode:
        # Build tools may echo local credentials: retain no raw subprocess log.
        fail(f"{Path(str(args[0])).name} failed with exit {result.returncode}; rerun locally for diagnostics")
    return result.stdout.strip()


def source_identity(repo, commit):
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        fail("--commit requires the full app SHA")
    if command(["git", "rev-parse", "HEAD"], cwd=repo) != commit:
        fail("selected commit must equal this script checkout's HEAD")
    if command(["git", "status", "--porcelain", "--untracked-files=normal"], cwd=repo):
        fail("app checkout must be clean, including untracked source")
    version = re.findall(r"^version: (\d+\.\d+\.\d+\+\d+)\s*$",
                         (repo / "intergalactic/pubspec.yaml").read_text(), re.M)
    if len(version) != 1:
        fail("one complete pubspec version is required")
    return version[0]


def build_environment(source, commit, flutter, defines, inherited=None):
    env = dict(os.environ if inherited is None else inherited)
    reject_root_overrides(env)
    # Explicit configuration owns all flags consumed by build_release.dart.
    for key in (*OPTIONS, "KLIPY_API_KEY", "ALLOW_DIRECT_KLIPY_API_KEY",
                "DISABLE_MANAGED_GIF_RELAY", "INTERGALACTIC_BUILD_RELEASE_NO_PUB",
                "DART_DEFINES", "IOS_NOTIFICATION_DEBUG_HARNESS_SWIFT_FLAG",
                "IG_E8_REQUIRE_POD_LINK", "FLUTTER_BUILD_NAME", "FLUTTER_BUILD_NUMBER"):
        env.pop(key, None)
    for key in ("RUSTFLAGS", "CARGO_ENCODED_RUSTFLAGS", "XCODE_XCCONFIG_FILE",
                "CFLAGS", "CXXFLAGS", "LDFLAGS", "SDKROOT"):
        if env.get(key):
            fail(f"unrecorded build override in environment: {key}")
    env.update(defines)
    env.update(IG_E8_PYTHON=sys.executable, IG_E8_SOURCE=str(source),
               IG_E8_APP_COMMIT=commit, FLUTTER_EXE=flutter, CARGO_BUILD_JOBS="2")
    env["PATH"] = str(Path(flutter).parent) + os.pathsep + env.get("PATH", os.defpath)
    return env


def reject_root_overrides(env):
    if any(key.startswith("FLUTTER_XCODE_") or key in ROOT_OVERRIDES for key in env):
        fail("unrecorded Xcode/root override in environment")


def canonical_path(path):
    path = Path(path)
    if not path.is_absolute() or path.resolve() != path:
        fail("relative or redirected Xcode path")
    return path


def default_derived_data_dir():
    return (Path.home() / "Library/Developer/Xcode/DerivedData").resolve()


@dataclass(frozen=True)
class XcodeBinding:
    """Only app/kind inputs; callers cannot supply roots or mutate product env."""
    app: Path
    kind: str
    env: object

    def __post_init__(self):
        if self.kind not in ("ipa", "development-app"):
            fail("unknown Xcode invocation kind")
        object.__setattr__(self, "app", canonical_path(self.app))
        env = dict(self.env)
        reject_root_overrides(env)
        env.update({f"FLUTTER_XCODE_{key}": str(value) for key, value in self.roots.items()})
        object.__setattr__(self, "env", MappingProxyType(env))

    @property
    def configuration(self):
        return "Release" if self.kind == "ipa" else "Profile"

    @property
    def roots(self):
        root = self.app / f"intergalactic/build/ios/ig-root-contract/{self.configuration}"
        return MappingProxyType({"OBJROOT": canonical_path(root / "intermediates"),
                                 "SYMROOT": canonical_path(root / "products")})

    @property
    def assignments(self):
        settings = {f"FLUTTER_XCODE_{key}": str(value) for key, value in self.roots.items()}
        actual = {key: value for key, value in self.env.items() if key.startswith("FLUTTER_XCODE_")}
        if actual != settings or any(key in self.env for key in ROOT_OVERRIDES):
            fail("product/query Xcode binding changed")
        return tuple(f"{key}={value}" for key, value in self.roots.items())


def build_command(kind, app, commit, version, config, flutter, dart, export_method):
    if kind == "ipa":
        args = [dart, "run", "scripts/build_release.dart", "--platform", "ios",
                "--version_tag", f"v{version}", "--git_hash", commit,
                "--ios_export_method", export_method, "--skip_flutter_pub"]
        for key, option in OPTIONS.items():
            args.extend([f"--{option}", config["defines"][key]])
        if not config["defines"]["GIF_API_BASE_URL"]:
            args.append("--disable_managed_gif_relay")
        return args
    name, number = version.split("+")
    return [flutter, "build", "ios", "--profile", "--no-pub",
            f"--build-name={name}", f"--build-number={number}",
            "--dart-define=BUILD_MODE=release", "--dart-define=PLATFORM=ios",
            f"--dart-define=GIT_HASH={commit}", f"--dart-define=VERSION_TAG=v{version}",
            *[f"--dart-define={key}={value}" for key, value in config["defines"].items()
              if value or key == "GIF_API_BASE_URL"]]


def check_toolchain(config):
    flutter = shutil.which("flutter")
    if not flutter:
        fail("Flutter is missing")
    flutter = str(Path(flutter).resolve())
    dart = str(Path(flutter).parent / "dart")
    machine = json.loads(command([flutter, "--version", "--machine"]))
    actual = {
        "flutter_version": machine["frameworkVersion"],
        "flutter_revision": machine["frameworkRevision"],
        "dart_version": machine["dartSdkVersion"],
        "xcode": command(["xcodebuild", "-version"]),
        "rustc": command(["rustc", "--version"]),
        "cargo": command(["cargo", "--version"]),
        "cocoapods": command(["pod", "--version"]),
    }
    if actual != config["toolchain"]:
        fail("installed toolchain differs from the supplied configuration")
    if actual["flutter_version"] != (REPO / ".flutter-version").read_text().strip():
        fail("Flutter version differs from the repository pin")
    return flutter, dart, actual


def archive_git(repo, ref, output):
    with output.open("wb") as stream:
        result = subprocess.run(["git", "archive", "--format=tar", ref], cwd=repo,
                                stdout=stream, stderr=subprocess.DEVNULL)
    if result.returncode:
        fail("source archive failed")


def capture_packet(app, source, output, commit, config_path):
    packet = output / "source-packet"
    packet.mkdir()
    archive_git(app, commit, packet / "app-source.tar")
    archive_git(source, "HEAD", packet / "wrapper-upstream.tar")
    tree = command(["git", "write-tree"], cwd=source)
    archive_git(source, tree, packet / "wrapper-patched.tar")
    shutil.copytree(app / RECIPE, packet / "recipe",
                    ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    shutil.copytree(app / "intergalactic/ios/build-config", packet / "build-instructions")
    shutil.copy2(app / "intergalactic/ios/scripts/build_ipa.py", packet / "build_ipa.py")
    shutil.copy2(config_path, packet / "build-config.json")
    return {p.relative_to(packet).as_posix(): sha(p) for p in sorted(packet.rglob("*")) if p.is_file()}


def capture_bundle(bundle, version):
    bundles = [bundle, *sorted((bundle / "PlugIns").glob("*.appex"))]
    if len(bundles) != 4:
        fail("Runner must contain exactly Broadcast, Share and Notification extensions")
    expected_ids = {"chat.intergalactic.app", "chat.intergalactic.app.broadcast",
                    "chat.intergalactic.app.share", "chat.intergalactic.app.nse"}
    result = {}
    teams = set()
    name, number = version.split("+")
    for path in bundles:
        info = plistlib.loads((path / "Info.plist").read_bytes())
        if (info.get("CFBundleShortVersionString"), str(info.get("CFBundleVersion"))) != (name, number):
            fail("bundle version differs from selected source identity")
        identity = info["CFBundleIdentifier"]
        executable = path / info["CFBundleExecutable"]
        command(["codesign", "--verify", "--strict", str(path)])
        entitlements = plistlib.loads(command(["codesign", "-d", "--entitlements", ":-", str(path)]).encode())
        if "group.chat.intergalactic.app" not in entitlements.get("com.apple.security.application-groups", []):
            fail("App Group entitlement is missing")
        team = entitlements.get("com.apple.developer.team-identifier", "")
        if not team or entitlements.get("application-identifier") != f"{team}.{identity}":
            fail("bundle signing identity does not match its identifier")
        teams.add(team)
        result[identity] = {"executable_sha256": sha(executable), "info_sha256": sha(path / "Info.plist"),
                            "version": name, "build": number,
                            "get_task_allow": entitlements.get("get-task-allow", False),
                            "aps_environment": entitlements.get("aps-environment"),
                            "app_groups": entitlements["com.apple.security.application-groups"]}
        if identity == "chat.intergalactic.app.nse":
            exports = command(["nm", "-g", str(executable)])
            if any(not re.search(rf"(?m)^\S+\s+T\s+{symbol}$", exports) for symbol in EXPORTS):
                fail("notification extension is missing the bounded E8 ABI")
    if set(result) != expected_ids:
        fail("unexpected or missing extension bundle identifiers")
    if len(teams) != 1:
        fail("all bundles must be signed by the same team")
    command(["codesign", "--verify", "--deep", "--strict", str(bundle)])
    return result


def capture_artifact(app, output, version, kind, export_method, *, ipa_dir=None,
                     extraction_name="exported"):
    package = app / "intergalactic"
    if kind == "ipa":
        directory = canonical_path(ipa_dir or package / "build/ios/ipa")
        ipas = list(directory.glob("*.ipa"))
        if len(ipas) != 1:
            fail("exactly one exported IPA is required")
        artifact = ipas[0]
        regular_file(artifact)
        with zipfile.ZipFile(artifact) as archive:
            if any(name.startswith("/") or ".." in Path(name).parts for name in archive.namelist()):
                fail("unsafe IPA member path")
        extracted = canonical_path(output / extraction_name)
        if extracted.exists():
            fail("artifact extraction destination must be fresh")
        command(["ditto", "-x", "-k", str(artifact), str(extracted)])
        bundles = list((extracted / "Payload").glob("*.app"))
        if len(bundles) != 1:
            fail("one exported Runner bundle is required")
        bundle = bundles[0]
    else:
        bundle = package / "build/ios/iphoneos/Runner.app"
        artifact = None
    receipt = {"bundles": capture_bundle(bundle, version)}
    runner = receipt["bundles"]["chat.intergalactic.app"]
    expected_aps = "development" if kind != "ipa" or export_method == "development" else "production"
    if runner["aps_environment"] != expected_aps:
        fail("Runner APNs environment differs from the selected export")
    if kind == "ipa" and export_method != "development" and any(
            value["get_task_allow"] for value in receipt["bundles"].values()):
        fail("distribution bundle allows debugging")
    magic = {b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf",
             b"\xfe\xed\xfa\xce", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"}
    payloads = {}
    for path in sorted(bundle.rglob("*")):
        if path.is_file() and not path.is_symlink():
            with path.open("rb") as stream:
                is_macho = stream.read(4) in magic
            if is_macho:
                payloads[str(path.relative_to(bundle))] = {"sha256": sha(path), "bytes": path.stat().st_size}
    notice_paths = list(bundle.rglob("rust-crates-NOTICE.txt"))
    if len(notice_paths) != 1 or sha(notice_paths[0]) != sha(package / "assets/licenses/rust-crates-NOTICE.txt"):
        fail("packaged Rust notice differs from tracked notice")
    receipt.update(macho_payloads=payloads, rust_notice_sha256=sha(notice_paths[0]))
    receipt["flutter_license_registry"] = {
        str(path.relative_to(bundle)): sha(path)
        for path in bundle.rglob("NOTICES*") if path.is_file()
    }
    if not receipt["flutter_license_registry"]:
        fail("Flutter packaged license registry is missing")
    if artifact:
        receipt["ipa"] = {"sha256": sha(artifact), "bytes": artifact.stat().st_size,
                          "path": str(artifact.relative_to(output))}
    return receipt


def regular_file(path):
    path = canonical_path(path)
    if not stat.S_ISREG(path.lstat().st_mode) or not path.stat().st_size:
        fail("symbol/binary file missing, empty or nonregular")
    return path


def symbol_plist(path):
    regular_file(path)
    try:
        value = plistlib.loads(path.read_bytes())
    except (ValueError, ExpatError):
        fail("malformed symbol/archive/export metadata")
    if not isinstance(value, dict):
        fail("symbol/archive/export metadata must be a dictionary")
    return value


def tree_manifest(root):
    """Never follow links or open a FIFO while measuring a symbol bundle."""
    root = canonical_path(root)
    if not stat.S_ISDIR(root.lstat().st_mode):
        fail("symbol tree must be a directory")
    entries = {}
    for path in sorted(root.rglob("*")):
        canonical_path(path)
        mode = path.lstat().st_mode
        key = path.relative_to(root).as_posix()
        if stat.S_ISDIR(mode):
            entries[key] = {"directory": True}
        elif stat.S_ISREG(mode):
            regular_file(path)
            entries[key] = {"sha256": sha(path), "bytes": path.stat().st_size}
        else:
            fail("nonregular symbol tree descendant")
    if not entries:
        fail("empty symbol tree")
    return entries


def binary_uuid(path):
    regular_file(path)
    text = command(["xcrun", "dwarfdump", "--uuid", str(path)])
    rows = text.splitlines()
    match = re.fullmatch(r"UUID: ([0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}) \(arm64\) .+", text)
    if len(rows) != 1 or not match:
        fail("expected exactly one arm64 binary UUID")
    return match[1].upper()


def symbol_binaries(runner):
    """Identify extensions by their actual bundle IDs, not historic filenames."""
    paths = [runner, *sorted((runner / "PlugIns").glob("*.appex")),
             runner / "Frameworks/App.framework", runner / "Frameworks/Flutter.framework"]
    if len(paths) != 6:
        fail("expected six symbol-bearing bundles")
    result = {}
    for bundle in paths:
        regular_file(bundle / "Info.plist")
        info = symbol_plist(bundle / "Info.plist")
        executable = info.get("CFBundleExecutable")
        if not isinstance(executable, str) or Path(executable).name != executable or executable in ("", ".", ".."):
            fail("invalid symbol binary basename")
        identity = info.get("CFBundleIdentifier")
        if not isinstance(identity, str) or identity in result:
            fail("duplicate or invalid symbol bundle identity")
        binary = regular_file(bundle / executable)
        result[identity] = {"path": str(binary), "sha256": sha(binary),
                            "info_sha256": sha(bundle / "Info.plist"),
                            "uuid": binary_uuid(binary), "dsym": bundle.name + ".dSYM",
                            "dwarf": executable}
    if set(result) != {"chat.intergalactic.app", "chat.intergalactic.app.nse",
                       "chat.intergalactic.app.broadcast", "chat.intergalactic.app.share",
                       "io.flutter.flutter.app", "io.flutter.flutter"}:
        fail("unexpected symbol bundle identities")
    if len({row["uuid"] for row in result.values()}) != 6 or len({row["dsym"] for row in result.values()}) != 6:
        fail("duplicate symbol UUID or basename")
    return result


@dataclass(frozen=True)
class SymbolBinding:
    app: Path
    output: Path
    snapshot: str

    @property
    def data(self):
        return json.loads(self.snapshot, object_pairs_hook=unique_object)


def symbol_snapshot(binding, output, version, bootstrap):
    if binding.kind != "ipa":
        fail("symbol gather requires an IPA invocation")
    archive = canonical_path(binding.app / "intergalactic/build/ios/archive/Runner.xcarchive")
    runner = archive / "Products/Applications/Runner.app"
    regular_file(archive / "Info.plist")
    metadata = symbol_plist(archive / "Info.plist")
    properties = metadata.get("ApplicationProperties")
    if not isinstance(properties, dict) or properties.get("ApplicationPath") != "Applications/Runner.app":
        fail("archive application identity mismatch")
    signatures = capture_bundle(runner, version)
    archived = symbol_binaries(runner)
    exported = symbol_binaries(output / "exported-bootstrap/Payload/Runner.app")
    if any(archived[key]["uuid"] != exported[key]["uuid"] or archived[key]["dsym"] != exported[key]["dsym"]
           for key in archived):
        fail("archive/bootstrap binary UUID mismatch")
    products = canonical_path(binding.roots["SYMROOT"] / "Release-iphoneos")
    names = {row["dsym"] for row in archived.values()}
    if {p.name for p in products.glob("*.dSYM")} != names:
        fail("missing or foreign generated dSYM")
    symbols = {}
    for key, row in archived.items():
        source = products / row["dsym"]
        files = tree_manifest(source)
        metadata = source / "Contents/Info.plist"
        if (key == "io.flutter.flutter.app" and row["dsym"] == "App.framework.dSYM"
                and row["dwarf"] == "App" and not metadata.exists() and not metadata.is_symlink()):
            # Pinned Flutter ios.dart combines/copies ONLY the App DWARF file.
            # Accept that exact producer shape, not arbitrary absent metadata.
            if set(files) != {"Contents", "Contents/Resources", "Contents/Resources/DWARF",
                              "Contents/Resources/DWARF/App"}:
                fail("unexpected sparse Flutter App dSYM tree")
        elif symbol_plist(metadata).get("CFBundlePackageType") != "dSYM":
            fail("generated dSYM metadata mismatch")
        dwarf = source / "Contents/Resources/DWARF" / row["dwarf"]
        if ({p.name for p in dwarf.parent.iterdir()} != {row["dwarf"]} or binary_uuid(dwarf) != row["uuid"]):
            fail("generated dSYM metadata/UUID mismatch")
        symbols[key] = {"source": str(source), "tree": files}
    ipa = regular_file(output / bootstrap["ipa"]["path"])
    if sha(ipa) != bootstrap["ipa"]["sha256"]:
        fail("bootstrap IPA changed")
    return SymbolBinding(binding.app, canonical_path(output), json.dumps({
        "archive": str(archive), "archive_info_sha256": sha(archive / "Info.plist"),
        "version": version, "archived": archived, "exported": exported,
        "symbols": symbols, "signatures": signatures, "bootstrap": bootstrap["ipa"]}, sort_keys=True))


def validate_symbol_binding(binding, symbols, *, gathered=False):
    binding.assignments
    if not isinstance(symbols, SymbolBinding) or symbols.app != binding.app:
        fail("foreign symbol invocation")
    data = symbols.data
    current = symbol_snapshot(binding, symbols.output, data["version"], {"ipa": data["bootstrap"]})
    if current != symbols:
        fail("symbol source/tree/binary binding changed")
    if gathered:
        destination = canonical_path(Path(data["archive"]) / "dSYMs")
        names = {row["dsym"] for row in data["archived"].values()}
        if {p.name for p in destination.iterdir()} != names:
            fail("incomplete or foreign archive symbols")
        for key, row in data["archived"].items():
            bundle = destination / row["dsym"]
            if tree_manifest(bundle) != data["symbols"][key]["tree"]:
                fail("gathered symbol tree changed")
            if binary_uuid(bundle / "Contents/Resources/DWARF" / row["dwarf"]) != row["uuid"]:
                fail("gathered symbol UUID changed")


def gather_symbols(binding, symbols):
    """Exclusive copies; bounded same-plan retry may adopt only exact known bytes."""
    validate_symbol_binding(binding, symbols)
    data = symbols.data
    marker = canonical_path(symbols.output / "symbol-gather.json")
    destination = canonical_path(Path(data["archive"]) / "dSYMs")
    names = {row["dsym"] for row in data["archived"].values()}
    if marker.exists():
        regular_file(marker)
        if marker.read_text() != symbols.snapshot:
            fail("foreign symbol gather receipt")
    else:
        if destination.exists() and (not destination.is_dir() or any(destination.iterdir())):
            fail("unknown preexisting symbol destination")
        with marker.open("x") as stream:
            stream.write(symbols.snapshot)
    destination.mkdir(exist_ok=True)
    if not destination.is_dir() or {p.name for p in destination.iterdir()} - names:
        fail("foreign symbol destination")
    for key, row in data["archived"].items():
        source = Path(data["symbols"][key]["source"])
        target = canonical_path(destination / row["dsym"])
        expected = data["symbols"][key]["tree"]
        if target.exists():
            present = tree_manifest(target) if any(target.iterdir()) else {}
            if any(expected.get(name) != value for name, value in present.items()):
                fail("conflicting partial symbol destination")
        else:
            target.mkdir()
        for name, value in expected.items():
            path = canonical_path(target / name)
            if value.get("directory"):
                path.mkdir(exist_ok=True)
            elif path.exists():
                regular_file(path)
                if sha(path) != value["sha256"]:
                    fail("conflicting symbol bytes")
            else:
                with path.open("xb") as dest, regular_file(source / name).open("rb") as src:
                    shutil.copyfileobj(src, dest)
    validate_symbol_binding(binding, symbols, gathered=True)


def export_options(path, method):
    regular_file(path)
    options = symbol_plist(path)
    expected = {"app-store": "app-store-connect", "ad-hoc": "release-testing", "development": "debugging"}[method]
    if (options.get("method") != expected or options.get("destination", "export") != "export"
            or (method == "app-store" and options.get("uploadSymbols", True) is not True)
            or options.get("stripSwiftSymbols", True) is not True):
        fail("unexpected local export option semantics")
    return sha(path)


def final_symbol_coverage(ipa, symbols, runner, method="app-store"):
    if method not in ("app-store", "ad-hoc", "development"):
        fail("unknown IPA export method")
    actual = symbol_binaries(runner)
    expected = symbols.data["archived"]
    if any(actual[key]["uuid"] != row["uuid"] or actual[key]["dsym"] != row["dsym"]
           for key, row in expected.items()):
        fail("final binary/symbol binding changed")
    regular_file(ipa)
    # Archive dSYMs/binary bindings apply to every mode; IPA symbol upload is
    # an App Store export intent, not a development/ad-hoc packaging contract.
    if method != "app-store":
        return {}
    names = {f"Symbols/{row['uuid']}.symbols" for row in expected.values()}
    with zipfile.ZipFile(regular_file(ipa)) as archive:
        files = [entry for entry in archive.infolist() if entry.filename.startswith("Symbols/") and not entry.is_dir()]
        if (len(files) != 6 or {entry.filename for entry in files} != names or
                any(entry.file_size == 0 or stat.S_IFMT(entry.external_attr >> 16) not in (0, stat.S_IFREG) for entry in files)):
            fail("final IPA symbol coverage missing, empty, duplicate or foreign")
        # Force CRC/decompression verification too, not just central-directory sizes.
        return {entry.filename: hashlib.sha256(archive.read(entry)).hexdigest() for entry in files}


def finish_ipa(binding, output, version, method, plan, receipt_path, postflight):
    bootstrap = capture_artifact(binding.app, output, version, "ipa", method,
                                 extraction_name="exported-bootstrap")
    plan.update(bootstrap_artifact=bootstrap, status="bootstrap exported; final symbol verification pending")
    receipt_path.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n")
    postflight()
    symbols = symbol_snapshot(binding, output, version, bootstrap)
    gather_symbols(binding, symbols)
    options = canonical_path(binding.app / "intergalactic/build/ios/ipa/ExportOptions.plist")
    options_hash = export_options(options, method)
    final = canonical_path(output / "final-export")
    if final.exists():
        fail("final export destination must be fresh")
    final.mkdir()
    postflight()
    validate_symbol_binding(binding, symbols, gathered=True)
    if export_options(options, method) != options_hash:
        fail("export options changed")
    command(["xcodebuild", "-exportArchive", "-archivePath", symbols.data["archive"],
             "-exportOptionsPlist", str(options), "-exportPath", str(final)],
            cwd=binding.app / "intergalactic/ios", env=binding.env)
    postflight()
    validate_symbol_binding(binding, symbols, gathered=True)
    if export_options(options, method) != options_hash:
        fail("export options changed")
    artifact = capture_artifact(binding.app, output, version, "ipa", method,
                                ipa_dir=final, extraction_name="exported-final")
    postflight()
    validate_symbol_binding(binding, symbols, gathered=True)
    coverage = final_symbol_coverage(output / artifact["ipa"]["path"], symbols,
                                     output / "exported-final/Payload/Runner.app", method)
    plan.update(symbols=symbols.data, final_symbols=coverage,
                ipa_symbol_coverage_required=method == "app-store", export_options_sha256=options_hash)
    return artifact


def query_settings(binding, target):
    ios = binding.app / "intergalactic/ios"
    args = ["xcodebuild", "-showBuildSettings", "-json"]
    if target == "Runner":
        args += ["-workspace", str(ios / "Runner.xcworkspace"), "-scheme", target]
    else:
        args += ["-project", str(ios / "Pods/Pods.xcodeproj"), "-target", target]
    args += ["-configuration", binding.configuration, "-sdk", "iphoneos",
             "-destination", "generic/platform=iOS", *binding.assignments]
    if binding.kind == "ipa":
        if target == "Runner":
            args += ["-archivePath", str(binding.app / "intergalactic/build/ios/archive/Runner.xcarchive")]
        args += ["archive"]
    else:
        args += [f"BUILD_DIR={binding.app}/intergalactic/build/ios", "build"]
    rows = json.loads(command(args, cwd=ios, env=binding.env), object_pairs_hook=unique_object)
    if not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows):
        fail("invalid Xcode settings rows")
    matches = [row.get("buildSettings") for row in rows if row.get("target") == target]
    if len(matches) != 1 or not isinstance(matches[0], dict):
        fail(f"one unambiguous {target} settings row is required")
    return matches[0]


def check_workspace_metadata(root, workspace):
    """Optional corroboration only; never discover roots from metadata."""
    path = canonical_path(root / "info.plist")
    if not path.exists():
        return
    if not stat.S_ISREG(path.stat().st_mode) or not path.stat().st_size:
        fail("invalid workspace metadata file")
    try:
        metadata = plistlib.loads(path.read_bytes())
    except (ValueError, plistlib.InvalidFileException, OverflowError):
        fail("malformed workspace metadata")
    if not isinstance(metadata, dict) or metadata.get("WorkspacePath") != str(workspace):
        fail("metadata belongs to a foreign workspace")


def cargokit_context(binding, *, require_fresh=False):
    """Corroborate wrapper-owned roots with Runner AND the actual pod target."""
    binding.assignments  # Revalidate the immutable product/query environment.
    app, configuration = binding.app, binding.configuration
    ios = canonical_path(app / "intergalactic/ios")
    workspace = canonical_path(ios / "Runner.xcworkspace")
    objroot, symroot = binding.roots["OBJROOT"], binding.roots["SYMROOT"]
    build_dir = symroot if binding.kind == "ipa" else app / "intergalactic/build/ios"
    products = canonical_path(build_dir / f"{configuration}-iphoneos")
    common = {"CONFIGURATION": configuration, "ACTION": "archive" if binding.kind == "ipa" else "build",
              "ARCHS": "arm64", "EFFECTIVE_PLATFORM_NAME": "-iphoneos", "OBJROOT": str(objroot),
              "SYMROOT": str(symroot), "BUILD_DIR": str(build_dir), "PODS_CONFIGURATION_BUILD_DIR": str(products)}
    context = {"app": str(app), "kind": binding.kind, "workspace": str(workspace),
               "configuration": configuration, "objroot": str(objroot), "symroot": str(symroot),
               "products": str(products)}
    metadata_roots = [objroot.parent, objroot, symroot]
    sdk = None
    for target, project in (("Runner", "Runner"), ("flutter_vodozemac", "Pods")):
        settings = query_settings(binding, target)
        project_root = ios if target == "Runner" else ios / "Pods"
        target_products = products if target == "Runner" else products / target
        target_temp = objroot / f"{project}.build/{configuration}-iphoneos/{target}.build"
        expected = dict(common, SRCROOT=str(project_root), PROJECT_FILE_PATH=str(project_root / f"{project}.xcodeproj"),
                        PRODUCT_NAME=target, CONFIGURATION_BUILD_DIR=str(target_products),
                        BUILT_PRODUCTS_DIR=str(target_products), PROJECT_TEMP_DIR=str(objroot / f"{project}.build"),
                        TARGET_TEMP_DIR=str(target_temp))
        if binding.kind != "ipa":
            expected["TARGET_BUILD_DIR"] = str(target_products)
        elif target != "Runner":
            expected["TARGET_BUILD_DIR"] = str(objroot / "UninstalledProducts/iphoneos")
        else:
            # Xcode keeps the archive installation directory in default DerivedData,
            # even with explicit intermediate/product roots. Never use it for Rust.
            value = settings.get("TARGET_BUILD_DIR")
            if not isinstance(value, str) or not value:
                fail("missing archive installation directory")
            installation = canonical_path(value)
            base = canonical_path(default_derived_data_dir())
            relative = installation.relative_to(base) if installation.is_relative_to(base) else Path()
            if (len(relative.parts) != 7 or not re.fullmatch(r"Runner-[a-z0-9]+", relative.parts[0])
                    or relative.parts[1:] != ("Build", "Intermediates.noindex", "ArchiveIntermediates", "Runner",
                                              "InstallationBuildProductsLocation", "Applications")):
                fail("foreign archive installation directory")
            expected["TARGET_BUILD_DIR"] = value
            metadata_roots.append(base / relative.parts[0])
        if any(settings.get(key) != value for key, value in expected.items()):
            fail(f"{target} settings do not match the invocation workspace/action/path equations")
        sdk_name = settings.get("SDK_NAME")
        if not isinstance(sdk_name, str) or not re.fullmatch(r"iphoneos[0-9]+(?:\.[0-9]+)*", sdk_name):
            fail("nonphysical or malformed Xcode SDK")
        if sdk is not None and sdk_name != sdk:
            fail("Runner/pod SDK disagreement")
        sdk = sdk_name
        for key, value in expected.items():
            if key in {"SRCROOT", "PROJECT_FILE_PATH", "OBJROOT", "SYMROOT", "BUILD_DIR",
                       "PODS_CONFIGURATION_BUILD_DIR", "CONFIGURATION_BUILD_DIR", "BUILT_PRODUCTS_DIR",
                       "PROJECT_TEMP_DIR", "TARGET_TEMP_DIR", "TARGET_BUILD_DIR"}:
                canonical_path(value)
            context[f"{target}:{key}"] = value
        context[f"{target}:SDK_NAME"] = sdk_name
    for root in metadata_roots:
        check_workspace_metadata(root, workspace)
    library = Path(context["flutter_vodozemac:TARGET_TEMP_DIR"]) / "aarch64-apple-ios/release/libvodozemac_bindings_dart.a"
    pod_archive = products / "flutter_vodozemac/libvodozemac_bindings_dart.a"
    for label, path in (("cargokit_static_library", library), ("xcode_pod_archive", pod_archive)):
        canonical_path(path)
        if require_fresh and (path.exists() or path.is_symlink()):
            fail("preexisting CargoKit artifact in fresh build invocation")
        context[label] = str(path)
    return MappingProxyType(context)


def capture_cargokit(binding, invocation):
    if not isinstance(invocation, MappingProxyType):
        fail("mutable or substituted CargoKit invocation")
    context = cargokit_context(binding)
    if context != invocation:
        fail("CargoKit invocation paths changed during the build")
    result = {}
    for label in ("cargokit_static_library", "xcode_pod_archive"):
        path = Path(context[label])
        if not path.exists() or not stat.S_ISREG(path.stat().st_mode) or not path.stat().st_size:
            fail(f"required {label} missing, empty or nonregular")
        symbols = command(["nm", "-g", str(path)])
        if any(not re.search(rf"(?m)^\S+\s+T\s+{symbol}$", symbols) for symbol in EXPORTS):
            fail(f"{label} is missing the bounded E8 ABI")
        result[label] = {"sha256": sha(path), "bytes": path.stat().st_size}
    return result


def run_product(binding, args, receipt_path, plan, invocation):
    """Persist original preflight before forwarding the identical product env."""
    binding.assignments
    plan["cargokit_invocation"] = dict(invocation)
    receipt_path.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n")
    command(args, cwd=binding.app / "intergalactic", env=binding.env)


def verify_defines(xcconfig, config, commit, version):
    encoded = re.findall(r"^DART_DEFINES=(.+)$", xcconfig, re.M)
    if len(encoded) != 1:
        fail("one generated Dart define set is required")
    pairs = [base64.b64decode(value, validate=True).decode().partition("=") for value in encoded[0].split(",")]
    actual = {key: value for key, _, value in pairs}
    if len(actual) != len(pairs):
        fail("duplicate generated Dart define")
    expected = dict(config["defines"], BUILD_MODE="release", PLATFORM="ios",
                    GIT_HASH=commit, VERSION_TAG=f"v{version}")
    # build_release.dart omits empty optional defines. Defaults in BuildConfig
    # remain visible to runtime; record these as absent rather than fabricating
    # that the define was emitted by the build.
    for key, value in expected.items():
        if actual.get(key, "") != value:
            fail("generated Dart defines differ from the supplied build configuration")
    if set(actual) - set(expected) - {"BUILD_DATE", "BUILD_DETAIL"} - FLUTTER_DEFINES:
        fail("unrecorded generated Dart defines")
    for key, pin in (("FLUTTER_VERSION", "flutter_version"),
                     ("FLUTTER_DART_VERSION", "dart_version")):
        if key in actual and actual[key] != config["toolchain"][pin]:
            fail("Flutter-generated identity differs from the pinned toolchain")
    # Pinned Flutter's flutter_command.dart emits frameworkRevisionShort;
    # version.dart truncates it to exactly ten characters. The independent
    # check_toolchain full-40 revision equality remains mandatory.
    pin = config["toolchain"]["flutter_revision"]
    revision = actual.get("FLUTTER_FRAMEWORK_REVISION")
    if not re.fullmatch(r"[0-9a-f]{40}", pin) or (
            revision is not None and revision not in (pin, pin[:10])):
        fail("Flutter-generated revision differs from the pinned toolchain")
    if "BUILD_DATE" in actual and not actual["BUILD_DATE"].isdigit():
        fail("build date must be a numeric timestamp")
    return actual


def main():
    if sys.version_info < (3, 11):
        fail("Python 3.11 or newer is required")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--kind", choices=("ipa", "development-app"), default="ipa")
    parser.add_argument("--export-method", choices=("app-store", "ad-hoc", "development"), default="app-store")
    parser.add_argument("--phase", choices=("plan", "prepare", "build"), default="plan")
    args = parser.parse_args()
    config = load_config(args.config)
    version = source_identity(REPO, args.commit)
    output = args.output.expanduser().resolve()
    if output == REPO or REPO in output.parents or output in REPO.parents:
        fail("output must be a separate directory outside the source checkout")
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        fail("output must be new or empty")
    plan = {"source_commit": args.commit, "version": version, "kind": args.kind,
            "mode": "release" if args.kind == "ipa" else "profile",
            "export_method": args.export_method if args.kind == "ipa" else "device-app",
            "config_sha256": sha(args.config), "configuration": config,
            "status": "planned; no build"}
    if args.phase == "plan":
        print(json.dumps(plan, indent=2, sort_keys=True))
        return
    if sys.platform != "darwin":
        fail("iOS preparation/build requires macOS")
    flutter, dart, toolchain = check_toolchain(config)
    if shutil.disk_usage(output.parent).free < 10 * 1024**3:
        fail("at least 10 GiB free is required")
    output.mkdir(parents=True, exist_ok=True)
    input_repo = output / "input"
    command(["git", "clone", "--local", "--no-hardlinks", "--no-checkout", str(REPO), str(input_repo)])
    command(["git", "checkout", "--detach", args.commit], cwd=input_repo)
    env = build_environment(output / "prepared/source", args.commit, flutter, config["defines"])
    command([sys.executable, str(input_repo / RECIPE / "prepare.py"),
             str(output / "prepared"), "--resolve-app"], env=env)
    app = output / "prepared/app"
    source = output / "prepared/source"
    recipe_dir = app / RECIPE
    command([sys.executable, str(recipe_dir / "verify_ios_patch.py")], env=env)
    # Run existing codegen in the same pinned environment as preparation.
    generated = command([sys.executable, "-c",
                         "import json,pathlib,sys,prepare; print(json.dumps(prepare.generate_app_sources(pathlib.Path(sys.argv[1]))))",
                str(app)], cwd=recipe_dir, env=env)
    generated_hashes = json.loads(generated)
    for path in (app / "intergalactic/lib").rglob("*.dart"):
        relative = path.relative_to(app / "intergalactic")
        if path.name.endswith(".g.dart") or "generated" in relative.parts:
            generated_hashes[str(relative)] = sha(path)
    plan.update(status="prepared; no product build", toolchain=toolchain,
                preparation=json.loads((output / "prepared/evidence.json").read_text()),
                generated_sources=generated_hashes,
                host={"macos": command(["sw_vers", "-productVersion"]),
                      "architecture": command(["uname", "-m"]),
                      "iphoneos_sdk": command(["xcrun", "--sdk", "iphoneos", "--show-sdk-version"])})
    plan["source_packet"] = capture_packet(app, source, output, args.commit, args.config)
    receipt_path = output / "build-receipt.json"
    receipt_path.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n")
    if args.phase == "build":
        args_list = build_command(args.kind, app, args.commit, version, config, flutter, dart, args.export_method)
        plan["status"] = "build started; artifact verification pending"
        receipt_path.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n")
        command([sys.executable, str(recipe_dir / "verify_ios_patch.py")], env=env)
        # Resolve the existing locked Pods before asking Xcode for invocation
        # settings. Flutter will still perform its normal CocoaPods checks.
        command(["pod", "install"], cwd=app / "intergalactic/ios", env=env)
        env["IG_E8_REQUIRE_POD_LINK"] = "1"
        binding = XcodeBinding(app, args.kind, env)
        command([sys.executable, str(recipe_dir / "verify_ios_patch.py")], env=binding.env)
        invocation = cargokit_context(binding, require_fresh=True)
        run_product(binding, args_list, receipt_path, plan, invocation)
        command([sys.executable, str(recipe_dir / "verify_ios_patch.py")], env=binding.env)
        def postflight():
            command([sys.executable, str(recipe_dir / "verify_ios_patch.py")], env=binding.env)
            measured = capture_cargokit(binding, invocation)
            if "cargokit" in plan and measured != plan["cargokit"]:
                fail("CargoKit bytes changed during final export")
            plan["cargokit"] = measured
            xcconfig = (app / "intergalactic/ios/Flutter/Generated.xcconfig").read_text()
            return verify_defines(xcconfig, config, args.commit, version)
        plan["build_command"] = args_list
        artifact = (finish_ipa(binding, output, version, args.export_method, plan, receipt_path, postflight)
                    if args.kind == "ipa" else capture_artifact(app, output, version, args.kind, args.export_method))
        actual = postflight()
        plan["artifact"] = artifact
        plan.update(status="built and measured; recipient source/publication not verified",
                    effective_defines=actual)
        receipt_path.write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n")
    print(f"iOS receipt: {receipt_path}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, json.JSONDecodeError) as error:
        print(f"iOS build failed closed: {error}", file=sys.stderr)
        sys.exit(1)
