import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intergalactic/config/platform_utils.dart';

/// Registers the licences of native binaries shipped beside the app.
///
/// Flutter's `showLicensePage` renders whatever is in [LicenseRegistry], and
/// the default registry only knows about Dart packages. Every desktop and
/// mobile build also ships native components the app did not write, so until
/// this existed the in-app licence page listed none of them.
///
/// FFmpeg's own compliance checklist asks for a mention "in your program about
/// box"; the same applies to mpv. This puts them where a user already looks
/// rather than adding a separate surface they would have to find.
///
/// Scoped per platform, because each platform ships a *different* set of native
/// artefacts and the licences are determined from the shipped binaries rather
/// than assumed — the evidence is under `docs/release/evidence/` and
/// `docs/security/findings/`. Asserting one platform's facts on another is how
/// the wrong licence gets published.
///
/// Windows, iOS and Android are covered. **macOS is deliberately not**, even
/// though it draws from the same upstream project: it ships a different tarball
/// with a different digest, no evidence has been collected for it, and the
/// owner deferred that platform on 2026-08-14 while a do-not-distribute hold
/// stands. Adding macOS here without its own check would recreate exactly the
/// gap the iOS and Android work closed.
///
/// All three platforms yield the **full licence documents** for their copyleft
/// components, not just notices. LGPL-2.1 §6 and LGPL-3 §4(b) require a copy of
/// the licence to accompany the binary. Windows used to discharge that by
/// installing the texts beside `ffmpeg.exe`; that binary and its directory were
/// removed on 2026-08-15, so this page is now the copy a Windows user can
/// reach, as it always was on iOS and Android where files inside an `.ipa` or
/// an `.apk` are not user-accessible.
///
/// **The permissive texts ship too, and they are per component rather than per
/// licence.** MIT, ISC, BSD-2-Clause, Apache-2.0 and zlib each require their
/// own notice *and its copyright line* to travel with the binary. The app
/// already renders hundreds of Dart-package licences, and `media_kit`'s own MIT
/// is among them — but that is the wrapper package's copyright, not HarfBuzz's.
/// Reproducing the right template under the wrong holder discharges nothing,
/// which is why these are named `harfbuzz-Old-MIT.txt` and the like.
///
/// Six of the seven are shared with the Apple set — libass, dav1d, HarfBuzz,
/// libxml2, Mbed TLS and FreeType. The sets differ at BOTH ends and the count
/// hid it: zlib is Android-only, and libpng is Apple-only. That sharing is
/// measured, not assumed: the texts are byte-identical at both platforms' pins even where the
/// component versions differ — dav1d 1.2.0/1.2.1, HarfBuzz 7.2.0/8.1.1, Mbed
/// TLS 3.4.0/3.4.1, libxml2 2.10.3/2.11.5, FreeType 2.13.0/2.13.2. **zlib is
/// the one exception and is Android-only**, because Android statically compiles
/// it in while iOS resolves the system dylib.
///
/// That measurement is recorded in
/// `docs/release/evidence/license-sources/PACKAGED-LICENCE-TEXT-PROVENANCE.md`.
/// Until 2026-08-15 it was asserted here and in the test and written down
/// nowhere, so the two surfaces stating it were each other's only support.
/// Worth checking rather than assuming, because FreeType is this project's own
/// precedent for a licence text that differs by version.
///
/// **Do not generalise one platform's component list to another.** Android and
/// iOS draw from the same upstream project through sibling build repos, and
/// nine of their twelve component rows still differ: Android has no uchardet
/// and no libpng, conveys its own statically linked zlib where iOS resolves the
/// system one, and pins six shared components at different versions. Copying
/// the iOS list across would have published four wrong facts.
class NativeLicenses {
  static bool _registered = false;

  /// Safe to call more than once; only the first call registers.
  ///
  /// [LicenseRegistry.addLicense] appends a provider rather than replacing one,
  /// so calling it twice would list every entry twice.
  static void register() {
    if (_registered) return;
    _registered = true;

    if (kIsWeb) return;

    if (PlatformUtils.isWindows) {
      LicenseRegistry.addLicense(_windowsEntries);
    } else if (PlatformUtils.isIOS) {
      LicenseRegistry.addLicense(_appleEntries);
    } else if (PlatformUtils.isAndroid) {
      LicenseRegistry.addLicense(_androidEntries);
    }

    // DeepFilterNet's `df` runtime is separately delivered on Windows and
    // Android. Its Rust tree is not covered by the vodozemac tree below and
    // cannot be discovered from Flutter package metadata.
    if (PlatformUtils.isWindows || PlatformUtils.isAndroid) {
      LicenseRegistry.addLicense(_libdfRustEntries);
    }

    // Unconditional, and deliberately outside the platform chain above. The
    // Rust encryption tree is the one native component this app links on
    // *every* platform, macOS included - it is not part of the media bundle
    // the macOS hold defers, and a macOS build links it exactly like the
    // others. Gating it per platform would recreate the gap on whichever
    // platform was forgotten.
    LicenseRegistry.addLicense(_rustEntries);
  }

  /// The iOS entries, without needing to run on iOS.
  ///
  /// [register] gates on the real platform, so on any other host the Apple
  /// branch is unreachable and its licence documents would go untested — which
  /// is the half that discharges an obligation.
  @visibleForTesting
  static Stream<LicenseEntry> appleEntriesForTest() => _appleEntries();

  /// The Windows entries, for the same reason as [appleEntriesForTest].
  ///
  /// Windows began loading its licence documents from the asset bundle when
  /// `ffmpeg.exe` was removed, so its document limb is now as testable — and as
  /// breakable — as the Apple one.
  @visibleForTesting
  static Stream<LicenseEntry> windowsEntriesForTest() => _windowsEntries();

  /// The Android entries, for the same reason as [appleEntriesForTest].
  ///
  /// Android is the platform this project shipped uncovered for eight releases,
  /// so its branch is the one that most needs a check that does not depend on
  /// running the real OS.
  @visibleForTesting
  static Stream<LicenseEntry> androidEntriesForTest() => _androidEntries();

  /// The cross-platform Rust entries, for the same reason as the others.
  @visibleForTesting
  static Stream<LicenseEntry> rustEntriesForTest() => _rustEntries();

  /// The Windows/Android DeepFilterNet libDF Rust entries.
  @visibleForTesting
  static Stream<LicenseEntry> libdfRustEntriesForTest() => _libdfRustEntries();
}

