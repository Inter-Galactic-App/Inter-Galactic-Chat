@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the evidence pointers in `docs/release/THIRD_PARTY_LICENSES.json`.
///
/// The machine-readable inventory tags each evidence location with a prefix:
/// `repo:` for a path in THIS repository, `workspace:` for one that lives only
/// in the Matrix_Dev workspace, `web:` for an upstream URL, `generated:` for a
/// build-time artefact. The prefix is a claim about where a recipient can
/// actually find the evidence, and the source archive is built from this repo
/// alone - so a `repo:` path that does not exist ships a pointer to nothing.
///
/// This has gone wrong three times: the DeepFilterNet OpenVINO directory that
/// had never existed in either repo (retracted by S&C 2026-08-15), and two
/// found by auditing every pointer rather than the one that was reported - the
/// 0.8.0+992 desktop-native receipt and notice, which are real but live only
/// in the workspace, and `Flutter.podspec`, which the Flutter tool generates
/// and which has never been tracked here. Reviewing prose cannot catch these;
/// resolving the paths can.
void main() {
  test('every repo: evidence path in THIRD_PARTY_LICENSES.json exists', () {
    final file = File('../docs/release/THIRD_PARTY_LICENSES.json');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'inventory not found at ${file.absolute.path}',
    );

    final repoRoot = Directory('..');
    final pattern = RegExp(r'repo:([A-Za-z0-9_\-./+]+)');
    final claimed = <String>{};

    void walk(Object? node) {
      if (node is Map) {
        node.values.forEach(walk);
      } else if (node is List) {
        node.forEach(walk);
      } else if (node is String) {
        for (final match in pattern.allMatches(node)) {
          claimed.add(match.group(1)!.replaceAll(RegExp(r'[.,]+$'), ''));
        }
      }
    }

    walk(jsonDecode(file.readAsStringSync()));
    expect(
      claimed,
      isNotEmpty,
      reason:
          'no repo: pointers found - the regex or the file shape changed, '
          'which would make this test silently vacuous',
    );

    // TRACKED, not merely present. existsSync() returns true for a generated
    // or untracked file sitting in a working tree, or in a CI checkout after a
    // build step - Flutter.podspec is exactly that, and it was one of the
    // three failures this test was written for. The source archive is built
    // from TRACKED content, so an untracked pointer still ships as a pointer
    // to nothing while an existence check stays green.
    final tracked = Process.runSync('git', const <String>[
      'ls-files',
      '-z',
    ], workingDirectory: repoRoot.path);
    expect(
      tracked.exitCode,
      0,
      reason:
          'git ls-files failed, so tracking cannot be verified: '
          '${tracked.stderr}',
    );
    final trackedPaths = (tracked.stdout as String)
        .split(String.fromCharCode(0))
        .where((entry) => entry.isNotEmpty)
        .toSet();
    expect(
      trackedPaths,
      isNotEmpty,
      reason: 'git reported no tracked files, which would make this vacuous',
    );

    bool isTracked(String path) =>
        trackedPaths.contains(path) ||
        trackedPaths.any((entry) => entry.startsWith('$path/'));

    final missing = claimed.where((path) => !isTracked(path)).toList()..sort();

    expect(
      missing,
      isEmpty,
      reason:
          'these repo: evidence paths are not TRACKED here, so the source '
          'archive built from this repository will not carry them. Either '
          'commit the evidence, or retag the pointer (workspace: / web: / '
          'generated:) so the record stops claiming this repository holds '
          'it:\n  ${missing.join('\n  ')}',
    );
  });

  test('no evidence pointer uses a scheme this gate does not know', () {
    // The gate above validates `repo:` and skips everything else, which is
    // correct only while every other scheme is a deliberate one. An
    // unrecognised scheme is not exempt from checking - it is UNCHECKED, and
    // the difference is invisible until someone audits the file by hand.
    //
    // Found exactly that way on 2026-08-18: eight pointers read
    // `local:intergalactic/.metadata`. `local:` appears nowhere among the four
    // schemes this record documents, and `.metadata` IS tracked here - so a
    // plain `repo:` pointer had been written under a label that made the
    // tracked-file check skip it. It was the revision pointer backing the
    // Flutter licence rows, the same rows flagged that week for resting on
    // evidence a recipient could not follow.
    final record = File('../docs/release/THIRD_PARTY_LICENSES.json');
    expect(record.existsSync(), isTrue);
    final text = record.readAsStringSync();

    // Add deliberately, with the reason it needs no path check - never just to
    // make this test pass.
    const known = <String>{
      'repo', // tracked in this repository; validated by the test above
      'workspace', // Matrix_Dev only, deliberately not in the source archive
      'web', // upstream URL
      'generated', // written at build time, not tracked
      'pub-cache', // resolved package in the local pub cache
      'app', // a path inside the built application
      'reference', // a named document rather than a fetchable path
      'source', // published corresponding-source archive
      'user-confirmation', // supplied attestation, no file to point at
      'project-confirmation', // project-origin assertion, no file to point at
    };

    final used = RegExp(r'"[a-z_]*evidence[a-z_]*"\s*:\s*"([^"]*)"')
        .allMatches(text)
        .expand((m) => m.group(1)!.split(';'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .map((part) => RegExp(r'^([a-z][a-z-]*):').firstMatch(part)?.group(1))
        .whereType<String>()
        .toSet();

    expect(
      used,
      isNotEmpty,
      reason:
          'no schemes parsed at all - the field names or the file shape '
          'changed and this test would otherwise pass vacuously',
    );
    expect(
      used.difference(known),
      isEmpty,
      reason:
          'these evidence-pointer schemes are undeclared, so nothing decides '
          'whether they need validating and the gate above silently skips '
          'them. Retag the pointers, or add the scheme to `known` WITH the '
          'reason it needs no check: ${used.difference(known)}',
    );
  });
}
