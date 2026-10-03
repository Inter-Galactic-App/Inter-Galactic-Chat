// Report-only inventory of English UI security assertions. Not a CI gate.
// Run from intergalactic/: dart run ../tools/quality/security_ui_claims.dart
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/analysis/utilities.dart';

const registryPath = 'tools/quality/security-ui-claims.json';
const englishArbPath = 'intergalactic/assets/l10n/intl_en.arb';
const uiPath = 'intergalactic/lib/ui/';

final _space = RegExp(r'\s+');
final _highConfidence = <RegExp>[
  RegExp(r'\bE2EE\b', caseSensitive: false),
  RegExp(r'\bend[- ]to[- ]end encrypt\w*\b', caseSensitive: false),
  RegExp(r'\bsecure session\b', caseSensitive: false),
  RegExp(r'\byour call is secure\b', caseSensitive: false),
  RegExp(
    r'\bencrypted calls are still under development\b',
    caseSensitive: false,
  ),
  RegExp(r'\bend[- ]to[- ]end encrypted voice rooms\b', caseSensitive: false),
  RegExp(r'\bonly (?:you|participants) can\b', caseSensitive: false),
  RegExp(r'\b(?:cannot|can not) (?:read|access)\b', caseSensitive: false),
  RegExp(r'\bserver cannot\b', caseSensitive: false),
  RegExp(
    r'\b(?:confidential|anonymous|zero[- ]knowledge)\b',
    caseSensitive: false,
  ),
  RegExp(r'\bnever leaves\b', caseSensitive: false),
  RegExp(r'\bnever sent to\b', caseSensitive: false),
  RegExp(r'\bstored locally only\b', caseSensitive: false),
  RegExp(r'\bstays on (?:this |the )?device\b', caseSensitive: false),
  RegExp(r'\bnot (?:uploaded|stored|logged)\b', caseSensitive: false),
  RegExp(r'\b(?:permanently deleted|erased)\b', caseSensitive: false),
  RegExp(r'\bnot end[- ]to[- ]end\b', caseSensitive: false),
  RegExp(r'\bdoes not (?:protect|hide)\b', caseSensitive: false),
  RegExp(r'\bcan access\b', caseSensitive: false),
  RegExp(
    r"\b(?:can|can't|cannot|could|couldn't) see (?:your |the |that )?(?:links?|messages?|contents?|data|audio|video|metadata)\b",
    caseSensitive: false,
  ),
  RegExp(r'\bcan see (?:that )?your device requested\b', caseSensitive: false),
  RegExp(r'\bmay involve separate services\b', caseSensitive: false),
];
final _discovery = RegExp(
  r'\b(?:encrypt\w*|decrypt\w*|verified|privacy|safe|secure|private|protected)\b',
  caseSensitive: false,
);

String normalizedText(String text) => text.replaceAll(_space, ' ').trim();

class UiLiteral {
  const UiLiteral(this.path, this.anchor, this.text, this.source);
  final String path;
  final String anchor;
  final String text;
  final String source;

  String get identity => '$path::$anchor::$text';
  Map<String, String> toJson() => {
    'path': path,
    'anchor': anchor,
    'displayedText': text,
    'source': source,
  };
}

String _displayedString(StringLiteral node) {
  if (node is AdjacentStrings) {
    return node.strings.map(_displayedString).join();
  }
  if (node is StringInterpolation) {
    return node.elements.map((element) {
      if (element is InterpolationString) return element.value;
      if (element is InterpolationExpression) {
        return '{${element.expression.toSource()}}';
      }
      return '';
    }).join();
  }
  return node.stringValue ?? '';
}

String _anchor(AstNode node) {
  String? member;
  String? variable;
  String? owner;
  for (
    AstNode? current = node.parent;
    current != null;
    current = current.parent
  ) {
    if (member == null) {
      if (current is MethodDeclaration) member = current.name.lexeme;
      if (current is FunctionDeclaration) member = current.name.lexeme;
      if (current is ConstructorDeclaration) {
        member = current.name?.lexeme ?? 'constructor';
      }
    }
    if (variable == null && current is VariableDeclaration)
      variable = current.name.lexeme;
    if (variable == null && current is EnumConstantDeclaration)
      variable = current.name.lexeme;
    if (owner == null && current is ClassDeclaration)
      owner = current.name.lexeme;
    if (owner == null && current is EnumDeclaration)
      owner = current.name.lexeme;
  }
  return [
    if (owner != null) owner,
    member ?? variable ?? '<top-level>',
  ].join('.');
}

