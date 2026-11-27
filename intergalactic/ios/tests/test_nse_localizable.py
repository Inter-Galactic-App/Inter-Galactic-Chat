import json
import tempfile
import unittest
from pathlib import Path

from intergalactic.ios.scripts.generate_nse_localizable import KEYS, generate


class NSELocalizableTests(unittest.TestCase):
    def test_only_six_media_keys_and_missing_translation_falls_back(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "arb"
            source.mkdir()
            english = {key: f"English {key}" for key in KEYS.values()}
            english["unrelated"] = "must not enter extension"
            (source / "intl_en.arb").write_text(json.dumps(english), encoding="utf-8")
            (source / "intl_es.arb").write_text(
                json.dumps({"notificationAttachmentSentImage": "Imagen"}),
                encoding="utf-8",
            )
            written = generate(source, root / "bundle")
            self.assertEqual(len(written), 2)
            en = (root / "bundle/en.lproj/Localizable.strings").read_text()
            es = (root / "bundle/es.lproj/Localizable.strings").read_text()
            self.assertEqual(en.count(" = "), 6)
            self.assertNotIn("unrelated", en)
            self.assertIn('"nse.body.image" = "Imagen";', es)
            self.assertNotIn("nse.body.audio", es)

    def test_missing_english_source_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "arb"
            source.mkdir()
            english = {key: key for key in KEYS.values()}
            del english["notificationAttachmentSentAudio"]
            (source / "intl_en.arb").write_text(json.dumps(english), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "notificationAttachmentSentAudio"):
                generate(source, root / "bundle")

    def test_removed_and_empty_locales_drop_only_generated_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "arb"
            source.mkdir()
            bundle = root / "bundle"
            english = {key: key for key in KEYS.values()}
            (source / "intl_en.arb").write_text(json.dumps(english), encoding="utf-8")
            for locale in ("es", "fr"):
                (source / f"intl_{locale}.arb").write_text(
                    json.dumps({"notificationAttachmentSentImage": locale}),
                    encoding="utf-8",
                )
            generate(source, bundle)
            (source / "intl_es.arb").unlink()
            (source / "intl_fr.arb").write_text("{}", encoding="utf-8")
            unrelated = bundle / "de.lproj/Localizable.strings"
            unrelated.parent.mkdir()
            unrelated.write_bytes(b'"other.key" = "Keep me";\xff\n')

            written = generate(source, bundle)

            self.assertEqual(written, [bundle / "en.lproj/Localizable.strings"])
            self.assertFalse((bundle / "es.lproj/Localizable.strings").exists())
            self.assertFalse((bundle / "fr.lproj/Localizable.strings").exists())
            self.assertTrue(unrelated.exists())

    def test_real_arbs_generate_english_and_match_swift_defaults(self):
        root = Path(__file__).resolve().parents[2]
        with tempfile.TemporaryDirectory() as temporary:
            written = generate(root / "assets/l10n", Path(temporary))
            self.assertIn(Path(temporary) / "en.lproj/Localizable.strings", written)
            english = (Path(temporary) / "en.lproj/Localizable.strings").read_text()
            self.assertIn('"nse.body.audio" = "Sent an audio message";', english)

        source = json.loads((root / "assets/l10n/intl_en.arb").read_text())
        swift = (root / "ios/InterGalactic Notification Extension/NotificationService.swift").read_text()
        for native_key, arb_key in KEYS.items():
            self.assertIn(
                f'localizedBody("{native_key}", english: "{source[arb_key]}")',
                swift,
            )


if __name__ == "__main__":
    unittest.main()
