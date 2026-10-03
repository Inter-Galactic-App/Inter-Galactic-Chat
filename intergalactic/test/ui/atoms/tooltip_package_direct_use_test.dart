import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// App code must reach tooltips through `tiamat.Tooltip`, not through the
/// package the atom happens to be built on.
///
/// The tooltip ratchet (`scripts/ci/check-tooltip-component.sh`) counts
/// MATERIAL tooltip sites and says so in its own header: a `tooltip:` on a
/// non-atom widget is invisible to it. A raw `JustTheTooltip` is invisible to
/// it too, and is the same defect in the other direction - it bypasses the
/// house component while looking like it uses it, so it carries none of the
/// atom's semantics wrapper and drifts from its styling for free. Three such
/// sites survived the 2026-08 migration precisely because nothing looked for
/// them.
///
/// This scans package imports rather than types, so it cannot be defeated by
/// an import alias or triggered by a comment. It is deliberately a ratchet
/// with named exceptions rather than a count.
final _directTooltipImport = RegExp(
  r'''^import\s+['"]package:just_the_tooltip/''',
  multiLine: true,
);

void main() {
  test('no new direct just_the_tooltip use outside the house component', () {
    final repoRoot = _repoRoot();
    final offenders = <String>[];
    var scanned = 0;

    for (final dir in <String>['intergalactic/lib', 'tiamat/lib']) {
      final directory = Directory('${repoRoot.path}/$dir');
      expect(
        directory.existsSync(),
        isTrue,
        reason: 'the scan must actually have source to read: $dir',
      );

      for (final entity in directory.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        scanned++;
        if (!_directTooltipImport.hasMatch(entity.readAsStringSync())) {
          continue;
        }
        final relative = entity.path
            .replaceAll(r'\', '/')
            .replaceFirst('${repoRoot.path.replaceAll(r'\', '/')}/', '');
        if (allowed.containsKey(relative)) {
          continue;
        }
        offenders.add(relative);
      }
    }

    // Arming. A scan that reads nothing reports the same empty list as a clean
    // repository - the failure this whole file exists to make impossible.
    expect(
      scanned,
      greaterThan(100),
      reason: 'the scan found almost no Dart files, so its result is void',
    );

    expect(
      offenders,
      isEmpty,
      reason:
          'use tiamat.Tooltip. If the atom cannot express what the site '
          'needs, add it here with the reason, as the two existing entries do',
    );
  });

  test('every allowed exception still exists and still uses the package', () {
    // Otherwise the list rots into a description of a repository that no
    // longer exists, and the ratchet silently stops ratcheting.
    final repoRoot = _repoRoot();
    for (final entry in allowed.entries) {
      final file = File('${repoRoot.path}/${entry.key}');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'stale exception: ${entry.key}',
      );
      expect(
        _directTooltipImport.hasMatch(file.readAsStringSync()),
        isTrue,
        reason:
            '${entry.key} no longer uses the package - remove its exception',
      );
    }
  });
}

/// Files still allowed to import the package directly, each with the reason it
/// cannot use the atom today. Removing an entry is the goal; adding one needs
/// the same argument made again.
const allowed = <String, String>{
  // tiamat.Tooltip IS the house component - the atom is implemented on the
  // package, which is the only reason the dependency still exists.
  'tiamat/lib/atoms/tooltip.dart': 'the house component itself',
  // Shows a widget (_ReactionUsersTooltip, a member list) rather than a
  // string, and uses triggerMode: longPress. tiamat.Tooltip takes `text` only
  // and exposes no trigger mode, so this cannot move until the atom grows a
  // rich-content API - an owner decision for tiamat, which is Unassigned in
  // the ownership map.
  'intergalactic/lib/ui/molecules/timeline_events/events/timeline_event_view_reactions.dart':
      'rich tooltip content and a long-press trigger the atom cannot express',
};

/// The checkout root, found by walking up from the test's working directory.
///
/// `flutter test` runs from `intergalactic/`, but the packages being scanned
/// are siblings under the repo root, and this repo is a pub workspace, so the
/// root is where `.worktrees`-local paths resolve from.
Directory _repoRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 5; i++) {
    if (Directory('${dir.path}/tiamat/lib').existsSync()) {
      return dir;
    }
    dir = dir.parent;
  }
  fail('could not locate the checkout root from ${Directory.current.path}');
}
