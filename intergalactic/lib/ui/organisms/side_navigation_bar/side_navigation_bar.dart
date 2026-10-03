import 'dart:async';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/top_level_space_order.dart';
import 'package:intergalactic/client/components/invitation/invitation_component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/favorite_rooms.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/accessibility/accessible_interactive_region.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:intergalactic/ui/atoms/dot_indicator.dart';
import 'package:intergalactic/ui/atoms/notification_badge.dart';
import 'package:intergalactic/ui/atoms/persistent_rail_icon_row.dart';
import 'package:intergalactic/ui/molecules/alert_view.dart';
import 'package:intergalactic/ui/molecules/space_selector.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/organisms/invitation_view/incoming_invitations_view.dart';
import 'package:intergalactic/ui/organisms/side_navigation_bar/side_navigation_bar_direct_messages.dart';
import 'package:intergalactic/ui/pages/get_or_create_room/get_or_create_room.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:intergalactic/utils/preference_image_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class SideNavigationBar extends StatefulWidget {
  const SideNavigationBar({
    super.key,
    this.currentUser,
    this.onSpaceSelected,
    this.onDirectMessageSelected,
    this.onSettingsSelected,
    this.onHomeSelected,
    this.onFavoritesSelected,
    this.favoritesSelected = false,
    this.extraEntryBuilders,
    this.width = 70.0,
    this.buttonSize = 70.0,
    this.filterClient,
    this.clearSpaceSelection,
  });

  static ValueKey settingsKey = const ValueKey(
    "SIDE_NAVIGATION_SETTINGS_BUTTON",
  );

  final List<Widget Function(double width)>? extraEntryBuilders;

  final Profile? currentUser;
  final Client? filterClient;
  final void Function(Space space)? onSpaceSelected;
  final void Function()? clearSpaceSelection;
  final void Function(Room room)? onDirectMessageSelected;
  final void Function()? onHomeSelected;
  final void Function()? onFavoritesSelected;
  final bool favoritesSelected;
  final void Function()? onSettingsSelected;
  final double width;
  final double buttonSize;

  @override
  State<SideNavigationBar> createState() => _SideNavigationBarState();

  static Widget tooltip(String text, Widget child, BuildContext context) {
    final showPersistentRailLabels =
        Layout.desktop && AccessibilityScope.of(context).persistentActionLabels;

    if (Layout.mobile) {
      return AspectRatio(aspectRatio: 1.0, child: child);
    }

    // The rail is vertical, so its tooltip belongs *beside* the icon rather
    // than over it (BUG-306). Material's Tooltip cannot do that at all - it
    // offers `preferBelow` only, above or below - which is why this uses the
    // house component. See DECISIONS.md 2026-08-18.
    //
    // Using the house component also takes this off `OverlayPortal`. Both rails
    // build their items inside a `ReorderableListView`, whose SDK-internal
    // GlobalKeys reparent items as the list changes; reparenting an
    // `OverlayPortal` mid-layout is the BUG-300 crash. `JustTheTooltip` uses an
    // `OverlayEntry`, which cannot reach that path.
    //
    // Deliberately silent to screen readers. `SpaceIcon` already wraps its
    // child in an `AccessibleInteractiveRegion` carrying the same
    // `displayName`, so announcing it here too would make a reader say it
    // twice - which is what the `material.Tooltip` this replaced did.
    final tooltip = tiamat.Tooltip(
      text: text,
      preferredDirection: AxisDirection.right,
      excludeFromSemantics: true,
      child: child,
    );

    if (showPersistentRailLabels) {
      return Align(alignment: Alignment.centerLeft, child: tooltip);
    }

    return AspectRatio(aspectRatio: 1, child: tooltip);
  }
}

class _SideNavigationBarState extends State<SideNavigationBar> {
  late ClientManager _clientManager;

  late List<StreamSubscription> subs;
  late List<StreamSubscription> invitationSubs;

  String get promptAddSpace => Intl.message(
    "Add Space",
    name: "promptAddSpace",
    desc: "Prompt to add a new space",
  );

