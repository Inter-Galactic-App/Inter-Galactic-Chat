import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/push_notification/android/embedded_ntfy_notifier.dart';
import 'package:intergalactic/client/components/push_notification/android/firebase_push_notifier.dart';
import 'package:intergalactic/client/components/push_notification/android/unified_push_notifier.dart';
import 'package:intergalactic/client/components/push_notification/ios/ios_notifier.dart';
import 'package:intergalactic/client/components/push_notification/macos/macos_notifier.dart';
import 'package:intergalactic/client/components/push_notification/notification_manager.dart';
import 'package:intergalactic/client/components/push_notification/notifier.dart';
import 'package:intergalactic/client/components/push_notification/push_notification_component.dart';
import 'package:intergalactic/client/components/push_notification/room_notification_snooze.dart';
import 'package:intergalactic/client/components/push_notification/web/web_push_notifier.dart';
import 'package:intergalactic/client/components/stories/story_component.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/config/preferences/string_preference.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/boolean_toggle.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/double_preference_slider.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/notification_settings/embedded_push_setup_view.dart';
import 'package:intergalactic/client/components/push_notification/notification_mode_policy.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/notification_settings/notification_preview_privacy_choice.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/notification_settings/notifier_debug_view.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/settings_category_room.dart';
import 'package:intergalactic/ui/pages/settings/categories/space/settings_category_space.dart';
import 'package:intergalactic/ui/pages/settings/room_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/settings_compact_action_button.dart';
import 'package:intergalactic/ui/pages/settings/settings_navigation.dart';
import 'package:intergalactic/ui/pages/settings/settings_account_scope.dart';
import 'package:intergalactic/ui/pages/settings/space_settings_page.dart';
import 'package:intergalactic/ui/pages/setup/menus/unified_push_setup.dart';
import 'package:intergalactic/utils/error_utils.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:intergalactic/utils/custom_sound_manager.dart';
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  Notifier? notifier;
  StreamSubscription? _preferencesSub;
  bool isWebPushLoading = false;
  bool isIosPushLoading = false;
  bool isMacosNotificationsLoading = false;
  bool isPickingNotificationSound = false;
  bool isPickingRingtoneSound = false;

  String get notificationSettingsNotSupported => Intl.message(
    "Push notifications are not supported on this system",
    name: "notificationSettingsNotSupported",
    desc: "Message to display when push notifications are not supported",
  );

  WebPushNotifier? get webPushNotifier =>
      notifier is WebPushNotifier ? notifier as WebPushNotifier : null;

  IosNotifier? get iosNotifier =>
      notifier is IosNotifier ? notifier as IosNotifier : null;

  MacosNotifier? get macosNotifier =>
      notifier is MacosNotifier ? notifier as MacosNotifier : null;

  String get webPushButtonText {
    final webNotifier = webPushNotifier;
    if (webNotifier == null) {
      return "Enable Browser Push";
    }

    if (webNotifier.permissionState == "granted" &&
        webNotifier.subscription != null) {
      return "Refresh Push Subscription";
    }

    if (webNotifier.permissionState == "granted") {
      return "Create Push Subscription";
    }

    return "Enable Browser Push";
  }

  @override
  void initState() {
    super.initState();
    notifier = NotificationManager.notifier;
    unawaited(preferences.pruneExpiredRoomNotificationSnoozes());
    _preferencesSub = preferences.onSettingChanged.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _preferencesSub?.cancel();
    super.dispose();
  }

  bool get canConfigureNotifications =>
      PlatformUtils.isAndroid ||
      PlatformUtils.isIOS ||
      PlatformUtils.isMacOS ||
      PlatformUtils.isLinux ||
      PlatformUtils.isWindows ||
      PlatformUtils.isWeb;

  bool get supportsCustomSoundFiles =>
      PlatformUtils.isLinux || PlatformUtils.isMacOS || PlatformUtils.isWindows;

  bool get supportsDesktopNotificationOptions =>
      PlatformUtils.isLinux || PlatformUtils.isMacOS || PlatformUtils.isWindows;

  @override
  Widget build(BuildContext context) {
    if (!canConfigureNotifications) {
      return SettingsSection(
        title: 'Notifications',
        showDivider: false,
        children: [
          SettingsControlRow(
            title: 'Not supported',
            description: notificationSettingsNotSupported,
          ),
        ],
      );
    }

    final manager = _providedClientManager(context) ?? clientManager;
    final selectedClient = manager == null
        ? null
        : SettingsAccountScope.selectedClientOf(context, manager);
    final overrides = collectNotificationOverrides(
      manager,
      client: selectedClient,
    );
    final snoozedRooms = collectRoomNotificationSnoozes(
      manager,
      client: selectedClient,
    );
    final storyAccounts = collectStoryNotificationAccounts(
      manager,
      client: selectedClient,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Notifications',
          children: [
            _NotificationModeControl(
              value: _currentNotificationMode(selectedClient),
              onChanged: (mode) => _setNotificationMode(selectedClient, mode),
            ),
            if (PlatformUtils.isAndroid)
              BooleanPreferenceToggle(
                preference: preferences.silenceNotifications,
                title: "Silence notifications when active elsewhere",
                description:
                    "When another device or client is active, silence notifications on this device.",
              ),
            if (supportsDesktopNotificationOptions)
              BooleanPreferenceToggle(
                preference: preferences.suppressNotificationWhenRoomFocused,
                title: "Hide notifications for current room",
                description:
                    "When you already have the selected chat open and focused, suppress duplicate alerts.",
              ),
            if (PlatformUtils.isWeb) buildWebNotificationSettings(),
            if (PlatformUtils.isIOS) buildIosNotificationSettings(),
            if (PlatformUtils.isMacOS) buildMacosNotificationSettings(),
          ],
        ),
        SettingsSection(
          title: 'Notification previews',
          children: [
            SettingsControlRow(
              title: 'Preview privacy',
              description:
                  'Choose how much message detail notifications can show on this device.',
              child: NotificationPreviewPrivacyChoice(
                onChanged: (_) {
                  if (mounted) {
                    setState(() {});
                  }
                },
              ),
            ),
            // Mobile-only, and deliberately NOT the desktop Appearance section.
            //
            // `showMediaInNotifications` is already honoured on iOS - the NSE
            // policy snapshot reads it and emits `show_media` - but the toggle
            // that sets it lived inside a section gated to desktop, so on a
            // phone the preference was live and unreachable. The only way to
            // stop image previews was the Private preset, which also removes
            // the message text. IOS request, 2026-09-03: keep text previews,
            // drop image previews.
            //
            // It is standalone here rather than nested under
            // `formatNotificationBody` the way desktop nests it. That nesting
            // is a desktop convention - rich body formatting implies rich
            // media - and body formatting is not exposed on mobile, so
            // inheriting the dependency would grey this control out with
            // nothing on screen explaining why.
            if (!supportsDesktopNotificationOptions)
              BooleanPreferenceToggle(
                preference: preferences.showMediaInNotifications,
                title: "Show images in notifications",
                description:
                    "Turn this off to keep message text in notifications but "
                    "hide image previews. Media Preview settings still apply.",
                onChanged: (_) => _markNotificationPreviewCustom(),
              ),
          ],
        ),
        if (storyAccounts.isNotEmpty)
          SettingsSection(
            title: 'Stories',
            children: [
              SettingsControlRow(
                title: 'Story notifications',
                description:
                    'Choose which story activity can create Inter Galactic story alerts. This does not change Matrix push rules or room unread counts.',
                child: Column(
                  children: [
                    for (final account in storyAccounts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _StoryNotificationAccountCard(
                          account: account,
                          onChanged: () {
                            if (mounted) {
                              setState(() {});
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        SettingsSection(
          title: 'Snoozed Chats',
          children: [
            SettingsControlRow(
              title: 'Temporary snoozes',
              description: snoozedRooms.isEmpty
                  ? 'No chats are snoozed on this device right now.'
                  : 'These local snoozes suppress Inter Galactic room notifications on this device until they expire.',
              child: snoozedRooms.isEmpty
                  ? null
                  : Column(
                      children: [
                        for (final summary in snoozedRooms)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _RoomNotificationSnoozeCard(
                              summary: summary,
                              onChanged: () {
                                if (mounted) {
                                  setState(() {});
                                }
                              },
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
        if (supportsDesktopNotificationOptions)
          SettingsSection(
            title: 'Appearance',
            children: [
              BooleanPreferenceToggle(
                preference: preferences.formatNotificationBody,
                title: "Message body formatting",
                description: "Apply user formatting in message notifications.",
                onChanged: (_) => _markNotificationPreviewCustom(),
              ),
              AnimatedOpacity(
                opacity: preferences.formatNotificationBody.value ? 1 : 0.3,
                duration: Durations.short4,
                child: IgnorePointer(
                  ignoring: preferences.formatNotificationBody.value == false,
                  child: Column(
                    children: [
                      BooleanPreferenceToggle(
                        preference: preferences.showMediaInNotifications,
                        title: "Show images",
                        description:
                            "Show images in notifications when allowed by General > Media Preview.",
                        onChanged: (_) => _markNotificationPreviewCustom(),
                      ),
                      BooleanPreferenceToggle(
                        preference: preferences.previewUrlInNotifications,
                        title: "Preview URLs",
                        description:
                            "Fetch URL previews to show extra link information in notifications.",
                        onChanged: (_) => _markNotificationPreviewCustom(),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        if (supportsDesktopNotificationOptions || supportsCustomSoundFiles)
          SettingsSection(
            title: 'Sounds',
            children: [
              if (supportsDesktopNotificationOptions)
                DoublePreferenceSlider(
                  preference: preferences.notificationsVolume,
                  min: 0,
                  max: 150,
                  numDecimals: 0,
                  units: "%",
                  title: "Notification volume",
                  description:
                      "Controls the volume of notifications and ringtones.",
                  onChanged: (p0) {
                    final player = NotificationManager.getSoundPlayer();
                    player.setVolume(p0);
                    player.open(
                      Media(CustomSoundManager.notificationSoundUri()),
                    );
                  },
                ),
              if (supportsCustomSoundFiles) ...[
                SettingsControlRow(
                  title: "Notification sound",
                  description:
                      "Choose the sound used for new message notifications on this device.",
                  child: _NotificationSoundPickerRow(
                    currentValueLabel:
                        CustomSoundManager.notificationSoundLabel(),
                    isBusy: isPickingNotificationSound,
                    onChoose: () =>
                        pickCustomSound(CustomSoundSlot.notification),
                    onPreview: () =>
                        previewCustomSound(CustomSoundSlot.notification),
                    onReset: () =>
                        resetCustomSound(CustomSoundSlot.notification),
                  ),
                ),
                SettingsControlRow(
                  title: "Ringtone",
                  description:
                      "Choose the ringtone used when calls come in or while you are dialing.",
                  child: _NotificationSoundPickerRow(
                    currentValueLabel: CustomSoundManager.ringtoneSoundLabel(),
                    isBusy: isPickingRingtoneSound,
                    onChoose: () => pickCustomSound(CustomSoundSlot.ringtone),
                    onPreview: () =>
                        previewCustomSound(CustomSoundSlot.ringtone),
                    onReset: () => resetCustomSound(CustomSoundSlot.ringtone),
                  ),
                ),
              ],
            ],
          ),
        SettingsSection(
          title: 'Overrides',
          showDivider: false,
          children: [
            SettingsControlRow(
              title: 'Room and space overrides',
              description: overrides.isEmpty
                  ? 'No room or space notification overrides are set for signed-in accounts.'
                  : 'Open the matching room or space settings to review or change each override.',
              child: overrides.isEmpty
                  ? null
                  : Column(
                      children: [
                        for (final override in overrides)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _NotificationOverrideCard(summary: override),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ],
    );
  }

  NotificationMode _currentNotificationMode(Client? selectedClient) {
    final isMigrated =
        selectedClient is MatrixClient &&
        preferences.isGlobalMutePushRuleMigrated(selectedClient.identifier);

    return resolveNotificationMode(
      isMigrated: isMigrated,
      serverMuted:
          isMigrated &&
          selectedClient.getMatrixClient().allPushNotificationsMuted,
      enableNotifications: preferences.enableNotifications.value,
      localModeValue: preferences.notificationMode.value,
    );
  }

  Future<void> _setNotificationMode(
    Client? selectedClient,
    NotificationMode mode,
  ) async {
    if (selectedClient is MatrixClient) {
      final result = await applyMatrixNotificationMode(
        mode: mode,
        clientIdentifier: selectedClient.identifier,
        setMuted: selectedClient.getMatrixClient().setMuteAllPushNotifications,
        preferences: preferences,
      );
      if (result == NotificationModeWriteResult.failed) {
        if (mounted) {
          // Non-modal: a mute the server did not accept needs showing, not
          // acknowledging. This draws because the settings route now carries
          // a Scaffold for the ScaffoldMessenger to present into.
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text('Could not update the server notification policy.'),
            ),
          );
        }
        return;
      }
    }

    if (selectedClient is! MatrixClient) {
      // Legacy, pre-migration path only. A Matrix account has already had both
      // preferences written by applyMatrixNotificationMode, against the server
      // rule it just accepted.
      await preferences.notificationMode.set(mode.preferenceValue);
      await preferences.enableNotifications.set(mode != NotificationMode.mute);
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _markNotificationPreviewCustom() async {
    if (preferences.notificationPreviewPrivacyChoiceValue.value ==
        Preferences.notificationPreviewPrivacyChoiceCustom) {
      return;
    }

    await preferences.applyNotificationPreviewPrivacyChoice(
      Preferences.notificationPreviewPrivacyChoiceCustom,
    );
    if (mounted) {
      setState(() {});
    }
  }

  Widget buildIosNotificationSettings() {
    final notifier = iosNotifier;
    final permissionLabel = notifier?.permissionStatus ?? "unknown";
    final permissionDescription = switch (permissionLabel) {
      "authorized" => "Allowed",
      "provisional" => "Allowed quietly",
      "ephemeral" => "Temporarily allowed",
      "denied" => "Denied",
      "not_determined" => "Not requested yet",
      _ => permissionLabel,
    };
    final tokenReady = notifier?.hasRemoteToken == true;

    return SettingsControlRow(
      title: 'iPhone push permission',
      description:
          'Grant notification permission to receive Matrix push notifications on this iPhone.',
      child: _StatusActionCard(
        buttonLabel:
            permissionLabel == "authorized" || permissionLabel == "provisional"
            ? "Refresh iPhone Notifications"
            : "Enable iPhone Notifications",
        isLoading: isIosPushLoading,
        onPressed: notifier == null ? null : onIosPushRequested,
        lines: [
          "Permission: $permissionDescription",
          tokenReady
              ? "Device is registered for push notifications."
              : "Device is not registered yet.",
        ],
      ),
    );
  }

  Widget buildWebNotificationSettings() {
    final webNotifier = webPushNotifier;
    final supported = webNotifier?.isSupported ?? false;
    final endpoint = webNotifier?.subscription?.endpoint;
    final error = webNotifier?.lastError;

    return SettingsControlRow(
      title: 'Browser push permission',
      description: supported
          ? 'Enable push notifications for this browser or Home Screen app.'
          : notificationSettingsNotSupported,
      child: _StatusActionCard(
        buttonLabel: webPushButtonText,
        isLoading: isWebPushLoading,
        onPressed: supported ? onWebPushRequested : null,
        lines: [
          "Permission: ${webNotifier?.permissionState ?? "unknown"}",
          if (endpoint != null) "Endpoint: $endpoint",
          if (error != null) "Last error: $error",
        ],
      ),
    );
  }

  Widget buildMacosNotificationSettings() {
    final notifier = macosNotifier;
    final permissionLabel = notifier?.permissionStatus ?? "unknown";
    final permissionDescription = switch (permissionLabel) {
      "authorized" => "Allowed",
      "provisional" => "Allowed quietly",
      "denied_or_not_requested" => "Denied or not requested yet",
      "unavailable" => "Unavailable",
      _ => permissionLabel,
    };

    return SettingsControlRow(
      title: 'Mac notification permission',
      description:
          'Grant local notification permission for this Mac. This does not register a Matrix push pusher.',
      child: _StatusActionCard(
        buttonLabel:
            permissionLabel == "authorized" || permissionLabel == "provisional"
            ? "Refresh Mac Notifications"
            : "Enable Mac Notifications",
        isLoading: isMacosNotificationsLoading,
        onPressed: notifier == null ? null : onMacosNotificationsRequested,
        lines: [
          "Permission: $permissionDescription",
          "Delivery: local macOS notifications",
        ],
      ),
    );
  }

  Future<void> onWebPushRequested() async {
    final webNotifier = this.webPushNotifier;
    if (webNotifier == null) {
      return;
    }

    setState(() {
      isWebPushLoading = true;
    });

    try {
      await webNotifier.requestPermission();
      await PushNotificationComponent.updateAllPushers();
    } finally {
      if (mounted) {
        setState(() {
          isWebPushLoading = false;
        });
      }
    }
  }

  Future<void> onIosPushRequested() async {
    final iosNotifier = this.iosNotifier;
    if (iosNotifier == null) {
      return;
    }

    setState(() {
      isIosPushLoading = true;
    });

    try {
      await iosNotifier.requestPermission();
    } finally {
      if (mounted) {
        setState(() {
          isIosPushLoading = false;
        });
      }
    }
  }

  Future<void> onMacosNotificationsRequested() async {
    final macosNotifier = this.macosNotifier;
    if (macosNotifier == null) {
      return;
    }

    setState(() {
      isMacosNotificationsLoading = true;
    });

    try {
      await macosNotifier.requestPermission();
    } finally {
      if (mounted) {
        setState(() {
          isMacosNotificationsLoading = false;
        });
      }
    }
  }

  Future<void> pickCustomSound(CustomSoundSlot slot) async {
    _setSoundPickerLoading(slot, true);

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: CustomSoundManager.allowedExtensions,
        dialogTitle: switch (slot) {
          CustomSoundSlot.notification => 'Pick notification sound',
          CustomSoundSlot.ringtone => 'Pick ringtone',
        },
      );

      final file = result == null || result.files.isEmpty
          ? null
          : result.files.first;
      if (file?.path == null) {
        return;
      }

      final preference = _soundPreference(slot);
      final previousPath = preference.value;
      final importedPath = await CustomSoundManager.importCustomSound(
        file!.path!,
        slot: slot,
      );
      await preference.set(importedPath);
      if (previousPath != importedPath) {
        await CustomSoundManager.deleteImportedSound(previousPath);
      }

      if (mounted) {
        setState(() {});
      }
    } finally {
      _setSoundPickerLoading(slot, false);
    }
  }

  Future<void> resetCustomSound(CustomSoundSlot slot) async {
    final preference = _soundPreference(slot);
    final previousPath = preference.value;
    await preference.set(null);
    await CustomSoundManager.deleteImportedSound(previousPath);

    if (mounted) {
      setState(() {});
    }
  }

  void previewCustomSound(CustomSoundSlot slot) {
    final player = NotificationManager.getSoundPlayer();
    player.setVolume(preferences.notificationsVolume.value);
    player.setPlaylistMode(PlaylistMode.none);
    player.open(
      Media(switch (slot) {
        CustomSoundSlot.notification =>
          CustomSoundManager.notificationSoundUri(),
        CustomSoundSlot.ringtone => CustomSoundManager.ringtoneSoundUri(),
      }),
    );
  }

  void _setSoundPickerLoading(CustomSoundSlot slot, bool value) {
    if (!mounted) {
      return;
    }

    setState(() {
      switch (slot) {
        case CustomSoundSlot.notification:
          isPickingNotificationSound = value;
          break;
        case CustomSoundSlot.ringtone:
          isPickingRingtoneSound = value;
          break;
      }
    });
  }

  NullableStringPreference _soundPreference(CustomSoundSlot slot) {
    return switch (slot) {
      CustomSoundSlot.notification => preferences.customNotificationSoundPath,
      CustomSoundSlot.ringtone => preferences.customRingtoneSoundPath,
    };
  }
}

@visibleForTesting
List<RoomNotificationSnoozeSummary> collectRoomNotificationSnoozes(
  ClientManager? manager, {
  Client? client,
}) {
  final summaries = <RoomNotificationSnoozeSummary>[];
  final seen = <String>{};
  final clients = client == null
      ? manager?.clients ?? const <Client>[]
      : <Client>[client];

  for (final currentClient in clients) {
    for (final room in currentClient.rooms) {
      final snooze = room.notificationSnooze;
      if (snooze == null) {
        continue;
      }
      summaries.add(RoomNotificationSnoozeSummary(room: room, snooze: snooze));
      seen.add(
        roomNotificationSnoozeKey(
          clientId: snooze.clientId,
          roomId: snooze.roomId,
        ),
      );
    }
  }

  // Pending legacy actions are retained only until the next Matrix sync moves
  // them into the per-room account-data record.
  for (final snooze in preferences.getRoomNotificationSnoozes().values) {
    if (client != null && snooze.clientId != client.identifier) {
      continue;
    }
    final key = roomNotificationSnoozeKey(
      clientId: snooze.clientId,
      roomId: snooze.roomId,
    );
    if (seen.contains(key)) {
      continue;
    }
    summaries.add(
      RoomNotificationSnoozeSummary(
        room:
            client?.getRoom(snooze.roomId) ??
            _findRoomForSnooze(manager, snooze),
        snooze: snooze,
      ),
    );
  }

  summaries.sort(
    (left, right) =>
        left.snooze.snoozedUntil.compareTo(right.snooze.snoozedUntil),
  );
  return summaries;
}

Room? _findRoomForSnooze(
  ClientManager? manager,
  RoomNotificationSnooze snooze,
) {
  if (manager == null) {
    return null;
  }

  final client = manager.getClient(snooze.clientId);
  return client?.getRoom(snooze.roomId);
}

class RoomNotificationSnoozeSummary {
  const RoomNotificationSnoozeSummary({
    required this.room,
    required this.snooze,
  });

  final Room? room;
  final RoomNotificationSnooze snooze;

  String get displayName => room?.displayName ?? 'Unknown chat';

  String get detail {
    final roomLabel = room == null ? 'Chat is not currently loaded' : 'Local';
    return '$roomLabel snooze';
  }
}

class _RoomNotificationSnoozeCard extends StatelessWidget {
  const _RoomNotificationSnoozeCard({
    required this.summary,
    required this.onChanged,
  });

  final RoomNotificationSnoozeSummary summary;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final until = DateFormat.MMMd().add_jm().format(
      summary.snooze.snoozedUntil,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.42),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              summary.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${summary.detail} until $until - '
              '${formatRoomNotificationSnoozeRemaining(summary.snooze)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 12),
            _SnoozeDurationButtonWrap(
              onSelected: (option) => unawaited(_setSnooze(context, option)),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: SettingsCompactActionButton(
                label: 'Unsnooze',
                onTap: () => unawaited(_clearSnooze(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Both mutations reach the network once a room is loaded: setNotificationSnooze
  // writes a push rule and per-room account data. Their callers invoke them
  // through `unawaited`, so an uncaught failure here is an unhandled async error
  // that the user never sees - they would tap Snooze, see nothing change, and
  // get no explanation. ErrorUtils.tryRun surfaces it and keeps the failure
  // inside the button press.
  Future<void> _setSnooze(
    BuildContext context,
    RoomNotificationSnoozeDurationOption option,
  ) async {
    var changed = false;
    await ErrorUtils.tryRun(context, () async {
      final room = summary.room;
      if (room == null) {
        await preferences.setRoomNotificationSnooze(
          clientId: summary.snooze.clientId,
          roomId: summary.snooze.roomId,
          duration: option.duration,
          source: 'app_settings_pending_sync',
        );
      } else {
        await room.setNotificationSnooze(
          option.duration,
          source: 'app_settings',
        );
      }
      await NotificationManager.clearNotificationsByRoute(
        clientId: summary.snooze.clientId,
        roomId: summary.snooze.roomId,
      );
      changed = true;
    });

    // Only after the whole operation succeeded: refreshing on a failed write
    // would redraw the row as though the change had taken.
    if (changed) {
      onChanged();
    }
  }

  Future<void> _clearSnooze(BuildContext context) async {
    var changed = false;
    await ErrorUtils.tryRun(context, () async {
      final room = summary.room;
      if (room == null) {
        await preferences.clearRoomNotificationSnooze(
          clientId: summary.snooze.clientId,
          roomId: summary.snooze.roomId,
        );
      } else {
        await room.clearNotificationSnooze();
      }
      changed = true;
    });

    if (changed) {
      onChanged();
    }
  }
}

class _SnoozeDurationButtonWrap extends StatelessWidget {
  const _SnoozeDurationButtonWrap({required this.onSelected});

  final ValueChanged<RoomNotificationSnoozeDurationOption> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in RoomNotificationSnoozeDurationOption.values)
          SettingsCompactActionButton(
            label: option.compactLabel,
            semanticLabel: 'Snooze ${option.label}',
            onTap: () => onSelected(option),
          ),
      ],
    );
  }
}

@visibleForTesting
List<StoryNotificationAccountSummary> collectStoryNotificationAccounts(
  ClientManager? manager, {
  Client? client,
}) {
  if (manager == null && client == null) {
    return const [];
  }

  final clients = client == null ? manager!.clients : <Client>[client];

  return [
    for (final currentClient in clients)
      if (currentClient.getComponent<StoryComponent>() != null)
        StoryNotificationAccountSummary(
          client: currentClient,
          component: currentClient.getComponent<StoryComponent>()!,
        ),
  ];
}

class StoryNotificationAccountSummary {
  const StoryNotificationAccountSummary({
    required this.client,
    required this.component,
  });

  final Client client;
  final StoryComponent component;

  String get displayName {
    final self = client.self;
    if (self != null && self.displayName.trim().isNotEmpty) {
      return self.displayName;
    }
    if (self != null && self.userName.trim().isNotEmpty) {
      return self.userName;
    }
    return client.identifier;
  }

  String get detail => client.self?.identifier ?? client.identifier;
}

class _StoryNotificationAccountCard extends StatelessWidget {
  const _StoryNotificationAccountCard({
    required this.account,
    required this.onChanged,
  });

  final StoryNotificationAccountSummary account;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = account.component.notificationSettings;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.42),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              account.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              account.detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 12),
            _StoryNotificationModeRow(
              title: 'Someone posts a story',
              description:
                  'Controls app-side story-post alerts while Inter Galactic is running or processing sync.',
              value: settings.storyPosts,
              onChanged: (mode) async =>
                  _update(context, settings.copyWith(storyPosts: mode)),
            ),
            const SizedBox(height: 10),
            _StoryNotificationModeRow(
              title: 'Someone reacts to my story',
              description:
                  'Controls app-side reaction alerts for your active stories.',
              value: settings.storyReactions,
              onChanged: (mode) async =>
                  _update(context, settings.copyWith(storyReactions: mode)),
            ),
            const SizedBox(height: 10),
            _StoryNotificationSoundRow(
              value: settings.sound,
              onChanged: (value) async =>
                  _update(context, settings.copyWith(sound: value)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _update(
    BuildContext context,
    StoryNotificationSettings settings,
  ) async {
    try {
      await account.component.updateNotificationSettings(settings);
      onChanged();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to update story notification settings',
      );
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Could not update story notification settings.'),
        ),
      );
    }
  }
}

class _StoryNotificationModeRow extends StatelessWidget {
  const _StoryNotificationModeRow({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String description;
  final StoryNotificationMode value;
  final ValueChanged<StoryNotificationMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 520;
        final label = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.25,
                letterSpacing: 0,
              ),
            ),
          ],
        );
        final control = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220, minWidth: 180),
          child: tiamat.DropdownSelector<StoryNotificationMode>(
            color: theme.colorScheme.surfaceContainer,
            items: StoryNotificationMode.values,
            itemBuilder: (mode) => tiamat.Text(_storyModeLabel(mode)),
            onItemSelected: (mode) {
              if (mode != null) {
                onChanged(mode);
              }
            },
            value: value,
          ),
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              label,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: control),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: label),
            const SizedBox(width: 16),
            control,
          ],
        );
      },
    );
  }
}

class _StoryNotificationSoundRow extends StatelessWidget {
  const _StoryNotificationSoundRow({
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Play sound',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Use the normal notification sound when a story alert is shown.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.25,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        SettingsSwitchStateLabel(
          value: value,
          child: Switch.adaptive(value: value, onChanged: onChanged),
        ),
      ],
    );
  }
}

String _storyModeLabel(StoryNotificationMode mode) {
  return switch (mode) {
    StoryNotificationMode.off => 'Off',
    StoryNotificationMode.mentionsOnly => 'Mentions only',
    StoryNotificationMode.contacts => 'Contacts',
    StoryNotificationMode.all => 'All',
  };
}

class NotificationDeveloperSettings extends StatefulWidget {
  const NotificationDeveloperSettings({super.key});

  @override
  State<NotificationDeveloperSettings> createState() =>
      _NotificationDeveloperSettingsState();
}

class _NotificationDeveloperSettingsState
    extends State<NotificationDeveloperSettings> {
  Notifier? notifier;
  GlobalKey pushGatewayKey = GlobalKey();
  bool isPushGatewayLoading = false;
  bool isRefreshingPushers = false;

  @override
  void initState() {
    super.initState();
    notifier = NotificationManager.notifier;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DeveloperNotificationCard(
          title: 'Push transport',
          description:
              'Inspect and configure the platform push path for this build.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildPushTransportStatus(),
              if (notifier is EmbeddedNtfyNotifier) ...[
                const SizedBox(height: 14),
                EmbeddedPushSetupView(
                  notifier: notifier as EmbeddedNtfyNotifier,
                  onChanged: () => setState(() {}),
                ),
              ],
              if (notifier is UnifiedPushNotifier) ...[
                const SizedBox(height: 14),
                UnifiedPushSetupView(onToggled: (_) => setState(() {})),
                if (preferences.unifiedPushEnabled.value == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: pushGatewaySelector(),
                  ),
              ] else ...[
                const SizedBox(height: 14),
                pushGatewaySelector(),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        const _DeveloperNotificationCard(
          title: 'Registered pushers',
          description:
              'Inspect Matrix pushers registered for the current accounts.',
          child: NotifierDebugView(),
        ),
      ],
    );
  }

  Widget buildPushTransportStatus() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tiamat.Text.labelLow("Active notifier: ${pushTransportLabel()}"),
        tiamat.Text.labelLow(
          "Google Services flag: ${BuildConfig.ENABLE_GOOGLE_SERVICES}",
        ),
        tiamat.Text.labelLow("Build detail: ${BuildConfig.BUILD_DETAIL}"),
        tiamat.Text.labelLow("Expected app id: ${expectedPushAppId()}"),
        tiamat.Text.labelLow("Gateway: ${preferences.pushGateway}"),
        if (PlatformUtils.isAndroid)
          tiamat.Text.labelLow(
            "Legacy Android and stale URL pushers are removed automatically during refresh.",
          ),
        const SizedBox(height: 12),
        tiamat.Button(
          text: "Refresh Pushers",
          isLoading: isRefreshingPushers,
          onTap: refreshPushers,
        ),
      ],
    );
  }

  String pushTransportLabel() {
    final currentNotifier = notifier;
    if (currentNotifier is FirebasePushNotifier) {
      return "FCM data-only";
    }
    if (currentNotifier is EmbeddedNtfyNotifier) {
      return "Embedded ntfy";
    }
    if (currentNotifier is UnifiedPushNotifier) {
      return "UnifiedPush distributor";
    }
    if (currentNotifier is IosNotifier) {
      return "iPhone APNs";
    }
    if (currentNotifier is WebPushNotifier) {
      return "Browser Web Push";
    }
    return currentNotifier.runtimeType.toString();
  }

  String expectedPushAppId() {
    if (PlatformUtils.isAndroid) {
      return BuildConfig.androidPushAppId;
    }
    if (PlatformUtils.isIOS) {
      return BuildConfig.iosPushAppId;
    }
    if (PlatformUtils.isWeb) {
      return BuildConfig.webPushAppId;
    }
    return "not applicable";
  }

  Widget pushGatewaySelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        tiamat.DropdownTextField(
          key: pushGatewayKey,
          initialValue: preferences.pushGateway,
          textEditorPlaceholder: "push.example.com",
          editableEntryPlaceholder: "Custom push gateway",
          items: [
            (PlatformUtils.isAndroid || PlatformUtils.isWeb)
                ? BuildConfig.androidPushGatewayHost
                : "push.ourgalaxy.space",
            if (notifier is UnifiedPushNotifier)
              "matrix.gateway.unifiedpush.org",
          ],
        ),
        const SizedBox(height: 10),
        tiamat.Button(
          text: CommonStrings.promptApply,
          isLoading: isPushGatewayLoading,
          onTap: onPushGatewaySelected,
        ),
      ],
    );
  }

  Future<void> onPushGatewaySelected() async {
    final state = pushGatewayKey.currentState as tiamat.DropdownTextFieldState;
    final value = state.value;

    setState(() {
      isPushGatewayLoading = true;
    });

    try {
      await preferences.setPushGateway(value);
      await PushNotificationComponent.updateAllPushers();
    } finally {
      if (mounted) {
        setState(() {
          isPushGatewayLoading = false;
        });
      }
    }
  }

  Future<void> refreshPushers() async {
    setState(() {
      isRefreshingPushers = true;
    });

    try {
      await PushNotificationComponent.updateAllPushers().timeout(
        const Duration(seconds: 45),
        onTimeout: () {
          throw TimeoutException("Refreshing pushers timed out");
        },
      );

      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: tiamat.Text.labelLow("Pushers refreshed")),
        );
      }
    } catch (e, s) {
      Log.e("Failed to refresh pushers");
      Log.onError(e, s);

      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: tiamat.Text.labelLow("Failed to refresh pushers: $e"),
          ),
        );
      }
    } finally {
      if (!mounted) return;

      setState(() {
        isRefreshingPushers = false;
      });
    }
  }
}

