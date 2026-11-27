import 'dart:async';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/user_presence/user_presence_component.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/atoms/shimmer_loading.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:intergalactic/ui/mobile/mobile_surface.dart';
import 'package:intergalactic/ui/organisms/activity/game_activity_overlay_pill.dart';
import 'package:intergalactic/ui/organisms/user_profile/user_profile.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class UserPanel extends material.StatefulWidget {
  const UserPanel({
    super.key,
    required this.userId,
    required this.client,
    required this.contextRoom,
    this.initialMember,
    this.detailOverride,
    this.isDirectMessage = false,
    this.onTap,
  });
  final String userId;
  final Client client;
  final Member? initialMember;
  final String? detailOverride;
  final Room contextRoom;
  final bool isDirectMessage;
  final void Function()? onTap;

  @override
  State<UserPanel> createState() => _UserPanelState();
}

class _UserPanelState extends material.State<UserPanel> {
  late String displayName;
  late Color color;
  ImageProvider? avatar;
  String? detail;
  TextStyle? detailStringStyle;
  late UserPresence presence;
  UserActivity? gameActivity;

  StreamSubscription? sub;
  StreamSubscription<UserActivity?>? activitySub;

  @override
  initState() {
    presence = UserPresence(UserPresenceStatus.unknown);

    super.initState();
    initPresence();
    getInfoFromMember();
    initLocalGameActivity();
  }

  void getInfoFromMember() {
    if (widget.isDirectMessage) {
      displayName = widget.contextRoom.displayName;
      color = widget.contextRoom.defaultColor;
      avatar = widget.contextRoom.avatar;
      return;
    }

    final member =
        widget.initialMember ??
        widget.contextRoom.getMemberOrFallback(widget.userId);
    displayName = member.displayName;
    color = member.defaultColor;
    avatar = member.avatar;
    detail = member.detail;
  }

  @override
  void didUpdateWidget(covariant UserPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    getInfoFromMember();
    if (oldWidget.userId != widget.userId ||
        oldWidget.client != widget.client) {
      initLocalGameActivity();
    }
  }

  @override
  void dispose() {
    sub?.cancel();
    activitySub?.cancel();
    super.dispose();
  }

  void initLocalGameActivity() {
    activitySub?.cancel();
    activitySub = null;
    gameActivity = null;

    if (widget.userId != widget.client.self?.identifier) {
      return;
    }

    gameActivity = activityService.currentGameActivity;
    activitySub = activityService.onActivityChanged.listen((_) {
      if (!mounted) return;
      setState(() {
        gameActivity = activityService.currentGameActivity;
      });
    });
  }

  initPresence() async {
    final presenceComponent = widget.client
        .getComponent<UserPresenceComponent>();

    if (presenceComponent == null) {
      return;
    }

    sub = presenceComponent.onPresenceChanged
        .where((tuple) => tuple.$1 == widget.userId)
        .listen(onChanged);

    var p = await presenceComponent.getUserPresence(widget.userId);
    final presenceText = p.message?.message.trim();
    if (presenceText == null || presenceText.isEmpty) {
      final profile = await widget.client
          .getComponent<UserProfileComponent>()
          ?.getProfile(widget.userId);
      p = _presenceWithProfileFallback(p, profile);
    }

    if (mounted) {
      setState(() {
        presence = p;
      });
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    TextStyle? style;

    var currentStyle = material.Theme.of(context).textTheme.bodyMedium;
    style = currentStyle?.copyWith(
      fontFamily: Layout.mobile ? "NunitoSans" : null,
      fontSize: Layout.mobile ? 11 : 10,
      height: Layout.mobile ? 1.16 : null,
    );

    if (presence.message != null) {
      style = style?.copyWith(fontWeight: FontWeight.w500);
    } else {
      style = style?.copyWith(color: Theme.of(context).colorScheme.secondary);
    }

    return UserPanelView(
      displayName: displayName,
      avatar: avatar,
      detail: widget.detailOverride ?? detail,
      detailStringStyle: style,
      color: color,
      avatarColor: color,
      nameColor: widget.isDirectMessage ? null : color,
      avatarSize: widget.isDirectMessage ? 20 : 15,
      presence: widget.detailOverride != null ? null : presence,
      gameActivity: gameActivity,
      onClicked: widget.onTap ?? onUserPanelClicked,
    );
  }

  void onUserPanelClicked() {
    UserProfile.show(context, client: widget.client, userId: widget.userId);
  }

  void onChanged((String, UserPresence) event) {
    if (mounted) {
      setState(() {
        presence = event.$2;
      });
    }
  }
}

UserPresence _presenceWithProfileFallback(
  UserPresence presence,
  Profile? profile,
) {
  final presenceText = presence.message?.message.trim();
  if (presenceText != null && presenceText.isNotEmpty) {
    return presence;
  }

  if (profile is! ProfileWithPresence) {
    return presence;
  }

  final profileMessage = (profile as ProfileWithPresence).precence?.message;
  final profileText = profileMessage?.message.trim();
  if (profileMessage == null || profileText == null || profileText.isEmpty) {
    return presence;
  }

  return UserPresence(presence.status, message: profileMessage);
}

class UserPanelView extends material.StatelessWidget {
  const UserPanelView({
    super.key,
    this.avatar,
    required this.displayName,
    this.color,
    this.avatarColor,
    this.nameColor,
    this.detail,
    this.padding,
    this.shimmer = false,
    this.random = 0,
    this.detailStringStyle,
    this.presence,
    this.gameActivity,
    this.avatarSize = 15,
    this.onClicked,
  });
  final ImageProvider? avatar;
  final String displayName;
  final double avatarSize;
  final Color? color;
  final Color? avatarColor;
  final Color? nameColor;
  final String? detail;
  final EdgeInsets? padding;
  final UserPresence? presence;
  final UserActivity? gameActivity;
  final bool shimmer;
  final TextStyle? detailStringStyle;
  final double random;
  final void Function()? onClicked;

