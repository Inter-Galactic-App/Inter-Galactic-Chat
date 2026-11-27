#!/bin/sh
# Both Podfile and Xcode invoke this before accepting the patched-only NSE ABI.
set -eu

if [ -z "${IG_E8_PYTHON:-}" ] || [ -z "${IG_E8_SOURCE:-}" ] || [ -z "${IG_E8_APP_COMMIT:-}" ]; then
  echo "error: E8 iOS build requires the verified patched-source recipe" >&2
  exit 1
fi

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
"$IG_E8_PYTHON" "$script_dir/../patches/dart-vodozemac/verify_ios_patch.py"