extension NotificationModeDetails on NotificationMode {
  String get title => switch (this) {
    NotificationMode.all => 'All',
    NotificationMode.mentions => 'Mentions & Keywords',
    NotificationMode.mute => 'Mute',
  };

  String get description => switch (this) {
    NotificationMode.all =>
      'Notify for all Matrix events that match your room settings.',
    NotificationMode.mentions =>
      'Only notify for highlighted Matrix events such as mentions, keywords, and @room.',
    NotificationMode.mute =>
      'Do not show message notifications on this device.',
  };

  IconData get icon => switch (this) {
    NotificationMode.all => Icons.notifications_active_outlined,
    NotificationMode.mentions => Icons.alternate_email_outlined,
    NotificationMode.mute => Icons.notifications_off_outlined,
  };
}

class _NotificationModeControl extends StatelessWidget {
  const _NotificationModeControl({
    required this.value,
    required this.onChanged,
  });

  final NotificationMode value;
  final Future<void> Function(NotificationMode mode) onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsControlRow(
      title: 'Notification mode',
      description:
          'Choose the default notification behavior for this device. Room and space overrides can still be tuned individually.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useColumn = constraints.maxWidth < 660;

          final options = [
            for (final mode in NotificationMode.values)
              NotificationModeTile(
                mode: mode,
                selected: value == mode,
                onTap: () {
                  unawaited(onChanged(mode));
                },
              ),
          ];

          if (useColumn) {
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
    );
  }
}

