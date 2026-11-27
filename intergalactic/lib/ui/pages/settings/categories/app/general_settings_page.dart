import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/user_presence/user_presence_component.dart';
import 'package:intergalactic/config/gif_api_key_store.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/preferences/preferences_dm_lock.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/boolean_toggle.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/ui/pages/settings/settings_account_scope.dart';
import 'package:intergalactic/ui/pages/setup/menus/check_for_updates.dart';
import 'package:intergalactic/utils/error_utils.dart';
import 'package:intergalactic/utils/update_checker.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class GeneralSettingsPage extends StatefulWidget {
  const GeneralSettingsPage({super.key});

  @override
  State<GeneralSettingsPage> createState() => GeneralSettingsPageState();
}

enum _MediaPreviewMode { none, privateOnly, all }

enum _GifDisableChoice { keepSetup, clearLocalSetup }

enum _GifSetupChoice { relay, apiKey }

String _toggleSemanticAction(bool value) => value ? 'Turn off' : 'Turn on';

class GeneralSettingsPageState extends State<GeneralSettingsPage> {
  StreamSubscription<String?>? _gifKeySubscription;
  StreamSubscription<String?>? _gifRelaySubscription;
  StreamSubscription<bool>? _gifSearchEnabledSubscription;

  Client? _selectedClient;
  bool _publicReadReceipts = true;
  bool _typingIndicator = true;

  String get labelUpdatesTitle => Intl.message(
    "Check for Updates",
    desc: "Header for app update settings",
    name: "labelUpdatesTitle",
  );

  String get labelMediaSettings => Intl.message(
    "Media",
    desc: "Header for media settings",
    name: "labelMediaSettings",
  );

  String get labelGifSearchToggle => Intl.message(
    "GIF search",
    desc: "Label for the toggle for enabling and disabling GIF search",
    name: "labelGifSearchToggle",
  );

  String get labelGifSearchApiKeyDescription => Intl.message(
    "Search and send GIFs from the composer using the managed GIF relay when available, or a relay/API key you save locally. Search terms are sent to the selected relay or provider.",
    desc:
        "Explains the managed relay and local override behavior for GIF search",
    name: "labelGifSearchApiKeyDescription",
  );

  String get labelUrlPreviewInEncryptedChatTitle => Intl.message(
    "URL previews in encrypted chats",
    desc:
        "Label for the toggle for enabling and disabling URL previews in encrypted chats",
    name: "labelUrlPreviewInEncryptedChatTitle",
  );

  String get labelUrlPreviewInEncryptedChatDescription => Intl.message(
    "Ask before first use on new installs. When enabled, encrypted-chat URLs may be sent to your homeserver or configured preview service for preview fetching.",
    desc:
        "Description for the toggle for enabling and disabling URL previews in encrypted chats",
    name: "labelUrlPreviewInEncryptedChatDescription",
  );

  String get labelDirectPreviewFallbackE2EETitle => Intl.message(
    "Direct preview fallback in encrypted chats",
    desc:
        "Label for the toggle allowing a direct third-party fetch as a fallback for URL previews in encrypted chats",
    name: "labelDirectPreviewFallbackE2EETitle",
  );

  String get labelDirectPreviewFallbackE2EEDescription => Intl.message(
    "Off by default. The app first tries a configured preview service if available, then may try your homeserver. If the preview remains incomplete, this option may fetch from TikTok, Instagram, or Reddit. A card with enough text but no image may still fetch a provider site icon. The service, homeserver, and link site may each receive the URL; the provider or image host may see your device's IP address when fetching a thumbnail or icon.",
    desc:
        "Description explaining that encrypted-chat direct fallback may fetch metadata, a thumbnail, or a site icon, disclosing the URL or device IP to additional recipients",
    name: "labelDirectPreviewFallbackE2EEDescription",
  );

  String get labelDirectPreviewFallbackUnencryptedTitle => Intl.message(
    "Direct preview fallback in unencrypted chats",
    desc:
        "Label for the toggle allowing a direct third-party fetch as a fallback for URL previews in unencrypted chats",
    name: "labelDirectPreviewFallbackUnencryptedTitle",
  );