  @override
  Widget build(BuildContext context) {
    var shimmerColor = Theme.of(context).colorScheme.surfaceContainerHighest;
    final isMobile = Layout.mobile;
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(isMobile ? 20 : 5);
    final effectiveNameColor = nameColor == null
        ? null
        : AccessibilityScope.tokensOf(
            context,
          ).resolveIdentityTextColor(nameColor, scheme);
    final gamePill = gameActivity != null
        ? GameActivityOverlayPill.maybeFromActivity(
            gameActivity,
            compact: true,
            maxWidth: isMobile ? 170 : 150,
            overlay: false,
          )
        : GameActivityOverlayPill.maybeFromPresenceText(
            presence?.message?.message,
            compact: true,
            maxWidth: isMobile ? 170 : 150,
            overlay: false,
          );

    var widget = ClipRRect(
      borderRadius: radius,
      child: material.Material(
        color: material.Colors.transparent,
        child: material.InkWell(
          splashColor: material.Theme.of(context).highlightColor,
          onTap: onClicked,
          child: Padding(
            padding:
                padding ??
                (isMobile
                    ? const EdgeInsets.fromLTRB(7, 5, 7, 5)
                    : const EdgeInsets.fromLTRB(4, 2, 4, 2)),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                material.Stack(
                  alignment: AlignmentGeometry.bottomRight,
                  children: [
                    Avatar(
                      radius: avatarSize,
                      image: shimmer ? null : avatar,
                      placeholderText: shimmer ? " " : displayName,
                      placeholderColor: shimmer ? shimmerColor : avatarColor,
                    ),
                    if (presence?.status != null)
                      createPresenceIcon(context, presence!.status),
                  ],
                ),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
                    child: Container(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        mainAxisSize: material.MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (shimmer)
                            Container(
                              height: 10,
                              width: (random * 50) + 50,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                color: shimmerColor,
                              ),
                            ),
                          if (shimmer)
                            material.Padding(
                              padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
                              child: Container(
                                height: 8,
                                width: (random * 20) + 20,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  color: shimmerColor,
                                ),
                              ),
                            ),
                          if (!shimmer)
                            isMobile
                                ? material.Text(
                                    displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: material.Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          color: effectiveNameColor,
                                          fontFamily: "NunitoSans",
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.1,
                                        ),
                                  )
                                : tiamat.Text.name(
                                    displayName,
                                    color: effectiveNameColor,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                          if (gamePill != null)
                            material.Padding(
                              padding: const EdgeInsets.fromLTRB(0, 3, 0, 2),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: gamePill,
                              ),
                            ),
                          if (gamePill == null && presence?.message != null)
                            material.Row(
                              mainAxisSize: MainAxisSize.max,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (presence!.message?.messageType ==
                                    PresenceMessageType.userCustom)
                                  material.Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      0,
                                      2,
                                      4,
                                      0,
                                    ),
                                    child: Icon(Icons.chat_bubble, size: 10),
                                  ),
                                Flexible(
                                  child: material.Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      0,
                                      0,
                                      0,
                                      2,
                                    ),
                                    child: material.Text(
                                      presence!.message!.message,
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 2,
                                      style: detailStringStyle,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          if (presence?.message == null && detail != null)
                            material.Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Flexible(
                                  child: material.Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      0,
                                      0,
                                      0,
                                      2,
                                    ),
                                    child: buildDetailString(),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (shimmer) {
      return ShimmerLoading(isLoading: true, child: widget);
    }

    if (isMobile) {
      return MobileGlassEdgeHighlight(
        borderRadius: radius,
        style: MobileGlassHighlightStyle.composer,
        intensity: 0.24,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.surfaceContainerLow.withValues(alpha: 0.48),
                scheme.surface.withValues(alpha: 0.32),
              ],
            ),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.035)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 3, 4, 3),
            child: widget,
          ),
        ),
      );
    }

    return widget;
  }

  static Widget createPresenceIcon(
    BuildContext context,
    UserPresenceStatus status,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = AccessibilityScope.tokensOf(context);
    final nonColorCue = tokens.settings.nonColorStateCues;
    final backgroundColor = scheme.surfaceContainer;
    final color = switch (status) {
      UserPresenceStatus.offline => tokens.statusOffline,
      UserPresenceStatus.online => tokens.statusOnline,
      UserPresenceStatus.unavailable => tokens.statusBusy,
      UserPresenceStatus.unknown => tokens.statusUnknown,
    };
    final foregroundColor = switch (status) {
      UserPresenceStatus.offline => tokens.onStatusOffline,
      UserPresenceStatus.online => tokens.onStatusOnline,
      UserPresenceStatus.unavailable => tokens.onStatusBusy,
      UserPresenceStatus.unknown => tokens.onStatusUnknown,
    };
    final icon = switch (status) {
      UserPresenceStatus.offline => Icons.radio_button_unchecked_rounded,
      UserPresenceStatus.online => Icons.check_rounded,
      UserPresenceStatus.unavailable => Icons.schedule_rounded,
      UserPresenceStatus.unknown => Icons.question_mark_rounded,
    };
    final label = switch (status) {
      UserPresenceStatus.offline => "Offline",
      UserPresenceStatus.online => "Online",
      UserPresenceStatus.unavailable => "Away",
      UserPresenceStatus.unknown => "Unknown",
    };

    return Semantics(
      label: "Presence: $label",
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            width: 2,
            strokeAlign: BorderSide.strokeAlignOutside,
            color: backgroundColor,
          ),
        ),
        child: SizedBox(
          width: nonColorCue ? 12 : 8,
          height: nonColorCue ? 12 : 8,
          child: nonColorCue
              ? Icon(icon, size: 8, color: foregroundColor)
              : null,
        ),
      ),
    );
  }

  Widget buildDetailString() {
    if (detailStringStyle == null) {
      return tiamat.Text.labelLow(detail!);
    }

    return material.Text(
      detail!,
      overflow: TextOverflow.ellipsis,
      maxLines: 2,
      style: detailStringStyle?.copyWith(
        fontFamily: Layout.mobile ? "NunitoSans" : "Code",
      ),
    );
  }
}

