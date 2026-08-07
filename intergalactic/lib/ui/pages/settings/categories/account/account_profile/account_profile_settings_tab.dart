import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/user_color/user_color_component.dart';
import 'package:intergalactic/client/components/user_presence/user_presence_component.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/molecules/image_select_dialog.dart';
import 'package:intergalactic/ui/molecules/message_input.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/organisms/user_profile/user_profile_view.dart';
import 'package:intergalactic/ui/pages/login/login_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/ui/pages/settings/settings_account_scope.dart';
import 'package:intergalactic/ui/pages/settings/settings_typography.dart';
import 'package:intergalactic/utils/picker_utils.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class AccountProfileSettingsTab extends StatefulWidget {
  const AccountProfileSettingsTab({required this.clientManager, super.key});

  static const addAccountKey =
      ValueKey("ACCOUNT_PROFILE_SETTINGS_ADD_ACCOUNT_BUTTON");
  static const saveChangesKey =
      ValueKey("ACCOUNT_PROFILE_SETTINGS_SAVE_CHANGES_BUTTON");
  static const cancelChangesKey =
      ValueKey("ACCOUNT_PROFILE_SETTINGS_CANCEL_CHANGES_BUTTON");

  final ClientManager clientManager;

  @override
  State<AccountProfileSettingsTab> createState() =>
      _AccountProfileSettingsTabState();
}

