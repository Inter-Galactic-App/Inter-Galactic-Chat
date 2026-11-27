import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/ui/organisms/side_navigation_bar/side_navigation_bar.dart';

/// Owner report, 2026-09-06: a space shows an indication when a room inside it
/// has a new message, and the favourites rail button shows nothing. So the only
/// place a new message was ever visible was the space rail, which teaches users
/// to keep using the space route instead of their favourites.
void main() {
  group('FavoritesUnread.from', () {
    test('no favourites means nothing to draw', () {
      final unread = FavoritesUnread.from(const []);

      expect(unread.notificationCount, 0);
      expect(unread.highlightedNotificationCount, 0);
      expect(unread.roomWideMentionNotification, isFalse);
    });

    test('ordinary unread across rooms is summed', () {
      final unread = FavoritesUnread.from([
        _FakeRoom(notifications: 3),
        _FakeRoom(notifications: 4),
      ]);

      expect(unread.notificationCount, 7);
      expect(unread.highlightedNotificationCount, 0);
    });

    test('highlights are summed separately from ordinary unread', () {
      // The two marks mean different things - a dot on the rail edge versus a
      // count badge - so collapsing them into one number would draw the wrong
      // one.
      final unread = FavoritesUnread.from([
        _FakeRoom(notifications: 5, highlights: 2),
      ]);

      expect(unread.notificationCount, 5);
      expect(unread.highlightedNotificationCount, 2);
    });

    test('a room-wide mention in any one favourite carries', () {
      final unread = FavoritesUnread.from([
        _FakeRoom(notifications: 1),
        _FakeRoom(notifications: 1, roomWideMention: true),
      ]);

      expect(unread.roomWideMentionNotification, isTrue);
    });

    group('a muted favourite stays silent', () {
      // The rule that makes this worth writing. A dot the user cannot trace to
      // any room they can hear is worse than no dot, and the muting rule lives
      // in Room's display* getters rather than here - so this also checks the
      // aggregate reads those and not the raw counts.
      test('a fully muted room contributes nothing', () {
        final unread = FavoritesUnread.from([
          _FakeRoom(
            notifications: 9,
            highlights: 3,
            roomWideMention: true,
            pushRule: PushRule.dontNotify,
          ),
        ]);

        expect(unread.notificationCount, 0);
        expect(unread.highlightedNotificationCount, 0);
        expect(unread.roomWideMentionNotification, isFalse);
      });

      test('a mentions-only room still reports its mentions', () {
        final unread = FavoritesUnread.from([
          _FakeRoom(
            notifications: 9,
            highlights: 3,
            roomWideMention: true,
            pushRule: PushRule.mentionsOnly,
          ),
        ]);

        expect(
          unread.notificationCount,
          0,
          reason: 'mentions-only means ordinary traffic raises nothing',
        );
        expect(unread.highlightedNotificationCount, 3);
        expect(unread.roomWideMentionNotification, isTrue);
      });

      test('a muted room does not silence its neighbours', () {
        final unread = FavoritesUnread.from([
          _FakeRoom(notifications: 9, pushRule: PushRule.dontNotify),
          _FakeRoom(notifications: 2),
        ]);

        expect(unread.notificationCount, 2);
      });
    });
  });

  // The dot and the badge are drawn inside the button's excluded semantics
  // subtree, so a screen-reader user's only route to the unread state is this
  // label. A test that asserted "the label is non-null" would pass against a
  // label that said "Favorites" and nothing else, which is the bug - so each
  // case names the number it has to carry.
  group('favoritesUnreadSemantics', () {
    test('nothing unread adds nothing to announce', () {
      expect(favoritesUnreadSemantics(FavoritesUnread.none), isNull);
    });

    test('ordinary unread is announced with its count', () {
      final label = favoritesUnreadSemantics(
        const FavoritesUnread(
          notificationCount: 4,
          highlightedNotificationCount: 0,
          roomWideMentionNotification: false,
        ),
      );

      expect(label, contains('4'));
    });

    test('a mention is announced instead of the ordinary count', () {
      // The two marks mean different things and the mention is the one a user
      // acts on, so it must not be buried behind the larger unread number.
      final label = favoritesUnreadSemantics(
        const FavoritesUnread(
          notificationCount: 9,
          highlightedNotificationCount: 2,
          roomWideMentionNotification: false,
        ),
      );

      expect(label, contains('2'));
      expect(
        label,
        isNot(contains('9')),
        reason: 'the badge shows the mention count, so the label must agree',
      );
    });

    test('a room-wide mention is announced with no counted highlight', () {
      // `@room` raises the exclamation badge without adding to the highlight
      // count, so a label keyed only on numbers would say nothing about it.
      final label = favoritesUnreadSemantics(
        const FavoritesUnread(
          notificationCount: 3,
          highlightedNotificationCount: 0,
          roomWideMentionNotification: true,
        ),
      );

      expect(label, isNotNull);
      expect(label, isNot(contains('3')));
    });
  });
}

/// Sets the RAW counts and the push rule, leaving Room's own `display*` getters
/// to apply the muting rule - the same code the rest of the app trusts.
// EXTENDS rather than implements: the muting rule lives in Room's concrete
// display* getters, and `implements` would leave those unimplemented and force
// this fake to restate the rule it is supposed to be testing.
class _FakeRoom extends Room {
  _FakeRoom({
    this.notifications = 0,
    this.highlights = 0,
    this.roomWideMention = false,
    PushRule pushRule = PushRule.notify,
  }) : pushRuleValue = pushRule;

  final int notifications;
  final int highlights;
  final bool roomWideMention;
  final PushRule pushRuleValue;

  @override
  int get notificationCount => notifications;

  @override
  int get highlightedNotificationCount => highlights;

  @override
  bool get hasRoomWideMentionNotification => roomWideMention;

  @override
  PushRule get pushRule => pushRuleValue;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
