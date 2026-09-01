# DeepFilterNet `libDF` Rust crate-tree evidence

Status: **PARTIAL — Windows and Android build-input correspondence and their
feature-specific dependency closures are captured. The 109-package source
licence roster is complete: 107 packages retain their own text, and two
MIT-declared packages are explicitly mapped to canonical SPDX MIT text because
their exact archives/source trees contain no licence file. Candidate packaging
proof and source-offer classification remain insufficient to describe the
shipped `df.dll` / `libdf.so` tree.**

This is an engineering evidence record, not a legal-sufficiency conclusion and
not an authorization to change a release notice, source offer, or publication.

## Component and delivered-payload boundary

The tracked native-payload inventory currently identifies these payloads under
the broader DeepFilterNet native runtime/model row:

| Platform | Candidate path | Candidate-inventory SHA-256 |
| --- | --- | --- |
| Windows | `df.dll` | `48D2DAE7451626CAF98E9D1B90B7AAF2E24DF1319D4820F33449655D4678C0C6` |
| Android arm64-v8a | `lib/arm64-v8a/libdf.so` | `92eb2be51d2462adb93a958bbe8627115df289c0bd292d202ac87b51f7608265` |
| Android armeabi-v7a | `lib/armeabi-v7a/libdf.so` | `38c96b0c5b35214fe4f1d8b56048dc08994c9916e835b74a47e2326f3ee65297` |

`df.dll.lib` is a Windows link input, not a delivered runtime payload under the
current Windows CMake route. The ONNX model archive is a separate model asset;
it is not part of this Rust crate-tree record.

### Committed source inputs are a separate identity

The tracked JNI source inputs are not interchangeable with the candidate APK
entries above. Their checked-out SHA-256 values are:

| Source input | SHA-256 |
| --- | --- |
| `windows/x64/df.dll` | `48D2DAE7451626CAF98E9D1B90B7AAF2E24DF1319D4820F33449655D4678C0C6` |
| `android/src/main/jniLibs/arm64-v8a/libdf.so` | `8EB64AC74752D2CD9EB7E60EF53B86F5B9A34E76298E7E02F7A2FCF1AA4991AC` |
| `android/src/main/jniLibs/armeabi-v7a/libdf.so` | `2EA1B67AD8F73318E100EFC4ABA8DF2522E361196E6A27961ABD6D4F09F7443F` |
| `android/src/main/jniLibs/x86_64/libdf.so` | `F9331BF6310B2469A3243FD2FB7902A6820A13753CCE166088F27E1AFB52845D` |

Git records all three Android inputs as added by `3ec3fa9b` on 2026-07-12 and
unchanged through the retained candidate-source commit `b40b2da2`; Windows
`df.dll` was added by `0ebd2f70` on 2026-07-02. The Android candidate-inventory
digests therefore identify a distinct APK artifact boundary. Do **not** replace
one set with the other: RELEASE PIPELINE must explain any packaging transform
or rebuild boundary before an exact source-input-to-candidate correspondence is
claimed.

## Source and upstream comparison

- Vendored source path:
  `plugins/intergalactic_noise_suppression/third_party/deepfilternet/libDF/`.
- Upstream: <https://github.com/Rikorose/DeepFilterNet>.
- The vendored `Cargo.toml` is byte-identical to upstream commit
  `d375b2d8309e0935d165700c91da9de862a99c31` (committed 2024-10-17), and
  declares `deep_filter` `0.5.7-pre`, `MIT/Apache-2.0`, with library name `df`.
- Seventeen of the nineteen tracked vendored `libDF` files match that upstream
  commit byte-for-byte. `src/dataset.rs` does not match a fetched upstream
  branch history, and `src/logging.rs` was subsequently modified locally in
  app commit `64221d2f18a9aaba06d931674705800cbb24079a`.
- Upstream `d375b2d8` `Cargo.lock` hashes to
  `0D46E3333FDC6861BF7D8BDB2CE7B6B0FD82B16211AA76BA52C26A25923CF6BA`.
  It is a provenance candidate only. It is not copied here as a durable
  crate roster because the vendored tree is mixed and the original Cargo build
  invocation for the prebuilt payloads is not recorded.
- App history supplies a separate negative control: the Windows prebuilt
  `df.dll` was added in `0ebd2f704dacf741aa3b8cc2f17e16a91232b3a7` on
  2026-07-02, while the tracked `libDF` source was added later in restored-Mac
  snapshot commit `3ec3fa9beb53e908afc1c9ca3bbb6f70a2bcf435` on 2026-07-12.
  The vendor tree therefore was not imported with the binary and does not by
  project history prove its source-to-binary correspondence.

### Operator acquisition receipt (2026-08-20)

