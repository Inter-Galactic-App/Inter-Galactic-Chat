import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/client/components/activity/sources/local_media/local_media_activity_source.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_activity_source.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_api_client.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_connection_service.dart';
import 'package:intergalactic/client/components/activity/sources/steam/steam_api_client.dart';
import 'package:intergalactic/client/components/activity/sources/steam/steam_activity_source.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/config/preferences/bool_preference.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/boolean_toggle.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

String _toggleSemanticAction(bool value) => value ? 'Turn off' : 'Turn on';

class ActivitySettingsPage extends StatefulWidget {
  const ActivitySettingsPage({super.key});

  @override
  State<ActivitySettingsPage> createState() => _ActivitySettingsPageState();
}

class _ActivitySettingsPageState extends State<ActivitySettingsPage> {
  StreamSubscription<SpotifyConnectionStatus>? _spotifyStatusSubscription;
  StreamSubscription<String?>? _steamConnectionIssueSubscription;
  SpotifyConnectionStatus _spotifyStatus = spotifyConnectionService.status;
  String? _steamConnectionIssue;
  final SpotifyApiClient _spotifyApiClient = SpotifyApiClient();
  final SteamApiClient _steamApiClient = SteamApiClient();
  String? _spotifyDisplayName;
  String? _steamDisplayName;
  int _displayNameGeneration = 0;

  String get titleActivityPrivacy => Intl.message(
    'Activity privacy',
    desc: 'Header for rich presence privacy settings',
    name: 'titleActivityPrivacy',
  );

  String get titleActivitySources => Intl.message(
    'Connections',
    desc: 'Header for rich presence account connection settings',
    name: 'titleActivitySources',
  );

  String get titleActivityDeveloperTools => Intl.message(
    'Activity developer tools',
    desc: 'Header for rich presence developer settings',
    name: 'titleActivityDeveloperTools',
  );

  String get showActivityLocallyTitle => Intl.message(
    'Show activity locally',
    desc: 'Toggle title for showing local activity cards',
    name: 'showActivityLocallyTitle',
  );

  String get showActivityLocallyDescription => Intl.message(
    'Show the current activity card near the account panel.',
    desc: 'Toggle description for showing local activity cards',
    name: 'showActivityLocallyDescription',
  );

  String get hideCurrentActivityTitle => Intl.message(
    'Hide current activity',
    desc: 'Toggle title for hiding current rich presence activity',
    name: 'hideCurrentActivityTitle',
  );

  String get hideCurrentActivityDescription => Intl.message(
    'Temporarily suppress the active local activity card.',
    desc: 'Toggle description for hiding current rich presence activity',
    name: 'hideCurrentActivityDescription',
  );

  String get localMediaControlsTitle => Intl.message(
    'Apple Music controls',
    desc: 'Toggle title for iOS local media playback controls',
    name: 'localMediaControlsTitle',
  );

  String get localMediaControlsDescription => Intl.message(
    'Show a compact iPhone media card for Apple Music and local media-library playback.',
    desc: 'Toggle description for iOS local media playback controls',
    name: 'localMediaControlsDescription',
  );

  String get publishBasicActivityStatusTitle => Intl.message(
    'Publish Matrix status',
    desc: 'Toggle title for publishing rich presence to Matrix status',
    name: 'publishBasicActivityStatusTitle',
  );

  String get publishBasicActivityStatusDescription => Intl.message(
    'Share a simple Listening or Playing line through Matrix presence.',
    desc: 'Toggle description for publishing rich presence to Matrix status',
    name: 'publishBasicActivityStatusDescription',
  );

  String get spotifyConfiguredDialogTitle => Intl.message(
    'Spotify setup',
    desc: 'Title for the multi-step Spotify activity setup dialog',
    name: 'spotifyConfiguredDialogTitle',
  );

  String get demoActivityTitle => Intl.message(
    'Demo activity',
    desc: 'Toggle title for the rich presence demo source',
    name: 'demoActivityTitle',
  );

