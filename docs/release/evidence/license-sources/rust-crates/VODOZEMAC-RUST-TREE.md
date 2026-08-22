# The Rust crates linked into the app binary

**Captured 2026-08-19 (MAC/REVIEW). Shipped notice:
`intergalactic/assets/licenses/rust-crates-NOTICE.txt`.**

## What ships, and why nothing saw it

`flutter_vodozemac` 0.5.0 does not ship a prebuilt library. Its podspec runs
cargokit as a build phase and then force-loads the archive it produces:

    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../rust vodozemac_bindings_dart'
    'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/libvodozemac_bindings_dart.a'

On Apple the whole Rust dependency tree is therefore merged into the single
`Runner` Mach-O — no `.framework`, no `.dylib`, no file to enumerate. On Android
and Windows the same tree arrives inside
`libvodozemac_bindings_dart.so` / `.dll`.

Every automatic notice surface enumerates packages, so none of them can see it:

- Flutter's `LicenseRegistry`, which backs `showLicensePage`, knows Dart
  packages. It sees `flutter_vodozemac` (AGPL-3.0) and `vodozemac` (the Dart
  wrapper, AGPL-3.0) — and nothing the Rust build pulled in.
- The Flutter `NOTICES` bundle, the Gradle notice inventory and the Play
  services OSS baseline are all package enumerations too.

Before 2026-08-19 the inventory carried `vodozemac` ×8 and **zero** mentions of
`curve25519`, `ed25519`, `tokio`, `serde`, `prost`, `anyhow`, `hashbrown`,
`dashmap`, `aes`, `base64ct`, `memchr` or `rand_chacha`, with `freetype` ×18 as
a control proving the search worked. `Cargo.lock` appeared nowhere in either
repo's documentation.

## A correction to an existing record

