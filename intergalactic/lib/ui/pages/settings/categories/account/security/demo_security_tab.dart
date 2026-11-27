import 'package:flutter/material.dart';
import 'package:intergalactic/client/demo/demo_client.dart';
import 'package:intergalactic/ui/onboarding/tutorial_anchor.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/security/matrix/session/matrix_session_view.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class DemoSecuritySettingsTab extends StatelessWidget {
  const DemoSecuritySettingsTab(this.client, {super.key});

  final DemoClient client;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Cross Signing & Backup',
          children: [
            TutorialAnchor(
              id: TutorialAnchorIds.securityVerify,
              padding: const EdgeInsets.all(6),
              child: SettingsControlRow(
                title: 'Verify this device',
                description:
                    'Confirm this demo session before trusting new encrypted messages.',
                trailing: tiamat.Button.secondary(
                  text: 'Verify',
                  onTap: () {},
                ),
              ),
            ),
            TutorialAnchor(
              id: TutorialAnchorIds.securityDecryption,
              padding: const EdgeInsets.all(6),
              child: SettingsControlRow(
                title: 'Encrypted message tools',
                description:
                    'Choose between repairing missing key delivery and retrying messages after keys arrive.',
                trailing: tiamat.Button.secondary(
                  text: 'Choose',
                  onTap: () {},
                ),
              ),
            ),
          ],
        ),
        SettingsSection(
          title: 'Sessions',
          children: [
            TutorialAnchor(
              id: TutorialAnchorIds.securitySessions,
              padding: const EdgeInsets.all(6),
              child: Column(
                children: [
                  MatrixSessionView(
                    displayName: 'Windows desktop',
                    deviceId: 'IG-DEMO-DESKTOP',
                    lastSeenIp: '192.0.2.24',
                    lastSeenTimestamp: DateTime.now().millisecondsSinceEpoch,
                    verified: true,
                    isThisDevice: true,
                    beginVerification: () {},
                  ),
                  const SizedBox(height: 8),
                  MatrixSessionView(
                    displayName: 'iOS review device',
                    deviceId: 'IG-DEMO-MOBILE',
                    lastSeenIp: '192.0.2.51',
                    lastSeenTimestamp: DateTime.now()
                        .subtract(const Duration(hours: 4))
                        .millisecondsSinceEpoch,
                    beginVerification: () {},
                    removeSession: () {},
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
