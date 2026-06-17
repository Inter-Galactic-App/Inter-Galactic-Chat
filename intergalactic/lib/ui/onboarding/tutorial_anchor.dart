import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

class TutorialAnchorIds {
  const TutorialAnchorIds._();

  static const spaceRail = 'tutorial.spaceRail';
  static const roomList = 'tutorial.roomList';
  static const composer = 'tutorial.composer';
  static const composerPlusButton = 'tutorial.composerPlusButton';
  static const composerEffectsButton = 'tutorial.composerEffectsButton';
  static const composerEmojiButton = 'tutorial.composerEmojiButton';
  static const composerPopup = 'tutorial.composerPopup';
  static const effectsMenu = 'tutorial.effectsMenu';
  static const timeline = 'tutorial.timeline';
  static const roomSidePanel = 'tutorial.roomSidePanel';
  static const settingsSurface = 'tutorial.settingsSurface';
  static const accountPanel = 'tutorial.accountPanel';
  static const activityCard = 'tutorial.activityCard';
  static const accountPopup = 'tutorial.accountPopup';
  static const emoticonHeart = 'tutorial.emoticonHeart';
  static const emoticonPacks = 'tutorial.emoticonPacks';
  static const callView = 'tutorial.callView';
  static const callPanel = 'tutorial.callPanel';
  static const callPopoutButton = 'tutorial.callPopoutButton';
  static const callControls = 'tutorial.callControls';
  static const callSoundboardButton = 'tutorial.callSoundboardButton';
  static const roomDecryptPadlock = 'tutorial.roomDecryptPadlock';
  static const soundboardPopup = 'tutorial.soundboardPopup';
  static const companionPreview = 'tutorial.companionPreview';
  static const securityVerify = 'tutorial.securityVerify';
  static const securityDecryption = 'tutorial.securityDecryption';
  static const securitySessions = 'tutorial.securitySessions';
  static const encryptedRoomPadlock = 'tutorial.encryptedRoomPadlock';
  static const faqAnswer = 'tutorial.faqAnswer';
  static const tutorialReplayButton = 'tutorial.tutorialReplayButton';
}

class TutorialAnchorRegistry extends ChangeNotifier {
  final Map<String, Rect> _rects = {};
  Size? _viewportSize;
  bool _disposed = false;

  Rect? rectFor(String id) => _rects[id];

  void updateViewport(Size size) {
    if (_disposed || size.isEmpty) {
      return;
    }

    final previous = _viewportSize;
    if (previous != null && _nearlyEqualSize(previous, size)) {
      return;
    }

    _viewportSize = size;
    if (_rects.isNotEmpty) {
      _rects.clear();
    }
    notifyListeners();
  }

  void invalidate(String id) {
    if (_disposed) {
      return;
    }

    if (_rects.remove(id) != null) {
      notifyListeners();
    }
  }

  void update(String id, Rect rect) {
    if (_disposed) {
      return;
    }

    final previous = _rects[id];

    if (previous != null && _nearlyEqual(previous, rect)) {
      return;
    }

    _rects[id] = rect;
    notifyListeners();
  }

  void remove(String id) {
    if (_disposed) {
      return;
    }

    if (_rects.remove(id) != null) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _rects.clear();
    super.dispose();
  }

  bool _nearlyEqual(Rect a, Rect b) {
    return (a.left - b.left).abs() < 0.5 &&
        (a.top - b.top).abs() < 0.5 &&
        (a.width - b.width).abs() < 0.5 &&
        (a.height - b.height).abs() < 0.5;
  }

  bool _nearlyEqualSize(Size a, Size b) {
    return (a.width - b.width).abs() < 0.5 && (a.height - b.height).abs() < 0.5;
  }
}

class TutorialAnchorScope extends InheritedNotifier<TutorialAnchorRegistry> {
  const TutorialAnchorScope({
    required TutorialAnchorRegistry registry,
    required super.child,
    super.key,
  }) : super(notifier: registry);

  static TutorialAnchorRegistry? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<TutorialAnchorScope>()
        ?.notifier;
  }
}

class TutorialAnchor extends StatefulWidget {
  const TutorialAnchor({
    required this.id,
    required this.child,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final String id;
  final Widget child;
  final EdgeInsets padding;

  @override
  State<TutorialAnchor> createState() => _TutorialAnchorState();
}

class _TutorialAnchorState extends State<TutorialAnchor>
    with WidgetsBindingObserver {
  TutorialAnchorRegistry? _registry;
  bool _measureScheduled = false;
  Timer? _animationFollowUpTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant TutorialAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.id != widget.id) {
      _registry?.remove(oldWidget.id);
    }
    _scheduleCurrentMeasure();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scheduleCurrentMeasure();
  }

  @override
  void didChangeMetrics() {
    _registry?.invalidate(widget.id);
    _scheduleCurrentMeasure();
  }

  @override
  void dispose() {
    _animationFollowUpTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _registry?.remove(widget.id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final registry = TutorialAnchorScope.maybeOf(context);
    if (_registry != registry) {
      _registry?.remove(widget.id);
    }
    _registry = registry;

    if (registry != null) {
      _scheduleMeasure(registry);
    }

    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }

          _scheduleCurrentMeasure();
          _scheduleAnimationFollowUp();
        });
        return false;
      },
      child: SizeChangedLayoutNotifier(
        child: widget.child,
      ),
    );
  }

  void _scheduleCurrentMeasure() {
    final registry = _registry;
    if (registry != null) {
      _scheduleMeasure(registry);
    }
  }

  void _scheduleMeasure(TutorialAnchorRegistry registry) {
    if (_measureScheduled) {
      return;
    }

    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;

      if (!mounted) {
        return;
      }

      final renderObject = context.findRenderObject();
      if (renderObject is! RenderBox ||
          !renderObject.attached ||
          renderObject.size.isEmpty) {
        registry.remove(widget.id);
        return;
      }

      final topLeft = renderObject.localToGlobal(Offset.zero);
      final rect = _withPadding(topLeft & renderObject.size, widget.padding);
      registry.update(widget.id, rect);
    });
  }

  void _scheduleAnimationFollowUp() {
    _animationFollowUpTimer?.cancel();
    _animationFollowUpTimer = Timer(const Duration(milliseconds: 240), () {
      _scheduleCurrentMeasure();
    });
  }

  Rect _withPadding(Rect rect, EdgeInsets padding) {
    return Rect.fromLTRB(
      math.max(0.0, rect.left - padding.left),
      math.max(0.0, rect.top - padding.top),
      rect.right + padding.right,
      rect.bottom + padding.bottom,
    );
  }
}