class NotificationModeTile extends StatelessWidget {
  const NotificationModeTile({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final NotificationMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = selected
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerLow;
    final foreground = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return Material(
      color: background,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
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
              Icon(mode.icon, color: foreground),
              const SizedBox(height: 10),
              Text(
                mode.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: foreground,
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                mode.description,
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
    );
  }
}

ClientManager? _providedClientManager(BuildContext context) {
  try {
    return Provider.of<ClientManager>(context, listen: false);
  } catch (_) {
    return null;
  }
}

@visibleForTesting
List<NotificationOverrideSummary> collectNotificationOverrides(
  ClientManager? manager, {
  Client? client,
}) {
  final summaries = <NotificationOverrideSummary>[];
  if (manager == null && client == null) {
    return summaries;
  }

  final clients = client == null ? manager!.clients : <Client>[client];

  for (final currentClient in clients) {
    for (final room in currentClient.rooms) {
      final hasCustomSound = CustomSoundManager.hasRoomNotificationSound(
        room.identifier,
      );
      final hasCustomVolume =
          preferences.getRoomNotificationVolume(room.identifier) != null;

      if (room.pushRule == PushRule.notify &&
          !hasCustomSound &&
          !hasCustomVolume) {
        continue;
      }

      summaries.add(
        NotificationOverrideSummary(
          displayName: room.displayName,
          typeLabel: 'Room',
          pushRule: room.pushRule,
          hasCustomSound: hasCustomSound,
          hasCustomVolume: hasCustomVolume,
          room: room,
        ),
      );
    }

    for (final space in currentClient.spaces) {
      // BUG-319: a space override can be set and still not appear here. Log the
      // collect-time reading only for spaces that actually carry a rule or
      // disagree with their cache, so a normal account emits nothing. Pairs
      // with the line MatrixSpace.setPushRule writes; remove with the bug.
      if (space is MatrixSpace) {
        final diagnostics = space.pushRuleDiagnostics;
        if (!diagnostics.contains('rules=none') ||
            !diagnostics.contains('fresh=notify')) {
          Log.i(
            'BUG-319 space collected: $diagnostics '
            'included=${space.pushRule != PushRule.notify}',
            category: LogCategory.notifications,
            source: 'collectNotificationOverrides',
          );
        }
      }

      if (space.pushRule == PushRule.notify) {
        continue;
      }

      summaries.add(
        NotificationOverrideSummary(
          displayName: space.displayName,
          typeLabel: 'Space',
          pushRule: space.pushRule,
          hasCustomSound: false,
          hasCustomVolume: false,
          space: space,
        ),
      );
    }
  }

  summaries.sort((a, b) {
    final type = a.typeLabel.compareTo(b.typeLabel);
    if (type != 0) {
      return type;
    }
    return a.displayName.compareTo(b.displayName);
  });

  return summaries;
}

class NotificationOverrideSummary {
  const NotificationOverrideSummary({
    required this.displayName,
    required this.typeLabel,
    required this.pushRule,
    required this.hasCustomSound,
    required this.hasCustomVolume,
    this.room,
    this.space,
  });

  final String displayName;
  final String typeLabel;
  final PushRule pushRule;
  final bool hasCustomSound;
  final bool hasCustomVolume;
  final Room? room;
  final Space? space;

  List<String> get details {
    final values = <String>[];
    if (pushRule != PushRule.notify) {
      values.add(_pushRuleLabel(pushRule));
    }
    if (hasCustomSound) {
      values.add('Custom sound');
    }
    if (hasCustomVolume) {
      values.add('Volume override');
    }
    return values;
  }
}

String _pushRuleLabel(PushRule rule) {
  return switch (rule) {
    PushRule.notify => 'All messages',
    PushRule.mentionsOnly => 'Mentions & keywords',
    PushRule.dontNotify => 'Muted',
  };
}

class _NotificationOverrideCard extends StatelessWidget {
  const _NotificationOverrideCard({required this.summary});

  final NotificationOverrideSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = summary.space != null
        ? Icons.grid_view_rounded
        : Icons.tag_rounded;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.72),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${summary.typeLabel} • ${summary.details.join(', ')}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.25,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: () => _openTargetSettings(context),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Open'),
          ),
        ],
      ),
    );
  }

  void _openTargetSettings(BuildContext context) {
    final room = summary.room;
    if (room != null) {
      SettingsNavigation.show(
        context,
        RoomSettingsPage(
          room: room,
          initialTabId: SettingsCategoryRoom.tabIdNotifications,
        ),
      );
      return;
    }

    final space = summary.space;
    if (space != null) {
      SettingsNavigation.show(
        context,
        SpaceSettingsPage(
          space: space,
          initialTabId: SettingsCategorySpace.tabIdNotifications,
        ),
      );
    }
  }
}