class ClientConnectionStatusBadge extends StatelessWidget {
  const ClientConnectionStatusBadge({required this.client, super.key});

  final Client client;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ClientConnectionStatusUpdate>(
      stream: client.connectionStatusChanged.stream,
      initialData: client.connectionStatusChanged.value,
      builder: (context, snapshot) {
        return switch (snapshot.data?.status) {
          ClientConnectionStatus.connecting => Semantics(
            label: 'Account connecting',
            // excludeFromSemantics: the enclosing Semantics already
            // labels this dot ('Account connecting'), and the house
            // tooltip announces by default - without this a reader says it
            // twice, which is the D7 trap SpaceIcon hit.
            child: tiamat.Tooltip(
              text: 'Connecting',
              excludeFromSemantics: true,
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          ClientConnectionStatus.disconnected => Semantics(
            label: 'Account disconnected',
            // excludeFromSemantics: the enclosing Semantics already
            // labels this dot ('Account disconnected'), and the house
            // tooltip announces by default - without this a reader says it
            // twice, which is the D7 trap SpaceIcon hit.
            child: tiamat.Tooltip(
              text: 'Disconnected',
              excludeFromSemantics: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    width: 2,
                    strokeAlign: BorderSide.strokeAlignOutside,
                  ),
                ),
                child: SizedBox(width: 9, height: 9),
              ),
            ),
          ),
          _ => const SizedBox.shrink(),
        };
      },
    );
  }
}