Two records describe this component as AGPL and stop there — the Android queue
row ("NOTICES.Z carries the full AGPL-3.0 text under flutter_vodozemac/
vodozemac, so record and artefact agree") and
`docs/security/findings/NATIVE_COMPONENT_COVERAGE_AUDIT_2026-08-15.md`
("`vodozemac_bindings_dart.dll` | vodozemac 0.9.0 + crates | no | none | app is
AGPL").

Both are describing the Dart wrapper's licence. Three different things are
involved and they do not share a licence:

| | licence | evidence |
| --- | --- | --- |
| `flutter_vodozemac` / `vodozemac` Dart packages (Famedly) | AGPL-3.0 | pub-cache `LICENSE` |
| `vodozemac_bindings_dart` Rust crate (Famedly) | AGPL-3.0 | `rust/LICENSE` in the pub package |
| **`vodozemac` Rust crate (matrix-org) 0.9.0** | **Apache-2.0** | `license = "Apache-2.0"` in its `Cargo.toml`; `LICENSE` is the Apache text |
| its 58 transitive crates | MIT, Apache-2.0, BSD-3-Clause, Unlicense, 0BSD, Zlib, BSL-1.0 | each crate's own `Cargo.toml` and licence files |

"The app is AGPL" answers the copyleft question. It does not answer the
permissive-notice question, and the permissive notices are the ones that were
missing. This does not change the source-offer posture: the AGPL limbs are still
AGPL and still carry what they carried.

## How the roster was established

Measured from the artefact, cross-checked against the lockfile — not read from
the lockfile:

1. **cargo panic paths.** rustc embeds
   `…/registry/src/<index>/<crate>-<version>/src/…` in panic locations, so the
   shipped binary names crate *and* version. 43 crate-versions.
2. **Rust legacy name mangling.** `_ZN<len><crate>…17h<hash>E` carries the crate
   identifier in every symbol, catching crates that emitted no panic path. 16
   more, versions resolved from the lockfile.
3. **Control.** All 43 path-derived crate-versions appear in
   `flutter_vodozemac-0.5.0/rust/Cargo.lock` — 0 disagreements.
4. **The standard library separates itself.** Seven crate-versions appear under
   a `/rust/deps/…` prefix rather than `registry/src`, and are absent from the
   bindings lockfile: `addr2line-0.25.1`, `gimli-0.32.3`, `hashbrown-0.16.1`,
   `memchr-2.7.6`, `miniz_oxide-0.8.9`, `object-0.37.3`,
   `rustc-demangle-0.1.26`. These are the precompiled standard library's own
   bundled dependencies. Three of them — gimli 0.32.3, hashbrown 0.16.1,
   rustc-demangle 0.1.26 — appear at exactly those versions in the toolchain's
   own `COPYRIGHT-library.html`, which confirms the inference independently.
5. **The toolchain is pinned by the artefact.** The binary carries
   `/rustc/e408947bfd200af42db322daf0fadfe7e26d3bd1`. The toolchain installed on
   this host reports `commit-hash: e408947bfd200af42db322daf0fadfe7e26d3bd1`,
   rustc 1.94.1 — so the licence texts below come from the exact toolchain that
   built the measured binary, not a plausible neighbour.

## How the texts were captured

Verbatim from the crate sources in the local cargo registry — the same trees
cargo compiled — so a text cannot be captured from the wrong revision of a
crate. All 59 resolved; none was missing from the registry.

**One substitution, made explicitly rather than silently.**
`flutter_rust_bridge` 2.11.1 declares `license = "MIT"` and ships no licence
file in its crates.io package. The text was taken from the Dart package of the
same project at the identical version 2.11.1, which does ship it. The generated
notice prints that substitution in its own body.

**Deduplication is of bytes, not of licences.** Identical texts are emitted once
and referenced by block id. Where a crate is dual-licensed, *every* text it
ships is reproduced — no election has been made among "MIT OR Apache-2.0" on the
owner's behalf.

## Roster

| crate | version | declared licence | artefact evidence |
| --- | --- | --- | --- |
| `addr2line` | 0.24.2 | Apache-2.0 OR MIT | cargo path + symbols |
| `adler2` | 2.0.0 | 0BSD OR MIT OR Apache-2.0 | symbols; version from Cargo.lock |
| `aead` | 0.5.2 | MIT OR Apache-2.0 | cargo path + symbols |
| `aes` | 0.8.4 | MIT OR Apache-2.0 | cargo path + symbols |
| `allo-isolate` | 0.1.27 | not declared | cargo path + symbols |
| `anyhow` | 1.0.97 | MIT OR Apache-2.0 | cargo path + symbols |
| `arrayvec` | 0.7.6 | MIT OR Apache-2.0 | cargo path + symbols |
| `atomic` | 0.5.3 | Apache-2.0/MIT | symbols; version from Cargo.lock |
| `backtrace` | 0.3.74 | MIT OR Apache-2.0 | cargo path + symbols |
| `base64` | 0.22.1 | MIT OR Apache-2.0 | cargo path + symbols |
| `base64ct` | 1.7.3 | Apache-2.0 OR MIT | cargo path + symbols |
| `block-buffer` | 0.10.4 | MIT OR Apache-2.0 | cargo path + symbols |
| `byteorder` | 1.5.0 | Unlicense OR MIT | cargo path + symbols |
| `bytes` | 1.10.1 | MIT | cargo path + symbols |
| `cipher` | 0.4.4 | MIT OR Apache-2.0 | cargo path + symbols |
| `ctr` | 0.9.2 | MIT OR Apache-2.0 | cargo path + symbols |
| `curve25519-dalek` | 4.1.3 | BSD-3-Clause | cargo path + symbols |
| `dashmap` | 5.5.3 | MIT | cargo path + symbols |
| `digest` | 0.10.7 | MIT OR Apache-2.0 | symbols; version from Cargo.lock |
| `ed25519` | 2.2.3 | Apache-2.0 OR MIT | symbols; version from Cargo.lock |
| `ed25519-dalek` | 2.1.1 | BSD-3-Clause | symbols; version from Cargo.lock |
| `flutter_rust_bridge` | 2.11.1 | MIT | cargo path + symbols |
| `futures-channel` | 0.3.31 | MIT OR Apache-2.0 | cargo path + symbols |
| `futures-core` | 0.3.31 | MIT OR Apache-2.0 | cargo path + symbols |
| `futures-executor` | 0.3.31 | MIT OR Apache-2.0 | cargo path + symbols |
| `futures-task` | 0.3.31 | MIT OR Apache-2.0 | symbols; version from Cargo.lock |
| `futures-util` | 0.3.31 | MIT OR Apache-2.0 | cargo path + symbols |
| `generic-array` | 0.14.7 | MIT | cargo path + symbols |
| `getrandom` | 0.3.2 | MIT OR Apache-2.0 | symbols; version from Cargo.lock |
| `gimli` | 0.31.1 | MIT OR Apache-2.0 | cargo path + symbols |
| `hashbrown` | 0.14.5 | MIT OR Apache-2.0 | cargo path + symbols |
| `hmac` | 0.12.1 | MIT OR Apache-2.0 | cargo path + symbols |
| `lazy_static` | 1.5.0 | MIT OR Apache-2.0 | cargo path + symbols |
| `log` | 0.4.27 | MIT OR Apache-2.0 | cargo path + symbols |
| `memchr` | 2.7.4 | Unlicense OR MIT | cargo path + symbols |
| `miniz_oxide` | 0.8.8 | MIT OR Zlib OR Apache-2.0 | symbols; version from Cargo.lock |
| `num_cpus` | 1.16.0 | MIT OR Apache-2.0 | symbols; version from Cargo.lock |
| `object` | 0.36.7 | Apache-2.0 OR MIT | cargo path + symbols |
| `once_cell` | 1.21.3 | MIT OR Apache-2.0 | cargo path + symbols |
| `oslog` | 0.2.0 | MIT | cargo path + symbols |
| `parking_lot_core` | 0.9.10 | MIT OR Apache-2.0 | cargo path + symbols |
| `poly1305` | 0.8.0 | Apache-2.0 OR MIT | symbols; version from Cargo.lock |
| `prost` | 0.13.5 | Apache-2.0 | symbols; version from Cargo.lock |
| `rand` | 0.8.5 | MIT OR Apache-2.0 | cargo path + symbols |
| `rand_chacha` | 0.3.1 | MIT OR Apache-2.0 | cargo path + symbols |
| `rand_core` | 0.6.4 | MIT OR Apache-2.0 | cargo path + symbols |
| `rustc-demangle` | 0.1.24 | MIT/Apache-2.0 | cargo path + symbols |
| `ryu` | 1.0.20 | Apache-2.0 OR BSL-1.0 | symbols; version from Cargo.lock |
| `serde` | 1.0.219 | MIT OR Apache-2.0 | cargo path + symbols |
| `serde_bytes` | 0.11.17 | MIT OR Apache-2.0 | symbols; version from Cargo.lock |
| `serde_json` | 1.0.140 | MIT OR Apache-2.0 | cargo path + symbols |
| `sha2` | 0.10.9 | MIT OR Apache-2.0 | symbols; version from Cargo.lock |
| `signature` | 2.2.0 | Apache-2.0 OR MIT | cargo path + symbols |
| `smallvec` | 1.15.0 | MIT OR Apache-2.0 | cargo path + symbols |
| `subtle` | 2.6.1 | BSD-3-Clause | symbols; version from Cargo.lock |
| `threadpool` | 1.8.1 | MIT/Apache-2.0 | cargo path + symbols |
| `tokio` | 1.44.2 | MIT | cargo path + symbols |
| `vodozemac` | 0.9.0 | Apache-2.0 | cargo path + symbols |
| `x25519-dalek` | 2.0.1 | BSD-3-Clause | symbols; version from Cargo.lock || Rust standard library | 1.94.1 (`e408947bf`) | Apache-2.0 OR MIT | `/rustc/<commit>` paths; toolchain commit matches |

## Regenerating

    python3 tools/release/generate_rust_crate_notice.py \
      --roster <roster.json> \
      --toolchain-licenses ~/.rustup/toolchains/<tc>/share/doc/rust/licenses \
      --rustc-version 1.94.1 \
      --rustc-commit e408947bfd200af42db322daf0fadfe7e26d3bd1 \
      --std-vendored "addr2line-0.25.1,gimli-0.32.3,hashbrown-0.16.1,memchr-2.7.6,miniz_oxide-0.8.9,object-0.37.3,rustc-demangle-0.1.26" \
      --supplement <supplement.json> \
      --out intergalactic/assets/licenses/rust-crates-NOTICE.txt

The generator lives in the **workspace** repo. Re-pin the digest in
`intergalactic/test/config/native_licenses_test.dart` in the same commit.

## Limits

- The notice's digest pin proves the asset is the generator's output for the
  measured roster. It does **not** prove the roster is current: a toolchain bump
  or a `flutter_vodozemac` bump changes the tree and nothing here notices. That
  is a re-measurement obligation, tracked on the payload queue row.
- Only the iOS binary was opened. Android and Windows compile the same lockfile
  from the same package, so the crate set is the same; their **toolchain** may
  differ, and with it the seven standard-library dependency versions. The
  shipped notice states this rather than implying a measurement not taken.
- `hashbrown` is in the lockfile at 0.14.5 and 0.15.2. Only 0.14.5 has a cargo
  path in the binary, so only 0.14.5 is claimed.
