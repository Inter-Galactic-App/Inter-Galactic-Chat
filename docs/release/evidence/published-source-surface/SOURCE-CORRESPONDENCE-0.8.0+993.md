# Source correspondence for 0.8.0+993

The 0.8.0+993 release was published in three passes on 2026-07-09, and the
Windows installer and the Android APK were built from different commits. One
source archive therefore cannot cover both. Both are published here.

| Binary | Corresponding source archive | Upstream commit |
|---|---|---|
| `InterGalactic-Setup-0.8.0+993.exe` (Windows) | `intergalactic-0.8.0+993-desktop-source.zip` | `29ed8795` (archive taken at `d244a882`) |
| `InterGalactic-0.8.0+993.apk` (Android) | `intergalactic-0.8.0+993-source.zip` | `5cde7aea2c171a820d8b7a1464bd225e5cf5a232` |

## Checksums

```
80db27d73d1a2bb0acf8970483b6ddc9faa6b8cf694c57dedd841f3fbb2032a8  intergalactic-0.8.0+993-desktop-source.zip   187,982,167 bytes
a46a8d322b48b71a65f24013420b1b3f8c2534f3001407b8b5137bb27041aac2  intergalactic-0.8.0+993-source.zip           187,982,517 bytes
```

## Why there are two

The Windows installer was packaged from a build produced at 11:38 on
2026-07-09, before commit `5cde7aea` ("Fix android overspill", 19:07) existed.
That commit changes three shared Dart UI files —
`favorite_rooms_list.dart`, `attachment_processor.dart` and
`room_side_panel.dart` — which compile into the Windows binary but are not
present in it. The Android APK was built at 22:40, after that commit.

The desktop archive above is the source that was originally published for this
release. It was later overwritten by the Android-matching archive; it is
restored here so that the source offered for the Windows installer is the
source that installer was actually built from.

Verified by extracting `data/app.so` from the shipped installer
(`sha256 d0bbb6c84ba831b0b64a98fba5615c44b21a2311f805551b1d94056b6b97750a`)
and confirming it is byte-identical to the archived build output, and by
confirming all three Dart files in the desktop archive match the `29ed8795`
tree rather than `5cde7aea`.

The two archives are otherwise identical apart from those files,
`pubspec.yaml`, `pubspec.lock`, and one release feature-note document.

---

**Correction, 2026-08-16.** The checksum line for
`intergalactic-0.8.0+993-desktop-source.zip` above previously read
`7090332aa4…6f35c3` / `188,044,409 bytes`. Neither value matched the file being
served. Both have been replaced with the digest and size re-computed from the
served archive itself.

The archive was never wrong and was never replaced — only this page's
description of it was. `/source/` and `downloads/checksums-0.8.0+993.txt` both
carried the correct values throughout, so anyone who verified their download
against either of those got a correct answer; anyone who used this page got a
mismatch on a good file.
