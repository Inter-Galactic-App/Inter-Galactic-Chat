import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show ByteData, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/native_licenses.dart';

/// These assertions are the cross-platform half of what
/// `tools/release/Assert-PackagedLicenceNotice.ps1` does for the Windows
/// payload. That gate is PowerShell and does not run on the Mac that produces
/// the iOS archive, so without this the iOS licence documents have no gate at
/// all — and they are the ones LGPL-2.1 §6 / LGPL-3 §4(b) actually require to
/// travel with the binary.
///
/// The shape is deliberate: assert the documents are *real texts*, not that
/// files exist. An empty or stub asset would satisfy "it is bundled" and
/// discharge nothing.
///
/// Uses `test` rather than `testWidgets`, and resolves the entries once in
/// `setUpAll`. A first draft used `testWidgets` and re-resolved the stream in
/// every case; its second case **hung for the full ten-minute timeout** rather
/// than failing. Restructuring to a plain `test` with a single `setUpAll`
/// resolution removed it — the suite now finishes in under a second.
///
/// The precise cause was **not** isolated, and the obvious explanation is not
/// quite right: `testWidgets` runs in a fake-async zone, but the *first* case
/// awaited `rootBundle` there and passed. So treat this as "do not re-resolve
/// the stream per case inside `testWidgets`" rather than a diagnosis. Anyone
/// reintroducing that shape should expect a hang and run with `--timeout`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<LicenseEntry> entries;
  late List<String> texts;
  late String everything;

  String textOf(LicenseEntry e) =>
      e.paragraphs.map((LicenseParagraph p) => p.text).join('\n');

  setUpAll(() async {
    entries = await NativeLicenses.appleEntriesForTest().toList();
    texts = entries.map(textOf).toList();
    everything = texts.join('\n');
  });

  group('iOS native licence entries', () {
    test('the required licence documents are present and are real texts', () {
      // FFmpeg here is LGPL-3, which incorporates GPL-3 by reference, so the
      // LGPL text alone would under-supply by one document.
      final String lgpl3 = texts.firstWhere(
        (String t) =>
            t.contains('GNU LESSER GENERAL PUBLIC LICENSE') &&
            t.contains('Version 3'),
        orElse: () => '',
      );
      final String gpl3 = texts.firstWhere(
        (String t) =>
            t.contains('GNU GENERAL PUBLIC LICENSE') &&
            t.contains('Version 3') &&
            !t.contains('LESSER'),
        orElse: () => '',
      );
      final String lgpl21 = texts.firstWhere(
        (String t) =>
            t.contains('GNU LESSER GENERAL PUBLIC LICENSE') &&
            t.contains('Version 2.1'),
        orElse: () => '',
      );

      expect(lgpl3, isNotEmpty, reason: 'LGPL-3.0 text missing');
      expect(gpl3, isNotEmpty, reason: 'GPL-3.0 text missing');
      expect(lgpl21, isNotEmpty, reason: 'LGPL-2.1 text missing');

      // Size floors catch a pointer stub or a truncated copy.
      expect(lgpl3.length, greaterThan(5000));
      expect(gpl3.length, greaterThan(20000));
      expect(lgpl21.length, greaterThan(20000));
    });

    test('the licence documents are the exact canonical texts', () async {
      // SIZE IS NOT ENOUGH, and the proof is in this project's own evidence:
      // S&C's FreeType capture found the FTL text at VER-2-13-2 differing from
      // master INSIDE THE CREDIT LINE while both files are exactly 6,743 bytes.
      // A size check is sound against a missing or truncated document and blind
      // to a wrong-version one — which for a licence is the failure that
      // matters, because the wrong version is still a plausible licence text.
      //
      // These digests were taken from the canonical copies that used to live at
      // intergalactic/windows/third_party/ffmpeg/licenses/. That directory was
      // deleted with ffmpeg.exe on 2026-08-15, so assets/licenses/ is now the
      // only copy in the repo and these constants are what pins it — there is
      // no second tracked file left to compare against. LGPL-3.0 is also the
      // digest already published as ffmpeg-LICENSE-LGPL-3.0.txt, so this asserts
      // the text a user reads in the app is the text offered publicly.
      //
      // That publication record is `tools/release/third-party-source.json` in
      // the WORKSPACE repo, not this one. Saying so because searching this repo
      // for it finds nothing, and "the cited file does not exist" is the wrong
      // conclusion to reach about a compliance claim.
      //
      // An unequal digest is not a formatting nit to fix by updating the
      // constant: a licence document is verbatim upstream, so a changed digest
      // means the wrong file is shipping.
      const Map<String, String> expected = <String, String>{
        'assets/licenses/LGPL-3.0.txt':
            'da7eabb7bafdf7d3ae5e9f223aa5bdc1eece45ac569dc21b3b037520b4464768',
        'assets/licenses/GPL-3.0.txt':
            'e6037104443f9a7829b2aa7c5370d0789a7bda3ca65a0b904cdc0c2e285d9195',
        'assets/licenses/LGPL-2.1.txt':
            '20e50fe7aae3e56378ebf0417d9de904f55a0e61e4df315333e632a4d3555d95',
        // The seven permissive texts, each captured from its own component at
        // the pinned version rather than from an SPDX template -- MIT/ISC/BSD-2
        // require "the above copyright notice", which is the component's own.
        // Fetch route, per-asset digests and the iOS/Android cross-pin
        // measurement are recorded in
        // docs/release/evidence/license-sources/PACKAGED-LICENCE-TEXT-PROVENANCE.md.
        // Note what these constants do and do not prove: they pin the bytes
        // against drift since capture; they do not establish provenance.
        'assets/licenses/libass-ISC.txt':
            'f7e30699d02798351e7f839e3d3bfeb29ce65e44efa7735c225464c4fd7dfe9c',
        'assets/licenses/dav1d-BSD-2-Clause.txt':
            'b327887de263238deaa80c34cdd2ff3e0ba1d35db585ce14a37ce3e74ee389e9',
        'assets/licenses/harfbuzz-Old-MIT.txt':
            'ba8f810f2455c2f08e2d56bb49b72f37fcf68f1f4fade38977cfd7372050ad64',
        'assets/licenses/libpng-PNG-2.0.txt':
            '5c0bb4b05b1354ae7c173532b6702ea68b611047ff9b91c4d3af77da39c195d9',
        'assets/licenses/mbedtls-Apache-2.0.txt':
            'cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30',
        'assets/licenses/libxml2-MIT.txt':
            'c5c63674f8a83c4d2e385d96d1c670a03cb871ba2927755467017317878574bd',
        // Byte-identical to the tracked evidence copy at
        // docs/release/evidence/license-sources/freetype/FTL.at-920c5502cc3d.txt
        'assets/licenses/freetype-FTL.txt':
            '08c135755dd589039470f1fdbb400daaabaaa50d0b366d19cebff4d22986baa1',
      };

      for (final MapEntry<String, String> e in expected.entries) {
        final ByteData data = await rootBundle.load(e.key);
        final String actual = sha256
            .convert(
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            )
            .toString();
        expect(actual, e.value, reason: '${e.key} is not the canonical text');
      }
    });

    test('each licence document is attached to the components it covers', () {
      Set<String> packagesCarrying(bool Function(String) match) => entries
          .where((LicenseEntry e) => match(textOf(e)))
          .expand((LicenseEntry e) => e.packages)
          .toSet();

      final Set<String> lgpl21Packages = packagesCarrying(
        (String t) =>
            t.contains('GNU LESSER GENERAL PUBLIC LICENSE') &&
            t.contains('Version 2.1'),
      );

      // mpv, FriBidi and uchardet are the LGPL-2.1 components in the bundle.
      expect(lgpl21Packages.any((String p) => p.contains('mpv')), isTrue);
      expect(lgpl21Packages.any((String p) => p.contains('FriBidi')), isTrue);
      expect(lgpl21Packages.any((String p) => p.contains('uchardet')), isTrue);

      final Set<String> gpl3Packages = packagesCarrying(
        (String t) =>
            t.contains('GNU GENERAL PUBLIC LICENSE') &&
            t.contains('Version 3') &&
            !t.contains('LESSER'),
      );
      expect(gpl3Packages.any((String p) => p.contains('FFmpeg')), isTrue);
    });

    test('every component carrying a text obligation has its text attached', () {
      // THIS IS THE TEST THAT WOULD HAVE CAUGHT THE MISS.
      //
      // The app previously shipped only the three GNU documents, on the reading
      // that the seven permissive components "need attribution in the notice,
      // not the text limb". That reading was wrong: ISC, BSD-2-Clause, MIT,
      // Old MIT, Apache-2.0 and PNG-2.0 each require their notice or licence to
      // be REPRODUCED in a binary distribution, not merely named.
      //
      // Naming a licence is not reproducing it, so asserting that the notice
      // MENTIONS a component is not enough -- this checks that a document
      // long enough to be a real licence text is attached to each package.
      const List<String> mustCarryText = <String>[
        'FFmpeg (Apple frameworks)',
        'mpv / libmpv (Apple frameworks)',
        'GNU FriBidi (Apple frameworks)',
        'uchardet (Apple frameworks)',
        'libass (Apple frameworks)',
        'dav1d (Apple frameworks)',
        'HarfBuzz (Apple frameworks)',
        'libpng (Apple frameworks)',
        'Mbed TLS (Apple frameworks)',
        'libxml2 (Apple frameworks)',
        'FreeType (Apple frameworks)',
      ];

      for (final String pkg in mustCarryText) {
        final Iterable<LicenseEntry> forPkg = entries.where(
          (LicenseEntry e) => e.packages.contains(pkg),
        );
        expect(forPkg, isNotEmpty, reason: '$pkg has no licence entry at all');
        // A notice paragraph is short; a licence text is not. 600 chars is well
        // above the longest notice here and well below the shortest real text
        // (libass ISC, 755 bytes).
        final bool hasDocument = forPkg.any(
          (LicenseEntry e) => textOf(e).length > 600,
        );
        expect(
          hasDocument,
          isTrue,
          reason: '$pkg is named but no licence TEXT is attached to it',
        );
      }
    });

    test('the Apple notice does not inherit the old Windows GPL findings', () {
      // FFTW and libzvbi reached the Windows ffmpeg.exe, which was removed on
      // 2026-08-15. They were always verifiably absent from the Apple
      // frameworks, so this guards against a copy-paste that would publish a
      // false statement about this build.
      expect(everything.contains('FFTW'), isFalse);
      expect(everything.contains('libzvbi'), isFalse);

      // And it must not claim more than was established. The conclusion is a
      // search that found nothing, not a proof of absence.
      expect(everything.contains('found by the checks'), isTrue);
    });

    test('the Apple notices do not claim the components are unmodified', () {
      // The libmpv-darwin-build v0.6.0 recipe applies four FFmpeg patches and
      // one mpv patch unconditionally, so the Apple binaries are MODIFIED.
      //
      // The first version of these notices carried "Inter Galactic does not
      // modify FFmpeg" and "does not modify mpv", inherited from the Windows
      // notices where those statements are true and verified. That is the exact
      // trap: correct wording for one artefact, false for another, and the
      // falsehood pointed a recipient at an upstream archive that does not
      // describe the binary they have.
      expect(everything.contains('does not modify'), isFalse);

      // NOT a blanket ban on the word "unmodified": the Apple FFmpeg notice
      // uses it correctly, about the *Windows* archive, to say that one does
      // not serve this binary. Banning the word outright failed on that
      // sentence — a control that fires on correct text is one somebody
      // deletes. The claim to forbid is the one about the Apple components.
      expect(everything.contains('this one carries the four patches'), isTrue);

      // The modifications must be named, not merely admitted, and each must be
      // stated as a modification rather than left to inference.
      expect(everything.contains('THIS FFmpeg IS MODIFIED'), isTrue);
      expect(everything.contains('THIS mpv IS MODIFIED'), isTrue);
      expect(everything.contains('ffmpeg-fix-vp9-hwaccel'), isTrue);
      expect(everything.contains('mpv-fix-missing-objc'), isTrue);
    });

    test('FreeType ships the MANDATORY disclaimer, not only the credit', () {
      // The FTL names TWO different things in two different places, and we
      // previously shipped only the second while describing it as the first.
      //
      //   MANDATORY, in LEGAL TERMS among the binding conditions on the grant:
      //     "Redistribution in binary form must provide a disclaimer that
      //      states that the software is based in part of the work of the
      //      FreeType Team, in the distribution documentation."
      //
      //   ENCOURAGED, in the introduction, before the legal terms:
      //     "we thus encourage you to use the following text" -> the
      //     Portions-of-this-software copyright credit.
      //
      // Two independent defects were fixed together. The missing disclaimer,
      // and -- separately, and true regardless of how the first resolves --
      // the notice CHARACTERISED THE ENCOURAGED TEXT AS REQUIRED. That second
      // one is a false fact claim about a licence, made inside a
      // licence-bearing notice: the same class as "does not modify FFmpeg".
      //
      // "based in part OF the work" is UPSTREAM'S OWN GRAMMAR, quoted verbatim
      // from FTL.at-920c5502cc3d.txt line 117. It is not a typo of ours. Do
      // not "correct" it to "on the work" -- reproducing the licence's own
      // phrase cannot be argued to state something different, which is the
      // same reason we reproduce the copyright symbol and the two spaces.
      final String notice = texts.firstWhere(
        (String t) => t.contains('FreeType Project licence'),
      );
      expect(
        notice.contains(
          'This software is based in part of the work of the FreeType Team.',
        ),
        isTrue,
      );
      // The characterisation defect, barred on its own terms.
      expect(notice.contains('requires the following credit'), isFalse);
    });

    test('FreeType ships its required credit line', () {
      // The FTL's credit obligation is separate from the LGPL text limb: it is
      // discharged by this wording appearing where a user can read it.
      //
      // THE YEAR IS PART OF THE OBLIGATION, NOT DECORATION. The FTL's own text
      // carries a `<year>` placeholder and directs you to substitute "the value
      // from the FreeType version you actually use". This line previously
      // carried no year at all -- the placeholder had been deleted rather than
      // filled -- which is the state this assertion exists to prevent
      // recurring.
      //
      // 2023 is READ, NOT ASSUMED: include/freetype/freetype.h and
      // src/base/ftinit.c at VER-2-13-2 both say `Copyright (C) 1996-2023 by`.
      // It tracks the SHIPPED VERSION and is not the current year, so do not
      // "update" it -- if this ever changes it is because the FreeType pin
      // moved, and the pin is what to check. 2.12.x would be 2022 and 2.11.x
      // 2021.
      //
      // The copyright symbol and the two spaces after the full stop are
      // upstream's preferred form, reproduced rather than normalised.
      expect(
        everything.contains(
          'Portions of this software are copyright © 2023 The FreeType',
        ),
        isTrue,
      );
      expect(
        everything.contains(
          'Project (www.freetype.org).  All rights reserved.',
        ),
        isTrue,
      );
      // The unfilled-placeholder state, explicitly barred -- but scoped to the
      // NOTICE text, not to `everything`.
      //
      // Banning `<year>` across all entries fails, and correctly so: the GPL-3
      // and LGPL-3 documents carry "Copyright (C) <year>  <name of author>" in
      // their own how-to-apply boilerplate, where the placeholder BELONGS. That
      // is the same trap as banning the word "unmodified" outright -- a control
      // that fires on correct text is one somebody deletes. Assert against the
      // notice that carries the obligation.
      final String freeTypeNotice = texts.firstWhere(
        (String t) => t.contains('FreeType Project licence'),
      );
      expect(freeTypeNotice.contains('copyright (c) The FreeType'), isFalse);
      expect(freeTypeNotice.contains('<year>'), isFalse);
    });
  });

  group('Windows native licence entries', () {
    late List<LicenseEntry> winEntries;
    late String winEverything;

    setUpAll(() async {
      winEntries = await NativeLicenses.windowsEntriesForTest().toList();
      winEverything = winEntries.map(textOf).join('\n');
    });

    test('libwebrtc is disclosed, with its components and the right route', () {
      // This component shipped undisclosed until 2026-08-15. It is the second
      // third-party native media component on Windows and contains a THIRD
      // FFmpeg, distinct from libmpv's and from the removed ffmpeg.exe.
      // winEverything is built once in setUpAll from the same stream. This
      // used to re-run windowsEntriesForTest() and reload every Windows
      // asset to rebuild an identical string.
      final String all = winEverything;

      expect(all.contains('libwebrtc.dll'), isTrue);
      for (final String c in <String>['FFmpeg', 'OpenH264', 'BoringSSL']) {
        expect(all.contains(c), isTrue, reason: '$c not disclosed');
      }

      // The source route must be the git repos, NOT /source/. Nothing
      // webrtc-related is served there - checked 2026-08-15, zero archives
      // against a control of 48 files - and a notice pointing at an address
      // that does not hold the file is worse than one naming the right place.
      expect(all.contains('github.com/Inter-Galactic-App/webrtc-core'), isTrue);
      expect(all.contains('github.com/Inter-Galactic-App/libwebrtc'), isTrue);

      // No GPL claim. ffmpeg_branding = "Chrome" selects the LGPL codec set,
      // read from the build's recorded gn args rather than from the binary.
      expect(all.contains('ffmpeg_branding = "Chrome"'), isTrue);
      expect(
        all.contains('GNU General Public'),
        isTrue,
      ); // the GPL-3 doc, for libmpv
      expect(
        all.contains('no GPL-licensed FFmpeg component is compiled in'),
        isTrue,
      );
    });

    test('libmpv ships its licence documents, not just a notice', () {
      // Windows used to discharge LGPL-2.1 §6 / LGPL-3 §4(b) by installing
      // these texts beside ffmpeg.exe. That binary and its licences/ directory
      // were deleted on 2026-08-15, so the in-app page is now the only copy a
      // Windows user can reach — and the only thing that can break silently.
      final List<String> docs = winEntries
          .map(textOf)
          .where((String t) => t.contains('GNU'))
          .toList();
      expect(docs.length, greaterThanOrEqualTo(3));

      // Real texts, not stubs. A bundled empty file would satisfy "it exists".
      expect(
        winEverything.contains('GNU LESSER GENERAL PUBLIC LICENSE'),
        isTrue,
      );
      expect(winEverything.contains('GNU GENERAL PUBLIC LICENSE'), isTrue);
      expect(winEverything.length, greaterThan(60000));
    });

    test('every Windows entry is attributed to a known shipped binary', () {
      // This read "attributed to libmpv" until 2026-08-15, which quietly
      // encoded the assumption that Windows ships ONE third-party native
      // media component. That assumption was the defect: libwebrtc.dll had
      // been shipping undisclosed the whole time. The test failed the moment
      // the second component was added, which is the test working.
      //
      // The per-entry loop below catches an ENTRY WITH NO HOME. The joined
      // check after it catches a NAMED BINARY WITH NO ENTRY - so deleting
      // either half loses a direction. This comment used to say the second
      // direction was uncovered here and left to the artefact-enumeration
      // audit; that was true when written and stopped being true when the
      // joined check was added, and a reader trusting it could have deleted
      // that check as redundant. What the audit still covers, and this cannot,
      // is a shipped binary that appears in NEITHER list - `shipped` is
      // hand-maintained, so an undisclosed component stays invisible here
      // until someone names it. That is the gap that hid libwebrtc.dll.
      const List<String> shipped = <String>[
        'libmpv-2.dll',
        'libwebrtc.dll',
        'd3dcompiler_47.dll',
        'Webview2Loader.dll',
      ];
      for (final LicenseEntry entry in winEntries) {
        expect(
          entry.packages.any(
            (String p) => shipped.any((String s) => p.contains(s)),
          ),
          isTrue,
          reason: 'unattributed Windows licence entry: ${entry.packages}',
        );
      }
      // Every name above must actually appear, so deleting one does not pass
      // by vacuity. (This said "Both components" while the list held four -
      // written when Windows disclosed two, and never updated as
      // d3dcompiler_47.dll and Webview2Loader.dll were added.)
      final String joined = winEntries
          .expand((LicenseEntry e) => e.packages)
          .join(' ');
      for (final String s in shipped) {
        expect(joined.contains(s), isTrue, reason: '$s has no entry at all');
      }
    });

    test('the Windows notice no longer presents ffmpeg.exe as shipping', () {
      // The binary is gone, but the obligation for the releases that carried
      // it is not, so the notice must still point at the published source
      // while being clear it is historical.
      expect(winEverything.contains('no longer part of this app'), isTrue);
      expect(
        winEverything.contains('https://app.ourgalaxy.space/source/'),
        isTrue,
      );

      // The retracted "no GPL-only component" reasoning must not reappear.
      expect(winEverything.contains('FFTW'), isFalse);
      expect(winEverything.contains('libzvbi'), isFalse);
    });

    test('Direct3D Compiler retains the exact SDK-terms evidence boundary', () {
      expect(winEverything.contains('d3dcompiler_47.dll'), isTrue);
      expect(
        winEverything.contains(
          'https://learn.microsoft.com/en-us/windows/win32/directx-sdk--august-2009-',
        ),
        isTrue,
      );
      expect(
        winEverything.contains("were not retained in this project's evidence"),
        isTrue,
      );
      expect(
        winEverything.contains('does not assert an exact Microsoft terms URL'),
        isTrue,
      );
      expect(winEverything.contains('license-terms-ewdk'), isFalse);
    });

    test('WebView2 ships its exact BSD-3-Clause text', () async {
      expect(winEverything.contains('Webview2Loader.dll'), isTrue);
      expect(
        winEverything.contains('Copyright (C) Microsoft Corporation.'),
        isTrue,
      );
      expect(
        winEverything.contains('1.0.992.28'),
        isTrue,
        reason: 'the exact packaged WebView2 version is not disclosed',
      );

      final ByteData text = await rootBundle.load(
        'assets/licenses/Microsoft-WebView2-BSD-3-Clause.txt',
      );
      expect(
        sha256
            .convert(
              text.buffer.asUint8List(text.offsetInBytes, text.lengthInBytes),
            )
            .toString(),
        '9995174528dba139ca753d02d8667dbec49f65ab17e65c643a914f2b58cfb4a2',
        reason: 'WebView2 BSD-3-Clause text is not the captured package text',
      );
    });

    test('SwiftShader is not presented as an ANGLE BSD component', () {
      expect(winEverything.contains('vk_swiftshader.dll'), isTrue);
      expect(
        winEverything.contains(
          'vk_swiftshader.dll), under the Apache License 2.0.',
        ),
        isTrue,
      );
      expect(
        winEverything.contains(
          'libGLESv2.dll, vk_swiftshader.dll), under the BSD',
        ),
        isFalse,
      );
    });
  });

  group('Android native licence entries', () {
    late List<LicenseEntry> droidEntries;
    late List<String> droidTexts;
    late String droidEverything;

    setUpAll(() async {
      droidEntries = await NativeLicenses.androidEntriesForTest().toList();
      droidTexts = droidEntries.map(textOf).toList();
      droidEverything = droidTexts.join('\n');
    });

    test('libmpv.so ships its licence documents, not just a notice', () {
      // The four jars media_kit_libs_android_video downloads contain exactly
      // two .so entries each and NO licence text at any depth — enumerated, not
      // assumed. So nothing travels with the binary from upstream, and files
      // inside an APK are no more reachable to a user than files inside an IPA.
      // This page is the only copy an Android user can read.
      final String lgpl3 = droidTexts.firstWhere(
        (String t) =>
            t.contains('GNU LESSER GENERAL PUBLIC LICENSE') &&
            t.contains('Version 3'),
        orElse: () => '',
      );
      final String gpl3 = droidTexts.firstWhere(
        (String t) =>
            t.contains('GNU GENERAL PUBLIC LICENSE') &&
            t.contains('Version 3') &&
            !t.contains('LESSER'),
        orElse: () => '',
      );
      final String lgpl21 = droidTexts.firstWhere(
        (String t) =>
            t.contains('GNU LESSER GENERAL PUBLIC LICENSE') &&
            t.contains('Version 2.1'),
        orElse: () => '',
      );

      expect(lgpl3, isNotEmpty, reason: 'LGPL-3.0 text missing');
      expect(gpl3, isNotEmpty, reason: 'GPL-3.0 text missing');
      expect(lgpl21, isNotEmpty, reason: 'LGPL-2.1 text missing');

      // Size floors catch a pointer stub or a truncated copy. The exact-digest
      // assertion in the iOS group pins the same three assets, so it is not
      // repeated here — there is one asset bundle, not one per platform.
      expect(lgpl3.length, greaterThan(5000));
      expect(gpl3.length, greaterThan(20000));
      expect(lgpl21.length, greaterThan(20000));
    });

    test('each licence document is attached to the components it covers', () {
      Set<String> packagesCarrying(bool Function(String) match) => droidEntries
          .where((LicenseEntry e) => match(textOf(e)))
          .expand((LicenseEntry e) => e.packages)
          .toSet();

      final Set<String> lgpl21Packages = packagesCarrying(
        (String t) =>
            t.contains('GNU LESSER GENERAL PUBLIC LICENSE') &&
            t.contains('Version 2.1'),
      );
      // mpv and FriBidi are the LGPL-2.1 components. uchardet is NOT — it does
      // not ship on Android, and asserting it here would be the iOS list
      // copied across, which is the specific error this platform's inventory
      // exists to prevent.
      //
      // Matched on the FULL label, not `contains('mpv')`. Every Android label
      // ends with "(Android libmpv.so)", so the substring check passed for
      // 'zlib (Android libmpv.so)' and would have stayed green with the mpv
      // entry itself dropped from the LGPL-2.1 yield. The iOS equivalent is
      // sound only because Apple labels end with "(Apple frameworks)".
      expect(
        lgpl21Packages.any((String p) => p.startsWith('mpv / libmpv')),
        isTrue,
        reason:
            'mpv itself must carry the LGPL-2.1 text, not just its siblings',
      );
      expect(lgpl21Packages.any((String p) => p.contains('FriBidi')), isTrue);
      expect(lgpl21Packages.any((String p) => p.contains('uchardet')), isFalse);

      final Set<String> gpl3Packages = packagesCarrying(
        (String t) =>
            t.contains('GNU GENERAL PUBLIC LICENSE') &&
            t.contains('Version 3') &&
            !t.contains('LESSER'),
      );
      expect(gpl3Packages.any((String p) => p.contains('FFmpeg')), isTrue);
    });

    test(
      'AndroidX native payloads carry Apache-2.0 under their own labels',
      () {
        // The payload inventory identifies these two .so files separately from
        // libmpv.so. Attaching the canonical Apache text only to Mbed TLS would
        // leave the AndroidX binaries named but without a licence document.
        const List<String> androidXPackages = <String>[
          'AndroidX Graphics Path (Android libandroidx.graphics.path.so)',
          'AndroidX DataStore (Android libdatastore_shared_counter.so)',
          'AndroidX Camera Core Surface Utility '
              '(Android libsurface_util_jni.so)',
        ];
        for (final String package in androidXPackages) {
          final String attached = droidEntries
              .where((LicenseEntry entry) => entry.packages.contains(package))
              .map(textOf)
              .join('\n');
          expect(attached.contains('Apache License'), isTrue);
          expect(attached.contains('Version 2.0, January 2004'), isTrue);
        }
      },
    );

    test(
      'LiveKit Noise runtime carries Apache-2.0 beside its KISS FFT limb',
      () {
        const String liveKitNoise = 'LiveKit Noise (Android libnoise.so)';
        final String attached = droidEntries
            .where(
              (LicenseEntry entry) => entry.packages.contains(liveKitNoise),
            )
            .map(textOf)
            .join('\n');
        expect(attached.contains('LiveKit Noise 2.0.0 native runtime'), isTrue);
        expect(attached.contains('Apache License'), isTrue);
        expect(
          attached.contains('KISS FFT is a separately attributed'),
          isTrue,
        );
      },
    );

    test(
      'SQLite native payload is identified as public domain, not its wrapper',
      () {
        const String sqlite = 'SQLite (Android libsqlite3.so)';
        final String attached = droidEntries
            .where((LicenseEntry entry) => entry.packages.contains(sqlite))
            .map(textOf)
            .join('\n');
        expect(attached.contains('SQLite 3.52.0'), isTrue);
        expect(attached.contains('public domain'), isTrue);
        expect(attached.contains('MIT-licensed Dart sqlite3 wrapper'), isTrue);
      },
    );

    test('Dart JNI native payload carries its BSD and Apache texts', () async {
      const String dartJni = 'Dart JNI (Android libdartjni.so)';
      final String attached = droidEntries
          .where((LicenseEntry entry) => entry.packages.contains(dartJni))
          .map(textOf)
          .join('\n');
      expect(
        attached.contains('Copyright 2022, the Dart project authors.'),
        isTrue,
      );
      expect(attached.contains('Apache License'), isTrue);

      final ByteData text = await rootBundle.load(
        'assets/licenses/dart-jni-BSD-3-Clause.txt',
      );
      expect(
        sha256
            .convert(
              text.buffer.asUint8List(text.offsetInBytes, text.lengthInBytes),
            )
            .toString(),
        '08a004aa8956c3cf3b24f7f69c966247233953e18e6afaa61191ea47b7eb70f6',
        reason: 'Dart JNI BSD text differs from the locked package LICENSE',
      );
    });

    test('KISS FFT carries its own BSD-3-Clause notice', () async {
      // io.livekit:noise is Apache-2.0 and IS surfaced by the Gradle notice
      // inventory and the OSS-licenses baseline. KISS FFT is statically linked
      // inside its libnoise.so and is surfaced by none of them, because no
      // generated notice surface sees inside a native artefact. Inheriting the
      // container's licence would leave a BSD-3-Clause binary-distribution
      // notice unshipped.
      const String kissFft = 'KISS FFT (Android libnoise.so)';
      final String attached = droidEntries
          .where((LicenseEntry entry) => entry.packages.contains(kissFft))
          .map(textOf)
          .join('\n');

      expect(
        attached.contains('Copyright (c) 2003-2010 Mark Borgerding'),
        isTrue,
        reason: 'the real copyright holder must appear, not a placeholder',
      );
      expect(attached.contains('Redistributions in binary form'), isTrue);
      expect(
        attached.contains('THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT'),
        isTrue,
      );

      // CLAUSE 3 IS THE REVISION DISCRIMINATOR, which is why this asserts on
      // wording and not only on the digest. At the pinned submodule revision
      // the clause reads "Neither the author"; on kissfft master today it
      // reads "Neither the name of the copyright holder". Same licence family,
      // same plausible length, different text - the FreeType failure this
      // project already documented. A re-capture from master would ship the
      // wrong revision's wording, and a digest mismatch alone would not say
      // which way it drifted.
      expect(
        attached.contains('Neither the author nor the names of any'),
        isTrue,
        reason:
            'this must be the COPYING at the pinned submodule revision, not '
            'kissfft master, whose clause 3 names the copyright holder',
      );

      // master splits the notice into a COPYING pointer plus a REUSE template
      // carrying "Copyright (c) <year> <owner>" and SPDX tooling metadata.
      // Neither is a usable notice, so their markers must never appear here.
      expect(attached.contains('<year>'), isFalse);
      expect(attached.contains('<owner>'), isFalse);
      expect(attached.contains('Valid-License-Identifier'), isFalse);
      expect(attached.contains('Usage-Guide'), isFalse);

      final ByteData text = await rootBundle.load(
        'assets/licenses/kissfft-BSD-3-Clause.txt',
      );
      expect(
        sha256
            .convert(
              text.buffer.asUint8List(text.offsetInBytes, text.lengthInBytes),
            )
            .toString(),
        'ddd1400f963747b305bfa39e21206e58805a1c650451e2ee5ce81ed86bc0b1ab',
        reason:
            'KISS FFT text must be the verbatim COPYING at kissfft '
            'd74fd2adaffdf4489441a12e0258423b9f5b8e12, the revision the '
            'livekit/noise submodule pins',
      );
    });

    test(
      "CameraX image processing carries libyuv's own BSD-3-Clause notice",
      () async {
        const String cameraImageProcessing =
            'AndroidX Camera Core Image Processing / libyuv '
            '(Android libimage_processing_util_jni.so)';
        final String attached = droidEntries
            .where(
              (LicenseEntry entry) =>
                  entry.packages.contains(cameraImageProcessing),
            )
            .map(textOf)
            .join('\n');

        expect(
          attached.contains('Copyright 2011 The LibYuv Project Authors.'),
          isTrue,
          reason:
              'Camera Core Apache or the Flutter wrapper BSD text is not libyuv attribution',
        );
        expect(
          attached.contains(
            'Neither the name of Google nor the names of its contributors',
          ),
          isTrue,
          reason: 'libyuv clause 3 is required with the conveyed binary limb',
        );

        final ByteData text = await rootBundle.load(
          'assets/licenses/libyuv-BSD-3-Clause.txt',
        );
        expect(
          sha256
              .convert(
                text.buffer.asUint8List(text.offsetInBytes, text.lengthInBytes),
              )
              .toString(),
          '2b2cc1180c7e6988328ad2033b04b80117419db9c4c584918bbb3cfec7e9364f',
          reason: 'libyuv text must remain the captured upstream LICENSE bytes',
        );
      },
    );

    test('WebRTC-SDK carries its exact release notice packet', () async {
      // The Gradle POM reports only BSD-3-Clause, but the precompiled AAR is a
      // static WebRTC distribution. Its release packet names the actual
      // component set, and unlike a POM it contains the copyright notices that
      // must travel with the binary. This guards against replacing it with the
      // wrapper repository's unrelated MIT LICENSE.
      const String webRtcSdk =
          'WebRTC-SDK (Android libjingle_peerconnection_so.so)';
      final String attached = droidEntries
          .where((LicenseEntry entry) => entry.packages.contains(webRtcSdk))
          .map(textOf)
          .join('\n');

      for (final String component in <String>[
        '# webrtc',
        '# abseil-cpp',
        '# boringssl',
        '# libvpx',
        '# libyuv',
        '# opus',
        '# zlib',
      ]) {
        expect(
          attached.contains(component),
          isTrue,
          reason: 'WebRTC-SDK release notice packet is missing $component',
        );
      }
      expect(attached.contains('The WebRTC project authors'), isTrue);
      expect(attached.length, greaterThan(700000));

      final ByteData text = await rootBundle.load(
        'assets/licenses/webrtc-sdk-android-137.7151.04-NOTICES.txt',
      );
      expect(
        sha256
            .convert(
              text.buffer.asUint8List(text.offsetInBytes, text.lengthInBytes),
            )
            .toString(),
        'd1f9382c6878ac024155fd6d44a5977329108bb8b0a01cea40e4a2f1d7de252e',
        reason:
            'WebRTC-SDK notice packet must remain the exact v137.7151.04 '
            'release packet, not a generic POM or wrapper-repository licence',
      );
    });

    test('every Android entry is attributed to an Android artefact', () {
      for (final LicenseEntry entry in droidEntries) {
        expect(
          entry.packages.any((String p) => p.contains('Android')),
          isTrue,
          reason: 'unattributed Android licence entry: ${entry.packages}',
        );
      }
    });

    test('the Android notices do not claim the components are unmodified', () {
      // libmpv-android-video-build v1.1.7 applies two FFmpeg patches and one
      // mpv patch unconditionally, so these binaries are MODIFIED. The Windows
      // notices say "Inter Galactic does not modify mpv", which is true there
      // and false here — exactly the copy-paste that would point a recipient at
      // an upstream archive that does not describe the binary they have.
      expect(droidEverything.contains('does not modify'), isFalse);
      expect(droidEverything.contains('THIS FFmpeg IS MODIFIED'), isTrue);
      expect(droidEverything.contains('THIS mpv IS MODIFIED'), isTrue);

      // Named, not merely admitted.
      expect(droidEverything.contains('dash_base_url_escape'), isTrue);
      expect(droidEverything.contains('hls_mp4_seek'), isTrue);
      expect(droidEverything.contains('mpv_lavc_set_java_vm'), isTrue);

      // And NOT the Apple patch set. Android applies two of Apple's four FFmpeg
      // patches and a completely different mpv patch; listing the Apple names
      // here would describe modifications this binary does not carry.
      expect(droidEverything.contains('ffmpeg-fix-vp9-hwaccel'), isFalse);
      expect(droidEverything.contains('ffmpeg-fix-ios-hdr-texture'), isFalse);
      expect(droidEverything.contains('mpv-fix-missing-objc'), isFalse);
    });

    test('the mpv revision is the Android one, not another platform\'s', () {
      // Three artefacts, three different mpv revisions, and no published
      // archive for one serves another. Getting this wrong is not cosmetic: it
      // sends someone exercising their LGPL rights to source that does not
      // build the binary they hold.
      //
      //   Android  78d43740f52db817d98bcf24fb30a76ab6fa13ff  (v0.36.0-549)
      //   Windows  652a1dd90711839acdccc08004056d25514ef2d8  (v0.36.0-403)
      //   iOS      the 0.36.0 release tag itself
      //
      // Read three ways: the v_mpv pin in depinfo.sh, the git reset --hard in
      // download-deps.sh, and the shipped binary's own version string
      // "mpv v0.36.0-549-g78d43740f5-dirty".
      expect(
        droidEverything.contains('78d43740f52db817d98bcf24fb30a76ab6fa13ff'),
        isTrue,
      );
      // The Windows revision may APPEAR — the notice names it to say it does
      // not serve this build — so assert the framing, not its absence. A bare
      // absence check would fail on correct text, and a control that fires on
      // correct text is one somebody deletes.
      expect(
        droidEverything.contains('No archive published for one of them'),
        isTrue,
      );
    });

    test('the Android component list is not the iOS one', () {
      // Nine of twelve component rows differ between the two platforms even
      // though both come from the same upstream project through sibling build
      // repos. These four assertions are the membership differences; the six
      // version differences are covered by the version assertions below.

      // uchardet and libpng ship on iOS and NOT on Android.
      expect(droidEverything.contains('uchardet 0.0.8'), isFalse);
      expect(droidEverything.contains('libpng 1.6.40'), isFalse);

      // zlib is the reverse: statically compiled in here and CONVEYED, where
      // iOS resolves the system dylib and conveys nothing. The iOS notice's
      // "provided by the operating system" sentence is correct there and false
      // here, and it is the sentence most likely to be copied.
      expect(droidEverything.contains('zlib 1.2.12'), isTrue);
      expect(
        droidEverything.contains(
          'zlib and libiconv are also used, but are provided by the operating',
        ),
        isFalse,
      );
    });

    test('component versions are the Android pins, not the iOS ones', () {
      // Read from buildscripts/include/depinfo.sh at v1.1.7, corroborated by
      // the binary where the component emits its own version string. Six of
      // these differ from iOS by a patch level, which is exactly the kind of
      // difference that survives a careless copy unnoticed.
      const Map<String, String> androidPins = <String, String>{
        'libass 0.17.1': 'same as iOS',
        'FreeType 2.13.0': 'iOS is 2.13.2',
        'GNU FriBidi 1.0.12': 'iOS is 1.0.13',
        'HarfBuzz 7.2.0': 'iOS is 8.1.1',
        'Mbed TLS 3.4.0': 'iOS is 3.4.1',
        'dav1d 1.2.0': 'iOS is 1.2.1',
        'libxml2 2.10.3': 'iOS is 2.11.5',
      };
      for (final MapEntry<String, String> pin in androidPins.entries) {
        expect(
          droidEverything.contains(pin.key),
          isTrue,
          reason: '${pin.key} missing from the Android notice (${pin.value})',
        );
      }

      // And the iOS pins must not appear.
      const List<String> iosPins = <String>[
        'FreeType 2.13.2',
        'GNU FriBidi 1.0.13',
        'HarfBuzz 8.1.1',
        'Mbed TLS 3.4.1',
        'dav1d 1.2.1',
        'libxml2 2.11.5',
      ];
      for (final String pin in iosPins) {
        expect(
          droidEverything.contains(pin),
          isFalse,
          reason: 'iOS pin "$pin" leaked into the Android notice',
        );
      }
    });

    test('the Android notice does not inherit the Windows GPL findings', () {
      // FFTW and libzvbi reached the removed Windows ffmpeg.exe. They were
      // measured absent here against working controls, in all four upstream
      // jar ABIs — a superset of the two that actually ship (arm64-v8a and
      // armeabi-v7a; x86 has never shipped and x86_64 stopped at 0.8.1+996).
      expect(droidEverything.contains('FFTW'), isFalse);
      expect(droidEverything.contains('libzvbi'), isFalse);

      // And the conclusion must not claim more than was established. Android
      // compiles everything into one library, so unlike iOS there is no
      // linkage graph to close as a second check — the notice says so rather
      // than borrowing iOS's stronger closure argument.
      expect(droidEverything.contains('found by the checks'), isTrue);
      expect(
        droidEverything.contains('there is no linkage graph to close'),
        isTrue,
      );
    });

    test('FreeType ships the mandatory disclaimer and the credit line', () {
      // Same two-part obligation as iOS, and the same trap: the FTL's
      // MANDATORY disclaimer sits in the legal terms while the ENCOURAGED
      // credit sits in the introduction, and this project once shipped only the
      // second while describing it as the first.
      //
      // The year tracks the SHIPPED version and is read, not assumed:
      // include/freetype/freetype.h at VER-2-13-0 says
      // `Copyright (C) 1996-2023 by`, so 2023 is correct for the 2.13.0 pin
      // here just as it is for iOS's 2.13.2. Do not "update" it to the current
      // year — if it ever changes it is because the FreeType pin moved.
      final String notice = droidTexts.firstWhere(
        (String t) => t.contains('FreeType Project licence'),
      );
      expect(
        notice.contains(
          'This software is based in part of the work of the FreeType Team.',
        ),
        isTrue,
      );
      expect(
        notice.contains(
          'Portions of this software are copyright © 2023 The FreeType',
        ),
        isTrue,
      );
      // The characterisation defect and the unfilled placeholder, both barred.
      expect(notice.contains('requires the following credit'), isFalse);
      expect(notice.contains('<year>'), isFalse);
    });

    test("the permissive components ship their own texts, not a wrapper's", () {
      // MIT, ISC, BSD-2-Clause, Apache-2.0 and zlib all require the notice AND
      // its copyright line to travel with the binary. The app already renders
      // hundreds of Dart-package licences, and media_kit's own MIT is among
      // them - but that is Hitesh Kumar Saini's copyright, not HarfBuzz's.
      // Reproducing the right TEMPLATE under the wrong HOLDER discharges
      // nothing, which is why these assert copyright lines rather than
      // licence names.
      const Map<String, String> holders = <String, String>{
        'libass': 'libass contributors',
        'dav1d': 'VideoLAN and dav1d authors',
        'HarfBuzz': 'Behdad Esfahbod',
        'libxml2': 'Daniel Veillard',
        'zlib': 'Jean-loup Gailly and Mark Adler',
        'media-kit-android-helper': 'Hitesh Kumar Saini',
      };
      for (final MapEntry<String, String> e in holders.entries) {
        expect(
          droidEverything.contains(e.value),
          isTrue,
          reason: '${e.key}: its own copyright line is not in the Android page',
        );
      }
      // Apache-2.0 is the exception: it carries no per-component copyright
      // line, so the document itself is the check.
      expect(droidEverything.contains('Apache License'), isTrue);
      expect(droidEverything.contains('Version 2.0, January 2004'), isTrue);
    });

    test('the Android helper ships its own pinned MIT text', () async {
      // The helper is a second conveyed .so, so the MIT text shipped by a
      // different component is not enough. This asset is the upstream LICENSE
      // at the exact commit in the Android inventory:
      // 42054e5d479f39ccbb0ae604862e2bcaf59b74c2.
      const String helper =
          'media-kit-android-helper (Android libmediakitandroidhelper.so)';
      final Iterable<LicenseEntry> helperEntries = droidEntries.where(
        (LicenseEntry entry) => entry.packages.contains(helper),
      );
      expect(helperEntries, isNotEmpty);
      // Length alone would pass if the helper were attached to ANY long text -
      // including one of the LGPL documents already on this page - which is the
      // very substitution this entry exists to prevent. Assert the licence
      // template AND the holder line, on the helper's own entry.
      final String helperText = helperEntries.map(textOf).join('\n');
      expect(
        helperText.contains('MIT License'),
        isTrue,
        reason: 'the helper is named but no MIT text is attached to its entry',
      );
      expect(
        helperText.contains('Copyright (c) 2021 & onwards Hitesh Kumar Saini'),
        isTrue,
        reason:
            "the helper's entry carries an MIT template under no holder, or "
            'under the wrong one',
      );

      final ByteData text = await rootBundle.load(
        'assets/licenses/media-kit-android-helper-MIT.txt',
      );
      expect(
        sha256
            .convert(
              text.buffer.asUint8List(text.offsetInBytes, text.lengthInBytes),
            )
            .toString(),
        '2e3000f38718f050869d57540c288c661a446f64df1ba4ea4764df552b04a331',
        reason: 'the helper MIT text differs from its pinned upstream LICENSE',
      );
    });

    test('zlib is present here and is NOT claimed on Apple', () async {
      // zlib is statically compiled into the Android libmpv.so and conveyed.
      // iOS resolves /usr/lib/libz.1.dylib and conveys nothing, so asserting
      // it there would name a component that is not bundled - the same class
      // of error as omitting one that is.
      expect(droidEverything.contains('Jean-loup Gailly'), isTrue);

      // Pinned like the other texts. zlib ships no LICENSE file at v1.2.12 —
      // that URL 404s — so this was taken from the notice in the README and
      // zlib.h, which agree. Capture and route:
      // docs/release/evidence/license-sources/zlib/SOURCE.md
      final ByteData z = await rootBundle.load('assets/licenses/zlib-Zlib.txt');
      expect(
        sha256
            .convert(z.buffer.asUint8List(z.offsetInBytes, z.lengthInBytes))
            .toString(),
        'd63f0feeb74cca59f7369452878bf3d659e32ca00777d3b594699b4c77190831',
        reason: 'zlib-Zlib.txt is not the canonical text',
      );

      // `everything` is the Apple set, joined once in setUpAll.
      expect(
        everything.contains('Jean-loup Gailly'),
        isFalse,
        reason: 'zlib must not be claimed on Apple, which does not bundle it',
      );
    });
  });

  group('Rust crates linked into the app binary', () {
    late List<LicenseEntry> rustEntries;
    late String rustEverything;

    setUpAll(() async {
      rustEntries = await NativeLicenses.rustEntriesForTest().toList();
      rustEverything = rustEntries.map(textOf).join('\n');
    });

    test('the notice document ships and is the exact generated text', () async {
      // Regenerated by tools/release/generate_rust_crate_notice.py in the
      // workspace repo, from the crate sources cargo itself compiled. Unlike
      // the upstream texts above, this file is COMPOSED, so the digest is not
      // pinning "verbatim upstream" - it is pinning "the generator's output for
      // the measured roster". Re-run the generator rather than hand-editing;
      // a hand edit that drops a component still passes every other assertion
      // here except this one.
      final ByteData data = await rootBundle.load(
        'assets/licenses/rust-crates-NOTICE.txt',
      );
      final String actual = sha256
          .convert(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          )
          .toString();
      expect(
        actual,
        '777f715ed4322654ecbd0a266c245d744e7587f1e030d52f03378547636296c2',
        reason: 'rust-crates-NOTICE.txt is not the generated text',
      );
    });

    test('the crate count in the shipped prose matches the roster', () async {
      // The digest above forces the ASSET to be regenerated when the roster
      // changes. It cannot force the Dart prose to move with it: a regenerated
      // notice carrying one crate more would still ship "all 59 crates" to
      // users, and nothing else here reads that number. So read the roster
      // size off the asset and compare it to the number the prose states.
      final String notice = await rootBundle.loadString(
        'assets/licenses/rust-crates-NOTICE.txt',
      );
      final int start = notice.indexOf('SECTION 1 - COMPONENTS');
      final int end = notice.indexOf('SECTION 2 - LICENCE TEXTS');
      expect(
        start >= 0 && end > start,
        isTrue,
        reason:
            'the notice no longer has its component section; this count '
            'tripwire is reading nothing',
      );

      // A component row is `name  version  licence  texts`, two or more spaces
      // between columns. The two-space requirement is what keeps the
      // `SECTION 1 - COMPONENTS` heading and the dashed rule out of the count.
      final RegExp componentRow = RegExp(
        r'^[A-Za-z0-9_.+-]+ {2,}\d[^ ]* {2,}',
        multiLine: true,
      );
      final int roster = componentRow
          .allMatches(notice.substring(start, end))
          .length;
      expect(
        roster,
        greaterThan(0),
        reason:
            'no component rows parsed; the generator changed the table '
            'shape and this locator needs updating',
      );

      final RegExpMatch? stated = RegExp(
        r'names all (\d+) crates',
      ).firstMatch(rustEverything);
      expect(
        stated,
        isNotNull,
        reason:
            'the Rust notice no longer states a crate count in the shape '
            'this check reads; if the number was removed on purpose, remove '
            'this test with it',
      );
      expect(
        int.parse(stated!.group(1)!),
        roster,
        reason:
            'the shipped Rust notice says ${stated.group(1)} crates but '
            'rust-crates-NOTICE.txt lists $roster - regenerate with '
            'tools/release/generate_rust_crate_notice.py and update the count '
            'in _rustNotice together',
      );
    });

    test('the document is attached, not just named in prose', () {
      // The failure this guards is specific and has happened on this project
      // before: a component gets a NOTICE saying it exists while the licence
      // TEXT it is obliged to carry never reaches the bundle.
      const String label =
          'vodozemac Rust crates (linked into the app binary on every platform)';

      final Iterable<LicenseEntry> forRust = rustEntries.where(
        (LicenseEntry e) => e.packages.contains(label),
      );
      expect(forRust, isNotEmpty, reason: 'no entry carries the Rust label');

      final bool hasDocument = forRust.any(
        (LicenseEntry e) => textOf(e).length > 100000,
      );
      expect(
        hasDocument,
        isTrue,
        reason: 'the Rust components are named but no licence text is attached',
      );
    });

    test('every crate the binary carries is named with its exact version', () {
      // Sampled across the licence families rather than all 59, so the check
      // fails for a reason a reader can act on. Versions are included on
      // purpose: a roster that regressed to "vodozemac" without "0.9.0" is a
      // roster that stopped being measured against an artefact.
      const List<String> mustName = <String>[
        'vodozemac',
        '0.9.0',
        'curve25519-dalek',
        '4.1.3',
        'ed25519-dalek',
        'x25519-dalek',
        'tokio',
        '1.44.2',
        'serde',
        'prost',
        'flutter_rust_bridge',
        '2.11.1',
        'Rust standard library',
      ];
      for (final String name in mustName) {
        expect(
          rustEverything.contains(name),
          isTrue,
          reason: '$name is linked in but is not named in the notice',
        );
      }
    });

    test('the copyright holders travel, not just the licence templates', () {
      // MIT, BSD-3-Clause and ISC oblige "the above copyright notice" - the
      // component's own. A template with nobody's name in it discharges
      // nothing, which is the same failure the seven Apple permissive texts
      // were captured per-component to avoid.
      const List<String> holders = <String>[
        'isis agora lovecruft',
        'Tokio Contributors',
        'fzyzcjy',
        'The Rust Project Developers',
      ];
      for (final String holder in holders) {
        expect(
          rustEverything.contains(holder),
          isTrue,
          reason: '$holder is a copyright holder whose notice must travel',
        );
      }
    });

    test('the full text of each licence family is present', () {
      expect(rustEverything.contains('Apache License'), isTrue);
      expect(rustEverything.contains('Version 2.0, January 2004'), isTrue);
      expect(rustEverything.contains('MIT License'), isTrue);
      expect(
        rustEverything.contains('Redistribution and use in source and binary'),
        isTrue,
        reason: 'the BSD-3-Clause components need their text, not their name',
      );
      expect(
        rustEverything.contains('THE SOFTWARE IS PROVIDED "AS IS"'),
        isTrue,
      );
    });

    test('the notice states the static-link mechanism, not just the list', () {
      // Why this is asserted rather than left to the generator: a reader who
      // cannot find these components in the app bundle needs to be told why
      // there is no file to find. Dropping the explanation turns a complete
      // notice into a confusing one.
      expect(rustEverything.contains('static archive'), isTrue);
      expect(rustEverything.contains('merged into the application'), isTrue);
    });

    test('nothing that is not linked in is claimed', () {
      // The control. Every assertion above is a presence check, and a file
      // that accidentally contained the whole crates.io index would pass all
      // of them.
      const List<String> notLinked = <String>[
        'openssl',
        'reqwest',
        'zzqqxx-not-a-crate',
      ];
      for (final String absent in notLinked) {
        expect(
          rustEverything.contains(absent),
          isFalse,
          reason: '$absent is not linked into this binary and must not appear',
        );
      }
    });

    test('the measured roster still describes the package that is pinned', () {
      // THE DRIFT THIS CATCHES IS THE ONE THE DIGEST CANNOT.
      //
      // The roster was measured from a built artefact at flutter_vodozemac
      // 0.5.0, whose rust/Cargo.lock pins all 59 crates. Bump that package and
      // the tree underneath it changes - new crates, new versions, possibly a
      // new licence - while assets/licenses/rust-crates-NOTICE.txt keeps
      // describing the old one. Every other assertion in this group still
      // passes: the file is intact, its digest matches, the holders are there.
      // The notice is simply about a different build.
      //
      // A lockfile parity check does not see it either. flutter_vodozemac is
      // ONE row in pubspec.lock and ONE pod in Podfile.lock; the 59 crates are
      // pinned by a Cargo.lock INSIDE the pub package, which is not an input to
      // any roster gate this project runs.
      //
      // So the pin is asserted here. This is a tripwire, not a measurement: it
      // fails on the bump and tells you to re-measure, which is the only thing
      // a test on this side can honestly do.
      //
      // HOW THIS WAS NEGATIVE-CONTROLLED, because the obvious way does not
      // work: hand-editing pubspec.lock to a different version and re-running
      // proves nothing, since `flutter test` re-resolves a lockfile it finds
      // newer than the manifest and silently rewrites the edit away BEFORE the
      // test reads it. Verified: the file said 0.6.0 going in and 0.5.0 coming
      // out. The control that does work is moving the expectation instead -
      // set measuredAt to a version the lockfile does not hold, and this
      // assertion fails with the message below naming the real value.
      const String measuredAt = '0.5.0';

      final File lockfile = File('../pubspec.lock');
      expect(
        lockfile.existsSync(),
        isTrue,
        reason: 'pubspec.lock moved; this tripwire is reading nothing',
      );
      final String lock = lockfile.readAsStringSync();

      final RegExp entry = RegExp(
        r'^  flutter_vodozemac:\n(?:.*\n)*?    version: "([^"]+)"',
        multiLine: true,
      );
      final RegExpMatch? match = entry.firstMatch(lock);
      expect(
        match,
        isNotNull,
        reason:
            'flutter_vodozemac is not in pubspec.lock under the expected '
            'shape - either it was removed, in which case the Rust notice '
            'should go too, or this locator needs updating',
      );

      expect(
        match!.group(1),
        measuredAt,
        reason:
            'flutter_vodozemac moved to ${match.group(1)} but the shipped Rust '
            'notice was measured at $measuredAt. Re-measure the roster from a '
            'built artefact and regenerate with '
            'tools/release/generate_rust_crate_notice.py - do NOT just re-pin '
            'the digest. See docs/release/evidence/license-sources/'
            'rust-crates/VODOZEMAC-RUST-TREE.md.',
      );
    });

    test('the Rust set is separate from every platform set', () async {
      // register() adds this stream OUTSIDE the platform chain, so the same
      // entries must not also be yielded by a platform branch - that would
      // list the whole 210 KB document twice on that platform.
      const String marker = 'RUST COMPONENTS LINKED INTO THE APPLICATION';

      // Positive control first: the marker must be findable at all, or the
      // three isFalse assertions below prove nothing.
      expect(rustEverything.contains(marker), isTrue);

      for (final MapEntry<String, Stream<LicenseEntry>> platform
          in <String, Stream<LicenseEntry>>{
            'iOS': NativeLicenses.appleEntriesForTest(),
            'Windows': NativeLicenses.windowsEntriesForTest(),
            'Android': NativeLicenses.androidEntriesForTest(),
          }.entries) {
        final List<LicenseEntry> platformEntries = await platform.value
            .toList();
        expect(
          platformEntries.map(textOf).join('\n').contains(marker),
          isFalse,
          reason: 'the Rust document is yielded twice on ${platform.key}',
        );
      }
    });
  });
}