bool _isMetadataOrDirective(StringLiteral node) {
  for (AstNode? parent = node.parent; parent != null; parent = parent.parent) {
    if (parent is UriBasedDirective) return true;
    if (parent is NamedExpression &&
        {
          'desc',
          'name',
          'meaning',
          'examples',
          'keywords',
          'searchKeywords',
        }.contains(parent.name.label.name)) {
      return true;
    }
    if (parent is MethodInvocation && parent.target?.toSource() == 'Log') {
      return true;
    }
    if (parent is VariableDeclaration ||
        parent is MethodDeclaration ||
        parent is FunctionDeclaration) {
      break;
    }
  }
  return false;
}

class _LiteralVisitor extends RecursiveAstVisitor<void> {
  _LiteralVisitor(this.path);
  final String path;
  final literals = <UiLiteral>[];

  void _collect(StringLiteral node) {
    if (node.parent is! AdjacentStrings && !_isMetadataOrDirective(node)) {
      final value = normalizedText(_displayedString(node));
      if (value.isNotEmpty) {
        literals.add(UiLiteral(path, _anchor(node), value, 'dart'));
      }
    }
    node.visitChildren(this);
  }

  @override
  void visitAdjacentStrings(AdjacentStrings node) => _collect(node);

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) => _collect(node);

  @override
  void visitStringInterpolation(StringInterpolation node) => _collect(node);
}

List<UiLiteral> scanDartSource(String path, String source) {
  final result = parseString(
    content: source,
    path: path,
    throwIfDiagnostics: false,
  );
  final errors = result.errors.where(
    (e) => e.errorCode.errorSeverity.name == 'ERROR',
  );
  if (errors.isNotEmpty) {
    throw FormatException(
      'Dart parse failed for $path: ${errors.first.message}',
    );
  }
  final visitor = _LiteralVisitor(path);
  result.unit.accept(visitor);
  return visitor.literals;
}

List<UiLiteral> scanArbContent(String path, String content) {
  final values = jsonDecode(content) as Map<String, dynamic>;
  return [
    for (final entry in values.entries)
      if (!entry.key.startsWith('@') && entry.value is String)
        UiLiteral(
          path,
          entry.key,
          normalizedText(entry.value as String),
          'arb',
        ),
  ];
}

bool isHighConfidence(String text) =>
    _highConfidence.any((rule) => rule.hasMatch(text));
bool isDiscovery(String text) =>
    _discovery.hasMatch(text) && !isHighConfidence(text);

class AuditFinding {
  const AuditFinding(this.code, this.subject, this.detail);
  final String code;
  final String subject;
  final String detail;
  Map<String, String> toJson() => {
    'code': code,
    'subject': subject,
    'detail': detail,
  };
}

class AuditReport {
  const AuditReport(this.highConfidence, this.discovery, this.findings);
  final List<UiLiteral> highConfidence;
  final List<UiLiteral> discovery;
  final List<AuditFinding> findings;
  Map<String, Object> toJson() => {
    'mode': 'report-only',
    'highConfidenceCount': highConfidence.length,
    'discoveryCount': discovery.length,
    'findings': findings.map((f) => f.toJson()).toList(),
    'highConfidence': highConfidence.map((l) => l.toJson()).toList(),
    'discovery': discovery.map((l) => l.toJson()).toList(),
  };
}

bool _watched(String path, String rule) => rule.endsWith('/**')
    ? path.startsWith(rule.substring(0, rule.length - 2))
    : path == rule;