The owner confirms that material in the previously identified local Hugging
Face download folder was downloaded by the owner from Hugging Face and that
AUDIO copied project inputs from that folder.

This is a useful local acquisition-chain receipt — **owner download → local
Hugging Face folder → AUDIO copy → project inputs** — but its scope is not yet
binary-specific. It does not name a Hub repository, revision, file manifest,
or checksum that maps that folder to the pinned `df.dll`/`libdf.so` inputs. It
therefore neither proves nor rules out a later native build, rebuild, or other
transformation. It also does not establish the upstream source revision,
patches, lockfile, selected features, target configuration, or source-to-binary
correspondence. Those remain required before this record can support a
release-candidate notice or source-offer conclusion.

### Artifact-local compilation evidence

Each of the committed native inputs — Windows `df.dll` and Android
`libdf.so` for arm64-v8a, armeabi-v7a, and x86_64 — retains both of these
binary-embedded source-path markers:

- a Cargo registry path under the current Windows user's
  `.cargo/registry/src/index.crates.io-*` tree; and
- `libDF/src/capi.rs`.

That is independently verifiable from the committed payload bytes and supports
a **local Cargo build environment** for every native payload. It means the
Hugging Face acquisition receipt cannot, by itself, establish those binaries as
opaque upstream download artifacts. It does not identify the person or process
that ran the build, the invocation, source revision, patches, lockfile, feature
selection, target configuration, or a byte-for-byte reproduction; do not
upgrade this to source-to-binary correspondence.

### Android source-to-input correspondence (captured 2026-08-20)

The retained Android build-output tree supplies stronger evidence for the three
**committed JNI inputs**. Its Git checkout records remote
`https://github.com/Rikorose/DeepFilterNet.git` at
`d375b2d8309e0935d165700c91da9de862a99c31`; its target output for each ABI has
the exact SHA-256 of the committed JNI library:

| Android ABI / Cargo target | Raw captured Cargo fingerprint | Exact committed-input SHA-256 |
| --- | --- | --- |
| arm64-v8a / `aarch64-linux-android` | `android-build-fingerprints/arm64-v8a-lib-df.json` (`0458DF09CC09480145EF9D94E76D53F306CCF8A7C5AD3F96031AC4DB45B7A164`) | `8EB64AC74752D2CD9EB7E60EF53B86F5B9A34E76298E7E02F7A2FCF1AA4991AC` |
| armeabi-v7a / `armv7-linux-androideabi` | `android-build-fingerprints/armeabi-v7a-lib-df.json` (`F03C23E07339769ED7E935FCC67B333ECF21C33BE049370888DAE6F236B8DA49`) | `2EA1B67AD8F73318E100EFC4ABA8DF2522E361196E6A27961ABD6D4F09F7443F` |
| x86_64 / `x86_64-linux-android` | `android-build-fingerprints/x86_64-lib-df.json` (`54DB3DDCFA9BE36EA4F3DBBD17F30903C2FC68C389B6C0C855ECBE2E2AE5115C`) | `F9331BF6310B2469A3243FD2FB7902A6820A13753CCE166088F27E1AFB52845D` |

The fingerprints are byte-captured here with `-text` attributes. They record a
release-profile `deep_filter` build with empty `rustflags` and the selected
feature set:

```text
capi, default, default-model, flac, logging, tract, transforms, vorbis
```

This establishes source-to-**committed-input** correspondence for the three
Android libraries, including their build targets and selected features. It does
not prove the distinct APK-entry hashes in the candidate inventory, establish a
Windows `df.dll` build, recover the literal Cargo command/NDK version, or
establish final release-candidate package inclusion, notice selection, or
source-offer classification. The
upstream `d375b2d8` lockfile remains the controlled source candidate; do not
silently substitute the currently modified retained checkout lockfile for it.

The tracked `libDF` tree contains no `Cargo.lock`. The current host Cargo
resolver refuses to evaluate the historical upstream lockfile with `--locked`
because it would modify that file; no generated dependency tree is therefore
used as evidence.

### Windows source-to-input correspondence (captured 2026-08-20)

The retained Windows build checkout supplies direct correspondence evidence for
the committed `windows/x64/df.dll` input. It records the public remote
`https://github.com/Rikorose/DeepFilterNet.git` at
`d375b2d8309e0935d165700c91da9de862a99c31`; its
`target/release/df.dll` has the exact committed-input hash
`48D2DAE7451626CAF98E9D1B90B7AAF2E24DF1319D4820F33449655D4678C0C6`
(16,570,880 bytes; retained output mtime 2026-07-01 19:10:24 -04:00).

The historic execution record is:

```text
cargo build -p deep_filter --release --features capi --no-default-features
```

