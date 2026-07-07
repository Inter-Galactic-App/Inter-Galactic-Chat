import 'dart:ui';

import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/ui/accessibility/paused_animated_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import 'package:tiamat/tiamat.dart' as tiamat;
import '../../utils/debounce.dart';
import '../../client/components/gif/gif_search_result.dart';

class GifPicker extends StatefulWidget {
  const GifPicker(
      {super.key,
      this.gifPicked,
      this.search,
      this.focus,
      this.searchController,
      this.showSearchBar = true,
      this.placeholderText = "Search Gif"});
  final Future<void> Function(GifSearchResult gif)? gifPicked;
  final Future<List<GifSearchResult>> Function(String query)? search;
  final FocusNode? focus;
  final TextEditingController? searchController;
  final bool showSearchBar;

  final String placeholderText;

  @override
  State<GifPicker> createState() => _GifPickerState();
}

class _GifPickerState extends State<GifPicker> {
  List<GifSearchResult>? searchResult;
  bool searching = false;
  bool sending = false;

  final TextEditingController _textController = TextEditingController();
  Debouncer debouce = Debouncer(delay: const Duration(milliseconds: 500));

  @override
  void initState() {
    activeSearchController.addListener(onTextChanged);
    super.initState();
  }

  @override
  void didUpdateWidget(covariant GifPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldController = oldWidget.searchController ?? _textController;
    if (oldController != activeSearchController) {
      oldController.removeListener(onTextChanged);
      activeSearchController.addListener(onTextChanged);
      onTextChanged();
    }
  }

  @override
  void dispose() {
    activeSearchController.removeListener(onTextChanged);
    _textController.dispose();
    super.dispose();
  }

  TextEditingController get activeSearchController =>
      widget.searchController ?? _textController;

  String prevText = "";
  void onTextChanged() {
    if (activeSearchController.text == prevText) {
      return;
    }

    prevText = activeSearchController.text;

    if (activeSearchController.text.isNotEmpty) {
      setState(() {
        searching = true;
        searchResult = null;
      });
      debouce.run(() => doSearch(activeSearchController.text));
    } else {
      debouce.cancel();
      setState(() {
        searching = false;
      });
    }
  }

  void doSearch(String query) {
    setState(() {
      searching = true;
    });

    widget.search?.call(query).then((value) {
      setState(() {
        searchResult = value;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      buildContent(context),
      IgnorePointer(
        ignoring: !sending,
        child: AnimatedOpacity(
          opacity: sending ? 1 : 0,
          duration: const Duration(milliseconds: 100),
          child: BackdropFilter(
            filter: ImageFilter.blur(
                sigmaX: 2, sigmaY: 2, tileMode: TileMode.repeated),
            child: Container(
              color: Colors.black.withAlpha(100),
              child: const Center(
                  child: SizedBox(
                width: 50,
                height: 50,
                child: CircularProgressIndicator(),
              )),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget buildContent(BuildContext context) {
    return Column(
      children: [
        if (widget.showSearchBar) buildSearchBar(),
        buildSearch(context),
      ],
    );
  }

  Widget buildSearchBar() {
    if (!Layout.desktop) {
      return tiamat.Tile.low(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            controller: activeSearchController,
            focusNode: widget.focus,
            textAlignVertical: TextAlignVertical.center,
            decoration: InputDecoration(
                icon: const Icon(Icons.search),
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: widget.placeholderText),
          ),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Layout.desktop ? 8 : 0,
        Layout.desktop ? 4 : 0,
        Layout.desktop ? 8 : 0,
        Layout.desktop ? 6 : 0,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(Layout.desktop ? 6 : 0),
          border: Layout.desktop
              ? Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.34),
                )
              : null,
        ),
        child: Padding(
          padding: EdgeInsets.all(Layout.desktop ? 0 : 8.0),
          child: SizedBox(
              height: Layout.desktop ? 36 : null,
              child: TextField(
                controller: activeSearchController,
                focusNode: widget.focus,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                    icon: const Icon(Icons.search),
                    isDense: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    hintText: widget.placeholderText),
              )),
        ),
      ),
    );
  }

  Widget buildSearch(BuildContext context) {
    if (!searching) {
      return const Expanded(child: SizedBox());
    }

    if (searchResult == null)
      return const Expanded(
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );

    return Expanded(
        child: Padding(
      padding: const EdgeInsets.all(8.0),
      child: MasonryGridView.extent(
        maxCrossAxisExtent: 300,
        mainAxisSpacing: 8,
        padding: EdgeInsetsGeometry.all(0),
        crossAxisSpacing: 8,
        itemCount: searchResult!.length,
        itemBuilder: (context, index) {
          var result = searchResult!.elementAt(index);
          return MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => sendGif(result),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: result.x / result.y,
                  child: SizedBox(
                    child: PausedAnimatedImage(
                      fit: BoxFit.fill,
                      filterQuality: FilterQuality.medium,
                      image: NetworkImage(result.previewUrl.toString()),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ));
  }

  Future<void> sendGif(GifSearchResult gif) async {
    setState(() {
      sending = true;
    });

    try {
      await widget.gifPicked?.call(gif);
    } catch (error, stackTrace) {
      Log.onError(error, stackTrace, content: "Failed to send GIF");
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text("Failed to send GIF: $error"),
          ),
        );
      }
      rethrow;
    } finally {
      if (mounted) {
        setState(() {
          sending = false;
        });
      }
    }
  }
}
