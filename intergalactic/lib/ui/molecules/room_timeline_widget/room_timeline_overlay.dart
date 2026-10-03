import 'dart:math' as math;

import 'package:intergalactic/client/components/emoticon_recent/recent_emoticon_component.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/atoms/emoji_widget.dart';
import 'package:intergalactic/ui/molecules/room_timeline_widget/room_timeline_overlay_button.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_event_menu.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/atoms/context_menu.dart';
import 'package:tiamat/atoms/tile.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

import 'package:flutter/material.dart' as m;

class TimelineOverlay extends StatefulWidget {
  const TimelineOverlay({
    required this.link,
    this.showMessageMenu = true,
    this.jumpToLatest,
    this.bottomInset = 0,
    super.key,
  });
  final LayerLink link;
  final bool showMessageMenu;
  final Function()? jumpToLatest;
  final double bottomInset;

  @override
  State<TimelineOverlay> createState() => TimelineOverlayState();
}

class TimelineOverlayState extends State<TimelineOverlay> {
  static const double hiddenJumpButtonBottom = -96;
  static const double iosJumpButtonComposerOverlap = 12;

  TimelineEventMenu? currentMenu;
  PageStorageBucket storage = PageStorageBucket();

  TimelineEventMenuEntry? selectedEntry;
  GlobalKey menuKey = GlobalKey();

  bool? openDownwards;

  final double tooltipHeight = 300;

  bool isAttatchedToBottom = true;

  String get labelJumpToLatest => Intl.message(
    "Jump to latest",
    desc:
        "Label for the button which jumps the room timeline view to the latest message",
    name: "labelJumpToLatest",
  );

