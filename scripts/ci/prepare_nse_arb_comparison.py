#!/usr/bin/env python3
"""Exclude only the two NSE-only messages from the Dart l10n comparison.

The iOS notification extension consumes these ARB messages directly. Keep the
exception explicit so the four NSE messages also used in Dart remain gated.
"""

import argparse
import json
import runpy
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
GENERATOR = ROOT / "intergalactic/ios/scripts/generate_nse_localizable.py"
NSE_ONLY_KEYS = {
    "notificationAttachmentSentAudio",
    "notificationAttachmentSharedLocation",
}


def nse_keys(generator: Path = GENERATOR) -> set[str]:
    keys = runpy.run_path(str(generator)).get("KEYS")
    if not isinstance(keys, dict) or len(keys) != 6:
        raise ValueError("NSE generator must map exactly six message keys")
    values = list(keys.values())
    if any(not isinstance(key, str) or not key for key in values) or len(set(values)) != 6:
        raise ValueError("NSE generator message keys must be six unique names")
    if not NSE_ONLY_KEYS <= set(values):
        raise ValueError("NSE-only messages are no longer in the generator mapping")
    return NSE_ONLY_KEYS


def read_arb(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError(f"ARB must be an object: {path}")
    return data


def prepare(committed: dict, extracted: dict, keys: set[str]) -> tuple[dict, list[str]]:
    expected = committed.copy()
    omitted = []
    for key in sorted(keys):
        metadata = f"@{key}"
        value = committed.get(key)
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"committed ARB has no usable NSE message: {key}")
        if not isinstance(committed.get(metadata), dict):
            raise ValueError(f"committed ARB has no NSE metadata: {metadata}")
        # A partially extracted pair is not an exemption: let compare_arb.dart
        # report the missing or changed counterpart in the ordinary way.
        if key not in extracted and metadata not in extracted:
            expected.pop(key)
            expected.pop(metadata)
            omitted.append(key)
    return expected, omitted


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("committed", type=Path)
    parser.add_argument("extracted", type=Path)
    parser.add_argument("prepared", type=Path)
    args = parser.parse_args()
    try:
        expected, omitted = prepare(
            read_arb(args.committed), read_arb(args.extracted), nse_keys()
        )
    except (OSError, ValueError) as error:
        parser.exit(1, f"NSE ARB comparison setup failed: {error}\n")
    args.prepared.write_text(json.dumps(expected, ensure_ascii=False), encoding="utf-8")
    if omitted:
        print("NSE-only ARB pairs omitted from Dart extraction comparison:")
        for key in omitted:
            print(f"  {key} and @{key}")


if __name__ == "__main__":
    main()
