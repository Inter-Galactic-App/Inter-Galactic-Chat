# Emojibase Source Evidence

Status: release-ready source and license evidence for Inter Galactic
`0.7.4+985`.

Reviewed by REVIEW on 2026-06-13 and link-normalized by REVIEW on 2026-06-14.

The Inter Galactic emoji metadata was regenerated from the upstream
`emojibase-data` npm package rather than retaining the stale Commet-era
`readme.md` note.

## Package

- Package: `emojibase-data@17.0.0`
- License: MIT
- Repository: `https://github.com/milesj/emojibase`
- Package directory: `packages/data`
- npm tarball:
  `https://registry.npmjs.org/emojibase-data/-/emojibase-data-17.0.0.tgz`
- npm shasum: `5816fba6395da6b567fbd54b029ca6b5de2d9255`
- npm integrity:
  `sha512-Yvgb5AWoHViHV/gq1qr5ZAarcBip+B27/ZLRsUJkbgAEaLlZ/fof9g882LTpmEpyhBNEC0m2SEmItljHsTygjA==`
- package gitHead: `a5fc630a91ca42cddf3f4a66492965600fd3bce8`

## Reference Links

- Project: `https://github.com/milesj/emojibase`
- Documentation: `https://emojibase.dev`
- npm package: `https://www.npmjs.com/package/emojibase-data`

## Shipped Inputs

| Shipped file | Package source | SHA-256 |
| --- | --- | --- |
| `intergalactic/assets/emoji_data/data.json` | `package/en/data.json` | `ED014F1049BD370C5794F815850156196AC382850F51C3E9F6A9E83553FB3F01` |
| `intergalactic/assets/emoji_data/shortcodes/en.json` | `package/en/shortcodes/emojibase.json` | `DB3D41EDF2F190BCB81BF171A51B1F889AF774EED5DC24D21AD8DFCB998B40D3` |

The app's generated `unicode_emoji_data_groups.g.dart` file is ignored by git
and can be regenerated from those two inputs through the existing
`UnicodeEmojiBuilder`.

## Regeneration Commands

```powershell
$env:npm_config_cache = '<workspace-cache>\npm-cache'
npm pack emojibase-data@17.0.0 --pack-destination <workspace-cache>\review-emojibase-17.0.0
tar -xzf <workspace-cache>\review-emojibase-17.0.0\emojibase-data-17.0.0.tgz -C <workspace-cache>\review-emojibase-17.0.0
```