class _StatusActionCard extends StatelessWidget {
  const _StatusActionCard({
    required this.buttonLabel,
    required this.isLoading,
    required this.onPressed,
    required this.lines,
  });

  final String buttonLabel;
  final bool isLoading;
  final VoidCallback? onPressed;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.72),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tiamat.Button(
            text: buttonLabel,
            isLoading: isLoading,
            onTap: onPressed,
          ),
          const SizedBox(height: 12),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                line,
                maxLines: line.startsWith('Endpoint:') ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  height: 1.25,
                  letterSpacing: 0,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeveloperNotificationCard extends StatelessWidget {
  const _DeveloperNotificationCard({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.72),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
              height: 1.25,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _NotificationSoundPickerRow extends StatelessWidget {
  const _NotificationSoundPickerRow({
    required this.currentValueLabel,
    required this.isBusy,
    required this.onChoose,
    required this.onPreview,
    required this.onReset,
  });

  final String currentValueLabel;
  final bool isBusy;
  final VoidCallback onChoose;
  final VoidCallback onPreview;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.72),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            currentValueLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
              height: 1.25,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: tiamat.Button.secondary(
                  text: isBusy ? 'Choosing...' : 'Choose File',
                  onTap: isBusy ? null : onChoose,
                ),
              ),
              const SizedBox(width: 8),
              tiamat.Tooltip(
                text: 'Preview sound',
                child: tiamat.CircleButton(
                  icon: Icons.play_arrow,
                  onPressed: onPreview,
                ),
              ),
              const SizedBox(width: 8),
              tiamat.Tooltip(
                text: 'Reset to default sound',
                child: tiamat.CircleButton(
                  icon: Icons.restart_alt,
                  onPressed: onReset,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
