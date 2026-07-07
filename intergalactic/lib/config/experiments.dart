class ExperimentDefinition {
  const ExperimentDefinition({
    required this.id,
    required this.label,
    required this.description,
    this.developerOnly = false,
    this.requiresRestart = true,
  });

  final String id;
  final String label;
  final String description;
  final bool developerOnly;
  final bool requiresRestart;
}

class Experiments {
  static const String profileBadgeTesting = "profile_badge_testing";

  static const List<ExperimentDefinition> available = [
    ExperimentDefinition(
      id: profileBadgeTesting,
      label: "Profile badge testing",
      description:
          "Adds local Inter Galactic sample badges to the profile badge picker "
          "so the old Commet badge flow can be tested without donation "
          "account data.",
      developerOnly: true,
      requiresRestart: false,
    ),
  ];

  static bool get hasExperiments => available.isNotEmpty;

  static List<ExperimentDefinition> visibleFor({
    required bool developerMode,
  }) {
    return available
        .where((experiment) => !experiment.developerOnly || developerMode)
        .toList(growable: false);
  }

  static bool hasVisibleExperiments({required bool developerMode}) {
    return visibleFor(developerMode: developerMode).isNotEmpty;
  }
}