It ran for host/target `x86_64-pc-windows-msvc` with no explicit `--target`,
release profile, empty Rust flags, and Rust `1.94.1`
(`e408947bfd200af42db322daf0fadfe7e26d3bd1`). The retained raw Cargo
fingerprint is captured byte-for-byte as
`windows-build-evidence/windows-lib-df.json`
(`C1B9A32768CD3CCC629C972BEDF3DDF97DB7D6531837DB44764A3292E04AFD5C`).
It selects exactly:

```text
capi, default-model, logging, tract, transforms
```

That is a distinct Windows feature graph. In particular, it does **not** select
the Android build's `default`, `flac`, or `vorbis` features; do not merge the
two graphs into one roster.

The build did not use `--locked`; Cargo modified the checkout's lockfile while
resolving the Windows build. The retained post-resolution bytes are therefore
captured as
`windows-build-evidence/windows-post-build-Cargo.lock`
(`6E54B54EE1732F37DF4C9E11B2C93F1D5BADB449C9234D1879BDE10EA463C017`,
146,531 bytes, `-text` protected). The source checkout still reports this file
modified. It is evidence of the historic resolved build state, **not** a
pristine upstream lockfile or proof that a fresh `--locked` rebuild would use
the same graph. Preserve it; do not clean or reset the retained checkout as a
substitute for this capture.

This establishes Windows source-to-**committed-input** correspondence. It does
not prove a later Windows release candidate/package contains that exact input,
or establish final notice selection or source-offer classification.

### Feature-specific crate roster (captured 2026-08-20)

The retained post-build lockfile was evaluated for the captured Windows and Android feature selections. The normalized public roster records 95 Windows package/version pairs, 105 Android pairs, and their union of 109 pairs.

`feature-rosters/crate-license-roster.json`
(`B9F198325EA0264409721FC30D0D3876DD21EF788EC96D644A088B19942717F7`) records each package's platform membership, registry/path source, declared licence expression, source-manifest hash, repository metadata, and copied licence/notice file hashes. `feature-rosters/crate-license-texts/` preserves those exact files. Host-specific command captures are retained as private, byte-preserved evidence and are intentionally not published in this source snapshot.

107 package rows have an exact source licence/notice file captured. The two
remaining source trees — `crunchy 0.2.2` and `realfft 3.3.0` — each declare
`MIT` but contain no licence/notice text file in either the exact crate archive
or matching upstream Git tree. Their upstream manifests byte-match the
published `Cargo.toml.orig` files and record the package author and SPDX `MIT`
declaration. The evidence captures SPDX's canonical MIT text and maps it only
through those declarations; `LICENSE-SOURCE.md` beside each crate records the
revision, manifest hash, source-file absence, and this qualification. This
completes the source roster, not a user-visible notice or candidate-package
claim.

All declared expressions in the 109-row result are permissive/public-domain or
multi-licence expressions (including Apache/MIT/Zlib/BSD/CC0 and the captured
Unicode/LLVM exceptions); this is a source-metadata observation, not a final
licence-arm election or a source-offer conclusion. The raw trees use
`--edges normal`, so they cover selected code/proc-macro dependencies and do
not represent build-only tooling as conveyed runtime material. See
`feature-rosters/README.md` for command scope and boundaries.

## Artifact-derived build footprint (bounded, not a crate roster)

All three pinned payloads retain Cargo-registry source-path strings. Extracting
the `crate-version/src` portion of those strings found 36 unique crate/version
pairs in each payload, with set equality across Windows x64, Android arm64-v8a,
and Android armeabi-v7a. They also retain the Rust compiler revision
`e408947bfd200af42db322daf0fadfe7e26d3bd1`.

The following is a durable **observed-in-binary floor**, not a declaration that
these are the complete direct or transitive dependencies of any payload:

```text
anyhow 1.0.82                    bit-set 0.5.3
bit-vec 0.6.3                    bytes 1.6.0
crossbeam-channel 0.5.12         dlv-list 0.5.2
flate2 1.0.30                    hashbrown 0.14.5
itertools 0.12.1                 lazy_static 1.4.0
log 0.4.21                       memmap2 0.9.4
miniz_oxide 0.7.2                ndarray 0.15.6
nom 7.1.3                        num-integer 0.1.46
ordered-multimap 0.7.3           primal-check 0.3.3
rand 0.8.5                       rand_core 0.6.4
realfft 3.3.0                    rust-ini 0.21.0
rustfft 6.2.0                    smallvec 1.13.2
strength_reduce 0.2.4            string-interner 0.15.0
tar 0.4.40                       tract-core 0.21.4
tract-data 0.21.4                tract-hir 0.21.4
tract-linalg 0.21.4              tract-onnx 0.21.4
tract-onnx-opl 0.21.4            tract-pulse 0.21.4
tract-pulse-opl 0.21.4           transpose 0.2.3
```