class _AccountProfileSettingsTabState extends State<AccountProfileSettingsTab> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _pronounsController = TextEditingController();
  final TextEditingController _statusController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();

  Client? _selectedClient;
  Profile? _profile;
  ImageProvider? _avatar;
  ImageProvider? _banner;
  List<ProfileBadge> _badges = const [];

  bool _isLoadingProfile = true;
  bool _isSaving = false;
  int _profileLoadToken = 0;

  String _loadedDisplayName = "";
  String _loadedPronounsText = "";
  String _loadedStatus = "";
  String _loadedBio = "";
  bool _loadedShareTimezone = false;
  String? _loadedTimezone;
  Color? _loadedProfileColor;
  Brightness? _loadedProfileBrightness;
  Color? _loadedLocalColorOverride;

  bool _draftShareTimezone = false;
  String? _draftTimezone;
  Color? _draftProfileColor;
  Brightness? _draftProfileBrightness;
  Color? _draftLocalColorOverride;

  String get promptAddAccount => Intl.message("Add Account",
      desc: "Label for button in settings to add another account",
      name: "promptAddAccount");

  String get promptProfileWriteBioHint => Intl.message("Write about yourself",
      name: "promptProfileWriteBioHint",
      desc: "Hint text for the profile bio editor");

  String get labelProfileYourBadges => Intl.message("Your Badges",
      name: "labelProfileYourBadges",
      desc:
          "label for the ui to select which badges to display on the users profile");

  String get labelProfileNoBadges =>
      Intl.message("You don't have any badges available for this account yet.",
          name: "labelProfileNoBadges",
          desc: "text that is shown when the user has no badges");

  bool get _hasUnsavedChanges {
    return _draftDisplayName != _loadedDisplayName ||
        _draftPronounsText != _loadedPronounsText ||
        _draftStatus != _loadedStatus ||
        _draftBio != _loadedBio ||
        _draftShareTimezone != _loadedShareTimezone ||
        _draftTimezone != _loadedTimezone ||
        _draftProfileColor != _loadedProfileColor ||
        _draftProfileBrightness != _loadedProfileBrightness ||
        _draftLocalColorOverride != _loadedLocalColorOverride;
  }

  String get _draftDisplayName => _displayNameController.text.trim();
  String get _draftPronounsText =>
      _parsePronouns(_pronounsController.text).join(", ");
  String get _draftStatus => _statusController.text.trim();
  String get _draftBio => _bioController.text.trim();

  @override
  void initState() {
    super.initState();
    final initialClient = SettingsAccountController.resolvePreferredClient(
      widget.clientManager,
    );
    if (initialClient != null) {
      _selectClient(initialClient, refresh: false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scopedClient = SettingsAccountScope.selectedClientOf(
      context,
      widget.clientManager,
    );
    if (scopedClient != null && !identical(scopedClient, _selectedClient)) {
      unawaited(_selectClient(scopedClient, refresh: false));
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _displayNameController.dispose();
    _pronounsController.dispose();
    _statusController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedClient = _selectedClient;

    if (selectedClient == null) {
      return Center(
        child: tiamat.Button(
          text: promptAddAccount,
          onTap: () => _openAddAccount(context),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final useTwoPane = constraints.maxWidth >= 820;
        final editor = _buildEditorPane(context, selectedClient);
        final preview = _buildPreviewPane(context, selectedClient);
        final bottomPadding = _hasUnsavedChanges ? 96.0 : 0.0;

        if (useTwoPane) {
          return Stack(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 6,
                    child: Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: false,
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: EdgeInsets.only(
                          right: 24,
                          bottom: bottomPadding,
                        ),
                        child: editor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 4,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 18),
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: preview,
                      ),
                    ),
                  ),
                ],
              ),
              if (_hasUnsavedChanges) _buildUnsavedChangesBar(context),
            ],
          );
        }

        return Stack(
          children: [
            Scrollbar(
              controller: _scrollController,
              thumbVisibility: false,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: EdgeInsets.only(bottom: bottomPadding),
                child: Padding(
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      preview,
                      const SizedBox(height: 18),
                      editor,
                    ],
                  ),
                ),
              ),
            ),
            if (_hasUnsavedChanges) _buildUnsavedChangesBar(context),
          ],
        );
      },
    );
  }

  Widget _buildEditorPane(BuildContext context, Client selectedClient) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: "Accounts",
          showDivider: true,
          children: [
            SettingsControlRow(
              title: "Add account",
              description:
                  "Sign in another account. Use the settings header to choose which account you are editing.",
              trailing: tiamat.Button.secondary(
                text: promptAddAccount,
                onTap: () => _openAddAccount(context),
              ),
            ),
          ],
        ),
        SettingsSection(
          title: "Profile",
          showDivider: false,
          children: [
            SettingsControlRow(
              title: "Display name",
              child: _ProfileTextField(
                controller: _displayNameController,
                hintText: "Display name",
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => unawaited(_savePendingChanges()),
              ),
            ),
            SettingsControlRow(
              title: "Pronouns",
              child: _ProfileTextField(
                controller: _pronounsController,
                hintText: "she/her, they/them",
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => unawaited(_savePendingChanges()),
              ),
            ),
            SettingsControlRow(
              title: "Status",
              child: _ProfileTextField(
                controller: _statusController,
                hintText: "What are you up to?",
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => unawaited(_savePendingChanges()),
              ),
            ),
            SettingsControlRow(
              title: "Color",
              child: _buildColorControls(
                context,
                selectedClient,
              ),
            ),
            SettingsControlRow(
              title: "Bio",
              child: _ProfileTextField(
                controller: _bioController,
                hintText: promptProfileWriteBioHint,
                minLines: 3,
                maxLines: 6,
                onChanged: (_) => setState(() {}),
              ),
            ),
            SettingsControlRow(
              title: "Timezone",
              semanticValue: settingsToggleStateLabel(_draftShareTimezone),
              toggled: _draftShareTimezone,
              semanticOnTapHint: "Toggle timezone sharing",
              onActivate: _isSaving
                  ? null
                  : () => unawaited(
                        _setTimezoneSharing(!_draftShareTimezone),
                      ),
              enabled: !_isSaving,
              excludeChildSemantics: true,
              trailing: Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 4, 0),
                child: SettingsSwitchStateLabel(
                  value: _draftShareTimezone,
                  child: ExcludeFocus(
                    child: tiamat.Switch(
                      state: _draftShareTimezone,
                      onChanged: _isSaving
                          ? null
                          : (value) => unawaited(_setTimezoneSharing(value)),
                    ),
                  ),
                ),
              ),
            ),
            if (preferences.developerMode.value)
              SettingsControlRow(
                title: "Show Raw Profile",
                description:
                    "Inspect the Matrix profile payload for this account.",
                trailing: tiamat.Button.secondary(
                  text: "Show Raw Profile",
                  onTap: _showSource,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildPreviewPane(BuildContext context, Client selectedClient) {
    final theme = Theme.of(context);

    final profileAccent = _profileThemeSwatchColor(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.36),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              "Profile preview",
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w400,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "This updates as you edit. Save writes changes to your selected Matrix account.",
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 14),
            if (_isLoadingProfile)
              const SizedBox(
                height: 260,
                child: Center(child: CircularProgressIndicator()),
              )
            else
              Theme(
                data: _previewTheme(context),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: profileAccent,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: 26,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(2),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: UserProfileView(
                      userAvatar: _avatar,
                      userBanner: _banner,
                      displayName: _draftDisplayName.isEmpty
                          ? selectedClient.self?.displayName ??
                              selectedClient.identifier
                          : _draftDisplayName,
                      identifier: selectedClient.self?.identifier ??
                          selectedClient.identifier,
                      userColor: _currentProfileSwatchColor(context),
                      isSelf: true,
                      presence: _previewPresence(),
                      pronouns: _parsePronouns(_pronounsController.text),
                      badges: _badges,
                      bio: _previewBio(context),
                      timezone: _draftShareTimezone ? _draftTimezone : null,
                      width: 460,
                      bannerHeight: 150,
                      maxBioHeight: 110,
                      doSafeArea: false,
                      showMessageButton: false,
                      showActionsMenu: false,
                      showEditOverlays: true,
                      profileBackgroundColor: profileAccent,
                      onSetBanner: _setBanner,
                      onSetAvatar: _setAvatar,
                      editBadges: _editBadges,
                      setBio: _openBioDialog,
                      clearBio: () async {
                        setState(() {
                          _bioController.clear();
                        });
                      },
                      setPreviewColor: _setProfileColor,
                      setPreviewBrightness: _setProfileBrightness,
                      savePreviewTheme: _savePendingChanges,
                      setColorOverride: (color) async =>
                          _setLocalColorOverride(color),
                      hasColorOverride: _draftLocalColorOverride != null,
                      showSource:
                          preferences.developerMode.value ? _showSource : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorControls(BuildContext context, Client selectedClient) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProfileColorOption(
          description: "Select Profile color and Display Name text color",
          color: _profileThemeSwatchColor(context),
          onTap: () => _showColorMenu(context, selectedClient),
        ),
        const SizedBox(height: 12),
        _ProfileColorOption(
          description:
              "Select color override for display name. This is only visible to you.",
          color: _localColorOverrideSwatchColor(context),
          muted: _draftLocalColorOverride == null,
          onTap: () => _showColorMenu(context, selectedClient),
        ),
      ],
    );
  }

  Widget _buildUnsavedChangesBar(BuildContext context) {
    final theme = Theme.of(context);

    return Positioned(
      left: 0,
      right: 18,
      bottom: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 18,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  "You have unsaved changes.",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              tiamat.Button.secondary(
                key: AccountProfileSettingsTab.cancelChangesKey,
                text: "Cancel",
                onTap: _isSaving ? null : _resetDraftFromLoaded,
              ),
              const SizedBox(width: 8),
              tiamat.Button(
                key: AccountProfileSettingsTab.saveChangesKey,
                text: "Save",
                isLoading: _isSaving,
                onTap: _isSaving ? null : _savePendingChanges,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showColorMenu(
    BuildContext context,
    Client selectedClient,
  ) async {
    await AdaptiveDialog.show<void>(
      context,
      title: "Set Color Override",
      scrollable: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            void update(VoidCallback change) {
              setState(change);
              setDialogState(() {});
            }

            return SizedBox(
              width: 380,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Profile accent",
                    style: Theme.of(dialogContext).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final color in _profileColors)
                        _ColorSwatch(
                          color: color,
                          selected: color == _draftProfileColor,
                          onTap: () => update(() => _setProfileColor(color)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Local display override",
                    style: Theme.of(dialogContext).textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final color in _profileColors)
                        _ColorSwatch(
                          color: color,
                          selected: color == _draftLocalColorOverride,
                          onTap: () => update(
                            () => _setLocalColorOverride(color),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      tiamat.Button.secondary(
                        text: "Use light profile",
                        onTap: () => update(() {
                          unawaited(_setProfileBrightness(Brightness.light));
                        }),
                      ),
                      tiamat.Button.secondary(
                        text: "Use dark profile",
                        onTap: () => update(() {
                          unawaited(_setProfileBrightness(Brightness.dark));
                        }),
                      ),
                      tiamat.Button.secondary(
                        text: "Clear override",
                        onTap: () => update(
                          () => _setLocalColorOverride(null),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget? _previewBio(BuildContext context) {
    final text = _draftBio;
    if (text.isEmpty) return null;

    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
          ),
    );
  }

  UserPresence? _previewPresence() {
    final status = _draftStatus;
    if (status.isEmpty) return null;

    return UserPresence(
      UserPresenceStatus.online,
      message: UserPresenceMessage(status, PresenceMessageType.userCustom),
    );
  }

  ThemeData _previewTheme(BuildContext context) {
    final theme = Theme.of(context);
    final seedColor =
        _draftProfileColor ?? _loadedProfileColor ?? _profile?.defaultColor;
    final brightness = _draftProfileBrightness ?? theme.colorScheme.brightness;

    if (seedColor == null) return theme;

    return theme.copyWith(
      colorScheme: ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: brightness,
        dynamicSchemeVariant: DynamicSchemeVariant.content,
      ),
    );
  }

  Future<void> _selectClient(Client client, {bool refresh = true}) async {
    setState(() {
      _selectedClient = client;
      _isLoadingProfile = true;
      _profile = null;
      _avatar = client.self?.avatar;
      _banner = null;
      _badges = const [];
      _loadedDisplayName = client.self?.displayName ?? "";
      _loadedPronounsText = "";
      _loadedStatus = "";
      _loadedBio = "";
      _loadedShareTimezone = false;
      _loadedTimezone = null;
      _loadedProfileColor = null;
      _loadedProfileBrightness = null;
      _loadedLocalColorOverride = null;
      _resetDraftFromLoaded(updateState: false);
    });

    if (refresh) {
      await _loadSelectedProfile();
    } else {
      unawaited(_loadSelectedProfile());
    }
  }

  Future<void> _loadSelectedProfile() async {
    final client = _selectedClient;
    final component = client?.getComponent<UserProfileComponent>();
    final userId = client?.self?.identifier;

    if (client == null || component == null || userId == null) {
      if (mounted) {
        setState(() {
          _isLoadingProfile = false;
        });
      }
      return;
    }

    final token = ++_profileLoadToken;
    setState(() {
      _isLoadingProfile = true;
    });

    final profile = await component.getProfile(userId);
    final profileBadges =
        profile is ProfileWithBadges ? profile as ProfileWithBadges : null;
    final profilePronouns =
        profile is ProfileWithPronouns ? profile as ProfileWithPronouns : null;
    final profilePresence =
        profile is ProfileWithPresence ? profile as ProfileWithPresence : null;
    final profileBio =
        profile is ProfileWithBio ? profile as ProfileWithBio : null;
    final profileColor = profile is ProfileWithColorScheme
        ? profile as ProfileWithColorScheme
        : null;
    final profileTimezone =
        profile is ProfileWithTimezone ? profile as ProfileWithTimezone : null;
    final badges = profileBadges != null
        ? await profileBadges.getBadges()
        : <ProfileBadge>[];
    final localColorOverride = client
        .getComponent<UserColorComponent>()
        ?.getColor(client.self?.identifier ?? client.identifier);

    if (!mounted || token != _profileLoadToken) return;

    setState(() {
      _profile = profile;
      _avatar = profile.avatar ?? client.self?.avatar;
      _banner = profile.banner;
      _badges = badges;
      _loadedDisplayName = profile.displayName;
      _loadedPronounsText = profilePronouns?.pronouns.join(", ") ?? "";
      _loadedStatus = profilePresence?.precence?.message?.message ?? "";
      _loadedBio = profileBio?.plaintextBio ?? "";
      _loadedTimezone = profileTimezone?.timezone;
      _loadedShareTimezone = _loadedTimezone != null;
      _loadedProfileColor = profileColor?.color;
      _loadedProfileBrightness = profileColor?.brightness;
      _loadedLocalColorOverride = localColorOverride;
      _isLoadingProfile = false;
      _resetDraftFromLoaded(updateState: false);
    });
  }

  void _resetDraftFromLoaded({bool updateState = true}) {
    void reset() {
      _displayNameController.text = _loadedDisplayName;
      _pronounsController.text = _loadedPronounsText;
      _statusController.text = _loadedStatus;
      _bioController.text = _loadedBio;
      _draftShareTimezone = _loadedShareTimezone;
      _draftTimezone = _loadedTimezone;
      _draftProfileColor = _loadedProfileColor;
      _draftProfileBrightness = _loadedProfileBrightness;
      _draftLocalColorOverride = _loadedLocalColorOverride;
    }

    if (updateState && mounted) {
      setState(reset);
    } else {
      reset();
    }
  }

  Future<void> _savePendingChanges() async {
    final client = _selectedClient;
    final component = client?.getComponent<UserProfileComponent>();
    if (client == null || component == null || !_hasUnsavedChanges) return;

    await _runProfileSave(() async {
      if (_draftDisplayName.isNotEmpty &&
          _draftDisplayName != _loadedDisplayName) {
        await client.setDisplayName(_draftDisplayName);
      }

      if (_draftPronounsText != _loadedPronounsText) {
        await component.setPronouns(_parsePronouns(_pronounsController.text));
      }

      if (_draftStatus != _loadedStatus) {
        await component.setStatus(_draftStatus.isEmpty ? null : _draftStatus);
        await client.getComponent<UserPresenceComponent>()?.setStatus(
              UserPresenceStatus.online,
              message: _draftStatus.isEmpty ? null : _draftStatus,
              clearMessage: _draftStatus.isEmpty,
            );
      }

      if (_draftBio != _loadedBio) {
        if (_draftBio.isEmpty) {
          await component.removeBio();
        } else {
          await component.setBio(_draftBio);
        }
      }

      if (_draftProfileColor != _loadedProfileColor ||
          _draftProfileBrightness != _loadedProfileBrightness) {
        await component.setProfileColorScheme(
          _draftProfileColor ??
              _loadedProfileColor ??
              Theme.of(context).colorScheme.primary,
          _draftProfileBrightness ?? Theme.of(context).colorScheme.brightness,
        );
      }

      if (_draftShareTimezone != _loadedShareTimezone ||
          _draftTimezone != _loadedTimezone) {
        if (_draftShareTimezone && _draftTimezone != null) {
          await component.setTimezone(_draftTimezone!);
        } else {
          await component.removeTimezone();
        }
      }

      if (_draftLocalColorOverride != _loadedLocalColorOverride) {
        final userId = client.self?.identifier ?? client.identifier;
        await client
            .getComponent<UserColorComponent>()
            ?.setColor(userId, _draftLocalColorOverride);
      }
    });
  }

  Future<void> _openBioDialog() async {
    final client = _selectedClient;
    if (client == null) return;

    await AdaptiveDialog.show(context, builder: (context) {
      return SizedBox(
        width: 600,
        child: MessageInput(
          hintText: promptProfileWriteBioHint,
          initialText: _bioController.text,
          showAttachmentButton: false,
          client: client,
          showGifSearch: false,
          disableEnterToSend: true,
          compact: true,
          enableKeyboardAdapter: false,
          availibleEmoticons:
              client.getComponent<EmoticonComponent>()?.availablePacks,
          onSendMessage: (message, {overrideClient}) {
            setState(() {
              _bioController.text = message;
            });
            Navigator.of(context).pop();
            return MessageInputSendResult.success;
          },
        ),
      );
    });
  }

  Future<void> _setAvatar() async {
    final client = _selectedClient;
    if (client == null) return;

    final result = await PickerUtils.pickImageAndCrop(context, aspectRatio: 1);
    if (result == null) return;

    setState(() {
      _avatar = Image.memory(result).image;
    });

    await _runImmediateProfileAction(() => client.setAvatar(result, ""));
  }

  Future<void> _setBanner() async {
    final component = _selectedClient?.getComponent<UserProfileComponent>();
    if (component == null) return;

    final action = await ImageSelectDialog.show(context, image: _banner);
    if (!mounted) return;

    if (action == ImageEditAction.remove) {
      setState(() {
        _banner = null;
      });
      await _runImmediateProfileAction(component.removeBanner);
      return;
    }

    if (action != ImageEditAction.pick) return;

    final result =
        await PickerUtils.pickImageAndCrop(context, aspectRatio: 700 / 230);
    if (result == null) return;

    setState(() {
      _banner = Image.memory(result).image;
    });

    await _runImmediateProfileAction(() => component.setBanner(result));
  }

  void _setProfileColor(Color color) {
    _draftProfileColor = color;
    _draftProfileBrightness ??= Theme.of(context).colorScheme.brightness;
  }

  Future<void> _setProfileBrightness(Brightness brightness) async {
    _draftProfileColor ??= _loadedProfileColor ??
        _profile?.defaultColor ??
        Theme.of(context).colorScheme.primary;
    _draftProfileBrightness = brightness;
  }

  void _setLocalColorOverride(Color? color) {
    _draftLocalColorOverride = color;
  }

  Future<void> _setTimezoneSharing(bool value) async {
    if (!value) {
      setState(() {
        _draftShareTimezone = false;
        _draftTimezone = null;
      });
      return;
    }

    final timezone = _loadedTimezone ??
        (await FlutterTimezone.getLocalTimezone()).identifier;
    if (!mounted) return;

    setState(() {
      _draftShareTimezone = true;
      _draftTimezone = timezone;
    });
  }

  Future<void> _editBadges() async {
    final component = _selectedClient?.getComponent<UserProfileComponent>();
    if (component == null) return;

    final availableBadges = await component.getAvailableBadges();
    if (!mounted) return;

    if (availableBadges.isEmpty) {
      await AdaptiveDialog.show(
        context,
        title: labelProfileYourBadges,
        builder: (context) => SizedBox(
          height: 180,
          child: Center(
            child: tiamat.Text.labelLow(labelProfileNoBadges),
          ),
        ),
      );
      return;
    }

    final selectedBadges = await AdaptiveDialog.pickMultiple<ProfileBadge>(
      context,
      selected: _badges,
      items: availableBadges,
      title: labelProfileYourBadges,
      itemBuilder: (context, item) {
        return Row(
          children: [
            SizedBox(width: 30, height: 30, child: Image(image: item.image)),
            const SizedBox(width: 8),
            tiamat.Text.labelLow(item.body),
          ],
        );
      },
    );

    if (selectedBadges == null) return;

    setState(() {
      _badges = selectedBadges;
    });
    await _runImmediateProfileAction(
      () => component.setProfileBadges(selectedBadges),
    );
  }

  void _showSource() {
    final profile = _profile;
    if (profile == null) return;

    AdaptiveDialog.show(
      context,
      title: "Source",
      builder: (context) {
        return SizedBox(
          width: 1000,
          child: SelectionArea(
            child: Text(profile.source),
          ),
        );
      },
    );
  }

  Future<void> _openAddAccount(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LoginPage(
          canNavigateBack: true,
          onSuccess: (_) {
            Navigator.of(context).pop();
          },
        ),
      ),
    );

    if (!mounted || widget.clientManager.clients.isEmpty) return;
    final newClient = widget.clientManager.clients.last;
    SettingsAccountScope.maybeRead(context)?.selectClient(newClient);
    await _selectClient(newClient);
  }

  Future<void> _runProfileSave(Future<void> Function() save) async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      await save();
      await _loadSelectedProfile();
    } catch (error, trace) {
      if (mounted) {
        await AdaptiveDialog.showError(context, error, trace);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _runImmediateProfileAction(Future<void> Function() save) async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      await save();
    } catch (error, trace) {
      if (mounted) {
        await AdaptiveDialog.showError(context, error, trace);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Color _currentProfileSwatchColor(BuildContext context) {
    return _draftLocalColorOverride ?? _profileThemeSwatchColor(context);
  }

  Color _profileThemeSwatchColor(BuildContext context) {
    return _draftProfileColor ??
        _loadedProfileColor ??
        _profile?.defaultColor ??
        Theme.of(context).colorScheme.primary;
  }

  Color _localColorOverrideSwatchColor(BuildContext context) {
    return _draftLocalColorOverride ?? _profileThemeSwatchColor(context);
  }

  List<String> _parsePronouns(String value) {
    return value
        .split(",")
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
  }

  static const List<Color> _profileColors = [
    Color(0xFF2196F3),
    Color(0xFF00BCD4),
    Color(0xFF009688),
    Color(0xFF4CAF50),
    Color(0xFFFFC107),
    Color(0xFFFF9800),
    Color(0xFFE91E63),
    Color(0xFF9C27B0),
    Color(0xFFFF3B30),
    Color(0xFF64FFDA),
    Color(0xFF536DFE),
    Color(0xFFFF2DCE),
  ];
}

class _ProfileTextField extends StatelessWidget {
  const _ProfileTextField({
    required this.controller,
    this.hintText,
    this.minLines,
    this.maxLines = 1,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? hintText;
  final int? minLines;
  final int? maxLines;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: settingsHintTextStyle(context),
        isDense: true,
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.24),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.24),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: theme.colorScheme.primary.withValues(alpha: 0.72),
          ),
        ),
      ),
    );
  }
}

class _ProfileColorOption extends StatelessWidget {
  const _ProfileColorOption({
    required this.description,
    required this.color,
    required this.onTap,
    this.muted = false,
  });

  final String description;
  final Color color;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
              height: 1.25,
              letterSpacing: 0,
            ),
          ),
        ),
        const SizedBox(width: 18),
        _ColorSwatch(
          color: muted
              ? Color.alphaBlend(
                  theme.colorScheme.surfaceContainerHigh
                      .withValues(alpha: 0.35),
                  color,
                )
              : color,
          size: 52,
          selected: true,
          onTap: onTap,
        ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.onTap,
    this.size = 34,
    this.selected = false,
  });

  final Color color;
  final VoidCallback onTap;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: selected
              ? theme.colorScheme.onSurface.withValues(alpha: 0.72)
              : theme.colorScheme.outline.withValues(alpha: 0.16),
          width: selected ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(7),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(width: size, height: size),
          ),
        ),
      ),
    );
  }
}