/// Windows ships one third-party native media component: `libmpv-2.dll`, which
/// statically carries its own FFmpeg. `ffmpeg.exe` was removed on 2026-08-15
/// along with story video trim, taking this project's only GPL obligation with
/// it — see `docs/DECISIONS.md`.
Stream<LicenseEntry> _windowsEntries() async* {
  const String libmpv = 'mpv / libmpv (libmpv-2.dll)';
  const String direct3d = 'Microsoft Direct3D Compiler (d3dcompiler_47.dll)';
  const String webView2 = 'Microsoft Edge WebView2 Loader (Webview2Loader.dll)';

  yield const LicenseEntryWithLineBreaks(<String>[libmpv], _libmpvNotice);

  // The documents themselves, not just the notice above. These used to be
  // installed as files beside ffmpeg.exe; with that directory gone, the in-app
  // page is the only place a Windows user can read them.
  //
  // libmpv itself is LGPL-2.1, but the FFmpeg compiled into it is LGPL-3, and
  // LGPL-3 is drafted as additional permissions on top of GPL-3 and
  // incorporates it by reference — so the GPL-3 text is required too.
  final String lgpl21 = await rootBundle.loadString(
    'assets/licenses/LGPL-2.1.txt',
  );
  final String lgpl3 = await rootBundle.loadString(
    'assets/licenses/LGPL-3.0.txt',
  );
  final String gpl3 = await rootBundle.loadString(
    'assets/licenses/GPL-3.0.txt',
  );

  yield LicenseEntryWithLineBreaks(const <String>[libmpv], lgpl21);
  yield LicenseEntryWithLineBreaks(const <String>[libmpv], lgpl3);
  yield LicenseEntryWithLineBreaks(const <String>[libmpv], gpl3);

  // libwebrtc.dll is the SECOND third-party native media component on Windows,
  // and it went undisclosed here until 2026-08-15. It statically contains 30
  // components — including a THIRD FFmpeg, distinct from both the one inside
  // libmpv-2.dll and the removed ffmpeg.exe.
  //
  // It was missed because every check this project had asked a declaration:
  // the inventory reads lockfiles, and the artefact row recorded the DLL's own
  // licence (BSD-3-Clause-like) rather than what is compiled into it. Found by
  // opening the binary. Fifth instance of that shape; see
  // `docs/security/findings/NATIVE_COMPONENT_COVERAGE_AUDIT_2026-08-15.md`.
  yield const LicenseEntryWithLineBreaks(<String>[
    'WebRTC and its bundled components (libwebrtc.dll)',
  ], _libwebrtcNotice);

  // d3dcompiler_47.dll is a Windows SDK redistributable staged beside the
  // game-capture binaries. The project has not retained the originating SDK
  // distribution and its REDIST/license material, so do not present another
  // Microsoft product agreement as the terms for this specific binary.
  yield const LicenseEntryWithLineBreaks(<String>[direct3d], _direct3dNotice);

  // desktop_webview_window stages this package-pinned DLL beside the app. Its
  // BSD-3-Clause text is bundled as an asset, because the Flutter notice bundle
  // does not include it and a package wrapper's licence is not the loader's.
  yield const LicenseEntryWithLineBreaks(<String>[webView2], _webView2Notice);
  final String webView2License = await rootBundle.loadString(
    'assets/licenses/Microsoft-WebView2-BSD-3-Clause.txt',
  );
  yield LicenseEntryWithLineBreaks(<String>[webView2], webView2License);

  // FFmpeg here is LGPL-2.1-or-later, so LGPL-2.1 above already covers it and
  // is not re-yielded. Nothing in this DLL is GPL: `ffmpeg_branding = "Chrome"`
  // selects the LGPL codec set, read from the build's own recorded gn args
  // rather than inferred from the binary.
}

/// The 18 frameworks media_kit embeds in the iOS app, which are 11 distinct
/// upstream components. Inventory and per-component evidence:
/// `docs/security/findings/APPLE_MEDIA_KIT_COMPONENT_INVENTORY_2026-08-14.md`.
Stream<LicenseEntry> _appleEntries() async* {
  const String ffmpeg = 'FFmpeg (Apple frameworks)';
  const String mpv = 'mpv / libmpv (Apple frameworks)';
  const String fribidi = 'GNU FriBidi (Apple frameworks)';
  const String uchardet = 'uchardet (Apple frameworks)';

  yield const LicenseEntryWithLineBreaks(<String>[ffmpeg], _appleFfmpegNotice);
  yield const LicenseEntryWithLineBreaks(<String>[mpv], _appleMpvNotice);
  yield const LicenseEntryWithLineBreaks(<String>[
    'Bundled media components (Apple frameworks)',
  ], _appleComponentsNotice);

  // The documents themselves. A notice that only names a licence discharges
  // neither LGPL-2.1 §6 nor LGPL-3 §4(b) — both ask for the licence text.
  //
  // FFmpeg here is LGPL-3, and LGPL-3 is drafted as additional permissions on
  // top of GPL-3 and incorporates it by reference, so the LGPL text alone would
  // under-supply by one document.
  final String lgpl3 = await rootBundle.loadString(
    'assets/licenses/LGPL-3.0.txt',
  );
  final String gpl3 = await rootBundle.loadString(
    'assets/licenses/GPL-3.0.txt',
  );
  final String lgpl21 = await rootBundle.loadString(
    'assets/licenses/LGPL-2.1.txt',
  );

  yield LicenseEntryWithLineBreaks(const <String>[ffmpeg], lgpl3);
  yield LicenseEntryWithLineBreaks(const <String>[ffmpeg], gpl3);
  yield LicenseEntryWithLineBreaks(const <String>[
    mpv,
    fribidi,
    uchardet,
  ], lgpl21);

  // The seven permissive components need their texts too, and this was missed
  // once already.
  //
  // The earlier reading was that these components "need attribution in the
  // notice, not the text limb" — that only the LGPL components carry a
  // text-supply obligation. That is WRONG, and each licence says so in its own
  // words:
  //
  //   libass    ISC          "copyright notice and this permission notice
  //                           appear in all copies"
  //   dav1d     BSD-2-Clause "Redistributions in binary form must reproduce the
  //                           above copyright notice, this list of conditions
  //                           and the following disclaimer in the documentation"
  //   HarfBuzz  Old MIT      permission notice in "all copies of this software"
  //   libxml2   MIT          "shall be included in all copies or substantial
  //                           portions of the Software"
  //   Mbed TLS  Apache-2.0   §4(a) "You must give any other recipients of the
  //                           Work ... a copy of this License"
  //   libpng    PNG-2.0      carries its copyright notices and disclaimer
  //   FreeType  FTL          disclaimer is carried in the notice above; the
  //                          text ships here so the set is uniform
  //
  // NAMING A LICENCE IS NOT REPRODUCING IT. These are per-component captures,
  // not generic SPDX templates, because MIT/ISC/BSD-2 require "the above
  // copyright notice" — the component's own holders, which a template does not
  // carry. Each was captured at the pinned version, with the fetch route, the
  // digests and the cross-platform measurement recorded in
  // docs/release/evidence/license-sources/PACKAGED-LICENCE-TEXT-PROVENANCE.md.
  //
  // That file was written 2026-08-15 because this comment used to point at the
  // license-sources/ DIRECTORY, which held per-component material for only two
  // of the then-eleven texts. The capture facts were real but lived only in commit
  // messages. Read the provenance file for what is established and, just as
  // importantly, for the limit: the digest test pins the bytes against drift,
  // it does not establish that the captured file was the right one.
  const Map<String, String> permissive = <String, String>{
    'assets/licenses/libass-ISC.txt': 'libass (Apple frameworks)',
    'assets/licenses/dav1d-BSD-2-Clause.txt': 'dav1d (Apple frameworks)',
    'assets/licenses/harfbuzz-Old-MIT.txt': 'HarfBuzz (Apple frameworks)',
    'assets/licenses/libpng-PNG-2.0.txt': 'libpng (Apple frameworks)',
    'assets/licenses/mbedtls-Apache-2.0.txt': 'Mbed TLS (Apple frameworks)',
    'assets/licenses/libxml2-MIT.txt': 'libxml2 (Apple frameworks)',
    'assets/licenses/freetype-FTL.txt': 'FreeType (Apple frameworks)',
  };

  for (final MapEntry<String, String> e in permissive.entries) {
    final String text = await rootBundle.loadString(e.key);
    yield LicenseEntryWithLineBreaks(<String>[e.value], text);
  }
}

