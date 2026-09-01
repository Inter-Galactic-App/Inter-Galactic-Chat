import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/stories/story_component.dart';
import 'package:intergalactic/client/components/user_presence/user_presence_component.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_activity_status.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_composer.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_viewer.dart';
import 'package:intergalactic/ui/organisms/user_profile/user_profile.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

const int _defaultDirectMessageStatusLimit = 24;

@visibleForTesting
String? homeStatusText(UserPresence? presence, Profile? profile) {
  final presenceMessage = presence?.message?.message;
  final presenceText = presenceMessage?.trim();
  if (presenceText != null && presenceText.isNotEmpty) {
    return presenceText;
  }

  if (profile is ProfileWithPresence) {
    final profilePresence = (profile as ProfileWithPresence).precence;
    final profilePresenceMessage = profilePresence?.message;
    final profilePresenceText = profilePresenceMessage?.message;
    final profileText = profilePresenceText?.trim();
    if (profileText != null && profileText.isNotEmpty) {
      return profileText;
    }
  }

  return null;
}

@visibleForTesting
class HomeStatusEntry {
  const HomeStatusEntry({
    required this.client,
    required this.userId,
    required this.isSelf,
    required this.fallbackDisplayName,
    required this.fallbackColor,
    required this.latestActivity,
    this.fallbackAvatar,
    this.directMessageRoom,
  });

  final Client client;
  final String userId;
  final bool isSelf;
  final String fallbackDisplayName;
  final Color fallbackColor;
  final ImageProvider? fallbackAvatar;
  final DateTime? latestActivity;
  final Room? directMessageRoom;

  String get stableKey => '${client.identifier}|$userId';
}

@visibleForTesting
List<HomeStatusEntry> buildHomeStatusEntries({
  required ClientManager clientManager,
  Client? filterClient,
  int directMessageLimit = _defaultDirectMessageStatusLimit,
}) {
  final entries = <HomeStatusEntry>[];
  final seen = <String>{};

  final clients = filterClient != null ? [filterClient] : clientManager.clients;
  for (final client in clients) {
    final self = client.self;
    final userId = self?.identifier;
    if (self == null || userId == null || userId.isEmpty || userId == 'Error') {
      continue;
    }

    final entry = HomeStatusEntry(
      client: client,
      userId: userId,
      isSelf: true,
      fallbackDisplayName: self.displayName,
      fallbackColor: self.defaultColor,
      fallbackAvatar: self.avatar,
      latestActivity: null,
    );
    if (seen.add(entry.stableKey)) {
      entries.add(entry);
    }
  }

  final directMessageRooms = <Room>[];
  for (final client in clients) {
    final component = client.getComponent<DirectMessagesComponent>();
    if (component != null) {
      directMessageRooms.addAll(component.directMessageRooms);
    }
  }

  if (directMessageRooms.isEmpty && filterClient == null) {
    directMessageRooms.addAll(clientManager.directMessages.directMessageRooms);
  }

  final rooms = List<Room>.from(directMessageRooms)
    ..sort((a, b) => b.lastEventTimestamp.compareTo(a.lastEventTimestamp));

  var directMessageCount = 0;
  for (final room in rooms) {
    if (filterClient != null && room.client != filterClient) {
      continue;
    }

    if (directMessageCount >= directMessageLimit) {
      break;
    }

    final component = room.client.getComponent<DirectMessagesComponent>();
    final userId = component?.getDirectMessagePartnerId(room);
    if (userId == null ||
        userId.isEmpty ||
        userId == room.client.self?.identifier) {
      continue;
    }

    final entry = HomeStatusEntry(
      client: room.client,
      userId: userId,
      isSelf: false,
      fallbackDisplayName: room.displayName,
      fallbackColor: room.defaultColor,
      fallbackAvatar: room.avatar,
      latestActivity: room.lastEventTimestamp,
      directMessageRoom: room,
    );
    if (seen.add(entry.stableKey)) {
      entries.add(entry);
      directMessageCount++;
    }
  }

  return entries;
}

class HomeStatusStrip extends StatefulWidget {
  const HomeStatusStrip({
    super.key,
    required this.clientManager,
    this.filterClient,
    this.onRoomClicked,
    @visibleForTesting this.storyComposerOpener,
  });

  final ClientManager clientManager;
  final Client? filterClient;
  final void Function(Room room)? onRoomClicked;