  String get demoActivityDescription => Intl.message(
    'Show a mock music activity for validating layout and controls.',
    desc: 'Toggle description for the rich presence demo source',
    name: 'demoActivityDescription',
  );

  String get steamIdDialogTitle => Intl.message(
    'Steam ID64',
    desc: 'Title for the dialog that stores a Steam ID64',
    name: 'steamIdDialogTitle',
  );

  String get steamIdDialogPlaceholder => Intl.message(
    '76561198000000000',
    desc: 'Placeholder Steam ID64 example',
    name: 'steamIdDialogPlaceholder',
  );

  String get steamIdDialogDescription => Intl.message(
    'Enter the SteamID64 for the account whose current game should appear. Steam profile game details must be visible to the Steam Web API.',
    desc: 'Description for the Steam ID64 rich presence dialog',
    name: 'steamIdDialogDescription',
  );

  @override
  void initState() {
    super.initState();
    _spotifyStatusSubscription = spotifyConnectionService.onStatusChanged
        .listen((status) {
          if (!mounted) {
            return;
          }

          setState(() {
            _spotifyStatus = status;
          });
        });
    _watchSteamConnectionIssue();
    unawaited(_refreshSpotifyStatus());
    unawaited(_refreshConnectionDisplayNames());
  }

  @override
  void dispose() {
    _spotifyStatusSubscription?.cancel();
    _steamConnectionIssueSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spotifyConfigured = spotifyConnectionService.authConfig.isConfigured;
    final steamId = preferences.activitySteamId.value?.trim();
    final steamConfigured = steamId != null && steamId.isNotEmpty;

    return Column(
      children: [
        SettingsSection(
          title: titleActivitySources,
          children: [
            Column(
              children: [
                if (PlatformUtils.isIOS)
                  BooleanPreferenceToggle(
                    preference: preferences.activityShowLocalMediaControls,
                    title: localMediaControlsTitle,
                    description: localMediaControlsDescription,
                    onChanged: (_) => _notifyLocalMediaChanged(),
                  ),
                ActivityConnectionSetupRow(
                  icon: const _ActivityBrandBadge(
                    icon: Icons.music_note,
                    color: Color(0xFF1DB954),
                  ),
                  title: 'Spotify',
                  description: _spotifyConnectionSummary(
                    configured: spotifyConfigured,
                  ),
                  actionLabel: spotifyConfigured ? 'Configure' : 'Setup',
                  onAction: _setSpotifyDeveloperInfo,
                ),
                if (!BuildConfig.MOBILE)
                  ActivityConnectionSetupRow(
                    icon: const _ActivityBrandBadge(
                      icon: Icons.sports_esports,
                      color: Color(0xFF1B2838),
                    ),
                    title: 'Steam',
                    description: _steamConnectionSummary(
                      configured: steamConfigured,
                    ),
                    actionLabel: steamConfigured ? 'Configure' : 'Setup',
                    onAction: _setSteamId,
                  ),
              ],
            ),
          ],
        ),
        if (spotifyConfigured || steamConfigured)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            child: Column(
              children: [
                if (spotifyConfigured)
                  ActivityConnectionCard(
                    icon: const _ActivityBrandBadge(
                      icon: Icons.music_note,
                      color: Color(0xFF1DB954),
                      size: 48,
                    ),
                    accountName: _spotifyDisplayName ?? _spotifyAccountLabel(),
                    providerName: 'Spotify',
                    statusText: _spotifyStatus.message,
                    onDisconnect: _disconnectSpotifyAccount,
                    children: [
                      _SpotifyConnectionToggle(
                        connected: _spotifyStatus.isConnected,
                        busy: _spotifyStatus.isBusy,
                        onChanged: (value) =>
                            value ? _connectSpotify() : _disconnectSpotify(),
                      ),
                      ActivityCardPreferenceToggle(
                        preference: preferences.activityShowSpotify,
                        title: 'Publish to Status',
                        description:
                            'Allow Spotify activity to appear when activity publishing is enabled.',
                        onChanged: (_) => activityService.refreshSettings(),
                      ),
                    ],
                  ),
                if (steamConfigured)
                  ActivityConnectionCard(
                    icon: const _ActivityBrandBadge(
                      icon: Icons.sports_esports,
                      color: Color(0xFF1B2838),
                      size: 48,
                    ),
                    accountName: _steamDisplayName ?? steamId,
                    providerName: 'Steam',
                    statusText: _steamConnectionIssue,
                    onDisconnect: _clearSteamId,
                    children: [
                      ActivityCardPreferenceToggle(
                        preference: preferences.activityShowGame,
                        title: 'Publish to Status',
                        description:
                            'Allow Steam game activity to appear when activity publishing is enabled.',
                        onChanged: (_) => activityService.refreshSettings(),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        SettingsSection(
          title: titleActivityPrivacy,
          children: [
            Column(
              children: [
                BooleanPreferenceToggle(
                  preference: preferences.activityShowLocally,
                  title: showActivityLocallyTitle,
                  description: showActivityLocallyDescription,
                  onChanged: (_) => activityService.refreshSettings(),
                ),
                BooleanPreferenceToggle(
                  preference: preferences.activityHideCurrent,
                  title: hideCurrentActivityTitle,
                  description: hideCurrentActivityDescription,
                  onChanged: (_) => activityService.refreshSettings(),
                ),
                BooleanPreferenceToggle(
                  preference: preferences.activityPublishBasicStatus,
                  title: publishBasicActivityStatusTitle,
                  description: publishBasicActivityStatusDescription,
                  onChanged: (_) => activityService.refreshSettings(),
                ),
              ],
            ),
          ],
        ),
        if (preferences.developerMode.value) ...[
          SettingsSection(
            title: titleActivityDeveloperTools,
            showDivider: false,
            children: [
              BooleanPreferenceToggle(
                preference: preferences.activityMockSourceEnabled,
                title: demoActivityTitle,
                description: demoActivityDescription,
                onChanged: (_) => activityService.refreshSettings(),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _refreshSpotifyStatus() async {
    final status = await spotifyConnectionService.refreshStatus();
    if (!mounted) {
      return;
    }

    setState(() {
      _spotifyStatus = status;
    });
    unawaited(_refreshConnectionDisplayNames());
  }

  void _watchSteamConnectionIssue() {
    final source = activityService.sources
        .whereType<SteamActivitySource>()
        .firstOrNull;
    _steamConnectionIssue = source?.connectionIssue;
    _steamConnectionIssueSubscription = source?.onConnectionIssueChanged.listen(
      (issue) {
        if (mounted) {
          setState(() => _steamConnectionIssue = issue);
        }
      },
    );
  }

  Future<void> _connectSpotify() async {
    await preferences.activityShowSpotify.set(true);
    await preferences.activityShowLocally.set(true);
    final status = await spotifyConnectionService.connect();
    for (final source in activityService.sources) {
      if (source is SpotifyActivitySource) {
        source.notifySettingsChanged();
      }
    }
    activityService.refreshSettings();

    if (mounted) {
      setState(() {
        _spotifyStatus = status;
      });
      unawaited(_refreshConnectionDisplayNames());
    }
  }

  void _notifyLocalMediaChanged() {
    for (final source in activityService.sources) {
      if (source is LocalMediaActivitySource) {
        source.notifySettingsChanged();
      }
    }
    activityService.refreshSettings();
  }

  Future<void> _disconnectSpotify() async {
    await spotifyConnectionService.disconnect();
    for (final source in activityService.sources) {
      if (source is SpotifyActivitySource) {
        source.notifySettingsChanged();
      }
    }
    activityService.refreshSettings();
  }

  Future<void> _disconnectSpotifyAccount() async {
    await preferences.activityShowSpotify.set(false);
    await _disconnectSpotify();
    if (mounted) {
      setState(() {
        _spotifyDisplayName = null;
      });
    }
  }

  Future<void> _setSpotifyDeveloperInfo() async {
    final previousConfig = spotifyConnectionService.authConfig;
    final currentConfig = spotifyConnectionService.authConfig;
    final result = await AdaptiveDialog.show<_SpotifySetupResult>(
      context,
      title: spotifyConfiguredDialogTitle,
      scrollable: false,
      builder: (_) => _SpotifySetupDialog(
        clientId:
            preferences.activitySpotifyClientId.value ?? currentConfig.clientId,
        redirectUri:
            preferences.activitySpotifyRedirectUri.value ??
            (currentConfig.redirectUri.trim().isNotEmpty
                ? currentConfig.redirectUri
                : _defaultSpotifyRedirectUri),
        defaultRedirectUri: _defaultSpotifyRedirectUri,
      ),
    );
    if (!mounted || result == null) {
      return;
    }

    final clientId = result.clientId.trim();
    final redirectUri = result.redirectUri.trim();
    await preferences.activitySpotifyClientId.set(_emptyToNull(clientId));
    await preferences.activitySpotifyRedirectUri.set(_emptyToNull(redirectUri));
    if (clientId.isEmpty && redirectUri.isEmpty) {
      await preferences.activitySpotifyLastBuildClientId.set(null);
      await preferences.activitySpotifyLastBuildRedirectUri.set(null);
    }

    final nextConfig = spotifyConnectionService.authConfig;
    if (previousConfig.clientId != nextConfig.clientId ||
        previousConfig.redirectUri != nextConfig.redirectUri) {
      await spotifyConnectionService.disconnect();
    }

    _refreshSpotifySource();
    final status = await spotifyConnectionService.refreshStatus();
    if (!mounted) {
      return;
    }

    setState(() {
      _spotifyStatus = status;
    });
    unawaited(_refreshConnectionDisplayNames());
  }

  String? _emptyToNull(String value) => value.isEmpty ? null : value;

  String get _defaultSpotifyRedirectUri =>
      spotifyConnectionService.authConfig.redirectUri.trim().isNotEmpty
      ? spotifyConnectionService.authConfig.redirectUri
      : 'intergalactic-spotify://callback';

  void _refreshSpotifySource() {
    for (final source in activityService.sources) {
      if (source is SpotifyActivitySource) {
        source.notifySettingsChanged();
      }
    }
    activityService.refreshSettings();
  }

  Future<void> _setSteamId() async {
    final result = await AdaptiveDialog.show<_SteamSetupResult>(
      context,
      title: steamIdDialogTitle,
      scrollable: false,
      builder: (_) => _SteamSetupDialog(
        steamId: preferences.activitySteamId.value,
        placeholder: steamIdDialogPlaceholder,
        description: steamIdDialogDescription,
      ),
    );
    if (!mounted || result == null) {
      return;
    }

    final steamId = result.steamId.trim();
    await preferences.activitySteamId.set(steamId.isEmpty ? null : steamId);
    if (!mounted) {
      return;
    }

    if (steamId.isNotEmpty) {
      await preferences.activityShowGame.set(true);
      if (!mounted) {
        return;
      }

      await preferences.activityShowLocally.set(true);
      if (!mounted) {
        return;
      }
    }

    _refreshSteamSource();
    unawaited(_refreshConnectionDisplayNames());
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  Future<void> _clearSteamId() async {
    await preferences.activitySteamId.set(null);
    _refreshSteamSource();
    if (mounted) {
      setState(() {
        _steamDisplayName = null;
      });
    }
  }

  void _refreshSteamSource() {
    for (final source in activityService.sources) {
      if (source is SteamActivitySource) {
        source.notifySettingsChanged();
      }
    }
    activityService.refreshSettings();
  }

  String _spotifyConnectionSummary({required bool configured}) {
    if (!configured) {
      return 'Set up a Spotify developer app to connect playback activity.';
    }

    if (_spotifyStatus.isConnected) {
      return 'Connected on this device.';
    }

    return _spotifyStatus.message ?? 'Ready to connect Spotify.';
  }

  String _steamConnectionSummary({required bool configured}) {
    if (!steamActivityApiBaseUrl().trim().isNotEmpty) {
      return configured
          ? 'Steam ID saved. Configure the activity proxy to poll game status.'
          : 'Set a SteamID64 to prepare game activity.';
    }

    return configured
        ? 'Steam game activity is configured.'
        : 'Set a SteamID64 to show current game activity.';
  }

  String _spotifyAccountLabel() {
    if (_spotifyStatus.isConnected) {
      return 'Connected account';
    }

    if (spotifyConnectionService.authConfig.isConfigured) {
      return 'Ready to connect';
    }

    return 'Not configured';
  }

  Future<void> _refreshConnectionDisplayNames() async {
    final generation = ++_displayNameGeneration;
    final names = await Future.wait<String?>([
      _loadSpotifyDisplayName(),
      _loadSteamDisplayName(),
    ]);
    if (!mounted || generation != _displayNameGeneration) {
      return;
    }

    setState(() {
      _spotifyDisplayName = names[0];
      _steamDisplayName = names[1];
    });
  }

  Future<String?> _loadSpotifyDisplayName() async {
    if (!_spotifyStatus.isConnected) {
      return null;
    }

    try {
      final tokens = await spotifyTokenStore.read();
      if (tokens == null) {
        return null;
      }

      return _spotifyApiClient.getCurrentUserDisplayName(tokens.accessToken);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _loadSteamDisplayName() async {
    final endpoint = Uri.tryParse(steamActivityApiBaseUrl().trim());
    final steamId = preferences.activitySteamId.value?.trim() ?? '';
    if (endpoint == null ||
        !endpoint.hasScheme ||
        endpoint.host.isEmpty ||
        steamId.isEmpty) {
      return null;
    }

    try {
      final summary = await _steamApiClient.getPlayerSummary(
        endpoint: endpoint,
        steamId: steamId,
      );
      final personaName = summary?.personaName?.trim();
      return personaName != null && personaName.isNotEmpty ? personaName : null;
    } catch (_) {
      return null;
    }
  }
}

class ActivityConnectionSetupRow extends StatelessWidget {
  const ActivityConnectionSetupRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.onAction,
    super.key,
  });

  final Widget icon;
  final String title;
  final String description;
  final String actionLabel;
  final Future<void> Function() onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final stackAction = constraints.maxWidth < 420;
        final label = Row(
          children: [
            icon,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                ],
              ),
            ),
          ],
        );

        final action = ActivitySetupActionButton(
          text: actionLabel,
          onTap: onAction,
        );

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: stackAction
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    label,
                    const SizedBox(height: 10),
                    Align(alignment: Alignment.centerRight, child: action),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: label),
                    const SizedBox(width: 16),
                    action,
                  ],
                ),
        );
      },
    );
  }
}

class ActivitySetupActionButton extends StatelessWidget {
  const ActivitySetupActionButton({
    required this.text,
    required this.onTap,
    super.key,
  });

  final String text;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => unawaited(onTap()),
        child: Container(
          width: 124,
          height: 40,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              text,
              maxLines: 1,
              softWrap: false,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurface,
                fontSize: 13,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ActivityConnectionCard extends StatelessWidget {
  const ActivityConnectionCard({
    required this.icon,
    required this.accountName,
    required this.providerName,
    required this.children,
    this.statusText,
    this.onDisconnect,
    super.key,
  });

  final Widget icon;
  final String accountName;
  final String providerName;
  final String? statusText;
  final Future<void> Function()? onDisconnect;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.75),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        child: Column(
          children: [
            Row(
              children: [
                icon,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        accountName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        providerName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                          letterSpacing: 0,
                        ),
                      ),
                      if (statusText != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          statusText!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                            height: 1.2,
                            letterSpacing: 0,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Disconnect',
                  icon: const Icon(Icons.close),
                  onPressed: onDisconnect == null
                      ? null
                      : () => unawaited(onDisconnect!()),
                ),
              ],
            ),
            if (children.isNotEmpty) ...[
              const SizedBox(height: 12),
              Divider(
                color: theme.colorScheme.outline.withValues(alpha: 0.7),
                height: 1,
                thickness: 1,
              ),
              const SizedBox(height: 4),
              ...children,
            ],
          ],
        ),
      ),
    );
  }
}