/// The Rust crates that vodozemac's Dart bindings link into the app.
///
/// **This is the one component group that has no file of its own inside an
/// Apple build.** `flutter_vodozemac` ships no prebuilt library. Its podspec
/// runs cargokit at pod-build time and then force-loads the result:
///
/// ```
/// OTHER_LDFLAGS = -force_load ${BUILT_PRODUCTS_DIR}/libvodozemac_bindings_dart.a
/// ```
///
/// The Rust dependency tree is merged into `Runner`; the iOS notification
/// extension also force-loads the archive when built against the pinned
/// patched 0.5.0 wrapper for its backup-decrypt ABI. Both Mach-O files then
/// carry the tree, with no separate Rust framework in the bundle. On Android
/// and Windows the same tree arrives as
/// `libvodozemac_bindings_dart.so` / `.dll`.
///
/// Either way **no generated notice surface can see it**, because every one of
/// them enumerates packages and this is not shipped as a package: not
/// `showLicensePage`'s own registry, which knows only Dart packages; not the
/// Flutter `NOTICES` bundle; not the Gradle notice inventory; not the Play
/// services OSS-licenses baseline. The record and the artefact disagreed and
/// nothing could notice.
///
/// The crates are MIT, Apache-2.0, BSD-3-Clause, Unlicense, 0BSD, Zlib and
/// BSL-1.0. Every one of those requires its notice to travel with a binary
/// distribution, so 59 components plus the Rust standard library had an unmet
/// obligation on all four platforms until 2026-08-19.
///
/// **This is registered on every platform, unlike everything above it, and the
/// reason is evidentiary rather than convenient.** The other component lists
/// come from per-platform build recipes, which is why generalising one across
/// platforms has already published wrong facts here. This list does not: it
/// comes from `rust/Cargo.lock` *inside the shared pub package*, which every
/// platform compiles. The versions were still measured from a real artefact
/// rather than read from that lockfile - the iOS `Runner`, whose embedded
/// cargo paths and mangled symbol names name each crate and version - and the
/// two agree. What genuinely can differ per platform is the Rust toolchain,
/// and with it the standard library's own bundled dependency versions; the
/// notice says so in as many words rather than implying a measurement that was
/// not taken.
///
/// Regenerate with `tools/release/generate_rust_crate_notice.py` in the
/// workspace repo. Evidence, including the symbol sweep and its controls, is
/// at `docs/release/evidence/apple-native-payloads/` and
/// `docs/release/evidence/license-sources/rust-crates/`.
Stream<LicenseEntry> _rustEntries() async* {
  const String rust =
      'vodozemac Rust crates (linked into the app binary on every platform)';

  yield const LicenseEntryWithLineBreaks(<String>[rust], _rustNotice);

  final String text = await rootBundle.loadString(
    'assets/licenses/rust-crates-NOTICE.txt',
  );
  yield LicenseEntryWithLineBreaks(const <String>[rust], text);
}

const String _rustNotice = """
The Matrix end-to-end encryption in this app is vodozemac, written in Rust.

It is not a library the app loads at runtime. The Rust code and everything it
depends on are compiled into a static archive and merged into the application
binary itself, which is why they appear under one heading here rather than as
separate entries. On iOS builds with the pinned patched wrapper, both Runner
and the notification extension contain the statically linked tree; there is
no separate Rust framework file in the bundle. The modified wrapper source
and build instructions are identified in the application's iOS patch source
record for dart-vodozemac 0.5.0.

The entry that follows names all 59 crates with the exact version compiled in,
together with the Rust standard library, and reproduces the full text of every
licence each of them ships.
""";

/// The Rust crate closures compiled into DeepFilterNet's native C API runtime.
///
/// `df.dll` is delivered on Windows and `libdf.so` is delivered on Android.
/// They have a distinct 109-package closure from vodozemac, so sharing the
/// latter's notice would give recipients a plausible but incorrect roster.
Stream<LicenseEntry> _libdfRustEntries() async* {
  const String libdf =
      'DeepFilterNet libDF Rust crates (Windows df.dll and Android libdf.so)';

  yield const LicenseEntryWithLineBreaks(<String>[libdf], _libdfRustNotice);
  final String text = await rootBundle.loadString(
    'assets/licenses/deepfilternet-libdf-rust-crates-NOTICE.txt',
  );
  yield LicenseEntryWithLineBreaks(const <String>[libdf], text);
}

