import base64
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
import shutil
import stat
import uuid
import zipfile
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/build_ipa.py"
SPEC = importlib.util.spec_from_file_location("build_ipa", SCRIPT)
build = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(build)
CONFIG = SCRIPT.parent.parent / "build-config/config.example.json"
COMMIT = "a" * 40


class IpaBuildTests(unittest.TestCase):
    def setUp(self):
        self.config = build.load_config(CONFIG)

    def config_file(self, text):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        path = Path(temp.name) / "config.json"
        path.write_text(text)
        return path

    def test_config_requires_all_service_choices(self):
        del self.config["defines"]["SPOTIFY_CLIENT_ID"]
        with self.assertRaisesRegex(ValueError, "every toolchain"):
            build.load_config(self.config_file(json.dumps(self.config)))

    def test_unknown_secret_field_is_rejected(self):
        self.config["defines"]["KLIPY_API_KEY"] = "do-not-embed"
        with self.assertRaises(ValueError):
            build.load_config(self.config_file(json.dumps(self.config)))

    def test_duplicate_json_cannot_substitute_a_valid_field(self):
        text = CONFIG.read_text().replace('"schema": 1', '"schema": 0, "schema": 1')
        with self.assertRaisesRegex(ValueError, "duplicate JSON"):
            build.load_config(self.config_file(text))

    def test_boolean_typo_rejected(self):
        self.config["defines"]["ENABLE_NATIVE_DETACHED_CALL_WINDOWS"] = "ture"
        with self.assertRaisesRegex(ValueError, "true or false"):
            build.load_config(self.config_file(json.dumps(self.config)))

    def test_source_commit_and_cleanliness_are_both_required(self):
        with patch.object(build, "command", return_value="b" * 40):
            with self.assertRaisesRegex(ValueError, "HEAD"):
                build.source_identity(Path("unused"), COMMIT)
        with patch.object(build, "command", side_effect=[COMMIT, " M source.dart"]):
            with self.assertRaisesRegex(ValueError, "clean"):
                build.source_identity(Path("unused"), COMMIT)
        with self.assertRaisesRegex(ValueError, "full app SHA"):
            build.source_identity(Path("unused"), "unknown")

    def test_ipa_command_uses_release_helper_and_preserves_resolution(self):
        args = build.build_command("ipa", Path("app"), COMMIT, "0.8.2+1008",
                                   self.config, "/sdk/flutter", "/sdk/dart", "app-store")
        self.assertEqual(args[:3], ["/sdk/dart", "run", "scripts/build_release.dart"])
        self.assertIn("--skip_flutter_pub", args)
        self.assertEqual(args[args.index("--git_hash") + 1], COMMIT)
        self.assertEqual(args[args.index("--ios_export_method") + 1], "app-store")
        for key, option in build.OPTIONS.items():
            self.assertEqual(args[args.index(f"--{option}") + 1], self.config["defines"][key])

    def test_profile_preserves_product_defines_and_platform(self):
        args = build.build_command("development-app", Path("app"), COMMIT,
                                   "0.8.2+1008", self.config, "/sdk/flutter", "/sdk/dart", "app-store")
        self.assertIn("--profile", args)
        self.assertIn("--no-pub", args)
        self.assertIn("--dart-define=BUILD_MODE=release", args)
        self.assertIn("--dart-define=PLATFORM=ios", args)
        for key, value in self.config["defines"].items():
            if value or key == "GIF_API_BASE_URL":
                self.assertIn(f"--dart-define={key}={value}", args)
            else:
                self.assertFalse(any(arg.startswith(f"--dart-define={key}=") for arg in args))

    def test_empty_gif_config_explicitly_disables_managed_relay_in_both_paths(self):
        self.config["defines"]["GIF_API_BASE_URL"] = ""
        args = build.build_command("ipa", Path("app"), COMMIT, "0.8.2+1008",
                                   self.config, "flutter", "dart", "development")
        self.assertIn("--disable_managed_gif_relay", args)
        dev = build.build_command("development-app", Path("app"), COMMIT,
                                  "0.8.2+1008", self.config, "flutter", "dart", "development")
        self.assertIn("--dart-define=GIF_API_BASE_URL=", dev)

    def test_credentials_in_public_url_are_rejected(self):
        self.config["defines"]["GIF_API_BASE_URL"] = "https://user:secret@example.com/api"
        with self.assertRaisesRegex(ValueError, "public HTTPS"):
            build.load_config(self.config_file(json.dumps(self.config)))

    def test_ambient_secret_and_harness_flags_cannot_change_build(self):
        env = build.build_environment(Path("source"), COMMIT, "/sdk/flutter", self.config["defines"],
                                      {"KLIPY_API_KEY": "hidden", "ALLOW_DIRECT_KLIPY_API_KEY": "1",
                                       "IOS_NOTIFICATION_DEBUG_HARNESS_SWIFT_FLAG": "-DDEBUG_HARNESS",
                                       "GIF_API_BASE_URL": "wrong", "DART_DEFINES": "wrong"})
        self.assertNotIn("KLIPY_API_KEY", env)
        self.assertNotIn("DART_DEFINES", env)
        self.assertNotIn("IOS_NOTIFICATION_DEBUG_HARNESS_SWIFT_FLAG", env)
        self.assertEqual(env["GIF_API_BASE_URL"], self.config["defines"]["GIF_API_BASE_URL"])

    def test_unrecorded_compiler_flags_fail(self):
        with self.assertRaisesRegex(ValueError, "unrecorded"):
            build.build_environment(Path("source"), COMMIT, "flutter", {}, {"RUSTFLAGS": "-Copt-level=0"})

    def test_inherited_xcode_and_root_overrides_fail_even_when_empty(self):
        for key in (*build.ROOT_OVERRIDES, "FLUTTER_XCODE_OBJROOT", "FLUTTER_XCODE_CODE_SIGNING_ALLOWED"):
            for value in ("", "/foreign"):
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    build.build_environment(Path("source"), COMMIT, "flutter", {}, {key: value})

    def xcconfig(self, changes=None, extras=None):
        values = dict(self.config["defines"], BUILD_MODE="release", PLATFORM="ios",
                      GIT_HASH=COMMIT, VERSION_TAG="v0.8.2+1008",
                      FLUTTER_VERSION=self.config["toolchain"]["flutter_version"],
                      FLUTTER_FRAMEWORK_REVISION=self.config["toolchain"]["flutter_revision"],
                      BUILD_DATE="123456789")
        values.update(changes or {})
        encoded = [base64.b64encode(f"{k}={v}".encode()).decode() for k, v in values.items()]
        encoded += [base64.b64encode(value.encode()).decode() for value in extras or []]
        return "DART_DEFINES=" + ",".join(encoded)

    def test_generated_flags_are_checked_against_plan(self):
        actual = build.verify_defines(self.xcconfig(), self.config, COMMIT, "0.8.2+1008")
        self.assertEqual(actual["BUILD_DATE"], "123456789")
        for changes in ({"PLATFORM": "desktop"}, {"GIT_HASH": "unknown"},
                        {"FLUTTER_FRAMEWORK_REVISION": "b" * 40}):
            with self.assertRaises(ValueError):
                build.verify_defines(self.xcconfig(changes), self.config, COMMIT, "0.8.2+1008")

    def test_duplicate_or_unknown_generated_define_fails(self):
        for extra in ("PLATFORM=ios", "KLIPY_API_KEY=hidden"):
            with self.assertRaises(ValueError):
                build.verify_defines(self.xcconfig(extras=[extra]), self.config, COMMIT, "0.8.2+1008")

    def test_framework_revision_accepts_only_full_pin_or_emitted_ten_characters(self):
        pin = self.config["toolchain"]["flutter_revision"]
        for revision in (pin, pin[:10]):
            build.verify_defines(self.xcconfig({"FLUTTER_FRAMEWORK_REVISION": revision}),
                                 self.config, COMMIT, "0.8.2+1008")
        for revision in ("b" * 40, "b" * 10, pin[:9], pin[:11], pin.upper(), "not-a-hash"):
            with self.subTest(revision=revision), self.assertRaises(ValueError):
                build.verify_defines(self.xcconfig({"FLUTTER_FRAMEWORK_REVISION": revision}),
                                     self.config, COMMIT, "0.8.2+1008")

    def test_installed_toolchain_still_requires_exact_full_revision(self):
        pins = self.config["toolchain"]
        for revision in (pins["flutter_revision"], pins["flutter_revision"][:10], "b" * 40):
            machine = json.dumps({"frameworkVersion": pins["flutter_version"],
                                  "frameworkRevision": revision, "dartSdkVersion": pins["dart_version"]})
            outputs = [machine, pins["xcode"], pins["rustc"], pins["cargo"], pins["cocoapods"]]
            with patch.object(build.shutil, "which", return_value="/sdk/flutter"), patch.object(
                    build, "command", side_effect=outputs):
                if revision == pins["flutter_revision"]:
                    self.assertEqual(build.check_toolchain(self.config)[2], pins)
                else:
                    with self.assertRaisesRegex(ValueError, "installed toolchain"):
                        build.check_toolchain(self.config)

    def cargokit_fixture(self, kind="ipa"):
        # Self-contained fields captured from pinned Xcode 26.5 Runner/pod
        # queries, normalized to isolated paths. No private workspace fixture.
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name).resolve()
        app, derived = root / "app", root / "DerivedData"
        ios = app / "intergalactic/ios"
        ios.mkdir(parents=True)
        binding = build.XcodeBinding(app, kind, {"PATH": "/sdk", "IG_E8_REQUIRE_POD_LINK": "1"})
        c = binding.configuration
        obj, sym = binding.roots["OBJROOT"], binding.roots["SYMROOT"]
        directory = sym if kind == "ipa" else app / "intergalactic/build/ios"
        products = directory / f"{c}-iphoneos"
        rows = {}
        for target, project in (("Runner", "Runner"), ("flutter_vodozemac", "Pods")):
            source = ios if project == "Runner" else ios / "Pods"
            output = products if project == "Runner" else products / target
            install = (derived / "Runner-bound/Build/Intermediates.noindex/ArchiveIntermediates/Runner/InstallationBuildProductsLocation/Applications"
                       if project == "Runner" else obj / "UninstalledProducts/iphoneos")
            rows[target] = {"SRCROOT": str(source), "PROJECT_FILE_PATH": str(source / f"{project}.xcodeproj"),
                "CONFIGURATION": c, "ACTION": "archive" if kind == "ipa" else "build",
                "ARCHS": "arm64", "EFFECTIVE_PLATFORM_NAME": "-iphoneos", "SDK_NAME": "iphoneos26.5",
                "OBJROOT": str(obj), "SYMROOT": str(sym), "BUILD_DIR": str(directory),
                "CONFIGURATION_BUILD_DIR": str(output), "BUILT_PRODUCTS_DIR": str(output),
                "PODS_CONFIGURATION_BUILD_DIR": str(products), "PRODUCT_NAME": target,
                "PROJECT_TEMP_DIR": str(obj / f"{project}.build"),
                "TARGET_TEMP_DIR": str(obj / f"{project}.build/{c}-iphoneos/{target}.build"),
                "TARGET_BUILD_DIR": str(install if kind == "ipa" else output)}
        return binding, derived, rows

    def fixture_commands(self, rows, **kwargs):
        def commands(args, **options):
            if args[0] == "xcodebuild":
                target = args[args.index("-target") + 1] if "-target" in args else "Runner"
                return json.dumps([{"target": target, "buildSettings": rows[target]}])
            return self.apple_command(args, **options)
        return commands

    def query_fixture(self, binding, derived, rows, **options):
        with patch.object(build, "default_derived_data_dir", return_value=derived), patch.object(
                build, "command", side_effect=self.fixture_commands(rows)):
            return build.cargokit_context(binding, **options)

    def capture_fixture(self, binding, derived, rows, context):
        with patch.object(build, "default_derived_data_dir", return_value=derived), patch.object(
                build, "command", side_effect=self.fixture_commands(rows)):
            return build.capture_cargokit(binding, context)

    def output_files(self, context, content=b"fresh"):
        for name in ("cargokit_static_library", "xcode_pod_archive"):
            path = Path(context[name])
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)

    def test_archive_and_profile_use_invocation_paths_and_ignore_stale_competitors(self):
        for kind in ("ipa", "development-app"):
            with self.subTest(kind=kind):
                binding, derived, rows = self.cargokit_fixture(kind)
                stale = derived / "Runner-old/Build/Intermediates.noindex/Pods.build/lib.a"
                stale.parent.mkdir(parents=True)
                stale.write_bytes(b"stale")
                context = self.query_fixture(binding, derived, rows, require_fresh=True)
                self.output_files(context)
                result = self.capture_fixture(binding, derived, rows, context)
                for name in ("cargokit_static_library", "xcode_pod_archive"):
                    self.assertEqual(result[name], {"bytes": 5, "sha256": build.sha(Path(context[name]))})
                with self.assertRaisesRegex(ValueError, "preexisting"):
                    self.query_fixture(binding, derived, rows, require_fresh=True)

    def test_binding_is_immutable_and_copies_environment(self):
        binding, _, _ = self.cargokit_fixture()
        inherited = {"PATH": "original"}
        bound = build.XcodeBinding(binding.app, "ipa", inherited)
        inherited["FLUTTER_XCODE_OBJROOT"] = "/foreign"
        inherited["PATH"] = "changed"
        self.assertEqual(bound.env["PATH"], "original")
        with self.assertRaises(TypeError):
            bound.env["PATH"] = "changed"
        with self.assertRaises(AttributeError):
            bound.kind = "development-app"
        with self.assertRaises(TypeError):
            build.XcodeBinding(binding.app, "ipa", {}, roots={})
        with self.assertRaises(ValueError):
            build.XcodeBinding(binding.app, "ipa", {"OBJROOT": ""})

    def test_query_and_product_environment_and_assignments_are_identical(self):
        for kind in ("ipa", "development-app"):
            binding, derived, rows = self.cargokit_fixture(kind)
            with patch.object(build, "default_derived_data_dir", return_value=derived), patch.object(
                    build, "command", side_effect=self.fixture_commands(rows)) as command:
                context = build.cargokit_context(binding, require_fresh=True)
                build.run_product(binding, ["product"], binding.app / "receipt.json", {"status": "pending"}, context)
                for call in command.call_args_list:
                    self.assertIs(call.kwargs["env"], binding.env)
                    args = call.args[0]
                    if args[0] == "xcodebuild":
                        for key, path in binding.roots.items():
                            self.assertIn(f"{key}={path}", args)
                            self.assertEqual(binding.env[f"FLUTTER_XCODE_{key}"], str(path))
                        self.assertEqual(args[-1], "archive" if kind == "ipa" else "build")
                        if kind != "ipa":
                            self.assertIn(f"BUILD_DIR={binding.app}/intergalactic/build/ios", args)
                receipt = json.loads((binding.app / "receipt.json").read_text())
                self.assertEqual(receipt["cargokit_invocation"], dict(context))

    def test_every_runner_and_pod_field_is_checked_in_both_modes(self):
        for kind in ("ipa", "development-app"):
            binding, derived, rows = self.cargokit_fixture(kind)
            for target, settings in rows.items():
                for field, original in list(settings.items()):
                    for wrong in (None, "", "/foreign/path"):
                        with self.subTest(kind=kind, target=target, field=field, wrong=wrong):
                            settings[field] = wrong
                            with self.assertRaises(ValueError):
                                self.query_fixture(binding, derived, rows)
                            settings[field] = original

    def test_valid_but_different_sdk_and_foreign_installation_root_fail(self):
        for kind in ("ipa", "development-app"):
            binding, derived, rows = self.cargokit_fixture(kind)
            rows["flutter_vodozemac"]["SDK_NAME"] = "iphoneos26.4"
            with self.assertRaisesRegex(ValueError, "disagreement"):
                self.query_fixture(binding, derived, rows)
        binding, derived, rows = self.cargokit_fixture()
        for path in ("relative/Applications", str(derived / "Other-bound/Build/Intermediates.noindex/ArchiveIntermediates/Runner/InstallationBuildProductsLocation/Applications")):
            rows["Runner"]["TARGET_BUILD_DIR"] = path
            with self.assertRaises(ValueError):
                self.query_fixture(binding, derived, rows)

    def test_pending_receipt_is_written_before_product_and_retained_on_failure(self):
        binding, derived, rows = self.cargokit_fixture()
        context = self.query_fixture(binding, derived, rows)
        receipt = binding.app / "receipt.json"
        plan = {"status": "build started; artifact verification pending", "source_commit": COMMIT}
        def failed_product(args, **kwargs):
            self.assertIs(kwargs["env"], binding.env)
            self.assertEqual(json.loads(receipt.read_text())["cargokit_invocation"], dict(context))
            raise ValueError("product failed")
        with patch.object(build, "command", side_effect=failed_product), self.assertRaises(ValueError):
            build.run_product(binding, ["product"], receipt, plan, context)
        self.assertEqual(json.loads(receipt.read_text())["status"], plan["status"])

    def test_cargokit_rejects_wrong_build_action(self):
        for kind, wrong in (("ipa", "build"), ("development-app", "archive")):
            binding, derived, rows = self.cargokit_fixture(kind)
            rows["Runner"]["ACTION"] = wrong
            with self.assertRaisesRegex(ValueError, "workspace/action"):
                self.query_fixture(binding, derived, rows)

    def test_cargokit_rejects_malformed_missing_and_duplicate_rows_for_both_targets(self):
        for kind in ("ipa", "development-app"):
            binding, derived, rows = self.cargokit_fixture(kind)
            for target in rows:
                for payload in ('{}', '[null]', '[]',
                                json.dumps([{"target": target, "buildSettings": rows[target]}] * 2),
                                '[{"target":"Runner","target":"Runner"}]',
                                json.dumps([{"target": "foreign", "buildSettings": rows[target]}]),
                                json.dumps([{"target": target, "buildSettings": None}])):
                    def commands(args, **kwargs):
                        actual = args[args.index("-target") + 1] if "-target" in args else "Runner"
                        return payload if actual == target else self.fixture_commands(rows)(args)
                    with self.subTest(kind=kind, target=target, payload=payload), patch.object(
                            build, "default_derived_data_dir", return_value=derived), patch.object(
                            build, "command", side_effect=commands), self.assertRaises(ValueError):
                        build.cargokit_context(binding)

    def test_optional_metadata_absent_then_matching_postbuild(self):
        for kind in ("ipa", "development-app"):
            binding, derived, rows = self.cargokit_fixture(kind)
            context = self.query_fixture(binding, derived, rows, require_fresh=True)
            root = binding.roots["OBJROOT"].parent
            self.assertFalse((root / "info.plist").exists())
            root.mkdir(parents=True)
            (root / "info.plist").write_bytes(plistlib.dumps({"WorkspacePath": context["workspace"]}))
            self.output_files(context)
            self.capture_fixture(binding, derived, rows, context)

    def test_existing_metadata_malformed_foreign_empty_nonregular_and_redirected_fails(self):
        for kind in ("ipa", "development-app"):
            for role in ("boundary", "obj", "sym", "default"):
                if role == "default" and kind != "ipa":
                    continue
                binding, derived, rows = self.cargokit_fixture(kind)
                context = self.query_fixture(binding, derived, rows, require_fresh=True)
                root = {"boundary": binding.roots["OBJROOT"].parent, "obj": binding.roots["OBJROOT"],
                        "sym": binding.roots["SYMROOT"], "default": derived / "Runner-bound"}[role]
                root.mkdir(parents=True, exist_ok=True)
                metadata = root / "info.plist"
                for data in (b"", b"not plist", plistlib.dumps(["invalid"]),
                             plistlib.dumps({"WorkspacePath": "/foreign"})):
                    metadata.write_bytes(data)
                    with self.subTest(kind=kind, role=role, data=data), self.assertRaises(ValueError):
                        self.query_fixture(binding, derived, rows)
                    with self.assertRaises(ValueError):
                        self.capture_fixture(binding, derived, rows, context)
                metadata.unlink()
                metadata.mkdir()
                with self.assertRaises(ValueError):
                    self.query_fixture(binding, derived, rows)
                metadata.rmdir()
                metadata.symlink_to(root / "missing.plist")
                with self.assertRaises(ValueError):
                    self.query_fixture(binding, derived, rows)

    def test_cargokit_rejects_changed_postflight_before_hash(self):
        for kind in ("ipa", "development-app"):
            binding, derived, rows = self.cargokit_fixture(kind)
            context = self.query_fixture(binding, derived, rows, require_fresh=True)
            self.output_files(context)
            for target, fields in rows.items():
                for key, original in list(fields.items()):
                    fields[key] = "/foreign"
                    with self.subTest(kind=kind, target=target, key=key), patch.object(
                            build, "sha", side_effect=AssertionError("hash before context")), self.assertRaises(ValueError):
                        self.capture_fixture(binding, derived, rows, context)
                    fields[key] = original
            with self.assertRaisesRegex(ValueError, "mutable"):
                self.capture_fixture(binding, derived, rows, dict(context))
            changed = build.MappingProxyType(dict(context, kind="different"))
            with self.assertRaisesRegex(ValueError, "changed"):
                self.capture_fixture(binding, derived, rows, changed)

    def test_cargokit_rejects_redirected_roots_and_output_paths(self):
        for kind in ("ipa", "development-app"):
            for role in ("obj", "sym", "library", "archive"):
                binding, derived, rows = self.cargokit_fixture(kind)
                context = self.query_fixture(binding, derived, rows, require_fresh=True)
                path = {"obj": binding.roots["OBJROOT"], "sym": binding.roots["SYMROOT"],
                        "library": Path(context["cargokit_static_library"]),
                        "archive": Path(context["xcode_pod_archive"])}[role]
                path.parent.mkdir(parents=True, exist_ok=True)
                path.symlink_to(binding.app / "missing")
                with self.subTest(kind=kind, role=role), self.assertRaisesRegex(ValueError, "redirected"):
                    self.query_fixture(binding, derived, rows, require_fresh=True)
                with self.assertRaises(ValueError):
                    self.capture_fixture(binding, derived, rows, context)

    def test_each_exact_output_is_required_to_be_fresh(self):
        for kind in ("ipa", "development-app"):
            for name in ("cargokit_static_library", "xcode_pod_archive"):
                binding, derived, rows = self.cargokit_fixture(kind)
                context = self.query_fixture(binding, derived, rows)
                path = Path(context[name])
                path.parent.mkdir(parents=True)
                path.write_bytes(b"stale")
                with self.assertRaisesRegex(ValueError, "preexisting"):
                    self.query_fixture(binding, derived, rows, require_fresh=True)

    def test_output_missing_nonregular_empty_and_each_abi_is_required(self):
        for kind in ("ipa", "development-app"):
            for name in ("cargokit_static_library", "xcode_pod_archive"):
                binding, derived, rows = self.cargokit_fixture(kind)
                context = self.query_fixture(binding, derived, rows, require_fresh=True)
                self.output_files(context)
                path = Path(context[name])
                path.unlink()
                for bad in ("missing", "empty", "directory", "fifo"):
                    if bad == "fifo" and not hasattr(build.os, "mkfifo"):
                        continue  # POSIX-only subcase; retain other controls on Windows.
                    if bad == "empty":
                        path.write_bytes(b"")
                    elif bad == "directory":
                        path.mkdir()
                    elif bad == "fifo":
                        build.os.mkfifo(path)
                    with self.subTest(kind=kind, name=name, bad=bad), self.assertRaisesRegex(ValueError, "missing, empty or nonregular"):
                        self.capture_fixture(binding, derived, rows, context)
                    if path.exists():
                        path.rmdir() if path.is_dir() else path.unlink()
                self.output_files(context)
                for missing in build.EXPORTS:
                    def commands(args, **kwargs):
                        if args[0] == "nm" and args[-1] == str(path):
                            return "\n".join(f"00001 T {s}" for s in build.EXPORTS if s != missing)
                        return self.fixture_commands(rows)(args, **kwargs)
                    with patch.object(build, "default_derived_data_dir", return_value=derived), patch.object(
                            build, "command", side_effect=commands), self.assertRaisesRegex(ValueError, "ABI"):
                        build.capture_cargokit(binding, context)

    def bundle_fixture(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        runner = Path(temp.name) / "Runner.app"
        entries = [(runner, "chat.intergalactic.app"),
                   (runner / "PlugIns/Broadcast.appex", "chat.intergalactic.app.broadcast"),
                   (runner / "PlugIns/Share.appex", "chat.intergalactic.app.share"),
                   (runner / "PlugIns/InterGalactic Notification Extension.appex", "chat.intergalactic.app.nse")]
        for path, identity in entries:
            path.mkdir(parents=True)
            (path / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": identity,
                "CFBundleShortVersionString": "0.8.2", "CFBundleVersion": "1008", "CFBundleExecutable": "binary"}))
            (path / "binary").write_bytes(b"\xcf\xfa\xed\xfecontents")
        return runner

    @staticmethod
    def apple_command(args, **kwargs):
        if args[0] == "nm":
            return "\n".join(f"00001 T {symbol}" for symbol in build.EXPORTS)
        if "--entitlements" in args:
            identity = plistlib.loads((Path(args[-1]) / "Info.plist").read_bytes())["CFBundleIdentifier"]
            return plistlib.dumps({"com.apple.security.application-groups": ["group.chat.intergalactic.app"],
                                   "com.apple.developer.team-identifier": "TESTTEAM",
                                   "application-identifier": f"TESTTEAM.{identity}",
                                   "aps-environment": "production", "get-task-allow": False}).decode()
        return ""

    def test_bundle_receipt_requires_three_known_extensions_and_matching_versions(self):
        runner = self.bundle_fixture()
        with patch.object(build, "command", side_effect=self.apple_command):
            self.assertEqual(len(build.capture_bundle(runner, "0.8.2+1008")), 4)
            with self.assertRaisesRegex(ValueError, "version"):
                build.capture_bundle(runner, "0.8.2+9999")
            extra = runner / "PlugIns/Unexpected.appex"
            extra.mkdir()
            with self.assertRaisesRegex(ValueError, "exactly"):
                build.capture_bundle(runner, "0.8.2+1008")

    def test_missing_e8_export_fails_bundle_capture(self):
        runner = self.bundle_fixture()
        def missing(args, **kwargs):
            return "00001 T _ios_decrypt_backup_event_v1" if args[0] == "nm" else self.apple_command(args)
        with patch.object(build, "command", side_effect=missing):
            with self.assertRaisesRegex(ValueError, "ABI"):
                build.capture_bundle(runner, "0.8.2+1008")

    def test_renamed_notification_extension_still_requires_e8_exports(self):
        runner = self.bundle_fixture()
        original = runner / "PlugIns/InterGalactic Notification Extension.appex"
        renamed = runner / "PlugIns/Notifications.appex"
        original.rename(renamed)
        with patch.object(build, "command", side_effect=self.apple_command) as command:
            self.assertEqual(len(build.capture_bundle(runner, "0.8.2+1008")), 4)
            command.assert_any_call(["nm", "-g", str(renamed / "binary")])
        def missing(args, **kwargs):
            return "" if args[0] == "nm" else self.apple_command(args)
        with patch.object(build, "command", side_effect=missing):
            with self.assertRaisesRegex(ValueError, "ABI"):
                build.capture_bundle(runner, "0.8.2+1008")

    def test_source_packet_excludes_python_runtime_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app, source, output = root / "app", root / "source", root / "output"
            recipe = app / build.RECIPE
            (recipe / "__pycache__").mkdir(parents=True)
            (recipe / "__pycache__/prepare.pyc").write_bytes(b"runtime")
            (recipe / "prepare.py").write_text("# tracked source\n")
            (app / "intergalactic/ios/build-config").mkdir()
            (app / "intergalactic/ios/scripts").mkdir()
            (app / "intergalactic/ios/scripts/build_ipa.py").write_text("# source\n")
            output.mkdir()
            def archive(repo, ref, path):
                path.write_bytes(b"archive")
            with patch.object(build, "archive_git", side_effect=archive), patch.object(build, "command", return_value="tree"):
                hashes = build.capture_packet(app, source, output, COMMIT, CONFIG)
            self.assertIn("recipe/prepare.py", hashes)
            self.assertFalse(any("__pycache__" in name or name.endswith(".pyc") for name in hashes))


class SymbolTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.output = Path(temp.name).resolve()
        self.app = self.output / "prepared/app"
        self.app.mkdir(parents=True)
        self.binding = build.XcodeBinding(self.app, "ipa", {})
        self.archive = self.app / "intergalactic/build/ios/archive/Runner.xcarchive"
        self.runner = self.archive / "Products/Applications/Runner.app"
        self.exported = self.output / "exported-bootstrap/Payload/Runner.app"
        self.products = self.binding.roots["SYMROOT"] / "Release-iphoneos"
        self.products.mkdir(parents=True)
        specs = [("", "chat.intergalactic.app", "Runner"),
                 ("PlugIns/Notifications.appex", "chat.intergalactic.app.nse", "NSE"),
                 ("PlugIns/Broadcast.appex", "chat.intergalactic.app.broadcast", "Broadcast"),
                 ("PlugIns/Share.appex", "chat.intergalactic.app.share", "Share"),
                 ("Frameworks/App.framework", "io.flutter.flutter.app", "App"),
                 ("Frameworks/Flutter.framework", "io.flutter.flutter", "Flutter")]
        self.sources = []
        for relative, identity, executable in specs:
            bundle = self.runner / relative
            bundle.mkdir(parents=True)
            (bundle / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": identity,
                "CFBundleExecutable": executable, "CFBundleVersion": "1008", "CFBundleShortVersionString": "0.8.2"}))
            (bundle / executable).write_bytes(executable.encode() + b"|binary")
            source = self.products / (bundle.name + ".dSYM")
            dwarf = source / "Contents/Resources/DWARF" / executable
            dwarf.parent.mkdir(parents=True)
            dwarf.write_bytes(executable.encode() + b"|dwarf")
            (source / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundlePackageType": "dSYM"}))
            self.sources.append((source, dwarf))
        shutil.copytree(self.runner, self.exported)
        (self.archive / "Info.plist").write_bytes(plistlib.dumps({"ApplicationProperties": {"ApplicationPath": "Applications/Runner.app"}}))
        (self.archive / "dSYMs").mkdir()
        self.bootstrap_path = self.app / "intergalactic/build/ios/ipa/bootstrap.ipa"
        self.bootstrap_path.parent.mkdir(parents=True)
        self.bootstrap_path.write_bytes(b"diagnostic IPA")
        self.bootstrap = {"ipa": {"path": str(self.bootstrap_path.relative_to(self.output)),
                                  "sha256": build.sha(self.bootstrap_path), "bytes": self.bootstrap_path.stat().st_size}}
        self.options = self.bootstrap_path.parent / "ExportOptions.plist"
        self.options.write_bytes(plistlib.dumps({"method": "app-store-connect", "destination": "export",
                                                "uploadSymbols": True, "stripSwiftSymbols": True}))
        self.command_patch = patch.object(build, "command", side_effect=self.commands)
        self.command_patch.start()
        self.addCleanup(self.command_patch.stop)

    def commands(self, args, **kwargs):
        if args[:3] == ["xcrun", "dwarfdump", "--uuid"]:
            seed = Path(args[-1]).read_bytes().split(b"|")[0].decode()
            value = str(uuid.uuid5(uuid.NAMESPACE_URL, seed)).upper()
            return f"UUID: {value} (arm64) {args[-1]}"
        return IpaBuildTests.apple_command(args, **kwargs)

    def snapshot(self):
        return build.symbol_snapshot(self.binding, self.output, "0.8.2+1008", self.bootstrap)

    def symbols_zip(self, path, symbols, *, defect=None):
        with zipfile.ZipFile(path, "w") as archive:
            names = [f"Symbols/{row['uuid']}.symbols" for row in symbols.data["archived"].values()]
            if defect == "missing":
                names.pop()
            if defect == "foreign":
                names[-1] = "Symbols/foreign.symbols"
            for i, name in enumerate(names):
                info = zipfile.ZipInfo(name)
                if defect == "symlink" and i == 0:
                    info.external_attr = (stat.S_IFLNK | 0o777) << 16
                archive.writestr(info, b"" if defect == "empty" and i == 0 else b"symbol data")
            if defect == "extra":
                archive.writestr("Symbols/extra.symbols", b"extra")
            if defect == "duplicate":
                import warnings
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore", UserWarning)
                    archive.writestr(names[0], b"duplicate")

    def test_failure_first_empty_archive_cannot_pass_and_positive_exact_gather(self):
        symbols = self.snapshot()
        with self.assertRaisesRegex(ValueError, "incomplete"):
            build.validate_symbol_binding(self.binding, symbols, gathered=True)
        build.gather_symbols(self.binding, symbols)
        build.validate_symbol_binding(self.binding, symbols, gathered=True)
        build.gather_symbols(self.binding, symbols)  # exact same-plan retry
        self.assertEqual(len(list((self.archive / "dSYMs").iterdir())), 6)
        self.assertEqual(build.sha(self.bootstrap_path), self.bootstrap["ipa"]["sha256"])

    def test_uuid_is_dynamic_and_renamed_nse_is_bound(self):
        first = self.snapshot()
        paths = [self.runner / "Runner", self.exported / "Runner", self.sources[0][1]]
        for path in paths:
            path.write_bytes(b"new invocation|contents")
        second = self.snapshot()
        self.assertNotEqual(first.data["archived"]["chat.intergalactic.app"]["uuid"], second.data["archived"]["chat.intergalactic.app"]["uuid"])
        self.assertEqual(second.data["archived"]["chat.intergalactic.app.nse"]["dsym"], "Notifications.appex.dSYM")

    def test_each_source_missing_empty_malformed_uuid_and_nonregular_fails(self):
        for source, dwarf in self.sources:
            original = dwarf.read_bytes()
            for defect in ("missing", "empty", "uuid", "fifo", "directory", "symlink"):
                if defect == "fifo" and not hasattr(build.os, "mkfifo"):
                    continue
                with self.subTest(source=source.name, defect=defect):
                    dwarf.unlink()
                    if defect == "empty":
                        dwarf.write_bytes(b"")
                    elif defect == "uuid":
                        dwarf.write_bytes(b"wrong|contents")
                    elif defect == "fifo":
                        build.os.mkfifo(dwarf)
                    elif defect == "directory":
                        dwarf.mkdir()
                    elif defect == "symlink":
                        dwarf.symlink_to(self.runner / "Runner")
                    with self.assertRaises((ValueError, OSError)):
                        self.snapshot()
                    if dwarf.is_dir():
                        dwarf.rmdir()
                    elif dwarf.exists() or dwarf.is_symlink():
                        dwarf.unlink()
                    dwarf.write_bytes(original)
            info = source / "Contents/Info.plist"
            contents = info.read_bytes()
            info.write_bytes(plistlib.dumps({"CFBundlePackageType": "wrong"}))
            with self.assertRaises(ValueError):
                self.snapshot()
            info.write_bytes(contents)

    def test_extra_and_renamed_source_and_dwarf_rejected(self):
        source, dwarf = self.sources[0]
        extra = self.products / "Unexpected.dSYM"
        extra.mkdir()
        with self.assertRaisesRegex(ValueError, "foreign"):
            self.snapshot()
        extra.rmdir()
        wrong = dwarf.with_name("wrong")
        dwarf.rename(wrong)
        with self.assertRaises(ValueError):
            self.snapshot()
        wrong.rename(dwarf)
        extra = dwarf.with_name("extra")
        extra.write_bytes(b"extra")
        with self.assertRaises(ValueError):
            self.snapshot()

    def test_wrong_duplicate_and_nonarm64_uuid_output_rejected(self):
        for text in ("", "malformed", "UUID: 00000000-0000-0000-0000-000000000000 (x86_64) binary",
                     "UUID: 00000000-0000-0000-0000-000000000000 (arm64) binary\n" * 2):
            with self.subTest(text=text), patch.object(build, "command", return_value=text), self.assertRaises(ValueError):
                build.binary_uuid(self.runner / "Runner")
        with patch.object(build, "binary_uuid", return_value="same"), self.assertRaisesRegex(ValueError, "duplicate"):
            self.snapshot()

    def test_full_binding_rechecked_after_copy_and_before_export(self):
        symbols = self.snapshot()
        paths = [self.runner / "Runner", self.exported / "Runner", self.sources[0][1],
                 self.sources[0][0] / "Contents/Info.plist", self.archive / "Info.plist", self.bootstrap_path]
        for path in paths:
            original = path.read_bytes()
            path.write_bytes(original + b"|changed")
            with self.subTest(path=path), self.assertRaises((ValueError, OSError, plistlib.InvalidFileException)):
                build.validate_symbol_binding(self.binding, symbols)
            path.write_bytes(original)
        with self.assertRaisesRegex(ValueError, "foreign"):
            build.validate_symbol_binding(build.XcodeBinding(self.output, "ipa", {}), symbols)
        with self.assertRaisesRegex(ValueError, "foreign"):
            build.validate_symbol_binding(self.binding, object())

    def test_unknown_destination_and_conflicting_retry_do_not_overwrite(self):
        symbols = self.snapshot()
        destination = self.archive / "dSYMs"
        unexpected = destination / "unknown"
        unexpected.write_bytes(b"preserve")
        with self.assertRaisesRegex(ValueError, "unknown"):
            build.gather_symbols(self.binding, symbols)
        self.assertEqual(unexpected.read_bytes(), b"preserve")
        unexpected.unlink()
        build.gather_symbols(self.binding, symbols)
        copied = destination / self.sources[0][0].name / "Contents/Resources/DWARF/Runner"
        copied.write_bytes(b"conflicting")
        with self.assertRaisesRegex(ValueError, "conflicting"):
            build.gather_symbols(self.binding, symbols)
        self.assertEqual(copied.read_bytes(), b"conflicting")

    def test_interruption_before_copy_has_exact_bounded_retry(self):
        symbols = self.snapshot()
        original = build.shutil.copyfileobj
        calls = 0
        def interrupted(src, dst):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError("interrupted")
            original(src, dst)
        with patch.object(build.shutil, "copyfileobj", side_effect=interrupted), self.assertRaises(OSError):
            build.gather_symbols(self.binding, symbols)
        # A partially written/empty file is deliberately NOT adopted or truncated.
        with self.assertRaises(ValueError):
            build.gather_symbols(self.binding, symbols)
        self.assertFalse((self.output / "final-export").exists())

    def test_retry_complete_known_subset_succeeds_but_marker_or_extra_fails(self):
        symbols = self.snapshot()
        (self.output / "symbol-gather.json").write_text(symbols.snapshot)
        source = self.sources[0][0]
        shutil.copytree(source, self.archive / "dSYMs" / source.name)
        build.gather_symbols(self.binding, symbols)
        extra = self.archive / "dSYMs/foreign"
        extra.mkdir()
        with self.assertRaisesRegex(ValueError, "foreign"):
            build.gather_symbols(self.binding, symbols)
        extra.rmdir()
        (self.output / "symbol-gather.json").write_text("foreign")
        with self.assertRaisesRegex(ValueError, "foreign"):
            build.gather_symbols(self.binding, symbols)

    def test_redirected_destination_source_marker_or_descendant_fails(self):
        for role in ("destination", "source", "marker", "descendant"):
            symbols = self.snapshot()
            path = {"destination": self.archive / "dSYMs", "source": self.sources[0][0],
                    "marker": self.output / "symbol-gather.json", "descendant": self.sources[0][1]}[role]
            backup = path.with_name(path.name + ".backup")
            if path.exists():
                path.rename(backup)
            path.symlink_to(backup)
            with self.subTest(role=role), self.assertRaises((ValueError, OSError)):
                build.gather_symbols(self.binding, symbols)
            path.unlink()
            if backup.exists():
                backup.rename(path)

    def test_final_coverage_requires_exact_six_nonempty_regular_records(self):
        symbols = self.snapshot()
        ipa = self.output / "test.ipa"
        for defect in ("missing", "empty", "foreign", "extra", "duplicate", "symlink"):
            self.symbols_zip(ipa, symbols, defect=defect)
            with self.subTest(defect=defect), self.assertRaisesRegex(ValueError, "coverage"):
                build.final_symbol_coverage(ipa, symbols, self.exported)
        self.symbols_zip(ipa, symbols)
        self.assertEqual(len(build.final_symbol_coverage(ipa, symbols, self.exported)), 6)
        (self.exported / "Runner").write_bytes(b"foreign|binary")
        with self.assertRaisesRegex(ValueError, "binding"):
            build.final_symbol_coverage(ipa, symbols, self.exported)

    def test_options_do_not_allow_upload_or_disabling_selected_symbol_intent(self):
        original = plistlib.loads(self.options.read_bytes())
        for key, value in (("destination", "upload"), ("method", "debugging"),
                           ("uploadSymbols", False), ("stripSwiftSymbols", False)):
            self.options.write_bytes(plistlib.dumps(dict(original, **{key: value})))
            with self.assertRaisesRegex(ValueError, "semantics"):
                build.export_options(self.options, "app-store")
        self.options.write_bytes(plistlib.dumps(original))

    def finish_fixture(self, *, failure=None, method="app-store"):
        symbols = self.snapshot()
        receipt = self.output / "receipt.json"
        plan = {"status": "pending", "source_commit": COMMIT}
        def capture(app, output, version, kind, method, **kwargs):
            if kwargs["extraction_name"] == "exported-bootstrap":
                return self.bootstrap
            self.assertEqual(kwargs["ipa_dir"], self.output / "final-export")
            if failure == "signature":
                raise ValueError("final signature/notice gate failed")
            paths = list(kwargs["ipa_dir"].glob("*.ipa"))
            if len(paths) != 1:
                raise ValueError("unique final IPA required")
            shutil.copytree(self.exported, self.output / "exported-final/Payload/Runner.app")
            return {"ipa": {"path": str(paths[0].relative_to(output)), "sha256": build.sha(paths[0])}}
        def commands(args, **kwargs):
            if args[:2] == ["xcodebuild", "-exportArchive"]:
                self.assertIs(kwargs["env"], self.binding.env)
                self.assertEqual(args[args.index("-archivePath") + 1], str(self.archive))
                self.assertNotIn("upload", args)
                build.validate_symbol_binding(self.binding, symbols, gathered=True)
                if failure == "export":
                    raise ValueError("export failed")
                final = Path(args[args.index("-exportPath") + 1])
                if method == "app-store":
                    self.symbols_zip(final / "final.ipa", symbols, defect="missing" if failure == "coverage" else None)
                else:
                    with zipfile.ZipFile(final / "final.ipa", "w") as archive:
                        archive.writestr("Payload/diagnostic-fixture", b"no IPA Symbols")
                if failure == "ambiguous":
                    shutil.copyfile(final / "final.ipa", final / "extra.ipa")
                return ""
            return self.commands(args, **kwargs)
        count = 0
        def postflight():
            nonlocal count
            count += 1
            if failure == "before-export" and count == 2:
                (self.sources[0][1]).write_bytes(b"Runner|changed")
            if failure == "postflight" and count == 3:
                raise ValueError("source/root/define gate failed")
        with patch.object(build, "capture_artifact", side_effect=capture), patch.object(build, "command", side_effect=commands):
            result = build.finish_ipa(self.binding, self.output, "0.8.2+1008", method, plan, receipt, postflight)
        self.assertEqual(count, 4)
        self.assertIn("final-export", result["ipa"]["path"])
        self.assertEqual(len(plan["final_symbols"]), 6 if method == "app-store" else 0)
        self.assertEqual(plan["ipa_symbol_coverage_required"], method == "app-store")
        self.assertNotIn("artifact", json.loads(receipt.read_text()))
        self.assertIn("pending", json.loads(receipt.read_text())["status"])
        return result

    def test_final_local_export_selects_only_final_and_never_stamps_success(self):
        self.finish_fixture()

    def sparse_app(self):
        source = self.products / "App.framework.dSYM"
        (source / "Contents/Info.plist").unlink()
        return source

    def test_sparse_flutter_app_completes_snapshot_gather_and_finish(self):
        self.sparse_app()
        symbols = self.snapshot()
        app = symbols.data["symbols"]["io.flutter.flutter.app"]
        self.assertNotIn("Contents/Info.plist", app["tree"])
        self.finish_fixture()
        self.assertFalse((self.archive / "dSYMs/App.framework.dSYM/Contents/Info.plist").exists())

    def test_missing_metadata_remains_failure_for_all_other_five_symbols(self):
        for source, _ in self.sources:
            if source.name == "App.framework.dSYM":
                continue
            path = source / "Contents/Info.plist"
            original = path.read_bytes()
            path.unlink()
            with self.subTest(source=source.name), self.assertRaises((ValueError, OSError)):
                self.snapshot()
            path.write_bytes(original)

    def test_optional_app_metadata_is_strict_and_not_a_redirect_exception(self):
        path = self.products / "App.framework.dSYM/Contents/Info.plist"
        original = path.read_bytes()
        for value in (b"", b"not a plist", plistlib.dumps([]), plistlib.dumps({"CFBundlePackageType": "wrong"})):
            path.write_bytes(value)
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.snapshot()
        path.unlink()
        for target in (self.output / "missing", self.sources[0][0] / "Contents/Info.plist"):
            path.symlink_to(target)
            with self.subTest(target=target), self.assertRaises(ValueError):
                self.snapshot()
            path.unlink()
        path.write_bytes(original)
        self.snapshot()

    def test_sparse_app_only_exact_tree_and_one_nonempty_arm64_dwarf(self):
        source = self.sparse_app()
        dwarf = source / "Contents/Resources/DWARF/App"
        original = dwarf.read_bytes()
        for defect in ("extra", "extra-directory", "wrong-name", "empty", "wrong-uuid", "symlink", "dangling"):
            with self.subTest(defect=defect):
                if defect == "extra":
                    extra = source / "extra"
                    extra.write_bytes(b"extra")
                elif defect == "extra-directory":
                    extra = source / "extra"
                    extra.mkdir()
                elif defect == "wrong-name":
                    dwarf.rename(dwarf.with_name("wrong"))
                elif defect == "empty":
                    dwarf.write_bytes(b"")
                elif defect == "wrong-uuid":
                    dwarf.write_bytes(b"wrong|dwarf")
                elif defect in ("symlink", "dangling"):
                    dwarf.unlink()
                    dwarf.symlink_to(self.output / "missing" if defect == "dangling" else self.runner / "Frameworks/App.framework/App")
                with self.assertRaises((ValueError, OSError)):
                    self.snapshot()
                if defect in ("extra", "extra-directory"):
                    extra.rmdir() if extra.is_dir() else extra.unlink()
                elif defect == "wrong-name":
                    dwarf.with_name("wrong").rename(dwarf)
                else:
                    if dwarf.is_symlink():
                        dwarf.unlink()
                    dwarf.write_bytes(original)

    def test_app_metadata_appearance_and_disappearance_change_snapshot_binding(self):
        path = self.products / "App.framework.dSYM/Contents/Info.plist"
        full = self.snapshot()
        original = path.read_bytes()
        path.unlink()
        with self.assertRaisesRegex(ValueError, "binding changed"):
            build.validate_symbol_binding(self.binding, full)
        sparse = self.snapshot()
        path.write_bytes(original)
        with self.assertRaisesRegex(ValueError, "binding changed"):
            build.validate_symbol_binding(self.binding, sparse)

    def test_development_and_ad_hoc_export_without_ipa_symbols(self):
        for method, native_method in (("development", "debugging"), ("ad-hoc", "release-testing")):
            for upload_symbols in (None, False, True):
                with self.subTest(method=method, upload_symbols=upload_symbols):
                    self.setUp()
                    options = {"method": native_method, "destination": "export", "stripSwiftSymbols": True}
                    if upload_symbols is not None:
                        options["uploadSymbols"] = upload_symbols
                    self.options.write_bytes(plistlib.dumps(options))
                    result = self.finish_fixture(method=method)
                    self.assertEqual(len(list((self.archive / "dSYMs").iterdir())), 6)
                    with zipfile.ZipFile(self.output / result["ipa"]["path"]) as archive:
                        self.assertFalse(any(p.startswith("Symbols/") for p in archive.namelist()))

    def test_non_store_modes_still_fail_binary_signature_source_and_local_option_gates(self):
        for method, native_method in (("development", "debugging"), ("ad-hoc", "release-testing")):
            for failure in ("signature", "postflight", "before-export"):
                with self.subTest(method=method, failure=failure):
                    self.setUp()
                    self.options.write_bytes(plistlib.dumps({"method": native_method, "destination": "export"}))
                    with self.assertRaises(ValueError):
                        self.finish_fixture(method=method, failure=failure)
                    self.assertIn("pending", json.loads((self.output / "receipt.json").read_text())["status"])
            options = {"method": native_method, "destination": "upload", "uploadSymbols": False}
            self.options.write_bytes(plistlib.dumps(options))
            with self.assertRaisesRegex(ValueError, "semantics"):
                build.export_options(self.options, method)

    def test_non_store_final_binary_binding_is_checked_without_symbol_records(self):
        symbols = self.snapshot()
        ipa = self.output / "no-symbols.ipa"
        with zipfile.ZipFile(ipa, "w") as archive:
            archive.writestr("Payload/fixture", b"fixture")
        for method in ("development", "ad-hoc"):
            self.assertEqual(build.final_symbol_coverage(ipa, symbols, self.exported, method), {})
        (self.exported / "Runner").write_bytes(b"foreign|binary")
        for method in ("development", "ad-hoc"):
            with self.assertRaisesRegex(ValueError, "binding"):
                build.final_symbol_coverage(ipa, symbols, self.exported, method)

    def test_every_final_boundary_failure_retains_pending_receipt(self):
        for failure in ("export", "coverage", "ambiguous", "signature", "postflight", "before-export"):
            with self.subTest(failure=failure):
                self.setUp()
                with self.assertRaises(ValueError):
                    self.finish_fixture(failure=failure)
                receipt = json.loads((self.output / "receipt.json").read_text())
                self.assertIn("pending", receipt["status"])
                self.assertNotIn("artifact", receipt)

    def test_gathered_tree_is_revalidated_not_just_its_count(self):
        symbols = self.snapshot()
        build.gather_symbols(self.binding, symbols)
        for source, _ in self.sources:
            info = self.archive / "dSYMs" / source.name / "Contents/Info.plist"
            original = info.read_bytes()
            info.write_bytes(original + b"changed")
            with self.subTest(source=source.name), self.assertRaisesRegex(ValueError, "tree changed"):
                build.validate_symbol_binding(self.binding, symbols, gathered=True)
            info.write_bytes(original)

    def test_unknown_final_destination_is_preserved_without_export(self):
        final = self.output / "final-export"
        final.mkdir()
        existing = final / "keep.ipa"
        existing.write_bytes(b"preserve")
        with self.assertRaisesRegex(ValueError, "fresh"):
            self.finish_fixture()
        self.assertEqual(existing.read_bytes(), b"preserve")

    def test_unsafe_binary_basename_and_archive_identity_fail(self):
        info = self.runner / "Info.plist"
        original = plistlib.loads(info.read_bytes())
        for value in ("../Runner", "", ".", "..", ["Runner"]):
            info.write_bytes(plistlib.dumps(dict(original, CFBundleExecutable=value)))
            with self.subTest(value=value), self.assertRaises((ValueError, TypeError)):
                build.symbol_binaries(self.runner)
        info.write_bytes(plistlib.dumps(original))
        (self.archive / "Info.plist").write_bytes(plistlib.dumps({"ApplicationProperties": {"ApplicationPath": "foreign"}}))
        with self.assertRaisesRegex(ValueError, "identity"):
            self.snapshot()


if __name__ == "__main__":
    unittest.main()