  String get promptFavorites => Intl.message(
    "Favorites",
    name: "promptFavorites",
    desc: "Prompt to show the user's favorite rooms",
  );

  String get promptInvitations => Intl.message(
    "Invitations",
    name: "promptInvitations",
    desc: "Prompt to show the user's pending room invitations",
  );

  String get promptAlerts => Intl.message(
    "Alerts",
    name: "promptAlerts",
    desc: "Prompt to show active app alerts",
  );

  String get showInvitationsHint => Intl.message(
    "Show invitations",
    name: "showInvitationsHint",
    desc: "Accessibility hint for opening pending room invitations",
  );

  String get showAlertsHint => Intl.message(
    "Show alerts",
    name: "showAlertsHint",
    desc: "Accessibility hint for opening active app alerts",
  );

  String pendingInvitationCount(int count) => Intl.plural(
    count,
    one: "1 Invitation",
    other: "$count Invitations",
    args: [count],
    name: "pendingInvitationCount",
    desc: "Tooltip for the temporary sidebar invitations icon",
  );

  String pendingAlertCount(int count) => Intl.plural(
    count,
    one: "1 Alert",
    other: "$count Alerts",
    args: [count],
    name: "pendingAlertCount",
    desc: "Tooltip for the temporary sidebar alerts icon",
  );

  String invitationSemantics(int count) => Intl.plural(
    count,
    one: "Invitations, 1 new",
    other: "Invitations, $count new",
    args: [count],
    name: "invitationSemantics",
    desc: "Accessibility label for pending room invitations",
  );

  String alertSemantics(int count) => Intl.plural(
    count,
    one: "Alerts, 1 active",
    other: "Alerts, $count active",
    args: [count],
    name: "alertSemantics",
    desc: "Accessibility label for active app alerts",
  );

  late List<Space> topLevelSpaces;

  Client? filterClient;
  List<StreamSubscription> favoriteSubs = [];

  @override
  void initState() {
    _clientManager = Provider.of<ClientManager>(context, listen: false);
    invitationSubs = [];
    filterClient = widget.filterClient;

    void setFilterClient(Client? event) {
      setState(() {
        filterClient = event;

        getSpaces();
      });
    }

    subs = [
      _clientManager.onSpaceChildUpdated.stream.listen((_) => onSpaceUpdate()),
      _clientManager.onSpaceUpdated.stream.listen((_) => onSpaceUpdate()),
      _clientManager.onSpaceRemoved.listen((_) => onSpaceUpdate()),
      _clientManager.onSpaceAdded.listen((_) => onSpaceUpdate()),
      _clientManager.onClientAdded.stream.listen((_) => onClientListChanged()),
      _clientManager.onClientRemoved.stream.listen(
        (_) => onClientListChanged(),
      ),
      _clientManager.onClientUpdated.stream.listen(
        (_) => onClientProfileUpdated(),
      ),
      _clientManager.onSync.stream.listen((_) => _onClientSync()),
      _clientManager.onDirectMessageRoomUpdated.stream.listen(
        onDirectMessageUpdated,
      ),
      _clientManager.alertManager.onAlertAdded.listen((_) => onAlertsChanged()),
      _clientManager.alertManager.onAlertRemoved.listen(
        (_) => onAlertsChanged(),
      ),
      EventBus.setFilterClient.stream.listen(setFilterClient),
      preferences.onSettingChanged.listen((_) {
        if (mounted) {
          // Starring a room changes WHICH rooms this rail has to listen to, not
          // just what it draws.
          subscribeToFavorites(notify: false);
          setState(() {});
        }
      }),
      favoriteRoomStore.onChanged.listen((_) => reconcileFavorites()),
      // A favourite set on another device arrives as an m.tag change in a
      // sync, and touches no local preference at all - so without this the
      // rail would only notice it when something unrelated rebuilt it.
      _clientManager.onSync.stream.listen((_) => reconcileFavorites()),
    ];

    getSpaces();
    subscribeToInvitations(notify: false);
    subscribeToFavorites(notify: false);

    super.initState();
  }

