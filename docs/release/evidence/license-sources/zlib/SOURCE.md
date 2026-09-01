# zlib licence text — capture and route

Captured by REVIEW, 2026-08-15.

## Why this component needs a text at all

**Android statically compiles zlib into `libmpv.so` and conveys it.** iOS does
not — it resolves `/usr/lib/libz.1.dylib`, an Apple system dylib, so no
obligation attaches there. That asymmetry is the whole reason this is the one
licence text the Apple pass could not have produced.

It is also the component **nothing declarative would ever have surfaced**:

- `libmpv-android-video-build`'s own `depinfo.sh` at `v1.1.7` does **not**
  mention zlib. The recipe pins libogg, libvorbis, libvpx and clones libx264,
  none of which ship, and omits the one that does.
- The Apple inventory does not list it, correctly, because Apple does not
  convey it.

It was found by opening the binary. That makes it the fourth instance of the
pattern recorded across this lane — a declaration is authoritative for what it
names and blind beneath it.

## Version, established from the artefact

`1.2.12`, read from the shipped `libmpv.so` (arm64-v8a) rather than from a
recipe. zlib emits its own version inside two copyright strings its source
compiles in:

```
inflate 1.2.12 Copyright
deflate 1.2.12 Copyright
```

Positive control for the extraction on the same binary: 36,831 printable runs,
`avcodec` 160. `strings(1)` is not installed on this host, so runs were
extracted in Python — a previous pass that used `strings` got zero for
everything **including its controls** and nearly recorded it as absence.

## The text

zlib carries **no `LICENSE` file** at `v1.2.12` — `.../v1.2.12/LICENSE` returns
404, verified rather than assumed. The licence lives in the `README` under
"Copyright notice:" and, identically, in the header comment of `zlib.h`.

Both were fetched and compared; the notice is the same in each. The shipped
asset reproduces the `zlib.h` form, which carries the word "Copyright" where
the README abbreviates to "(C)".

| File | Bytes | SHA-256 |
| --- | ---: | --- |
| `intergalactic/assets/licenses/zlib-Zlib.txt` | 1,006 | `d63f0feeb74cca59f7369452878bf3d659e32ca00777d3b594699b4c77190831` |
| `README.at-v1.2.12.txt` (this directory) | 5,368 | `fc2c3368901700f0acdeb1d8afeaca5923296768ec6824ecdf627aac396001fd` |

Upstream: `https://raw.githubusercontent.com/madler/zlib/v1.2.12/README`
and `.../v1.2.12/zlib.h`.

The README is kept whole rather than trimmed, so a reader can see the notice in
its original context and confirm the extraction was faithful.

## Which clause is actually binding here

zlib's licence has three restrictions. Only the third bears on a binary
redistribution: *"This notice may not be removed or altered from any source
distribution."* The first two govern misrepresentation of origin and marking of
altered sources.

This project does not alter zlib — it arrives already compiled inside
`libmpv.so`, built by `libmpv-android-video-build`. The acknowledgment in clause
1 is explicitly *"appreciated but is not required"*, and is provided anyway by
the in-app notice.

**No compliance conclusion is drawn here.** This file records identity,
retrieval, digests and what was checked.

## Not an Apple obligation — do not copy it across

If a future pass unifies the licence assets across platforms, zlib belongs to
the Android set only. Shipping it on iOS would assert a bundled component that
is not bundled there, which is the same class of error as the reverse omission.
