# iOS CocoaPods licence evidence — promoted snapshot

Captured 2026-08-14 by REVIEW.

## Why this directory exists

`docs/release/THIRD_PARTY_LICENSES.json` cited its iOS licence evidence at
`intergalactic/ios/Pods/…`. That path is **gitignored** —
`intergalactic/ios/.gitignore:13` excludes `**/Pods/`, and the app-root
`.gitignore:113` excludes `Pods/`. So a tracked compliance document rested, for
31 pod rows, on files git does not keep.

It was not a near miss. Across the whole repository history — 1,449 commits, all
refs, the entire object graph — **no `ios/Pods/` path has ever been committed**.
There was nothing to recover; the evidence simply had no durable copy.

The files here are that copy. The citations in `THIRD_PARTY_LICENSES.json` now
point at this directory instead of the working tree.

## What is here

| File | Source |
| --- | --- |
| `Pods-Runner-acknowledgements.markdown` | `Pods/Target Support Files/Pods-Runner/` |
| `Pods-Runner-acknowledgements.plist` | same |
| `pod-licenses/DKImagePickerController-LICENSE.txt` | `Pods/DKImagePickerController/LICENSE` |
| `pod-licenses/DKPhotoGallery-LICENSE.txt` | `Pods/DKPhotoGallery/LICENSE` |
| `pod-licenses/SDWebImage-LICENSE.txt` | `Pods/SDWebImage/LICENSE` |
| `pod-licenses/SwiftyGif-LICENSE.txt` | `Pods/SwiftyGif/LICENSE` |
| `pod-licenses/WebRTC-SDK-LICENSE.txt` | `Pods/WebRTC-SDK/WebRTC.xcframework/LICENSE` |

Renamed on promotion because seven files all called `LICENSE` cannot share a
directory; the table above is the mapping back.

**`Podfile.lock` is deliberately NOT copied here.** It is already tracked at
`intergalactic/ios/Podfile.lock`, and duplicating a tracked file creates a
second copy that drifts silently when the first is updated. Instead, the input
this snapshot corresponds to is pinned by digest:

    intergalactic/ios/Podfile.lock
    sha256 E348D4E286953E323D1159C2A12D4CC7DCDDB5E8639B7183AE900CB9743E0EEE

If that digest no longer matches, the pod set has changed and this snapshot is
stale. That is the check to run, and it is why the digest is here rather than a
copy.

## What this snapshot is NOT

**It is not evidence for a specific shipped build.** It is the state of the pod
set at the recorded `Podfile.lock` digest, captured on 2026-08-14. The
`android-oss-licenses/` directories beside it are keyed by build (`0.8.1+1001`
and so on) because they are produced during a release; nothing equivalent has
ever run for iOS. Do not retro-label this with a version number it was not
captured against.

**It does not describe what is inside the media_kit frameworks, and that is the
larger gap.** `Podfile.lock` names 71 pod entries, of which the media_kit
surface is exactly two — `media_kit_libs_ios_video` and `media_kit_video`. The
acknowledgements name the same two. The IPA embeds **18** libmpv-darwin
frameworks (FFmpeg 6.0 libraries, mpv, libass, dav1d, freetype, fribidi,
harfbuzz, mbedtls, png16, uchardet, xml2), and none of them appears in any file
in this directory.

That is the same failure the FFmpeg work hit twice: **a manifest names a direct
dependency and is blind to what is inside it by construction.** FFmpeg's
`configure` could not see FFTW arriving through chromaprint; a pod row cannot
see 18 frameworks arriving through `media_kit_libs_ios_video`. The 2026-06-13
acceptance of "all 31 pod rows resolve" was correctly scoped to the pod list and
says nothing about the framework contents.

The enumeration of those 18 is tracked separately — integration-queue row
*"Apple media_kit/libmpv bundle (iOS/macOS) has no licence notice, source-offer,
or evidence coverage - 2026-08-13"*.

## Refreshing this

When the pod set changes, re-copy the seven files, update the `Podfile.lock`
digest above, and keep the previous snapshot if it corresponds to something that
shipped. Do not point a citation back at `Pods/` — that is the defect this
directory exists to fix, and `tools/quality/Assert-DurablePointers.ps1` now
fails on it.