  @override
  void didUpdateWidget(covariant SideNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterClient != widget.filterClient) {
      filterClient = widget.filterClient;
      getSpaces();
      subscribeToInvitations(notify: false);
      subscribeToFavorites(notify: false);
    }
  }

  void getSpaces() {
    List<Space> spaces;
    if (filterClient != null) {
      spaces = filterClient!.spaces.where((e) => e.isTopLevel).toList();
    } else {
      _clientManager = Provider.of<ClientManager>(context, listen: false);

      spaces = _clientManager.spaces.where((e) => e.isTopLevel).toList();
    }

    topLevelSpaces = applySavedSpaceOrder(spaces);
  }

  void onSpaceUpdate() {
    setState(() {
      getSpaces();
    });
  }

  void onClientListChanged() {
    final selectedClient = filterClient;
    final clearStaleFilter =
        selectedClient != null &&
        !_clientManager.clients.any((client) => client == selectedClient);

    setState(() {
      if (clearStaleFilter) {
        filterClient = null;
      }
      getSpaces();
    });

    if (clearStaleFilter) {
      EventBus.setFilterClient.add(null);
    }

    subscribeToInvitations();
    subscribeToFavorites(notify: false);
  }

  void onClientProfileUpdated() {
    if (!mounted) {
      return;
    }

    setState(() {
      getSpaces();
    });
  }

  Future<void> _onClientSync() async {
    var orderChanged = false;
    try {
      for (final client in _clientManager.clients) {
        orderChanged =
            topLevelSpaceOrderStore.onClientSync(client) || orderChanged;
        await topLevelSpaceOrderStore.migrateClient(client, topLevelSpaces);
      }
    } catch (error, trace) {
      Log.onError(
        error,
        trace,
        content: 'Failed to sync top-level Space order',
      );
      return;
    }
    if (mounted && orderChanged) onSpaceUpdate();
  }

  void onDirectMessageUpdated(Room room) {
    setState(() {});
  }

  void onAlertsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    for (var sub in subs) {
      sub.cancel();
    }
    for (var sub in invitationSubs) {
      sub.cancel();
    }
    for (var sub in favoriteSubs) {
      sub.cancel();
    }
    super.dispose();
  }

  Iterable<InvitationComponent> get invitationComponents => _clientManager
      .clients
      .where((client) => filterClient == null || client == filterClient)
      .map((client) => client.getComponent<InvitationComponent>())
      .whereType<InvitationComponent>();

  Iterable<InvitationComponent> get allInvitationComponents => _clientManager
      .clients
      .map((client) => client.getComponent<InvitationComponent>())
      .whereType<InvitationComponent>();

  int get alertCount => _clientManager.alertManager.alerts.length;

  /// Rooms the user has starred, filtered the same way the favourites list
  /// itself filters them.
  Iterable<Room> get favoriteRooms => _clientManager.rooms.where((room) {
    if (filterClient != null && room.client != filterClient) {
      return false;
    }

    return favoriteRoomStore.isFavorite(room);
  });

  /// What the favourites button has to say for itself.
  ///
  /// A space shows unread state for the rooms inside it, so a favourited room
  /// that is also in a space was already announced - by the space, on the route
  /// the user was trying to leave. The favourites button said nothing, so the
  /// only place a new message was ever visible was the space rail, and the
  /// habit it teaches is to keep using spaces.
  ///
  FavoritesUnread get favoritesUnread => FavoritesUnread.from(favoriteRooms);

  /// A favourite room's unread state changes on its own schedule - a message
  /// arriving, or being read somewhere else. Nothing else in this rail listens
  /// to individual rooms, so without these the indicator would only appear when
  /// something unrelated happened to rebuild the rail.
  Set<String> lastFavoriteIds = {};

  /// Re-subscribe and redraw only when the starred SET changed.
  ///
  /// This runs on every sync, and a favourite room's own unread changes are
  /// already handled by [subscribeToFavorites]; without the comparison the
  /// rail would rebuild on all traffic in every room.
  void reconcileFavorites() {
    if (!mounted) {
      return;
    }

    final ids = favoriteRooms.map((room) => room.favoriteStorageId).toSet();
    if (setEquals(ids, lastFavoriteIds)) {
      return;
    }

    lastFavoriteIds = ids;
    subscribeToFavorites(notify: false);
    setState(() {});
  }

  void subscribeToFavorites({bool notify = true}) {
    for (final sub in favoriteSubs) {
      sub.cancel();
    }

    favoriteSubs = [
      for (final room in favoriteRooms)
        room.onUpdate.listen((_) {
          if (mounted) {
            setState(() {});
          }
        }),
    ];

    if (notify && mounted) {
      setState(() {});
    }
  }

  // Invitation removals notify before mutating the backing list, so avoid
  // caching this value inside the stream listener.
  int get invitationCount => invitationComponents.fold<int>(
    0,
    (count, component) => count + component.invitations.length,
  );

  void subscribeToInvitations({bool notify = true}) {
    for (var sub in invitationSubs) {
      sub.cancel();
    }

    invitationSubs = [
      for (var component in allInvitationComponents)
        component.invitations.onListUpdated.listen((_) {
          if (mounted) {
            setState(() {});
          }
        }),
    ];

    if (notify && mounted) {
      setState(() {});
    }
  }

  Future<void> showInvitations() {
    return AdaptiveDialog.show<void>(
      context,
      title: promptInvitations,
      initialHeightMobile: 0.45,
      builder: (_) =>
          IncomingInvitationsWidget(_clientManager, filterClient: filterClient),
    );
  }

  Future<void> showAlerts() {
    return AdaptiveDialog.show<void>(
      context,
      title: promptAlerts,
      initialHeightMobile: 0.45,
      builder: (_) => AlertListView(_clientManager.alertManager),
    );
  }

  ImageProvider? _favoritesIconImage() {
    final bytes = decodePreferenceImageData(
      preferences.favoritesIconImageData.value,
    );
    return bytes == null ? null : MemoryImage(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final width = widget.width;
    final buttonSize = widget.buttonSize;
    final pendingInvitations = invitationCount;
    final favoritesIcon = _favoritesIconImage();
    final favorites = favoritesUnread;
    final favoritesLabel = favoritesUnreadSemantics(favorites);
    final railPersistentLabelMaxWidth = (width - buttonSize - 18)
        .clamp(48.0, 96.0)
        .toDouble();

    return SizedBox(
      width: width,
      child: Column(
        children: [
          // Home button — moved out of SpaceSelector header
          Padding(
            padding: SpaceSelector.padding,
            child: SideNavigationBar.tooltip(
              CommonStrings.promptHome,
              _RailActionButton(
                width: width,
                buttonSize: buttonSize,
                label: CommonStrings.promptHome,
                semanticHint: "Open home",
                icon: Icons.home,
                onTap: widget.onHomeSelected,
              ),
              context,
            ),
          ),
          // DM list — moved out so its ReorderableListView is
          // no longer nested inside SpaceSelector's ScrollView
          Padding(
            padding: SpaceSelector.padding,
            child: SideNavigationBarDirectMessages(
              _clientManager.directMessages,
              width: buttonSize,
              onRoomTapped: widget.onDirectMessageSelected,
            ),
          ),
          // Favorites button — moved out of SpaceSelector header
          Padding(
            padding: SpaceSelector.padding,
            child: Stack(
              alignment: Alignment.centerLeft,
              clipBehavior: Clip.none,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
                  child: SideNavigationBar.tooltip(
                    promptFavorites,
                    _RailActionButton(
                      width: width,
                      buttonSize: buttonSize,
                      label: promptFavorites,
                      semanticLabel: favoritesLabel ?? promptFavorites,
                      semanticHint: widget.favoritesSelected
                          ? "Selected favorites"
                          : "Open favorites",
                      selected: widget.favoritesSelected,
                      image: favoritesIcon,
                      icon: favoritesIcon == null ? Icons.star : null,
                      notificationCount: favorites.notificationCount,
                      highlightedNotificationCount:
                          favorites.highlightedNotificationCount,
                      roomWideMentionNotification:
                          favorites.roomWideMentionNotification,
                      showNotificationDot: false,
                      onTap: widget.onFavoritesSelected,
                    ),
                    context,
                  ),
                ),
                if (favorites.notificationCount > 0)
                  SpaceSelector.unreadIndicator(),
              ],
            ),
          ),
          if (pendingInvitations > 0)
            Padding(
              padding:
                  SpaceSelector.padding + const EdgeInsets.fromLTRB(0, 4, 0, 0),
              child: SideNavigationBar.tooltip(
                pendingInvitationCount(pendingInvitations),
                _AttentionSpaceButton(
                  count: pendingInvitations,
                  icon: Icons.mail_rounded,
                  tone: NotificationBadgeTone.accent,
                  semanticsLabel: invitationSemantics(pendingInvitations),
                  onTapHint: showInvitationsHint,
                  persistentLabel: Layout.desktop ? promptInvitations : null,
                  persistentLabelMaxWidth: railPersistentLabelMaxWidth,
                  onTap: showInvitations,
                ),
                context,
              ),
            ),
          if (alertCount > 0)
            Padding(
              padding:
                  SpaceSelector.padding + const EdgeInsets.fromLTRB(0, 4, 0, 0),
              child: SideNavigationBar.tooltip(
                pendingAlertCount(alertCount),
                _AttentionSpaceButton(
                  count: alertCount,
                  icon: Icons.priority_high_rounded,
                  tone: NotificationBadgeTone.warning,
                  semanticsLabel: alertSemantics(alertCount),
                  onTapHint: showAlertsHint,
                  persistentLabel: Layout.desktop ? promptAlerts : null,
                  persistentLabelMaxWidth: railPersistentLabelMaxWidth,
                  onTap: showAlerts,
                ),
                context,
              ),
            ),
          const tiamat.Seperator(),
          // Spaces — now gets remaining vertical space
          Expanded(
            child: SpaceSelector(
              topLevelSpaces,
              width: buttonSize,
              onReordered: onSpacesReordered,
              clearSelection: widget.clearSpaceSelection,
              shouldShowAvatarForSpace: shouldShowAvatarForSpace,
              footer: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 2, 0, 4),
                    child: SideNavigationBar.tooltip(
                      promptAddSpace,
                      _RailActionButton(
                        width: width,
                        buttonSize: buttonSize,
                        label: promptAddSpace,
                        semanticHint: "Create a space",
                        icon: Icons.add,
                        onTap: () {
                          GetOrCreateRoom.show(
                            null,
                            context,
                            pickExisting: false,
                            createSpace: true,
                          );
                        },
                      ),
                      context,
                    ),
                  ),
                ],
              ),
              onSelected: (space) {
                widget.onSpaceSelected?.call(space);
              },
            ),
          ),
          if (widget.extraEntryBuilders != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.start,
              children: widget.extraEntryBuilders!
                  .map((e) => e(width))
                  .toList(),
            ),
        ],
      ),
    );
  }

  bool shouldShowAvatarForSpace(Space space) {
    var spaces = _clientManager.spaces.where(
      (element) => element.identifier == space.identifier,
    );
    return spaces.length > 1;
  }

  List<Space> applySavedSpaceOrder(List<Space> spaces) {
    final savedOrder = preferences.getTopLevelSpaceOrder();
    if (savedOrder.isEmpty) {
      return topLevelSpaceOrderStore.apply(spaces);
    }

    final spaceMap = <String, Space>{
      for (final space in spaces) space.localId: space,
    };

    final ordered = <Space>[];
    for (final id in savedOrder) {
      final space = spaceMap.remove(id);
      if (space != null) {
        ordered.add(space);
      }
    }

    for (final space in spaces) {
      if (spaceMap.containsKey(space.localId)) {
        ordered.add(space);
      }
    }

    return topLevelSpaceOrderStore.apply(ordered);
  }

  Future<void> onSpacesReordered(List<Space> spaces) async {
    final previous = List<Space>.from(topLevelSpaces);
    setState(() {
      topLevelSpaces = spaces;
    });

    try {
      await topLevelSpaceOrderStore.saveReorder(
        previous: previous,
        reordered: spaces,
      );
      await preferences.setTopLevelSpaceOrder(
        spaces.map((space) => space.localId).toList(),
      );
    } catch (error, trace) {
      Log.onError(error, trace, content: 'Failed to reorder top-level Spaces');
      if (mounted) setState(() => topLevelSpaces = previous);
    }
  }
}

