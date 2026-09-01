@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Holds `docs/release/THIRD_PARTY_LICENSES.json` level with the lockfiles it
/// claims to describe, in BOTH directions.
///
/// The 2026-08-19 dependency-accounting audit found the roster had drifted
/// silently and at scale: 37 packages recorded at a version the lockfile no
/// longer resolved, `camera_windows` absent for four days across three edits of
/// this very file, and `window_manager` recorded as the stock pub.dev package
/// while we ship a patched vendored fork. Every one of those is invisible to a
/// reader and to every other licence gate, because the other gates ask whether
/// a RECORD is well-formed - never whether the set of records still matches the
/// set of dependencies.
///
/// Both directions matter and the audit said so explicitly: a stale row for a
/// removed package is the same defect as a missing row for an added one. A
/// record that over-claims is a compliance statement about something we do not
/// ship.
///
/// What this gate is NOT: it compares a source tree against a source roster. It
/// says nothing about a built artefact. `Assert-NativePayloadInventory.ps1`
/// covers the Windows payload; Android and Apple are still opened by hand. A
/// green run here is not candidate evidence and must never be cited as any.
void main() {
  /// Rows deliberately kept after their package left the lockfile retain a
  /// structured release scope, so source accounting for older distributed
  /// releases remains visible without putting workflow state in public records.
  bool isHistorical(Map<String, dynamic> row) =>
      row['release_scope'] == 'historical';

  Map<String, dynamic> readInventory() {
    final file = File('../docs/release/THIRD_PARTY_LICENSES.json');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'inventory not found at ${file.absolute.path}',
    );
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  }

  Map<String, Map<String, dynamic>> section(
    Map<String, dynamic> inventory,
    String name,
  ) {
    final rows = (inventory[name] as List).cast<Map<String, dynamic>>();
    return <String, Map<String, dynamic>>{
      for (final row in rows) row['name'] as String: row,
    };
  }

  /// `pubspec.lock` lives at the CHECKOUT ROOT, not beside this package - it is
  /// a pub workspace, and resolution is workspace-wide.
  Map<String, String> readPubspecLock() {
    final file = File('../pubspec.lock');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'pubspec.lock not found at ${file.absolute.path}',
    );
    final resolved = <String, String>{};
    var inPackages = false;
    String? current;
    for (final line in file.readAsLinesSync()) {
      if (line.startsWith('packages:')) {
        inPackages = true;
        continue;
      }
      // Any other column-0 key ends the packages block (e.g. `sdks:`).
      if (inPackages && RegExp(r'^[a-z]').hasMatch(line)) break;
      if (!inPackages) continue;

      final package = RegExp(r'^  ([A-Za-z0-9_]+):\s*$').firstMatch(line);
      if (package != null) {
        current = package.group(1);
        continue;
      }
      final version = RegExp(r'^    version: "?([^"]+)"?\s*$').firstMatch(line);
      if (version != null && current != null) {
        resolved[current] = version.group(1)!.trim();
      }
    }
    return resolved;
  }

  /// CocoaPods records subspecs as `Root/Subspec (version)`; the inventory
  /// carries one row per root pod, so subspecs collapse into their root.
  Map<String, String> readPodfileLock(String path) {
    final file = File(path);
    expect(
      file.existsSync(),
      isTrue,
      reason: 'Podfile.lock not found at ${file.absolute.path}',
    );
    final resolved = <String, String>{};
    var inPods = false;
    for (final line in file.readAsLinesSync()) {
      if (line.startsWith('PODS:')) {
        inPods = true;
        continue;
      }
      if (inPods && RegExp(r'^[A-Z]').hasMatch(line)) break;
      if (!inPods) continue;

      final pod = RegExp(
        r'^  - ([^ (/]+)(?:/[^ (]+)? \(([^)]+)\)',
      ).firstMatch(line);
      if (pod != null) {
        resolved.putIfAbsent(pod.group(1)!, () => pod.group(2)!);
      }
    }
    return resolved;
  }

  void expectParity({
    required String label,
    required Map<String, String> lockfile,
    required Map<String, Map<String, dynamic>> rows,
  }) {
    // A parser that silently matched nothing would report parity between two
    // empty sets. Both sides must be non-empty before any comparison counts.
    expect(
      lockfile,
      isNotEmpty,
      reason:
          '$label: parsed zero packages from the lockfile, so this comparison '
          'would be vacuous. The lockfile format changed, or the path is wrong',
    );
    expect(
      rows,
      isNotEmpty,
      reason:
          '$label: the inventory section is empty, so this would be vacuous',
    );

    final missing = lockfile.keys.where((n) => !rows.containsKey(n)).toList()
      ..sort();
    expect(
      missing,
      isEmpty,
      reason:
          '$label: these packages resolve in the lockfile but have NO row in '
          'THIRD_PARTY_LICENSES.json, so we ship them with no recorded '
          'licence:\n  ${missing.join('\n  ')}',
    );

    final stale =
        rows.entries
            .where(
              (e) => !lockfile.containsKey(e.key) && !isHistorical(e.value),
            )
            .map((e) => e.key)
            .toList()
          ..sort();
    expect(
      stale,
      isEmpty,
      reason:
          '$label: these rows claim a package the lockfile no longer resolves. '
          'Either delete the row, or set release_scope to "historical" if it '
          'is deliberately retained for source-offer accounting on an older '
          'release:\n  ${stale.join('\n  ')}',
    );

    final drifted = <String>[];
    for (final entry in lockfile.entries) {
      final row = rows[entry.key];
      if (row == null) continue;
      final recorded = row['version']?.toString();
      if (recorded != entry.value) {
        drifted.add('${entry.key}: lockfile ${entry.value}, row $recorded');
      }
    }
    drifted.sort();
    expect(
      drifted,
      isEmpty,
      reason:
          '$label: these rows record a different version than the lockfile '
          'resolves. Re-hash the licence text rather than editing the version '
          'field alone - this project\'s own FreeType capture found the licence '
          'text differing INSIDE the credit line at an identical byte '
          'size:\n  ${drifted.join('\n  ')}',
    );
  }

  test('every pubspec.lock package has a matching inventory row', () {
    final inventory = readInventory();
    expectParity(
      label: 'pubspec.lock -> dart_flutter_packages',
      lockfile: readPubspecLock(),
      rows: section(inventory, 'dart_flutter_packages'),
    );
  });

  test('every iOS pod has a matching inventory row', () {
    final inventory = readInventory();
    expectParity(
      label: 'ios/Podfile.lock -> ios_pods',
      lockfile: readPodfileLock('ios/Podfile.lock'),
      rows: section(inventory, 'ios_pods'),
    );
  });

  test('macOS pods are either a declared input or an explicit exclusion', () {
    // The sequencing risk the audit named: macOS pods are correctly LATENT
    // today because no macOS build has been distributed and an owner
    // do-not-distribute hold stands. 14 pods have no row, one of them
    // (HotKey) a genuine third-party native component. The moment the hold
    // lifts, that becomes an active gap - and nothing would have announced it.
    //
    // So the exclusion has to be a written claim rather than an omission, and
    // withdrawing it has to turn this gate red until the rows exist. Per
    // recording-third-party-licenses.md an omitted row is not "not applicable".
    final inventory = readInventory();
    final excluded =
        ((inventory['inputs'] as Map<String, dynamic>)['excluded_pod_lockfiles']
                    as List? ??
                const [])
            .cast<Map<String, dynamic>>();

    const macosLockfile = 'intergalactic/macos/Podfile.lock';
    Map<String, dynamic>? declaration;
    for (final entry in excluded) {
      if (entry['path'] == macosLockfile) {
        declaration = entry;
        break;
      }
    }

    if (declaration != null && declaration['state'] == 'not_applicable') {
      expect(
        (declaration['reason'] as String? ?? '').trim(),
        isNotEmpty,
        reason:
            'the macOS lockfile is excluded with no stated reason. An '
            'exclusion without a reason is an omission wearing a label',
      );
      return;
    }

    // The hold is gone, or the exclusion was dropped: macOS is now a real
    // input and owes the same parity as iOS.
    expectParity(
      label: 'macos/Podfile.lock -> ios_pods',
      lockfile: readPodfileLock('macos/Podfile.lock'),
      rows: section(inventory, 'ios_pods'),
    );
  });
}
