# Isolated iOS IPA and development-app builds

Run `python3 intergalactic/ios/scripts/build_ipa.py` from a clean committed
app repository on macOS, with Python 3.11 or newer. The default phase prints
the plan. Supply an explicit full app commit, a JSON configuration, and a
new output directory outside the source checkout:

```sh
python3 intergalactic/ios/scripts/build_ipa.py \
  --commit FULL_APP_COMMIT \
  --config intergalactic/ios/build-config/config.example.json \
  --output /private/tmp/ig-ios-build-unique \
  --kind ipa --export-method app-store --phase plan
```

`config.example.json` records a measured toolchain and an example public
service configuration. Select the intended public endpoints and OAuth
client identifiers before using it; empty Spotify, Steam and URL-preview
values leave those build integrations unconfigured. Do not put credentials,
API keys, tokens or signing material in this file. Unknown/duplicate fields
are rejected. The wrapper compares installed Flutter revision, Dart, Xcode,
Rust, Cargo and CocoaPods with the selected pins before preparation.

Use `--phase prepare` to clone the selected commit, prepare the exact patched
0.5.0 wrapper, resolve both Dart packages to one verified source tree, run
code generation, and retain a local source packet and receipt. Use `--phase
build` on a **different fresh output directory** to perform all those steps
and export an IPA through `scripts/build_release.dart`. The wrapper supplies
the complete app identity, public service flags, export method and `--no-pub`
behavior. It removes ambient service/debug flags and refuses unrecorded
compiler overrides. Local signing assets must already be available to Xcode.
No upload, installation or source publication is performed.

### IPA symbols and final export

The shared builder's first IPA is retained as a **bootstrap diagnostic**, not the
selected candidate. Explicit owned product roots can leave Xcode's archive
`dSYMs` empty despite generating symbols. The wrapper derives six arm64 UUIDs
from this invocation's archive and bootstrap binaries (Runner, three extensions,
App and Flutter); no UUID from an earlier candidate is hardcoded. Every generated
dSYM must have the matching UUID and basename, valid metadata and a complete
regular-file tree. Unknown/extra, empty, redirected or conflicting trees fail.

Pinned Flutter combines/copies only `Contents/Resources/DWARF/App` for the
`io.flutter.flutter.app` bundle's `App.framework.dSYM`. Only that exact sparse
tree (the one DWARF file and its three parent directories) may omit
`Contents/Info.plist`; metadata is never fabricated. If App metadata exists,
it must be regular, nonempty, nonredirected and valid dSYM metadata. The other
five bundles always require it. App DWARF basename, arm64 UUID and binary
bindings remain mandatory. Metadata appearing/disappearing after the snapshot
changes its tree manifest and fails revalidation like any other byte/tree change.

Only a fresh invocation's archive is augmented. `symbol-gather.json` binds its
original binaries, signatures, metadata, bootstrap IPA and all generated symbol
bytes before copying. Copy uses exclusive creation and never overwrites unknown
bytes. A same-plan helper retry can accept a complete known subset; interrupted
partial/empty files fail closed, without truncation or automatic deletion. The
CLI does not resume an old output: retain failed output and use a fresh directory.
All six copied trees, UUIDs, original archive/bootstrap bindings and source/root/
CargoKit/define gates are rechecked after gather and immediately before export.

The wrapper then performs an explicit **local** `xcodebuild -exportArchive` into
the distinct fresh `final-export/` directory using the original verified export
options: matching method, destination export and stripSwiftSymbols true;
App Store exports additionally require uploadSymbols true (including Xcode's
true defaults when absent). No upload
destination is accepted. These symbols are diagnostics, not a claim that missing
IPA Symbols alone causes Store rejection. The selected default symbol intent is
nevertheless enforced for App Store exports: exactly six nonempty UUID-named
`Symbols/*.symbols` records, matching the final binaries, are required for
candidate success. Development and ad-hoc exports do not require IPA Symbols
or uploadSymbols=true: that option is App Store-specific. Every supported IPA
method still requires all six archive dSYMs and exact final binary UUID bindings.
The receipt explicitly records whether IPA symbol coverage was required.

Only the unique regular IPA under `final-export/` can become the receipt's
`artifact`. Original signature/APNs/version/notice/source gates still run. Until
all final checks succeed the persisted receipt stays pending and identifies the
bootstrap separately. Export may change signatures/IPA hashes. Preserve all
earlier archives/exports; this route does not repair or upload them.
Focused synthetic tests establish source gates only; exercise
the actual signed archive/export transition before relying on product evidence.