class ActivityCardPreferenceToggle extends StatefulWidget {
  const ActivityCardPreferenceToggle({
    required this.preference,
    required this.title,
    this.description,
    this.onChanged,
    super.key,
  });

  final BoolPreference preference;
  final String title;
  final String? description;
  final FutureOr<void> Function(bool)? onChanged;

  @override
  State<ActivityCardPreferenceToggle> createState() =>
      _ActivityCardPreferenceToggleState();
}

class _ActivityCardPreferenceToggleState
    extends State<ActivityCardPreferenceToggle> {
  StreamSubscription<bool>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant ActivityCardPreferenceToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(widget.preference, oldWidget.preference)) {
      return;
    }

    _subscription?.cancel();
    _subscribe();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _subscribe() {
    _subscription = widget.preference.onChanged.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _ActivityCardToggleRow(
      title: widget.title,
      description: widget.description,
      value: widget.preference.value,
      onChanged: (value) async {
        await widget.preference.set(value);
        await widget.onChanged?.call(value);
        if (mounted) {
          setState(() {});
        }
      },
    );
  }
}

class _SpotifyConnectionToggle extends StatelessWidget {
  const _SpotifyConnectionToggle({
    required this.connected,
    required this.busy,
    required this.onChanged,
  });

  final bool connected;
  final bool busy;
  final Future<void> Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    return _ActivityCardToggleRow(
      title: 'Playback Controls',
      description: connected
          ? 'Spotify playback controls are available from activity cards.'
          : 'Connect Spotify to enable playback controls.',
      value: connected,
      onChanged: busy ? null : onChanged,
    );
  }
}

