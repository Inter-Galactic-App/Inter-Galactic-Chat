# libmpv compliance bundle

Prepared by S&C, 2026-08-07. Promoted from scratch into tracked release evidence on
2026-08-08 at REVIEW's placement direction. This is engineering licence/provenance evidence,
not legal advice.

Nothing in this directory has been published to the live site. The public wording lives on
`https://app.ourgalaxy.space/source/`; if the two ever disagree, the deployed page is what
was offered.

## Headline — the original task premise did not hold

This work was commissioned as **GPL** compliance for a GPL libmpv already in users' hands. On
re-checking the inputs, that finding was wrong:

**The shipped `libmpv-2.dll` was built with `-Dgpl=false`. It is an LGPL build.**

- There is **no GPL obligation** from libmpv for `0.8.0+992`, `0.8.0+993`, or any other build.
- There **is** a live **LGPL** obligation for every Windows desktop release. It is now
  partly met: the mpv corresponding source is published and the notice text is written.
- The planned replacement "LGPL libmpv" build may be **redundant** — the artefact is already
  LGPL. OPERATIONS should confirm before spending the effort.

Unlike the FFmpeg situation, this does **not** split into past-versus-future. One DLL, one
hash, every Windows build from `0.7.2+980` to `0.8.1+1001`. The same obligation covers all of
them and would cover a rebuild too.

## Files

| File | Purpose |
| --- | --- |
| `LICENCE-DETERMINATION.md` | The core finding and its four independent checks. Read first. |
| `THIRD_PARTY_NOTICES.libmpv.md` | Notice content for mpv/libmpv and for the FFmpeg n6.0 inside it, kept distinct from the bundled exe pair. |
| `THIRD_PARTY_LICENSES.libmpv.json` | Structured component inventory with per-entry confidence and evidence. Matches the shape of `docs/release/evidence/ffmpeg-components/THIRD_PARTY_LICENSES.ffmpeg-components.json`. |
| `corresponding-source-bundle.md` | What must be published, from where, at which revisions. Includes the one remaining blocker. |
| `licence-combination-analysis.md` | AGPL app + libmpv. Tests the owner's GPL reading on its own terms, then gives the position that actually applies. |
| `ffmpeg-n6.0-SOURCE.md` | Identity, retrieval route and digest for the FFmpeg statically linked into the DLL. **Archive published 2026-08-08.** |
| `evidence/mpv-meson-configure-line.txt` | mpv's meson command line, recovered from the shipped DLL. The authority for the licence determination. |
| `evidence/ffmpeg-configure-line.txt` | The inner FFmpeg's configure line, recovered from the same DLL. The authority for the component list. |
| `evidence/artifact-hashes.txt` | Hashes closing the provenance chain across 19 sampled builds. |

## Method, and why it matters

Everything rests on the two configure lines **recovered from the shipped binary itself**,
not on the build repository. That choice was forced by the evidence: the build repo's
`packages/mpv.cmake` at the recorded commit says `-Dlua=enabled -Dopenal=enabled
-Dvulkan=enabled -Dlibplacebo=enabled` and carries no `-Dgpl` flag, while the binary says the
opposite on all four and adds `-Dgpl=false`. **The recorded commit does not describe the
shipped artefact.** Had the deliverable been built from the repository, every conclusion in it
would have been wrong.

Two method notes worth keeping, and the second is the one that produced the original wrong
answer:

- **The `packages/` catalogue is not a component list.** It holds 100+ definitions including
  GPL-only ones. The list here comes from the configure lines and is corroborated
  component-by-component against data strings in the binary.
- **Absence is usually not provable in this artefact.** LTO, `--gc-sections` and
  `--enable-stripping` remove internal symbol names; only data strings survive. `dav1d_open`
  and `mbedtls_ssl_init` return zero hits for components that are demonstrably present.
  Presence of a distinctive string is good evidence; absence of a symbol is not evidence of
  absence. The one absence claim made here — that `vo_direct3d` is not compiled in — is
  supported by a control: sibling VO description strings *are* present, so that table survived
  and its gap is meaningful.

## Provenance chain, verified end to end

