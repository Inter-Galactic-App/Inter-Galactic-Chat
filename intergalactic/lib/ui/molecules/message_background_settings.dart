import 'package:flutter/material.dart';
import 'package:intergalactic/config/custom_theme_definition.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/theme_settings/custom_theme_editor.dart';
import 'package:intergalactic/utils/message_background/message_background_manager.dart';
import 'package:intergalactic/utils/picker_utils.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class MessageBackgroundSettings extends StatefulWidget {
  const MessageBackgroundSettings({
    required this.title,
    required this.description,
    required this.storageKey,
    required this.value,
    required this.onChanged,
    this.clearText = 'Clear',
    this.backgroundOpacity,
    this.backgroundOpacityInherited = false,
    this.backgroundOpacityClearText = 'Reset',
    this.onBackgroundOpacityChanged,
    this.onClearBackgroundOpacity,
    this.bubbleColorClearText = 'Reset',
    this.sentBubbleColorHex,
    this.sentBubbleColorInherited = false,
    this.onSentBubbleColorChanged,
    this.onClearSentBubbleColor,
    this.receivedBubbleColorHex,
    this.receivedBubbleColorInherited = false,
    this.onReceivedBubbleColorChanged,
    this.onClearReceivedBubbleColor,
    super.key,
  });

  final String title;
  final String description;
  final String storageKey;
  final String? value;
  final String clearText;
  final Future<void> Function(String? path) onChanged;
  final double? backgroundOpacity;
  final bool backgroundOpacityInherited;
  final String backgroundOpacityClearText;
  final Future<void> Function(double value)? onBackgroundOpacityChanged;
  final Future<void> Function()? onClearBackgroundOpacity;
  final String bubbleColorClearText;
  final String? sentBubbleColorHex;
  final bool sentBubbleColorInherited;
  final Future<void> Function(String? hexColor)? onSentBubbleColorChanged;
  final Future<void> Function()? onClearSentBubbleColor;
  final String? receivedBubbleColorHex;
  final bool receivedBubbleColorInherited;
  final Future<void> Function(String? hexColor)? onReceivedBubbleColorChanged;
  final Future<void> Function()? onClearReceivedBubbleColor;

  @override
  State<MessageBackgroundSettings> createState() =>
      _MessageBackgroundSettingsState();
}

class _MessageBackgroundSettingsState extends State<MessageBackgroundSettings> {
  bool _busy = false;
  late double _opacityValue;

  @override
  void initState() {
    super.initState();
    _opacityValue = widget.backgroundOpacity ?? 1.0;
  }

