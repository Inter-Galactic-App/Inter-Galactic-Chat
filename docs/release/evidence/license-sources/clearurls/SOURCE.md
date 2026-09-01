# ClearURLs Rules Source Evidence

Status: release-ready source and license evidence for Inter Galactic
`0.7.4+985`.

Reviewed by REVIEW on 2026-06-14.

## Shipped Material

- Shipped file: `intergalactic/assets/data/clearurls.json`
- Source pin: `ClearURLs/Rules @ 9317c06`
- Pin record: `intergalactic/assets/data/sources.txt`
- App-authored companion data: `intergalactic/assets/data/url_handlers.json`

## Source And License

- Source repository: `https://github.com/ClearURLs/Rules`
- License file: `https://raw.githubusercontent.com/ClearURLs/Rules/master/LICENSE`
- License: LGPL-3.0
- Local license text: `LICENSE.txt`

The ClearURLs GitHub repository describes itself as the rules database for the
ClearURLs WebExtension and marks the repository license as LGPL-3.0. The local
`LICENSE.txt` file preserves the LGPL-3.0 text for release packaging.

## Release Use

For the current pinned rules, the release notice/source-offer surface must
include the LGPL-3.0 notice text, the `ClearURLs/Rules @ 9317c06` source pin,
and a source link or source-offer entry for the retained rules data. Re-audit
if `clearurls.json` is regenerated, modified, fetched from a different source,
or re-pinned.