AuditReport auditClaims({
  required List<UiLiteral> literals,
  required Map<String, dynamic> registry,
  required Set<String> changedPaths,
  required bool baselineAvailable,
  required bool Function(String path) trackedPath,
  required DateTime today,
}) {
  if (registry['schemaVersion'] != 1)
    throw const FormatException('Unknown registry version');
  final findings = <AuditFinding>[];
  final unique = {for (final literal in literals) literal.identity: literal};
  final occurrenceCounts = <String, int>{};
  for (final literal in literals) {
    occurrenceCounts.update(
      literal.identity,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
  }
  final high = unique.values.where((l) => isHighConfidence(l.text)).toList();
  final discovery = unique.values.where((l) => isDiscovery(l.text)).toList();
  final entries = (registry['claims'] as List).cast<Map<String, dynamic>>();
  final exclusions = (registry['exclusions'] as List)
      .cast<Map<String, dynamic>>();
  final excluded = <String>{};
  final registered = <String>{};
  final ids = <String>{};

  for (final exclusion in exclusions) {
    final surface = exclusion['surface'] as Map<String, dynamic>;
    final identity =
        '${surface['path']}::${surface['anchor']}::${exclusion['displayedText']}';
    if (exclusion['reason'] == null ||
        exclusion['reviewedAt'] == null ||
        exclusion['expires'] == null) {
      findings.add(
        AuditFinding(
          'invalid_exclusion',
          identity,
          'Reason, review date, and expiry required',
        ),
      );
    }
    if (exclusion['reviewStatus'] != 'approved_by_sc') {
      findings.add(
        AuditFinding(
          'pending_exclusion_review',
          identity,
          'S&C has not approved this exact exclusion',
        ),
      );
    }
    final expiry = DateTime.tryParse('${exclusion['expires']}');
    if (expiry == null || today.isAfter(expiry)) {
      findings.add(
        AuditFinding(
          'expired_exclusion',
          identity,
          'Exclusion requires review',
        ),
      );
    }
    if (!unique.containsKey(identity)) {
      findings.add(
        AuditFinding(
          'stale_exclusion',
          identity,
          'Exact anchored literal no longer exists',
        ),
      );
    } else {
      excluded.add(identity);
    }
  }

  for (final claim in entries) {
    final id = '${claim['id']}';
    if (!ids.add(id)) {
      findings.add(
        AuditFinding('duplicate_id', id, 'Registry claim IDs must be unique'),
      );
    }
    if (!{'property', 'limitation', 'completeness'}.contains(claim['kind']) ||
        claim['scope'] is! Map ||
        claim['assertion'] is! String ||
        (claim['assertion'] as String).trim().isEmpty ||
        claim['excludes'] is! String ||
        (claim['excludes'] as String).trim().isEmpty) {
      findings.add(
        AuditFinding(
          'invalid_claim',
          id,
          'Kind, scope, assertion, and excludes are required',
        ),
      );
    }
    if (registry['reviewedAtCommit'] != null &&
        claim['reviewedAtCommit'] != registry['reviewedAtCommit']) {
      findings.add(
        AuditFinding(
          'baseline_mismatch',
          id,
          'Claim baseline differs from registry baseline',
        ),
      );
    }
    final surface = claim['surface'] as Map<String, dynamic>;
    final path = '${surface['path']}';
    final anchor = '${surface['anchor']}';
    final text = '${claim['displayedText']}';
    final identity = '$path::$anchor::$text';
    final anchorCandidates = unique.values.where(
      (l) => l.path == path && l.anchor == anchor,
    );
    if (!unique.containsKey(identity)) {
      findings.add(
        AuditFinding(
          anchorCandidates.isEmpty ? 'missing_claim' : 'changed_claim',
          '${claim['id']}',
          'Registered wording is absent at $path::$anchor',
        ),
      );
    } else {
      registered.add(identity);
    }
    final expectedOccurrences = claim['expectedOccurrences'];
    if (expectedOccurrences != null) {
      if (expectedOccurrences is! int || expectedOccurrences < 1) {
        findings.add(
          AuditFinding(
            'invalid_claim',
            id,
            'Expected occurrence count must be a positive integer',
          ),
        );
      } else if (occurrenceCounts[identity] != expectedOccurrences) {
        findings.add(
          AuditFinding(
            'occurrence_mismatch',
            id,
            'Expected $expectedOccurrences anchored occurrences; found ${occurrenceCounts[identity] ?? 0}',
          ),
        );
      }
    }
    if (claim['reviewStatus'] != 'approved_by_sc') {
      findings.add(
        AuditFinding(
          'pending_review',
          '${claim['id']}',
          'S&C baseline review has not approved this entry',
        ),
      );
    }
    final evidence = claim['evidence'] as Map<String, dynamic>?;
    final evidencePaths = ((evidence?['paths'] ?? []) as List).cast<String>();
    if ((claim['kind'] == 'property' ||
            claim['affirmativeProtection'] == true) &&
        evidence?['status'] != 'supported') {
      findings.add(
        AuditFinding(
          'missing_proof',
          '${claim['id']}',
          'Affirmative protection claim is unresolved',
        ),
      );
    }
    if (evidencePaths.isEmpty && evidence?['status'] != 'missing') {
      findings.add(
        AuditFinding(
          'missing_evidence_paths',
          '${claim['id']}',
          'No implementation evidence paths',
        ),
      );
    }
    for (final evidencePath in evidencePaths) {
      if (!trackedPath(evidencePath)) {
        findings.add(
          AuditFinding('untracked_evidence', '${claim['id']}', evidencePath),
        );
      }
    }
    for (final testPath
        in ((evidence?['tests'] ?? []) as List).cast<String>()) {
      if (!trackedPath(testPath)) {
        findings.add(AuditFinding('untracked_test', id, testPath));
      }
    }
    final watched = ((claim['invalidationPaths'] ?? []) as List).cast<String>();
    if (watched.isEmpty) {
      findings.add(
        AuditFinding(
          'missing_watch_paths',
          '${claim['id']}',
          'Claim-specific watch paths required',
        ),
      );
    }
    for (final rule in watched.where((rule) => !rule.endsWith('/**'))) {
      if (!trackedPath(rule)) {
        findings.add(AuditFinding('untracked_watch', id, rule));
      }
    }
    if (!baselineAvailable) {
      findings.add(
        AuditFinding(
          'unknown_invalidation',
          '${claim['id']}',
          'Reviewed commit unavailable',
        ),
      );
    } else if (changedPaths.any(
      (path) => watched.any((rule) => _watched(path, rule)),
    )) {
      findings.add(
        AuditFinding(
          'invalidated',
          '${claim['id']}',
          'Watched implementation path changed',
        ),
      );
    }
    final due = DateTime.tryParse('${claim['reviewDue']}');
    if (due == null || today.isAfter(due)) {
      findings.add(
        AuditFinding(
          'review_due',
          '${claim['id']}',
          'Review date absent or past',
        ),
      );
    }
    if (claim['kind'] == 'completeness') {
      for (final gap
          in ((claim['watchCoverageGaps'] ?? []) as List).cast<String>()) {
        findings.add(AuditFinding('coverage_gap', id, gap));
      }
      final completeAsOf = DateTime.tryParse('${claim['completeAsOf']}');
      if (completeAsOf == null ||
          due == null ||
          due.difference(completeAsOf).inDays > 90) {
        findings.add(
          AuditFinding(
            'incomplete_review',
            '${claim['id']}',
            'Substantive enumeration review and <=90 day due date required',
          ),
        );
      }
      final topics =
          (claim['requiredTopics'] as List?)?.cast<Map<String, dynamic>>() ??
          [];
      if (topics.isEmpty) {
        findings.add(
          AuditFinding(
            'missing_topics',
            '${claim['id']}',
            'Explicit content assertions required',
          ),
        );
      }
      final actual = unique[identity]?.text ?? '';
      for (final topic in topics) {
        final required = (topic['allOf'] as List).cast<String>();
        if (required.any(
          (phrase) => !actual.toLowerCase().contains(phrase.toLowerCase()),
        )) {
          findings.add(
            AuditFinding('missing_topic', '${claim['id']}', '${topic['name']}'),
          );
        }
      }
    }
  }
  for (final literal in high) {
    if (!registered.contains(literal.identity) &&
        !excluded.contains(literal.identity)) {
      findings.add(
        AuditFinding(
          'unregistered_claim',
          literal.identity,
          'High-confidence phrase has no reviewed registry entry',
        ),
      );
    }
  }
  return AuditReport(high, discovery, findings);
}

Future<Set<String>> _gitLines(String root, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: root);
  if (result.exitCode != 0)
    throw StateError('git ${args.first} failed: ${result.stderr}');
  return (result.stdout as String)
      .split(RegExp(r'\r?\n'))
      .where((s) => s.isNotEmpty)
      .toSet();
}

