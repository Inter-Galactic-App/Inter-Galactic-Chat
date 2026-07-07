import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:widgetbook_annotation/widgetbook_annotation.dart';

const double defaultTiamatMinimumInteractiveDimension = 40.0;

@UseCase(name: 'Default', type: IconButton)
Widget wbIconButton(BuildContext context) {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: const [
        SizedBox(
          width: 50,
          height: 50,
          child: Center(
            child: IconButton(
              icon: material.Icons.send,
              size: 25,
            ),
          ),
        ),
      ],
    ),
  );
}

class IconButton extends StatefulWidget {
  const IconButton({
    super.key,
    this.size = 15,
    required this.icon,
    this.onPressed,
    this.backgroundColor = material.Colors.transparent,
    this.iconColor,
    this.semanticLabel,
    this.semanticHint,
    this.tooltip,
    this.minimumSize,
  });

  final double size;
  final Function? onPressed;
  final IconData icon;
  final Color backgroundColor;
  final Color? iconColor;
  final String? semanticLabel;
  final String? semanticHint;
  final String? tooltip;
  final double? minimumSize;

  @override
  State<IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<IconButton> {
  bool focused = false;

  bool get enabled => widget.onPressed != null;

  void _activate() {
    if (!enabled) {
      return;
    }
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = material.Theme.of(context);
    final defaultMinimumSize = widget.size + 8;
    final resolvedMinimumSize = widget.minimumSize ?? defaultMinimumSize;
    final minimumSize =
        resolvedMinimumSize > defaultTiamatMinimumInteractiveDimension
            ? resolvedMinimumSize
            : defaultTiamatMinimumInteractiveDimension;
    final label = widget.semanticLabel ??
        widget.tooltip ??
        defaultTiamatIconActionLabel(widget.icon);

    final button = Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              _activate();
              return null;
            },
          ),
        },
        child: FocusableActionDetector(
          enabled: enabled,
          mouseCursor:
              enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onShowFocusHighlight: (value) {
            setState(() {
              focused = value;
            });
          },
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: minimumSize,
              minHeight: minimumSize,
            ),
            child: Center(
              child: SizedBox(
                width: minimumSize,
                height: minimumSize,
                child: material.Material(
                  type: material.MaterialType.transparency,
                  child: material.InkWell(
                    canRequestFocus: false,
                    customBorder: const material.CircleBorder(),
                    onTap: enabled ? _activate : null,
                    child: Center(
                      child: SizedBox(
                        width: defaultMinimumSize,
                        height: defaultMinimumSize,
                        child: material.Ink(
                          decoration: BoxDecoration(
                            color: widget.backgroundColor,
                            shape: BoxShape.circle,
                            border: focused
                                ? Border.all(
                                    color: theme.colorScheme.outline,
                                    width: 2,
                                  )
                                : null,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(4.0),
                            child: Align(
                              alignment: Alignment.center,
                              child: Icon(
                                widget.icon,
                                size: widget.size,
                                color: widget.iconColor ??
                                    theme.colorScheme.secondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final result = Semantics(
      button: true,
      enabled: enabled,
      label: label,
      hint: widget.semanticHint,
      onTap: enabled ? _activate : null,
      child: ExcludeSemantics(child: button),
    );

    if (widget.tooltip == null) {
      return result;
    }

    return material.Tooltip(
      message: widget.tooltip!,
      excludeFromSemantics: true,
      child: result,
    );
  }
}

String defaultTiamatIconActionLabel(IconData? icon) {
  if (icon == material.Icons.fullscreen ||
      icon == material.Icons.fullscreen_rounded) {
    return "Enter fullscreen";
  }
  if (icon == material.Icons.fullscreen_exit ||
      icon == material.Icons.fullscreen_exit_rounded) {
    return "Exit fullscreen";
  }
  if (icon == material.Icons.close || icon == material.Icons.close_rounded) {
    return "Close";
  }
  if (icon == material.Icons.add || icon == material.Icons.add_rounded) {
    return "Add";
  }
  if (icon == material.Icons.edit || icon == material.Icons.edit_rounded) {
    return "Edit";
  }
  if (icon == material.Icons.delete || icon == material.Icons.delete_rounded) {
    return "Delete";
  }
  if (icon == material.Icons.download ||
      icon == material.Icons.download_rounded) {
    return "Download";
  }
  if (icon == material.Icons.save || icon == material.Icons.save_rounded) {
    return "Save";
  }
  if (icon == material.Icons.search || icon == material.Icons.search_rounded) {
    return "Search";
  }
  if (icon == material.Icons.settings ||
      icon == material.Icons.settings_rounded) {
    return "Settings";
  }
  if (icon == material.Icons.more_vert || icon == material.Icons.more_horiz) {
    return "More actions";
  }
  if (icon == material.Icons.send || icon == material.Icons.send_rounded) {
    return "Send";
  }
  if (icon == material.Icons.check || icon == material.Icons.check_rounded) {
    return "Confirm";
  }
  if (icon == material.Icons.arrow_back ||
      icon == material.Icons.arrow_back_rounded) {
    return "Back";
  }
  if (icon == material.Icons.arrow_forward ||
      icon == material.Icons.arrow_forward_rounded) {
    return "Next";
  }
  if (icon == material.Icons.play_arrow ||
      icon == material.Icons.play_arrow_rounded) {
    return "Play";
  }
  if (icon == material.Icons.pause || icon == material.Icons.pause_rounded) {
    return "Pause";
  }
  if (icon == material.Icons.stop || icon == material.Icons.stop_rounded) {
    return "Stop";
  }
  if (icon == material.Icons.mic || icon == material.Icons.mic_rounded) {
    return "Microphone";
  }
  if (icon == material.Icons.mic_off ||
      icon == material.Icons.mic_off_rounded) {
    return "Mute microphone";
  }
  if (icon == material.Icons.videocam ||
      icon == material.Icons.videocam_rounded) {
    return "Camera";
  }
  if (icon == material.Icons.videocam_off ||
      icon == material.Icons.videocam_off_rounded) {
    return "Turn camera off";
  }
  if (icon == material.Icons.volume_off ||
      icon == material.Icons.volume_off_rounded) {
    return "Mute audio";
  }
  if (icon == material.Icons.screen_share ||
      icon == material.Icons.screen_share_rounded) {
    return "Share screen";
  }
  if (icon == material.Icons.stop_screen_share ||
      icon == material.Icons.stop_screen_share_rounded) {
    return "Stop sharing screen";
  }
  if (icon == material.Icons.call_end ||
      icon == material.Icons.call_end_rounded) {
    return "End call";
  }
  if (icon == material.Icons.open_in_new ||
      icon == material.Icons.open_in_new_rounded) {
    return "Open in new window";
  }
  if (icon == material.Icons.push_pin ||
      icon == material.Icons.push_pin_rounded) {
    return "Pin";
  }
  if (icon == material.Icons.attach_file ||
      icon == material.Icons.attach_file_rounded) {
    return "Attach file";
  }
  if (icon == material.Icons.emoji_emotions ||
      icon == material.Icons.emoji_emotions_rounded) {
    return "Emoji";
  }
  if (icon == material.Icons.image || icon == material.Icons.image_rounded) {
    return "Image";
  }
  if (icon == material.Icons.person_add ||
      icon == material.Icons.person_add_rounded) {
    return "Invite user";
  }
  if (icon == material.Icons.toggle_on || icon == material.Icons.toggle_off) {
    return "Toggle";
  }
  return "Icon action";
}