  String get labelDirectPreviewFallbackUnencryptedDescription => Intl.message(
    "Off by default. The app first tries a configured preview service if available, then may try your homeserver. If the preview remains incomplete, this option may fetch from TikTok, Instagram, or Reddit. A card with enough text but no image may still fetch a provider site icon. Your homeserver already sees unencrypted links; the service and link site may also receive the URL. The provider or image host may see your device's IP address when fetching a thumbnail or icon.",
    desc:
        "Description explaining that unencrypted-chat direct fallback may fetch metadata, a thumbnail, or a site icon, disclosing the URL or device IP to additional recipients",
    name: "labelDirectPreviewFallbackUnencryptedDescription",
  );

  String get labelMediaPreviewsTitle => Intl.message(
    "Media previews",
    desc: "Label for the media preview picker",
    name: "labelMediaPreviewsTitle",
  );

  String get labelMediaPreviewsDescription => Intl.message(
    "Choose where images, videos, stickers, and URL previews can load automatically. URL previews may use your homeserver, an optional configured preview service, or a direct client fetch when supported.",
    desc: "Description for the media preview picker",
    name: "labelMediaPreviewsDescription",
  );

  String get labelRemovePhotoMetadataBeforeSendingTitle => Intl.message(
    "Remove photo metadata before sending",
    desc: "Label for the photo upload privacy setting",
    name: "labelRemovePhotoMetadataBeforeSendingTitle",
  );

  String get labelRemovePhotoMetadataBeforeSendingDescription => Intl.message(
    "For compatible photos, helps protect your privacy by removing details such as where a photo was taken. If Inter Galactic cannot safely prepare a photo, it sends the original unchanged. Turn this off to always send the original photo unchanged.",
    desc: "Explains the photo upload metadata privacy setting",
    name: "labelRemovePhotoMetadataBeforeSendingDescription",
  );

  String get labelAutoSaveStoriesTitle => Intl.message(
    "Auto-download story uploads",
    desc: "Label for automatically saving the user's uploaded stories locally",
    name: "labelAutoSaveStoriesTitle",
  );

  String get labelAutoSaveStoriesDescription => Intl.message(
    "When supported, save your uploaded photo stories to the device photo library after they post. On iPhone, this uses Photos instead of the Files picker.",
    desc: "Description for automatically saving uploaded story photos locally",
    name: "labelAutoSaveStoriesDescription",
  );

  String get labelAutoSaveCapturedMediaTitle => Intl.message(
    "Save camera captures to gallery",
    desc: "Label for automatically saving photos and videos taken in the app",
    name: "labelAutoSaveCapturedMediaTitle",
  );

  String get labelAutoSaveCapturedMediaDescription => Intl.message(
    "Photos and videos you take with the in-app camera are also saved to your device gallery. Applies to camera captures only, not to media you pick from your gallery.",
    desc:
        "Description for automatically saving photos and videos taken in the app",
    name: "labelAutoSaveCapturedMediaDescription",
  );

  String get labelStickerCompatibility => Intl.message(
    "Sticker compatibility",
    desc: "Header for the settings to enable sticker compatibility mode",
    name: "labelStickerCompatibility",
  );

  String get labelSettingsStickerCompatibilityExplanation => Intl.message(
    "Send stickers as image messages for Matrix clients that do not render m.sticker events correctly.",
    desc: "Explains what sticker compatibility mode does",
    name: "labelSettingsStickerCompatibilityExplanation",
  );

  String get labelDirectMessageLockTitle => Intl.message(
    "Direct Message Lock",
    desc: "Header for direct message lock settings",
    name: "labelDirectMessageLockTitle",
  );

  String get labelAppBehaviourTitle => Intl.message(
    "App Behavior",
    desc: "Header for the app behavior section in settings",
    name: "labelAppBehaviourTitle",
  );

  String get labelAskBeforeDeletingMessageToggle => Intl.message(
    "Ask before deleting messages",
    desc:
        "Label for the toggle for enabling and disabling message deletion confirmation",
    name: "labelAskBeforeDeletingMessageToggle",
  );

  String get labelAskBeforeDeletingMessageDescription => Intl.message(
    "Enables the pop-up asking for confirmation when deleting a message.",
    desc: "Label describing what asking before deleting messages means",
    name: "labelAskBeforeDeletingMessageDescription",
  );

