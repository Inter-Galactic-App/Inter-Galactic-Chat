import 'package:flutter/material.dart';

class NotificationCompanionAvatarPreview extends StatelessWidget {
  const NotificationCompanionAvatarPreview({
    required this.notificationCount,
    this.assetVariant = 'app_icon_light_avatar',
    this.onTap,
    this.size = 120,
    super.key,
  });

  final int notificationCount;
  final String assetVariant;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hasNotifications = notificationCount > 0;

    return Semantics(
      button: onTap != null,
      label: hasNotifications
          ? 'Open latest companion notification'
          : 'Notification companion',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: Image.asset(
                  companionAvatarAssetPath(
                    assetVariant: assetVariant,
                    hasNotifications: hasNotifications,
                  ),
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
              if (hasNotifications)
                Positioned(
                  top: size * 0.35,
                  child: Text(
                    notificationCount > 99
                        ? '99+'
                        : notificationCount.toString(),
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.orangeAccent.shade400,
                      fontSize:
                          notificationCount > 99 ? size * 0.2 : size * 0.28,
                      fontWeight: FontWeight.w800,
                      height: 1,
                      shadows: const [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 3,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class NotificationCompanionBubblePreview extends StatelessWidget {
  const NotificationCompanionBubblePreview({
    required this.roomName,
    required this.senderName,
    required this.body,
    this.isDirectMessage = false,
    this.onTap,
    super.key,
  });

  final String roomName;
  final String senderName;
  final String body;
  final bool isDirectMessage;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final text = isDirectMessage ? body : '$senderName: $body';

    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withAlpha(244),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(34),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                roomName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 11,
                  height: 1.16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String companionAvatarAssetPath({
  required String assetVariant,
  required bool hasNotifications,
}) {
  final selected = switch (assetVariant) {
    'app_icon_dark_avatar' => 'app_icon_dark_avatar',
    _ => 'app_icon_light_avatar',
  };
  final assetName =
      hasNotifications ? selected.replaceFirst('_avatar', '_blank') : selected;
  return 'assets/images/notification_companion/$assetName.png';
}
