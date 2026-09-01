#!/usr/bin/env bash
set -euo pipefail
set -v

if [ -f "${HOME}/.cargo/env" ]; then
  # rustup installs Cargo here, but non-interactive WSL shells do not always
  # source it before this script runs from build_web.bat.
  # shellcheck disable=SC1090
  source "${HOME}/.cargo/env"
fi

if [ -d "${HOME}/.local/dart-sdk/bin" ]; then
  export PATH="${HOME}/.local/dart-sdk/bin:${PATH}"
fi

cargo_bin="$(command -v cargo || true)"
if [ -z "${cargo_bin}" ] || ! "${cargo_bin}" --version >/dev/null 2>&1; then
  echo "Cargo was not found in WSL." >&2
  echo "Install Rust/Cargo inside WSL before building web assets:" >&2
  echo "  wsl sudo apt update" >&2
  echo "  wsl sudo apt install -y cargo rustc" >&2
  echo "Or install rustup inside WSL and re-run build_web.bat." >&2
  exit 1
fi

case "${cargo_bin}" in
  /mnt/*|*.exe)
    echo "cargo resolves to a Windows binary (${cargo_bin}). Use/install Linux Rust inside WSL." >&2
    exit 1
    ;;
esac

cc_bin="$(command -v cc || true)"
if [ -z "${cc_bin}" ] || ! "${cc_bin}" --version >/dev/null 2>&1; then
  echo "A C linker (cc) was not found in WSL." >&2
  echo "Install the Linux build toolchain inside WSL before building web assets:" >&2
  echo "  wsl -u root bash -lc 'apt-get update && apt-get install -y build-essential'" >&2
  echo "Or run inside WSL with sudo: sudo apt update && sudo apt install -y build-essential" >&2
  exit 1
fi

case "${cc_bin}" in
  /mnt/*|*.exe)
    echo "cc resolves to a Windows binary (${cc_bin}). Use/install Linux build-essential inside WSL." >&2
    exit 1
    ;;
esac

dart_bin="$(command -v dart || true)"
if [ -z "${dart_bin}" ] || ! "${dart_bin}" --version >/dev/null 2>&1; then
  echo "A Linux-compatible Dart SDK was not found in WSL." >&2
  echo "Install Dart inside WSL before building web assets." >&2
  echo "Windows Flutter/Dart wrappers on /mnt/c cannot run this Linux vodozemac build step." >&2
  echo "This script will use ~/.local/dart-sdk/bin automatically when it exists." >&2
  exit 1
fi

case "${dart_bin}" in
  /mnt/*|*.exe)
    echo "dart resolves to a Windows binary (${dart_bin}). Use/install Linux Dart inside WSL." >&2
    exit 1
    ;;
esac

rm -rf .vodozemac

version=$(grep -E "^[[:space:]]*flutter_vodozemac:" pubspec.yaml | head -n1 | sed -E "s/.*flutter_vodozemac:[[:space:]]*\^?([^[:space:]]+).*/\1/")
if [ -z "${version}" ]; then
  echo "Unable to determine flutter_vodozemac version from pubspec.yaml" >&2
  exit 1
fi

git -c core.autocrlf=false -c core.eol=lf clone https://github.com/famedly/dart-vodozemac.git -b "${version}" .vodozemac
git -C .vodozemac config core.autocrlf false
find .vodozemac -type f \( -name "*.sh" -o -path "*/scripts/*.sh" \) -exec sed -i 's/\r$//' {} +
cd .vodozemac
cargo install flutter_rust_bridge_codegen --version 2.11.1
flutter_rust_bridge_codegen build-web --dart-root dart --rust-root $(readlink -f rust) --release
cd ..
mkdir -p ./web/pkg
rm -rf ./web/pkg/*
rm -f ./assets/vodozemac/vodozemac_bindings_dart*
mv .vodozemac/dart/web/pkg/* ./web/pkg/
rm -rf .vodozemac