class _RailActionButton extends StatelessWidget {
  const _RailActionButton({
    required this.width,
    required this.buttonSize,
    required this.label,
    required this.semanticHint,
    required this.onTap,
    this.semanticLabel,
    this.icon,
    this.image,
    this.selected = false,
    this.notificationCount = 0,
    this.highlightedNotificationCount = 0,
    this.roomWideMentionNotification = false,
    this.showNotificationDot = true,
  });

  final double width;
  final double buttonSize;
  final String label;

  /// Announced in place of [label] when the button carries state a sighted
  /// user reads off the marks below, which sit inside the excluded subtree.
  final String? semanticLabel;
  final String semanticHint;
  final VoidCallback? onTap;
  final IconData? icon;
  final ImageProvider? image;
  final bool selected;

  /// Unread state, drawn with the same two marks a space icon uses: a dot on
  /// the rail edge for ordinary unread, a count badge for anything that named
  /// you. Zero on every other rail button, which is why they are optional.
  final int notificationCount;
  final int highlightedNotificationCount;
  final bool roomWideMentionNotification;
  final bool showNotificationDot;

  @override
  Widget build(BuildContext context) {
    final showPersistentLabel = shouldShowPersistentRailIconLabel(context);
    final iconSize = persistentRailIconSizeFor(
      baseSize: buttonSize,
      showPersistentLabel: showPersistentLabel,
    );
    final radius = BorderRadius.circular(iconSize * 0.34);
    final selectedBorder = selected && !showPersistentLabel
        ? Border.all(
            color: Theme.of(context).colorScheme.inverseSurface,
            width: 3,
            strokeAlign: 0.5,
          )
        : null;
    final iconWidget = tiamat.ImageButton(
      size: iconSize,
      image: image,
      icon: image == null ? icon : null,
      border: selectedBorder,
      onTap: showPersistentLabel ? null : onTap,
    );
    final showBadge =
        roomWideMentionNotification || highlightedNotificationCount > 0;
    final markedIcon = notificationCount > 0 || showBadge
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              iconWidget,
              if (showNotificationDot && notificationCount > 0)
                Positioned(
                  left: -6,
                  top: iconSize / 2 - 5,
                  child: const IgnorePointer(child: DotIndicator()),
                ),
              if (showBadge)
                Positioned(
                  right: 0,
                  top: 0,
                  child: IgnorePointer(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: NotificationBadge(
                        highlightedNotificationCount,
                        exclamation: roomWideMentionNotification,
                        tone: roomWideMentionNotification
                            ? NotificationBadgeTone.warning
                            : NotificationBadgeTone.danger,
                      ),
                    ),
                  ),
                ),
            ],
          )
        : iconWidget;
    final content = showPersistentLabel
        ? PersistentRailIconRow(
            icon: markedIcon,
            iconSize: iconSize,
            label: label,
            selected: selected,
          )
        : markedIcon;
    final regionRadius = showPersistentLabel
        ? const BorderRadius.all(Radius.circular(8))
        : radius;

    return AccessibleInteractiveRegion(
      semanticLabel: semanticLabel ?? label,
      semanticHint: semanticHint,
      selected: selected,
      onActivate: onTap,
      borderRadius: regionRadius,
      excludeChildSemantics: true,
      child: showPersistentLabel
          ? SizedBox(width: width, child: content)
          : content,
    );
  }
}