const String _libdfRustNotice = """
The DeepFilterNet native C API runtime is written in Rust and is distributed as
df.dll on Windows and libdf.so on Android. It has its own feature-specific Rust
dependency closure, separate from the app's vodozemac Rust components.

The entry that follows names all 109 selected package/version pairs, together
with the Rust standard library used to build the delivered runtime, and
reproduces every captured licence text. Two MIT declarations are expressly
identified as canonical SPDX MIT mappings because their exact package sources
contain no licence file.
""";

/// The single `libmpv.so` the APK ships per ABI, which statically carries 10
/// distinct upstream components. Inventory and per-component evidence:
/// `docs/security/findings/ANDROID_MEDIA_KIT_COMPONENT_INVENTORY_2026-08-15.md`
/// in the workspace repo.
///
/// Structurally unlike iOS: there, 18 separate frameworks dynamically link each
/// other and `otool -L` closes the graph. Here `DT_NEEDED` lists only six
/// Android platform libraries, so everything third-party is compiled in and the
/// component list rests on the build recipe plus symbol evidence.
Stream<LicenseEntry> _androidEntries() async* {
  const String ffmpeg = 'FFmpeg (Android libmpv.so)';
  const String mpv = 'mpv / libmpv (Android libmpv.so)';
  const String fribidi = 'GNU FriBidi (Android libmpv.so)';
  const List<String> androidXNative = <String>[
    'AndroidX Graphics Path (Android libandroidx.graphics.path.so)',
    'AndroidX DataStore (Android libdatastore_shared_counter.so)',
  ];
  const String sqlite = 'SQLite (Android libsqlite3.so)';
  const String dartJni = 'Dart JNI (Android libdartjni.so)';
  const String cameraSurfaceUtil =
      'AndroidX Camera Core Surface Utility (Android libsurface_util_jni.so)';
  const String cameraImageProcessing =
      'AndroidX Camera Core Image Processing / libyuv '
      '(Android libimage_processing_util_jni.so)';
  const String liveKitNoise = 'LiveKit Noise (Android libnoise.so)';
  const String kissFft = 'KISS FFT (Android libnoise.so)';
  const String webRtcSdk =
      'WebRTC-SDK (Android libjingle_peerconnection_so.so)';

  yield const LicenseEntryWithLineBreaks(<String>[
    ffmpeg,
  ], _androidFfmpegNotice);
  yield const LicenseEntryWithLineBreaks(<String>[mpv], _androidMpvNotice);
  yield const LicenseEntryWithLineBreaks(<String>[
    'Bundled media components (Android libmpv.so)',
  ], _androidComponentsNotice);

  // The documents themselves, for the same reason as the other two platforms:
  // a notice that only names a licence discharges neither LGPL-2.1 §6 nor
  // LGPL-3 §4(b). Files inside an APK are no more reachable to a user than
  // files inside an IPA, so this page is the copy they can actually read.
  //
  // FFmpeg here is LGPL-3, and LGPL-3 is drafted as additional permissions on
  // top of GPL-3 and incorporates it by reference, so the LGPL text alone would
  // under-supply by one document.
  final String lgpl3 = await rootBundle.loadString(
    'assets/licenses/LGPL-3.0.txt',
  );
  final String gpl3 = await rootBundle.loadString(
    'assets/licenses/GPL-3.0.txt',
  );
  final String lgpl21 = await rootBundle.loadString(
    'assets/licenses/LGPL-2.1.txt',
  );

  yield LicenseEntryWithLineBreaks(const <String>[ffmpeg], lgpl3);
  yield LicenseEntryWithLineBreaks(const <String>[ffmpeg], gpl3);
  yield LicenseEntryWithLineBreaks(const <String>[mpv, fribidi], lgpl21);

  // These are separate native APK payloads, not pieces of libmpv.so. The
  // generic Apache file is intentionally attached to component-specific
  // labels: its filename records where the canonical text was first captured,
  // not an attribution to Mbed TLS. Candidate paths, hashes and source routes
  // are in docs/release/evidence/license-sources/android-native-payloads/.
  yield LicenseEntryWithLineBreaks(androidXNative, _androidXNativeNotice);
  final String apache2 = await rootBundle.loadString(
    'assets/licenses/mbedtls-Apache-2.0.txt',
  );
  yield LicenseEntryWithLineBreaks(androidXNative, apache2);

  // Camera Core conveys this as a separate JNI payload. Its exact 1.6.0
  // release build file links this target only to Android system APIs; unlike
  // image_processing_util_jni, it does not link libyuv. The generic Apache
  // text is deliberately attached to the specific binary label, not inferred
  // from the adjacent CameraX payload which remains blocked on libyuv evidence.
  yield const LicenseEntryWithLineBreaks(<String>[
    cameraSurfaceUtil,
  ], _androidCameraSurfaceUtilNotice);
  yield LicenseEntryWithLineBreaks(const <String>[cameraSurfaceUtil], apache2);

  // Flutter's camera_android_camerax plugin brings Camera Core 1.6.0 into the
  // Android package. Its image-processing JNI target links libyuv::yuv; the
  // Camera Core POM declares that conveyed limb BSD-3-Clause. Attach libyuv's
  // own notice, not the Flutter wrapper's BSD text or Camera Core's Apache text.
  yield const LicenseEntryWithLineBreaks(<String>[
    cameraImageProcessing,
  ], _androidCameraImageProcessingNotice);
  final String libyuvBsd = await rootBundle.loadString(
    'assets/licenses/libyuv-BSD-3-Clause.txt',
  );
  yield LicenseEntryWithLineBreaks(const <String>[
    cameraImageProcessing,
  ], libyuvBsd);

  // This is the Apache-2.0 LiveKit container that conveys libnoise.so. KISS
  // FFT remains a separately attributed BSD-3-Clause static limb below; the
  // Maven source JAR does not establish a native rebuild, which this notice
  // does not claim.
  yield const LicenseEntryWithLineBreaks(<String>[
    liveKitNoise,
  ], _androidLiveKitNoiseNotice);
  yield LicenseEntryWithLineBreaks(const <String>[liveKitNoise], apache2);

  // SQLite core is public domain, while the Dart sqlite3 package is a separate
  // MIT-licensed wrapper. This statement makes the conveyed native payload
  // visible without attaching the wrapper's licence to the wrong component.
  yield const LicenseEntryWithLineBreaks(<String>[
    sqlite,
  ], _androidSqliteNotice);

  yield const LicenseEntryWithLineBreaks(<String>[dartJni], _androidJniNotice);
  final String jniBsd = await rootBundle.loadString(
    'assets/licenses/dart-jni-BSD-3-Clause.txt',
  );
  yield LicenseEntryWithLineBreaks(const <String>[dartJni], jniBsd);
  yield LicenseEntryWithLineBreaks(const <String>[dartJni], apache2);

  // KISS FFT is statically linked into libnoise.so and is invisible to every
  // generated notice surface: it is absent from the Flutter NOTICES bundle,
  // from the Gradle notice inventory and from the Play services OSS-licenses
  // baseline, because none of them see inside a native artefact. The
  // containing Gradle module (io.livekit:noise, Apache-2.0) IS surfaced by
  // those routes, which is exactly why the gap was easy to miss. BSD-3-Clause
  // requires this notice to travel with a binary distribution, so it is
  // yielded here rather than inherited from the container's licence.
  yield const LicenseEntryWithLineBreaks(<String>[
    kissFft,
  ], _androidKissFftNotice);
  final String kissFftBsd = await rootBundle.loadString(
    'assets/licenses/kissfft-BSD-3-Clause.txt',
  );
  yield LicenseEntryWithLineBreaks(const <String>[kissFft], kissFftBsd);

  // The Maven POM names the wrapper's BSD-3-Clause declaration, but the exact
  // release AAR carries a WebRTC notice packet for the static component set.
  // The AAR itself ships no readable notice asset, so attaching only the POM
  // declaration would repeat the native-container gap KISS FFT exposed.
  yield const LicenseEntryWithLineBreaks(<String>[
    webRtcSdk,
  ], _androidWebRtcSdkNotice);
  final String webRtcSdkNotices = await rootBundle.loadString(
    'assets/licenses/webrtc-sdk-android-137.7151.04-NOTICES.txt',
  );
  yield LicenseEntryWithLineBreaks(const <String>[webRtcSdk], webRtcSdkNotices);

  // The permissive components. Naming a licence is not reproducing it: MIT,
  // ISC, BSD-2-Clause, Apache-2.0 and zlib all require their own notice — with
  // their own copyright line — to travel with a binary distribution. A wrapper
  // package's MIT is a different licence with a different copyright holder and
  // discharges nothing here.
  //
  // The loop below loads EIGHT assets, of which SIX are shared with the Apple
  // set. The two that are not: zlib is Android-only (see the note at its entry)
  // and the media-kit helper is separately conveyed under its own MIT holder.
  // This comment said "seven files are shared" - wrong on both halves of the
  // sentence, and contradicted by the class doc above, which has the right
  // figure. Measured rather than assumed: the six shared texts are
  // byte-identical at both platforms' pins even where the component versions
  // differ. Five of the six are cross-pinned below (dav1d 1.2.0/1.2.1,
  // HarfBuzz 7.2.0/8.1.1, Mbed TLS 3.4.0/3.4.1, libxml2 2.10.3/2.11.5,
  // FreeType 2.13.0/2.13.2); libass is the sixth and shares one pin, 0.17.1,
  // so it has no version pair to name.
  for (final (String asset, List<String> packages) in <(String, List<String>)>[
    ('assets/licenses/libass-ISC.txt', <String>['libass (Android libmpv.so)']),
    (
      'assets/licenses/dav1d-BSD-2-Clause.txt',
      <String>['dav1d (Android libmpv.so)'],
    ),
    (
      'assets/licenses/harfbuzz-Old-MIT.txt',
      <String>['HarfBuzz (Android libmpv.so)'],
    ),
    (
      'assets/licenses/libxml2-MIT.txt',
      <String>['libxml2 (Android libmpv.so)'],
    ),
    (
      'assets/licenses/mbedtls-Apache-2.0.txt',
      <String>['Mbed TLS (Android libmpv.so)'],
    ),
    (
      'assets/licenses/freetype-FTL.txt',
      <String>['FreeType (Android libmpv.so)'],
    ),
    // zlib is ANDROID-ONLY. It is statically compiled into libmpv.so here and
    // conveyed; iOS resolves the system libz.1.dylib and conveys nothing, so
    // this entry must not be copied into the Apple set. It is also the one
    // component no declarative source names — absent from the recipe's
    // depinfo.sh entirely, found only by reading the binary.
    ('assets/licenses/zlib-Zlib.txt', <String>['zlib (Android libmpv.so)']),
    // The helper is separately conveyed by the APK, not statically linked into
    // libmpv.so. It has its own MIT copyright holder, so none of the other
    // MIT texts can stand in for its notice.
    (
      'assets/licenses/media-kit-android-helper-MIT.txt',
      <String>[
        'media-kit-android-helper (Android libmediakitandroidhelper.so)',
      ],
    ),
  ]) {
    yield LicenseEntryWithLineBreaks(
      packages,
      await rootBundle.loadString(asset),
    );
  }
}

