# KISS FFT — Android `libnoise.so`, candidate `0.8.1+1003`

**Status:** notice recorded and shipped in-app. This is a coverage measurement,
not a legal-sufficiency conclusion.

## Why this record exists

The five Android native payloads the mapping gate reports unresolved were
checked on 2026-08-19 against the three surfaces that actually reach a user:
the Flutter `NOTICES.Z` bundle in the APK, the Gradle notice inventory, and the
Play services OSS-licenses baseline (whose plugin **is** applied in the release
build — `intergalactic/android/app/build.gradle:3` plus
`play-services-oss-licenses:17.5.1` at `:137`).

Four of the five were **records gaps only** — the component's notice already
reached users through at least one surface. This one was not:

| Surface | KISS FFT present? |
|---|---|
| Flutter `NOTICES.Z` | **No** |
| Gradle notice inventory | **No** |
| Play services OSS-licenses baseline | **No** |

BSD-3-Clause requires the copyright notice, conditions and disclaimer to
accompany a binary distribution. Nothing was carrying them.

## Why every generated surface missed it

The **container** is surfaced and the **limb** is not. `io.livekit:noise:2.0.0`
is Apache-2.0, appears in the Gradle notice inventory with a POM evidence path,
and appears in the OSS baseline. KISS FFT is *statically linked inside* that
module's `libnoise.so`, and **no generated notice surface sees inside a native
artefact**. A tool that reads POMs and package manifests cannot find it by
construction, which is why this needed the binary to be opened.

## Conveyance — confirmed from the binary, not inferred

`lib/arm64-v8a/libnoise.so` in the `0.8.1+1003` candidate exports:

```
kiss_fft            kiss_fftr            kiss_fft_alloc       kiss_fftr_alloc
kiss_fft_stride     kiss_fft_cleanup     kiss_fft_next_fast_size
kiss_fftri
```

and carries the literal strings `kissfft require input length to be even` and
`kiss fft usage error: improper alloc`. A nonsense control probe against the
same string table returned zero, so the scan is not matching noise.

## Origin — confirmed by digest

The AAR at
`caches/modules-2/files-2.1/io.livekit/noise/2.0.0/…/noise-2.0.0.aar` carries
`libnoise.so` for four ABIs. The two that ship are **byte-identical** to the
APK's:

| ABI | AAR vs APK |
|---|---|
| `arm64-v8a` | identical — `51176EBDACB2F58075A66564525DE60B0E870F0C81974A9ECEACB032A584F153` |
| `armeabi-v7a` | identical — `CAB25539F0AA5893D00F811245419021127E69EE130775A4E51568C1C982F0E1` |
| `x86`, `x86_64` | present upstream, **do not ship** |

**The AAR contains no `LICENSE` or `NOTICE` file of any kind** — its entries are
`R.txt`, `AndroidManifest.xml`, `classes.jar`, the AAR metadata properties and
the four `jni/*/libnoise.so`. That is why nothing downstream could have picked
this up automatically.

The JNI bridge symbols are `Java_com_paramsen_noise_NoiseNativeBridge_*`, so the
chain is **KISS FFT → `paramsen/noise` → `io.livekit:noise` → our APK**.

## The shipped text is the verbatim `COPYING` at a pinned revision

**Corrected 2026-08-19, same day as the original record.** The first version of
this file said the revision could not be determined and shipped a *composed*
text. Both were wrong, and the owner's question — "if it came through LiveKit,
LiveKit should have that posted somewhere" — is what found it.

LiveKit does publish it. The `noise-2.0.0.pom` `scm` block points at
`github.com/livekit/noise`, which is a **fork of `paramsen/noise`**, and its
`.gitmodules` declares:

```
[submodule "noise/src/main/native/kissfft"]
	path = noise/src/main/native/kissfft
	url = git@github.com:mborgerding/kissfft.git
```

The gitlink resolves to **`d74fd2adaffdf4489441a12e0258423b9f5b8e12`**
(2017-01-06). At that revision `COPYING` is a **complete, self-contained
BSD-3-Clause notice** — full conditions and disclaimer, no SPDX metadata, no
pointer to another file — so it ships **verbatim**. No composition is needed or
performed.

| | |
|---|---|
| Source | `mborgerding/kissfft` @ `d74fd2adaffdf4489441a12e0258423b9f5b8e12`, file `COPYING` |
| Pinned by | `livekit/noise` `.gitmodules` → `noise/src/main/native/kissfft` |
| Size | 1,475 bytes |
| SHA-256 | `ddd1400f963747b305bfa39e21206e58805a1c650451e2ee5ce81ed86bc0b1ab` |
| Digest pinned in | `intergalactic/test/config/native_licenses_test.dart` |

### What the first attempt got wrong, kept because it is the instructive part

It was composed from kissfft **master**, where `COPYING` is only a pointer and
`LICENSES/BSD-3-Clause` is a REUSE template carrying a `Copyright (c) <year>
<owner>` placeholder plus SPDX tooling metadata. Neither is usable verbatim, so
the two were joined and the placeholder substituted.

That produced text that was *plausible and wrong*. **Clause 3 differs between
the two revisions:**

| | Clause 3 |
|---|---|
| Pinned `d74fd2ad` — what ships | "Neither the **author** nor the names of any contributors…" |
| master — what was first shipped | "Neither the name of the **copyright holder** nor the names of its contributors…" |

Same licence family, same plausible size, different text. That is the FreeType
failure this project already documented, reached by a different route — and no
gate caught it, because a digest pin only proves the bytes have not drifted
*since capture*, never that the capture was the right one.

The test now asserts the clause-3 wording alongside the digest, so a re-capture
from master fails loudly rather than silently swapping revisions.

## Stated limits

The revision is now pinned, so the earlier "revision undetermined" limit is
**withdrawn**. Two limits remain and are real:

- **No reproducibility is asserted.** Nothing here maps the shipped `libnoise.so`
  back to a buildable source tree; the submodule pin establishes *which source*
  the notice must come from, not that the binary was built from it.
- **The pin was read from `livekit/noise` at `master`, not at a `2.0.0` tag** —
  the repository publishes no tags. The submodule pointer has been unchanged
  since the 2019 `paramsen/noise` history and the four 2025 commits are build
  and publishing changes, but a tagged release would be firmer evidence than a
  branch head.

This is a notice-coverage record, not a legal-sufficiency conclusion.
