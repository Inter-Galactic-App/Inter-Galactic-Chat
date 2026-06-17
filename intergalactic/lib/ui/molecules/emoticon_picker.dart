import 'dart:math' as math;

import 'package:intergalactic/client/components/gif/gif_component.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/ui/molecules/emoji_picker.dart';
import 'package:intergalactic/ui/molecules/gif_picker.dart';
import 'package:intergalactic/ui/mobile/mobile_visuals.dart';
import 'package:intergalactic/client/components/gif/gif_search_result.dart';
import 'package:intergalactic/utils/autofill_utils.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../client/components/emoticon/emoji_pack.dart';
import '../../client/components/emoticon/emoticon.dart';

class EmoticonPicker extends StatefulWidget {
  const EmoticonPicker({
    super.key,
    required this.emoji,
    required this.stickers,
    this.allowGifSearch = false,
    this.onEmojiPressed,
    this.onStickerPressed,
    this.onGifPressed,
    this.gifComponent,
    this.emojiSearchFocus,
    this.stickerSearchFocus,
    this.gifSearchFocus,
    this.searchDelegate,
    this.packListAxis = Axis.vertical,
    this.mobileStyle = false,
    this.onCreatePressed,
  });
  final List<EmoticonPack> emoji;
  final List<EmoticonPack> stickers;
  final GifComponent? gifComponent;
  final FocusNode? emojiSearchFocus;
  final FocusNode? stickerSearchFocus;
  final FocusNode? gifSearchFocus;
  final bool allowGifSearch;
  final void Function(Emoticon emoticon)? onEmojiPressed;
  final void Function(Emoticon emoticon)? onStickerPressed;

  final List<AutofillSearchResultEmoticon> Function(String text)?
      searchDelegate;
  final Future<void> Function(GifSearchResult emoticon)? onGifPressed;
  final Axis packListAxis;
  final bool mobileStyle;
  final VoidCallback? onCreatePressed;

  @override
  State<EmoticonPicker> createState() => _EmoticonPickerState();
}

