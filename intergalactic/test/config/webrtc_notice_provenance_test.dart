@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Holds the four patched-libwebrtc source pointers in AGREEMENT.
///
/// `docs/agent-control/integration-queue.json` carries the release-process rule
/// — the pin and the two commit SHAs move in the same change across every
/// surface that names them, because *"partial application is the failure mode
/// this project keeps hitting"*. The same row says plainly not to move any of
/// them before 0.8.1 is distributed; until then the 0.8.0 values correctly
/// describe the artefact people actually have.
///
/// **This does not enforce that rule, and must not be described as doing so.**
/// It does not read the queue row and cannot tell four surfaces updated in one
/// commit from four updated across four — same-change atomicity is unenforced
/// and stays a process rule. What it does is make a partial update unable to
/// survive as a green state.
///
/// So it asserts AGREEMENT, never a particular value. Green today with all four
/// on the distributed pair, green after a correct simultaneous update, red the
/// moment one moves alone.
///
/// Each commit is extracted **by role**, anchored on the repository it belongs
/// to, and compared role-to-role. An earlier version compared unordered sets,
/// which passed when two surfaces named the same two SHAs with the roles
/// SWAPPED — a notice sending someone to the wrapper tree for the core commit.
/// Anchoring also removes the fixed character windows that version used; those
/// silently included or excluded pointers as surrounding prose changed.
///
/// A second test covers the rebuild recipe's OTHER pin. The four surfaces
/// agreeing on the patch tips does not make the recipe coherent: it also names
/// an upstream base, and a base that does not carry those tips sends someone
/// through a sync at step 3 and a checkout at step 4 that contradict each other.
/// That is compared against `pinned-dependency-revisions.json`, which the recipe
/// itself calls the thing that actually pins the tree. Deliberately NOT compared
/// against the artefact sidecar manifest: that file lives in the Matrix_Dev
/// workspace, outside the checkout CI clones, so a test naming it would be
/// unrunnable there and would pass locally for the wrong reason.
///
/// The recipe's fourth pin, `depot_tools`, is recorded nowhere else, so there is
/// nothing to compare it against and no gate is claimed over it.
///
/// What this cannot prove: that the agreed commits built the DLL in the
/// package. That needs the artefact opened and stays RELEASE PIPELINE's step.
void main() {
  /// The first 40-hex commit appearing after [anchor], or null.
  ///
  /// Bounded by [window] only to stop a missing commit silently matching one
  /// from a later section; the anchor does the real work.
  String? commitAfter(String text, String anchor, {int window = 300}) {
    final at = text.indexOf(anchor);
    if (at < 0) return null;
    final slice = text.substring(at, (at + window).clamp(0, text.length));
    return RegExp(r'\b[0-9a-f]{40}\b').firstMatch(slice)?.group(0);
  }

  test('the libwebrtc source pointers agree across every surface', () {
    final surfaces = <String, ({String path, String core, String wrapper})>{
      'the in-app notice': (
        path: 'lib/config/native_licenses.dart',
        core: 'Inter-Galactic-App/webrtc-core',
        wrapper: 'Inter-Galactic-App/libwebrtc',
      ),
      'SOURCE_OFFER.md': (
        path: '../docs/policies/SOURCE_OFFER.md',
        core: 'Inter-Galactic-App/webrtc-core',
        wrapper: 'Inter-Galactic-App/libwebrtc',
      ),
      'THIRD_PARTY_LICENSES.json': (
        path: '../docs/release/THIRD_PARTY_LICENSES.json',
        core: 'webrtc-core (branch',
        wrapper: 'libwebrtc (branch',
      ),
      // The rebuild recipe. It agrees today, and someone following it after a
      // release that moved the others would rebuild the superseded DLL — so it
      // is a surface, not a bystander. If it is ever deliberately pinned to a
      // historical revision, remove it HERE with the reason rather than letting
      // it drift silently.
      'the webrtc-fork rebuild recipe': (
        path:
            '../docs/architecture/calls-streaming-audio/webrtc-fork/README.md',
        // The TABLE CELLS, pipe-delimited. Bare 'WebRTC core' also appears in
        // a prose bullet and in a remotes table further up, neither of which
        // carries a commit — anchoring there found nothing and the vacuity
        // guard caught it.
        core: '| WebRTC core |',
        wrapper: '| libwebrtc wrapper |',
      ),
    };

    final found = <String, ({String core, String wrapper})>{};
    for (final entry in surfaces.entries) {
      final file = File(entry.value.path);
      expect(
        file.existsSync(),
        isTrue,
        reason: '${entry.key} is missing at ${entry.value.path}',
      );
      final text = file.readAsStringSync();
      final core = commitAfter(text, entry.value.core);
      final wrapper = commitAfter(text, entry.value.wrapper);
      expect(
        core,
        isNotNull,
        reason:
            'no webrtc-core commit found in ${entry.key} — its wording changed '
            'and this test would otherwise pass vacuously',
      );
      expect(
        wrapper,
        isNotNull,
        reason: 'no libwebrtc commit found in ${entry.key}',
      );
      expect(
        core,
        isNot(equals(wrapper)),
        reason:
            '${entry.key} names the same SHA for both trees, which means the '
            'anchors are matching one pointer twice',
      );
      found[entry.key] = (core: core!, wrapper: wrapper!);
    }

    final reference = found['SOURCE_OFFER.md']!;
    for (final entry in found.entries) {
      if (entry.key == 'SOURCE_OFFER.md') continue;
      expect(
        entry.value.core,
        reference.core,
        reason:
            '${entry.key} names webrtc-core ${entry.value.core} while '
            'SOURCE_OFFER.md names ${reference.core}. Every surface moves '
            'together or none does.',
      );
      expect(
        entry.value.wrapper,
        reference.wrapper,
        reason:
            '${entry.key} names libwebrtc ${entry.value.wrapper} while '
            'SOURCE_OFFER.md names ${reference.wrapper}.',
      );
    }
  });

  test('the rebuild recipe base matches the revisions that pin the tree', () {
    const recipePath =
        '../docs/architecture/calls-streaming-audio/webrtc-fork/README.md';
    const revisionsPath =
        '../docs/architecture/calls-streaming-audio/webrtc-fork/'
        'pinned-dependency-revisions.json';

    final recipe = File(recipePath);
    final revisions = File(revisionsPath);
    expect(recipe.existsSync(), isTrue, reason: 'missing at $recipePath');
    expect(revisions.existsSync(), isTrue, reason: 'missing at $revisionsPath');

    // The TABLE CELL. Bare 'upstream WebRTC base' also appears in prose above
    // the table without a commit beside it.
    final stated = commitAfter(
      recipe.readAsStringSync(),
      '| upstream WebRTC base |',
    );
    expect(
      stated,
      isNotNull,
      reason:
          'no upstream base commit found in the rebuild recipe — its table '
          'wording changed and this test would otherwise pass vacuously',
    );

    final decoded = jsonDecode(revisions.readAsStringSync());
    expect(
      decoded,
      isA<Map<String, dynamic>>(),
      reason: '$revisionsPath is not a JSON object',
    );
    final pinned = (decoded as Map<String, dynamic>)['src'];
    expect(
      pinned,
      isA<String>(),
      reason:
          "$revisionsPath has no 'src' revision, so there is nothing to check "
          'the recipe against — the gate would pass vacuously',
    );

    expect(
      stated,
      pinned,
      reason:
          'the rebuild recipe syncs to $pinned at step 3 but names $stated as '
          'the upstream base. The base and the patch tips have to describe one '
          'coherent checkout; following this recipe would produce neither.',
    );
  });
}
