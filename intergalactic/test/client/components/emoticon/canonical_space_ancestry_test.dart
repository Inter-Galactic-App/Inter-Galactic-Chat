import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/emoticon/canonical_space_ancestry.dart';
import 'package:intergalactic/client/matrix/matrix_space_link_validation.dart';

void main() {
  group('canonicalSpaceAncestorIds', () {
    test('uses only the canonical parent hierarchy, nearest first', () {
      final parents = <String, List<String>>{
        '!room:example.org': ['!canonical:example.org'],
        '!canonical:example.org': ['!root:example.org'],
        '!root:example.org': [],
        '!also-contains-room:example.org': [],
      };

      expect(
        canonicalSpaceAncestorIds(
          roomId: '!room:example.org',
          canonicalParentIdsFor: (roomId) => parents[roomId] ?? const [],
        ),
        ['!canonical:example.org', '!root:example.org'],
      );
    });

    test('does not expand non-canonical sibling spaces', () {
      final parents = <String, List<String>>{
        '!room:example.org': ['!canonical:example.org'],
        '!canonical:example.org': [],
        '!non-canonical:example.org': ['!unrelated:example.org'],
      };

      final ancestors = canonicalSpaceAncestorIds(
        roomId: '!room:example.org',
        canonicalParentIdsFor: (roomId) => parents[roomId] ?? const [],
      );

      expect(ancestors, ['!canonical:example.org']);
      expect(ancestors, isNot(contains('!non-canonical:example.org')));
      expect(ancestors, isNot(contains('!unrelated:example.org')));
    });

    test('is cycle-safe and returns each ancestor once', () {
      final parents = <String, List<String>>{
        '!room:example.org': ['!space-a:example.org'],
        '!space-a:example.org': ['!space-b:example.org'],
        '!space-b:example.org': ['!space-a:example.org'],
      };

      expect(
        canonicalSpaceAncestorIds(
          roomId: '!room:example.org',
          canonicalParentIdsFor: (roomId) => parents[roomId] ?? const [],
        ),
        ['!space-a:example.org', '!space-b:example.org'],
      );
    });

    test('bounds a malformed chain of canonical parents', () {
      final ancestors = canonicalSpaceAncestorIds(
        roomId: '!room:example.org',
        canonicalParentIdsFor: (roomId) {
          final index = roomId == '!room:example.org'
              ? 0
              : int.parse(roomId.substring(6, roomId.indexOf(':')));
          return ['!space${index + 1}:example.org'];
        },
      );
      expect(ancestors, hasLength(128));
      expect(ancestors.last, '!space128:example.org');
    });
  });

  group('canonicalSpaceParentIds', () {
    test('isolates non-canonical direct Spaces', () {
      final parents = <String, bool>{
        '!canonical:example.org': true,
        '!also-contains-room:example.org': false,
      };

      expect(
        canonicalSpaceParentIds(
          parentState: parents,
          isCanonical: (canonical) => canonical,
          hasValidVia: (_) => true,
          isLegitimateParent: (_, _) => true,
        ),
        ['!canonical:example.org'],
      );
    });

    test('selects the lowest valid canonical parent ID', () {
      final parents = <String, bool>{
        '!second:example.org': true,
        '!first:example.org': true,
      };

      expect(
        canonicalSpaceParentIds(
          parentState: parents,
          isCanonical: (canonical) => canonical,
          hasValidVia: (_) => true,
          isLegitimateParent: (_, _) => true,
        ),
        ['!first:example.org'],
      );
    });

    test('treats missing parent state as no Space-pack ancestry', () {
      expect(
        canonicalSpaceParentIds<bool>(
          parentState: null,
          isCanonical: (canonical) => canonical,
          hasValidVia: (_) => true,
          isLegitimateParent: (_, _) => true,
        ),
        isEmpty,
      );
    });

    test('rejects canonical links with invalid via or no parent authority', () {
      final parents = <String, String>{
        '!forged:example.org': 'forged',
        '!missing-via:example.org': 'missing',
        '!valid:example.org': 'valid',
      };
      expect(
        canonicalSpaceParentIds(
          parentState: parents,
          isCanonical: (_) => true,
          hasValidVia: (state) => state != 'missing',
          isLegitimateParent: (_, state) => state == 'valid',
        ),
        ['!valid:example.org'],
      );
    });
  });

  group('hasValidSpaceVia', () {
    test('requires usable server names', () {
      expect(hasValidSpaceVia(['example.org']), isTrue);
      expect(hasValidSpaceVia(['example.org:8448']), isTrue);
      expect(hasValidSpaceVia(null), isFalse);
      expect(hasValidSpaceVia([]), isFalse);
      expect(hasValidSpaceVia(['']), isFalse);
      expect(hasValidSpaceVia(['https://example.org']), isFalse);
      expect(hasValidSpaceVia(['example.org:bad']), isFalse);
      expect(hasValidSpaceVia(['bad_host']), isFalse);
      expect(hasValidSpaceVia([42]), isFalse);
    });
  });
}
