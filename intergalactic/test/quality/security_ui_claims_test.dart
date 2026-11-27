import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/pages/settings/settings_status_components.dart';

import '../../../tools/quality/security_ui_claims.dart';

void main() {
  const path = 'intergalactic/lib/ui/example.dart';

  Map<String, dynamic> claim({
    String text = 'Only you can read messages.',
    String kind = 'property',
    String evidenceStatus = 'supported',
    List<Map<String, Object>>? topics,
  }) => {
    'id': 'example',
    'surface': {'path': path, 'anchor': 'Example.build'},
    'displayedText': text,
    'kind': kind,
    'scope': {
      'platforms': ['all'],
      'data': ['messages'],
    },
    'assertion': 'Example assertion',
    'excludes': 'No call-media implication',
    'evidence': {
      'status': evidenceStatus,
      'paths': ['intergalactic/lib/client/example.dart'],
      'symbols': ['example'],
      'tests': ['intergalactic/test/example_test.dart'],
    },
    'reviewStatus': 'pending_sc_review',
    'reviewedAt': '2026-09-27',
    'reviewedAtCommit': '9cc5c950',
    'reviewDue': '2026-12-26',
    'invalidationPaths': ['intergalactic/lib/client/example.dart'],
    if (kind == 'completeness') ...{
      'completeAsOf': '2026-09-27',
      'requiredTopics':
          topics ??
          [
            {
              'name': 'call-media',
              'allOf': ['Calls', 'not end-to-end encrypted'],
            },
          ],
    },
  };

  AuditReport run(
    List<UiLiteral> literals, {
    List<Map<String, dynamic>> claims = const [],
    List<Map<String, dynamic>> exclusions = const [],
    Set<String> changed = const {},
    bool baseline = true,
  }) => auditClaims(
    literals: literals,
    registry: {'schemaVersion': 1, 'claims': claims, 'exclusions': exclusions},
    changedPaths: changed,
    baselineAvailable: baseline,
    trackedPath: (_) => true,
    today: DateTime(2026, 9, 27),
  );

  test(
    'parses joined strings and interpolation, not identifiers or comments',
    () {
      final literals = scanDartSource(path, '''
class Example {
  void build(String name) {
    final SafeArea = 1;
    // Only you can read comments.
    final value = 'Only you ' 'can read \$name messages.';
  }
}
''');
      expect(literals, hasLength(1));
      expect(literals.single.anchor, 'Example.build');
      expect(literals.single.text, 'Only you can read {name} messages.');
      expect(
        run(literals).findings.map((f) => f.code),
        contains('unregistered_claim'),
      );
    },
  );

  test('ARB parser reads values and skips metadata', () {
    final literals = scanArbContent(englishArbPath, '''{
      "secureClaim": "Only you can read messages.",
      "@secureClaim": {"description": "developer metadata"}
    }''');
    expect(literals, hasLength(1));
    expect(literals.single.anchor, 'secureClaim');
  });

  test('direct-preview disclosures match UI, English ARB, and registry', () {
    const uiSource =
        'intergalactic/lib/ui/pages/settings/categories/app/general_settings_page.dart';
    final uiLiterals = scanDartSource(
      uiSource,
      File(uiSource.substring('intergalactic/'.length)).readAsStringSync(),
    );
    final arbLiterals = scanArbContent(
      englishArbPath,
      File('assets/l10n/intl_en.arb').readAsStringSync(),
    );
    final registry =
        jsonDecode(
              File(
                '../tools/quality/security-ui-claims.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final claims = (registry['claims'] as List).cast<Map<String, dynamic>>();

    for (final (key, idPrefix) in [
      ('labelDirectPreviewFallbackE2EEDescription', 'preview-e2ee-direct'),
      (
        'labelDirectPreviewFallbackUnencryptedDescription',
        'preview-plain-direct',
      ),
    ]) {
      final uiText = uiLiterals
          .singleWhere(
            (literal) => literal.anchor == 'GeneralSettingsPageState.$key',
          )
          .text;
      final arbText = arbLiterals
          .singleWhere((literal) => literal.anchor == key)
          .text;
      expect(uiText, arbText);
      expect(
        claims.singleWhere(
          (claim) => claim['id'] == '$idPrefix-ui',
        )['displayedText'],
        uiText,
      );
      expect(
        claims.singleWhere(
          (claim) => claim['id'] == '$idPrefix-arb',
        )['displayedText'],
        arbText,
      );
      expect(uiText, contains('first tries a configured preview service'));
      expect(uiText, contains('then may try your homeserver'));
      expect(uiText, contains('may fetch from TikTok, Instagram, or Reddit'));
      expect(uiText, contains('may still fetch a provider site icon'));
      expect(uiText, isNot(contains('not an additional one')));
      expect(uiText, isNot(contains('second party')));
    }
    final encrypted = arbLiterals
        .singleWhere(
          (literal) =>
              literal.anchor == 'labelDirectPreviewFallbackE2EEDescription',
        )
        .text;
    expect(
      encrypted,
      contains('service, homeserver, and link site may each receive the URL'),
    );
  });

  test('crypto startup warning and non-claim classifications stay aligned', () {
    final source = File(
      'lib/client/matrix/matrix_client.dart',
    ).readAsStringSync();
    final arb =
        jsonDecode(File('assets/l10n/intl_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    final registry =
        jsonDecode(
              File(
                '../tools/quality/security-ui-claims.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final claims = (registry['claims'] as List).cast<Map<String, dynamic>>();
    final exclusions = (registry['exclusions'] as List)
        .cast<Map<String, dynamic>>();

    const warning =
        'Encryption could not be initialized for this session. '
        'End-to-end encrypted messages will not be available until this is resolved.';
    expect(
      source,
      contains('Encryption could not be initialized for this session.'),
    );
    expect(
      source,
      contains(
        'End-to-end encrypted messages will not be available until this is resolved.',
      ),
    );
    expect(arb['matrixClientVodozemacMissingMessage'], warning);
    expect(
      claims.singleWhere(
        (entry) => entry['id'] == 'vodozemac-missing-e2ee-unavailable',
      )['displayedText'],
      warning,
    );
    expect(
      source,
      isNot(contains('vodozemac is not installed or was not found')),
    );

    for (final id in [
      'secure-session-progress-ui',
      'secure-session-progress-arb',
      'olm-missing-e2ee-unavailable',
    ]) {
      expect(claims.where((entry) => entry['id'] == id), isEmpty);
    }
    expect(
      RegExp(r'\bmatrixClientOlmMissingMessage\b').allMatches(source),
      hasLength(2), // Getter declaration and Intl name, no call site.
    );
    final otherLibReferences = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (file) =>
              file.path.endsWith('.dart') &&
              !file.path.endsWith('matrix_client.dart') &&
              !file.path.split(Platform.pathSeparator).contains('generated') &&
              file.readAsStringSync().contains('matrixClientOlmMissingMessage'),
        );
    expect(otherLibReferences, isEmpty);
    for (final (path, anchor, displayedText) in [
      (
        'intergalactic/lib/ui/pages/login/post_login_matrix_recovery_dialog.dart',
        '_PostLoginMatrixRecoveryDialogState.labelPreparingSecureSession',
        'Preparing secure session',
      ),
      (
        'intergalactic/assets/l10n/intl_en.arb',
        'labelPreparingSecureSession',
        'Preparing secure session',
      ),
      (
        'intergalactic/assets/l10n/intl_en.arb',
        'matrixClientOlmMissingMessage',
        'libolm is not installed or was not found. End to End Encryption will not be available until this is resolved',
      ),
    ]) {
      expect(
        exclusions.where((entry) {
          final surface = entry['surface'] as Map<String, dynamic>;
          return surface['path'] == path &&
              surface['anchor'] == anchor &&
              entry['displayedText'] == displayedText;
        }),
        hasLength(1),
      );
    }
  });

  test('does not treat diagnostic log or search keywords as UI copy', () {
    final literals = scanDartSource(path, '''
class Example {
  void build() {
    Log.w('Only you can read logs.');
    FaqEntry(keywords: ['e2ee', 'can see messages'],
      searchKeywords: ['e2ee'],
      answer: ['Calls are not end-to-end encrypted.']);
  }
}
''');
    expect(
      literals.map((l) => l.text),
      contains('Calls are not end-to-end encrypted.'),
    );
    expect(
      literals.map((l) => l.text),
      isNot(contains('Only you can read logs.')),
    );
    expect(literals.map((l) => l.text), isNot(contains('e2ee')));
  });

  test('planted unregistered assertion is reported', () {
    final report = run([
      const UiLiteral(
        path,
        'Example.build',
        'Only you can read messages.',
        'dart',
      ),
    ]);
    expect(report.findings.map((f) => f.code), contains('unregistered_claim'));
  });

  test('removed call-media assurances are planted positive controls', () {
    for (final falseClaim in [
      'This room is encrypted, your call is secure and private.',
      'Encrypted calls are still under development.',
      'Sorry, End-to-end encrypted voice rooms are not yet supported.',
    ]) {
      final literals = scanDartSource(
        path,
        "class Example { void build() { Text('$falseClaim'); } }",
      );
      expect(
        run(literals).findings.map((f) => f.code),
        contains('unregistered_claim'),
        reason: falseClaim,
      );
    }
  });

  test('changed registered wording is reported in both directions', () {
    final report = run(
      [
        const UiLiteral(
          path,
          'Example.build',
          'Only participants can read messages.',
          'dart',
        ),
      ],
      claims: [claim()],
    );
    expect(
      report.findings.map((f) => f.code),
      containsAll(['changed_claim', 'unregistered_claim']),
    );
  });

  test('removing either status-chip layout loses both registered labels', () {
    const statusPath =
        'intergalactic/lib/ui/pages/settings/categories/account/security/matrix/matrix_security_tab.dart';
    const compactPair =
        'compactLabel: status.encryptionAvailable ? "E2EE ready" : "E2EE off",';
    final source = File(
      statusPath.substring('intergalactic/'.length),
    ).readAsStringSync();
    final occurrences = RegExp(
      RegExp.escape(compactPair),
    ).allMatches(source).toList();
    expect(occurrences, hasLength(2));

    final claims = <Map<String, dynamic>>[
      for (final text in ['E2EE ready', 'E2EE off'])
        claim(text: text)
          ..['id'] = text
          ..['surface'] = {
            'path': statusPath,
            'anchor': '_MatrixSecurityTabState._statusChips',
          }
          ..['expectedOccurrences'] = 2,
    ];
    AuditReport audit(String content) =>
        run(scanDartSource(statusPath, content), claims: claims);

    expect(
      audit(source).findings.where((f) => f.code == 'occurrence_mismatch'),
      isEmpty,
    );
    for (final removed in occurrences) {
      final changed = source.replaceRange(removed.start, removed.end, '');
      expect(
        audit(changed).findings
            .where((f) => f.code == 'occurrence_mismatch')
            .map((f) => f.subject),
        containsAll(['E2EE ready', 'E2EE off']),
      );
    }
  });

  test(
    'removed completeness clause is detected even with remaining E2EE text',
    () {
      final text = 'Messages are end-to-end encrypted.';
      final report = run(
        [UiLiteral(path, 'Example.build', text, 'dart')],
        claims: [claim(text: text, kind: 'completeness')],
      );
      expect(report.findings.map((f) => f.code), contains('missing_topic'));
    },
  );

  test('completeness claim retains unresolved external coverage gap', () {
    final entry = claim(
      text:
          'Messages are end-to-end encrypted. Calls are not end-to-end encrypted.',
      kind: 'completeness',
      evidenceStatus: 'missing',
    )..['watchCoverageGaps'] = ['Bridge policy is external'];
    entry['affirmativeProtection'] = true;
    final report = run(
      [
        UiLiteral(
          path,
          'Example.build',
          entry['displayedText'] as String,
          'dart',
        ),
      ],
      claims: [entry],
    );
    expect(
      report.findings.map((f) => f.code),
      containsAll(['coverage_gap', 'missing_proof']),
    );
  });

  test('changed watched implementation invalidates unchanged copy', () {
    final report = run(
      [
        const UiLiteral(
          path,
          'Example.build',
          'Only you can read messages.',
          'dart',
        ),
      ],
      claims: [claim()],
      changed: {'intergalactic/lib/client/example.dart'},
    );
    expect(report.findings.map((f) => f.code), contains('invalidated'));
  });

  test('unavailable reviewed commit is indeterminate, not silently green', () {
    final report = run(
      [
        const UiLiteral(
          path,
          'Example.build',
          'Only you can read messages.',
          'dart',
        ),
      ],
      claims: [claim()],
      baseline: false,
    );
    expect(
      report.findings.map((f) => f.code),
      contains('unknown_invalidation'),
    );
  });

  test('affirmative claim with missing proof is unresolved', () {
    final report = run(
      [
        const UiLiteral(
          path,
          'Example.build',
          'Only you can read messages.',
          'dart',
        ),
      ],
      claims: [claim(evidenceStatus: 'missing')],
    );
    expect(report.findings.map((f) => f.code), contains('missing_proof'));
  });

  test('exact anchored exclusion does not hide another surface', () {
    final report = run(
      [
        const UiLiteral(
          path,
          'Example.build',
          'Only you can read messages.',
          'dart',
        ),
        const UiLiteral(
          path,
          'Other.build',
          'Only you can read messages.',
          'dart',
        ),
      ],
      exclusions: [
        {
          'surface': {'path': path, 'anchor': 'Example.build'},
          'displayedText': 'Only you can read messages.',
          'reason': 'Planted non-claim',
          'reviewedAt': '2026-09-27',
          'expires': '2026-12-26',
        },
      ],
    );
    expect(
      report.findings.where((f) => f.code == 'unregistered_claim'),
      hasLength(1),
    );
  });

  test('expired exact exclusion stays visible for review', () {
    final report = run(
      [
        const UiLiteral(
          path,
          'Example.build',
          'Privacy and Encryption',
          'dart',
        ),
      ],
      exclusions: [
        {
          'surface': {'path': path, 'anchor': 'Example.build'},
          'displayedText': 'Privacy and Encryption',
          'reason': 'Title only',
          'reviewedAt': '2026-01-01',
          'reviewStatus': 'pending_sc_review',
          'expires': '2026-01-02',
        },
      ],
    );
    expect(
      report.findings.map((f) => f.code),
      containsAll(['expired_exclusion', 'pending_exclusion_review']),
    );
  });

  test('standalone privacy title is discovery only', () {
    final report = run([
      const UiLiteral(path, 'Example.build', 'Privacy and Encryption', 'dart'),
    ]);
    expect(report.highConfidence, isEmpty);
    expect(report.discovery, hasLength(1));
  });

  testWidgets('status chip compact labels use width, not platform', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    Future<void> pumpChip(String full, String compact) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SettingsStatusChip(
              icon: Icons.lock_outline,
              label: full,
              compactLabel: compact,
            ),
          ),
        ),
      );
    }

    for (final labels in [
      ('Encryption ready', 'E2EE ready'),
      ('Encryption unavailable', 'E2EE off'),
    ]) {
      await pumpChip(labels.$1, labels.$2);
      expect(find.text(labels.$2), findsOneWidget);
      expect(find.text(labels.$1), findsNothing);

      tester.view.physicalSize = const Size(500, 800);
      await tester.pump();
      expect(find.text(labels.$1), findsOneWidget);
      expect(find.text(labels.$2), findsNothing);

      tester.view.physicalSize = const Size(400, 800);
    }
  });
}
