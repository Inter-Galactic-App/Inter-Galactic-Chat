import 'dart:async';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/user_presence/user_presence_component.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/ui/atoms/shimmer_loading.dart';
import 'package:intergalactic/ui/mobile/mobile_surface.dart';
import 'package:intergalactic/ui/organisms/user_profile/user_profile.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class UserPanel extends material.StatefulWidget {
  const UserPanel(
      {super.key,
      required this.userId,
      required this.client,
      required this.contextRoom,
      this.initialMember,
      this.detailOverride,
      this.isDirectMessage = false,
      this.onTap});
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

  StreamSubscription? sub;

  @override
  initState() {
    presence = UserPresence(UserPresenceStatus.unknown);

    super.initState();
    initPresence();
    getInfoFromMember();
  }

  void getInfoFromMember() {
    if (widget.isDirectMessage) {
      displayName = widget.contextRoom.displayName;
      color = widget.contextRoom.defaultColor;
      avatar = widget.contextRoom.avatar;
      return;
    }

    final member = widget.initialMember ??
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
  }

  @override
  dispose() {
    super.dispose();
    sub?.cancel();
  }

  initPresence() async {
    final presenceComponent =
        widget.client.getComponent<UserPresenceComponent>();

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
      style = style?.copyWith(
        fontWeight: FontWeight.w500,
      );
    } else {
      style = style?.copyWith(
        color: Theme.of(context).colorScheme.secondary,
      );
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
  const UserPanelView(
      {super.key,
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
      this.avatarSize = 15,
      this.onClicked});
  final ImageProvider? avatar;
  final String displayName;
  final double avatarSize;
  final Color? color;
  final Color? avatarColor;
  final Color? nameColor;
  final String? detail;
  final EdgeInsets? padding;
  final UserPresence? presence;
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

    var widget = ClipRRect(
      borderRadius: radius,
      child: material.Material(
        color: material.Colors.transparent,
        child: material.InkWell(
          splashColor: material.Theme.of(context).highlightColor,
          onTap: onClicked,
          child: Padding(
            padding: padding ??
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
                                  color: shimmerColor),
                            ),
                          if (shimmer)
                            material.Padding(
                              padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
                              child: Container(
                                height: 8,
                                width: (random * 20) + 20,
                                decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                    color: shimmerColor),
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
                                          color: nameColor,
                                          fontFamily: "NunitoSans",
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.1,
                                        ),
                                  )
                                : tiamat.Text.name(
                                    displayName,
                                    color: nameColor,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                          if (presence?.message != null)
                            material.Row(
                              mainAxisSize: MainAxisSize.max,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (presence!.message?.messageType ==
                                    PresenceMessageType.userCustom)
                                  material.Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(0, 2, 4, 0),
                                    child: Icon(
                                      Icons.chat_bubble,
                                      size: 10,
                                    ),
                                  ),
                                Flexible(
                                  child: material.Padding(
                                      padding:
                                          const EdgeInsets.fromLTRB(0, 0, 0, 2),
                                      child: material.Text(
                                        presence!.message!.message,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 2,
                                        style: detailStringStyle,
                                      )),
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
                                    padding:
                                        const EdgeInsets.fromLTRB(0, 0, 0, 2),
                                    child: buildDetailString(),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                )
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
            border: Border.all(
              color: scheme.outline.withValues(alpha: 0.035),
            ),
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

  static material.DecoratedBox createPresenceIcon(
      BuildContext context, UserPresenceStatus status) {
    var scheme = Theme.of(context).colorScheme;

    var backgroundColor = scheme.surfaceContainer;

    var color = switch (status) {
      UserPresenceStatus.offline => Colors.grey,
      UserPresenceStatus.online => Colors.lightGreen,
      UserPresenceStatus.unavailable => Colors.amber,
      UserPresenceStatus.unknown => Colors.grey,
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
            width: 2,
            strokeAlign: BorderSide.strokeAlignOutside,
            color: backgroundColor),
      ),
      child: SizedBox(
        width: 8,
        height: 8,
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
