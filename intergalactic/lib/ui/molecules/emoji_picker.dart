import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/utils/autofill_utils.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/atoms/image_button.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/ui/atoms/emoji_widget.dart';

class EmojiPicker extends StatefulWidget {
  EmojiPicker(
    this.packs, {
    super.key,
    double? size,
    this.onEmoticonPressed,
    double? packButtonSize,
    this.onlyEmoji = false,
    this.onlyStickers = false,
    this.staggered = false,
    this.searchDelegate,
    this.searchController,
    this.showSearchBar = true,
    this.focus,
    this.preferredTooltipDirection = AxisDirection.right,
    this.packListAxis = Axis.vertical,
    this.mobileStyle = false,
  })
    // Resolved here rather than as parameter defaults: the platform flags
    // are no longer compile-time constants, so they cannot be default values.
    : size = size ?? (BuildConfig.MOBILE ? 48 : 42),
       packButtonSize = packButtonSize ?? (BuildConfig.MOBILE ? 48 : 42);
  final void Function(Emoticon emoticon)? onEmoticonPressed;
  final List<EmoticonPack> packs;
  final double size;
  final Axis packListAxis;
  final FocusNode? focus;
  final double packButtonSize;
  final bool staggered;
  final bool onlyStickers;
  final bool onlyEmoji;
  final List<AutofillSearchResultEmoticon> Function(String text)?
  searchDelegate;
  final TextEditingController? searchController;
  final bool showSearchBar;
  final AxisDirection preferredTooltipDirection;
  final bool mobileStyle;

  @override
  State<EmojiPicker> createState() => _EmojiPickerState();
}

class _EmojiPickerState extends State<EmojiPicker> {
  int crossAxisCount = 12;
  double searchBarSize = 50;
  double headerSize = 40;
  GlobalKey key = GlobalKey();
  ScrollController controller = ScrollController();
  final TextEditingController textController = TextEditingController();

  List<AutofillSearchResultEmoticon>? searchResults;

  @override
  void initState() {
    super.initState();
    activeSearchController.addListener(handleSearchTextChanged);
  }

  @override
  void didUpdateWidget(covariant EmojiPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldController = oldWidget.searchController ?? textController;
    if (oldController != activeSearchController) {
      oldController.removeListener(handleSearchTextChanged);
      activeSearchController.addListener(handleSearchTextChanged);
      handleSearchTextChanged();
    }
  }

  @override
  void dispose() {
    activeSearchController.removeListener(handleSearchTextChanged);
    textController.dispose();
    controller.dispose();
    super.dispose();
  }

  TextEditingController get activeSearchController =>
      widget.searchController ?? textController;

  void handleSearchTextChanged() {
    onSearchTextChanged(activeSearchController.text);
  }

  List<Emoticon> getEmoticonList(EmoticonPack pack) {
    if (widget.onlyEmoji) {
      return pack.emoji;
    }

    if (widget.onlyStickers) {
      return pack.stickers;
    }

    return pack.emotes;
  }

  void onSearchTextChanged(String value) {
    setState(() {
      if (value == "") {
        searchResults = null;
      } else {
        searchResults = widget.searchDelegate?.call(value);
      }
    });
  }

  void jumpToPack(int packIndex) {
    if (packIndex == 0) {
      controller.jumpTo(0);
      return;
    }

    if (key.currentContext?.findRenderObject() != null) {
      var renderBox = key.currentContext!.findRenderObject() as RenderBox;
      var boxSize = renderBox.size.width / crossAxisCount.toDouble();

      double offset = 0;
      if (widget.searchDelegate != null && widget.showSearchBar) {
        offset += searchBarSize.toDouble();
      }

      for (int i = 0; i < packIndex; i++) {
        offset += headerSize;

        var numEmotes = getEmoticonList(widget.packs[i]).length;
        var numRows = (numEmotes / crossAxisCount).ceil();

        offset += numRows.toDouble() * boxSize;
      }

      controller.jumpTo(offset);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: widget.packListAxis == Axis.vertical
          ? buildWithVerticalList(context)
          : buildWithHorizontalList(context),
    );
  }

  double get gridSpacing => widget.mobileStyle ? 4 : 0;

  EdgeInsets get gridPadding => EdgeInsets.fromLTRB(
    widget.mobileStyle ? 8 : 0,
    0,
    widget.mobileStyle ? 8 : 0,
    widget.mobileStyle ? 8 : 0,
  );

