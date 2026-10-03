"""Focused fail-closed tests for the isolated E8 package-resolution gate."""

import json
import os
import pathlib
import tempfile
import unittest
from unittest import mock

import prepare
import verify_ios_patch


class PackageResolutionTests(unittest.TestCase):
    def assert_resolution(self, flutter_source="path", flutter_version="0.5.0",
                          extra_flutter_fields=()):
        with tempfile.TemporaryDirectory() as root:
            root = pathlib.Path(root)
            app = root / "app"
            source = root / "source"
            (app / ".dart_tool").mkdir(parents=True)
            (source / "flutter").mkdir(parents=True)
            (source / "dart").mkdir()
            lock_text = (
                "packages:\n"
                "  flutter_vodozemac:\n"
                "    dependency: direct overridden\n"
                f"    source: {flutter_source}\n"
                f'    version: "{flutter_version}"\n'
            ) + "".join(f"    {field}\n" for field in extra_flutter_fields) + (
                "  vodozemac:\n"
                "    dependency: direct overridden\n"
                "    source: path\n"
                '    version: "0.5.0"\n'
                "sdks:\n"
                '  dart: ">=3.0.0"\n'
            )
            (app / "pubspec.lock").write_text(lock_text)
            (app / ".dart_tool/package_config.json").write_text(json.dumps({
                "packages": [
                    {"name": "flutter_vodozemac", "rootUri": (source / "flutter").as_uri()},
                    {"name": "vodozemac", "rootUri": (source / "dart").as_uri()},
                ]
            }))
            return prepare.assert_package_resolution(app, source)

    def test_both_path_resolved_packages_pass(self):
        self.assertIn("pubspec_lock_sha256", self.assert_resolution())

    def test_hosted_target_followed_by_path_package_fails(self):
        with self.assertRaisesRegex(SystemExit, "flutter_vodozemac.*source"):
            self.assert_resolution(flutter_source="hosted")

    def test_wrong_target_version_followed_by_correct_version_fails(self):
        with self.assertRaisesRegex(SystemExit, "flutter_vodozemac.*version"):
            self.assert_resolution(flutter_version="0.4.0")

    def test_duplicate_source_with_path_and_hosted_fails(self):
        with self.assertRaisesRegex(SystemExit, "flutter_vodozemac.*duplicate.*source"):
            self.assert_resolution(extra_flutter_fields=("source: hosted",))

    def test_duplicate_source_with_identical_values_fails(self):
        with self.assertRaisesRegex(SystemExit, "flutter_vodozemac.*duplicate.*source"):
            self.assert_resolution(extra_flutter_fields=("source: path",))

    def test_duplicate_version_with_correct_and_wrong_values_fails(self):
        with self.assertRaisesRegex(SystemExit, "flutter_vodozemac.*duplicate.*version"):
            self.assert_resolution(extra_flutter_fields=('version: "0.4.0"',))

    def test_ios_gate_requires_explicit_source_and_commit(self):
        with mock.patch.dict(os.environ, {}, clear=True):
            with self.assertRaisesRegex(SystemExit, "IG_E8_SOURCE.*IG_E8_APP_COMMIT"):
                verify_ios_patch.main()

    def test_ios_gate_rejects_missing_or_wrong_override(self):
        with tempfile.TemporaryDirectory() as root:
            app = pathlib.Path(root) / "app"
            source = pathlib.Path(root) / "source"
            app.mkdir()
            with self.assertRaisesRegex(SystemExit, "override missing"):
                verify_ios_patch.assert_override(app, source)
            override = app / "pubspec_overrides.yaml"
            override.write_text(verify_ios_patch.expected_override(source) + "# extra\n")
            with self.assertRaisesRegex(SystemExit, "override missing or differs"):
                verify_ios_patch.assert_override(app, source)
            override.write_text(verify_ios_patch.expected_override(source))
            verify_ios_patch.assert_override(app, source)

    def test_ios_inventory_variant_matches_tracked_source_manifest(self):
        manifest = json.loads(prepare.MANIFEST.read_text())
        inventory = json.loads(
            (prepare.APP_REPO / "docs/release/THIRD_PARTY_LICENSES.json").read_text()
        )
        rows = {row["name"]: row for row in inventory["dart_flutter_packages"]
                if row["name"] in ("flutter_vodozemac", "vodozemac")}
        self.assertEqual(set(rows), {"flutter_vodozemac", "vodozemac"})
        for row in rows.values():
            variant = row["ios_patched_variant"]
            self.assertEqual(variant["upstream_commit"], manifest["baseline_commit"])
            self.assertEqual(variant["patch_sha256"], manifest["patch_sha256"])
            self.assertEqual(variant["post_patch_tree"], manifest["patched_tree"])
            self.assertEqual(row["license_text_sha256"],
                             manifest["patched_files_sha256"]["LICENSE"])
            self.assertIn("dart-vodozemac-ios-patch/SOURCE.md", row["license_evidence_path"])


if __name__ == "__main__":
    unittest.main()