  /// Widget tests must inject an opener that passes fake media services to
  /// [HomeStoryComposer.show]; the default opener enumerates real capture
  /// devices, which leaves pending platform-channel work under the fake-async
  /// test clock.
  final void Function(BuildContext context, Client client)? storyComposerOpener;

  @override
  State<HomeStatusStrip> createState() => _HomeStatusStripState();
}

class _HomeStatusStripState extends State<HomeStatusStrip> {
  final Map<String, UserPresence> _presenceByKey = {};
  final Map<String, Profile> _profileByKey = {};
  final Set<String> _loadingPresenceKeys = {};
  final Set<String> _loadingProfileKeys = {};
  final Map<String, StreamSubscription<(String, UserPresence)>>
  _presenceSubscriptions = {};
  final Map<String, StreamSubscription<void>> _storySubscriptions = {};
  late List<HomeStatusEntry> _entries;
  late List<StreamSubscription> _subscriptions;

  String get labelStatuses => Intl.message(
    'Status',
    name: 'labelHomeStatusStrip',
    desc: 'Header for the Home screen horizontal status strip',
  );

  @override
  void initState() {
    super.initState();
    _entries = _buildEntries();
    _subscriptions = [
      widget.clientManager.directMessages.onRoomsListUpdated.listen(
        (_) => _refreshEntries(),
      ),
      widget.clientManager.directMessages.onHighlightedRoomsListUpdated.listen(
        (_) => _refreshEntries(),
      ),
      widget.clientManager.onClientAdded.stream.listen(
        (_) => _refreshEntries(),
      ),
      widget.clientManager.onClientRemoved.stream.listen(
        (_) => _refreshEntries(),
      ),
      widget.clientManager.onClientUpdated.stream.listen(_handleClientUpdated),
    ];
    _syncPresenceSubscriptions();
    _syncStorySubscriptions();
    _loadMissingData();
  }

  @override
  void didUpdateWidget(covariant HomeStatusStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clientManager != widget.clientManager ||
        oldWidget.filterClient != widget.filterClient) {
      for (final subscription in _subscriptions) {
        subscription.cancel();
      }
      _subscriptions = [
        widget.clientManager.directMessages.onRoomsListUpdated.listen(
          (_) => _refreshEntries(),
        ),
        widget.clientManager.directMessages.onHighlightedRoomsListUpdated
            .listen((_) => _refreshEntries()),
        widget.clientManager.onClientAdded.stream.listen(
          (_) => _refreshEntries(),
        ),
        widget.clientManager.onClientRemoved.stream.listen(
          (_) => _refreshEntries(),
        ),
        widget.clientManager.onClientUpdated.stream.listen(
          _handleClientUpdated,
        ),
      ];
      _refreshEntries();
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    for (final subscription in _presenceSubscriptions.values) {
      subscription.cancel();
    }
    for (final subscription in _storySubscriptions.values) {
      subscription.cancel();
    }
    super.dispose();
  }

  void _refreshEntries() {
    if (!mounted) {
      return;
    }

    setState(() {
      _entries = _buildEntries();
      final activeKeys = _entries.map((entry) => entry.stableKey).toSet();
      _presenceByKey.removeWhere((key, _) => !activeKeys.contains(key));
      _profileByKey.removeWhere((key, _) => !activeKeys.contains(key));
      _loadingPresenceKeys.removeWhere((key) => !activeKeys.contains(key));
      _loadingProfileKeys.removeWhere((key) => !activeKeys.contains(key));
    });
    _syncPresenceSubscriptions();
    _syncStorySubscriptions();
    _loadMissingData();
  }

  void _handleClientUpdated(Client client) {
    if (!mounted) {
      return;
    }

    setState(() {
      _entries = _buildEntries();
      final activeKeys = _entries.map((entry) => entry.stableKey).toSet();
      final selfKeysToReload = _entries
          .where((entry) => identical(entry.client, client) && entry.isSelf)
          .map((entry) => entry.stableKey)
          .toSet();
      _presenceByKey.removeWhere((key, _) => !activeKeys.contains(key));
      _profileByKey.removeWhere(
        (key, _) => !activeKeys.contains(key) || selfKeysToReload.contains(key),
      );
      _loadingPresenceKeys.removeWhere((key) => !activeKeys.contains(key));
      _loadingProfileKeys.removeWhere(
        (key) => !activeKeys.contains(key) || selfKeysToReload.contains(key),
      );
    });
    _syncPresenceSubscriptions();
    _syncStorySubscriptions();
    _loadMissingData();
  }

