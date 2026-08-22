class OnboardingState {
  const OnboardingState({
    required this.completed,
    required this.version,
    required this.completedAt,
  });

  final bool completed;
  final int version;
  final DateTime? completedAt;

  bool isCompletedFor(int currentVersion) {
    return completed && version >= currentVersion;
  }
}
