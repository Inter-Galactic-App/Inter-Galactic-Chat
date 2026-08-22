# libmpv-2.dll licence determination — the shipped build is LGPL, not GPL

Prepared by S&C, 2026-08-07. **Draft. Not published.** REVIEW owns integration and publication.
Nothing here has been written to the live mirror, pushed, or deployed.

## Headline

**The premise of this task does not hold. The shipped `libmpv-2.dll` is an LGPL build.**

The task was scoped to produce GPL compliance materials for a GPL libmpv already in users'
hands. Re-checking the inputs, as instructed, shows the "it is a GPL build" finding is wrong
on its decisive facts. The binary carries its own meson configure line, and that line contains:

```text
-Dgpl=false
```

Consequences:

- There is **no GPL obligation** arising from libmpv for `0.8.0+992`, `0.8.0+993`, or any
  other shipped Windows build.
- There is a **real and currently unmet LGPL obligation**, for those builds and every other
  Windows desktop build, because mpv under `-Dgpl=false` is LGPLv2.1-or-later and the FFmpeg
  inside it is LGPLv3-or-later — and the project ships neither notice nor source offer for
  either.
- The planned "build an LGPL libmpv going forward" work may be **redundant**. The shipped
  artefact is already LGPL. OPERATIONS should confirm before spending the build effort.

The compliance work is therefore still needed, but it is LGPL work, not GPL work, and it
applies to past *and* future releases rather than splitting into a past/future obligation the
way the FFmpeg situation did.

## Why the earlier finding went wrong

The earlier determination rested on three claims. The first is true in general, the second is
false for this build, and the third is a misattribution.

| Claim | Status | What the evidence shows |
| --- | --- | --- |
| mpv defaults `gpl` to true | True in general | Not reached — this build sets the flag explicitly. |
| "The build passes no `-Dgpl` flag at all" | **False** | The binary's embedded meson line contains `-Dgpl=false`, twice, at two independent offsets. |
| "The DLL contains the direct3d VO and the d3d9 implementation" | **Misattributed** | The GPL-only VO is absent. The d3d9 code belongs to FFmpeg's DXVA2 hwcontext and mpv's LGPL `dxinterop` GL context. The bare string `direct3d` is a deprecation-alias table entry. |

The third row is the trap worth recording. mpv keeps a table of removed video-output names so
it can print a helpful error, and that table is a plain run of strings:

```text
video outputs\0gl\0gpu\0direct3d_shaders\0direct3d\0opengl\0opengl-cb\0libmpv
```

These are `old-name → new-name` pairs (`gl`→`gpu`, `direct3d_shaders`→`direct3d`,
`opengl-cb`→`libmpv`). The word `direct3d` appears in a binary that does **not** contain
`vo_direct3d.c`. A string search for the VO name therefore cannot answer the question, and
here it produced a false positive that inverted the licence conclusion.

## The four independent checks

### 1. The build's own meson configure line, extracted from the shipped DLL

Full line: `evidence/mpv-meson-configure-line.txt`. Relevant part:

```text
-Dgpl=false -Db_lto=true -Db_ndebug=true -Dlibmpv=true -Dpdf-build=enabled
-Dlua=disabled -Djavascript=enabled -Duchardet=enabled -Dlcms2=enabled
-Dopenal=disabled -Dspirv-cross=enabled -Dvulkan=disabled -Dlibplacebo=disabled
-Degl-angle=enabled
-Dprefix=/__w/libmpv-win32-video-build/libmpv-win32-video-build/mpv-winbuild-cmake/build64/install/mingw
-Dbuildtype=release -Ddefault_library=shared -Dprefer_static=True
```

The `/__w/libmpv-win32-video-build/...` prefix is the GitHub Actions workspace path of
`media-kit/libmpv-win32-video-build`, so this line is that repository's CI build of this
artefact, not a stray string copied from elsewhere.

### 2. mpv's own source gates direct3d behind gpl

`meson.build` at mpv `652a1dd907`:

```text
direct3d_opt = get_option('direct3d').require(
    get_option('gpl') and features['win32-desktop'],
```

With `-Dgpl=false` the requirement fails and the VO is not built. The same gate governs
`cdda`, `dvbin`, `dvdnav`, `jack`, `oss-audio`, `caca` and `x11` — none of which is relevant
on this target, but all of which are likewise excluded.

### 3. The GPL-only VO is absent from the binary

`vo_direct3d.c` registers a description string. Sibling VO description strings survive
stripping in this binary, so their table is intact and searchable:

| String | Present |
| --- | --- |
| `Null video output` | yes |
| `Direct3D 9 Renderer` | **no** |
| `Shaderless Direct3D` | **no** |
| `vo_direct3d` | **no** |

The control case matters: if description strings had been stripped wholesale, absence would
prove nothing. They were not, so absence here is meaningful.

### 4. The d3d9 strings belong to LGPL components

Three distinct clusters, each attributable:

