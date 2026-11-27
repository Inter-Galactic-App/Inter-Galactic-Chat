import 'package:flutter/material.dart';

bool shouldShowRoomMigrationNotice({
  required bool developerMode,
  required String? predecessorRoomId,
}) {
  return developerMode && predecessorRoomId != null;
}

/// A compact continuation marker shown at the start of a migrated room.
///
/// The room settings page also exposes the predecessor. Keeping this notice
/// in the chat makes the history boundary discoverable where people encounter
/// it, matching the behavior of other Matrix clients.
class RoomMigrationNotice extends StatelessWidget {
  const RoomMigrationNotice({required this.onOpenHistory, super.key});

  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: 'This room is a continuation of another conversation',
      child: Container(
        width: double.infinity,
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.chat_bubble_outline,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This room is a continuation of another conversation.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Semantics(
                    button: true,
                    label: 'See older messages',
                    child: InkWell(
                      onTap: onOpenHistory,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          'Click here to see older messages.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: scheme.primary),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