const String _libwebrtcNotice = '''
The Windows desktop build bundles libwebrtc.dll, the real-time communication
library used for calls, screen sharing and gameplay streaming. It is a patched
build of WebRTC. Its two patched source trees are public:

  https://github.com/Inter-Galactic-App/webrtc-core
    branch intergalactic/windows-streaming-m137
    commit c6bf02fe64a993fa9d34d44957db71615ec98ddd

  https://github.com/Inter-Galactic-App/libwebrtc
    branch intergalactic/windows-hardware-h264
commit c8619a6d98d49939b6affe642a037d9f5a6ed9d5

Unlike the other components on this page, these are NOT served from
https://app.ourgalaxy.space/source/ — they are whole git repositories rather
than archives. Stating that plainly because a notice that points at an address
which does not hold the file is worse than one that names the right place.

WebRTC itself is under the BSD 3-Clause licence. That licence covers the
project, NOT the thirty third-party components statically compiled into this
DLL. Those are listed with their exact upstream revisions and licence digests
in the release evidence.

The ones with their own obligations are:

  - FFmpeg, under the LGPL version 2.1 or later. This is a THIRD FFmpeg,
    separate from the one inside libmpv-2.dll and from the ffmpeg.exe that
    earlier releases carried. It is Chromium's fork, built with
    ffmpeg_branding = "Chrome", which selects the LGPL codec set; the build
    sets no GPL option and no GPL-licensed FFmpeg component is compiled in.
  - OpenH264, under the BSD 2-Clause licence, from Cisco. H.264 support is
    enabled in this build.
  - BoringSSL, libvpx, libaom, dav1d, libsrtp, libyuv, Opus, Abseil,
    Protocol Buffers, libjpeg-turbo, crc32c, RNNoise and others, under
    permissive licences (BSD, Apache 2.0 and MIT variants).

Inter Galactic does not modify the third-party components. The WebRTC build
itself is patched, and those patches are part of the corresponding source.

This component was absent from this page until 2026-08-15. The omission was
not a judgement that it did not matter: every check in place asked a build
declaration what shipped, and a declaration names its direct inputs and is
blind to what is compiled in beneath them. It was found by reading the binary.
The same method had already produced three earlier corrections on this page,
and the note is kept here so the reason is visible rather than only the fix.

Full details — every component's revision, licence file digest and upstream
repository — are recorded in the release evidence for this build.
''';