  List<HomeStatusEntry> _buildEntries() => buildHomeStatusEntries(
    clientManager: widget.clientManager,
    filterClient: widget.filterClient,
  );

  void _syncPresenceSubscriptions() {
    final activeClientIds = _entries
        .map((entry) => entry.client.identifier)
        .toSet();

    for (final clientId in _presenceSubscriptions.keys.toList()) {
      if (!activeClientIds.contains(clientId)) {
        _presenceSubscriptions.remove(clientId)?.cancel();
      }
    }

    for (final entry in _entries) {
      final clientId = entry.client.identifier;
      if (_presenceSubscriptions.containsKey(clientId)) {
        continue;
      }

      final component = entry.client.getComponent<UserPresenceComponent>();
      final subscription = component?.onPresenceChanged.listen((event) {
        final key = '$clientId|${event.$1}';
        if (!_entries.any((entry) => entry.stableKey == key) || !mounted) {
          return;
        }

        setState(() {
          _presenceByKey[key] = event.$2;
        });
      });

      if (subscription != null) {
        _presenceSubscriptions[clientId] = subscription;
      }
    }
  }

  void _syncStorySubscriptions() {
    final activeClientIds = _entries
        .map((entry) => entry.client.identifier)
        .toSet();

    for (final clientId in _storySubscriptions.keys.toList()) {
      if (!activeClientIds.contains(clientId)) {
        _storySubscriptions.remove(clientId)?.cancel();
      }
    }

    for (final entry in _entries) {
      final clientId = entry.client.identifier;
      if (_storySubscriptions.containsKey(clientId)) {
        continue;
      }

      final component = entry.client.getComponent<StoryComponent>();
      if (component == null) {
        continue;
      }

      _storySubscriptions[clientId] = component.onStoriesChanged.listen((_) {
        if (!mounted) {
          return;
        }
        setState(() {});
      });
      unawaited(component.refreshStories());
    }
  }

  void _loadMissingData() {
    for (final entry in _entries) {
      final key = entry.stableKey;
      if (!_presenceByKey.containsKey(key) && _loadingPresenceKeys.add(key)) {
        unawaited(_loadPresence(entry));
      }
      if (!_profileByKey.containsKey(key) && _loadingProfileKeys.add(key)) {
        unawaited(_loadProfile(entry));
      }
    }
  }

  Future<void> _loadPresence(HomeStatusEntry entry) async {
    final key = entry.stableKey;
    try {
      final presence = await entry.client
          .getComponent<UserPresenceComponent>()
          ?.getUserPresence(entry.userId);
      if (!mounted || presence == null) {
        return;
      }

      setState(() {
        _presenceByKey[key] = presence;
      });
    } finally {
      _loadingPresenceKeys.remove(key);
    }
  }