- `Failed to load D3D9 library` / `Failed to locate Direct3DCreate9Ex` /
  `Failed to create IDirect3D9Ex object`, sitting immediately beside `Failed to load D3D11
  library` and `AVHWDeviceContext` — this is FFmpeg's `libavutil/hwcontext_dxva2.c`, pulled in
  by `--enable-dxva2`.
- `DX_interop backbuffer format` / `Couldn't share rendertarget with OpenGL` /
  `Couldn't stretchrect for present` — mpv's `--gpu-context=dxinterop`, which is LGPL and is
  not gated on `gpl`. `dxinterop` appears 8 times in the binary.
- `Failed to load "dxva2.dll"` / `Can't StretchRect from NV12 to XRGB surfaces` — mpv's DXVA2
  hardware-decode path.

None is `vo_direct3d`.

## A caution about method — absence is usually not provable here

This build uses `-Db_lto=true`, `-Wl,--gc-sections`, `--prefer-static` and (for FFmpeg)
`--enable-stripping`. Internal symbol names are gone: `luaL_openlibs`, `dav1d_open`,
`mbedtls_ssl_init` and `ass_render_frame` all return zero hits even for components that are
demonstrably present. **Only data strings survive** — error messages, option names, and file
paths baked in by assertion macros.

So, for this artefact:

- Presence of a distinctive data string is good evidence a component is **in**.
- Absence of a symbol name is **not** evidence a component is out.
- Absence of a data string is evidence only where a comparable control string of the same
  kind is present, which is the reasoning used in check 3 above.

An earlier pass of this investigation recorded zero hits for libplacebo, vulkan, rubberband
and lua and nearly concluded they were absent. The meson line then showed
`-Dlibplacebo=disabled -Dvulkan=disabled` — correct by luck for two of them, and wrong for the
general method. The configure lines, not the symbol probes, are the authority.

## Unresolved: the build-repo commit does not match the artefact

The build definition was recorded as `media-kit/libmpv-win32-video-build` at `0837d6b2eb`.
That commit's `packages/mpv.cmake` declares:

```text
-Dlua=enabled -Dopenal=enabled -Dvulkan=enabled -Dlibplacebo=enabled
```

The shipped binary says `-Dlua=disabled -Dopenal=disabled -Dvulkan=disabled
-Dlibplacebo=disabled`, and adds `-Dgpl=false`, which that file does not contain at all. These
are systematically opposite, so **`0837d6b2eb` is not the commit that produced the shipped
artefact**, or the artefact was produced with overrides not present in that file.

This does not affect the licence determination — the binary's own configure line settles that
regardless of which commit produced it. It does affect the Corresponding Source claim, because
citing a build definition that demonstrably does not describe the binary would be worse than
citing none. **Do not publish `0837d6b2eb` as the build definition until the discrepancy is
resolved.** See `corresponding-source-bundle.md`.

Note also that the upstream repository was **archived on 2024-10-09** and is read-only.

## Verified artefact facts

| Fact | Value | How verified |
| --- | --- | --- |
| Artefact | `libmpv-2.dll`, 29,764,622 bytes (28.4 MiB) | local file |
| SHA-256 | `D5F0694B08C124E785D858D00082F3E3B158DD9138BFC48C0382BF1EB443A5FC` | computed |
| Identical across releases | `0.7.2+980` … `0.8.1+1001`, all 19 sampled builds | computed, one hash |
| mpv version | `mpv v0.36.0-403-g652a1dd907` | string in binary |
| mpv licence mode | `-Dgpl=false` → **LGPLv2.1-or-later** | embedded meson line + mpv `Copyright` |
| Inner FFmpeg | `n6.0` | string in binary |
| Inner FFmpeg licence | **LGPLv3-or-later** | `--disable-gpl --disable-nonfree --enable-version3`, plus six `lib*  license: LGPL version 3 or later` strings |
| Source archive | `mpv-dev-x86_64-20230924-git-652a1dd.7z`, 8,785,710 bytes | local file |
| Archive MD5 | `a832ef24b3a6ff97cd2560b5b9d04cd8` — **matches** the value pinned in the package | computed vs pinned |
| Archive SHA-256 | `DCE982222D7A23E4A1C6F0FB6CC39F6E899A6714624B95EA49CFF6558EE97572` | computed |
| Dart package | `media_kit_libs_windows_video` 1.0.11 | `pubspec.lock` |
| Download URL | `https://github.com/media-kit/libmpv-win32-video-build/releases/download/2023-09-24/mpv-dev-x86_64-20230924-git-652a1dd.7z` | package `windows/CMakeLists.txt` |

The MD5 match closes the provenance chain end to end: locked package version → pinned URL and
hash → local archive → extracted DLL → the DLL in every shipped build, all one artefact.

## What the vendor archive ships

The `.7z` contains exactly:

```text
libmpv-2.dll
libmpv.dll.a
include/{client.h, render.h, render_gl.h, stream_cb.h}
```

**No licence file, no notice, no copyright statement, no source offer.** Nothing was inherited
automatically, which is the mechanical reason mpv and libmpv appear nowhere in either
`THIRD_PARTY_NOTICES.md`. Every notice obligation for this artefact has to be authored here.