class _ActivityCardToggleRow extends StatelessWidget {
  const _ActivityCardToggleRow({
    required this.title,
    required this.value,
    this.description,
    this.onChanged,
  });

  final String title;
  final String? description;
  final bool value;
  final FutureOr<void> Function(bool)? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    description!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      height: 1.2,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          SettingsSwitchStateLabel(
            value: value,
            child: tiamat.Switch(
              state: value,
              onChanged: onChanged == null
                  ? null
                  : (next) => unawaited(Future.sync(() => onChanged!(next))),
              semanticLabel: title,
              semanticHint: description,
              semanticOnTapHint: _toggleSemanticAction(value),
              onLabel: settingsToggleStateLabel(true),
              offLabel: settingsToggleStateLabel(false),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityBrandBadge extends StatelessWidget {
  const _ActivityBrandBadge({
    required this.icon,
    required this.color,
    this.size = 40,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size / 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.24),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.54),
    );
  }
}

class _SpotifySetupResult {
  const _SpotifySetupResult({
    required this.clientId,
    required this.redirectUri,
  });

  final String clientId;
  final String redirectUri;
}

class _SteamSetupResult {
  const _SteamSetupResult({required this.steamId});

  final String steamId;
}

class _SpotifySetupDialog extends StatefulWidget {
  const _SpotifySetupDialog({
    required this.clientId,
    required this.redirectUri,
    required this.defaultRedirectUri,
  });

