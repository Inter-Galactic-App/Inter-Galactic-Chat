#!/usr/bin/env python3
"""Generate the notification extension's six media bodies from host ARBs."""

import argparse
import json
import re
from pathlib import Path


KEYS = {
    "nse.body.image": "notificationAttachmentSentImage",
    "nse.body.video": "notificationAttachmentSentVideo",
    "nse.body.audio": "notificationAttachmentSentAudio",
    "nse.body.file": "notificationAttachmentSentFile",
    "nse.body.location": "notificationAttachmentSharedLocation",
    "nse.body.sticker": "notificationAttachmentSentSticker",
}
LOCALE_NAME = re.compile(r"intl_([a-z]{2,3}(?:_[A-Z]{2})?)\.arb\Z")
GENERATED_HEADER = "/* Generated from assets/l10n/intl_*.arb. Do not edit. */"


def generate(arb_dir: Path, output_dir: Path) -> list[Path]:
    english_path = arb_dir / "intl_en.arb"
    if not english_path.is_file():
        raise ValueError("English ARB is required")

    written = []
    for path in sorted(arb_dir.glob("intl_*.arb")):
        match = LOCALE_NAME.fullmatch(path.name)
        if match is None:
            raise ValueError(f"Invalid ARB locale filename: {path.name}")
        source = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(source, dict):
            raise ValueError(f"ARB must be an object: {path.name}")

        values = {}
        for native_key, arb_key in KEYS.items():
            value = source.get(arb_key)
            if value is None and match.group(1) != "en":
                continue  # Bundle.localizedString uses the explicit English default.
            if not isinstance(value, str) or not value.strip():
                raise ValueError(f"Missing or invalid {arb_key} in {path.name}")
            if "{" in value or "}" in value:
                raise ValueError(f"Unexpected interpolation in {arb_key} in {path.name}")
            values[native_key] = value

        if not values:
            continue

        locale = match.group(1).replace("_", "-")
        destination = output_dir / f"{locale}.lproj" / "Localizable.strings"
        destination.parent.mkdir(parents=True, exist_ok=True)
        lines = [GENERATED_HEADER]
        lines += [
            f"{json.dumps(key, ensure_ascii=False)} = {json.dumps(value, ensure_ascii=False)};"
            for key, value in sorted(values.items())
        ]
        destination.write_text("\n".join(lines) + "\n", encoding="utf-8")
        written.append(destination)

    for destination in output_dir.glob("*.lproj/Localizable.strings"):
        if destination in written:
            continue
        with destination.open(encoding="utf-8", errors="replace") as existing:
            is_generated = existing.readline().rstrip("\r\n") == GENERATED_HEADER
        if is_generated:
            destination.unlink()
    return written


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arb-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    generate(args.arb_dir, args.output_dir)


if __name__ == "__main__":
    main()