class _EmoticonPickerState extends State<EmoticonPicker>
    with TickerProviderStateMixin {
  late TabController controller;
  PageStorageBucket bucket = PageStorageBucket();
  final TextEditingController emojiSearchController = TextEditingController();
  final TextEditingController stickerSearchController = TextEditingController();
  final TextEditingController gifSearchController = TextEditingController();

  String get labelEmojiPickerEmojiTab => Intl.message("Emoji",
      desc: "Label for the emoji tab in emoji picker",
      name: "labelEmojiPickerEmojiTab");

  String get labelEmojiPickerStickerTab => Intl.message("Stickers",
      desc: "Label for the sticker tab in the emoji picker",
      name: "labelEmojiPickerStickerTab");

  String get labelEmojiPickerGifTab => Intl.message("GIFs",
      desc: "Label for the gif search tab in the emoji picker",
      name: "labelEmojiPickerGifTab");

  String get labelEmojiPickerCreate => Intl.message("Create",
      desc: "Label for the create button in the emoji picker",
      name: "labelEmojiPickerCreate");

  String get labelEmojiPickerSearchGifs => Intl.message("Search GIFs",
      desc: "Placeholder for GIF search in the emoji picker",
      name: "labelEmojiPickerSearchGifs");

  bool get useDesktopTabOrder => !widget.mobileStyle;

  int get tabCount {
    var count = 1;
    if (widget.stickers.isNotEmpty) {
      count += 1;
    }
    if (widget.allowGifSearch && widget.gifComponent != null) {
      count += 1;
    }
    return count;
  }

  int get initialTabIndex {
    if (!useDesktopTabOrder) {
      return 0;
    }

    var index = 0;
    if (widget.allowGifSearch && widget.gifComponent != null) {
      index += 1;
    }
    if (widget.stickers.isNotEmpty) {
      index += 1;
    }
    return index;
  }

  @override
  void initState() {
    controller = TabController(
      length: tabCount,
      initialIndex: initialTabIndex,
      vsync: this,
    );
    controller.addListener(onTabChanged);

    super.initState();
  }

  @override
  void dispose() {
    controller.removeListener(onTabChanged);
    controller.dispose();
    emojiSearchController.dispose();
    stickerSearchController.dispose();
    gifSearchController.dispose();
    super.dispose();
  }

  void onTabChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pages = <Widget>[];
    final tabWidgets = <Widget>[];

    void addTab(String label, Widget page) {
      tabWidgets.add(Tab(text: label));
      pages.add(page);
    }

    final emojiPage = EmojiPicker(
      widget.emoji,
      size: widget.mobileStyle ? 40 : (BuildConfig.MOBILE ? 48 : 38),
      packButtonSize: widget.mobileStyle ? 42 : (BuildConfig.MOBILE ? 48 : 36),
      focus: widget.emojiSearchFocus,
      searchController: emojiSearchController,
      showSearchBar: widget.mobileStyle,
      searchDelegate: (value) {
        final searchDelegate = widget.searchDelegate;
        if (searchDelegate == null) {
          return const [];
        }

        return searchDelegate(value).where((i) => i.emoticon.isEmoji).toList();
      },
      onlyEmoji: true,
      mobileStyle: widget.mobileStyle,
      onEmoticonPressed: (emoticon) => widget.onEmojiPressed?.call(emoticon),
    );

    final stickerPage = widget.stickers.isEmpty
        ? null
        : EmojiPicker(
            widget.stickers,
            size: widget.mobileStyle ? 82 : (BuildConfig.MOBILE ? 82 : 66),
            packButtonSize:
                widget.mobileStyle ? 42 : (BuildConfig.MOBILE ? 48 : 36),
            focus: widget.stickerSearchFocus,
            searchController: stickerSearchController,
            showSearchBar: widget.mobileStyle,
            searchDelegate: (value) {
              final searchDelegate = widget.searchDelegate;
              if (searchDelegate == null) {
                return const [];
              }

              return searchDelegate(value)
                  .where((i) => i.emoticon.isSticker)
                  .toList();
            },
            onlyStickers: true,
            mobileStyle: widget.mobileStyle,
            onEmoticonPressed: (emoticon) =>
                widget.onStickerPressed?.call(emoticon),
          );

    final gifPage = widget.allowGifSearch && widget.gifComponent != null
        ? GifPicker(
            focus: widget.gifSearchFocus,
            searchController: gifSearchController,
            showSearchBar: widget.mobileStyle,
            search: widget.gifComponent!.search,
            placeholderText: widget.gifComponent!.searchPlaceholder,
            gifPicked: widget.onGifPressed,
          )
        : null;

    if (useDesktopTabOrder) {
      if (gifPage != null) {
        addTab(labelEmojiPickerGifTab, gifPage);
      }
      if (stickerPage != null) {
        addTab(labelEmojiPickerStickerTab, stickerPage);
      }
      addTab(labelEmojiPickerEmojiTab, emojiPage);
    } else {
      addTab(labelEmojiPickerEmojiTab, emojiPage);
      if (stickerPage != null) {
        addTab(labelEmojiPickerStickerTab, stickerPage);
      }
      if (gifPage != null) {
        addTab(labelEmojiPickerGifTab, gifPage);
      }
    }

    return ClipRect(
      child: PageStorage(
        bucket: bucket,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!widget.mobileStyle) desktopHeader(tabWidgets),
            if (controller.length > 1 && widget.mobileStyle)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHigh
                        .withValues(alpha: 0.5),
                    borderRadius:
                        BorderRadius.circular(MobileVisuals.pillRadius),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .outline
                          .withValues(alpha: 0.12),
                    ),
                  ),
                  child: TabBar(
                    controller: controller,
                    dividerColor: Colors.transparent,
                    dividerHeight: 0,
                    indicatorSize: TabBarIndicatorSize.tab,
                    tabs: tabWidgets,
                  ),
                ),
              ),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.mobileStyle
                      ? Colors.transparent
                      : scheme.surfaceContainer,
                ),
                child: TabBarView(controller: controller, children: pages),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget desktopHeader(List<Widget> tabs) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.44),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (controller.length > 1)
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: tabs.length * 78.0,
                  height: 28,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.32),
                      ),
                    ),
                    child: TabBar(
                      controller: controller,
                      dividerColor: Colors.transparent,
                      dividerHeight: 0,
                      indicatorSize: TabBarIndicatorSize.tab,
                      labelPadding: EdgeInsets.zero,
                      indicator: BoxDecoration(
                        color: scheme.outline.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: scheme.outline.withValues(alpha: 0.36),
                        ),
                      ),
                      labelColor: scheme.onSurface,
                      unselectedLabelColor: scheme.onSurfaceVariant,
                      labelStyle:
                          Theme.of(context).textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                      unselectedLabelStyle:
                          Theme.of(context).textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                              ),
                      tabs: tabs,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: desktopSearchField()),
                if (widget.onCreatePressed != null) ...[
                  const SizedBox(width: 8),
                  desktopCreateButton(),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget desktopSearchField() {
    final scheme = Theme.of(context).colorScheme;
    final searchController = currentSearchController;

    return SizedBox(
      height: 34,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.36),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 1),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: 17,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: searchController,
                  focusNode: currentSearchFocus,
                  maxLines: 1,
                  textAlignVertical: TextAlignVertical.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        height: 1.2,
                      ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.only(
                      bottom: 2,
                    ),
                    hintText: currentSearchPlaceholder,
                    hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                          height: 1.2,
                        ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget desktopCreateButton() {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 34,
      child: TextButton(
        onPressed: widget.onCreatePressed,
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurface,
          backgroundColor: scheme.outline.withValues(alpha: 0.12),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(
              color: scheme.outline.withValues(alpha: 0.42),
            ),
          ),
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
        ),
        child: Text(labelEmojiPickerCreate),
      ),
    );
  }

  TextEditingController get currentSearchController {
    final tabIndex = controller.index;
    final currentTabLabel = tabLabelAt(tabIndex);
    if (currentTabLabel == labelEmojiPickerGifTab) {
      return gifSearchController;
    }
    if (currentTabLabel == labelEmojiPickerStickerTab) {
      return stickerSearchController;
    }
    return emojiSearchController;
  }

  FocusNode? get currentSearchFocus {
    final tabIndex = controller.index;
    final currentTabLabel = tabLabelAt(tabIndex);
    if (currentTabLabel == labelEmojiPickerGifTab) {
      return widget.gifSearchFocus;
    }
    if (currentTabLabel == labelEmojiPickerStickerTab) {
      return widget.stickerSearchFocus;
    }
    return widget.emojiSearchFocus;
  }

  String get currentSearchPlaceholder {
    final currentTabLabel = tabLabelAt(controller.index);
    if (currentTabLabel == labelEmojiPickerGifTab) {
      return widget.gifComponent?.searchPlaceholder ??
          labelEmojiPickerSearchGifs;
    }
    return CommonStrings.promptSearch;
  }

  String tabLabelAt(int index) {
    final labels = <String>[];
    if (useDesktopTabOrder) {
      if (widget.allowGifSearch && widget.gifComponent != null) {
        labels.add(labelEmojiPickerGifTab);
      }
      if (widget.stickers.isNotEmpty) {
        labels.add(labelEmojiPickerStickerTab);
      }
      labels.add(labelEmojiPickerEmojiTab);
    } else {
      labels.add(labelEmojiPickerEmojiTab);
      if (widget.stickers.isNotEmpty) {
        labels.add(labelEmojiPickerStickerTab);
      }
      if (widget.allowGifSearch && widget.gifComponent != null) {
        labels.add(labelEmojiPickerGifTab);
      }
    }
    final safeIndex = math.min(math.max(index, 0), labels.length - 1);
    return labels[safeIndex];
  }
}