/// What the favourites rail button has to draw.
class FavoritesUnread {
  const FavoritesUnread({
    required this.notificationCount,
    required this.highlightedNotificationCount,
    required this.roomWideMentionNotification,
  });

  static const FavoritesUnread none = FavoritesUnread(
    notificationCount: 0,
    highlightedNotificationCount: 0,
    roomWideMentionNotification: false,
  );

  /// Rolls a set of favourite rooms into one mark.
  ///
  /// Reads the `display*` counts rather than the raw ones, so a muted
  /// favourite stays silent here exactly as it does everywhere else - a rail
  /// dot the user cannot trace to any room they can hear is worse than no dot.
  factory FavoritesUnread.from(Iterable<Room> rooms) {
    var notifications = 0;
    var highlights = 0;
    var roomWideMention = false;

    for (final room in rooms) {
      notifications += room.displayNotificationCount;
      highlights += room.displayHighlightedNotificationCount;
      roomWideMention |= room.displayRoomWideMentionNotification;
    }

    return FavoritesUnread(
      notificationCount: notifications,
      highlightedNotificationCount: highlights,
      roomWideMentionNotification: roomWideMention,
    );
  }

  final int notificationCount;
  final int highlightedNotificationCount;
  final bool roomWideMentionNotification;
}

/// What a screen reader is told about the favourites button, or null when the
/// plain name already says everything.
///
/// The dot and the badge are drawn inside `excludeChildSemantics`, so nothing
/// under the button can announce itself and this label is the only route to
/// the unread state. Mentions win over the ordinary count because that is the
/// mark a user acts on, the same order `_AttentionSpaceButton` reads in.
String? favoritesUnreadSemantics(FavoritesUnread favorites) {
  if (favorites.highlightedNotificationCount > 0) {
    return favoritesMentionSemantics(favorites.highlightedNotificationCount);
  }
  if (favorites.roomWideMentionNotification) {
    return favoritesRoomWideMentionSemantics;
  }
  if (favorites.notificationCount > 0) {
    return favoritesUnreadCountSemantics(favorites.notificationCount);
  }
  return null;
}