  String get labelPublicReadReceiptsToggle => Intl.message(
    "Read receipts",
    desc:
        "Label for the toggle for enabling and disabling sending read receipts",
    name: "labelPublicReadReceiptsToggle",
  );

  String get labelPublicReadReceiptsDescription => Intl.message(
    "Let other room members know when you have read their messages.",
    desc:
        "Description for the toggle for enabling and disabling sending read receipts",
    name: "labelPublicReadReceiptsDescription",
  );

  String get labelTypingIndicatorsToggle => Intl.message(
    "Typing indicator",
    desc:
        "Label for the toggle for enabling and disabling sending typing indicator",
    name: "labelTypingIndicatorsToggle",
  );

  String get labelPublicTypingIndicatorDescription => Intl.message(
    "Let other room members know when you are typing a message.",
    desc:
        "Description for the toggle for enabling and disabling sending typing indicator",
    name: "labelPublicTypingIndicatorDescription",
  );

  String get labelMessageEffectsTitle => Intl.message(
    "Message effects",
    desc: "Header for the settings tile for message effects",
    name: "labelMessageEffectsTitle",
  );

  String get labelMessageEffectsDescription => Intl.message(
    "Messages can be sent with additional effects, such as confetti.",
    desc: "Label describing what message effects are",
    name: "labelMessageEffectsDescription",
  );

  String get labelAutomaticMessageEffectsTitle => Intl.message(
    "Automatic message effects",
    desc:
        "Header for the settings tile for automatic trigger-based message effects",
    name: "labelAutomaticMessageEffectsTitle",
  );

  String get labelAutomaticMessageEffectsDescription => Intl.message(
    "Send a matching effect when a normal message includes phrases like congratulations, pride, or snow day. Manual effects still work.",
    desc:
        "Label describing automatic trigger-based message effects and their manual effect boundary",
    name: "labelAutomaticMessageEffectsDescription",
  );

  String get labelOfflineDemoLoginToggle => Intl.message(
    "Show offline demo sign-in",
    desc:
        "Label for the setting that shows or hides the offline demo login button",
    name: "labelOfflineDemoLoginToggle",
  );

  String get labelOfflineDemoLoginDescription => Intl.message(
    "Adds a local demo account option to the login page for app review and walkthroughs. It does not connect to a homeserver.",
    desc:
        "Description for the setting that shows or hides the offline demo login button",
    name: "labelOfflineDemoLoginDescription",
  );

  String get labelWindowBehaviourTitle => Intl.message(
    "Window behavior",
    desc: "Header for window behavior settings",
    name: "labelWindowBehaviourTitle",
  );

  String get labelSettingsMinimizeOnCloseToggle => Intl.message(
    "Minimize on close",
    desc: "Label for the toggle to turn on and off minimize on close",
    name: "labelSettingsMinimizeOnCloseToggle",
  );

  String get labelSettingsMinimizeOnCloseExplanation => Intl.message(
    "When closing the window, the app will be minimized instead of exited.",
    desc: "Explains what the minimize on close setting does",
    name: "labelSettingsMinimizeOnCloseExplanation",
  );

  UserPresenceComponent? get _presenceComponent =>
      _selectedClient?.getComponent<UserPresenceComponent>();

  _MediaPreviewMode get _mediaPreviewMode {
    final privatePreviews = preferences.previewMediaInPrivateRooms.value;
    final publicPreviews = preferences.previewMediaInPublicRooms.value;

    if (!privatePreviews && !publicPreviews) {
      return _MediaPreviewMode.none;
    }

    if (publicPreviews) {
      return _MediaPreviewMode.all;
    }

    return _MediaPreviewMode.privateOnly;
  }

  bool get _gifSearchEnabled =>
      preferences.gifSearchEnabled.value && GifApiKeyStore.hasSearchProvider;

