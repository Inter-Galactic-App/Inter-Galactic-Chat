# Flutter framework licence evidence

Captured 2026-08-18 because `docs/release/THIRD_PARTY_LICENSES.json` recorded
the iOS `Flutter` pod as `OK WITH NOTICE SURFACE` while its only evidence was
`intergalactic/ios/Flutter/Flutter.podspec` — a file the Flutter tool writes at
build time, which is **not tracked in this repository and never has been** — plus
`intergalactic/ios/Podfile.lock`, which pins a version but carries no licence
text or licence declaration. A status of OK rested on a pointer a recipient of
the source archive could not follow.

## What is held

| Field | Value |
| --- | --- |
| File | `LICENSE-flutter-BSD-3-Clause.txt` |
| Upstream | `https://raw.githubusercontent.com/flutter/flutter/7048ed95a5ad3e43d697e0c397464193991fc230/LICENSE` |
| Pinned revision | `7048ed95a5ad3e43d697e0c397464193991fc230` (stable) |
| Size | 1,519 bytes |
| SHA-256 | `a598db94b6290ffbe10b5ecf911057b6a943351c727fdda9e5f2891d68700a20` |
| Licence | BSD-3-Clause, "Copyright 2014 The Flutter Authors" |

The revision is the one recorded in `intergalactic/.metadata`, so this text is
version-mapped to the SDK this app is actually built against rather than to
whatever `master` holds today.

## What this does not establish

This is the **framework** licence. The Flutter engine vendors many third-party
components under their own terms; those are surfaced by the app's own licence
page and by the Dart/Flutter package rows in the inventory, not by this file.

Capturing a licence text proves the text and its provenance. It is not a
compliance conclusion, and nothing here rules on sufficiency.
