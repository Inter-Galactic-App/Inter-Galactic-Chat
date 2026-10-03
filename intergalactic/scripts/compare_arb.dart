// Compares two ARB files by CONTENT rather than by bytes, and reports what
// differs in terms a person can act on.
//
// WHY THIS EXISTS RATHER THAN `git diff`. `extract_strings.dart` writes keys in
// the order it walks lib/, and that walk order is filesystem order, which is
// not the same on Windows and Linux. An ARB regenerated on Windows and one
// regenerated on the CI runner therefore differ by thousands of lines while
// being identical in content - every key present on both sides, just moved. A
// byte or line comparison reports that as a catastrophic difference and is
// useless as a gate. Key set, values and metadata are what actually matter.
//
// `@@last_modified` is ignored: extraction always rewrites it.
//
// Usage: dart run scripts/compare_arb.dart <expected.arb> <actual.arb>
// Exit 0 if the two are equivalent, 1 if not.

import 'dart:convert';
import 'dart:io';

const String _lastModified = '@@last_modified';

// Sets `exitCode` rather than returning one: Dart IGNORES a value returned
// from `main`, so an earlier version of this script printed every difference
// it found and still exited 0 - a check that reports failure and passes.
void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('usage: compare_arb.dart <expected.arb> <actual.arb>');
    exitCode = 2;
    return;
  }

  final expected = _load(args[0]);
  final actual = _load(args[1]);
  if (expected == null || actual == null) {
    exitCode = 2;
    return;
  }

  final expectedKeys = expected.keys.toSet();
  final actualKeys = actual.keys.toSet();

  final removed = expectedKeys.difference(actualKeys).toList()..sort();
  final added = actualKeys.difference(expectedKeys).toList()..sort();
  final changed =
      expectedKeys
          .intersection(actualKeys)
          .where((k) => !_deepEquals(expected[k], actual[k]))
          .toList()
        ..sort();

  if (removed.isEmpty && added.isEmpty && changed.isEmpty) {
    stdout.writeln(
      'ARB content matches: ${_messageCount(actual)} messages, order ignored.',
    );
    return;
  }

  // Report messages before their `@`-prefixed metadata: a person reads the
  // message list, and a metadata-only difference is a different (smaller)
  // problem worth seeing separately.
  _report('missing from the committed ARB', added);
  _report(
    'present in the committed ARB but no longer declared in lib',
    removed,
  );
  _report('different between the two', changed);
  exitCode = 1;
}

Map<String, dynamic>? _load(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('no such file: $path');
    return null;
  }
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, dynamic>) {
      stderr.writeln('not a JSON object: $path');
      return null;
    }
    return Map<String, dynamic>.of(decoded)..remove(_lastModified);
  } on FormatException catch (error) {
    stderr.writeln('could not parse $path: $error');
    return null;
  }
}

int _messageCount(Map<String, dynamic> arb) =>
    arb.keys.where((k) => !k.startsWith('@')).length;

void _report(String what, List<String> keys) {
  if (keys.isEmpty) return;
  final messages = keys.where((k) => !k.startsWith('@')).toList();
  final metadata = keys.where((k) => k.startsWith('@')).toList();
  stdout.writeln('${keys.length} key(s) $what:');
  for (final key in [...messages, ...metadata]) {
    stdout.writeln('  $key');
  }
}

bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (!_deepEquals(entry.value, b[entry.key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
