import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/activity/activity_renderer.dart';
import 'package:intergalactic/client/components/activity/activity_service.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/user_presence/user_presence_component.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/login/login_page_shared.dart';
import 'package:intergalactic/ui/pages/settings/app_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/settings_category_account.dart';
import 'package:intergalactic/ui/pages/settings/settings_navigation.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class DesktopAccountPopupAnchor extends StatefulWidget {
  const DesktopAccountPopupAnchor({
    required this.child,
    required this.client,
    required this.clientManager,
    required this.activityService,
    this.popupWidth = 304,
    super.key,
  });

  final Widget child;
  final Client client;
  final ClientManager clientManager;
  final ActivityService activityService;
  final double popupWidth;

  @override
  State<DesktopAccountPopupAnchor> createState() =>
      _DesktopAccountPopupAnchorState();
}

class _DesktopAccountPopupAnchorState extends State<DesktopAccountPopupAnchor> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _entry;

  @override
  void dispose() {
    _hidePopup();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: _togglePopup, child: widget.child),
      ),
    );
  }

  void _togglePopup() {
    if (_entry != null) {
      _hidePopup();
      return;
    }

    final navigationContext = context;
    final entry = OverlayEntry(
      builder: (context) {
        return _AccountPopupOverlay(
          link: _layerLink,
          width: widget.popupWidth,
          client: widget.client,
          clientManager: widget.clientManager,
          activityService: widget.activityService,
          navigationContext: navigationContext,
          onDismiss: _hidePopup,
        );
      },
    );
    _entry = entry;
    Overlay.of(context).insert(entry);
  }

  void _hidePopup() {
    _entry?.remove();
    _entry = null;
  }
}

class _AccountPopupOverlay extends StatelessWidget {
  const _AccountPopupOverlay({
    required this.link,
    required this.width,
    required this.client,
    required this.clientManager,
    required this.activityService,
    required this.navigationContext,
    required this.onDismiss,
  });

  final LayerLink link;
  final double width;
  final Client client;
  final ClientManager clientManager;
  final ActivityService activityService;
  final BuildContext navigationContext;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
          ),
        ),
        CompositedTransformFollower(
          link: link,
          showWhenUnlinked: false,
          targetAnchor: Alignment.topLeft,
          followerAnchor: Alignment.bottomLeft,
          offset: const Offset(4, -8),
          child: Material(
            color: Colors.transparent,
            child: AccountPopup(
              width: width,
              client: client,
              clientManager: clientManager,
              activityService: activityService,
              navigationContext: navigationContext,
              onDismiss: onDismiss,
            ),
          ),
        ),
      ],
    );
  }
}

class AccountPopup extends StatefulWidget {
  const AccountPopup({
    required this.width,
    required this.client,
    required this.clientManager,
    required this.activityService,
    required this.navigationContext,
    required this.onDismiss,
    super.key,
  });

  final double width;
  final Client client;
  final ClientManager clientManager;
  final ActivityService activityService;
  final BuildContext navigationContext;
  final VoidCallback onDismiss;

  @override
  State<AccountPopup> createState() => _AccountPopupState();
}

