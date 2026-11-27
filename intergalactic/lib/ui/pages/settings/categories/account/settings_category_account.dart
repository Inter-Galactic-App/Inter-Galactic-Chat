import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/account_profile/account_profile_settings_tab.dart';
import 'package:intergalactic/ui/pages/settings/settings_category.dart';
import 'package:intergalactic/ui/pages/settings/settings_tab.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'security/security_tab.dart';

class SettingsCategoryAccount implements SettingsCategory {
  static const accountProfileTabId = "account.profile";
  static const accountSecurityTabId = "account.security";

  String get labelSettingsTabAccountProfile => Intl.message("Account & Profile",
      name: "labelSettingsTabAccountProfile",
      desc: "Label for the combined Account and Profile settings page");

  String get labelSettingsTabPrivacy => Intl.message("Privacy",
      name: "labelSettingsTabPrivacy",
      desc: "Label for the Privacy settings page");

  String get labelSettingsTabSecurity => Intl.message("Security",
      name: "labelSettingsTabSecurity",
      desc: "Label for the Security settings page");

  String get labelSettingsTabDeveloper => Intl.message("Developer",
      name: "labelSettingsTabDeveloper",
      desc: "Label for the Developer settings page");

  String get labelSettingsCategoryAccount => Intl.message("Account",
      name: "labelSettingsCategoryAccount",
      desc: "Label for the settings category Account");

  @override
  String get title => labelSettingsCategoryAccount;

  @override
  List<SettingsTab> get tabs => List.from([
        SettingsTab(
            id: accountProfileTabId,
            label: labelSettingsTabAccountProfile,
            icon: Icons.person,
            makeScrollable: false,
            searchKeywords: const [
              "account & profile",
              "manage accounts",
              "accounts",
              "login",
              "logout",
              "homeserver",
              "profile",
              "display name",
              "avatar",
              "banner",
              "pronouns",
              "status",
              "bio",
              "badges",
              "profile color",
            ],
            searchEntries: const [
              SettingsSearchEntry(
                title: "Selected account",
                section: "Settings header",
                anchorId: "settings-account-header",
                keywords: [
                  "manage accounts",
                  "account selector",
                  "selected account",
                  "homeserver",
                  "login",
                ],
              ),
              SettingsSearchEntry(
                title: "Add account",
                section: "Accounts",
                keywords: ["new account", "login", "plus"],
              ),
              SettingsSearchEntry(
                title: "Display name",
                section: "Profile",
                keywords: ["profile", "name"],
              ),
              SettingsSearchEntry(
                title: "Pronouns",
                section: "Profile",
                keywords: ["profile"],
              ),
              SettingsSearchEntry(
                title: "Status",
                section: "Profile",
                keywords: ["profile", "activity"],
              ),
              SettingsSearchEntry(
                title: "Color",
                section: "Profile",
                keywords: ["profile color", "display name color"],
              ),
              SettingsSearchEntry(
                title: "Bio",
                section: "Profile",
                keywords: ["about me", "profile"],
              ),
              SettingsSearchEntry(
                title: "Profile picture",
                section: "Profile Preview",
                keywords: ["avatar", "set profile picture", "photo"],
              ),
              SettingsSearchEntry(
                title: "Banner",
                section: "Profile Preview",
                keywords: ["profile banner", "header image"],
              ),
              SettingsSearchEntry(
                title: "Badges",
                section: "Profile Preview",
                keywords: ["add badges", "profile badges"],
              ),
              SettingsSearchEntry(
                title: "Show Raw Profile",
                section: "Profile",
                keywords: ["developer", "raw profile", "json"],
              ),
            ],
            pageBuilder: (context) {
              return AccountProfileSettingsTab(
                clientManager: Provider.of<ClientManager>(context),
              );
            }),
        SettingsTab(
            id: accountSecurityTabId,
            label: labelSettingsTabSecurity,
            icon: Icons.security,
            searchKeywords: const [
              "encryption",
              "keys",
              "verification",
              "sessions",
              "devices",
              "account recovery",
              "recovery codes",
              "forgot password",
              "password reset",
              "delete account",
              "account deletion",
              "account deletion guide",
              "deactivate account",
              "homeserver",
            ],
            searchEntries: const [
              SettingsSearchEntry(
                title: "Account Recovery",
                section: "Security",
                anchorId: "setting-row-recovery-codes",
                keywords: [
                  "recovery codes",
                  "forgot password",
                  "password reset",
                  "homeserver recovery",
                ],
              ),
              SettingsSearchEntry(
                title: "Cross Signing & Backup",
                section: "Security",
                keywords: [
                  "cross signing",
                  "message backup",
                  "verification",
                  "encryption",
                  "keys",
                ],
              ),
              SettingsSearchEntry(
                title: "Encrypted message tools",
                section: "Security",
                keywords: [
                  "decrypt",
                  "decryption",
                  "repair encrypted messages",
                  "missing keys",
                  "encrypted history",
                ],
              ),
              SettingsSearchEntry(
                title: "Sessions",
                section: "Security",
                keywords: ["devices", "session", "logged in devices"],
              ),
              SettingsSearchEntry(
                title: "Account Deletion",
                description:
                    "Open the selected homeserver handoff and public account-deletion guide.",
                section: "Security",
                keywords: [
                  "delete account",
                  "deactivate account",
                  "homeserver",
                  "public guide",
                  "account deletion guide",
                ],
              ),
            ],
            pageBuilder: (context) {
              return SecuritySettingsTab(
                clientManager: Provider.of<ClientManager>(context),
              );
            }),
      ]);
}