```text
media_kit_libs_windows_video 1.0.11   (pubspec.lock)
  └─ pins URL + MD5 a832ef24b3a6ff97cd2560b5b9d04cd8
       └─ mpv-dev-x86_64-20230924-git-652a1dd.7z   MD5 MATCHES locally
            └─ libmpv-2.dll
                 └─ SHA-256 D5F0694B…A5FC, identical in all 19 sampled builds
```

The vendor archive contains **only** the DLL, the import library and four headers. **No licence
file, no notice, no copyright statement.** That is the mechanical reason mpv and libmpv appeared
nowhere in either `THIRD_PARTY_NOTICES.md`: nothing was inherited, so every notice had to be
authored.

## What changes once an LGPL rebuild lands

Given the current build is already LGPL, a replacement changes less than expected.

| Item | Applies to shipped builds | Applies after a rebuild |
| --- | --- | --- |
| **A** Corresponding-source archive | Yes | Yes — same structure, new revisions. Not historical-only. |
| **B** mpv/libmpv notice | Yes | Yes — text unchanged if the rebuild is also `-Dgpl=false`; the LGPLv2.1+ statement holds. |
| **C** Inner-FFmpeg notice | Yes | Version-dependent. If the rebuild moves off n6.0, the version and component list change; the LGPLv3+ conclusion probably does not. |
| **D** Component list | Yes | Must be re-derived. It is specific to this configure line and does not transfer. |
| **E** Licence-combination analysis | Yes | Yes — unchanged, unless the rebuild alters the uchardet situation. |

Nothing here becomes historical-only, because the current artefact is not defective in the way
the task assumed. What a rebuild *would* usefully fix is the **build-definition gap**: a build
produced by this project, from a known commit, would close the one blocker that still prevents
finalising the source offer.

## Blockers and open items

1. **Build definition unidentified.** The recorded commit contradicts the binary. This blocks
   the build-definition half of the corresponding-source offer and the Tier-3 component
   revisions. Critical path. Open legal question: whether the binary's own recorded configure
   line is an acceptable substitute for the scripts.
2. ~~**FFmpeg `n6.0` archive is staged, not published.**~~ **CLOSED 2026-08-08** — published
   at `/source/ffmpeg-n6.0-source.tar.gz`, digest re-verified against the served file after
   copying. Struck rather than deleted so the sequence stays legible.
3. ~~**uchardet is tri-licensed** (MPL-1.1 / GPL-2.0+ / LGPL-2.1+); the project should elect and
   record an arm.~~ **CLOSED 2026-08-09** — the owner elected **LGPL-2.1-or-later**, the arm
   matching this DLL's own class. Its source is published, at a **best-evidence** commit
   rather than a recovered pin: the build definition pins no version for it at all.
4. **Per-component licence texts not yet collected** for the attribution-only components;
   depends on item 1. The obligated components' texts were captured at their pinned commits.
5. **This DLL's transitive dependencies are not enumerable** — the blind spot that hid FFTW
   inside `ffmpeg.exe`, still open on this artefact. The obligated set of three is therefore
   not proven complete.

### Closed since this bundle was written

- **MuJS — RESOLVED 2026-08-08, no longer a blocker.** This list previously read "MuJS
  relicensed ISC → AGPL-3.0 … it changes the notice". The artefact is bounded to MuJS
  `<= 1.3.3`, which is ISC. See `THIRD_PARTY_LICENSES.libmpv.json` and the MuJS section of
  `licence-combination-analysis.md` for the bound and its basis. What remains is a narrower
  legal question about MuJS as a project today, not about this artefact.
- **ANGLE — COVERED.** This list previously said `libEGL.dll`, `libGLESv2.dll` and
  `vk_swiftshader.dll` "appear in no notice". They are now named in
  `docs/release/THIRD_PARTY_NOTICES.md` and `intergalactic/lib/config/native_licenses.dart`.

## Boundaries

Notices and source-bundle **content** only. OPERATIONS owns any replacement build, DESIGN owns
the website, RELEASE PIPELINE owns the release flow, REVIEW integrates and publishes.
