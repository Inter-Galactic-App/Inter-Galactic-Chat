import 'package:intergalactic/client/components/push_notification/modifiers/notification_modifiers.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/components/push_notification/notification_identity.dart';
import 'package:intergalactic/client/timeline_events/photo_stack_grouping.dart';
import 'package:intergalactic/debug/log.dart';

/// Collapses a burst of bare image uploads into a single notification.
///
/// Sending several photos at once produces one timeline event per photo, so
/// without this the recipient gets one notification per photo. The timeline
/// already folds that burst into a single stacked bubble
/// ([PhotoStackGrouping]); this lets the first photo of a stack through and
/// drops the rest of it.
///
/// The window is rolling — each photo is measured against the previous one in
/// the stack, not against the first — so a slow upload of twenty photos still
/// counts as one stack. [maxStackSpan] bounds that so a sender trickling photos
/// out over a long stretch eventually gets a fresh notification.
class NotificationModifierCoalescePhotoStack implements NotificationModifier {
  NotificationModifierCoalescePhotoStack({
    Duration? window,
    Duration? maxStackSpan,
    DateTime Function()? clock,
  }) : window = window ?? PhotoStackGrouping.window,
       maxStackSpan = maxStackSpan ?? const Duration(minutes: 10),
       _clock = clock ?? DateTime.now;

  /// Longest gap between two photos of the same stack.
  final Duration window;

  /// Longest a single stack may run before the next photo starts a new one.
  final Duration maxStackSpan;

  final DateTime Function() _clock;

  /// Rooms tracked at once. Bounded so a client in many active rooms cannot
  /// grow this without limit; the least recently touched room is dropped.
  static const int maxTrackedRooms = 64;

  final Map<String, _PhotoStackState> _stacks = {};

  @override
  Future<NotificationContent?> process(NotificationContent content) async {
    if (content is! MessageNotificationContent) {
      return content;
    }

    final key = NotificationIdentity.roomKeyForMessage(content);

    if (!content.isStackablePhoto) {
      // Anything else in the room ends the run of photos.
      _stacks.remove(key);
      return content;
    }

    final now = _clock();
    final existing = _stacks[key];

    if (existing != null && existing.continues(content, now, this)) {
      existing.add(content, now);
      Log.i(
        'Suppressing photo notification folded into an existing photo stack: '
        'photos=${existing.count}',
        category: LogCategory.notifications,
        source: 'photo-stack-coalescing',
      );
      return null;
    }

    _stacks.remove(key);
    _stacks[key] = _PhotoStackState(
      senderId: content.senderId,
      startedAt: now,
      lastAt: now,
    )..add(content, now);
    _evictOverflow();

    return content;
  }

  /// Forgets any stack tracked for a room, so the next photo notifies again.
  /// Called when the room's notifications are cleared, which happens once the
  /// user has actually seen the room.
  void reset({required String clientId, required String roomId}) {
    _stacks.remove(
      NotificationIdentity.roomKey(clientId: clientId, roomId: roomId),
    );
  }

  /// Forgets every tracked stack.
  void resetAll() {
    _stacks.clear();
  }

  void _evictOverflow() {
    while (_stacks.length > maxTrackedRooms) {
      _stacks.remove(_stacks.keys.first);
    }
  }
}

class _PhotoStackState {
  _PhotoStackState({
    required this.senderId,
    required this.startedAt,
    required this.lastAt,
  });

  final String senderId;
  final DateTime startedAt;
  final Set<String> _eventIds = {};
  DateTime lastAt;

  int get count => _eventIds.length;

  bool continues(
    MessageNotificationContent content,
    DateTime now,
    NotificationModifierCoalescePhotoStack owner,
  ) {
    if (content.senderId != senderId) {
      return false;
    }

    if (_eventIds.contains(content.eventId)) {
      // A photo already folded into this stack, delivered again. Re-suppress it
      // rather than surfacing the same photo twice.
      return true;
    }

    if (now.difference(lastAt).abs() > owner.window) {
      return false;
    }

    return now.difference(startedAt).abs() <= owner.maxStackSpan;
  }

  void add(MessageNotificationContent content, DateTime now) {
    _eventIds.add(content.eventId);
    lastAt = now;
  }
}