class _AccountPopupState extends State<AccountPopup> {
  Profile? _profile;
  UserPresence? _presence;
  List<ProfileBadge> _badges = const [];
  StreamSubscription<(String, UserPresence)>? _presenceSubscription;
  StreamSubscription<UserActivity?>? _activitySubscription;
  UserActivity? _activity;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _profile = widget.client.self;
    _activity = widget.activityService.currentActivity;
    _listenForPresence();
    _activitySubscription = widget.activityService.onActivityChanged.listen((
      activity,
    ) {
      if (!mounted) return;
      setState(() {
        _activity = activity;
      });
    });
    unawaited(_loadProfile());
  }

  @override
  void didUpdateWidget(covariant AccountPopup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client == widget.client) {
      return;
    }

    _profile = widget.client.self;
    _presenceSubscription?.cancel();
    _listenForPresence();
    unawaited(_loadProfile());
  }

  @override
  void dispose() {
    _presenceSubscription?.cancel();
    _activitySubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final outerRadius = BorderRadius.circular(12);
    final innerRadius = BorderRadius.circular(10);

    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: widget.width,
        maxWidth: widget.width,
        maxHeight: MediaQuery.sizeOf(context).height - 24,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: outerRadius,
          border: Border.all(
            color: scheme.outline.withValues(alpha: 0.78),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.42),
              blurRadius: 24,
              offset: const Offset(0, 14),
            ),
            BoxShadow(
              color: scheme.outline.withValues(alpha: 0.22),
              blurRadius: 0,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(1.5),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: innerRadius,
            ),
            child: ClipRRect(
              borderRadius: innerRadius,
              child: SingleChildScrollView(
                padding: EdgeInsets.zero,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ProfileSummary(
                      client: widget.client,
                      profile: _profile ?? widget.client.self,
                      presence: _presence,
                      badges: _badges,
                      onStatusTap: _changeStatus,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                      child: _AccountActivityView(
                        service: widget.activityService,
                        currentActivity: _activity,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
                      child: _AccountActionCard(
                        onEditProfile: _openProfileSettings,
                        onSwitchAccounts: _openSwitchAccounts,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _listenForPresence() {
    final userId = widget.client.self?.identifier ?? widget.client.identifier;
    _presenceSubscription = widget.client
        .getComponent<UserPresenceComponent>()
        ?.onPresenceChanged
        .listen((event) {
          if (event.$1 != userId || !mounted) {
            return;
          }

          setState(() {
            _presence = event.$2;
          });
        });
  }

  Future<void> _loadProfile() async {
    final token = ++_loadToken;
    final component = widget.client.getComponent<UserProfileComponent>();
    final userId = widget.client.self?.identifier ?? widget.client.identifier;
    Profile? profile = widget.client.self;
    var badges = <ProfileBadge>[];

    try {
      profile = await component?.getProfile(userId) ?? profile;
      if (profile is ProfileWithBadges) {
        final badgeProfile = profile as ProfileWithBadges;
        badges = await badgeProfile.getBadges();
      }
    } catch (_) {
      profile = widget.client.self;
      badges = const [];
    }

    if (!mounted || token != _loadToken) {
      return;
    }

    setState(() {
      _profile = profile;
      _badges = badges;
      if (profile is ProfileWithPresence) {
        final presenceProfile = profile as ProfileWithPresence;
        _presence = presenceProfile.precence;
      }
    });
  }

  Future<void> _changeStatus() async {
    final initialText = _statusText();
    final status = await AdaptiveDialog.show<String?>(
      widget.navigationContext,
      title: "Set status",
      builder: (_) => _StatusPrompt(initialText: initialText),
    );

    if (status == null) {
      return;
    }

    final trimmed = status.trim();
    await widget.client.getComponent<UserProfileComponent>()?.setStatus(
      trimmed.isEmpty ? null : trimmed,
    );
    await widget.client.getComponent<UserPresenceComponent>()?.setStatus(
      UserPresenceStatus.online,
      message: trimmed.isEmpty ? null : trimmed,
      clearMessage: trimmed.isEmpty,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _presence = trimmed.isEmpty
          ? UserPresence(UserPresenceStatus.online)
          : UserPresence(
              UserPresenceStatus.online,
              message: UserPresenceMessage(
                trimmed,
                PresenceMessageType.userCustom,
              ),
            );
    });
  }

  String? _statusText() {
    final presenceMessage = _presence?.message?.message;
    if (presenceMessage != null && presenceMessage.trim().isNotEmpty) {
      return presenceMessage;
    }

    final profile = _profile;
    if (profile is ProfileWithPresence) {
      final presenceProfile = profile as ProfileWithPresence;
      final message = presenceProfile.precence?.message?.message;
      if (message != null && message.trim().isNotEmpty) {
        return message;
      }
    }

    return null;
  }

  Future<void> _openProfileSettings() async {
    widget.onDismiss();
    await SettingsNavigation.show(
      widget.navigationContext,
      const AppSettingsPage(
        initialTabId: SettingsCategoryAccount.accountProfileTabId,
      ),
    );
  }

  Future<void> _openSwitchAccounts() async {
    widget.onDismiss();
    final choice = await AdaptiveDialog.show<_AccountSwitchChoice>(
      widget.navigationContext,
      title: "Switch accounts",
      builder: (_) => _AccountSwitchDialog(clientManager: widget.clientManager),
    );

    if (choice == null) {
      return;
    }

    if (choice.addAccount) {
      await _openAddAccount();
      return;
    }

    EventBus.setFilterClient.add(choice.client);
    await preferences.filterClient.set(choice.client?.identifier);
  }

  Future<void> _openAddAccount() async {
    await Navigator.of(widget.navigationContext).push(
      MaterialPageRoute(
        builder: (_) => LoginPage(
          canNavigateBack: true,
          onSuccess: (_) {
            Navigator.of(widget.navigationContext).pop();
          },
        ),
      ),
    );
  }
}

class _ProfileSummary extends StatelessWidget {
  const _ProfileSummary({
    required this.client,
    required this.profile,
    required this.presence,
    required this.badges,
    required this.onStatusTap,
  });

  final Client client;
  final Profile? profile;
  final UserPresence? presence;
  final List<ProfileBadge> badges;
  final VoidCallback onStatusTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolvedProfile = profile ?? client.self;
    final displayName =
        resolvedProfile?.displayName ?? client.self?.displayName ?? "Account";
    final identifier =
        resolvedProfile?.identifier ??
        client.self?.identifier ??
        client.identifier;
    var profileColor = resolvedProfile?.defaultColor ?? scheme.primary;
    if (resolvedProfile is ProfileWithColorScheme) {
      final colorProfile = resolvedProfile as ProfileWithColorScheme;
      profileColor = colorProfile.color ?? profileColor;
    }

    String? bio;
    if (resolvedProfile is ProfileWithBio) {
      final bioProfile = resolvedProfile as ProfileWithBio;
      bio = bioProfile.plaintextBio?.trim();
    }
    final status = _statusText(resolvedProfile) ?? "Set a status";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 198,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 132,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: scheme.surfaceContainerLow),
                  child: resolvedProfile?.banner != null
                      ? Image(
                          image: resolvedProfile!.banner!,
                          fit: BoxFit.cover,
                        )
                      : DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                scheme.surfaceContainerLow,
                                scheme.surfaceContainer,
                                profileColor.withValues(alpha: 0.72),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 68,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: profileColor),
                ),
              ),
              Positioned(
                left: 20,
                bottom: 32,
                child: tiamat.Avatar(
                  radius: 42,
                  image: resolvedProfile?.avatar,
                  placeholderColor: resolvedProfile?.defaultColor,
                  placeholderText: displayName,
                ),
              ),
              Positioned(
                right: 42,
                bottom: 28,
                child: _StatusPill(status: status, onTap: onStatusTap),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: scheme.onSurface,
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0,
                          ),
                    ),
                    const SizedBox(height: 2),
                    InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () =>
                          Clipboard.setData(ClipboardData(text: identifier)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              identifier,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontFamily: "Code",
                                    fontSize: 11,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.copy_rounded,
                            size: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (badges.isNotEmpty) ...[
                const SizedBox(width: 10),
                _ProfileBadgeIcon(badge: badges.first),
              ],
            ],
          ),
        ),
        if (bio != null && bio.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Text(
              bio,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurface,
                height: 1.25,
                letterSpacing: 0,
              ),
            ),
          ),
      ],
    );
  }

  String? _statusText(Profile? profile) {
    final presenceMessage = presence?.message?.message;
    if (presenceMessage != null && presenceMessage.trim().isNotEmpty) {
      return presenceMessage;
    }

    if (profile is ProfileWithPresence) {
      final presenceProfile = profile as ProfileWithPresence;
      final message = presenceProfile.precence?.message?.message;
      if (message != null && message.trim().isNotEmpty) {
        return message;
      }
    }

    return null;
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.onTap});

  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.28)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 132),
              child: Text(
                status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface,
                  fontSize: 14,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileBadgeIcon extends StatelessWidget {
  const _ProfileBadgeIcon({required this.badge});

  final ProfileBadge badge;

  @override
  Widget build(BuildContext context) {
    return tiamat.Tooltip(
      text: badge.body,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image(
          image: badge.image,
          width: 36,
          height: 36,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _AccountActivityView extends StatelessWidget {
  const _AccountActivityView({
    required this.service,
    required this.currentActivity,
  });

  final ActivityService service;
  final UserActivity? currentActivity;

  @override
  Widget build(BuildContext context) {
    final activities = service.currentActivities;
    if (activities.isEmpty) {
      return _EmptyActivityView();
    }

    if (activities.length == 1) {
      return _ActivityViewCard(activity: activities.first, service: service);
    }

    final current = currentActivity ?? activities.first;
    final top = activities.firstWhere(
      (activity) => activity.id != current.id,
      orElse: () => activities.first,
    );
    final back = current.id == top.id ? activities.last : current;

    return SizedBox(
      height: 112,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 10,
            right: 0,
            top: 18,
            child: Opacity(
              opacity: 0.72,
              child: _ActivityViewCard(
                activity: back,
                service: service,
                compact: true,
                secondary: true,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 10,
            top: 0,
            child: _ActivityViewCard(activity: top, service: service),
          ),
          Positioned(
            right: 8,
            top: 8,
            child: tiamat.Tooltip(
              text: "Swap activity view",
              child: Material(
                color: Colors.transparent,
                child: InkResponse(
                  radius: 18,
                  onTap: service.selectNextLocalActivity,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                    ),
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: Icon(
                        Icons.swap_vert_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyActivityView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.18)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "No current activity",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityViewCard extends StatelessWidget {
  const _ActivityViewCard({
    required this.activity,
    required this.service,
    this.compact = false,
    this.secondary = false,
  });

  final UserActivity activity;
  final ActivityService service;
  final bool compact;
  final bool secondary;

  static const _renderer = ActivityRenderer();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final subtitle = _renderer.compactSubtitle(activity);
    final progress = _activityProgress(activity);
    final artworkSize = compact ? 38.0 : 50.0;
    final controls = compact ? const <ActivityControl>[] : activity.controls;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: secondary ? scheme.surfaceContainer : scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          compact ? 8 : 10,
          10,
          compact ? 8 : 10,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _ActivityArtwork(
                  activity: activity,
                  size: artworkSize,
                  radius: 5,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _activityLabel(activity),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        activity.subtitle ?? activity.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0,
                        ),
                      ),
                      Text(
                        activity.subtitle == null
                            ? subtitle ?? ""
                            : activity.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (!compact && (progress != null || controls.isNotEmpty)) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  SizedBox(width: artworkSize + 10),
                  Expanded(
                    child: progress == null
                        ? const SizedBox.shrink()
                        : _ActivityProgressBar(progress: progress),
                  ),
                  if (controls.isNotEmpty) ...[
                    if (progress != null) const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: controls
                          .map(
                            (control) => IconButton(
                              tooltip: control.tooltip ?? control.label,
                              icon: Icon(_iconForControl(control)),
                              iconSize: 15,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 24,
                                height: 24,
                              ),
                              onPressed: control.enabled
                                  ? () => service.executeControlForActivity(
                                      activity,
                                      control,
                                    )
                                  : null,
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _activityLabel(UserActivity activity) {
    final base = _renderer.compactTitle(activity);
    final provider = switch (activity.provider) {
      "spotify" => "Spotify",
      "steam" => "Steam",
      "local_media" => "Media",
      final value? when value.trim().isNotEmpty => value,
      _ => null,
    };

    if (provider == null) {
      return base;
    }

    return switch (activity.kind) {
      ActivityKind.music => "$base to $provider",
      ActivityKind.game => "$base on $provider",
      _ => "$base - $provider",
    };
  }

  IconData _iconForControl(ActivityControl control) {
    if (control.kind == ActivityControlKind.playPause) {
      return control.label.toLowerCase() == "pause"
          ? Icons.pause
          : Icons.play_arrow;
    }

    if (control.kind == ActivityControlKind.like) {
      return control.label.toLowerCase() == "like"
          ? Icons.favorite_border
          : Icons.favorite;
    }

    return switch (control.kind) {
      ActivityControlKind.playPause => Icons.play_arrow,
      ActivityControlKind.previous => Icons.skip_previous,
      ActivityControlKind.next => Icons.skip_next,
      ActivityControlKind.like => Icons.favorite_border,
      ActivityControlKind.volume => Icons.volume_up,
      ActivityControlKind.openExternal => Icons.open_in_new,
      ActivityControlKind.hide => Icons.visibility_off,
      ActivityControlKind.custom => Icons.more_horiz,
    };
  }
}

class _ActivityArtwork extends StatelessWidget {
  const _ActivityArtwork({
    required this.activity,
    required this.size,
    required this.radius,
  });

  final UserActivity activity;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final artworkUrl = activity.artworkUrl;
    if (artworkUrl != null && artworkUrl.isNotEmpty) {
      final imageData = _dataImageBytes(artworkUrl);
      if (imageData != null) {
        return _artworkFrame(
          context,
          Image.memory(
            imageData,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            errorBuilder: (context, error, stackTrace) => _fallback(context),
          ),
        );
      }

      return _artworkFrame(
        context,
        Image.network(
          artworkUrl,
          fit: BoxFit.contain,
          alignment: Alignment.center,
          errorBuilder: (context, error, stackTrace) => _fallback(context),
        ),
      );
    }

    return _fallback(context);
  }

  Widget _artworkFrame(BuildContext context, Widget child) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: DecoratedBox(
        decoration: BoxDecoration(color: scheme.surfaceContainerHighest),
        child: SizedBox(width: size, height: size, child: child),
      ),
    );
  }

  Uint8List? _dataImageBytes(String value) {
    final separator = value.indexOf(",");
    if (!value.startsWith("data:image/") || separator == -1) {
      return null;
    }

    final header = value.substring(0, separator).toLowerCase();
    if (!header.endsWith(";base64")) {
      return null;
    }

    try {
      return base64Decode(value.substring(separator + 1));
    } on FormatException {
      return null;
    }
  }

  Widget _fallback(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(
          switch (activity.kind) {
            ActivityKind.music => Icons.music_note_rounded,
            ActivityKind.game => Icons.sports_esports_rounded,
            ActivityKind.call => Icons.call_rounded,
            ActivityKind.screenShare => Icons.screen_share_rounded,
            ActivityKind.custom => Icons.star_rounded,
          },
          size: size * 0.48,
          color: scheme.primary,
        ),
      ),
    );
  }
}

class _ActivityProgressBar extends StatelessWidget {
  const _ActivityProgressBar({required this.progress});

  final _ActivityProgress progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          _formatDuration(progress.position),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontSize: 10,
            fontFamily: "Code",
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              minHeight: 3,
              value: progress.fraction,
              backgroundColor: scheme.outline.withValues(alpha: 0.28),
              valueColor: AlwaysStoppedAnimation<Color>(
                scheme.onSurfaceVariant.withValues(alpha: 0.76),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          _formatDuration(progress.duration),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontSize: 10,
            fontFamily: "Code",
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, "0");
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, "0");
    return "$minutes:$seconds";
  }
}

class _ActivityProgress {
  const _ActivityProgress({required this.position, required this.duration});

  final Duration position;
  final Duration duration;

  double get fraction {
    if (duration.inMilliseconds <= 0) {
      return 0;
    }

    return (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
  }
}

_ActivityProgress? _activityProgress(UserActivity activity) {
  final durationMs = _intMetadata(activity, "duration_ms");
  if (durationMs == null || durationMs <= 0) {
    return null;
  }

  final positionMs = _intMetadata(activity, "progress_ms") ?? 0;
  return _ActivityProgress(
    position: Duration(milliseconds: positionMs),
    duration: Duration(milliseconds: durationMs),
  );
}

int? _intMetadata(UserActivity activity, String key) {
  final value = activity.metadata[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value);
  }

  return null;
}

class _AccountActionCard extends StatelessWidget {
  const _AccountActionCard({
    required this.onEditProfile,
    required this.onSwitchAccounts,
  });

  final VoidCallback onEditProfile;
  final VoidCallback onSwitchAccounts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AccountActionButton(
            icon: Icons.edit_rounded,
            label: "Edit Profile",
            onTap: onEditProfile,
          ),
          Divider(
            height: 1,
            indent: 12,
            endIndent: 12,
            color: scheme.outline.withValues(alpha: 0.32),
          ),
          _AccountActionButton(
            icon: Icons.switch_account_rounded,
            label: "Switch Accounts",
            onTap: onSwitchAccounts,
          ),
        ],
      ),
    );
  }
}

class _AccountActionButton extends StatelessWidget {
  const _AccountActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 15, 16, 15),
          child: Row(
            children: [
              Icon(icon, size: 17, color: scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurface,
                    fontSize: 16,
                    letterSpacing: 0,
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

class _StatusPrompt extends StatefulWidget {
  const _StatusPrompt({required this.initialText});

  final String? initialText;

  @override
  State<_StatusPrompt> createState() => _StatusPromptState();
}

class _StatusPromptState extends State<_StatusPrompt> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText ?? "");
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(hintText: "What are you up to?"),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: tiamat.Button.secondary(
                  text: "Cancel",
                  onTap: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: tiamat.Button(text: "Save", onTap: _save),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _save() {
    Navigator.of(context).pop(_controller.text);
  }
}

class _AccountSwitchChoice {
  const _AccountSwitchChoice.client(this.client) : addAccount = false;

  const _AccountSwitchChoice.addAccount() : client = null, addAccount = true;

  final Client? client;
  final bool addAccount;
}

class _AccountSwitchDialog extends StatelessWidget {
  const _AccountSwitchDialog({required this.clientManager});

  final ClientManager clientManager;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SwitchAccountRow(
            icon: Icons.all_inclusive_rounded,
            title: "All accounts",
            subtitle: "Show rooms and messages from every signed-in account.",
            onTap: () => Navigator.of(
              context,
            ).pop(const _AccountSwitchChoice.client(null)),
          ),
          const SizedBox(height: 8),
          for (final client in clientManager.clients)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SwitchAccountRow(
                avatar: client.self?.avatar,
                avatarColor: client.self?.defaultColor,
                avatarText: client.self?.displayName ?? client.identifier,
                title: client.self?.displayName ?? client.identifier,
                subtitle: client.self?.identifier ?? client.identifier,
                onTap: () => Navigator.of(
                  context,
                ).pop(_AccountSwitchChoice.client(client)),
              ),
            ),
          Divider(color: scheme.outline.withValues(alpha: 0.28)),
          _SwitchAccountRow(
            icon: Icons.add_rounded,
            title: "Add account",
            subtitle: "Sign in to another Matrix account on this device.",
            onTap: () => Navigator.of(
              context,
            ).pop(const _AccountSwitchChoice.addAccount()),
          ),
        ],
      ),
    );
  }
}

class _SwitchAccountRow extends StatelessWidget {
  const _SwitchAccountRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.icon,
    this.avatar,
    this.avatarColor,
    this.avatarText,
  });

  final IconData? icon;
  final ImageProvider? avatar;
  final Color? avatarColor;
  final String? avatarText;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.14)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                if (icon != null)
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(icon, size: 20, color: scheme.primary),
                  )
                else
                  tiamat.Avatar(
                    radius: 18,
                    image: avatar,
                    placeholderColor: avatarColor,
                    placeholderText: avatarText,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
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
