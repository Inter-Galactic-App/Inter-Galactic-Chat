import 'package:flutter/material.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

@UseCase(name: 'Default', type: PopupDialog)
Widget wbpopupDialog(BuildContext context) {
  return Container(
    child: Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tiamat.Text.largeTitle("Example Content"),
              tiamat.Text.labelEmphasised(
                  "Random stuff here to put a dialog over"),
              tiamat.Text.body(
                  "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."),
              tiamat.Text.body(
                  "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."),
            ],
          ),
        ),
        Container(
          color: PopupDialog.barrierColor,
          child: Center(
              child: PopupDialog(
            title: "Hello!",
            content: tiamat.Text.body(
                "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum."),
          )),
        ),
      ],
    ),
  );
}

class PopupDialog extends StatelessWidget {
  const PopupDialog(
      {super.key,
      required this.title,
      required this.content,
      this.contentPadding = 8,
      this.width = null,
      this.height = null});
  final String? title;
  final double? width;
  final double? height;
  final double contentPadding;
  final Widget content;

  static Color barrierColor = Colors.black.withAlpha(128);

  static Future<T?> show<T extends Object?>(BuildContext context,
      {required Widget content,
      String? title,
      double? width,
      double? height,
      double contentPadding = 8,
      bool barrierDismissible = true,
      String? barrierLabel,
      bool? reduceMotion}) {
    final effectiveReduceMotion = reduceMotion ?? _shouldReduceMotion(context);
    final effectiveBarrierLabel = _barrierLabel(context, title, barrierLabel);

    return showGeneralDialog(
        context: context,
        barrierDismissible: barrierDismissible,
        barrierLabel: effectiveBarrierLabel,
        barrierColor: barrierColor,
        requestFocus: true,
        pageBuilder: (context, _, __) {
          return Theme(
            data: Theme.of(context),
            child: PopupDialog(
              title: title,
              content: content,
              width: width,
              height: height,
              contentPadding: contentPadding,
            ),
          );
        },
        transitionDuration: effectiveReduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 300),
        transitionBuilder: effectiveReduceMotion
            ? (context, animation, secondaryAnimation, child) => child
            : (context, animation, secondaryAnimation, child) =>
                SlideTransition(
                  position: Tween(
                    begin: const Offset(0, 1),
                    end: const Offset(0, 0),
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                  child: child,
                ));
  }

  static bool _shouldReduceMotion(BuildContext context) {
    final mediaQuery = MediaQuery.maybeOf(context);
    return mediaQuery?.disableAnimations == true ||
        mediaQuery?.accessibleNavigation == true;
  }

  static String _barrierLabel(
      BuildContext context, String? title, String? explicitLabel) {
    final label = explicitLabel?.trim();
    if (label != null && label.isNotEmpty) {
      return label;
    }

    final dismissLabel =
        MaterialLocalizations.of(context).modalBarrierDismissLabel;
    final titleLabel = title?.trim();
    if (titleLabel == null || titleLabel.isEmpty) {
      return dismissLabel;
    }

    return '$dismissLabel $titleLabel';
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final availableWidth = media?.size.width ?? 720;
    final availableHeight = media?.size.height ?? 720;
    final maxDialogWidth =
        width ?? (availableWidth - 48).clamp(0.0, 720.0).toDouble();
    final maxDialogHeight = height ??
        (availableHeight - (media?.viewInsets.vertical ?? 0) - 48)
            .clamp(0.0, 720.0)
            .toDouble();
    final minDialogWidth =
        width ?? (maxDialogWidth < 280 ? maxDialogWidth : 280.0);

    return FocusTraversalGroup(
      child: Dialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: minDialogWidth,
            maxWidth: maxDialogWidth,
            maxHeight: maxDialogHeight,
          ),
          child: Padding(
            padding: EdgeInsets.all(contentPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            container: true,
                            header: true,
                            namesRoute: true,
                            child: Text(title!),
                          ),
                        ),
                      ],
                    ),
                  ),
                Flexible(
                  fit: FlexFit.loose,
                  child: Semantics(
                    container: true,
                    explicitChildNodes: true,
                    child: content,
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
