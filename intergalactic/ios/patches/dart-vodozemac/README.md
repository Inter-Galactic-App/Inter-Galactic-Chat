# Pinned iOS backup-notification wrapper experiment

Status: iOS-only fail-closed integration recipe. This recipe alone is not a
signed Apple payload, public release, or served source offer. The committed
default `pubspec.lock` remains hosted and must not describe an iOS patched
build. Direct iOS builds without this verified source gate now fail closed.
Upstream PR #62 remains the preferred long-term home.

## Exact source and build recipe

`manifest.json` pins upstream `famedly/dart-vodozemac` tag `0.5.0` to commit
`1bdded7dd13d26b3f77c4287c9321f7cf924dec9` and tree
`ef7825610cc462cc16b48d950959ab7325b52d5c`, the patch SHA-256, the
four changed files, their before/after bytes, and post-patch tree. The single
`.patch` file is the full modification source. The baseline and patched
license bytes are identical (SHA-256 in the manifest). The patch does not
change either Dart pubspec. It adds only a direct caret requirement
`serde_json = "1.0.140"` to Cargo.toml; Cargo.lock already resolves
`serde_json` 1.0.140 and gains one root dependency-list line. It preserves
Rust vodozemac 0.9.0, flutter_rust_bridge 2.11.1 and all resolved checksums.

On a Mac with Python 3.11+, Git, Rust/Cargo, and Flutter, run from this app
repository's root:

```sh
python3 -m unittest discover -v \
  -s intergalactic/ios/patches/dart-vodozemac -p test_prepare.py
python3 intergalactic/ios/patches/dart-vodozemac/prepare.py \
  /private/tmp/ig-e8-review-UNIQUE --resolve-app
cargo test --locked --manifest-path \
  /private/tmp/ig-e8-review-UNIQUE/source/rust/Cargo.toml \
  ios_ffi_bindings::tests
# Optional, using a *different* new empty output directory:
python3 intergalactic/ios/patches/dart-vodozemac/prepare.py \
  /private/tmp/ig-e8-build-UNIQUE --resolve-app --build-ios
```

Use a fresh, empty output directory on every run. The recipe fetches the exact
upstream tag into `source`, verifies base commit/tree/file hashes and patch
bytes, applies it with `git apply --check`, and verifies the changed-file set,
post-patch tree/file hashes, Cargo package versions and checksums. It creates
an absolute-path `pubspec_overrides.yaml` for both `flutter_vodozemac` and
`vodozemac`. With `--resolve-app` it clones the committed app branch into
`app` within the output, copies the override only there, runs `flutter pub
get`, then rejects any result in which either package is not path-resolved at
0.5.0 to its expected subdirectory of this one patched tree. Its lock check
reads only each named package's stanza; focused tests reject a hosted target
followed by a different path-resolved package, even when package-config paths
otherwise look correct. It also requires exactly one canonical `source` and
`version` field per target stanza, rejecting duplicate keys even when one
value is correct. The generated
override, resolved `app/pubspec.lock`, `.dart_tool/package_config.json`,
source, patch, and `evidence.json` remain in the isolated output. Never copy
the override into the live checkout or patch the shared pub cache.

## iOS integration gate

`verify_ios_patch.py` checks the exact baseline and post-patch Git trees,
changed-file set and file hashes, Cargo resolution, a full app commit,
the generated override bytes, and both named lock/package-config paths.
`ios/scripts/verify_e8_patched_source.sh` is invoked before CocoaPods resolves
plugins and at the beginning of both Runner and notification-extension Xcode
target builds. It requires `IG_E8_PYTHON` (Python 3.11+), the absolute
`IG_E8_SOURCE` tree and full `IG_E8_APP_COMMIT`; omission or mismatch aborts
the iOS build. The Xcode phases additionally require CocoaPods' plugin
symlink to resolve to that same patched `flutter/` directory.
`prepare.py --resolve-app --build-ios` supplies these only to
its isolated build subprocess after verifying the source and app. A hosted
default lock, a stale Pod installation, or direct Xcode invocation cannot
silently supply the patched-only extension ABI. This command path remains
unsigned; a separate signing/export flow must retain the same source checks.

The modified AGPL wrapper's exact source and pending offer route are recorded
in `docs/release/evidence/license-sources/dart-vodozemac-ios-patch/SOURCE.md`.
That route has not been published. A separate signed iOS build used this
pinned source route and has candidate-specific correspondence evidence; the
recipe's unsigned scratch build alone is not that proof.

An optional `--build-ios` (only accepted with `--resolve-app`) runs an
**unsigned scratch build** from that isolated clone. It rechecks both package
resolutions before code generation, immediately before invoking Flutter with
`--no-pub`, and after the build. It runs the app's `build_runner` and Intl
generator first, then requires the ignored Drift, emoji, and Intl outputs.
The macOS system Bash lacks `mapfile`, so it invokes the same Intl generator
with the repository's bounded source/ARB inputs rather than calling
`generate-from-arb.sh`. It cannot start a build through this recipe with either package hosted,
resolved outside this source tree, or at a different version. This is not a
distribution/candidate workflow or signing recipe. The optional full build
also refuses to start below 10 GiB free on the scratch filesystem. The first
trial on this Mac ran out of space; after freeing storage and adding the clean
checkout's required code generation, the unsigned build passed. The isolated
Rust iOS-target compile and package resolution checks remain separate evidence.
A successful unsigned build
records generated-source, CargoKit static-library, notification-extension
Mach-O and Runner Mach-O hashes in `evidence.json` and verifies both combined
ABI exports in the library and extension. These are internal build bytes, not
signed candidate payloads.

The Podfile and Xcode targets enforce the patched-source gate, but they do not
run `prepare.py` automatically. For any signed candidate, prepare the source
and verify the same package configuration before `pod install` and Xcode.
That gate must retain the generated override, resolved lock and package paths,
Cargo resolution, toolchain, source and patch bytes, actual CargoKit static
library, extension Mach-O, exported-symbol and signed package hashes with
the candidate. The source packet must include this manifest, patch, source
and these build instructions. A hosted, unpatched 0.5.0 lock entry never
describes the patched binary. The optional unsigned build alone makes **no**
signed-payload provenance claim; each signed build needs its own correspondence
evidence before distribution.

## Security boundary

The added `ios_decrypt_backup_event_v1` accepts an exact
`m.megolm_backup.v1` type, a 32-byte raw backup private key, bounded backup
public key/MAC/ciphertext, and bounded Megolm event ciphertext. It requires
the decrypted document's `m.megolm.v1.aes-sha2` algorithm, imports its
exported session key inside Rust, and returns only event plaintext (at most
64 KiB). The matching free function volatile-wipes that output. Every
returning failure is null/zero with no error text; allocator OOM and
abort-mode panics cannot return. The caller must clear its own key input.
The accepted `Curve25519SecretKey::from_slice` transient-copy residual remains.
The Rust wrapper has no storage, file, network, logging, retry, Flutter bridge,
notification-rendering, or account access; this does not replace the NSE's E5
exact-row selection or any E1-E10 budget and Developer Mode gate.

The port is deliberately against 0.5.0. No 0.8.1 package/toolchain fallback,
fork, app-consumption path, source-offer change, merge, or shipment is implied.