Future<void> main() async {
  final current = Directory.current;
  final root = Directory('${current.path}/intergalactic').existsSync()
      ? current
      : current.parent;
  final ui = Directory('${root.path}/$uiPath');
  final files =
      ui
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final literals = <UiLiteral>[
    for (final file in files)
      ...scanDartSource(
        file.path.substring(root.path.length + 1).replaceAll('\\', '/'),
        file.readAsStringSync(),
      ),
    ...scanArbContent(
      englishArbPath,
      File('${root.path}/$englishArbPath').readAsStringSync(),
    ),
  ];
  final registry =
      jsonDecode(File('${root.path}/$registryPath').readAsStringSync())
          as Map<String, dynamic>;
  final base = '${registry['reviewedAtCommit']}';
  final available =
      (await Process.run('git', [
        'cat-file',
        '-e',
        '$base^{commit}',
      ], workingDirectory: root.path)).exitCode ==
      0;
  final tracked = await _gitLines(root.path, ['ls-files']);
  final changed = <String>{};
  if (available) {
    changed.addAll(
      await _gitLines(root.path, ['diff', '--name-only', '$base..HEAD']),
    );
    changed.addAll(await _gitLines(root.path, ['diff', '--name-only', 'HEAD']));
    changed.addAll(
      await _gitLines(root.path, [
        'ls-files',
        '--others',
        '--exclude-standard',
      ]),
    );
  }
  final report = auditClaims(
    literals: literals,
    registry: registry,
    changedPaths: changed,
    baselineAvailable: available,
    trackedPath: tracked.contains,
    today: DateTime.now(),
  );
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report.toJson()));
  // Deliberately report-only: findings never decide the process exit status.
}