For a signed development app use `--kind development-app --phase build`.
It builds Profile mode with the same explicit platform/service flags and
`BUILD_MODE=release`, retaining normal product feature behavior. It does not
enable the notification debug harness. The resulting Runner app has its own
signature/APNs receipt. Select `--kind ipa --export-method development` if
an exported development IPA in Release mode is wanted instead.

Every successful build rechecks the patched source, lock/package paths and
Pod symlink; measures the CargoKit and wrapped pod archives; verifies E8
exports and signatures; checks Runner and all three extension identities,
versions and App Groups; enumerates Mach-O payloads; verifies the packaged
Rust notice; and records the Flutter license registry and effective Dart
defines. `build-receipt.json` and `source-packet/` stay with the isolated
output. A partially failed build retains a pending receipt, never a success
claim. Use the recipient source/notice and native-inventory review procedure
for any eventual distribution; this script records payload bytes but does
not approve inventory re-pins or source availability.

CargoKit roots are computed by the wrapper, not supplied by callers or
discovered from existing libraries. Inherited `FLUTTER_XCODE_*` and raw root
overrides are rejected, including empty values. An immutable copied environment
sets only `FLUTTER_XCODE_OBJROOT` and `FLUTTER_XCODE_SYMROOT`; pinned Flutter
forwards them as Xcode settings on the actual product invocation. The two direct
settings queries use exactly the same values and environment. The locked Pods
and patched pod link are verified before preflight.

For prepared app root `A` and configuration `C` (Release for IPA, Profile for
development), roots are `A/intergalactic/build/ios/ig-root-contract/C/intermediates`
and `.../products`. Both Runner and the actual `flutter_vodozemac` pod must
corroborate source/project/action/SDK/architecture and root/temp/product path
equations. IPA products are `SYMROOT/Release-iphoneos`; Profile retains Flutter's
explicit `BUILD_DIR=A/intergalactic/build/ios` and products `BUILD_DIR/Profile-iphoneos`.
The Rust archive is under `OBJROOT/Pods.build/C-iphoneos/flutter_vodozemac.build/aarch64-apple-ios/release/`;
the wrapped archive is under the product directory's `flutter_vodozemac/`.
Default DerivedData archive installation paths cannot choose either library.

Relevant workspace metadata is optional, never fabricated. If present at the
explicit roots/boundary or queried archive installation's default DerivedData
root, it must be regular, nonempty, non-redirected, valid and name exactly this
Runner workspace. Absence before or after compilation is acceptable because
explicit product roots, both corroborating queries and unchanged context bind
the outputs. Matching metadata may appear after compilation. Xcode query-created
PIF caches are not compiled products.

Both expected archives must be absent before compilation, including dangling
symlinks. The complete immutable invocation context is persisted in the pending
receipt before the product command. Postflight repeats both queries and validates
context equality before measuring archives. Only nonempty regular, non-redirected
files with both required E8 decrypt/free symbols are hashed. Missing, ambiguous,
foreign, preexisting or changed paths fail closed; no newest-file or stale
normal-build fallback is used. Failures do not restamp a pending receipt as success.

The installed Flutter revision still must equal the full forty-character
configured pin. For generated Dart defines only, the wrapper accepts either
that full revision or its exact first ten characters: pinned Flutter's
`flutter_command.dart` emits `frameworkRevisionShort`, and `version.dart`
defines that representation as a ten-character truncation. Other prefix
lengths or different revisions are rejected.

The historical recipe copy is never reused: the packet contains the selected
commit's complete app archive, upstream and patched wrapper archives, full
recipe, current build instructions and configuration. It is locally staged
source. Review its README status statements before any recipient route.

Repeatability here means fixed source, toolchain and configuration with
measured outputs. `build_release.dart` emits a current `BUILD_DATE`, and
Apple signatures/export metadata can also differ between runs. Each
receipt records the actual date and hashes; identical IPA bytes are not
promised. Raw build logs and private signing details are not copied into the
source packet or receipt.

## Development versus IPA flags

| Setting | Development app from this wrapper | App Store IPA |
| --- | --- | --- |
| Flutter mode | Profile | Release |
| `BUILD_MODE` / `PLATFORM` | `release` / `ios` | `release` / `ios` |
| Service and feature defines | Same explicit configuration | Same explicit configuration |
| Package resolution | Verified patched tree, no pub during build | Same |
| Signature / APNs | Development, measured after build | Distribution / production, measured after export |
| Notification debug harness | Off | Off |

The native iOS PiP path has no Release/Profile feature switch. It requires
an active call, a prepared usable video track and native PiP readiness.
Audio-only calls or failed track preparation can reject PiP in either mode.
Changing export method or the Flutter build mode does not repair that path.
