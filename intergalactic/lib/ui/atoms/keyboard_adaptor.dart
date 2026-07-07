import 'dart:math';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/utils/scaled_app.dart';
import 'package:flutter/material.dart';

class KeyboardAdaptorController {
  Function()? keepCurrentSize;
  Function()? clearOverride;

  bool Function()? hasOverride;
  double? Function()? currentReservedHeight;
}

class KeyboardAdaptor extends StatefulWidget {
  const KeyboardAdaptor({
    super.key,
    required this.child,
    this.paddingContent,
    this.enabled = true,
    this.shouldPushContent,
    this.controller,
    this.systemKeyboardGap = 0,
  });

  final Widget child;
  final bool enabled;
  final Widget? paddingContent;
  final bool Function()? shouldPushContent;
  final KeyboardAdaptorController? controller;
  final double systemKeyboardGap;
  @override
  State<KeyboardAdaptor> createState() => _KeyboardAdaptorState();
}

class _KeyboardAdaptorState extends State<KeyboardAdaptor> {
  // Android/iOS own the IME animation. Follow viewInsets directly so the
  // composer stays attached to the keyboard instead of trailing behind it.
  static const keyboardMotionDuration = Duration.zero;
  static const keyboardMotionCurve = Curves.linear;

  double? sizeOverride;

  @override
  initState() {
    super.initState();
    _attachController(widget.controller);
  }

  @override
  void didUpdateWidget(covariant KeyboardAdaptor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detachController(oldWidget.controller);
      _attachController(widget.controller);
    }
  }

  @override
  void dispose() {
    _detachController(widget.controller);
    super.dispose();
  }

  void _attachController(KeyboardAdaptorController? controller) {
    controller?.keepCurrentSize = keepCurrentSize;
    controller?.clearOverride = clearOverride;
    controller?.hasOverride = hasOverride;
    controller?.currentReservedHeight = currentReservedHeight;
  }

  void _detachController(KeyboardAdaptorController? controller) {
    controller?.keepCurrentSize = null;
    controller?.clearOverride = null;
    controller?.hasOverride = null;
    controller?.currentReservedHeight = null;
  }

  @override
  Widget build(BuildContext context) {
    var scaledQuery = MediaQuery.of(context).scale();
    final keyboardVisible = scaledQuery.viewInsets.bottom > 0;
    final safeAreaBottom = scaledQuery.padding.bottom;
    var offset = max(scaledQuery.viewInsets.bottom, safeAreaBottom);
    final hasPaddingContent = widget.paddingContent != null;
    final shouldReserveContentHeight =
        hasPaddingContent || sizeOverride != null;

    var padding = scaledQuery.viewPadding;
    final retainedBottomPadding = (PlatformUtils.isIOS && keyboardVisible)
        ? 0.0
        : padding.bottom;

    bool shouldPushContent =
        widget.shouldPushContent == null ||
        widget.shouldPushContent?.call() == true;
    // Mobile chat owns system-keyboard avoidance in Flutter. The optional
    // shouldPushContent callback only controls custom panels such as emoji,
    // GIF, and sticker pickers; normal text keyboard focus must always push.
    final shouldAvoidSystemKeyboard =
        (PlatformUtils.isAndroid || PlatformUtils.isIOS) &&
        keyboardVisible &&
        !hasPaddingContent &&
        sizeOverride == null;
    final pickerReservedHeight = _pickerReservedHeight(baseOffset: offset);

    if (sizeOverride != null && offset > sizeOverride!) {
      preferences.emojiPickerHeight.set(pickerReservedHeight);
      sizeOverride = null;
    }

    var contentHeight = shouldReserveContentHeight
        ? (sizeOverride ?? offset) - retainedBottomPadding
        : 0.0;
    var pushHeight =
        ((hasPaddingContent && shouldPushContent) || shouldAvoidSystemKeyboard)
        ? (offset - retainedBottomPadding)
        : 0.0;
    if (shouldAvoidSystemKeyboard && pushHeight > 0) {
      pushHeight += widget.systemKeyboardGap;
    }
    pushHeight = max(pushHeight, 0);
    contentHeight = max(contentHeight, 0);
    final customPanelTopGap =
        PlatformUtils.isIOS && hasPaddingContent && widget.systemKeyboardGap > 0
        ? min(widget.systemKeyboardGap, contentHeight)
        : 0.0;
    var paddingContent = widget.paddingContent;
    if (paddingContent != null && customPanelTopGap > 0) {
      final panelContent = paddingContent;
      // The iOS keyboard gap is empty space above the panel, not extra panel
      // height. Keep the total reservation keyboard-sized while lowering the
      // custom picker to match the native keyboard spacing.
      paddingContent = Column(
        children: [
          SizedBox(height: customPanelTopGap),
          if (contentHeight > customPanelTopGap) Expanded(child: panelContent),
        ],
      );
    }

    return Column(
      children: [
        widget.child,
        Container(
          //color: Colors.green.withAlpha(40),
          child: AnimatedContainer(
            duration: keyboardMotionDuration,
            curve: keyboardMotionCurve,
            child: paddingContent,
            height:
                (!widget.enabled && sizeOverride == null) ||
                    !shouldReserveContentHeight
                ? 0
                : contentHeight,
          ),
        ),
        Container(
          // color: Colors.blue.withAlpha(40),
          child: AnimatedContainer(
            duration: keyboardMotionDuration,
            curve: keyboardMotionCurve,
            height: widget.enabled ? pushHeight : 0,
          ),
        ),
        SizedBox(height: widget.enabled ? retainedBottomPadding : 0),
      ],
    );
  }

  keepCurrentSize({double min = 300}) {
    if (!mounted) {
      return;
    }
    var scaledQuery = MediaQuery.of(context).scale();
    var offset = max(scaledQuery.viewInsets.bottom, scaledQuery.padding.bottom);

    if (offset < min) {
      offset = preferences.emojiPickerHeight.value;
    } else {
      offset = _pickerReservedHeight(baseOffset: offset);
      preferences.emojiPickerHeight.set(offset);
    }

    sizeOverride = offset;
  }

  double _pickerReservedHeight({required double baseOffset}) {
    return baseOffset + widget.systemKeyboardGap;
  }

  clearOverride() {
    if (!mounted) {
      return;
    }
    setState(() {
      sizeOverride = null;
    });
  }

  bool hasOverride() {
    return mounted && sizeOverride != null;
  }

  double? currentReservedHeight() {
    if (!mounted) {
      return null;
    }

    return sizeOverride;
  }
}