  final String clientId;
  final String redirectUri;
  final String defaultRedirectUri;

  @override
  State<_SpotifySetupDialog> createState() => _SpotifySetupDialogState();
}

class _SpotifySetupDialogState extends State<_SpotifySetupDialog> {
  late final TextEditingController _clientIdController;
  late final TextEditingController _redirectUriController;
  var _page = 0;

  @override
  void initState() {
    super.initState();
    _clientIdController = TextEditingController(text: widget.clientId);
    _redirectUriController = TextEditingController(text: widget.redirectUri);
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _redirectUriController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 540,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_page == 0) _buildInstructions(context) else _buildForm(context),
          const SizedBox(height: 18),
          Row(
            children: [
              if (_page > 0)
                Expanded(
                  child: tiamat.Button.secondary(
                    text: 'Back',
                    onTap: () => setState(() => _page = 0),
                  ),
                ),
              if (_page > 0) const SizedBox(width: 8),
              Expanded(
                child: tiamat.Button.secondary(
                  text: 'Cancel',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: tiamat.Button(
                  text: _page == 0 ? 'Next' : 'Save',
                  onTap: _page == 0
                      ? () => setState(() => _page = 1)
                      : () => Navigator.of(context).pop(
                          _SpotifySetupResult(
                            clientId: _clientIdController.text,
                            redirectUri: _redirectUriController.text,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInstructions(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Set up Spotify activity',
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w400,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Create a Spotify developer app, add the Inter Galactic redirect URI, then paste the Client ID on the next page. Inter Galactic uses PKCE, so never enter or share a Client Secret.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 12,
            height: 1.35,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 14),
        _SetupInstructionStep(
          number: '1',
          text:
              'Open https://developer.spotify.com/dashboard and create an app.',
        ),
        _SetupInstructionStep(
          number: '2',
          text: 'Add this Redirect URI exactly: ${widget.defaultRedirectUri}',
        ),
        const _SetupInstructionStep(
          number: '3',
          text: 'Copy the Client ID and continue here.',
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SetupTextField(
          controller: _clientIdController,
          label: 'Client ID',
          hint: 'Spotify Client ID',
        ),
        const SizedBox(height: 12),
        _SetupTextField(
          controller: _redirectUriController,
          label: 'Redirect URI',
          hint: widget.defaultRedirectUri,
        ),
      ],
    );
  }
}

class _SteamSetupDialog extends StatefulWidget {
  const _SteamSetupDialog({
    required this.steamId,
    required this.placeholder,
    required this.description,
  });

  final String? steamId;
  final String placeholder;
  final String description;

  @override
  State<_SteamSetupDialog> createState() => _SteamSetupDialogState();
}

class _SteamSetupDialogState extends State<_SteamSetupDialog> {
  late final TextEditingController _steamIdController;
  var _page = 0;

  @override
  void initState() {
    super.initState();
    _steamIdController = TextEditingController(text: widget.steamId);
  }

  @override
  void dispose() {
    _steamIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 540,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_page == 0) _buildInstructions(context) else _buildForm(context),
          const SizedBox(height: 18),
          Row(
            children: [
              if (_page > 0)
                Expanded(
                  child: tiamat.Button.secondary(
                    text: 'Back',
                    onTap: () => setState(() => _page = 0),
                  ),
                ),
              if (_page > 0) const SizedBox(width: 8),
              Expanded(
                child: tiamat.Button.secondary(
                  text: 'Cancel',
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: tiamat.Button(
                  text: _page == 0 ? 'Next' : 'Save',
                  onTap: _page == 0
                      ? () => setState(() => _page = 1)
                      : () => Navigator.of(context).pop(
                          _SteamSetupResult(steamId: _steamIdController.text),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInstructions(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Set up Steam activity',
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w400,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          widget.description,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 12,
            height: 1.35,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 14),
        const _SetupInstructionStep(
          number: '1',
          text: 'Open your Steam profile and copy the SteamID64.',
        ),
        const _SetupInstructionStep(
          number: '2',
          text: 'Make sure game details are visible to the Steam Web API.',
        ),
        const _SetupInstructionStep(
          number: '3',
          text: 'Paste the SteamID64 on the next page.',
        ),
      ],
    );
  }

  Widget _buildForm(BuildContext context) {
    return _SetupTextField(
      controller: _steamIdController,
      label: 'SteamID64',
      hint: widget.placeholder,
    );
  }
}

class _SetupInstructionStep extends StatelessWidget {
  const _SetupInstructionStep({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              number,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontSize: 12,
                height: 1.35,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupTextField extends StatelessWidget {
  const _SetupTextField({
    required this.controller,
    required this.label,
    required this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextField(
      controller: controller,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurface,
        fontSize: 14,
        letterSpacing: 0,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerLowest,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}
