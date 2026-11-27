import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/ui/onboarding/onboarding_state.dart';

class OnboardingService {
  OnboardingService(
    this.preferences, {
    this.tutorialVersion = currentVersion,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const int currentVersion = 1;

  final Preferences preferences;
  final int tutorialVersion;
  final DateTime Function() _clock;

  OnboardingState get state {
    final completedAt = preferences.onboardingCompletedAt.value;

    return OnboardingState(
      completed: preferences.onboardingCompleted.value,
      version: preferences.onboardingVersion.value,
      completedAt: completedAt == null ? null : DateTime.tryParse(completedAt),
    );
  }

  bool shouldShow({required bool isLoggedIn}) {
    return isLoggedIn && !state.isCompletedFor(tutorialVersion);
  }

  Future<void> markCompleted() async {
    await preferences.onboardingCompleted.set(true);
    await preferences.onboardingVersion.set(tutorialVersion);
    await preferences.onboardingCompletedAt.set(_clock().toIso8601String());
  }
}
