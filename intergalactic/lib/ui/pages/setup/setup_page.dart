import 'dart:async';

import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/ui/atoms/scaled_safe_area.dart';
import 'package:intergalactic/ui/pages/setup/setup_menu.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class SetupPage extends StatefulWidget {
  const SetupPage(this.menus, {super.key});
  final List<SetupMenu> menus;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  int currentMenuIndex = 0;
  late SetupMenu currentMenu;
  StreamSubscription<SetupMenuState>? _menuStateSubscription;
  SetupMenuState _menuState = SetupMenuState.canProgress;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    currentMenu = widget.menus[currentMenuIndex];
    _listenToCurrentMenu();
  }

  void _listenToCurrentMenu() {
    _menuStateSubscription?.cancel();
    _menuState = currentMenu.state;
    _menuStateSubscription = currentMenu.onStateChanged.listen((state) {
      if (mounted) {
        setState(() => _menuState = state);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Tile.surfaceContainer(
        child: Padding(
          padding: EdgeInsets.all(BuildConfig.MOBILE ? 10 : 50.0),
          child: ScaledSafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.max,
              children: [
                Flexible(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Tile.low(
                      child: Column(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: SingleChildScrollView(
                                child: currentMenu.builder(context),
                              ),
                            ),
                          ),
                          Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: tiamat.Button(
                                    text: CommonStrings.promptNext,
                                    onTap:
                                        _isSubmitting ||
                                            _menuState ==
                                                SetupMenuState.cannotProgress
                                        ? null
                                        : goNextMenu,
                                  ),
                                ),
                              ),
                              TweenAnimationBuilder(
                                tween: Tween<double>(
                                  begin: 0,
                                  end: currentMenuIndex / widget.menus.length,
                                ),
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeOutCubic,
                                builder: (context, value, _) {
                                  return LinearProgressIndicator(value: value);
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> goNextMenu() async {
    if (_isSubmitting || _menuState == SetupMenuState.cannotProgress) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await currentMenu.submit();
    } catch (error, stackTrace) {
      // This runs fire-and-forget from onTap, so an escaping error only
      // reaches the zone handler: the page would stay put with nothing said.
      // Stay on this menu instead - a menu that refused to submit has not
      // produced the state the next one depends on.
      Log.onError(error, stackTrace, content: 'Setup menu submit failed');
      return;
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }

    if (!mounted) {
      return;
    }

    final newIndex = currentMenuIndex + 1;

    if (newIndex >= widget.menus.length) {
      Navigator.pop(context);
    } else {
      setState(() {
        currentMenuIndex = newIndex;
        currentMenu = widget.menus[currentMenuIndex];
        _listenToCurrentMenu();
      });
    }
  }

  @override
  void dispose() {
    _menuStateSubscription?.cancel();
    super.dispose();
  }
}
