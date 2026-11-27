import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:intergalactic/config/app_globals.dart' as globals;
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:intergalactic/ui/atoms/scaled_safe_area.dart';
import 'package:intergalactic/ui/mobile/mobile_visuals.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';
import 'package:intergalactic/ui/onboarding/demo_tutorial_content.dart';
import 'package:intergalactic/ui/onboarding/mobile_tutorial_content.dart';
import 'package:intergalactic/ui/onboarding/onboarding_content.dart';
import 'package:intergalactic/ui/onboarding/onboarding_controller.dart';
import 'package:intergalactic/ui/onboarding/onboarding_service.dart';
import 'package:intergalactic/ui/onboarding/onboarding_step.dart';
import 'package:intergalactic/ui/onboarding/tutorial_demo_backdrop.dart';
import 'package:intergalactic/ui/onboarding/tutorial_mode.dart';
import 'package:intergalactic/ui/onboarding/tutorial_scene.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({
    super.key,
    this.replay = false,
    this.mode = TutorialMode.realAccount,
    this.service,
    this.steps,
  });

  final bool replay;
  final TutorialMode mode;
  final OnboardingService? service;
  final List<OnboardingStep>? steps;

  static Future<void> show(
    BuildContext context, {
    bool replay = false,
    TutorialMode mode = TutorialMode.realAccount,
    OnboardingService? service,
    List<OnboardingStep>? steps,
  }) {
    return Navigator.of(context).push<void>(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => OnboardingPage(
          replay: replay,
          mode: mode,
          service: service,
          steps: steps,
        ),
        transitionDuration: const Duration(milliseconds: 420),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0, 0.04),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  late final OnboardingController _controller;
  late final List<OnboardingStep> _steps;
  Timer? _autoAdvanceTimer;
  Timer? _mobileAdvanceTimer;
  String? _autoAdvanceStepId;
  bool _saving = false;
  bool _mobileCardVisible = true;
  bool _mobileAdvancePending = false;
  double _mobileHorizontalDragDistance = 0;
  double _mobileVerticalDragDistance = 0;

  static final _goBackSemanticsAction = CustomSemanticsAction(
    label: 'Go back one tutorial step',
  );
  static final _skipSemanticsAction = CustomSemanticsAction(
    label: 'Skip tutorial',
  );

  @override
  void initState() {
    super.initState();

    _steps =
        widget.steps ??
        (widget.mode.usesGuidedDemoBackdrop
            ? (Layout.mobile ? mobileTutorialSteps : demoTutorialSteps)
            : initialOnboardingSteps);
    _controller = OnboardingController(
      service: widget.service ?? OnboardingService(globals.preferences),
      steps: _steps,
      replay: widget.replay,
      mode: widget.mode,
    )..addListener(_handleControllerChanged);
    _scheduleSceneAutoAdvance();
  }

  @override
  void dispose() {
    _autoAdvanceTimer?.cancel();
    _mobileAdvanceTimer?.cancel();
    _controller
      ..removeListener(_handleControllerChanged)
      ..dispose();
    super.dispose();
  }

  void _handleControllerChanged() {
    _scheduleSceneAutoAdvance();
    if (mounted) {
      setState(() {});
    }
  }

  void _scheduleSceneAutoAdvance() {
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = null;
    _autoAdvanceStepId = null;

    if (!widget.mode.usesGuidedDemoBackdrop) {
      return;
    }

    final stepId = _controller.currentStep.id;
    final scene = tutorialSceneForStep(stepId);
    final delay = scene.autoAdvanceAfter;
    if (delay == null || _controller.isLastStep) {
      return;
    }

    _autoAdvanceStepId = stepId;
    _autoAdvanceTimer = Timer(delay, () {
      if (!mounted || _controller.currentStep.id != _autoAdvanceStepId) {
        return;
      }

      _controller.next();
    });
  }

  @override
  Widget build(BuildContext context) {
    // System back (Android gesture/button, iOS edge swipe) is a tutorial
    // control, not an escape hatch: it steps back, and on the first step it
    // is Skip - so the tutorial can only end through a path that writes the
    // same completion state Skip writes.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _saving) {
          return;
        }

        if (_controller.isFirstStep) {
          unawaited(_skip());
        } else {
          _goBack();
        }
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: _buildDefaultPage(context),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _saving) {
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
        event.logicalKey == LogicalKeyboardKey.enter) {
      if (_controller.isLastStep) {
        unawaited(_finish());
      } else {
        _advance();
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _goBack();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      unawaited(_skip());
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _advance() {
    if (_saving || _mobileAdvancePending) {
      return;
    }

    if (!Layout.mobile || !widget.mode.usesGuidedDemoBackdrop) {
      _controller.next();
      return;
    }

    if (_controller.isLastStep) {
      unawaited(_finish());
      return;
    }

    // Briefly hide the card before changing scenes so the person can take in
    // the UI they just learned about. This is intentionally a pause, not a
    // long decorative animation, and reduced motion keeps it instantaneous.
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = null;
    _autoAdvanceStepId = null;
    final reducedMotion = InterGalacticMotion.shouldReduce(context);
    setState(() {
      _mobileAdvancePending = true;
      _mobileCardVisible = false;
    });
    _mobileAdvanceTimer = Timer(
      reducedMotion ? Duration.zero : const Duration(milliseconds: 1200),
      () {
        if (!mounted) {
          return;
        }
        _controller.next();
        if (mounted) {
          setState(() {
            _mobileAdvancePending = false;
            _mobileCardVisible = true;
          });
        }
      },
    );
  }

  void _goBack() {
    if (_saving || _controller.isFirstStep) {
      return;
    }

    _cancelPendingMobileAdvance();
    _controller.back();
  }

  void _cancelPendingMobileAdvance() {
    if (!_mobileAdvancePending && _mobileAdvanceTimer == null) {
      return;
    }

    _mobileAdvanceTimer?.cancel();
    _mobileAdvanceTimer = null;
    if (mounted) {
      setState(() {
        _mobileAdvancePending = false;
        _mobileCardVisible = true;
      });
    }
  }

  void _handleMobileHorizontalDragStart(DragStartDetails details) {
    _mobileHorizontalDragDistance = 0;
  }

  void _handleMobileHorizontalDragUpdate(DragUpdateDetails details) {
    _mobileHorizontalDragDistance += details.delta.dx;
  }

  void _handleMobileHorizontalDragEnd(DragEndDetails details) {
    if (_mobileHorizontalDragDistance > 72 ||
        (details.primaryVelocity ?? 0) > 320) {
      _goBack();
    }
  }

  void _handleMobileVerticalDragStart(DragStartDetails details) {
    _mobileVerticalDragDistance = 0;
  }

  void _handleMobileVerticalDragUpdate(DragUpdateDetails details) {
    _mobileVerticalDragDistance += details.delta.dy;
  }

  void _handleMobileVerticalDragEnd(DragEndDetails details) {
    if ((_mobileVerticalDragDistance < -96 ||
            (details.primaryVelocity ?? 0) < -420) &&
        !_mobileAdvancePending) {
      unawaited(_skip());
    }
  }

  Widget _buildDefaultPage(BuildContext context) {
    if (widget.mode.usesGuidedDemoBackdrop) {
      return _buildDemoPreview(context);
    }

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: tiamat.Tile.surfaceContainer(
        child: ScaledSafeArea(
          child: Layout.mobile ? _buildMobile(context) : _buildDesktop(context),
        ),
      ),
    );
  }

  Widget _buildDemoPreview(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scene = tutorialSceneForStep(_controller.currentStep.id);

    return Material(
      color: scheme.surface,
      child: Stack(
        children: [
          Positioned.fill(
            child: ExcludeFocus(child: _buildDemoBackdrop(scene)),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.surface.withValues(alpha: 0.08),
                      scheme.surface.withValues(alpha: 0.22),
                      scheme.scrim.withValues(alpha: 0.16),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ScaledSafeArea(
            child: Layout.mobile
                ? _buildDemoPreviewMobile(context, scene)
                : _buildDemoPreviewDesktop(context, scene),
          ),
        ],
      ),
    );
  }

  Widget _buildDemoBackdrop(TutorialSceneSpec scene) {
    // Keep the app shell at natural scale. Tutorial scenes should switch rooms,
    // settings, and overlays instead of zooming the whole app into view.
    return TutorialDemoBackdrop(scene: scene);
  }

  Widget _buildDemoPreviewDesktop(
    BuildContext context,
    TutorialSceneSpec scene,
  ) {
    if (scene.hideTutorialCard) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(
          380.0,
          math.max(300.0, constraints.maxWidth * 0.3),
        );
        final height = math.min(
          380.0,
          math.max(320.0, constraints.maxHeight * 0.42),
        );

        return Align(
          alignment: _alignmentForPlacement(scene.cardPlacement),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: SizedBox(
              width: width,
              height: height,
              child: _buildCompactTutorialSurface(),
            ),
          ),
        );
      },
    );
  }

  Alignment _alignmentForPlacement(TutorialCardPlacement placement) {
    return switch (placement) {
      TutorialCardPlacement.topCenter => Alignment.topCenter,
      TutorialCardPlacement.topLeft => Alignment.topLeft,
      TutorialCardPlacement.topRight => Alignment.topRight,
      TutorialCardPlacement.centerLeft => Alignment.centerLeft,
      TutorialCardPlacement.centerRight => Alignment.centerRight,
      TutorialCardPlacement.bottomLeft => Alignment.bottomLeft,
      TutorialCardPlacement.bottomRight => Alignment.bottomRight,
    };
  }

  Widget _buildDemoPreviewMobile(
    BuildContext context,
    TutorialSceneSpec scene,
  ) {
    if (scene.hideTutorialCard) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = math.max(156.0, constraints.maxHeight - 28);
        final placeTop =
            scene.mobileCardPlacement == TutorialMobileCardPlacement.top;
        final titleNeedsTwoLines = _mobileTutorialTitleNeedsTwoLines(
          context,
          constraints,
          placeTop: placeTop,
        );
        final standardHeight = math.min(
          maxHeight,
          math.min(180.0, math.max(156.0, constraints.maxHeight * 0.23)),
        );
        final height = titleNeedsTwoLines
            ? math.min(maxHeight, math.min(196.0, standardHeight + 28))
            : standardHeight;

        return Semantics(
          label:
              '${_controller.progressLabel}. ${_controller.currentStep.title}. ${_controller.currentStep.body}',
          hint:
              'Tap to advance. Swipe right to go back. Swipe up to skip the tutorial.',
          button: true,
          onTap: _mobileAdvancePending ? null : _advance,
          customSemanticsActions: {
            _goBackSemanticsAction: _goBack,
            _skipSemanticsAction: () => unawaited(_skip()),
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _mobileAdvancePending ? null : _advance,
            onHorizontalDragStart: _handleMobileHorizontalDragStart,
            onHorizontalDragUpdate: _handleMobileHorizontalDragUpdate,
            onHorizontalDragEnd: _handleMobileHorizontalDragEnd,
            onVerticalDragStart: _handleMobileVerticalDragStart,
            onVerticalDragUpdate: _handleMobileVerticalDragUpdate,
            onVerticalDragEnd: _handleMobileVerticalDragEnd,
            child: AnimatedAlign(
              duration: InterGalacticMotion.duration(
                context,
                InterGalacticMotion.standard,
              ),
              curve: InterGalacticMotion.standardOut,
              alignment: placeTop
                  ? Alignment.topCenter
                  : Alignment.bottomCenter,
              child: Padding(
                padding: placeTop
                    ? const EdgeInsets.fromLTRB(38, 76, 38, 14)
                    : const EdgeInsets.fromLTRB(14, 14, 14, 22),
                child: AnimatedSlide(
                  duration: InterGalacticMotion.duration(
                    context,
                    InterGalacticMotion.shortEmphasis,
                  ),
                  curve: InterGalacticMotion.standardOut,
                  offset: _mobileCardVisible
                      ? Offset.zero
                      : Offset(0, placeTop ? -0.16 : 0.16),
                  child: AnimatedOpacity(
                    duration: InterGalacticMotion.duration(
                      context,
                      InterGalacticMotion.shortEmphasis,
                    ),
                    opacity: _mobileCardVisible ? 1 : 0,
                    child: SizedBox(
                      key: const ValueKey('mobile-tutorial-sheet'),
                      width: double.infinity,
                      height: height,
                      child: _buildMobileTutorialCard(
                        titleNeedsTwoLines: titleNeedsTwoLines,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  bool _mobileTutorialTitleNeedsTwoLines(
    BuildContext context,
    BoxConstraints constraints, {
    required bool placeTop,
  }) {
    final cardWidth = constraints.maxWidth - (placeTop ? 76 : 28);
    final titleWidth = math.max(0.0, cardWidth - 32);
    final style = Theme.of(context).textTheme.titleMedium?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w500,
      letterSpacing: 0,
    );
    final painter = TextPainter(
      text: TextSpan(text: _controller.currentStep.title, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout(maxWidth: titleWidth);

    return painter.didExceedMaxLines;
  }

  Widget _buildCompactTutorialSurface({bool sheet = false}) {
    return _OnboardingSurface(
      footer: _buildFooter(context),
      floating: widget.mode.usesGuidedDemoBackdrop,
      sheet: sheet,
      child: Column(
        children: [
          _StepRail(
            controller: _controller,
            replay: widget.replay,
            compact: true,
            dense: sheet,
          ),
          SizedBox(height: sheet ? 8 : 18),
          Expanded(
            child: SingleChildScrollView(
              child: _StepContent(
                controller: _controller,
                compact: widget.mode.usesGuidedDemoBackdrop,
                dense: sheet,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileTutorialCard({required bool titleNeedsTwoLines}) {
    return _OnboardingSurface(
      footer: const SizedBox.shrink(),
      floating: true,
      sheet: true,
      child: _MobileTutorialCardContent(
        controller: _controller,
        titleNeedsTwoLines: titleNeedsTwoLines,
      ),
    );
  }

  Widget _buildDesktop(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(
          860.0,
          math.max(320.0, constraints.maxWidth - 64),
        );
        final height = math.min(
          620.0,
          math.max(420.0, constraints.maxHeight - 64),
        );

        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: _OnboardingSurface(
              footer: _buildFooter(context),
              child: Row(
                children: [
                  SizedBox(
                    width: 250,
                    child: _StepRail(
                      controller: _controller,
                      replay: widget.replay,
                    ),
                  ),
                  const SizedBox(width: 28),
                  Expanded(child: _StepContent(controller: _controller)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobile(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(14),
      child: SizedBox.expand(
        child: _OnboardingSurface(
          footer: _buildFooter(context),
          child: Column(
            children: [
              _StepRail(
                controller: _controller,
                replay: widget.replay,
                compact: true,
              ),
              const SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  child: _StepContent(controller: _controller),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _skip() async {
    _mobileAdvanceTimer?.cancel();
    _mobileAdvanceTimer = null;
    await _complete(_controller.skip);
  }

  Future<void> _finish() async {
    await _complete(_controller.finish);
  }

  Future<void> _complete(Future<void> Function() action) async {
    if (_saving) {
      return;
    }

    setState(() {
      _saving = true;
    });

    await action();

    if (!mounted) {
      return;
    }

    Navigator.of(context).pop();
  }

  Widget _buildFooter(BuildContext context) {
    final primaryLabel = _controller.isLastStep
        ? _controller.currentStep.primaryActionLabel ?? "Finish"
        : _controller.currentStep.primaryActionLabel ?? "Next";

    final back = tiamat.Button.secondary(
      text: "Back",
      onTap: _controller.isFirstStep || _saving ? null : _goBack,
    );
    final skip = tiamat.Button.secondary(
      text: "Skip",
      isLoading: _saving,
      onTap: _saving ? null : _skip,
    );
    final primary = tiamat.Button(
      text: primaryLabel,
      isLoading: _saving,
      onTap: _saving
          ? null
          : _controller.isLastStep
          ? _finish
          : _advance,
    );

    return Padding(
      padding: Layout.mobile
          ? const EdgeInsets.fromLTRB(16, 6, 16, 12)
          : const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Layout.mobile
          ? Row(
              children: [
                Expanded(child: back),
                const SizedBox(width: 8),
                Expanded(child: skip),
                const SizedBox(width: 8),
                Expanded(child: primary),
              ],
            )
          : Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [back, skip, primary],
            ),
    );
  }
}

class _OnboardingSurface extends StatelessWidget {
  const _OnboardingSurface({
    required this.child,
    required this.footer,
    this.floating = false,
    this.sheet = false,
  });

  final Widget child;
  final Widget footer;
  final bool floating;

  /// Mobile sheet treatment: mobile card radius, a decorative grip line, and
  /// a fully solid surface when reduce-transparency is active.
  final bool sheet;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = Column(
      children: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              floating ? 16 : 20,
              sheet ? 10 : (floating ? 16 : 20),
              floating ? 16 : 20,
              sheet ? 10 : (floating ? 16 : 20),
            ),
            child: child,
          ),
        ),
        footer,
      ],
    );

    if (!floating) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: tiamat.Tile.low(child: content),
      );
    }

    final reduceTransparency =
        sheet &&
        AccessibilityScope.maybeOf(context)?.reduceTransparency == true;
    final radius = sheet ? MobileVisuals.cardRadius : 14.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: reduceTransparency
            ? scheme.surfaceContainerLow
            : scheme.surfaceContainerLow.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.62)),
        boxShadow: [
          BoxShadow(
            color: scheme.scrim.withValues(alpha: 0.34),
            blurRadius: 30,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius - 1),
        child: Column(children: [Expanded(child: content)]),
      ),
    );
  }
}

class _StepRail extends StatelessWidget {
  const _StepRail({
    required this.controller,
    required this.replay,
    this.compact = false,
    this.dense = false,
  });

  final OnboardingController controller;
  final bool replay;
  final bool compact;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final step = controller.currentStep;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      children: [
        Row(
          children: [
            _StepIcon(icon: step.icon, size: dense ? 40 : 52),
            SizedBox(width: dense ? 10 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tiamat.Text.labelLow(
                    replay ? "Tutorial replay" : "First-run tutorial",
                  ),
                  tiamat.Text.labelEmphasised(
                    controller.progressLabel,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: dense ? 8 : 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: controller.progressValue,
            minHeight: dense ? 5 : 8,
          ),
        ),
        if (!compact) ...[
          const SizedBox(height: 24),
          Expanded(
            child: ListView.builder(
              itemCount: controller.steps.length,
              itemBuilder: (context, index) {
                final item = controller.steps[index];
                final selected = index == controller.index;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(
                                  context,
                                ).colorScheme.outline.withValues(alpha: 0.35),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: tiamat.Text.labelLow(
                          item.title,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _MobileTutorialCardContent extends StatelessWidget {
  const _MobileTutorialCardContent({
    required this.controller,
    required this.titleNeedsTwoLines,
  });

  final OnboardingController controller;
  final bool titleNeedsTwoLines;

  @override
  Widget build(BuildContext context) {
    final step = controller.currentStep;
    final scheme = Theme.of(context).colorScheme;

    return ExcludeSemantics(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            step.title,
            maxLines: titleNeedsTwoLines ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: scheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            step.body,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontSize: 14,
              height: 1.3,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 14),
          Semantics(
            label: controller.progressLabel,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: controller.progressValue,
                minHeight: 5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepContent extends StatelessWidget {
  const _StepContent({
    required this.controller,
    this.compact = false,
    this.dense = false,
  });

  final OnboardingController controller;
  final bool compact;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final step = controller.currentStep;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: Align(
        key: ValueKey(step.id),
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (step.assetPath != null) ...[
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(step.assetPath!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 24),
            ],
            if (compact)
              Text(
                step.title,
                softWrap: true,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: dense ? 17 : 18,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              )
            else
              tiamat.Text.largeTitle(step.title, softwrap: true),
            SizedBox(height: compact ? (dense ? 6 : 10) : 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: compact
                  ? Text(
                      step.body,
                      softWrap: true,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                        height: dense ? 1.28 : 1.34,
                        letterSpacing: 0,
                      ),
                    )
                  : tiamat.Text.body(step.body, softwrap: true),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepIcon extends StatelessWidget {
  const _StepIcon({required this.icon, this.size = 52});

  final IconData? icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).colorScheme.primaryContainer,
      ),
      child: Icon(
        icon ?? Icons.auto_awesome_outlined,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
        size: size * 0.46,
      ),
    );
  }
}
