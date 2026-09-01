import 'package:intergalactic/client/room.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';

class RoomNotificationsSettingsView extends StatelessWidget {
  const RoomNotificationsSettingsView({
    super.key,
    required this.pushRule,
    this.onPushRuleChanged,
    this.contextLabel = 'room',
  });

  final PushRule pushRule;
  final void Function(PushRule? rule)? onPushRuleChanged;
  final String contextLabel;

  String get labelRoomSettingsNotifications => Intl.message(
    "Notifications",
    desc: "Label for the notifications section in room settings",
    name: "labelRoomSettingsNotifications",
  );

  String get roomNotificationsIntro => Intl.message(
    "Choose how this room should notify you across your signed-in devices.",
    desc: "Intro text for room notification settings",
    name: "roomNotificationsIntro",
  );

  String get labelPushRuleNotifyAll => Intl.message(
    "All Messages",
    desc: "Label for the push rule which notifies for all received messages",
    name: "labelPushRuleNotifyAll",
  );

  String get labelPushRuleNotifyAllDescription => Intl.message(
    "Notify for every new message in this room.",
    desc: "Description for the all messages room notification rule",
    name: "labelPushRuleNotifyAllDescription",
  );

  String get labelPushRuleMentionsAndKeywords => Intl.message(
    "Mentions, Keywords, & @room",
    desc:
        "Label for the push rule which only notifies for mentions, keywords, and room-wide pings",
    name: "labelPushRuleMentionsAndKeywordsRoomNotifications",
  );

  String get labelPushRuleMentionsAndKeywordsDescription => Intl.message(
    "Silence routine room chatter while still notifying for direct tags, keyword matches, and @room mentions.",
    desc: "Description for the mentions only room notification rule",
    name: "labelPushRuleMentionsAndKeywordsDescription",
  );

  String get labelPushRuleNone => Intl.message(
    "Mute Everything",
    desc: "Label for the push rule which sends no notifications",
    name: "labelPushRuleNoneRoomNotifications",
  );

  String get labelPushRuleNoneDescription => Intl.message(
    "Silence every notification from this room, including direct tags and @room mentions.",
    desc: "Description for the fully muted room notification rule",
    name: "labelPushRuleNoneDescription",
  );

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: labelRoomSettingsNotifications,
      children: [
        SettingsControlRow(
          title: 'Notification mode',
          description: contextLabel == 'space'
              ? 'Choose how this space should notify you across your signed-in devices.'
              : roomNotificationsIntro,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final options = [
                _NotificationModeTile(
                  selected: pushRule == PushRule.notify,
                  icon: material.Icons.notifications_active_outlined,
                  title: labelPushRuleNotifyAll,
                  description: labelPushRuleNotifyAllDescription,
                  onTap: () => onPushRuleChanged?.call(PushRule.notify),
                ),
                _NotificationModeTile(
                  selected: pushRule == PushRule.mentionsOnly,
                  icon: material.Icons.alternate_email_outlined,
                  title: labelPushRuleMentionsAndKeywords,
                  description: labelPushRuleMentionsAndKeywordsDescription,
                  onTap: () => onPushRuleChanged?.call(PushRule.mentionsOnly),
                ),
                _NotificationModeTile(
                  selected: pushRule == PushRule.dontNotify,
                  icon: material.Icons.notifications_off_outlined,
                  title: labelPushRuleNone,
                  description: labelPushRuleNoneDescription,
                  onTap: () => onPushRuleChanged?.call(PushRule.dontNotify),
                ),
              ];

              if (constraints.maxWidth < 660) {
                return Column(
                  children: [
                    for (final option in options)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: option,
                      ),
                  ],
                );
              }

              return Row(
                children: [
                  for (final option in options) ...[
                    Expanded(child: option),
                    if (option != options.last) const SizedBox(width: 10),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _NotificationModeTile extends StatelessWidget {
  const _NotificationModeTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = material.Theme.of(context);
    final background = selected
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerLow;
    final foreground = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: title,
      hint: description,
      onTap: onTap,
      child: material.Material(
        color: background,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: material.InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 108),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline.withValues(alpha: 0.72),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: foreground),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: foreground,
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: selected
                        ? theme.colorScheme.onPrimaryContainer.withValues(
                            alpha: 0.82,
                          )
                        : theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.25,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