  @override
  Widget build(BuildContext context) {
    final jumpButtonBottom =
        Layout.mobile && PlatformUtils.isIOS && widget.bottomInset > 0
        ? math.max(0.0, widget.bottomInset - iosJumpButtonComposerOverlap)
        : widget.bottomInset;

    // The LayoutBuilder reports the timeline's own width. The hover menu is a
    // follower anchored at the message's right edge that grows leftwards, and
    // it lives inside the timeline's ClipRect - so in the call-room side rail
    // (280-340 px) a menu built for a full-width chat was cut off at the
    // panel's left edge. The right-click menu is unaffected because it is
    // rendered in the root overlay.
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          if (widget.showMessageMenu)
            Positioned(
              right: 0,
              top: 0,
              child: CompositedTransformFollower(
                targetAnchor: Alignment.topRight,
                followerAnchor: openDownwards == true
                    ? Alignment.topRight
                    : Alignment.bottomRight,
                showWhenUnlinked: false,
                offset: Offset(-20, openDownwards == true ? -50 : 0),
                link: widget.link,
                child: ExcludeSemantics(
                  child: MouseRegion(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                      child: buildTooltipMenu(
                        child: buildPrimaryMenu(
                          context,
                          maxWidth: constraints.maxWidth,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          AnimatedPositioned(
            left: 0,
            right: 0,
            bottom: isAttatchedToBottom
                ? hiddenJumpButtonBottom
                : jumpButtonBottom,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOutCubic,
            child: IgnorePointer(
              ignoring: isAttatchedToBottom,
              child: AnimatedOpacity(
                opacity: isAttatchedToBottom ? 0 : 1,
                duration: const Duration(milliseconds: 120),
                child: Center(
                  child: RoomTimelineOverlayButton(
                    text: labelJumpToLatest,
                    onTap: widget.jumpToLatest,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildTooltipMenu({required Widget child}) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        verticalDirection: openDownwards == true
            ? VerticalDirection.up
            : VerticalDirection.down,
        children: [
          if (selectedEntry != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Tile.surfaceContainer(
                  child: SizedBox(
                    width: tooltipHeight,
                    height: tooltipHeight,
                    child: MouseRegion(
                      child: selectedEntry!.secondaryMenuBuilder?.call(
                        context,
                        clearSelection,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Flexible(child: child),
        ],
      ),
    );
  }

  /// Width of one action button, quick reactions included.
  static const double actionSize = 30;

  /// Everything in the menu row that is not a quick reaction, in pixels:
  /// the follower's outer padding (20 + 20), the row's inner padding (4 + 4),
  /// the 1 px border on each side, and the default `VerticalDivider` width
  /// after the add-reaction button.
  static const double _menuOuterPadding = 40;
  static const double _menuInnerPadding = 8;
  static const double _menuBorder = 2;
  static const double _dividerWidth = 16;

  /// How many quick reactions fit beside the fixed actions in [maxWidth].
  ///
  /// The fixed actions - add reaction, the primary actions, and the options
  /// button - always show; quick reactions are the only part that can give.
  /// Clamped to `[0, quickReactionCount]`. An unbounded width - a
  /// LayoutBuilder under a horizontally unconstrained parent reports
  /// infinity - fits everything; `(infinity / size).floor()` throws.
  static int quickReactionsThatFit({
    required double maxWidth,
    required int quickReactionCount,
    required int primaryActionCount,
    required bool hasAddReaction,
  }) {
    if (!maxWidth.isFinite) {
      return quickReactionCount;
    }
    final fixed =
        _menuOuterPadding +
        _menuInnerPadding +
        _menuBorder +
        (hasAddReaction ? actionSize + _dividerWidth : 0) +
        primaryActionCount * actionSize +
        actionSize; // options
    final room = maxWidth - fixed;
    if (room <= 0) {
      return 0;
    }
    return math.min((room / actionSize).floor(), quickReactionCount);
  }

  Widget buildPrimaryMenu(BuildContext context, {required double maxWidth}) {
    var reactions = currentMenu?.quickReactions;
    if (reactions != null) {
      final fit = quickReactionsThatFit(
        maxWidth: maxWidth,
        quickReactionCount: math.min(
          reactions.length,
          RecentEmoticonComponent.quickReactionCount,
        ),
        primaryActionCount: currentMenu?.primaryActions.length ?? 0,
        hasAddReaction: currentMenu?.addReactionAction != null,
      );
      if (reactions.length > fit) {
        reactions = reactions.sublist(0, fit);
      }
    }
    const double size = actionSize;

    return MouseRegion(
      child: DecoratedBox(
        key: menuKey,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: m.Theme.of(context).colorScheme.surfaceDim,
          border: Border.all(
            color: m.Theme.of(context).colorScheme.surfaceContainerHighest,
            width: 1,
          ),
        ),
        child: currentMenu != null
            ? Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                child: Row(
                  children: [
                    for (var e in reactions!)
                      buildAction(
                        name: e.shortcode,
                        child: EmojiWidget(
                          e,
                          height: size / 1.5,
                          padding: const EdgeInsetsGeometry.all(2),
                        ),
                        onTap: () {
                          currentMenu?.timeline.room.addReaction(
                            currentMenu!.event,
                            e,
                          );
                        },
                      ),
                    if (currentMenu!.addReactionAction != null)
                      buildAction(
                        name: currentMenu!.addReactionAction!.name,
                        child: m.Icon(
                          currentMenu!.addReactionAction!.icon,
                          color: Theme.of(context).colorScheme.secondary,
                          size: size / 1.5,
                        ),
                        onTap: () =>
                            togglePopupMenu(currentMenu!.addReactionAction!),
                      ),
                    if (currentMenu!.addReactionAction != null)
                      SizedBox(height: 10, child: VerticalDivider()),
                    for (var e in currentMenu!.primaryActions)
                      buildAction(
                        name: e.name,
                        child: m.Icon(
                          e.icon,
                          color: Theme.of(context).colorScheme.secondary,
                          size: size / 1.5,
                        ),
                        size: size,
                        onTap: e.secondaryMenuBuilder != null
                            ? () => togglePopupMenu(e)
                            : () => e.action?.call(context),
                      ),
                    buildAction(
                      name: "Options",
                      child: Icon(m.Icons.more_vert),
                      size: size,
                      contextMenuItems: currentMenu!.secondaryActions
                          .map(
                            (e) => ContextMenuItem(
                              text: e.name,
                              icon: e.icon,
                              onPressed: () => e.action?.call(context),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              )
            : Container(),
      ),
    );
  }

  void clearSelection() {
    setState(() {
      openDownwards = null;
      selectedEntry = null;
    });
  }

  void togglePopupMenu(TimelineEventMenuEntry entry) {
    if (selectedEntry == entry) {
      setState(() {
        selectedEntry = null;
      });
    } else {
      var obj = menuKey.currentContext?.findRenderObject() as RenderBox;
      var pos = obj.localToGlobal(Offset.zero) * preferences.appScale.value;
      openDownwards = pos.dy < (tooltipHeight + 100);
      setState(() {
        selectedEntry = entry;
      });
    }
  }

  void setMenu(TimelineEventMenu menu) {
    if (BuildConfig.DEBUG || kDebugMode) {
      // Debug level for the same reason as `timeline_entry_selected`: this is
      // routine hover behaviour, not a fault.
      Log.d(
        'overlay_lifecycle transition=timeline_overlay_menu_set',
        category: LogCategory.media,
        source: 'overlay-lifecycle',
      );
    }
    setState(() {
      currentMenu = menu;
      selectedEntry = null;
    });
  }

  void setAttachedToBottom(bool value) {
    if (value != isAttatchedToBottom) {
      setState(() {
        isAttatchedToBottom = value;
      });
    }
  }

  Widget buildAction({
    required Widget child,
    String? name,
    Function()? onTap,
    double size = 30,
    List<ContextMenuItem>? contextMenuItems,
  }) {
    var pad = const EdgeInsets.all(2);

    var result = m.Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: Material(
          color: Colors.transparent,
          child: m.SizedBox(
            width: size,
            height: size,
            child: contextMenuItems != null
                ? ContextMenu(
                    modal: true,
                    items: contextMenuItems,
                    child: Padding(padding: pad, child: child),
                  )
                : InkWell(
                    onTap: onTap,
                    child: Padding(padding: pad, child: child),
                  ),
          ),
        ),
      ),
    );
    if (name != null) return tiamat.Tooltip(text: name, child: result);

    return result;
  }
}
