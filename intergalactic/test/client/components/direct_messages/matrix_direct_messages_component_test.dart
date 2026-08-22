import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/direct_messages/matrix_direct_messages_component.dart';

void main() {
  group('MatrixDirectMessagesComponent joined one-to-one fallback', () {
    const selfId = '@self:ourgalaxy.space';
    const partnerId = '@friend:ourgalaxy.space';

    String? partnerIdFromSnapshot({
      required Iterable<String> joinedMemberIds,
      required bool isMembersListComplete,
      required int? joinedMemberCount,
      bool isRoomInSpace = false,
    }) {
      return MatrixDirectMessagesComponent.joinedOneToOnePartnerIdFromSnapshot(
        selfId: selfId,
        joinedMemberIds: joinedMemberIds,
        isMembersListComplete: isMembersListComplete,
        joinedMemberCount: joinedMemberCount,
        isRoomInSpace: isRoomInSpace,
      );
    }

    test('accepts a complete two-member joined room', () {
      expect(
        partnerIdFromSnapshot(
          joinedMemberIds: const [selfId, partnerId],
          isMembersListComplete: true,
          joinedMemberCount: 2,
        ),
        partnerId,
      );
    });

    test('accepts complete two-member rooms when joined count is omitted', () {
      expect(
        partnerIdFromSnapshot(
          joinedMemberIds: const [selfId, partnerId],
          isMembersListComplete: true,
          joinedMemberCount: null,
        ),
        partnerId,
      );
    });

    test('rejects incomplete member snapshots', () {
      expect(
        partnerIdFromSnapshot(
          joinedMemberIds: const [selfId, partnerId],
          isMembersListComplete: false,
          joinedMemberCount: 2,
        ),
        isNull,
      );
    });

    test('rejects group rooms even when only two members are cached', () {
      expect(
        partnerIdFromSnapshot(
          joinedMemberIds: const [selfId, partnerId],
          isMembersListComplete: false,
          joinedMemberCount: 3,
        ),
        isNull,
      );
    });

    test('rejects snapshots without the local user', () {
      expect(
        partnerIdFromSnapshot(
          joinedMemberIds: const [partnerId, '@other:ourgalaxy.space'],
          isMembersListComplete: true,
          joinedMemberCount: 2,
        ),
        isNull,
      );
    });

    test('rejects space rooms even when joined snapshot looks one-to-one', () {
      expect(
        partnerIdFromSnapshot(
          joinedMemberIds: const [selfId, partnerId],
          isMembersListComplete: true,
          joinedMemberCount: 2,
          isRoomInSpace: true,
        ),
        isNull,
      );
    });
  });

  group('MatrixDirectMessagesComponent app direct room markers', () {
    test('parses valid private account-data markers', () {
      final markers =
          MatrixDirectMessagesComponent.directRoomMarkersFromContent(const {
        'v': 1,
        'rooms': {
          '!dm:ourgalaxy.space': {'partner': '@friend:ourgalaxy.space'},
        },
      });

      expect(markers, {
        '!dm:ourgalaxy.space': '@friend:ourgalaxy.space',
      });
    });

    test('ignores malformed marker entries', () {
      final markers =
          MatrixDirectMessagesComponent.directRoomMarkersFromContent(const {
        'v': 1,
        'rooms': {
          '!valid:ourgalaxy.space': {'partner': '@friend:ourgalaxy.space'},
          '!missing-partner:ourgalaxy.space': {'other': '@friend:server'},
          '!bad-user:ourgalaxy.space': {'partner': 'friend'},
          '#alias:ourgalaxy.space': {'partner': '@friend:ourgalaxy.space'},
        },
      });

      expect(markers, {
        '!valid:ourgalaxy.space': '@friend:ourgalaxy.space',
      });
    });

    test('serializes markers into versioned account-data content', () {
      expect(
        MatrixDirectMessagesComponent.directRoomMarkersToContent(const {
          '!dm:ourgalaxy.space': '@friend:ourgalaxy.space',
          '#alias:ourgalaxy.space': '@ignored:ourgalaxy.space',
          '!bad-user:ourgalaxy.space': 'ignored',
        }),
        {
          'v': 1,
          'rooms': {
            '!dm:ourgalaxy.space': {
              'partner': '@friend:ourgalaxy.space',
            },
          },
        },
      );
    });
  });
}
