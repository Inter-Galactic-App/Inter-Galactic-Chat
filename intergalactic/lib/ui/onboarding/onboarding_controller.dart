import 'package:flutter/foundation.dart';
import 'package:intergalactic/ui/onboarding/onboarding_service.dart';
import 'package:intergalactic/ui/onboarding/onboarding_step.dart';
import 'package:intergalactic/ui/onboarding/tutorial_mode.dart';

class OnboardingController extends ChangeNotifier {
  OnboardingController({
    required this.service,
    required this.steps,
    this.replay = false,
    this.mode = TutorialMode.realAccount,
  }) : assert(
          steps.isNotEmpty,
          'OnboardingController requires at least one onboarding step',
        );

  final OnboardingService service;
  final List<OnboardingStep> steps;
  final bool replay;
  final TutorialMode mode;

  int _index = 0;

  int get index => _index;
  int get progressNumber => _index + 1;
  bool get isFirstStep => _index == 0;
  bool get isLastStep => _index >= steps.length - 1;
  OnboardingStep get currentStep => steps[_index];
  String get progressLabel => "$progressNumber of ${steps.length}";
  double get progressValue => progressNumber / steps.length;

  void next() {
    if (isLastStep) {
      return;
    }

    _index += 1;
    notifyListeners();
  }

  void back() {
    if (isFirstStep) {
      return;
    }

    _index -= 1;
    notifyListeners();
  }

  Future<void> skip() {
    if (!mode.recordsCompletion) {
      return Future.value();
    }

    return service.markCompleted();
  }

  Future<void> finish() {
    if (!mode.recordsCompletion) {
      return Future.value();
    }

    return service.markCompleted();
  }
}
