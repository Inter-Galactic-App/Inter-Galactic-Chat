"""Execute the NSE's actual policy parser against pre-developer-mode snapshots."""

import pathlib
import subprocess
import sys
import tempfile
import textwrap
import unittest


SOURCE = (
    pathlib.Path(__file__).resolve().parent.parent
    / "InterGalactic Notification Extension"
    / "NotificationService.swift"
)
START = "// MARK: - Policy (C1-C3)"
END = "// MARK: - Host backup-version handoff (E2, E3)"


@unittest.skipUnless(sys.platform == "darwin", "NSE Swift policy test requires macOS")
class SnapshotCompatibilityTests(unittest.TestCase):
    def test_old_snapshot_keeps_rich_preview_without_developer_mode(self):
        source = SOURCE.read_text(encoding="utf-8")
        self.assertEqual(source.count(START), 1)
        self.assertEqual(source.count(END), 1)
        policy = source.split(START, 1)[1].split(END, 1)[0]
        harness = textwrap.dedent(
            """
            import CryptoKit
            import Foundation

            @main struct PolicyCompatibility {
              static func main() throws {
                let root = FileManager.default.temporaryDirectory
                  .appendingPathComponent(UUID().uuidString, isDirectory: true)
                let policyDir = root.appendingPathComponent("notification-policy", isDirectory: true)
                try FileManager.default.createDirectory(at: policyDir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: root) }

                // The old host wrote every policy field below, but no developer_mode.
                var old: [String: Any] = [
                  "version": 1,
                  "notifications_enabled": true,
                  "notification_mode": "all",
                  "preview_choice": "rich",
                  "show_media": true,
                  "digest_key": String(repeating: "00", count: 32),
                  "snoozes": [],
                ]
                func decision(_ doc: [String: Any]) throws -> NSEPolicy.Decision {
                  let data = try JSONSerialization.data(withJSONObject: doc)
                  try data.write(to: policyDir.appendingPathComponent("policy.json"))
                  return NSEPolicy.load(container: root).decide(
                    clientId: "client", roomId: "!room:example.org", now: Date()
                  )
                }
                switch try decision(old) {
                case .render(let rendering):
                  precondition(rendering.showMedia && rendering.richActions)
                  precondition(!rendering.developerMode)
                default: fatalError("old rich snapshot became generic")
                }

                old["developer_mode"] = true
                switch try decision(old) {
                case .render(let rendering): precondition(rendering.developerMode)
                default: fatalError("explicit Developer Mode became generic")
                }

                old["developer_mode"] = "yes"
                switch try decision(old) {
                case .generic(let reason): precondition(reason == "policy_malformed")
                default: fatalError("malformed Developer Mode was accepted")
                }

                old.removeValue(forKey: "developer_mode")
                old["notifications_enabled"] = false
                switch try decision(old) {
                case .generic(let reason): precondition(reason == "muted")
                default: fatalError("old snapshot lost its mute policy")
                }
              }
            }
            """
        )
        with tempfile.TemporaryDirectory(prefix="nse-policy-compat-") as tmp:
            swift = pathlib.Path(tmp) / "PolicyCompatibility.swift"
            binary = pathlib.Path(tmp) / "policy-compat"
            swift.write_text("import CryptoKit\nimport Foundation\n" + policy + harness, encoding="utf-8")
            compile_result = subprocess.run(
                ["swiftc", "-parse-as-library", str(swift), "-o", str(binary)],
                capture_output=True,
                text=True,
            )
            self.assertEqual(compile_result.returncode, 0, compile_result.stderr)
            run_result = subprocess.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(run_result.returncode, 0, run_result.stderr)


if __name__ == "__main__":
    unittest.main()
