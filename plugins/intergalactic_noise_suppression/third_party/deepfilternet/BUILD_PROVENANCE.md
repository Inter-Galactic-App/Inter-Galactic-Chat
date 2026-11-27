# libDF native-input candidate - 2026-09-25

Status: staged for REVIEW and RELEASE PIPELINE; not approved for shipment.

The five native inputs below were rebuilt after S&C approved the pinned
replacement-build envelope in the 2026-09-25 S&C handoff. This is a new
candidate, not a byte reproduction of the previously packaged libraries.

## Source and build

- Public DeepFilterNet commit: `d375b2d8309e0935d165700c91da9de862a99c31`.
- Overlay from merged app source `e2e7a738`: `libDF/src/capi.rs`
  (`0CCDE432C828CC4C695A7BB972BBE18522AD9D8BB882377B9AA35649C8B58D56`),
  `logging.rs` (`C0EF76454F963D51ADAC39CB0CC64F7F72EE1532BA7AD1C05B461F13C15519D0`),
  and `transforms.rs` (`9E5D396AEBDE0ECCCE427F11624670A4461B9A444F2899683DF5D9312162B242`).
  These hashes were rechecked against this app branch before building.
- `Cargo.lock` SHA-256:
  `6E54B54EE1732F37DF4C9E11B2C93F1D5BADB449C9234D1879BDE10EA463C017`.
  The retained lockfile is in
  `docs/release/evidence/license-sources/deepfilternet-libdf-rust-tree/windows-build-evidence/`.
- Rust/Cargo 1.94.1; `cargo build -p deep_filter --release --features capi
  --no-default-features --locked --offline` for Windows MSVC
  `x86_64-pc-windows-msvc`.
- Rust/Cargo 1.94.1; `cargo build -p deep_filter --release --features capi
  --locked --offline --target <target>` separately for Android
  `aarch64-linux-android`, `armv7-linux-androideabi`, and
  `x86_64-linux-android`. Android default features were enabled. Linker and C
  compiler were the corresponding NDK `28.2.13676358` API 24 Clang wrappers;
  `llvm-ar` came from the same NDK. `CARGO_INCREMENTAL=0` was set for all
  builds. A separate target directory was used, not the earlier diagnostic
  output directory.

## Staged inputs

| File relative to `plugins/intergalactic_noise_suppression/` | Bytes | SHA-256 |
| --- | ---: | --- |
| `third_party/deepfilternet/windows/x64/df.dll` | 16,561,664 | `D88A299413AAD935DB6EC6306AAEFE1B5D62E32EBDDC798B8AC1FDFB279EF7DF` |
| `third_party/deepfilternet/windows/x64/df.dll.lib` | 3,268 | `61969E4BABE3A366156B02E4E4FC44C1F11BBEDC6795577298B25FD0FECD7ECF` |
| `android/src/main/jniLibs/arm64-v8a/libdf.so` | 18,704,296 | `F1D070B403A7640EDB7C88A001B6864B2F66EB02785F30A683EF57F79B95031F` |
| `android/src/main/jniLibs/armeabi-v7a/libdf.so` | 11,849,920 | `9AA3BC5C23E4232B25B0A0C6DF9C5E4915DEDFFDED6571A5BFC42059CA58AA08` |
| `android/src/main/jniLibs/x86_64/libdf.so` | 21,402,056 | `21D550A56E17E02E01F09F3184537E79F2188812CA16A2F578C51E55D7309121` |

The Android outputs happen to be byte-identical to the prior diagnostic
builds; they were independently rebuilt for this candidate. The Windows DLL
differs from both the earlier diagnostic DLL and the existing packaged DLL.

## Checks and gates

- All four `cargo build` commands succeeded with four pre-existing lifetime
  syntax warnings in `libDF/src/tract.rs` per target.
- The fresh Windows DLL created the bundled real model with a 480-sample frame
  and returned null, without aborting, for a valid gzip containing non-model
  bytes. The bundled model SHA-256 was
  `C94D91F70911001C946E0FABB4AA9ADC37045F45A03B56008CB0C8244CB63616`.
- Each Android library exported the same nine `df_*` symbols as the previous
  ABI input. No Android device was attached; no rebuilt app was run.
- RELEASE PIPELINE and REVIEW must check exact candidate input and Android
  post-strip package hashes, packaged ABI selection, and inclusion of
  `intergalactic/assets/licenses/deepfilternet-libdf-rust-crates-NOTICE.txt`.
  The current native-payload inventory hashes describe an older candidate and
  must not be treated as proof of this one. QA/AUDIO still need rebuilt Windows
  and Android behavior checks before release acceptance.
