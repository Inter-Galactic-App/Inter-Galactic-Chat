enum TutorialMode {
  /// The production tutorial shown after first sign-in and from Help replay.
  ///
  /// It uses the guided offline demo backdrop so users see stable sample app
  /// state, but Skip and Finish still write the real local completion flag.
  realAccount,

  /// Developer/review preview of the guided tutorial that does not write
  /// onboarding completion.
  demoPreview,

  /// Developer-only access to the old card-only placeholder tutorial.
  legacyPlaceholder,
}

extension TutorialModeBehavior on TutorialMode {
  bool get usesGuidedDemoBackdrop =>
      this == TutorialMode.realAccount || this == TutorialMode.demoPreview;

  bool get recordsCompletion => this == TutorialMode.realAccount;
}
