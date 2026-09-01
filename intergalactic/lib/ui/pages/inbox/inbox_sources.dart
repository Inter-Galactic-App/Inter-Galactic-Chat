import 'dart:async';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/inbox/inbox_query.dart';

/// Shared source selection and change subscriptions for the Inbox surfaces.
///
/// `InboxPage` and `InboxTrigger` each carried their own copy of this. The
/// selection was identical, but the subscription sets were NOT: the trigger
/// never listened to `onSpaceUpdated`, so a space change refreshed the list
/// and left the badge stale. Keeping one definition is what stops the badge
/// and the list disagreeing about which rooms count.
///
/// This lives in the UI layer on purpose. `inbox_query.dart` knows nothing
/// about `ClientManager`, and that decoupling is worth more than putting every
/// Inbox helper in one file.
List<InboxRoomSource> inboxSourcesFor(
  ClientManager manager, {
  Client? filterClient,
}) {
  final sources = <InboxRoomSource>[];
  for (final room in manager.rooms) {
    if (filterClient != null && !identical(room.client, filterClient)) {
      continue;
    }
    if (room case final InboxRoomSource source) {
      sources.add(source);
    }
  }
  return sources;
}

/// Every manager event that can change which rooms belong in the Inbox.
///
/// Callers own cancellation. Listeners that are about masking rather than
/// membership - the DM lock, for one - stay at the call site, because only
/// some surfaces care about them.
List<StreamSubscription<dynamic>> subscribeToInboxSourceChanges(
  ClientManager manager,
  void Function() onChanged,
) => <StreamSubscription<dynamic>>[
  manager.onRoomAdded.listen((_) => onChanged()),
  manager.onRoomRemoved.listen((_) => onChanged()),
  manager.onClientAdded.stream.listen((_) => onChanged()),
  manager.onClientRemoved.stream.listen((_) => onChanged()),
  manager.onSpaceAdded.listen((_) => onChanged()),
  manager.onSpaceRemoved.listen((_) => onChanged()),
  manager.onSpaceUpdated.stream.listen((_) => onChanged()),
];
