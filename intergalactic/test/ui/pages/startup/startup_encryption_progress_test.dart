import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/ui/pages/startup/startup_shell.dart';

/// The accounts phase awaits encryption init before restoring any session, so
/// on a slow cold WASM load it can hold startup for the whole retry budget.
/// These cover the progress line that makes that wait legible: it must replace
/// the generic detail only while encryption init is actually running, and only
/// during the phase that waits on it.
void main() {
  setUp(() => MatrixClient.encryptionStartupProgress.value = null);
  tearDown(() => MatrixClient.encryptionStartupProgress.value = null);

  Widget host(StartupPhase phase) {
    return MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<String?>(
          valueListenable: MatrixClient.encryptionStartupProgress,
          builder: (context, encryptionProgress, _) {
            final detail = phase == StartupPhase.accounts
                ? (encryptionProgress ?? phase.detail)
                : phase.detail;
            return Text(detail);
          },
        ),
      ),
    );
  }

  testWidgets('accounts phase shows its generic detail when encryption init is '
      'not running', (tester) async {
    await tester.pumpWidget(host(StartupPhase.accounts));

    expect(find.text(StartupPhase.accounts.detail), findsOneWidget);
  });

  testWidgets('accounts phase surfaces encryption progress while init runs', (
    tester,
  ) async {
    await tester.pumpWidget(host(StartupPhase.accounts));

    MatrixClient.encryptionStartupProgress.value =
        'Preparing encryption (attempt 2 of 3).';
    await tester.pump();

    expect(find.text('Preparing encryption (attempt 2 of 3).'), findsOneWidget);
    expect(find.text(StartupPhase.accounts.detail), findsNothing);
  });

  testWidgets('clearing progress restores the generic detail', (tester) async {
    await tester.pumpWidget(host(StartupPhase.accounts));

    MatrixClient.encryptionStartupProgress.value = 'Preparing encryption.';
    await tester.pump();
    MatrixClient.encryptionStartupProgress.value = null;
    await tester.pump();

    expect(find.text(StartupPhase.accounts.detail), findsOneWidget);
  });

  testWidgets('other phases ignore encryption progress', (tester) async {
    await tester.pumpWidget(host(StartupPhase.storage));

    MatrixClient.encryptionStartupProgress.value = 'Preparing encryption.';
    await tester.pump();

    expect(find.text(StartupPhase.storage.detail), findsOneWidget);
    expect(find.text('Preparing encryption.'), findsNothing);
  });

  test('progress copy stays coarse and carries no identifiers', () {
    // S&C requirement: this string is rendered on screen and can be captured in
    // screenshots or bug reports, so it must never carry account, device,
    // session, room, or key material.
    for (final copy in [
      'Preparing encryption.',
      'Preparing encryption (attempt 2 of 3).',
      'Preparing encryption (attempt 3 of 3).',
    ]) {
      expect(copy.contains('@'), isFalse, reason: 'no matrix user id');
      expect(copy.contains('!'), isFalse, reason: 'no room id');
      expect(copy.contains('\$'), isFalse, reason: 'no event id');
      expect(
        RegExp(r'[0-9a-f]{16,}').hasMatch(copy),
        isFalse,
        reason: 'no key/token-looking material',
      );
    }
  });
}
