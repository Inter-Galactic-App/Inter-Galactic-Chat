import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/ui/onboarding/onboarding_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Preferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = Preferences();
    await preferences.init();
  });

  test('empty state should show onboarding for logged-in users', () {
    final service = OnboardingService(preferences);

    expect(service.shouldShow(isLoggedIn: true), isTrue);
    expect(service.shouldShow(isLoggedIn: false), isFalse);
  });

  test('completed current version should not show onboarding', () async {
    final completedAt = DateTime.utc(2026, 5, 5, 14, 30);
    final service = OnboardingService(
      preferences,
      clock: () => completedAt,
    );

    await service.markCompleted();

    expect(service.shouldShow(isLoggedIn: true), isFalse);
    expect(preferences.onboardingCompleted.value, isTrue);
    expect(
        preferences.onboardingVersion.value, OnboardingService.currentVersion);
    expect(service.state.completedAt, completedAt);
  });

  test('skip and finish completion records are idempotent', () async {
    final service = OnboardingService(preferences);

    await service.markCompleted();
    await service.markCompleted();

    expect(service.state.completed, isTrue);
    expect(service.state.version, OnboardingService.currentVersion);
    expect(service.state.completedAt, isNotNull);
  });

  test('lower stored version re-triggers onboarding after a version bump',
      () async {
    final versionOneService = OnboardingService(
      preferences,
      tutorialVersion: 1,
    );
    await versionOneService.markCompleted();

    final versionTwoService = OnboardingService(
      preferences,
      tutorialVersion: 2,
    );

    expect(versionOneService.shouldShow(isLoggedIn: true), isFalse);
    expect(versionTwoService.shouldShow(isLoggedIn: true), isTrue);
  });

  test('completed flag without matching version replays onboarding', () async {
    await preferences.onboardingCompleted.set(true);
    await preferences.onboardingVersion
        .set(OnboardingService.currentVersion - 1);
    await preferences.onboardingCompletedAt
        .set(DateTime.utc(2026, 5, 5).toIso8601String());

    final service = OnboardingService(preferences);

    expect(service.state.completed, isTrue);
    expect(service.state.version, OnboardingService.currentVersion - 1);
    expect(service.state.completedAt, DateTime.utc(2026, 5, 5));
    expect(service.shouldShow(isLoggedIn: true), isTrue);
  });

  test('invalid completed timestamp keeps completion state readable', () async {
    await preferences.onboardingCompleted.set(true);
    await preferences.onboardingVersion.set(OnboardingService.currentVersion);
    await preferences.onboardingCompletedAt.set('not-a-date');

    final service = OnboardingService(preferences);

    expect(service.state.completed, isTrue);
    expect(service.state.completedAt, isNull);
    expect(service.shouldShow(isLoggedIn: true), isFalse);
  });

  test('completed state survives a new Preferences initialization', () async {
    final service = OnboardingService(preferences);
    await service.markCompleted();

    final reloadedPreferences = Preferences();
    await reloadedPreferences.init();
    final reloadedService = OnboardingService(reloadedPreferences);

    expect(reloadedService.shouldShow(isLoggedIn: true), isFalse);
    expect(reloadedService.state.completed, isTrue);
    expect(reloadedService.state.version, OnboardingService.currentVersion);
  });
}
