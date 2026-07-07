import 'package:flutter/material.dart';
import 'package:intergalactic/config/app_globals.dart' as globals;
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/ui/onboarding/onboarding_page.dart';
import 'package:intergalactic/ui/onboarding/onboarding_service.dart';
import 'package:intergalactic/ui/onboarding/tutorial_anchor.dart';
import 'package:intergalactic/ui/onboarding/tutorial_mode.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class HelpTutorialPage extends StatefulWidget {
  const HelpTutorialPage({super.key});

  @override
  State<HelpTutorialPage> createState() => _HelpTutorialPageState();
}

class _HelpTutorialPageState extends State<HelpTutorialPage> {
  late final OnboardingService _service;

  @override
  void initState() {
    super.initState();
    _service = OnboardingService(globals.preferences);
  }

  @override
  Widget build(BuildContext context) {
    if (Layout.mobile) {
      return _buildMobileRestrictedPage();
    }

    final state = _service.state;
    final completedForCurrent =
        state.isCompletedFor(OnboardingService.currentVersion);
    final completedAt = state.completedAt?.toLocal();

    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const tiamat.Text.largeTitle("Tutorial"),
              const SizedBox(height: 8),
              const tiamat.Text.body(
                "Replay the Inter Galactic tour any time. The tutorial is stored as a local app preference on this device.",
                softwrap: true,
              ),
              const SizedBox(height: 16),
              _TutorialSection(
                title: "Status",
                children: [
                  tiamat.Text.body(
                    completedForCurrent
                        ? "Completed tutorial version ${state.version}."
                        : "Not completed for tutorial version ${OnboardingService.currentVersion}.",
                    softwrap: true,
                  ),
                  if (completedAt != null) ...[
                    const SizedBox(height: 8),
                    tiamat.Text.labelLow(
                      "Completed at ${completedAt.toString()}",
                      softwrap: true,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              _TutorialSection(
                title: "Replay",
                children: [
                  const tiamat.Text.body(
                    "The tutorial opens over local sample app data so every step has a stable app context. The final step explains where to replay this later and where app support information lives.",
                    softwrap: true,
                  ),
                  const SizedBox(height: 12),
                  TutorialAnchor(
                    id: TutorialAnchorIds.tutorialReplayButton,
                    padding: const EdgeInsets.all(4),
                    child: tiamat.Button(
                      text: "Replay tutorial",
                      onTap: () async {
                        await OnboardingPage.show(
                          context,
                          replay: true,
                          service: _service,
                        );

                        if (mounted) {
                          setState(() {});
                        }
                      },
                    ),
                  ),
                  if (globals.preferences.developerMode.value) ...[
                    const SizedBox(height: 16),
                    const tiamat.Text.body(
                      "Developer mode keeps the original card-only placeholder available for testing future tutorial copy without the guided app backdrop.",
                      softwrap: true,
                    ),
                    const SizedBox(height: 12),
                    tiamat.Button.secondary(
                      text: "Open placeholder tutorial",
                      onTap: () async {
                        await OnboardingPage.show(
                          context,
                          replay: true,
                          mode: TutorialMode.legacyPlaceholder,
                          service: _service,
                        );

                        if (mounted) {
                          setState(() {});
                        }
                      },
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileRestrictedPage() {
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              tiamat.Text.largeTitle("Tutorial"),
              SizedBox(height: 8),
              tiamat.Text.body(
                "The guided tutorial is desktop-only for now. Mobile builds hide replay until the mobile tutorial path is ready.",
                softwrap: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TutorialSection extends StatelessWidget {
  const _TutorialSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          tiamat.Text.labelEmphasised(title),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}
