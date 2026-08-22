@TestOn('vm')
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keeps `PACKAGED-LICENCE-TEXT-PROVENANCE.md` in step with the assets it
/// describes.
///
/// That table is where a source-archive recipient looks to find out where a
/// shipped licence text came from. On 2026-08-18 it held twelve rows while
/// `assets/licenses/` held thirteen files: `Microsoft-WebView2-BSD-3-Clause.txt`
/// shipped with no row at all. Its bytes WERE pinned, by a digest constant in
/// `native_licenses_test.dart` — but a byte pin is not a provenance record, and
/// nothing connected the two, so an asset could be added through a route that
/// never touched this document and no test would notice.
///
/// Both directions matter. A missing row is a shipped text with no recorded
/// origin; a stale row is a record for a file that is no longer there.
void main() {
  final provenance = File(
    '../docs/release/evidence/license-sources/'
    'PACKAGED-LICENCE-TEXT-PROVENANCE.md',
  );
  final assets = Directory('assets/licenses');

  test('every shipped licence text has a provenance row, and vice versa', () {
    // recursive: true here and in the count test below. `assets/licenses/` is
    // declared to pubspec as a DIRECTORY, so Flutter bundles anything beneath
    // it — including a nested subdirectory, which a non-recursive listing would
    // have shipped with no provenance row, no digest check, and no effect on
    // the stated total.
    expect(
      provenance.existsSync(),
      isTrue,
      reason: 'the provenance record moved; this gate is reading nothing',
    );
    expect(assets.existsSync(), isTrue);

    final text = provenance.readAsStringSync();
    final recorded =
        RegExp(r'\|\s*`([^`]+\.txt)`\s*\|\s*([\d,]+)\s*\|\s*`([0-9a-f]{64})`')
            .allMatches(text)
            .map((m) => (m.group(1)!, m.group(2)!, m.group(3)!))
            .toList();
    expect(
      recorded.length,
      greaterThanOrEqualTo(13),
      reason:
          'only ${recorded.length} rows parsed out of the table; the format '
          'changed and this test would otherwise pass vacuously',
    );

    // The path RELATIVE to assets/licenses, not the basename. Taking the last
    // segment merged `nested/libass-ISC.txt` into the root `libass-ISC.txt`, so
    // a nested file with a colliding name looked covered and the digest check
    // then validated the root file instead of it. That hole arrived WITH the
    // recursive listing: before it, basename and relative path were the same
    // thing.
    // Normalise separators FIRST, then strip the directory prefix. Windows
    // listSync returns a mix of forward and back slashes, so comparing raw
    // paths against the directory prefix strips nothing and every row reads
    // as "no longer shipped".
    final root = assets.path.replaceAll('\\', '/');
    String relative(File f) {
      final normalised = f.path.replaceAll('\\', '/');
      final stripped = normalised.startsWith(root)
          ? normalised.substring(root.length)
          : normalised;
      return stripped.replaceFirst(RegExp('^/'), '');
    }

    final shipped = assets
        .listSync(recursive: true)
        .whereType<File>()
        .map(relative)
        .where((n) => n.endsWith('.txt'))
        .toSet();
    final rowNames = recorded.map((r) => r.$1).toSet();

    expect(
      shipped.difference(rowNames),
      isEmpty,
      reason:
          'these licence texts ship with no provenance row, so nothing records '
          'where they came from',
    );
    expect(
      rowNames.difference(shipped),
      isEmpty,
      reason: 'these provenance rows describe files that are no longer shipped',
    );
  });

  test('every provenance row matches the bytes it claims to describe', () {
    // The row is only worth having if it is true. A digest recorded once and
    // never re-checked is the failure mode this whole directory exists against.
    final text = provenance.readAsStringSync();
    final recorded = RegExp(
      r'\|\s*`([^`]+\.txt)`\s*\|\s*([\d,]+)\s*\|\s*`([0-9a-f]{64})`',
    ).allMatches(text).map((m) => (m.group(1)!, m.group(2)!, m.group(3)!));

    for (final (name, size, digest) in recorded) {
      // Joined onto the directory, so a relative row like `nested/x.txt`
      // resolves to the nested file rather than to a root file of that name.
      final file = File('assets/licenses/$name');
      expect(file.existsSync(), isTrue, reason: '$name is recorded but absent');
      final bytes = file.readAsBytesSync();
      expect(
        bytes.length,
        int.parse(size.replaceAll(',', '')),
        reason: '$name byte count disagrees with its provenance row',
      );
      expect(
        sha256.convert(bytes).toString(),
        digest,
        reason: '$name content disagrees with its recorded digest',
      );
    }
  });

  test('every stated licence-asset count matches the real directory', () {
    // Three counts in these records have gone stale by being maintained as
    // prose. THIRD_PARTY_NOTICES.md says so itself: "wrong twice in the same
    // way - it said eleven when there were twelve, and twelve when there were
    // thirteen", and its remedy was a sentence asking whoever adds a
    // fourteenth to remember. That is the mechanism that had already failed
    // twice, and it failed again: the same correction never reached
    // THIRD_PARTY_LICENSES.json, which still called eleven the complete
    // listing after the directory reached thirteen.
    //
    // So the number is derived here instead. A fourteenth asset fails this
    // test rather than depending on anyone noticing.
    final actual = Directory('assets/licenses')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.txt'))
        .length;
    expect(actual, greaterThan(0));

    const words = <String, int>{
      'eleven': 11,
      'twelve': 12,
      'thirteen': 13,
      'fourteen': 14,
      'fifteen': 15,
      'sixteen': 16,
      'seventeen': 17,
      'eighteen': 18,
    };

    final sources = <String, String>{
      'THIRD_PARTY_NOTICES.md': '../docs/release/THIRD_PARTY_NOTICES.md',
      'THIRD_PARTY_LICENSES.json': '../docs/release/THIRD_PARTY_LICENSES.json',
    };

    var claimsChecked = 0;
    for (final entry in sources.entries) {
      final file = File(entry.value);
      expect(file.existsSync(), isTrue, reason: '${entry.key} moved');
      final text = file.readAsStringSync().toLowerCase();

      // Only the phrasings that assert a CURRENT directory total. A dated,
      // explicitly historical count ("covered eleven files") is a record of a
      // past measurement and must stay as written.
      final claims = RegExp(
        r'(?:directory holds|complete directory listing[^.]*?is|holds)\s+\*{0,2}([a-z]+)\*{0,2}',
      ).allMatches(text);

      for (final claim in claims) {
        final word = claim.group(1)!;
        if (!words.containsKey(word)) continue;
        claimsChecked += 1;
        expect(
          words[word],
          actual,
          reason:
              '${entry.key} states the licence-asset directory holds "$word" '
              '(${words[word]}) but it holds $actual. Update the sentence in '
              'the same commit as the asset.',
        );
      }
    }

    expect(
      claimsChecked,
      greaterThan(0),
      reason:
          'no directory-total claim matched in either record - the phrasing '
          'changed and this test would otherwise pass vacuously',
    );
  });
}
