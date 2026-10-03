import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/matrix_timeline_rows.dart';

/// `M` is a Matrix row, `L` a local-only row (a pending media send).
bool Function(int) _rows(String shape) =>
    (row) => shape[row] == 'M';

/// `h` is a hidden SDK event, `v` a visible one.
bool Function(int) _matrix(String shape) =>
    (i) => shape[i] == 'h';

void main() {
  group('hiddenTimelineEventTypes', () {
    test('is exactly the MatrixRTC call membership', () {
      // A closed set: growing it hides events from every chat with nothing
      // on screen to say so. If this fails, the addition needs its own
      // decision, not a test edit.
      expect(hiddenTimelineEventTypes, {'org.matrix.msc3401.call.member'});
      expect(
        isHiddenTimelineEventType('org.matrix.msc3401.call.member'),
        isTrue,
      );
      expect(isHiddenTimelineEventType('m.room.message'), isFalse);
    });

    test('the history filter excludes the same set and keeps lazy members', () {
      final json = timelineRowFilter().toJson();
      expect(json['not_types'], ['org.matrix.msc3401.call.member']);
      expect(json['lazy_load_members'], isTrue);
    });
  });

  group('visibleMatrixEventsBefore', () {
    test('counts only the events that have rows', () {
      expect(
        visibleMatrixEventsBefore(
          matrixIndex: 5,
          matrixEventIsHidden: _matrix('vhhvhv'),
        ),
        2,
      );
      expect(
        visibleMatrixEventsBefore(
          matrixIndex: 0,
          matrixEventIsHidden: _matrix('vvv'),
        ),
        0,
      );
    });
  });

  group('rowOfMatrixRowNumber', () {
    test('skips local-only rows when counting', () {
      // Rows: L M L M M. Matrix row 0 is at 1, row 1 at 3, row 2 at 4.
      expect(
        rowOfMatrixRowNumber(
          matrixRowNumber: 1,
          rowCount: 5,
          rowIsMatrixEvent: _rows('LMLMM'),
        ),
        3,
      );
      expect(
        rowOfMatrixRowNumber(
          matrixRowNumber: 2,
          rowCount: 5,
          rowIsMatrixEvent: _rows('LMLMM'),
        ),
        4,
      );
    });

    test('is -1 past the last Matrix row', () {
      expect(
        rowOfMatrixRowNumber(
          matrixRowNumber: 3,
          rowCount: 5,
          rowIsMatrixEvent: _rows('LMLMM'),
        ),
        -1,
      );
    });
  });

  group('rowInsertIndexForMatrixRowNumber', () {
    test('a live event with nothing before it goes to the top', () {
      // Above a pending local send, which is where it landed before hidden
      // rows existed.
      expect(
        rowInsertIndexForMatrixRowNumber(
          matrixRowNumber: 0,
          rowCount: 3,
          rowIsMatrixEvent: _rows('LMM'),
        ),
        0,
      );
    });

    test('goes right after the preceding Matrix row, before local rows', () {
      // Rows: M L M. One Matrix row precedes -> slot 1, ahead of the local.
      expect(
        rowInsertIndexForMatrixRowNumber(
          matrixRowNumber: 1,
          rowCount: 3,
          rowIsMatrixEvent: _rows('MLM'),
        ),
        1,
      );
    });

    test('history appends at the end', () {
      expect(
        rowInsertIndexForMatrixRowNumber(
          matrixRowNumber: 2,
          rowCount: 2,
          rowIsMatrixEvent: _rows('MM'),
        ),
        2,
      );
    });

    test('hidden events do not shift the slot', () {
      // The SDK list after the insert is v h h NEW v: three events precede
      // the new one but only one of them has a row, so it belongs between the
      // two rows, at 1. Counting raw SDK events would have put it at the end.
      final before = visibleMatrixEventsBefore(
        matrixIndex: 3,
        matrixEventIsHidden: _matrix('vhhvv'),
      );
      expect(before, 1);
      expect(
        rowInsertIndexForMatrixRowNumber(
          matrixRowNumber: before,
          rowCount: 2,
          rowIsMatrixEvent: _rows('MM'),
        ),
        1,
      );
    });
  });
}
