import 'package:intergalactic/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:matrix/matrix.dart' as matrix;

/// Matrix event types that never become timeline rows.
///
/// `org.matrix.msc3401.call.member` is the MatrixRTC membership that every
/// participant republishes every 25 seconds for as long as a call runs. The
/// VoIP component reads it from room state and straight from sync
/// (`MatrixVoipRoomComponent.onSync`); nothing reads it from the timeline. As
/// a row it rendered as an empty `Container` and still cost a slot, a key and
/// an element - and in a call room it outnumbered messages about thirty to
/// one, so history pagination there fetched page after page of it, gained no
/// scroll extent, and showed nothing. See the 2026-08-21 call-room audit and
/// the `_maxUnproductiveHistoryLoads` breaker in `room_timeline_widget_view`,
/// which this turns into a safety net rather than the mechanism.
///
/// Closed set on purpose. Hiding here is invisible to the user, so a type
/// added casually silently disappears from every chat.
const Set<String> hiddenTimelineEventTypes = {
  MatrixVoipRoomComponent.callMemberStateEvent,
};

bool isHiddenTimelineEventType(String type) =>
    hiddenTimelineEventTypes.contains(type);

/// Asks the server to leave the hidden types out of a history or future page,
/// so a page of thirty is thirty messages rather than thirty memberships.
///
/// Only `/messages` honours this; events already in the local store from sync
/// still arrive and are skipped by the row mapping. `lazyLoadMembers` is what
/// the SDK sets on its own default filter.
matrix.StateFilter timelineRowFilter() => matrix.StateFilter(
  notTypes: hiddenTimelineEventTypes.toList(growable: false),
  lazyLoadMembers: true,
);

// The three functions below are the whole of the index mapping between the
// SDK's event list (every event, hidden ones included) and the app's row list
// (Matrix rows in the same order, interleaved with local-only rows such as a
// pending media send). They are pure so they can be tested without a client.
//
// The invariant they rely on: the app's Matrix rows are exactly the SDK's
// non-hidden events, in order. Every SDK insert, change and removal is
// mirrored through them, so the k-th non-hidden SDK event is the k-th Matrix
// row.

/// How many SDK events before [matrixIndex] have rows.
int visibleMatrixEventsBefore({
  required int matrixIndex,
  required bool Function(int matrixIndex) matrixEventIsHidden,
}) {
  var count = 0;
  for (var i = 0; i < matrixIndex; i++) {
    if (!matrixEventIsHidden(i)) {
      count++;
    }
  }
  return count;
}

/// Row of the [matrixRowNumber]-th (zero-based) Matrix row, or -1.
int rowOfMatrixRowNumber({
  required int matrixRowNumber,
  required int rowCount,
  required bool Function(int row) rowIsMatrixEvent,
}) {
  var seen = 0;
  for (var row = 0; row < rowCount; row++) {
    if (!rowIsMatrixEvent(row)) {
      continue;
    }
    if (seen == matrixRowNumber) {
      return row;
    }
    seen++;
  }
  return -1;
}

/// Where a new Matrix row goes when [matrixRowNumber] Matrix rows precede it.
///
/// Immediately after the last of those, and before any local-only rows that
/// follow it - except at the very top, where it goes first so a live message
/// lands above a still-uploading media send. That is the placement the
/// previous counting code produced, kept so nothing moves on screen.
int rowInsertIndexForMatrixRowNumber({
  required int matrixRowNumber,
  required int rowCount,
  required bool Function(int row) rowIsMatrixEvent,
}) {
  var seen = 0;
  for (var row = 0; row < rowCount; row++) {
    if (seen == matrixRowNumber) {
      return row;
    }
    if (rowIsMatrixEvent(row)) {
      seen++;
    }
  }
  return rowCount;
}
