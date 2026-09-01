import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/utils/mention_search.dart';

/// A member whose room nickname hides both their username and the account name
/// everyone knew them by before they renamed themselves.
const _renamedMember = MentionSearchCandidate(
  userId: '@bob:example.org',
  displayName: 'Stargazer',
  accountDisplayName: 'Robert Vega',
);

/// A member with no nickname, so the row label, the account name and the
/// username all describe the same person.
const _plainMember = MentionSearchCandidate(
  userId: '@alice:example.org',
  displayName: 'alice',
  accountDisplayName: 'alice',
);

/// A member with no nickname whose account display name differs from their
/// username, which is the shape the old nickname-only search already handled.
/// Widening the search must not cost them their existing match.
const _nicknamelessMember = MentionSearchCandidate(
  userId: '@carol:example.org',
  displayName: 'Carol Danvers',
  accountDisplayName: 'Carol Danvers',
);

List<String> _idsOf(Iterable<MentionSearchCandidate> results) =>
    results.map((result) => result.userId).toList();

void main() {
  group('searchMentionCandidates', () {
    test('finds a member by their room nickname', () {
      final results = searchMentionCandidates('starg', const [
        _renamedMember,
        _plainMember,
      ]);

      expect(_idsOf(results), ['@bob:example.org']);
    });

    test('finds a member by their username localpart', () {
      final results = searchMentionCandidates('bob', const [
        _renamedMember,
        _plainMember,
      ]);

      expect(_idsOf(results), ['@bob:example.org']);
    });

    test('finds a member by their global account display name', () {
      final results = searchMentionCandidates('robert', const [
        _renamedMember,
        _plainMember,
      ]);

      expect(_idsOf(results), ['@bob:example.org']);
    });

    test('lists a member once when several of their names match', () {
      final results = searchMentionCandidates('alice', const [
        _plainMember,
        _renamedMember,
      ]);

      // 'alice' is this member's nickname, their localpart AND their account
      // display name, which is three separate matches for one person.
      expect(_idsOf(results), ['@alice:example.org']);
    });

    test('returns nothing when no name matches', () {
      final results = searchMentionCandidates('qqzx', const [
        _renamedMember,
        _plainMember,
      ]);

      expect(results, isEmpty);
    });

    test('still matches a member with no nickname by both of their names', () {
      // Their row label IS their account display name, and it is what the
      // nickname-only search matched before. Both routes must still land.
      expect(
        _idsOf(
          searchMentionCandidates('danvers', const [
            _nicknamelessMember,
            _renamedMember,
          ]),
        ),
        ['@carol:example.org'],
      );
      expect(
        _idsOf(
          searchMentionCandidates('carol', const [
            _nicknamelessMember,
            _renamedMember,
          ]),
        ),
        ['@carol:example.org'],
      );
    });

    test('ranks an exact match above a weaker match on another member', () {
      const looselyMatching = MentionSearchCandidate(
        userId: '@zeta:example.org',
        displayName: 'Alexander Iceborn',
      );
      const exactlyMatching = MentionSearchCandidate(
        userId: '@ali:example.org',
        displayName: 'Bob',
      );

      final results = searchMentionCandidates('ali', const [
        looselyMatching,
        exactlyMatching,
      ]);

      expect(_idsOf(results), ['@ali:example.org', '@zeta:example.org']);
    });

    test('an empty query lists everyone in the order given', () {
      final results = searchMentionCandidates('', const [
        _renamedMember,
        _plainMember,
      ]);

      expect(_idsOf(results), ['@bob:example.org', '@alice:example.org']);
    });

    test('a bare domain does not match every member', () {
      final results = searchMentionCandidates('example', const [
        _renamedMember,
        _plainMember,
      ]);

      expect(results, isEmpty);
    });

    test('a domain-qualified query still matches the full user id', () {
      final results = searchMentionCandidates('bob:example.org', const [
        _renamedMember,
        _plainMember,
      ]);

      expect(_idsOf(results), ['@bob:example.org']);
    });
  });

  group('mentionQueryMatches', () {
    test('offers @room for an empty or matching query', () {
      expect(mentionQueryMatches('@room', ''), isTrue);
      expect(mentionQueryMatches('@room', 'roo'), isTrue);
    });

    test('withholds @room for an unrelated query', () {
      expect(mentionQueryMatches('@room', 'stargazer'), isFalse);
    });
  });

  group('matrixLocalpart', () {
    test('drops the sigil and the domain', () {
      expect(matrixLocalpart('@alice:example.org'), 'alice');
      expect(matrixLocalpart('alice'), 'alice');
    });
  });
}