  @override
  void initState() {
    super.initState();

    final initialClient = SettingsAccountController.resolvePreferredClient(
      clientManager,
    );
    if (initialClient != null) {
      _selectedClient = initialClient;
      _syncPresenceState();
    }

    _gifKeySubscription = GifApiKeyStore.onChanged.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
    _gifRelaySubscription = GifApiKeyStore.onRelayChanged.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
    _gifSearchEnabledSubscription = preferences.gifSearchEnabled.onChanged
        .listen((_) {
          if (mounted) {
            setState(() {});
          }
        });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final manager = clientManager;
    if (manager == null) {
      return;
    }

    final scopedClient = SettingsAccountScope.selectedClientOf(
      context,
      manager,
    );
    if (!identical(scopedClient, _selectedClient)) {
      _selectedClient = scopedClient;
      _syncPresenceState();
    }
  }

  @override
  void dispose() {
    _gifKeySubscription?.cancel();
    _gifRelaySubscription?.cancel();
    _gifSearchEnabledSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (UpdateChecker.shouldCheckForUpdates)
          SettingsSection(
            title: labelUpdatesTitle,
            children: [CheckForUpdatesSettingWidget()],
          ),
        SettingsSection(
          title: labelMediaSettings,
          children: [
            _buildGifSearchSetting(),
            BooleanPreferenceToggle(
              preference: preferences.urlPreviewInE2EEChat,
              title: labelUrlPreviewInEncryptedChatTitle,
              description: labelUrlPreviewInEncryptedChatDescription,
              onChanged: (value) =>
                  preferences.applyUrlPreviewE2EEConsentChoice(allow: value),
            ),
            BooleanPreferenceToggle(
              preference: preferences.allowDirectUrlPreviewFallbackInE2EEChat,
              title: labelDirectPreviewFallbackE2EETitle,
              description: labelDirectPreviewFallbackE2EEDescription,
            ),
            BooleanPreferenceToggle(
              preference:
                  preferences.allowDirectUrlPreviewFallbackInUnencryptedChat,
              title: labelDirectPreviewFallbackUnencryptedTitle,
              description: labelDirectPreviewFallbackUnencryptedDescription,
            ),
            _buildMediaPreviewModePicker(),
            BooleanPreferenceToggle(
              preference: preferences.removePhotoMetadataBeforeSending,
              title: labelRemovePhotoMetadataBeforeSendingTitle,
              description: labelRemovePhotoMetadataBeforeSendingDescription,
            ),
            BooleanPreferenceToggle(
              preference: preferences.autoSaveUploadedStories,
              title: labelAutoSaveStoriesTitle,
              description: labelAutoSaveStoriesDescription,
            ),
            // Only Android and iOS have a device gallery to write into, so the
            // toggle would be inert everywhere else.
            if (PlatformUtils.isAndroid || PlatformUtils.isIOS)
              BooleanPreferenceToggle(
                preference: preferences.autoSaveCapturedMedia,
                title: labelAutoSaveCapturedMediaTitle,
                description: labelAutoSaveCapturedMediaDescription,
              ),
            BooleanPreferenceToggle(
              preference: preferences.stickerCompatibilityMode,
              title: labelStickerCompatibility,
              description: labelSettingsStickerCompatibilityExplanation,
            ),
            if (Layout.mobile) ...[
              tiamat.Seperator(),
              BooleanPreferenceToggle(
                preference: preferences.autoRotateImages,
                title: "Rotate images",
                description:
                    "When showing images in fullscreen, automatically rotate the image to best fill the screen.",
              ),
              BooleanPreferenceToggle(
                preference: preferences.autoRotateVideos,
                title: "Rotate videos",
                description:
                    "When showing videos in fullscreen, automatically rotate the video to best fill the screen.",
              ),
            ],
          ],
        ),
        if (_selectedClient != null)
          SettingsSection(
            title: labelDirectMessageLockTitle,
            children: [
              DmLockPreferences(
                client: _selectedClient!,
                showPanel: false,
                key: ValueKey(
                  "general-dm-lock-preferences_${_selectedClient!.identifier}",
                ),
              ),
            ],
          ),
        SettingsSection(
          title: labelAppBehaviourTitle,
          showDivider: Layout.desktop,
          children: [
            BooleanPreferenceToggle(
              preference: preferences.askBeforeDeletingMessageEnabled,
              title: labelAskBeforeDeletingMessageToggle,
              description: labelAskBeforeDeletingMessageDescription,
            ),
            if (_presenceComponent != null) ...[
              _PresenceSwitchRow(
                title: labelPublicReadReceiptsToggle,
                description: labelPublicReadReceiptsDescription,
                value: _publicReadReceipts,
                onChanged: _setPublicReadReceipts,
              ),
              _PresenceSwitchRow(
                title: labelTypingIndicatorsToggle,
                description: labelPublicTypingIndicatorDescription,
                value: _typingIndicator,
                onChanged: _setTypingIndicator,
              ),
            ],
            BooleanPreferenceToggle(
              preference: preferences.autoFocusMessageTextBox,
              title: "Autofocus message input",
              description:
                  "Automatically focus on the message input text field when opening a chat.",
            ),
            BooleanPreferenceToggle(
              preference: preferences.automaticallyOpenSpace,
              title: "Always open space",
              description:
                  "When navigating to a room from outside of a space, also open the space the room is in, if any.",
            ),
            BooleanPreferenceToggle(
              preference: preferences.messageEffectsEnabled,
              title: labelMessageEffectsTitle,
              description: labelMessageEffectsDescription,
            ),
            BooleanPreferenceToggle(
              preference: preferences.automaticMessageEffectsEnabled,
              title: labelAutomaticMessageEffectsTitle,
              description: labelAutomaticMessageEffectsDescription,
            ),
            BooleanPreferenceToggle(
              preference: preferences.offlineDemoLoginEnabled,
              title: labelOfflineDemoLoginToggle,
              description: labelOfflineDemoLoginDescription,
            ),
          ],
        ),
        if (Layout.desktop)
          SettingsSection(
            title: labelWindowBehaviourTitle,
            showDivider: false,
            children: [
              BooleanPreferenceToggle(
                preference: preferences.minimizeOnClose,
                title: labelSettingsMinimizeOnCloseToggle,
                description: labelSettingsMinimizeOnCloseExplanation,
              ),
            ],
          ),
      ],
    );
  }

  SettingsControlRow _buildGifSearchSetting() {
    final hasApiKey = GifApiKeyStore.hasApiKey;
    final hasSavedRelay = GifApiKeyStore.hasSavedRelayBaseUrl;
    final hasProvider = GifApiKeyStore.hasSearchProvider;
    final description =
        "$labelGifSearchApiKeyDescription ${GifApiKeyStore.providerStatusLabel}.";

    return SettingsControlRow(
      title: labelGifSearchToggle,
      description: description,
      semanticValue: settingsToggleStateLabel(_gifSearchEnabled),
      toggled: _gifSearchEnabled,
      semanticOnTapHint: _toggleSemanticAction(_gifSearchEnabled),
      onActivate: () => _handleGifSearchToggle(!_gifSearchEnabled),
      trailing: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 4, 0),
        child: SettingsSwitchStateLabel(
          value: _gifSearchEnabled,
          child: ExcludeFocus(
            child: tiamat.Switch(
              state: _gifSearchEnabled,
              onChanged: _handleGifSearchToggle,
            ),
          ),
        ),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          tiamat.Button.secondary(
            text: hasProvider ? "Change GIF setup" : "Set up GIF search",
            onTap: () => _showGifSearchSetup(enableAfterSave: true),
          ),
          if (hasSavedRelay)
            tiamat.Button.secondary(
              text: "Clear saved relay",
              onTap: _clearGifRelayUrl,
            ),
          if (hasApiKey)
            tiamat.Button.secondary(
              text: "Clear saved key",
              onTap: _clearGifApiKey,
            ),
        ],
      ),
    );
  }

  SettingsControlRow _buildMediaPreviewModePicker() {
    return SettingsControlRow(
      title: labelMediaPreviewsTitle,
      description: labelMediaPreviewsDescription,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260, minWidth: 180),
        child: tiamat.DropdownSelector<_MediaPreviewMode>(
          color: ColorScheme.of(context).surfaceContainer,
          items: _MediaPreviewMode.values,
          itemBuilder: (item) {
            return tiamat.Text.label(_mediaPreviewModeLabel(item));
          },
          onItemSelected: _setMediaPreviewMode,
          value: _mediaPreviewMode,
        ),
      ),
    );
  }

  String _mediaPreviewModeLabel(_MediaPreviewMode mode) {
    return switch (mode) {
      _MediaPreviewMode.none => "None",
      _MediaPreviewMode.privateOnly => "Private chats only",
      _MediaPreviewMode.all => "All chats",
    };
  }

  Future<void> _setMediaPreviewMode(_MediaPreviewMode? mode) async {
    if (mode == null) {
      return;
    }

    switch (mode) {
      case _MediaPreviewMode.none:
        await preferences.previewMediaInPrivateRooms.set(false);
        await preferences.previewMediaInPublicRooms.set(false);
        break;
      case _MediaPreviewMode.privateOnly:
        await preferences.previewMediaInPrivateRooms.set(true);
        await preferences.previewMediaInPublicRooms.set(false);
        break;
      case _MediaPreviewMode.all:
        await preferences.previewMediaInPrivateRooms.set(true);
        await preferences.previewMediaInPublicRooms.set(true);
        break;
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _handleGifSearchToggle(bool value) async {
    if (value) {
      if (!GifApiKeyStore.hasSearchProvider) {
        await _showGifSearchSetup(enableAfterSave: true);
        return;
      }

      await preferences.gifSearchEnabled.set(true);
      if (mounted) {
        setState(() {});
      }
      return;
    }

    final disableChoice = await AdaptiveDialog.show<_GifDisableChoice>(
      context,
      title: "Disable GIF search?",
      builder: (context) {
        return SizedBox(
          width: Layout.desktop ? 420 : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              tiamat.Text.label(
                "You can disable GIF search and keep local relay/API setup for later, or clear local setup from this device.",
              ),
              const SizedBox(height: 12),
              tiamat.Button(
                text: "Disable and keep setup",
                onTap: () =>
                    Navigator.of(context).pop(_GifDisableChoice.keepSetup),
              ),
              const SizedBox(height: 8),
              tiamat.Button.secondary(
                text: "Disable and clear local setup",
                onTap: () => Navigator.of(
                  context,
                ).pop(_GifDisableChoice.clearLocalSetup),
              ),
              const SizedBox(height: 8),
              tiamat.Button.secondary(
                text: "Cancel",
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      },
    );

    if (disableChoice == null) {
      return;
    }

    await preferences.gifSearchEnabled.set(false);
    if (disableChoice == _GifDisableChoice.clearLocalSetup) {
      await GifApiKeyStore.clearApiKey();
      await GifApiKeyStore.clearRelayBaseUrl();
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showGifSearchSetup({required bool enableAfterSave}) async {
    final choice = await AdaptiveDialog.show<_GifSetupChoice>(
      context,
      title: "Set up GIF search",
      builder: (context) {
        return SizedBox(
          width: Layout.desktop ? 420 : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              tiamat.Text.label(
                "This build can use the managed GIF relay when it is available. You can also save a different relay or your own KLIPY API key. Search terms are sent to the selected relay or provider.",
              ),
              const SizedBox(height: 12),
              tiamat.Button(
                text: "Use relay URL",
                onTap: () => Navigator.of(context).pop(_GifSetupChoice.relay),
              ),
              const SizedBox(height: 8),
              tiamat.Button.secondary(
                text: "Use KLIPY API key",
                onTap: () => Navigator.of(context).pop(_GifSetupChoice.apiKey),
              ),
              const SizedBox(height: 8),
              tiamat.Button.secondary(
                text: "Cancel",
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      },
    );

    switch (choice) {
      case _GifSetupChoice.relay:
        await _promptForGifRelayUrl(enableAfterSave: enableAfterSave);
        break;
      case _GifSetupChoice.apiKey:
        await _promptForGifApiKey(enableAfterSave: enableAfterSave);
        break;
      case null:
        break;
    }
  }

  Future<void> _promptForGifRelayUrl({required bool enableAfterSave}) async {
    final relayUrl = await AdaptiveDialog.textPrompt(
      context,
      title: "GIF relay URL",
      submitText: enableAfterSave ? "Save and enable" : "Save relay",
      hintText: "https://example.com/api/gif",
    );
    final normalizedRelayUrl = GifApiKeyStore.normalizeRelayBaseUrl(relayUrl);
    if (normalizedRelayUrl == null) {
      if (relayUrl != null && relayUrl.trim().isNotEmpty) {
        await AdaptiveDialog.showError(
          context,
          const FormatException("Enter a valid http or https GIF relay URL."),
          StackTrace.current,
        );
      }
      return;
    }

    await GifApiKeyStore.setRelayBaseUrl(normalizedRelayUrl);
    if (enableAfterSave) {
      await preferences.gifSearchEnabled.set(true);
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _promptForGifApiKey({required bool enableAfterSave}) async {
    final apiKey = await AdaptiveDialog.textPrompt(
      context,
      title: "KLIPY API key",
      submitText: enableAfterSave ? "Save and enable" : "Save key",
      hintText: "Paste your KLIPY API key",
    );
    final normalizedApiKey = apiKey?.trim();
    if (normalizedApiKey == null || normalizedApiKey.isEmpty) {
      return;
    }

    await GifApiKeyStore.setApiKey(normalizedApiKey);
    if (enableAfterSave) {
      await preferences.gifSearchEnabled.set(true);
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _clearGifApiKey() async {
    final confirmed = await AdaptiveDialog.confirmation(
      context,
      title: "Clear GIF API key?",
      prompt:
          "This removes the saved KLIPY API key from this device. GIF search stays available if a relay is configured.",
      confirmationText: "Clear key",
      cancelText: "Cancel",
      dangerous: true,
    );

    if (confirmed != true) {
      return;
    }

    await GifApiKeyStore.clearApiKey();
    if (!GifApiKeyStore.hasSearchProvider) {
      await preferences.gifSearchEnabled.set(false);
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _clearGifRelayUrl() async {
    final confirmed = await AdaptiveDialog.confirmation(
      context,
      title: "Clear saved GIF relay?",
      prompt:
          "This removes the saved GIF relay URL from this device. GIF search stays available if this build has a relay configured or you have a saved API key.",
      confirmationText: "Clear relay",
      cancelText: "Cancel",
      dangerous: true,
    );

    if (confirmed != true) {
      return;
    }

    await GifApiKeyStore.clearRelayBaseUrl();
    if (!GifApiKeyStore.hasSearchProvider) {
      await preferences.gifSearchEnabled.set(false);
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _setPublicReadReceipts(bool value) async {
    final presenceComponent = _presenceComponent;
    if (presenceComponent == null) {
      return;
    }

    setState(() {
      _publicReadReceipts = value;
    });

    await ErrorUtils.tryRun(context, () async {
      await presenceComponent.setUsePublicReadReceipts(value);
    });

    if (mounted && identical(presenceComponent, _presenceComponent)) {
      setState(() {
        _publicReadReceipts = presenceComponent.usePublicReadReceipts;
      });
    }
  }

  Future<void> _setTypingIndicator(bool value) async {
    final presenceComponent = _presenceComponent;
    if (presenceComponent == null) {
      return;
    }

    setState(() {
      _typingIndicator = value;
    });

    await ErrorUtils.tryRun(context, () async {
      await presenceComponent.setTypingIndicatorEnabled(value);
    });

    if (mounted && identical(presenceComponent, _presenceComponent)) {
      setState(() {
        _typingIndicator = presenceComponent.typingIndicatorEnabled;
      });
    }
  }

  void _syncPresenceState() {
    final presenceComponent = _presenceComponent;
    _publicReadReceipts = presenceComponent?.usePublicReadReceipts ?? true;
    _typingIndicator = presenceComponent?.typingIndicatorEnabled ?? true;
  }
}

class _PresenceSwitchRow extends StatelessWidget {
  const _PresenceSwitchRow({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String description;
  final bool value;
  final Future<void> Function(bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsControlRow(
      title: title,
      description: description,
      semanticValue: settingsToggleStateLabel(value),
      semanticOnTapHint: _toggleSemanticAction(value),
      toggled: value,
      onActivate: () => onChanged(!value),
      excludeChildSemantics: true,
      trailing: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 4, 0),
        child: SettingsSwitchStateLabel(
          value: value,
          child: ExcludeFocus(
            child: tiamat.Switch(state: value, onChanged: onChanged),
          ),
        ),
      ),
    );
  }
}