const String _direct3dNotice = '''
The Windows desktop build includes Microsoft Direct3D Compiler
(d3dcompiler_47.dll) with the optional game-capture support binaries. It is an
application-local Windows SDK redistributable, not a Windows system DLL.

Microsoft's DirectX documentation identifies the D3DCompiler API and
redistributable DLL as a Windows SDK component that may be distributed
application-local with an application:

  https://learn.microsoft.com/en-us/windows/win32/directx-sdk--august-2009-

The Windows SDK distribution, REDIST record, and exact license terms from which
this particular DLL was staged were not retained in this project's evidence.
This entry therefore does not assert an exact Microsoft terms URL for this
binary, and it does not replace or modify Microsoft's terms.
''';

const String _webView2Notice = '''
The Windows desktop build includes Microsoft Edge WebView2 Loader
(Webview2Loader.dll), version 1.0.992.28, to support embedded web content.
It is distributed application-local with the app by desktop_webview_window.

The full BSD 3-Clause licence text from the exact Microsoft.Web.WebView2
1.0.992.28 package is included below. Microsoft documents the loader
distribution model at:

  https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/distribution
''';

const String _libmpvNotice = '''
This software uses mpv (libmpv) licensed under the LGPL version 2.1 or later,
and its source can be downloaded from:

  https://app.ourgalaxy.space/source/

libmpv-2.dll is bundled with the Windows desktop build for video playback and
is loaded dynamically. mpv is licensed under the GPL by default and under the
LGPL only when built with -Dgpl=false; the library shipped here was built with
that option, and records it in its own build configuration.

Inter Galactic does not modify mpv. The published source archive is upstream mpv
at revision 652a1dd90711839acdccc08004056d25514ef2d8, unmodified.

libmpv statically contains its own copy of FFmpeg, version n6.0, under the LGPL
version 3 or later. Its corresponding source is covered by the published source
offer above, and the LGPL version 3 and GPL version 3 texts it requires are
included on this page.

Earlier Windows releases, from 0.7.4+985 through 0.8.0+993, also shipped a
separate ffmpeg.exe program at version n8.1.1 for story video recording and
export. That binary is no longer part of this app. It is a different FFmpeg from
the one inside this library, and its corresponding source remains published at
the address above for the releases that carried it.

Also compiled in: MuJS, under the ISC licence. Shipped alongside it: ANGLE
(libEGL.dll and libGLESv2.dll), under the BSD 3-Clause licence; and SwiftShader
(vk_swiftshader.dll), under the Apache License 2.0.

Inter Galactic is not affiliated with or endorsed by the mpv project.
''';

const String _appleFfmpegNotice = '''
This software uses code of FFmpeg licensed under the LGPL version 3 or later,
and its source can be downloaded from:

  https://app.ourgalaxy.space/source/

On iOS, FFmpeg version 6.0 is bundled through media_kit as six separate,
dynamically linked frameworks - Avcodec, Avformat, Avutil, Avfilter, Swresample
and Swscale - built by media-kit/libmpv-darwin-build v0.6.0. They are separate
dynamic frameworks rather than code linked into the app.

Swapping a framework inside an installed app is not a route iOS allows: the app
bundle and each nested framework are separately code-signed, and iOS refuses to
launch a bundle whose signature no longer matches. The route that does work is
the one the offer above serves - take the corresponding source, modify the
library, and rebuild and sign the app with it.

THIS FFmpeg IS MODIFIED. The libmpv-darwin-build v0.6.0 recipe applies four
patches to FFmpeg 6.0 before configuring it, unconditionally:

  - ffmpeg-fix-vp9-hwaccel        adds a VideoToolbox VP9 decoder
  - ffmpeg-fix-hls-mp4-seek
  - ffmpeg-fix-ios-hdr-texture
  - ffmpeg-fix-dash-base-url-escape

These are functional source changes, not packaging. Corresponding source for a
modified library has to include the modifications, so the upstream 6.0 archive
alone does not describe this binary: the four patches are part of the
corresponding source that the offer above covers.

This shares an upstream release with the FFmpeg inside the Windows
libmpv-2.dll, but is NOT the same source: that one is unmodified and this one
carries the four patches above. Do not treat one archive as covering both.

A third FFmpeg, the standalone ffmpeg.exe at version n8.1.1, shipped with
Windows desktop releases 0.7.4+985 through 0.8.0+993 and is no longer part of
this app. It was different again. All are covered, separately, by the
published source offer.

Each of the six frameworks reports --enable-version3 and does not report
--enable-gpl or --enable-nonfree, read from the shipped binaries rather than
from a build recipe.

Those flags govern FFmpeg's own directly enabled components. They do not reach
code pulled in beneath those components - that is how a GPL component reached
the Windows build unnoticed. So the absence of GPL code here does not rest on
them. It rests on the dependency graph of the 18 shipped frameworks being
closed, with every dependency itself one of the 18, plus direct probes of the
binaries for the components that have caused this before, all of which came back
absent.

Stated precisely: no GPL-licensed code was found by the checks that caught the
previous case. A component compiled statically inside one of these frameworks
would evade both checks, so this is not a claim that none can exist.

Full details, including the component inventory, versions and checksums, are
published alongside the source at the address above.

FFmpeg is a trademark of Fabrice Bellard. Inter Galactic is not affiliated with
or endorsed by the FFmpeg project.
''';