  Future<void> _loadProfile(HomeStatusEntry entry) async {
    final key = entry.stableKey;
    try {
      final profile =
          await entry.client.getComponent<UserProfileComponent>()?.getProfile(
            entry.userId,
          ) ??
          (entry.isSelf ? entry.client.self : null);
      if (!mounted || profile == null) {
        return;
      }

      setState(() {
        _profileByKey[key] = profile;
      });
    } finally {
      _loadingProfileKeys.remove(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_entries.isEmpty) {
      return const SizedBox.shrink();
    }

    final sortedEntries = List<HomeStatusEntry>.from(_entries)
      ..sort(_compareEntries);
    final isMobile = Layout.mobile;
    final height = isMobile ? 104.0 : 96.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
      child: tiamat.Panel(
        mode: tiamat.TileType.surfaceContainerLow,
        header: labelStatuses,
        padding: isMobile ? 10 : 8,
        child: SizedBox(
          height: height,
          child: ScrollConfiguration(
            behavior: const _HomeStatusScrollBehavior(),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: sortedEntries.length,
              separatorBuilder: (_, __) => SizedBox(width: isMobile ? 10 : 8),
              itemBuilder: (context, index) {
                final entry = sortedEntries[index];
                final profile = _profileByKey[entry.stableKey];
                final presence = _presenceByKey[entry.stableKey];
                final storyComponent = entry.client
                    .getComponent<StoryComponent>();
                final stories =
                    storyComponent?.activeStoriesForUser(entry.userId) ??
                    const <StoryItem>[];
                final statusText = _statusText(presence, profile);
                return _HomeStatusBubble(
                  entry: entry,
                  profile: profile,
                  presence: presence,
                  statusText: statusText,
                  activityKind: homeActivityStatusKindForStatusText(statusText),
                  hasStories: stories.isNotEmpty,
                  hasUnseenStories:
                      storyComponent?.hasUnseenStories(entry.userId) ?? false,
                  hasPendingStoryUpload:
                      storyComponent?.hasPendingStoryUpload(entry.userId) ??
                      false,
                  onTap: () => _onEntryTap(entry, profile, stories),
                  onLongPress: () => _onEntryLongPress(entry),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  int _compareEntries(HomeStatusEntry a, HomeStatusEntry b) {
    if (a.isSelf != b.isSelf) {
      return a.isSelf ? -1 : 1;
    }

    final aHasUnseenStories = _hasUnseenStories(a);
    final bHasUnseenStories = _hasUnseenStories(b);
    if (aHasUnseenStories != bHasUnseenStories) {
      return aHasUnseenStories ? -1 : 1;
    }

    final aPresence = _presenceByKey[a.stableKey];
    final bPresence = _presenceByKey[b.stableKey];
    final aProfile = _profileByKey[a.stableKey];
    final bProfile = _profileByKey[b.stableKey];
    final aRank = _presenceRank(aPresence, _statusText(aPresence, aProfile));
    final bRank = _presenceRank(bPresence, _statusText(bPresence, bProfile));
    if (aRank != bRank) {
      return aRank.compareTo(bRank);
    }

    final latestComparison =
        (b.latestActivity ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
          a.latestActivity ?? DateTime.fromMillisecondsSinceEpoch(0),
        );
    if (latestComparison != 0) {
      return latestComparison;
    }

    return a.fallbackDisplayName.compareTo(b.fallbackDisplayName);
  }

  bool _hasUnseenStories(HomeStatusEntry entry) {
    return entry.client.getComponent<StoryComponent>()?.hasUnseenStories(
          entry.userId,
        ) ??
        false;
  }

  int _presenceRank(UserPresence? presence, String? statusText) {
    final online = presence?.status == UserPresenceStatus.online;
    final hasStatus = statusText != null && statusText.trim().isNotEmpty;

    if (online && hasStatus) return 0;
    if (online) return 1;
    if (hasStatus) return 2;
    return 3;
  }

  String? _statusText(UserPresence? presence, Profile? profile) {
    return homeStatusText(presence, profile);
  }

  void _onEntryTap(
    HomeStatusEntry entry,
    Profile? profile,
    List<StoryItem> stories,
  ) {
    if (entry.isSelf) {
      final openComposer = widget.storyComposerOpener;
      if (openComposer != null) {
        openComposer(context, entry.client);
      } else {
        HomeStoryComposer.show(context, client: entry.client);
      }
      return;
    }

    if (stories.isNotEmpty) {
      HomeStoryViewer.show(
        context,
        client: entry.client,
        userId: entry.userId,
        stories: stories,
        displayName: profile?.displayName ?? entry.fallbackDisplayName,
        avatar: profile?.avatar ?? entry.fallbackAvatar,
        avatarColor: profile?.defaultColor ?? entry.fallbackColor,
      );
      return;
    }

    final room = entry.directMessageRoom;
    if (room != null) {
      widget.onRoomClicked?.call(room);
      return;
    }

    UserProfile.show(
      context,
      client: entry.client,
      userId: entry.userId,
      initialHeightMobile: 0.72,
    );
  }

  void _onEntryLongPress(HomeStatusEntry entry) {
    final room = entry.directMessageRoom;
    if (!entry.isSelf && room != null) {
      widget.onRoomClicked?.call(room);
      return;
    }

    UserProfile.show(
      context,
      client: entry.client,
      userId: entry.userId,
      initialHeightMobile: 0.72,
    );
  }
}

class _HomeStatusScrollBehavior extends MaterialScrollBehavior {
  const _HomeStatusScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  };
}

class _HomeStatusBubble extends StatelessWidget {
  const _HomeStatusBubble({
    required this.entry,
    required this.onTap,
    this.profile,
    this.presence,
    this.statusText,
    required this.activityKind,
    required this.hasStories,
    required this.hasUnseenStories,
    required this.hasPendingStoryUpload,
    required this.onLongPress,
  });

  final HomeStatusEntry entry;
  final Profile? profile;
  final UserPresence? presence;
  final String? statusText;
  final HomeActivityStatusKind? activityKind;
  final bool hasStories;
  final bool hasUnseenStories;
  final bool hasPendingStoryUpload;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = AccessibilityScope.tokensOf(context);
    final isMobile = Layout.mobile;
    final avatarDiameter = isMobile ? 58.0 : 52.0;
    final outerSize = avatarDiameter + 8;
    final width = isMobile ? 78.0 : 72.0;
    final displayName = profile?.displayName ?? entry.fallbackDisplayName;
    final avatar = profile?.avatar ?? entry.fallbackAvatar;
    final avatarColor = profile?.defaultColor ?? entry.fallbackColor;
    final online = presence?.status == UserPresenceStatus.online;
    final status = homeActivityStatusBubbleText(statusText);
    final presenceLabel = _presenceLabel(presence?.status);
    final storyLabel = _storyLabel(
      hasStories,
      hasUnseenStories,
      hasPendingStoryUpload,
    );
    final semanticLabel = _semanticLabel(
      displayName: displayName,
      presenceLabel: presenceLabel,
      storyLabel: storyLabel,
      status: status,
      activityKind: activityKind,
    );
    final hasActiveRing = hasStories || hasPendingStoryUpload;
    final ringColor = hasPendingStoryUpload
        ? tokens.storyPending
        : hasStories
        ? hasUnseenStories
              ? tokens.storyUnseen
              : tokens.storySeen
        : tokens.storyInactive.withValues(alpha: 0.72);

    return Semantics(
      button: true,
      label: semanticLabel,
      // When this migrates to tiamat.Tooltip it needs two things that are not
      // the component defaults, or it will regress twice over:
      //
      //   preferredDirection: AxisDirection.down  - the strip sits near the top
      //     of the window and the blank space is *below* the avatars. The house
      //     default is `up`, which puts the label over the section header. This
      //     is the "down for surfaces near the top" case from DECISIONS.md D3.
      //   excludeFromSemantics: true  - the Semantics wrapper directly above
      //     already announces `semanticLabel`, and the tooltip message is the
      //     same string, so a reader would say it twice. Same shape as SpaceIcon
      //     and AccessibleInteractiveRegion on the rails.
      child: Tooltip(
        message: semanticLabel,
        child: SizedBox(
          width: width,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              onLongPress: onLongPress,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(2, 2, 2, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: width,
                      height: outerSize + 10,
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          AnimatedContainer(
                            duration: InterGalacticMotion.duration(
                              context,
                              InterGalacticMotion.shortEmphasis,
                            ),
                            width: outerSize,
                            height: outerSize,
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                width: hasActiveRing ? 2.8 : 1.2,
                                color: ringColor,
                              ),
                            ),
                            child: tiamat.Avatar(
                              radius: avatarDiameter / 2,
                              image: avatar,
                              placeholderText: displayName,
                              placeholderColor: avatarColor,
                            ),
                          ),
                          if (online)
                            Positioned(
                              right: 4,
                              bottom: 8,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: tokens.statusOnline,
                                  border: Border.all(
                                    color: scheme.surface,
                                    width: 2,
                                  ),
                                ),
                                child: SizedBox(
                                  width: tokens.settings.nonColorStateCues
                                      ? 14
                                      : 11,
                                  height: tokens.settings.nonColorStateCues
                                      ? 14
                                      : 11,
                                  child: tokens.settings.nonColorStateCues
                                      ? Icon(
                                          Icons.check_rounded,
                                          size: 9,
                                          color: tokens.onStatusOnline,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          if (activityKind != null)
                            Positioned(
                              left: 4,
                              bottom: 8,
                              child: _HomeActivityBadge(
                                kind: activityKind!,
                                size: isMobile ? 22 : 20,
                              ),
                            ),
                          if (status != null && status.isNotEmpty)
                            Positioned(
                              top: 0,
                              left: 0,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: width - 4,
                                  minWidth: 28,
                                ),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: scheme.outline.withValues(
                                        alpha: 0.22,
                                      ),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.16,
                                        ),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 3,
                                    ),
                                    child: Text(
                                      status,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: scheme.onSurface,
                                            fontSize: isMobile ? 10 : 9.5,
                                            height: 1,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurface,
                        fontSize: isMobile ? 11 : 10.5,
                        height: 1.1,
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

  String _presenceLabel(UserPresenceStatus? status) {
    return switch (status) {
      UserPresenceStatus.online => Intl.message(
        'online',
        name: 'homeStatusPresenceOnline',
        desc: 'Accessibility label for an online Home status contact',
      ),
      UserPresenceStatus.unavailable => Intl.message(
        'away',
        name: 'homeStatusPresenceAway',
        desc: 'Accessibility label for an away Home status contact',
      ),
      UserPresenceStatus.offline => Intl.message(
        'offline',
        name: 'homeStatusPresenceOffline',
        desc: 'Accessibility label for an offline Home status contact',
      ),
      UserPresenceStatus.unknown || null => Intl.message(
        'presence unknown',
        name: 'homeStatusPresenceUnknown',
        desc: 'Accessibility label for a Home status contact with no presence',
      ),
    };
  }

  String _storyLabel(
    bool hasStories,
    bool hasUnseenStories,
    bool hasPendingStoryUpload,
  ) {
    if (hasPendingStoryUpload) {
      return Intl.message(
        ', uploading story',
        name: 'homeStatusUploadingStoryLabel',
        desc:
            'Accessibility suffix for the current user while a story is uploading',
      );
    }
    if (!hasStories) {
      return '';
    }
    if (hasUnseenStories) {
      return Intl.message(
        ', new story',
        name: 'homeStatusNewStoryLabel',
        desc:
            'Accessibility suffix for a Home status contact with unseen stories',
      );
    }
    return Intl.message(
      ', viewed story',
      name: 'homeStatusViewedStoryLabel',
      desc: 'Accessibility suffix for a Home status contact with seen stories',
    );
  }

  String _semanticLabel({
    required String displayName,
    required String presenceLabel,
    required String storyLabel,
    required String? status,
    required HomeActivityStatusKind? activityKind,
  }) {
    final activityLabel = _activitySemanticLabel(activityKind);
    if (status == null || status.isEmpty) {
      if (activityLabel != null) {
        return Intl.message(
          '$displayName, $presenceLabel$storyLabel, $activityLabel',
          name: 'homeStatusSemanticLabelWithActivity',
          args: [displayName, presenceLabel, storyLabel, activityLabel],
          desc:
              'Accessibility label for a Home status contact with an activity badge',
        );
      }
      return Intl.message(
        '$displayName, $presenceLabel$storyLabel',
        name: 'homeStatusSemanticLabel',
        args: [displayName, presenceLabel, storyLabel],
        desc: 'Accessibility label for a Home status contact',
      );
    }
    if (activityLabel != null) {
      return Intl.message(
        '$displayName, $presenceLabel$storyLabel, $activityLabel, status: $status',
        name: 'homeStatusSemanticLabelWithActivityAndStatus',
        args: [displayName, presenceLabel, storyLabel, activityLabel, status],
        desc:
            'Accessibility label for a Home status contact with an activity badge and a short status',
      );
    }
    return Intl.message(
      '$displayName, $presenceLabel$storyLabel, status: $status',
      name: 'homeStatusSemanticLabelWithStatus',
      args: [displayName, presenceLabel, storyLabel, status],
      desc: 'Accessibility label for a Home status contact with a short status',
    );
  }

  String? _activitySemanticLabel(HomeActivityStatusKind? kind) {
    return switch (kind) {
      HomeActivityStatusKind.game => Intl.message(
        'playing a game',
        name: 'homeStatusActivityGameLabel',
        desc: 'Accessibility label for a Home status game activity badge',
      ),
      HomeActivityStatusKind.music => Intl.message(
        'listening to music',
        name: 'homeStatusActivityMusicLabel',
        desc: 'Accessibility label for a Home status music activity badge',
      ),
      null => null,
    };
  }
}

class _HomeActivityBadge extends StatelessWidget {
  const _HomeActivityBadge({required this.kind, required this.size});

  final HomeActivityStatusKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final backgroundColor = switch (kind) {
      HomeActivityStatusKind.game => scheme.secondaryContainer,
      HomeActivityStatusKind.music => scheme.tertiaryContainer,
    };
    final foregroundColor = switch (kind) {
      HomeActivityStatusKind.game => scheme.onSecondaryContainer,
      HomeActivityStatusKind.music => scheme.onTertiaryContainer,
    };
    final icon = switch (kind) {
      HomeActivityStatusKind.game => Icons.sports_esports_rounded,
      HomeActivityStatusKind.music => Icons.music_note_rounded,
    };

    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: backgroundColor,
          border: Border.all(color: scheme.surface, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: size * 0.58, color: foregroundColor),
        ),
      ),
    );
  }
}
