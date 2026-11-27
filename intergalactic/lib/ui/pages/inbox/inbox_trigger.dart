import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/inbox/inbox_query.dart';
import 'package:intergalactic/ui/atoms/notification_badge.dart';
import 'package:intergalactic/ui/pages/inbox/inbox_sources.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// User-panel Inbox entry with a conversation-count badge.
///
/// It owns its source lifecycle so the badge follows the same visible-unread
/// semantics as the Inbox page without coupling the main shell to Matrix data.
class InboxTrigger extends StatefulWidget {
  const InboxTrigger({
    required this.clientManager,
    required this.onPressed,
    this.filterClient,
    this.size = 50,
    this.iconSize,
    this.badgeSize,
    super.key,
  });

  final ClientManager clientManager;
  final Client? filterClient;
  final VoidCallback onPressed;
  final double size;

  /// Defaults to the full rail's `size / 4`. The compact rail's buttons are
  /// 38px with 15px glyphs, a ratio the default would render at 9.5px - visibly
  /// smaller than every button beside it.
  final double? iconSize;

  /// Defaults to 18. Scaled down with the button so the badge does not swallow
  /// a compact-rail glyph.
  final double? badgeSize;

  @override
  State<InboxTrigger> createState() => _InboxTriggerState();
}

class _InboxTriggerState extends State<InboxTrigger> {
  late final InboxStateController _controller;
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _controller = InboxStateController();
    _subscribe();
    unawaited(_setSources());
  }

  @override
  void didUpdateWidget(covariant InboxTrigger oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.clientManager, widget.clientManager) ||
        !identical(oldWidget.filterClient, widget.filterClient)) {
      _cancelSubscriptions();
      _subscribe();
      unawaited(_setSources());
    }
  }

  void _subscribe() {
    // This set used to omit onSpaceUpdated, which InboxPage listened to - so a
    // space change refreshed the list and left this badge stale.
    _subscriptions.addAll(
      subscribeToInboxSourceChanges(
        widget.clientManager,
        () => unawaited(_setSources()),
      ),
    );
  }

  Future<void> _setSources() => _controller.setSources(
    inboxSourcesFor(widget.clientManager, filterClient: widget.filterClient),
  );

  void _cancelSubscriptions() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  @override
  void dispose() {
    _cancelSubscriptions();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<InboxState>(
      valueListenable: _controller,
      builder: (context, state, _) {
        final count = state.badgeCount;
        final semanticCount = count == 0
            ? 'No unread Inbox conversations'
            : count == 1
            ? '1 unread Inbox conversation'
            : '$count unread Inbox conversations';
        return Semantics(
          button: true,
          label: 'Inbox, $semanticCount',
          child: tiamat.Tooltip(
            text: count == 0 ? 'Inbox' : 'Inbox, $semanticCount',
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: tiamat.IconButton(
                      icon: Icons.inbox_outlined,
                      size: widget.iconSize ?? widget.size / 4,
                      onPressed: widget.onPressed,
                    ),
                  ),
                  if (count > 0)
                    Positioned(
                      top: 2,
                      right: 1,
                      child: ExcludeSemantics(
                        child: NotificationBadge(
                          count,
                          size: widget.badgeSize ?? 18,
                          maxDisplayCount: 99,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
