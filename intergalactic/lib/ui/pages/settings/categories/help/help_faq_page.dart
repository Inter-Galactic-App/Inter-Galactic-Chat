import 'package:flutter/material.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/ui/pages/settings/settings_tab.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

enum FaqSection {
  general("General", Icons.help_outline_rounded),
  security("Security", Icons.shield_outlined),
  features("Features", Icons.auto_awesome_outlined);

  const FaqSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

class FaqEntry {
  const FaqEntry({
    required this.section,
    required this.question,
    required this.summary,
    required this.answer,
    this.keywords = const [],
  });

  final FaqSection section;
  final String question;
  final String summary;
  final List<String> answer;
  final List<String> keywords;
}

const List<FaqEntry> faqEntries = [
  FaqEntry(
    section: FaqSection.general,
    question: "What are rooms and spaces?",
    summary:
        "Rooms are chats or channels. Spaces group rooms together so communities stay organized.",
    answer: [
      "A room is a chat or channel. Rooms can be direct messages, group chats, forums, photo albums, calendars, voice rooms, or other Matrix room types.",
      "A space is a folder-like community area that can hold rooms. When you invite someone to a space, they can discover and join rooms made visible inside that space.",
      "Favorites are separate from spaces. Starred rooms appear together in the favorites area so important conversations stay easy to reach.",
    ],
    keywords: [
      "channels",
      "communities",
      "favorites",
      "folder",
      "server",
      "spaces",
    ],
  ),
  FaqEntry(
    section: FaqSection.general,
    question: "How do I set permissions for my room or space?",
    summary:
        "Open the room or space settings from its header and use Security, Admin, or Permissions.",
    answer: [
      "When you create a room or space, you are usually its admin. Open the room or space header, then open settings.",
      "Room and space permissions live in the contextual settings for that room or space. Use room Security for encryption, visibility, and room history. Use Admin Settings for identity, addresses, and room events. Use Permissions when you need power-level style member controls.",
      "Some controls only appear when your current Matrix power level allows you to change them.",
    ],
    keywords: [
      "admin",
      "moderation",
      "power level",
      "permissions",
      "security",
      "room settings",
      "space settings",
      "room history",
    ],
  ),
  FaqEntry(
    section: FaqSection.general,
    question: "How do I get help or report a problem?",
    summary:
        "Use Help & Safety for Matrix reports and Report a Bug for app diagnostics.",
    answer: [
      "Use Settings > Help & Safety for Matrix-native report and block controls. Those reports go through the selected Matrix homeserver.",
      "Use Settings > Report a Bug for app crashes, broken UI, notification problems, media bugs, or anything that needs Inter Galactic diagnostics.",
      "For app support, use intergalactic@ourgalaxy.space.",
    ],
    keywords: [
      "abuse",
      "bug",
      "diagnostics",
      "help",
      "report",
      "support",
    ],
  ),
  FaqEntry(
    section: FaqSection.general,
    question: "How do I replay the tutorial?",
    summary:
        "The guided tutorial is currently desktop-only and can be replayed from desktop settings.",
    answer: [
      "On desktop, open Settings > Tutorial and choose Replay tutorial.",
      "Mobile builds hide the tutorial page until the mobile tutorial path is ready.",
      "The desktop tutorial opens over local sample rooms without changing Matrix room state.",
    ],
    keywords: [
      "demo preview",
      "guide",
      "onboarding",
      "replay",
      "tour",
      "tutorial",
    ],
  ),
  FaqEntry(
    section: FaqSection.security,
    question: "How do I verify my session?",
    summary:
        "Use Settings > Security to verify a new device or session with emoji comparison.",
    answer: [
      "Session verification is an important part of end-to-end encryption. You can start verification from Settings > Security.",
      "The app will ask you to compare emoji or another verification method with an already trusted session.",
      "Each time you sign in on a new device or app, you may need to verify that session. If you are signed out everywhere, your recovery key may be the only way to regain access to encrypted history.",
    ],
    keywords: [
      "cross signing",
      "device",
      "emoji verification",
      "encrypted",
      "session",
      "verify",
    ],
  ),
  FaqEntry(
    section: FaqSection.security,
    question: "What is my recovery key?",
    summary:
        "Your recovery key helps recover encrypted history when no verified session is available.",
    answer: [
      "Your recovery key protects access to your encrypted message history. Keep it somewhere safe and private.",
      "If you sign in on a new session and cannot verify from another device, the recovery key may be needed to use your encryption backup.",
      "If you lose your recovery key and cannot verify from another session, you may lose access to older encrypted messages.",
    ],
    keywords: [
      "backup",
      "encrypted history",
      "key backup",
      "recovery",
      "security",
    ],
  ),
  FaqEntry(
    section: FaqSection.security,
    question: "I verified my account, but I still get decryption errors.",
    summary:
        "Run room or global decryption repair from the room lock control or Security settings.",
    answer: [
      "First open the affected room's side panel and look for the lock action. Running the room decrypt action can retry encrypted events in that room.",
      "You can also go to Settings > Security and run decryption repair for all rooms.",
      "If errors continue, the sender may not have shared the room keys with this session, or the sender's device may need verification or repair.",
    ],
    keywords: [
      "decrypt",
      "decryption",
      "e2ee",
      "encrypted",
      "lock",
      "missing session",
      "room keys",
    ],
  ),
  FaqEntry(
    section: FaqSection.security,
    question: "How do I clear an unverified session?",
    summary:
        "Use Settings > Security and remove the session you no longer trust or use.",
    answer: [
      "Go to Settings > Security and find the Sessions list.",
      "Use the delete action for the old or untrusted session. You may need to enter your account password, depending on the homeserver.",
      "Only remove sessions you recognize as old or unwanted. Removing the wrong session can interrupt that device's access.",
    ],
    keywords: [
      "delete device",
      "device",
      "session",
      "trash",
      "unverified",
    ],
  ),
  FaqEntry(
    section: FaqSection.security,
    question: "I can't see someone's messages.",
    summary:
        "This can be caused by encryption keys, blocked users, room history, or server-side moderation.",
    answer: [
      "In encrypted rooms, missing room keys are the most common cause. Try the room lock action or Settings > Security > Run Decryption.",
      "Also check whether the user is blocked or ignored, whether you joined after the messages were sent, or whether the homeserver removed or withheld content.",
      "If only one sender is affected, they may need to verify your session or repair their encrypted-message setup.",
    ],
    keywords: [
      "blocked",
      "can't see messages",
      "decryption",
      "ignored",
      "missing messages",
    ],
  ),
  FaqEntry(
    section: FaqSection.security,
    question: "Why can't people see message history?",
    summary:
        "Encrypted rooms usually only share readable history from after someone joins.",
    answer: [
      "In encrypted rooms, new members can usually read messages sent after they join. If the room uses Members (full history), admins may also share locally available encrypted history with newly invited eligible devices.",
      "When an admin invites someone to an encrypted room with full-history visibility, Inter Galactic tries to send an encrypted room-key bundle to devices allowed by the sender's current Matrix key-sharing policy. If a joined user lost keys later, an admin can use /sharehistory after that user re-requests encryption keys from an undecryptable message.",
      "Only share history when the room's privacy expectations allow it. Devices that are blocked or ineligible under the sender's key-sharing policy do not receive automatic history.",
    ],
    keywords: [
      "encrypted history",
      "history visibility",
      "message history",
      "sharehistory",
    ],
  ),
  FaqEntry(
    section: FaqSection.features,
    question: "Why can't I see images or emoticons?",
    summary:
        "Check media preview settings and make sure the relevant emoticon packs are enabled.",
    answer: [
      "For media previews, go to Settings > General and choose the preview level you want: none, private chats only, or all chats.",
      "For emoticons, go to Settings > Emoticons and check Customize Reactions, Favorite Packs, and Available Packs.",
      "Some image previews can still depend on the sender, room permissions, encryption state, and homeserver media access.",
    ],
    keywords: [
      "attachments",
      "emojis",
      "emoticons",
      "images",
      "media",
      "previews",
      "stickers",
    ],
  ),
  FaqEntry(
    section: FaqSection.features,
    question: "How do I get custom emoticons?",
    summary:
        "Use Settings > Emoticons to favorite available packs or manage your own.",
    answer: [
      "Go to Settings > Emoticons > Available Packs to see public packs from joined rooms and spaces. Use the favorite action to add a pack to your usable list.",
      "To make a pack available to people in a room or space, upload it through that room or space's emoticon settings when permissions allow it.",
      "You can also keep personal packs in your own Emoticons settings.",
    ],
    keywords: [
      "available packs",
      "custom emoji",
      "emote",
      "emoticons",
      "favorite packs",
      "packs",
      "stickers",
    ],
  ),
  FaqEntry(
    section: FaqSection.features,
    question: "How do I enable GIFs?",
    summary:
        "Turn on GIF search in General and add the required KLIPY key or relay details.",
    answer: [
      "Go to Settings > General and enable GIF search.",
      "GIF search requires a KLIPY API key or a relay address provided by your homeserver or deployment. The setup action on that setting explains what to enter.",
      "Disabling GIF search stops GIF lookup without changing normal image and sticker behavior.",
    ],
    keywords: [
      "gif",
      "gifs",
      "klipy",
      "media",
      "relay",
      "tenor",
    ],
  ),
  FaqEntry(
    section: FaqSection.features,
    question: "How do activity and presence features work?",
    summary:
        "Activity features show local media, Spotify, Steam, or status only when enabled.",
    answer: [
      "Activity and presence are opt-in. Go to Settings > Activity to connect or configure supported providers such as Spotify or Steam.",
      "When multiple activities are available, Inter Galactic can choose which activity view/card to show locally and publish according to the enabled privacy settings.",
      "If an activity does not clear after an app closes, disconnect and reconnect that provider from Activity settings.",
    ],
    keywords: [
      "activity",
      "game",
      "presence",
      "spotify",
      "steam",
      "status",
    ],
  ),
  FaqEntry(
    section: FaqSection.features,
    question: "How do voice, video, and screen sharing work?",
    summary:
        "Use Voice and Video settings for devices, volume, mic checks, camera tests, and screen-share quality.",
    answer: [
      "Go to Settings > Voice and Video to choose microphone, speaker, and camera devices.",
      "Use the mic check and camera test before joining a call when you need to confirm devices are working.",
      "Screen-share quality presets live on the same page. Developer diagnostics for calls are kept under Developer.",
    ],
    keywords: [
      "camera",
      "calls",
      "microphone",
      "screen share",
      "speaker",
      "video",
      "voice",
    ],
  ),
];

final List<SettingsSearchEntry> faqSearchEntries =
    List<SettingsSearchEntry>.unmodifiable([
  for (final entry in faqEntries)
    SettingsSearchEntry(
      title: entry.question,
      description: entry.summary,
      section: entry.section.label,
      keywords: entry.keywords,
    ),
]);

class HelpFaqPage extends StatelessWidget {
  const HelpFaqPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "FAQ",
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                "Quick answers for common Inter Galactic and Matrix questions.",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      height: 1.25,
                      letterSpacing: 0,
                    ),
              ),
              const SizedBox(height: 20),
              for (final section in FaqSection.values)
                SettingsSection(
                  title: section.label,
                  showDivider: section != FaqSection.values.last,
                  children: [
                    for (final entry in faqEntries)
                      if (entry.section == section) _FaqQuestionCard(entry),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FaqQuestionCard extends StatelessWidget {
  const _FaqQuestionCard(this.entry);

  final FaqEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showFaqAnswer(context, entry),
          child: Ink(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.36),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  entry.section.icon,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.question,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.summary,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          height: 1.25,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.open_in_new_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showFaqAnswer(BuildContext context, FaqEntry entry) {
  return showFaqAnswerDialog(context, entry);
}

Future<void> showFaqAnswerDialog(BuildContext context, FaqEntry entry) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: FaqAnswerCard(entry: entry),
        ),
      );
    },
  );
}

class FaqAnswerCard extends StatelessWidget {
  const FaqAnswerCard({
    required this.entry,
    this.showCloseButton = true,
    super.key,
  });

  final FaqEntry entry;
  final bool showCloseButton;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.45),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.scrim.withValues(alpha: 0.28),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  entry.section.icon,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    entry.question,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontSize: 18,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (var index = 0; index < entry.answer.length; index += 1)
              Padding(
                padding: EdgeInsets.only(
                  bottom: index == entry.answer.length - 1 ? 0 : 10,
                ),
                child: Text(
                  entry.answer[index],
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    height: 1.35,
                    letterSpacing: 0,
                  ),
                ),
              ),
            if (showCloseButton) ...[
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: tiamat.Button.secondary(
                  text: "Close",
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
