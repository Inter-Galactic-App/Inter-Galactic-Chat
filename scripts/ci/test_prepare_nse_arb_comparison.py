#!/usr/bin/env python3
"""Focused positive and negative controls for the NSE-only ARB exemption."""

import runpy
import unittest
from unittest.mock import patch

from prepare_nse_arb_comparison import (
    GENERATOR,
    NSE_ONLY_KEYS,
    ROOT,
    nse_keys,
    prepare,
    read_arb,
)


class NseArbComparisonTests(unittest.TestCase):
    def setUp(self):
        self.keys = nse_keys()
        self.assertEqual(self.keys, NSE_ONLY_KEYS)
        self.committed = {"ordinary": "Dart message", "@ordinary": {"description": "Dart"}}
        self.generator_keys = set(runpy.run_path(str(GENERATOR))["KEYS"].values())
        self.assertEqual(len(self.generator_keys), 6)
        for key in self.generator_keys:
            self.committed[key] = f"English {key}"
            self.committed[f"@{key}"] = {"description": "NSE"}

    def test_only_wholly_absent_nse_pairs_are_omitted(self):
        absent = {"notificationAttachmentSentAudio", "notificationAttachmentSharedLocation"}
        self.assertEqual(absent, self.keys)
        extracted = {key: value for key, value in self.committed.items()
                     if key not in absent and not (key.startswith("@") and key[1:] in absent)}
        prepared, omitted = prepare(self.committed, extracted, self.keys)
        self.assertEqual(prepared, extracted)
        self.assertEqual(set(omitted), absent)
        self.assertEqual(len([key for key in self.generator_keys if key in prepared]), 4)

    def test_dual_use_nse_message_remains_gated_if_dart_drops_it(self):
        dual_use = next(iter(self.generator_keys - self.keys))
        extracted = {key: value for key, value in self.committed.items()
                     if key not in {dual_use, f"@{dual_use}"}}
        prepared, omitted = prepare(self.committed, extracted, self.keys)
        self.assertIn(dual_use, prepared)
        self.assertIn(f"@{dual_use}", prepared)
        self.assertNotIn(dual_use, omitted)

    def test_unrelated_stale_and_changed_messages_stay_visible(self):
        extracted = {"ordinary": "Changed", "newDartMessage": "New"}
        prepared, _ = prepare(self.committed, extracted, self.keys)
        self.assertIn("ordinary", prepared)
        self.assertEqual(prepared["ordinary"], "Dart message")
        self.assertIn("@ordinary", prepared)
        self.assertNotIn("newDartMessage", prepared)

    def test_partial_nse_pair_is_not_exempt(self):
        key = "notificationAttachmentSentAudio"
        prepared, omitted = prepare(self.committed, {f"@{key}": {}}, self.keys)
        self.assertNotIn(key, omitted)
        self.assertIn(key, prepared)
        self.assertIn(f"@{key}", prepared)

    def test_missing_committed_nse_message_fails_closed(self):
        self.committed.pop("notificationAttachmentSharedLocation")
        with self.assertRaisesRegex(ValueError, "no usable NSE message"):
            prepare(self.committed, {}, self.keys)

    def test_missing_committed_nse_metadata_fails_closed(self):
        self.committed.pop("@notificationAttachmentSentAudio")
        with self.assertRaisesRegex(ValueError, "no NSE metadata"):
            prepare(self.committed, {}, self.keys)

    def test_generator_mapping_must_still_require_both_nse_only_messages(self):
        with patch("prepare_nse_arb_comparison.runpy.run_path", return_value={
            "KEYS": {f"nse.body.{index}": f"other{index}" for index in range(6)}
        }):
            with self.assertRaisesRegex(ValueError, "no longer in the generator"):
                nse_keys()

    def test_real_english_arb_keeps_both_nse_only_pairs(self):
        arb = read_arb(ROOT / "intergalactic/assets/l10n/intl_en.arb")
        extracted = {key: value for key, value in arb.items()
                     if key not in self.keys and not (key.startswith("@") and key[1:] in self.keys)}
        prepared, omitted = prepare(arb, extracted, self.keys)
        self.assertEqual(prepared, extracted)
        self.assertEqual(set(omitted), self.keys)


if __name__ == "__main__":
    unittest.main()