  Row buildWithVerticalList(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            border: widget.mobileStyle
                ? null
                : Border(
                    right: BorderSide(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: 0.42),
                    ),
                  ),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              widget.mobileStyle ? 4 : 5,
              widget.mobileStyle ? 4 : 6,
              widget.mobileStyle ? 4 : 5,
              widget.mobileStyle ? 4 : 6,
            ),
            child: SizedBox(
              width: widget.packButtonSize,
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(scrollbars: false),
                child: ListView.builder(
                  itemCount: widget.packs.length,
                  padding: EdgeInsets.all(0),
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
                      child: buildPackButton(index, () {
                        jumpToPack(index);
                      }),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        buildEmojiList(),
      ],
    );
  }

  Widget buildWithHorizontalList(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: widget.mobileStyle
              ? const EdgeInsets.fromLTRB(12, 0, 12, 8)
              : EdgeInsets.zero,
          child: tiamat.Tile.low(
            child: Padding(
              padding: EdgeInsets.all(widget.mobileStyle ? 8.0 : 4.0),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight:
                      widget.packButtonSize + (widget.mobileStyle ? 4 : 0),
                ),
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.packs.length,
                    itemBuilder: (context, index) {
                      return Padding(
                        padding: EdgeInsets.fromLTRB(
                          widget.mobileStyle ? 4 : 2,
                          0,
                          widget.mobileStyle ? 4 : 2,
                          0,
                        ),
                        child: buildPackButton(index, () {
                          jumpToPack(index);
                        }),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        Container(child: buildEmojiList()),
      ],
    );
  }

  Widget buildPackButton(int index, void Function()? onTap) {
    return SizedBox(
      child: tiamat.Tooltip(
        text: widget.packs[index].displayName,
        preferredDirection: widget.preferredTooltipDirection,
        child: ImageButton(
          size: widget.packButtonSize,
          iconSize: widget.mobileStyle
              ? widget.packButtonSize - 12
              : widget.packButtonSize - 8,
          icon: widget.packs[index].icon,
          image: widget.packs[index].image,
          onTap: onTap,
        ),
      ),
    );
  }

  Expanded buildEmojiList() {
    return Expanded(
      key: key,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: widget.mobileStyle
              ? Colors.transparent
              : Theme.of(context).colorScheme.surfaceContainer,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            var availableWidth = constraints.maxWidth;
            if (widget.mobileStyle) {
              availableWidth -= 16;
            }

            var count =
                ((availableWidth + gridSpacing) / (widget.size + gridSpacing))
                    .floor();
            if (count < 1) {
              count = 1;
            }
            if (count != crossAxisCount) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) {
                  return;
                }
                setState(() {
                  crossAxisCount = count;
                });
              });
            }

            return CustomScrollView(
              controller: controller,
              slivers: [
                if (widget.searchDelegate != null && widget.showSearchBar)
                  SliverList(
                    delegate: SliverChildListDelegate([
                      SizedBox(
                        height: searchBarSize,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            widget.mobileStyle ? 12 : 8,
                            widget.mobileStyle ? 0 : 4,
                            widget.mobileStyle ? 12 : 8,
                            widget.mobileStyle ? 0 : 6,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: widget.mobileStyle
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerLow
                                  : Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerLowest,
                              borderRadius: BorderRadius.circular(
                                widget.mobileStyle ? 18 : 6,
                              ),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant
                                    .withValues(
                                      alpha: widget.mobileStyle ? 0.12 : 0.34,
                                    ),
                              ),
                            ),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  0,
                                ),
                                child: TextField(
                                  focusNode: widget.focus,
                                  controller: activeSearchController,
                                  textAlignVertical: TextAlignVertical.center,
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    hintText: CommonStrings.promptSearch,
                                    icon: const Icon(Icons.search),
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
                if (searchResults?.isEmpty == true)
                  SliverList(
                    delegate: SliverChildListDelegate([
                      SizedBox(
                        height: 50,
                        child: Center(
                          child: tiamat.Text.labelLow("No results found :("),
                        ),
                      ),
                    ]),
                  ),
                if (searchResults?.isNotEmpty == true)
                  SliverPadding(
                    padding: gridPadding,
                    sliver: SliverGrid.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        mainAxisSpacing: gridSpacing,
                        crossAxisSpacing: gridSpacing,
                      ),
                      itemCount: searchResults!.length,
                      itemBuilder: (context, index) {
                        var emote = searchResults![index].emoticon;
                        return buildEmoticon(emote);
                      },
                    ),
                  ),
                if (searchResults == null)
                  for (var i = 0; i < widget.packs.length; i++) ...[
                    SliverList(
                      delegate: SliverChildListDelegate([
                        DecoratedBox(
                          decoration: BoxDecoration(
                            border: widget.mobileStyle
                                ? null
                                : Border(
                                    top: BorderSide(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .outlineVariant
                                          .withValues(
                                            alpha: i == 0 ? 0.0 : 0.34,
                                          ),
                                    ),
                                  ),
                          ),
                          child: SizedBox(
                            height: headerSize,
                            child: Padding(
                              padding: EdgeInsets.fromLTRB(
                                widget.mobileStyle ? 14 : 10,
                                0,
                                widget.mobileStyle ? 14 : 8,
                                0,
                              ),
                              child: Align(
                                alignment: AlignmentGeometry.centerLeft,
                                child: tiamat.Text.labelLow(
                                  widget.packs[i].displayName,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ]),
                    ),
                    SliverPadding(
                      padding: gridPadding,
                      sliver: SliverGrid.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: gridSpacing,
                          crossAxisSpacing: gridSpacing,
                        ),
                        itemCount: getEmoticonList(widget.packs[i]).length,
                        itemBuilder: (context, index) {
                          var emote = getEmoticonList(widget.packs[i])[index];
                          return buildEmoticon(emote);
                        },
                      ),
                    ),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget buildEmoticon(Emoticon emoticon) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: InkWell(
        borderRadius: BorderRadius.circular(widget.mobileStyle ? 12 : 3),
        onTap: () => widget.onEmoticonPressed?.call(emoticon),
        mouseCursor: SystemMouseCursors.click,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.mobileStyle ? 12 : 3),
            color: widget.mobileStyle
                ? Theme.of(context).colorScheme.surfaceContainerLow.withValues(
                    alpha: emoticon.isSticker ? 0.18 : 0.08,
                  )
                : Colors.transparent,
          ),
          child: Padding(
            padding: EdgeInsets.all(widget.mobileStyle ? 4.0 : 2.0),
            child: Center(
              child: EmojiWidget(
                emoticon,
                height: widget.mobileStyle
                    ? (emoticon.isSticker ? widget.size - 8 : widget.size - 10)
                    : widget.size,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
