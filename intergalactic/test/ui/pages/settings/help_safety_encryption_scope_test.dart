import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/pages/settings/categories/help/help_safety_page.dart';

/// BUG-335 follow-up. The in-app privacy summary is the ONE place that tells a
/// user where end-to-end encryption stops, and it did not mention calls - so a
/// reader who came looking for exactly that left with the wrong answer, from the
/// text written to give them the right one.
///
/// This is a different defect shape from the three false claims removed on the
/// call surface: nothing here was false. It was an omission from an
/// enumeration, and an enumeration is read as complete because that is what an
/// enumeration is for. An omission cannot be caught by banning a wrong string,
/// which is what the call-surface tests do; it needs a REQUIRED one.
///
/// Deliberately asserts the FACT, not the sentence. Rewording the policy text
/// should not require touching this file; dropping calls from the scope
/// statement should.
void main() {
  String policyBody(String title) =>
      HelpPoliciesPage.policyBodiesForTesting[title] ?? '';

  group('the privacy summary states where encryption stops', () {
    test('it mentions calls at all', () {
      final body = policyBody('Privacy Policy').toLowerCase();

      expect(
        body,
        contains('call'),
        reason:
            'THE DEFECT: this enumerated what E2EE does not cover - metadata, '
            'push routing, backups, bridges, previews, search, diagnostics, '
            'integrations - and omitted calls entirely, which are not '
            'end-to-end encrypted at all.',
      );
    });

    test('it says calls are NOT end-to-end encrypted', () {
      // Mentioning calls is not enough: a sentence that mentions calls while
      // implying they are covered would pass the case above.
      final body = policyBody('Privacy Policy').toLowerCase();

      expect(
        body,
        contains('calls are not end-to-end encrypted'),
        reason:
            'the app configures no call-media E2EE on any path; saying so is '
            'the point of the clause',
      );
    });

    test('ARMING: the document it reads is the real one and is not empty', () {
      // Without this, a renamed title or an empty body would make both bans
      // above pass over nothing - the failure mode that let three false claims
      // live on the call surface for five months.
      final body = policyBody('Privacy Policy');

      expect(body.length, greaterThan(200));
      expect(body.toLowerCase(), contains('end-to-end encrypted messages'));
    });
  });
}