String favoritesUnreadCountSemantics(int count) => Intl.plural(
  count,
  one: "Favorites, 1 unread",
  other: "Favorites, $count unread",
  args: [count],
  name: "favoritesUnreadCountSemantics",
  desc: "Accessibility label for unread messages in the user's favorite rooms",
);

String favoritesMentionSemantics(int count) => Intl.plural(
  count,
  one: "Favorites, 1 mention",
  other: "Favorites, $count mentions",
  args: [count],
  name: "favoritesMentionSemantics",
  desc: "Accessibility label for mentions in the user's favorite rooms",
);

String get favoritesRoomWideMentionSemantics => Intl.message(
  "Favorites, room mention",
  name: "favoritesRoomWideMentionSemantics",
  desc:
      "Accessibility label for an @room mention in one of the user's favorite "
      "rooms",
);

class _AttentionSpaceButton extends StatelessWidget {
  const _AttentionSpaceButton({
    required this.count,
    required this.icon,
    required this.tone,
    required this.semanticsLabel,
    required this.onTapHint,
    this.persistentLabel,
    this.persistentLabelMaxWidth = 72,
    required this.onTap,
  });

  final int count;
  final IconData icon;
  final NotificationBadgeTone tone;
  final String semanticsLabel;
  final String onTapHint;
  final String? persistentLabel;
  final double persistentLabelMaxWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = NotificationBadgeColors.from(context, tone);

    return AccessibleInteractiveRegion(
      semanticLabel: semanticsLabel,
      semanticOnTapHint: onTapHint,
      onActivate: onTap,
      borderRadius: BorderRadius.circular(22),
      excludeChildSemantics: true,
      persistentLabel: persistentLabel,
      persistentLabelMaxWidth: persistentLabelMaxWidth,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, color: colors.foreground, size: 38),
                if (count > 0)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: NotificationBadge(
                      count,
                      size: 18,
                      tone: NotificationBadgeTone.neutral,
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
