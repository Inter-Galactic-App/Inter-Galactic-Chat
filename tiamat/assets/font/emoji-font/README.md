# Emoji font (removed)

`NotoColorEmoji.ttf` used to live here and was removed on 2026-08-07. The
`LICENSE` beside this file is deliberately kept — see below.

## Why it went

It shipped 23.75 MB into every Windows, Android and web build and was never
drawn.

A font declared in a package's `pubspec.yaml` is registered under a namespaced
family name. The built `FontManifest.json` showed both of these:

```text
EmojiFont                 -> assets/font/emoji-font/TwemojiCOLR.otf          (app, 1.0 MB)
packages/tiamat/EmojiFont -> packages/tiamat/assets/font/emoji-font/NotoColorEmoji.ttf
```

Every emoji font request in this repo asks for the bare `EmojiFont`
(`ThemeCommon.fontFamilyFallback`, `TextUtils.nativeEmojiFontFallback`,
`emoji_widget.dart`), so the app's TwemojiCOLR always won. Nothing anywhere
referenced `packages/tiamat/EmojiFont`.

That was confirmed by rendering rather than by reading. An engine-level probe
drew the same emoji three times: with no emoji font registered, then with
TwemojiCOLR added, then with NotoColorEmoji additionally registered under its
namespaced family. Adding TwemojiCOLR changed the pixels; adding NotoColorEmoji
changed nothing. The middle step is the control — without it, "no change" would
equally describe a probe that cannot see any font at all.

## Why the LICENSE stays

Releases up to and including `0.8.0+993` shipped the font, so the OFL notice is
still a live obligation for those builds, and
`docs/release/THIRD_PARTY_LICENSES.json` cites this exact path as licence
evidence. Removing a file from future payloads does not retire the attribution
for payloads already distributed.

## If you are about to add an emoji font here

Don't, unless tiamat is genuinely being consumed by an app that declares no
`EmojiFont` family of its own. A package font under a shadowed family name is
invisible in the build log and shows up only as bundle size — which is how this
one survived as long as it did.