const String _appleMpvNotice = '''
This software uses mpv (libmpv) version 0.36.0, licensed under the LGPL version
2.1 or later, and its source can be downloaded from:

  https://app.ourgalaxy.space/source/

mpv is licensed under the GPL by default and under the LGPL only when built with
-Dgpl=false. The framework shipped here embeds its own build configuration, and
that configuration records -Dgpl=false along with -Dcplayer=false and
-Dlibmpv=true: it is the LGPL build, and a library rather than the player.

THIS mpv IS MODIFIED. The libmpv-darwin-build v0.6.0 recipe applies
mpv-fix-missing-objc.patch unconditionally. That modification is part of the
corresponding source the offer above covers.

It is also a different base from the Windows one. This is upstream 0.36.0; the
Windows libmpv-2.dll is built from revision 652a1dd90711839acdccc08004056d25514ef2d8
and is unpatched. Neither the base nor the modification state matches, so the
archive published for the Windows build does not serve this one.

Unlike the Windows build, where libmpv statically contains its own copy of
FFmpeg, the iOS build links FFmpeg as separate dynamic frameworks, listed
separately above.
''';

const String _appleComponentsNotice = '''
The iOS build bundles the following additional components through media_kit,
each as a separate dynamically linked framework, from
media-kit/libmpv-darwin-build v0.6.0. Source for the copyleft components can be
downloaded from:

  https://app.ourgalaxy.space/source/

  - libass 0.17.1               ISC licence
  - dav1d 1.2.1                 BSD 2-Clause licence
  - GNU FriBidi 1.0.13          LGPL version 2.1 or later
  - HarfBuzz 8.1.1              "Old MIT" licence
  - libpng 1.6.40               PNG Reference Library licence v2
  - Mbed TLS 3.4.1              Apache licence 2.0
  - FreeType 2.13.2             FreeType Project licence (FTL)
  - libxml2 2.11.5              MIT licence
  - uchardet 0.0.8              LGPL version 2.1 or later

The full text of every licence above is included in this app, listed under the
component it covers. Each was taken from the component's own source at the
version shipped here, so the copyright holders named in it are that component's
own.

FreeType is dual licensed under the FreeType Project licence and the GPL version
2 or later; it is used here under the FreeType Project licence.

That licence requires, as a condition of redistributing in binary form, a
disclaimer in the accompanying documentation:

  This software is based in part of the work of the FreeType Team.

It separately gives a preferred form of credit, which it encourages rather than
requires:

  Portions of this software are copyright © 2023 The FreeType
  Project (www.freetype.org).  All rights reserved.

uchardet is available under the Mozilla Public Licence 1.1, the GPL version 2 or
later, or the LGPL version 2.1 or later; it is used here under the LGPL version
2.1 or later.

The patches the libmpv-darwin-build v0.6.0 recipe applies are to FFmpeg and mpv,
listed with those components above; no patch to the nine components here has
been identified. That is the recipe as read, not an audit of each component, so
it is stated as what was found rather than as a guarantee.

zlib and libiconv are also used, but are provided by the operating system rather
than bundled here.
''';

const String _androidFfmpegNotice = '''
This software uses code of FFmpeg licensed under the LGPL version 3 or later,
and its source can be downloaded from:

  https://app.ourgalaxy.space/source/

On Android, FFmpeg version n6.0 is bundled through media_kit, compiled
statically into a single libmpv.so, built by media-kit/libmpv-android-video-build
v1.1.7. This release ships that library for two ABIs - arm64-v8a and armeabi-v7a.
Releases up to and including 0.8.1+996 also carried an x86_64 copy, and the
corresponding-source offer above covers those releases too. Unlike the iOS build,
where FFmpeg is six separate dynamic frameworks, it is linked into the library
here and cannot be replaced independently of it.

THIS FFmpeg IS MODIFIED. The libmpv-android-video-build v1.1.7 recipe applies
two patches to FFmpeg n6.0 before configuring it, unconditionally:

  - dash_base_url_escape   escapes XML special characters in the DASH
                           base URL, in libavformat/dashdec.c
  - hls_mp4_seek           re-fetches the HLS init segment on seek, in
                           libavformat/hls.c

These are functional source changes, not packaging. Corresponding source for a
modified library has to include the modifications, so the upstream n6.0 archive
alone does not describe this binary: the two patches are part of the
corresponding source that the offer above covers, and both are published there
beside it.

Both patches are byte-identical to two of the four already published for the iOS
build, verified by digest rather than by name. The iOS build applies those two
plus two more that Android does not, so the iOS FFmpeg and this one are NOT the
same source. The FFmpeg inside the Windows libmpv-2.dll shares the same n6.0
upstream release and is unmodified, so it is different again. All three are
covered, separately, by the published source offer.

A fourth FFmpeg, the standalone ffmpeg.exe at version n8.1.1, shipped with
Windows desktop releases 0.7.4+985 through 0.8.0+993 and is no longer part of
this app.

The build configuration is embedded in the shipped library and reports
--disable-gpl, --disable-nonfree and --enable-version3 explicitly, read from the
binary rather than from a build recipe. Each of the six FFmpeg libraries inside
it - libavcodec, libavformat, libavutil, libavfilter, libswscale and
libswresample - separately reports "LGPL version 3 or later".

Those flags govern FFmpeg's own directly enabled components. They do not reach
code pulled in beneath those components - that is how a GPL component reached
the Windows build unnoticed. So the absence of GPL code here does not rest on
them. It rests on the upstream project publishing its GPL-bearing build as a
separate "encoders-gpl" flavour that this app does not consume, on the build
recipe naming FFmpeg's external libraries exhaustively as Mbed TLS, dav1d and
libxml2, and on direct probes of the binary for the components that have caused
this before, all of which came back absent.

Stated precisely: no GPL-licensed code was found by the checks that caught the
previous case. A component compiled statically inside this library and emitting
no recognisable symbol would evade those checks, so this is not a claim that
none can exist. Android compiles everything into one library, so there is no
linkage graph to close as a second check, and that limitation is real.

Full details, including the component inventory, versions and checksums, are
published alongside the source at the address above.

FFmpeg is a trademark of Fabrice Bellard. Inter Galactic is not affiliated with
or endorsed by the FFmpeg project.
''';

const String _androidXNativeNotice = '''
This Android build bundles native AndroidX code from Graphics Path 1.0.1
(libandroidx.graphics.path.so) and DataStore 1.1.7
(libdatastore_shared_counter.so). Both components are licensed under the
Apache License, Version 2.0. The full licence text is included below.

The candidate-specific component and payload record, including the two APK ABI
paths and hashes, is maintained with this app's third-party licence inventory.
These native payloads are separate from the Android libmpv media bundle.
''';

const String _androidSqliteNotice = '''
This Android build bundles SQLite 3.52.0 (libsqlite3.so) through the
sqlite3-native-library runtime package. SQLite core code is dedicated to the
public domain; this native library is distinct from the MIT-licensed Dart
sqlite3 wrapper package.
''';

