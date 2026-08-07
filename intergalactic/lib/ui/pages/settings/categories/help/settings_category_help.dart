import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/ui/pages/settings/categories/help/help_faq_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/help/help_safety_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/help/help_tutorial_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/help/report_bug_page.dart';
import 'package:intergalactic/ui/pages/settings/settings_category.dart';
import 'package:intergalactic/ui/pages/settings/settings_tab.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class SettingsCategoryHelp implements SettingsCategory {
  static const tabIdSafety = "help.safety";
  static const tabIdFaq = "help.faq";
  static const tabIdReportBug = "help.report_bug";
  static const tabIdPolicies = "help.policies";
  static const tabIdTutorial = "help.tutorial";

  String get labelSettingsHelpSafety => Intl.message(
        "Help & Safety",
        name: "labelSettingsHelpSafety",
        desc: "Label for the safety and abuse reporting settings page",
      );

  String get labelSettingsHelpPolicies => Intl.message(
        "Policies",
        name: "labelSettingsHelpPolicies",
        desc: "Label for the app policy documents settings page",
      );

  String get labelSettingsHelpReportBug => Intl.message(
        "Report a Bug",
        name: "labelSettingsHelpReportBug",
        desc: "Label for the app bug reporting settings page",
      );

  String get labelSettingsHelpFaq => Intl.message(
        "FAQ",
        name: "labelSettingsHelpFaq",
        desc: "Label for the app frequently asked questions settings page",
      );

  String get labelSettingsHelpTutorial => Intl.message(
        "Tutorial",
        name: "labelSettingsHelpTutorial",
        desc: "Label for the app tutorial replay settings page",
      );

  @override
  List<SettingsTab> get tabs => [
        SettingsTab(
          id: tabIdSafety,
          label: labelSettingsHelpSafety,
          icon: Icons.help_outline,
          searchKeywords: const [
            "support",
            "report",
            "abuse",
            "block",
            "safety",
            "feedback",
            "feature request",
          ],
          searchEntries: const [
            SettingsSearchEntry(
              title: "Send feedback or request a feature",
              description:
                  "Open the website feedback form without attaching diagnostics or account identifiers.",
              section: "Help",
              keywords: [
                "feedback",
                "feature request",
                "usability feedback",
                "general feedback",
                "support",
              ],
            ),
          ],
          pageBuilder: (context) => const HelpSafetyPage(),
        ),
        SettingsTab(
          id: tabIdFaq,
          label: labelSettingsHelpFaq,
          icon: Icons.question_answer_outlined,
          searchKeywords: const [
            "faq",
            "frequently asked questions",
            "questions",
            "answers",
            "help",
            "troubleshooting",
            "support",
            "how do i",
          ],
          searchEntries: faqSearchEntries,
          pageBuilder: (context) => const HelpFaqPage(),
        ),
        SettingsTab(
          id: tabIdReportBug,
          label: labelSettingsHelpReportBug,
          icon: Icons.bug_report_outlined,
          searchKeywords: const [
            "bug",
            "report bug",
            "diagnostics",
            "logs",
            "support",
          ],
          searchEntries: const [
            SettingsSearchEntry(
              title: "Report a Bug",
              description:
                  "Send a redacted app diagnostic report after previewing it.",
              section: "Help",
              keywords: [
                "logs",
                "diagnostics",
                "support",
                "crash",
                "bug report",
              ],
            ),
          ],
          pageBuilder: (context) => const ReportBugPage(),
        ),
        SettingsTab(
          id: tabIdPolicies,
          label: labelSettingsHelpPolicies,
          icon: Icons.policy_outlined,
          searchKeywords: const [
            "privacy policy",
            "terms",
            "guidelines",
            "eula",
            "support",
            "report abuse",
            "account deletion",
            "source offer",
            "third-party notices",
            "third party licenses",
            "asset provenance",
          ],
          searchEntries: const [
            SettingsSearchEntry(
              title: "Privacy Policy",
              description: "Open the hosted public privacy policy.",
              section: "Policies",
              keywords: [
                "privacy",
                "policy",
                "public link",
                "app store",
              ],
            ),
            SettingsSearchEntry(
              title: "Terms / EULA",
              description: "Open the hosted public terms and EULA page.",
              section: "Policies",
              keywords: ["terms", "eula", "public link"],
            ),
            SettingsSearchEntry(
              title: "Community Guidelines",
              description: "Open the hosted public community guidelines.",
              section: "Policies",
              keywords: ["guidelines", "moderation", "safety"],
            ),
            SettingsSearchEntry(
              title: "Report Abuse",
              description: "Open the hosted public abuse-reporting guide.",
              section: "Policies",
              keywords: ["abuse", "safety", "report"],
            ),
            SettingsSearchEntry(
              title: "Account Deletion",
              description: "Open the hosted Matrix account-deletion guide.",
              section: "Policies",
              keywords: ["delete account", "deactivate", "homeserver"],
            ),
            SettingsSearchEntry(
              title: "Source Offer",
              description: "Open the hosted source and license information.",
              section: "Policies",
              keywords: ["source", "license", "agpl", "fork"],
            ),
            SettingsSearchEntry(
              title: "Third-Party Notices",
              description:
                  "Open the hosted third-party notices and license bundle.",
              section: "Policies",
              keywords: [
                "third party",
                "third-party",
                "licenses",
                "notices",
                "asset provenance",
              ],
            ),
          ],
          pageBuilder: (context) => const HelpPoliciesPage(),
        ),
        if (!Layout.mobile)
          SettingsTab(
            id: tabIdTutorial,
            label: labelSettingsHelpTutorial,
            icon: Icons.school_outlined,
            searchKeywords: const [
              "onboarding",
              "tour",
              "guide",
              "replay",
            ],
            searchEntries: const [
              SettingsSearchEntry(
                title: "Replay tutorial",
                description: "Open the Inter Galactic tutorial again.",
                section: "Help",
                keywords: [
                  "onboarding",
                  "tour",
                  "guide",
                  "replay",
                ],
              ),
            ],
            pageBuilder: (context) => const HelpTutorialPage(),
          ),
      ];

  @override
  String? get title => null;
}