All 36 pairs occur in the **workspace-root** `Cargo.lock` at the public
upstream candidate `d375b2d8`; this corroborates the candidate family and the
observed `tract`/C-API path. It does not select the build command, distinguish
enabled features from a workspace lockfile union, identify local patches, or
prove that path/debug-string extraction is exhaustive. A source string can be
absent from a binary for build or stripping reasons, so an unobserved crate
remains neither disproven nor licensed by this list.

At that same upstream revision, the version-controlled
`.github/workflows/build_capi.yml` recipe invokes:

```text
cargo cinstall --profile=release-lto -p deep_filter --features capi
```

This is a concrete **upstream C-API build recipe** and explains why `capi` is
the appropriate candidate feature, but it is not a retained record of the
local Windows invocation. The recovered Android build-output evidence above is
separate and stronger for its three committed inputs. The upstream recipe alone
still cannot connect the recipe, local source patches, selected lockfile, target
toolchain, or resulting bytes to Windows `df.dll` or the delivered APK-entry
payload hashes above.

The original project evidence added with `df.dll` on 2026-07-02 recorded file
hashes and the upstream project URL but no binary acquisition identifier,
build command, source revision, lockfile, or target-feature record. The Android
libraries and vendored source arrived later together in the 2026-07-12 restored
snapshot with the same missing project-history record. The subsequently
captured Android build-output equality is the evidence that closes the
Android-input portion; the import timing remains a negative result for Windows
and for final APK packaging, not a substitute for either proof.

## Surface map

| Surface | State | Evidence or reason | Owner / next validation |
| --- | --- | --- | --- |
| Structured inventory | blocked | The three payload paths still point to the broader runtime/model row. Do not repoint them until release-candidate payload correspondence is cross-checked and the component record is reviewed. | S&C / REVIEW |
| Upstream licence and notice capture | required / captured | Exact source text is captured for 107 packages. For `crunchy 0.2.2` and `realfft 3.3.0`, exact upstream/package MIT declarations, authors, source-file absence, and an explicit canonical SPDX-MIT mapping are captured. | S&C |
| Crate roster | required / captured | Captured fingerprints and locked, feature-specific trees establish 95 Windows / 105 Android / 109 union package pairs; `crate-license-roster.json` maps every selected package to source and text evidence. | S&C |
| Shipped artifact enumeration | required | Windows and Android payload identities above are pinned. A future record must compare each claimed crate/notice route with the actual candidate payloads. | RELEASE PIPELINE / S&C |
| User-visible native notice | blocked | The source roster is complete, but candidate-package correspondence and final licence-arm/notice selection are not evidenced. Do not attach a notice surface yet. | S&C / app owner |
| Release/policy notice | blocked | Do not add a summary until candidate packaging is cross-checked and final notice selection is reviewed. | S&C / REVIEW |
| Corresponding source / public offer | partial / blocked | Windows and Android source-to-committed-input correspondence are captured, but final candidate packaging, full licence mix, and source-offer classification remain open. Do not infer a permissive-only outcome from `deep_filter`'s own licence. | S&C / RELEASE PIPELINE |
| Package inclusion | required | Existing platform candidate evidence establishes the payload paths; a release candidate must re-verify them after any payload change. | RELEASE PIPELINE |
| Tests and negative controls | required | Preserve the captured fingerprint hashes and exact target-output-to-committed-input equality; a future record also needs a control against mapping these paths to the model/runtime wrapper. | S&C / REVIEW |
| Queue and handoff | required | `libdf.so/df.dll is a Rust crate tree recorded as a 'native C API runtime' - 2026-08-20` tracks this blocked evidence boundary. | S&C |

## Required next evidence

1. Keep the captured Windows post-resolution lockfile distinct from the
   pristine upstream lockfile and from the Android default-feature graph; do
   not substitute or merge any of them when deriving a roster.
2. Separate the Hugging Face download identity for any model/input it supplied
   from the native payloads. Capture the exact Hub repository, revision, file
   manifest, and matching checksum before claiming that any specific committed
   file came from that download.
3. Treat the mixed vendored `libDF` tree as a separate future-rebuild concern;
   it must not replace the evidenced `d375b2d8` source/lock state for these
   committed inputs. Record any future rebuild's patches and lockfile anew.
4. Cross-check the completed graph against all three delivered payloads. This must state
   what is proven from the candidate binaries versus what remains a source-only
   inference.
5. Only then add the `native_components` record, repoint the three payload
   mappings, add applicable notice assets/attachments, and classify any source
   offer obligation.