const String _androidKissFftNotice = '''
This Android build bundles KISS FFT, statically linked into libnoise.so. That
native library is delivered by the Gradle module io.livekit:noise 2.0.0, which
is itself Apache-2.0 and republishes the com.paramsen.noise FFT wrapper; KISS
FFT is a separate BSD-3-Clause work by Mark Borgerding and its notice is
reproduced in full below.

The revision is pinned. livekit/noise is a fork of paramsen/noise and carries
KISS FFT as a git submodule of mborgerding/kissfft, pinned at
d74fd2adaffdf4489441a12e0258423b9f5b8e12. The text below is that revision's
COPYING file, reproduced verbatim.
''';

const String _androidCameraSurfaceUtilNotice = '''
This Android build bundles the AndroidX Camera Core 1.6.0 surface utility JNI
runtime (libsurface_util_jni.so). It is separately conveyed in the Camera Core
AAR for arm64-v8a and armeabi-v7a. The exact CameraX 1.6.0 release source builds
this target from surface_util_jni.cc under Apache-2.0 and links it only to the
Android native-window API; it does not include the separate libyuv-linked image
processing utility. The full Apache-2.0 text is included below.
''';

const String _androidCameraImageProcessingNotice = '''
This Android build bundles AndroidX Camera Core 1.6.0's image-processing JNI
runtime (libimage_processing_util_jni.so), conveyed by Flutter's
camera_android_camerax implementation. Camera Core's published build source
links this target to libyuv, and its Maven publication declares BSD-3-Clause
for that included component.

The full libyuv BSD-3-Clause notice, including the LibYuv Project Authors
copyright and non-endorsement clause, is included below. This record identifies
the published dependency and notice route; it does not claim a native rebuild
or a separate corresponding-source offer.
''';

const String _androidLiveKitNoiseNotice = '''
This Android build bundles the LiveKit Noise 2.0.0 native runtime
(libnoise.so), conveyed by the io.livekit:noise 2.0.0 Maven AAR. LiveKit's
published POM declares Apache License 2.0 and its matching source JAR identifies
the com.paramsen.noise JNI wrapper that loads this library. The AAR itself has
no LICENSE or NOTICE entry, so the complete Apache-2.0 text is included below.

KISS FFT is a separately attributed BSD-3-Clause work statically linked into
this library; it has its own notice entry. This record does not claim that the
Maven source JAR can rebuild the native library or establishes a source offer.
''';

const String _androidWebRtcSdkNotice = '''
This Android build bundles the precompiled WebRTC-SDK Android runtime in
libjingle_peerconnection_so.so through io.github.webrtc-sdk:android 137.7151.04.

The published v137.7151.04 libwebrtc.aar and the Maven AAR used by this build
are byte-identical. The full upstream notice packet for that exact release is
reproduced below under this component label. It covers WebRTC and the bundled
third-party components; it is not the MIT licence of the release-wrapper
repository, and it does not claim that this application can reproduce the
binary from source.
''';

const String _androidJniNotice = '''
This Android build bundles the Dart JNI 1.0.0 native runtime (libdartjni.so).
The native target is BSD 3-Clause licensed by the Dart project authors and
includes Android NDK JNI interface material under Apache License 2.0. Full
texts for both licences are included below.
''';

const String _androidMpvNotice = '''
This software uses mpv (libmpv), licensed under the LGPL version 2.1 or later,
and its source can be downloaded from:

  https://app.ourgalaxy.space/source/

mpv is licensed under the GPL by default and under the LGPL only when built with
-Dgpl=false. The library shipped here embeds its own build configuration, and
that configuration records -Dgpl=false along with -Dcplayer=false and
-Dlibmpv=true: it is the LGPL build, and a library rather than the player.

THIS mpv IS MODIFIED. The libmpv-android-video-build v1.1.7 recipe applies
mpv_lavc_set_java_vm.patch unconditionally, which adds an exported
mpv_lavc_set_java_vm() function so the statically linked libavcodec can reach
the Java VM for MediaCodec hardware decoding. That modification is part of the
corresponding source the offer above covers.

It is also a different base from either other platform. This is upstream mpv at
revision 78d43740f52db817d98bcf24fb30a76ab6fa13ff, which is 549 commits after
the 0.36.0 release; the iOS build is the 0.36.0 release itself, and the Windows
libmpv-2.dll is revision 652a1dd90711839acdccc08004056d25514ef2d8. Three
artefacts, three different revisions. No archive published for one of them
serves either of the others.

Unlike the iOS build, where FFmpeg and the supporting libraries are separate
dynamic frameworks, the Android build compiles all of them into this single
library. They are listed separately above and below.
''';

const String _androidComponentsNotice = '''
The Android build compiles the following additional components into libmpv.so,
from media-kit/libmpv-android-video-build v1.1.7. Source for the copyleft
components can be downloaded from:

  https://app.ourgalaxy.space/source/

  - libass 0.17.1               ISC licence
  - FreeType 2.13.0             FreeType Project licence (FTL)
  - GNU FriBidi 1.0.12          LGPL version 2.1 or later
  - HarfBuzz 7.2.0              "Old MIT" licence
  - Mbed TLS 3.4.0              Apache licence 2.0
  - dav1d 1.2.0                 BSD 2-Clause licence
  - libxml2 2.10.3              MIT licence
  - zlib 1.2.12                 zlib licence

These versions are NOT the same as the iOS ones, even though both builds come
from the same upstream project. Six of the components above are pinned at a
different version there, and the two builds do not carry the same set: the iOS
build includes uchardet and libpng, which this one does not.

zlib is compiled into this library on Android rather than being provided by the
operating system as it is on iOS, so it is listed here.

The APK also ships libmediakitandroidhelper.so, from
media-kit/media-kit-android-helper, under the MIT licence.

FreeType is dual licensed under the FreeType Project licence and the GPL version
2 or later; it is used here under the FreeType Project licence.

That licence requires, as a condition of redistributing in binary form, a
disclaimer in the accompanying documentation:

  This software is based in part of the work of the FreeType Team.

It separately gives a preferred form of credit, which it encourages rather than
requires:

  Portions of this software are copyright © 2023 The FreeType
  Project (www.freetype.org).  All rights reserved.

The patches the libmpv-android-video-build v1.1.7 recipe applies are to FFmpeg
and mpv, listed with those components above; no patch to the eight components
here has been identified. That is the recipe as read, not an audit of each
component, so it is stated as what was found rather than as a guarantee.
''';
