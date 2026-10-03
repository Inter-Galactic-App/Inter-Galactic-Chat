import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural guards for two startup fixes whose behaviour a test process
/// cannot reach.
///
/// `single_instance_test.dart` covers everything
/// `debugClaimOrNotifyExistingForTesting` can reach: it injects the four
/// callbacks, so it never sees which socket path or which lock file the real
/// implementation derives, and it never enters `_tryConnectToMainInstance`.
///
/// The two behaviours below sit outside that reach for reasons no harness
/// removes:
///
///  * The dev-instance suffix is read from `Platform.environment`, which Dart
///    fixes at process start and offers no override for, and both paths are
///    Windows-only. A behavioural test would have to launch a second process
///    with `INTERGALACTIC_DEV_INSTANCE_ID` set, bind a real named pipe, and
///    take a real exclusive file lock.
///  * The stale-socket delete is inside `if (PlatformUtils.isLinux)`, which is
///    `Platform.isLinux` on the host. On the Windows and macOS machines that
///    run this suite that branch cannot execute, so a behavioural test of it
///    would pass by never running - the exact shape of a green check whose
///    scope is wrong.
///
/// So this file pins the source structure instead, in the style of
/// `android_notification_preview_plugin_contract_test.dart`. It proves the two
/// call sites still exist and still say what the fix made them say; it does not
/// prove the runtime behaviour. Every lookup below asserts it found something
/// before asserting anything about it, so a rename cannot turn this file into a
/// set of checks that match nothing and pass.
void main() {
  final source = File('lib/single_instance_io.dart').readAsStringSync();

  /// The body of a member, located by its declaration and brace-matched from
  /// the `{` that opens it.
  ///
  /// [bodyOpenMarker] is needed because a member whose named parameters are
  /// declared in a `{...}` group opens a brace before its body does, and
  /// matching that one would hand back the parameter list as the body.
  ({String body, int start, int end}) memberBody(
    String declaration, {
    String bodyOpenMarker = ') async {',
  }) {
    final declarationStart = source.indexOf(declaration);
    expect(
      declarationStart,
      isNonNegative,
      reason:
          'single_instance_io.dart no longer declares `$declaration`, so every '
          'assertion about its body below is checking nothing.',
    );

    final markerStart = source.indexOf(bodyOpenMarker, declarationStart);
    expect(
      markerStart,
      isNonNegative,
      reason: 'could not find the body of `$declaration`.',
    );

    final open = markerStart + bodyOpenMarker.length - 1;
    var depth = 0;
    var index = open;
    while (index < source.length) {
      final character = source[index];
      if (character == '{') {
        depth += 1;
      } else if (character == '}') {
        depth -= 1;
        if (depth == 0) {
          break;
        }
      }
      index += 1;
    }

    expect(
      depth,
      0,
      reason: 'the body of `$declaration` has unbalanced braces.',
    );

    final body = source.substring(open + 1, index);
    expect(
      body.trim(),
      isNotEmpty,
      reason: 'the body of `$declaration` came back empty.',
    );

    return (body: body, start: open, end: index);
  }

  group('SingleInstance dev instance paths', () {
    test('the startup lock is separated per dev instance like the socket', () {
      final socket = memberBody('static Future<String> _socketPath');
      final lock = memberBody(
        'static Future<RandomAccessFile?> _tryAcquireStartupLock',
      );

      expect(socket.body, contains('_devInstanceSuffix()'));
      expect(
        lock.body,
        contains('_devInstanceSuffix()'),
        reason:
            'two dev instances that share one startup lock cannot both own a '
            'socket: the loser waits on a socket path no process ever binds, '
            'and the wait ends in a StateError that is fatal at launch.',
      );
    });

    test('one helper decides whether a dev instance is separated', () {
      final suffix = memberBody(
        'static String _devInstanceSuffix',
        bodyOpenMarker: '() {',
      );

      expect(
        suffix.body,
        contains('_devInstanceIdEnvironment'),
        reason: 'the shared helper no longer reads the dev instance id.',
      );

      const declaration = 'static const String _devInstanceIdEnvironment';
      final declarationStart = source.indexOf(declaration);
      expect(declarationStart, isNonNegative);
      final declarationEnd = source.indexOf(';', declarationStart);
      expect(declarationEnd, isNonNegative);

      final pattern = RegExp(r'_devInstanceIdEnvironment\b');
      final references = pattern.allMatches(source).toList();
      expect(
        references,
        isNotEmpty,
        reason: 'nothing reads the dev instance id, so nothing is separated.',
      );

      for (final reference in references) {
        final isDeclaration =
            reference.start >= declarationStart &&
            reference.start < declarationEnd;
        final isInsideSharedHelper =
            reference.start > suffix.start && reference.start < suffix.end;
        expect(
          isDeclaration || isInsideSharedHelper,
          isTrue,
          reason:
              'a second place derives the dev instance from the environment. '
              'One derivation is what keeps the socket and the startup lock '
              'from separating one instance without separating the other.',
        );
      }
    });
  });

  group('SingleInstance stale socket removal', () {
    test('waiting for the owner never deletes the socket it waits on', () {
      final wait = memberBody(
        'static Future<bool> _waitForMainInstance(String path)',
      );

      expect(
        wait.body,
        contains('removeStaleSocket: false'),
        reason:
            'the wait only runs while another process holds the startup lock, '
            'so a refused connection means the owner is not accepting yet. '
            'Deleting the socket there unbinds the live owner.',
      );
    });

    test('the socket is only deleted when the caller asked for it', () {
      final connect = memberBody(
        'static Future<bool> _tryConnectToMainInstance(',
      );

      expect(
        connect.body,
        contains('File(path).delete()'),
        reason:
            'the stale-socket recovery is gone, so the flag that gates it '
            'guards nothing.',
      );
      expect(
        connect.body,
        contains('if (removeStaleSocket)'),
        reason:
            'an ungated delete makes `removeStaleSocket: false` decorative: '
            'the polling path would still delete the socket of a live owner.',
      );
    });

    test('the connect the claim path retries with can delete', () {
      // `single_instance_test.dart` proves the re-claim path runs one more
      // `tryConnect` before `becomeOwner`. It cannot prove that connect is one
      // that removes a dead socket: the seam injects the callback, so the
      // whole point of the retry - that `bind` no longer meets a socket file
      // its owner never unlinked - lives in this wiring and nowhere the
      // harness can see.
      final start = memberBody(
        'static Future<bool> startOrConnectToMainInstance(List<String> args)',
      );

      // DELIBERATELY STRICT, and CodeRabbit round 4 asked for it to be
      // loosened to also accept an explicit `removeStaleSocket: true`.
      // Rejected. This expression and the `removeStaleSocket = true` default
      // asserted below are a PAIR: together they prove the call site passes no
      // flag and the default supplies removal. Accepting a second shape would
      // retire the pairing and leave two forms to keep in step, in exchange
      // for tolerating a rewrite nobody has proposed.
      //
      // A structural test that is too strict fails loudly on a legitimate
      // change and says what to check - the `reason` below does exactly that.
      // One that is too loose passes on an illegitimate one. Those risks are
      // not symmetric, and this file exists for the second kind.
      final wiring = RegExp(
        r'tryConnect:\s*\(\)\s*=>\s*_tryConnectToMainInstance\(\s*path\s*,?\s*\)',
      );
      expect(
        wiring.hasMatch(start.body),
        isTrue,
        reason:
            'the injected connect is no longer plain '
            '`_tryConnectToMainInstance(path)`. If it grew arguments, check '
            'whether it still removes a stale socket - the re-claim retry is '
            'the only step that can, and it relies on the default here.',
      );

      // The default lives in the parameter list, which is outside the body
      // `memberBody` hands back, so this one is matched against the source.
      expect(
        RegExp(r'bool\s+removeStaleSocket\s*=\s*true').hasMatch(source),
        isTrue,
        reason:
            'removal is no longer the default, so the call site above opts '
            'out of it by saying nothing, and the re-claim retry clears '
            'nothing.',
      );
    });

    test('the delete cannot escape as a fatal startup error', () {
      final connect = memberBody(
        'static Future<bool> _tryConnectToMainInstance(',
      );

      expect(
        RegExp(
          r'try\s*\{\s*await\s+File\(path\)\.delete\(\);\s*\}\s*'
          r'on\s+FileSystemException',
        ).hasMatch(connect.body),
        isTrue,
        reason:
            'the delete sits INSIDE a catch block, and a throw in a catch '
            'block is not caught by it. An unguarded PathNotFoundException - '
            'which two processes racing the same stale socket produce, and so '
            'does a path this process may not remove - escapes '
            'startOrConnectToMainInstance and reaches the fatal-error handler '
            'in appMain, so the app refuses to start.',
      );
    });

    // The test above proves a handler is THERE. A handler that logs and then
    // rethrows - or one that maps the FileSystemException to a StateError
    // "because the socket path is unusable" - matches that regex exactly and
    // escapes `startOrConnectToMainInstance` exactly as an unguarded delete
    // did. So the handler's body is the thing to assert on.
    //
    // Why this is still a source assertion rather than a behavioural one: the
    // delete sits inside `if (PlatformUtils.isLinux)`, and `_tryConnect...`
    // has no injection point for the delete, the platform, or `connect`. A
    // behavioural test would need errno 111 from a real AF_UNIX socket on
    // Linux, and this suite runs on Windows and macOS, where the branch cannot
    // execute - it would pass by never running. Strengthening the structural
    // check is what is available without changing lib.
    test('the handler swallows the delete failure rather than re-raising it', () {
      final connect = memberBody(
        'static Future<bool> _tryConnectToMainInstance(',
      );

      final deleteAt = connect.body.indexOf('File(path).delete()');
      expect(
        deleteAt,
        isNonNegative,
        reason: 'the stale-socket delete is gone, so this checks nothing.',
      );
      final handlerAt = connect.body.indexOf(
        'on FileSystemException',
        deleteAt,
      );
      expect(
        handlerAt,
        isNonNegative,
        reason:
            'the delete is no longer guarded by a FileSystemException '
            'handler.',
      );
      final open = connect.body.indexOf('{', handlerAt);
      expect(open, isNonNegative, reason: 'the handler has no body.');

      var depth = 0;
      var index = open;
      while (index < connect.body.length) {
        final character = connect.body[index];
        if (character == '{') {
          depth += 1;
        } else if (character == '}') {
          depth -= 1;
          if (depth == 0) {
            break;
          }
        }
        index += 1;
      }
      expect(depth, 0, reason: 'the handler body has unbalanced braces.');
      final handler = connect.body.substring(open + 1, index);
      expect(
        handler.trim(),
        isNotEmpty,
        reason:
            'the handler body came back empty, so nothing below is being '
            'checked.',
      );

      // The handler's own comment explains why it must not throw, so a raw
      // search for `throw` matches the explanation rather than a statement.
      final handlerCode = handler.replaceAll(RegExp(r'//[^\n]*'), '');
      expect(
        handlerCode.trim(),
        isNotEmpty,
        reason: 'the handler is comments only, so it does not log either.',
      );

      expect(
        handlerCode,
        isNot(contains('rethrow')),
        reason:
            'a rethrow here reaches the fatal-error handler in appMain, which '
            'is the failure the guard was added to stop: the process holds the '
            'startup lock and is entitled to leave a socket it could not '
            'remove for bind() to complain about later.',
      );
      expect(
        RegExp(r'\bthrow\b').hasMatch(handlerCode),
        isFalse,
        reason:
            'raising anything else out of this handler ends the same way - '
            'a throw inside a catch block is not caught by that block.',
      );
      expect(
        RegExp(
          r'return\s+false;',
        ).hasMatch(connect.body.substring(index, connect.body.length)),
        isTrue,
        reason:
            'swallowing the delete failure and then falling through to a '
            'thrown result would report the startup as connected; the errno '
            '111 branch has to answer "no main instance" either way.',
      );
    });
  });
}
