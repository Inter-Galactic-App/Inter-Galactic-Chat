import 'dart:async';
import 'package:intergalactic/client/components/space_banner/space_banner_component.dart';
import 'package:intergalactic/client/components/space_color_scheme/space_color_scheme_component.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/utils/image/lod_image.dart';
import 'package:intergalactic/utils/scaled_app.dart';
import 'package:flutter/material.dart';

import '../../client/client.dart';

class SpaceHeader extends StatefulWidget {
  const SpaceHeader(this.space,
      {this.onTap,
      this.backgroundColor = Colors.transparent,
      this.height = 100,
      super.key})
      : assert(height >= 0 && height <= double.maxFinite);
  final Space space;
  final Color backgroundColor;
  final double height;
  final void Function()? onTap;

  @override
  State<SpaceHeader> createState() => _SpaceHeaderState();
}

class _SpaceHeaderState extends State<SpaceHeader> {
  late StreamSubscription _sub;
  String? _lastFullResImageId;

  @override
  void initState() {
    super.initState();
    _sub = widget.space.onUpdate.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  void _requestFullRes(ImageProvider? image) {
    if (image is! LODImageProvider) {
      return;
    }

    if (_lastFullResImageId == image.id) {
      return;
    }

    final imageId = image.id;
    _lastFullResImageId = imageId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _lastFullResImageId != imageId) {
        return;
      }

      unawaited(image.fetchFullRes());
    });
  }

  @override
  Widget build(BuildContext context) {
    var colorScheme = Theme.of(context).colorScheme;

    var comp = widget.space.getComponent<SpaceColorSchemeComponent>();
    if (comp != null) {
      colorScheme = comp.scheme;
    }

    final padding = Layout.mobile
        ? EdgeInsets.zero
        : MediaQuery.of(context).scale().viewPadding;
    final topInset = Layout.mobile ? 0.0 : MediaQuery.of(context).padding.top;

    var banner = widget.space.getComponent<SpaceBannerComponent>();
    final headerImage = banner?.banner ?? widget.space.avatar;
    final hasHeaderImage = headerImage != null;
    _requestFullRes(headerImage);

    return ClipRRect(
      borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(8), bottomRight: Radius.circular(8)),
      child: ConstrainedBox(
        constraints: BoxConstraints.expand(height: widget.height + topInset),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (hasHeaderImage)
              Image(
                image: headerImage,
                fit: BoxFit.cover,
                alignment: padding.top > 0
                    ? AlignmentGeometry.xy(0, -0.25)
                    : Alignment.center,
                filterQuality: FilterQuality.medium,
              ),
            Material(
              color: hasHeaderImage ? Colors.transparent : colorScheme.primary,
              child: InkWell(
                onTap: widget.onTap,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                      gradient: hasHeaderImage
                          ? LinearGradient(
                              begin: AlignmentGeometry.bottomCenter,
                              end: AlignmentGeometry.topCenter,
                              colors: [colorScheme.primary, Colors.transparent],
                            )
                          : null),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 2, 0, 2),
                      child: Text(widget.space.displayName,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium!
                              .copyWith(
                                  color: colorScheme.onPrimary,
                                  fontFamily:
                                      Layout.mobile ? "NunitoSans" : null,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                  shadows: hasHeaderImage
                                      ? [
                                          const BoxShadow(
                                              blurRadius: 2,
                                              spreadRadius: 10,
                                              color: Colors.black,
                                              offset: Offset(2, 2))
                                        ]
                                      : null)),
                    ),
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }
}