  @override
  void didUpdateWidget(covariant MessageBackgroundSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.backgroundOpacity != oldWidget.backgroundOpacity) {
      _opacityValue = widget.backgroundOpacity ?? 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final supportsLocalImages = MessageBackgroundManager.supportsLocalImages;
    final hasBubbleControls = widget.onSentBubbleColorChanged != null ||
        widget.onReceivedBubbleColorChanged != null;

    if (!supportsLocalImages && !hasBubbleControls) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer.withAlpha(100),
        border: Border.all(
          color: Theme.of(context).colorScheme.secondary.withAlpha(20),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            if (supportsLocalImages) ...[
              Row(
                spacing: 12,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: 60,
                      height: 84,
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      child: _MessageBackgroundPreviewImage(
                        storedPath: widget.value,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        tiamat.Text(widget.title),
                        tiamat.Text.labelLow(widget.description),
                      ],
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                spacing: 8,
                children: [
                  if (widget.value?.isNotEmpty == true)
                    tiamat.Button.secondary(
                      text: widget.clearText,
                      onTap: _busy ? null : _clear,
                    ),
                  tiamat.Button(
                    text: _busy ? 'Saving...' : 'Choose Image',
                    onTap: _busy ? null : _pickImage,
                  ),
                ],
              ),
              if (widget.backgroundOpacity != null &&
                  widget.onBackgroundOpacityChanged != null)
                _MessageBackgroundOpacityControl(
                  value: _opacityValue,
                  inherited: widget.backgroundOpacityInherited,
                  clearText: widget.backgroundOpacityClearText,
                  onChanged: (value) {
                    setState(() {
                      _opacityValue = value;
                    });
                    widget.onBackgroundOpacityChanged?.call(value);
                  },
                  onClear: widget.onClearBackgroundOpacity,
                ),
            ],
            if (widget.onSentBubbleColorChanged != null ||
                widget.onReceivedBubbleColorChanged != null)
              _MessageBubbleColorControls(
                sentHexColor: widget.sentBubbleColorHex,
                sentInherited: widget.sentBubbleColorInherited,
                onSentChanged: widget.onSentBubbleColorChanged,
                onClearSent: widget.onClearSentBubbleColor,
                receivedHexColor: widget.receivedBubbleColorHex,
                receivedInherited: widget.receivedBubbleColorInherited,
                onReceivedChanged: widget.onReceivedBubbleColorChanged,
                onClearReceived: widget.onClearReceivedBubbleColor,
                clearText: widget.bubbleColorClearText,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage() async {
    setState(() {
      _busy = true;
    });

    try {
      final bytes = await PickerUtils.pickImageAndCrop(context);
      if (bytes == null) {
        return;
      }

      final oldValue = widget.value;
      final path = await MessageBackgroundManager.importBackground(
        bytes,
        storageKey: widget.storageKey,
      );
      await widget.onChanged(path);
      final sameBackground =
          await MessageBackgroundManager.referencesSameBackground(
              oldValue, path);
      if (oldValue != null && !sameBackground) {
        await MessageBackgroundManager.deleteBackground(oldValue);
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _clear() async {
    setState(() {
      _busy = true;
    });

    try {
      final oldValue = widget.value;
      await widget.onChanged(null);
      await MessageBackgroundManager.deleteBackground(oldValue);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }
}

class _MessageBackgroundPreviewImage extends StatelessWidget {
  const _MessageBackgroundPreviewImage({required this.storedPath});

  final String? storedPath;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      Icons.image_outlined,
      color: Theme.of(context).colorScheme.secondary,
    );
    final image = MessageBackgroundManager.imageProvider(storedPath);
    if (image != null) {
      return _preview(image);
    }

    if (storedPath == null || storedPath!.isEmpty) {
      return fallback;
    }

    return FutureBuilder<ImageProvider?>(
      future: MessageBackgroundManager.resolveImageProvider(storedPath),
      builder: (context, snapshot) {
        final resolvedImage = snapshot.data;
        if (resolvedImage == null) {
          return fallback;
        }

        return _preview(resolvedImage);
      },
    );
  }

  Widget _preview(ImageProvider image) {
    return Image(
      image: image,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
    );
  }
}

class _MessageBackgroundOpacityControl extends StatelessWidget {
  const _MessageBackgroundOpacityControl({
    required this.value,
    required this.inherited,
    required this.clearText,
    required this.onChanged,
    required this.onClear,
  });

  final double value;
  final bool inherited;
  final String clearText;
  final ValueChanged<double> onChanged;
  final Future<void> Function()? onClear;

  @override
  Widget build(BuildContext context) {
    final percentage = (value * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 4,
      children: [
        Row(
          children: [
            const Expanded(
              child: tiamat.Text("Background transparency"),
            ),
            tiamat.Text.labelLow(
              inherited ? "Inherits $percentage%" : "$percentage%",
            ),
          ],
        ),
        tiamat.Text.labelLow(
          "Higher values keep more of the picture visible behind messages.",
        ),
        Row(
          children: [
            Expanded(
              child: tiamat.Slider(
                min: 0,
                max: 1,
                value: value.clamp(0.0, 1.0),
                onChanged: (newValue) {
                  onChanged(double.parse(newValue.toStringAsFixed(2)));
                },
              ),
            ),
            if (onClear != null && !inherited)
              tiamat.Button.secondary(
                text: clearText,
                onTap: onClear,
              ),
          ],
        ),
      ],
    );
  }
}

class _BubbleColorPreset {
  const _BubbleColorPreset({
    required this.label,
    required this.hexColor,
  });

  final String label;
  final String hexColor;
}

const _sentBubbleColorPresets = [
  _BubbleColorPreset(label: 'Ocean', hexColor: '#ff0a84ff'),
  _BubbleColorPreset(label: 'Pulse', hexColor: '#ff0084ff'),
  _BubbleColorPreset(label: 'Evergreen', hexColor: '#ff005c4b'),
  _BubbleColorPreset(label: 'Cobalt', hexColor: '#ff2c6bed'),
  _BubbleColorPreset(label: 'Sky', hexColor: '#ff2aabee'),
  _BubbleColorPreset(label: 'Sunset', hexColor: '#ff833ab4'),
];

const _receivedBubbleColorPresets = [
  _BubbleColorPreset(label: 'Graphite', hexColor: '#ff3a3b3c'),
  _BubbleColorPreset(label: 'Ash', hexColor: '#ff303136'),
  _BubbleColorPreset(label: 'Deep Teal', hexColor: '#ff202c33'),
  _BubbleColorPreset(label: 'Charcoal', hexColor: '#ff2f3338'),
  _BubbleColorPreset(label: 'Slate', hexColor: '#ff313338'),
  _BubbleColorPreset(label: 'Indigo', hexColor: '#ff37345f'),
];

class _MessageBubbleColorControls extends StatelessWidget {
  const _MessageBubbleColorControls({
    required this.sentHexColor,
    required this.sentInherited,
    required this.onSentChanged,
    required this.onClearSent,
    required this.receivedHexColor,
    required this.receivedInherited,
    required this.onReceivedChanged,
    required this.onClearReceived,
    required this.clearText,
  });

  final String? sentHexColor;
  final bool sentInherited;
  final Future<void> Function(String? hexColor)? onSentChanged;
  final Future<void> Function()? onClearSent;
  final String? receivedHexColor;
  final bool receivedInherited;
  final Future<void> Function(String? hexColor)? onReceivedChanged;
  final Future<void> Function()? onClearReceived;
  final String clearText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        if (onSentChanged != null)
          _MessageBubbleColorControl(
            title: 'Sent bubbles',
            description: sentInherited
                ? 'Inherits the default sent bubble color'
                : 'Local sent-message bubble color',
            hexColor: sentHexColor,
            inherited: sentInherited,
            presets: _sentBubbleColorPresets,
            defaultColor: Theme.of(context).colorScheme.primaryContainer,
            clearText: clearText,
            onChanged: onSentChanged!,
            onClear: onClearSent,
          ),
        if (onReceivedChanged != null)
          _MessageBubbleColorControl(
            title: 'Received bubbles',
            description: receivedInherited
                ? 'Inherits the default received bubble color'
                : 'Local received-message bubble color',
            hexColor: receivedHexColor,
            inherited: receivedInherited,
            presets: _receivedBubbleColorPresets,
            defaultColor: Theme.of(context).colorScheme.surfaceContainerLow,
            clearText: clearText,
            onChanged: onReceivedChanged!,
            onClear: onClearReceived,
          ),
      ],
    );
  }
}

class _MessageBubbleColorControl extends StatelessWidget {
  const _MessageBubbleColorControl({
    required this.title,
    required this.description,
    required this.hexColor,
    required this.inherited,
    required this.presets,
    required this.defaultColor,
    required this.clearText,
    required this.onChanged,
    required this.onClear,
  });

  final String title;
  final String description;
  final String? hexColor;
  final bool inherited;
  final List<_BubbleColorPreset> presets;
  final Color defaultColor;
  final String clearText;
  final Future<void> Function(String? hexColor) onChanged;
  final Future<void> Function()? onClear;

  @override
  Widget build(BuildContext context) {
    final color = hexColor == null
        ? defaultColor
        : parseHexColor(hexColor!) ?? defaultColor;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer.withAlpha(90),
        border: Border.all(
          color: Theme.of(context).colorScheme.secondary.withAlpha(18),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          Row(
            spacing: 10,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    tiamat.Text(title),
                    tiamat.Text.labelLow(description),
                  ],
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in presets)
                _BubblePresetButton(
                  preset: preset,
                  selectedHex: hexColor,
                  onSelected: onChanged,
                ),
            ],
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onClear != null && !inherited)
                tiamat.Button.secondary(
                  text: clearText,
                  onTap: onClear,
                ),
              tiamat.Button.secondary(
                text: "Custom",
                onTap: () async {
                  final selected = await showCustomThemeColorPicker(
                    context,
                    title: title,
                    initialColor: color,
                    defaultColor: defaultColor,
                  );
                  if (selected != null) {
                    await onChanged(colorToHex(selected));
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BubblePresetButton extends StatelessWidget {
  const _BubblePresetButton({
    required this.preset,
    required this.selectedHex,
    required this.onSelected,
  });

  final _BubbleColorPreset preset;
  final String? selectedHex;
  final Future<void> Function(String? hexColor) onSelected;

  @override
  Widget build(BuildContext context) {
    final color =
        parseHexColor(preset.hexColor) ?? Theme.of(context).colorScheme.primary;
    final selected =
        selectedHex?.toLowerCase() == preset.hexColor.toLowerCase();

    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => onSelected(preset.hexColor),
      child: Container(
        width: 112,
        padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: selected
                  ? Icon(
                      Icons.check,
                      size: 17,
                      color: color.computeLuminance() > 0.5
                          ? Colors.black
                          : Colors.white,
                    )
                  : null,
            ),
            Expanded(
              child: tiamat.Text.labelLow(
                preset.label,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
