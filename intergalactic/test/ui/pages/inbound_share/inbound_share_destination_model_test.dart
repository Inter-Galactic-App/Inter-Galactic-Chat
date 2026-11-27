import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/pages/inbound_share/inbound_share_destination_model.dart';

void main() {
  test('destinations sort by recent activity before unused rooms', () {
    final values = [
      _Candidate('Archive', 'personal'),
      _Candidate('Older', 'work', lastActivity: DateTime.utc(2026, 8, 1)),
      _Candidate('Zebra', 'personal'),
      _Candidate('Newest', 'personal', lastActivity: DateTime.utc(2026, 8, 3)),
    ];

    final sorted = InboundShareDestinations.sortByRecentActivity(
      values,
      lastActivity: (value) => value.lastActivity,
      roomName: (value) => value.room,
      accountLabel: (value) => value.account,
    );

    expect(sorted.map((value) => value.room), [
      'Newest',
      'Older',
      'Archive',
      'Zebra',
    ]);
  });
  test('search reaches account-labeled destinations beyond recents', () {
    const values = [
      _Candidate('Family', 'personal'),
      _Candidate('Roadmap', 'work'),
    ];
    final results = InboundShareDestinations.search(
      values,
      'work',
      (value, query) => value.matches(query),
    );
    expect(results.single.room, 'Roadmap');
  });
}

class _Candidate {
  const _Candidate(this.room, this.account, {this.lastActivity});
  final String room;
  final String account;
  final DateTime? lastActivity;
  bool matches(String query) =>
      room.toLowerCase().contains(query) ||
      account.toLowerCase().contains(query);
}
