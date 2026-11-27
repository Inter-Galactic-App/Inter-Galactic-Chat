import 'dart:async';
import 'dart:math';

import 'package:intergalactic/client/components/typing_indicators/typing_indicator_component.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class TypingIndicatorsWidget extends StatefulWidget {
  const TypingIndicatorsWidget({required this.component, super.key});
  final TypingIndicatorComponent component;

  @override
  State<TypingIndicatorsWidget> createState() => _TypingIndicatorsWidgetState();
}

class _TypingIndicatorsWidgetState extends State<TypingIndicatorsWidget> {
  StreamSubscription? sub;

  late List<Member> typingMembers;

  late List<GlobalKey> blobKeys = [
    GlobalKey(),
    GlobalKey(),
    GlobalKey(),
  ];

  Timer? timer;

  late String currentText = "";
  bool reduceMotion = false;

  String typingUsers(int howMany, String user1, String user2, String user3) =>
      Intl.plural(howMany,
          one: "$user1 is typing...",
          two: "$user1 and $user2 are typing...",
          few: "$user1, $user2, and $user3 are typing...",
          other: "Several people are typing...",
          desc: "Text to display which users are currently typing",
          name: "typingUsers",
          args: [howMany, user1, user2, user3]);

  @override
  void initState() {
    sub = widget.component.onTypingUsersUpdated.listen(onTypingUsersUpdated);
    typingMembers = widget.component.typingUsers;
    if (typingMembers.isNotEmpty) {
      currentText = getTypingText();
      startTimer();
    }
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextReduceMotion = AccessibilityScope.of(context).reduceMotion;
    if (nextReduceMotion == reduceMotion) {
      return;
    }

    reduceMotion = nextReduceMotion;
    if (reduceMotion) {
      timer?.cancel();
      timer = null;
    } else if (typingMembers.isNotEmpty && timer == null) {
      startTimer();
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    sub?.cancel();
    super.dispose();
  }

  int prevIndex = 0;

  void onTimer(Timer timer) {
    var r = Random().nextInt(3);

    if (r == prevIndex) {
      r += 1;
      r = r % blobKeys.length;
    }

    prevIndex = r;

    var key = blobKeys[r];

    if (key.currentState == null) {
      return;
    }

    var state = key.currentState! as __SingleTypingIndicatorBlobState;
    state.controller.forward(from: 0);
  }

  void onTypingUsersUpdated(void event) {
    setState(() {
      typingMembers = widget.component.typingUsers;
      if (typingMembers.isNotEmpty) {
        currentText = getTypingText();
        if (!reduceMotion && timer == null) {
          startTimer();
        }
      } else {
        timer?.cancel();
        timer = null;
      }
    });
  }

  void startTimer() {
    if (reduceMotion) {
      return;
    }
    timer = Timer.periodic(const Duration(milliseconds: 250), onTimer);
  }

  @override
  Widget build(BuildContext context) {
    final result = SizedBox(
        height: 23,
        child: ClipRect(
          child: AnimatedSlide(
              duration:
                  InterGalacticMotion.duration(context, Durations.medium3),
              curve: Curves.easeInOutExpo,
              offset: typingMembers.isEmpty ? const Offset(0, 1) : Offset.zero,
              child: Row(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                  child: Row(
                    children: [
                      _SingleTypingIndicatorBlob(
                        key: blobKeys[0],
                      ),
                      _SingleTypingIndicatorBlob(
                        key: blobKeys[1],
                      ),
                      _SingleTypingIndicatorBlob(
                        key: blobKeys[2],
                      ),
                    ],
                  ),
                ),
                tiamat.Text.labelLow(currentText)
              ])),
        ));

    if (typingMembers.isEmpty) {
      return ExcludeSemantics(child: result);
    }

    return Semantics(
      container: true,
      liveRegion: true,
      label: currentText,
      child: ExcludeSemantics(child: result),
    );
  }

  String getTypingText() {
    String user1 = typingMembers[0].displayName;
    String user2 =
        typingMembers.length >= 2 ? typingMembers[1].displayName : "";
    String user3 =
        typingMembers.length >= 3 ? typingMembers[2].displayName : "";
    return typingUsers(typingMembers.length, user1, user2, user3);
  }
}

class _SingleTypingIndicatorBlob extends StatefulWidget {
  const _SingleTypingIndicatorBlob({super.key});

  @override
  State<_SingleTypingIndicatorBlob> createState() =>
      __SingleTypingIndicatorBlobState();
}

class __SingleTypingIndicatorBlobState extends State<_SingleTypingIndicatorBlob>
    with TickerProviderStateMixin {
  late AnimationController controller = AnimationController(
      duration: const Duration(milliseconds: 200), vsync: this, value: 1);

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = InterGalacticMotion.shouldReduce(context);
    return Padding(
      padding: const EdgeInsets.all(1),
      child: reduceMotion ? _staticBlob(context) : _animatedBlob(),
    );
  }

  Widget _animatedBlob() {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        var alpha = 1.0;
        alpha -= sin(controller.value * 3.1415926) * 0.4;

        var translation = sin(controller.value * 3.1415926);

        return SizedBox(
          height: 7,
          width: 7,
          child: Align(
            alignment: Alignment.center,
            heightFactor: controller.value,
            child: Transform(
              transform: Matrix4.translationValues(0, translation * 4, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Align(
                  heightFactor: alpha,
                  child: Container(
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _staticBlob(BuildContext context) {
    return SizedBox(
      height: 7,
      width: 7,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: ColoredBox(
          color: Theme.of(context).colorScheme.secondary,
        ),
      ),
    );
  }
}
