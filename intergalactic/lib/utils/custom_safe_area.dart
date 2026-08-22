import 'dart:async';

import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:flutter/material.dart';

class CustomSafeArea extends StatefulWidget {
  const CustomSafeArea({required this.child, super.key});
  final Widget child;

  @override
  State<CustomSafeArea> createState() => _CustomSafeAreaState();
}

class _CustomSafeAreaState extends State<CustomSafeArea> {
  bool isTextFieldFocused = false;
  StreamSubscription<bool>? textFieldFocusedSubscription;

  @override
  void initState() {
    textFieldFocusedSubscription =
        EventBus.onTextFieldFocused.stream.listen(onTextFieldFocused);
    super.initState();
  }

  @override
  void dispose() {
    textFieldFocusedSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (preferences.customOnscreenKeyboardViewOffset.value == 0) {
      return widget.child;
    }

    var query = MediaQuery.of(context);

    return MediaQuery(
        data: query.copyWith(
            viewPadding: EdgeInsets.fromLTRB(
                0,
                0,
                0,
                isTextFieldFocused
                    ? preferences.customOnscreenKeyboardViewOffset.value
                    : 0)),
        child: widget.child);
  }

  void onTextFieldFocused(bool event) {
    if (!mounted) {
      return;
    }

    if (event != isTextFieldFocused) {
      setState(() {
        isTextFieldFocused = event;
      });
    }
  }
}
