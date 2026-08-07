import 'dart:async';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/invitation/invitation_component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/accessibility/accessible_interactive_region.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
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
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:just_the_tooltip/just_the_tooltip.dart';
import 'package:provider/provider.dart';
import 'package:tiamat/tiamat.dart';
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

    final tooltip = JustTheTooltip(
      content: Padding(
        padding: const EdgeInsets.all(8.0),
        child: tiamat.Text(text),
      ),
      preferredDirection: AxisDirection.right,
      offset: 5,
      tailLength: 5,
      tailBaseWidth: 5,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
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
          setState(() {});
        }
      }),
    ];

    getSpaces();
    subscribeToInvitations(notify: false);

    super.initState();
  }

  @override
  void didUpdateWidget(covariant SideNavigationBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterClient != widget.filterClient) {
      filterClient = widget.filterClient;
      getSpaces();
      subscribeToInvitations(notify: false);
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
  }

  void onClientProfileUpdated() {
    if (!mounted) {
      return;
    }

    setState(() {
      getSpaces();
    });
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
            padding:
                SpaceSelector.padding + const EdgeInsets.fromLTRB(0, 4, 0, 0),
            child: SideNavigationBar.tooltip(
              promptFavorites,
              _RailActionButton(
                width: width,
                buttonSize: buttonSize,
                label: promptFavorites,
                semanticHint: widget.favoritesSelected
                    ? "Selected favorites"
                    : "Open favorites",
                selected: widget.favoritesSelected,
                image: favoritesIcon,
                icon: favoritesIcon == null ? Icons.star : null,
                onTap: widget.onFavoritesSelected,
              ),
              context,
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
          const Seperator(),
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
      return spaces;
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

    return ordered;
  }

  Future<void> onSpacesReordered(List<Space> spaces) async {
    setState(() {
      topLevelSpaces = spaces;
    });

    await preferences.setTopLevelSpaceOrder(
      spaces.map((space) => space.localId).toList(),
    );
  }
}

class _RailActionButton extends StatelessWidget {
  const _RailActionButton({
    required this.width,
    required this.buttonSize,
    required this.label,
    required this.semanticHint,
    required this.onTap,
    this.icon,
    this.image,
    this.selected = false,
  });

  final double width;
  final double buttonSize;
  final String label;
  final String semanticHint;
  final VoidCallback? onTap;
  final IconData? icon;
  final ImageProvider? image;
  final bool selected;

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
    final iconWidget = ImageButton(
      size: iconSize,
      image: image,
      icon: image == null ? icon : null,
      border: selectedBorder,
      onTap: showPersistentLabel ? null : onTap,
    );
    final content = showPersistentLabel
        ? PersistentRailIconRow(
            icon: iconWidget,
            iconSize: iconSize,
            label: label,
            selected: selected,
          )
        : iconWidget;
    final regionRadius = showPersistentLabel
        ? const BorderRadius.all(Radius.circular(8))
        : radius;

    return AccessibleInteractiveRegion(
      semanticLabel: label,
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
