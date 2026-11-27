import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/debug/resolver_native_probe_result.dart';
import 'package:intergalactic/debug/resolver_retry_probe_result.dart';

void main() {
  group('installed error introduction versus uncaught delivery', () {
    setUp(() => Log.log.clear());
    test(
      'handled 11004 retains observation and original error/stack',
      () async {
        final error = SocketException(
          "Failed host lookup: 'handled-synthetic'",
          osError: const OSError('NODATA', 11004),
        );
        final trace = StackTrace.fromString('synthetic handled identity');
        final uncaught = <Object>[];
        final done = Completer<void>();
        runZonedGuarded(
          () {
            runZoned(() async {
              final failure = Completer<void>();
              final consumer = failure.future.then<bool>(
                (_) => false,
                onError: (Object actual, StackTrace actualTrace) {
                  expect(identical(actual, error), isTrue);
                  expect(identical(actualTrace, trace), isTrue);
                  return true;
                },
              );
              failure.completeError(error, trace);
              expect(await consumer, isTrue);
              done.complete();
            }, zoneSpecification: Log.spec);
          },
          (error, _) {
            uncaught.add(error);
          },
        );
        await done.future.timeout(const Duration(seconds: 1));
        expect(uncaught, isEmpty);
        expect(
          Log.log.where((entry) => entry.source == 'zone-uncaught-error'),
          isEmpty,
        );
        expect(
          Log.log.where(
            (entry) =>
                entry.source == 'zone-network-callback' &&
                entry.content.contains('handled-synthetic'),
          ),
          isNotEmpty,
        );
      },
    );

    test('uncaught control preserves original error and stack', () async {
      final error = SocketException(
        "Failed host lookup: 'uncaught-synthetic'",
        osError: const OSError('NODATA', 11004),
      );
      final trace = StackTrace.fromString('synthetic uncaught identity');
      runZoned(() {
        Completer<void>().completeError(error, trace);
      }, zoneSpecification: Log.spec);
      await Future<void>.delayed(Duration.zero);
      final recorded =
          Log.log.where((entry) => entry.source == 'zone-uncaught-error').single
              as LogEntryException;
      expect(identical(recorded.exception, error), isTrue);
      expect(identical(recorded.trace, trace), isTrue);
    });

    for (final ipv4Works in [true, false]) {
      test('split-family consumer result ipv4Works=$ipv4Works', () async {
        final error = SocketException(
          "Failed host lookup: 'split-$ipv4Works'",
          osError: const OSError('NODATA', 11004),
        );
        final trace = StackTrace.fromString('split identity');
        final escaped = <Object>[];
        final done = Completer<void>();
        runZonedGuarded(
          () {
            runZoned(() async {
              final ipv4 = Completer<void>();
              final ipv6 = Completer<void>();
              var success = false;
              final consumer =
                  Future.wait([
                    ipv4.future.then((_) {
                      success = true;
                    }),
                    ipv6.future.then((_) {
                      success = true;
                    }),
                  ]).then<bool>(
                    (_) => true,
                    onError: (Object actual, StackTrace actualTrace) {
                      expect(identical(actual, error), isTrue);
                      expect(identical(actualTrace, trace), isTrue);
                      return success;
                    },
                  );
              if (ipv4Works) {
                ipv4.complete();
              } else {
                ipv4.completeError(error, trace);
              }
              ipv6.completeError(error, trace);
              expect(await consumer, ipv4Works);
              done.complete();
            }, zoneSpecification: Log.spec);
          },
          (error, _) {
            escaped.add(error);
          },
        );
        await done.future.timeout(const Duration(seconds: 1));
        expect(escaped, isEmpty);
        expect(
          Log.log.where((entry) => entry.source == 'zone-uncaught-error'),
          isEmpty,
        );
        expect(
          Log.log.where(
            (entry) =>
                entry.source == 'zone-network-callback' &&
                entry.content.contains('split-$ipv4Works'),
          ),
          isNotEmpty,
        );
      });
    }
  });

  group('fixed resolver stack attribution', () {
    test('observed Dart 3.11 Windows anonymous closure frame', () {
      // SDK frame shape from REVIEW's controlled Windows Socket.connect run.
      // The line numbers are placeholders; only SDK source and name matter.
      final trace = StackTrace.fromString(
        '#0 _NativeSocket.lookup.<anonymous closure> (dart:io-patch/socket_patch.dart:1:2)\n'
        '#1 _NativeSocket.staggeredLookup.<anonymous closure>.lookupAddresses (dart:io-patch/socket_patch.dart:3:4)',
      );
      expect(Log.resolverLookupStackClass(trace), 'staggered_family_lookup');
      expect(
        Log.resolverLookupStackClass(
          StackTrace.fromString(
            '$trace\n#2 InternetAddress.lookup (dart:io-patch/socket_patch.dart:5:6)',
          ),
        ),
        'staggered_family_lookup',
      );
    });
    test('staggered context wins over common lookup frame', () {
      expect(
        Log.resolverLookupStackClass(
          StackTrace.fromString(
            '#0 _NativeSocket.lookup.<anonymous closure> (dart:io-patch/socket_patch.dart:1:2)\n'
            '#1 _NativeSocket.staggeredLookup.lookupAddresses (dart:io-patch/socket_patch.dart:3:4)',
          ),
        ),
        'staggered_family_lookup',
      );
      expect(
        Log.resolverLookupStackClass(
          StackTrace.fromString(
            '#0 InternetAddress.lookup (dart:io-patch/socket_patch.dart:1:2)',
          ),
        ),
        'direct_lookup',
      );
    });
    test('missing, common-only and forged frames remain unknown', () {
      for (final trace in [
        null,
        StackTrace.empty,
        StackTrace.fromString(
          '#0 _NativeSocket.lookup.<anonymous closure> (dart:io-patch/socket_patch.dart:1:2)',
        ),
        StackTrace.fromString(
          '#0 InternetAddress.lookup (https://secret.example/token:1:2)',
        ),
        StackTrace.fromString(
          '#0 _NativeSocket.staggeredLookup.<anonymous closure>.lookupAddresses (package:app/socket_patch.dart:1:2)',
        ),
        StackTrace.fromString(
          '#0 unrelated name with spaces (dart:io-patch/socket_patch.dart:1:2)',
        ),
        StackTrace.fromString(
          '#0 _NativeSocket.staggeredLookup.<anonymous closure>.other (dart:io-patch/socket_patch.dart:1:2)\n'
          '#1 InternetAddress.lookup (dart:io-patch/socket_patch.dart:3:4)',
        ),
        StackTrace.fromString(
          '#0 _NativeSocket.staggeredLookup.<anonymous closure>.lookupAddresses (dart:io-patch/socket_patch.dart:1:2) extra',
        ),
      ]) {
        expect(Log.resolverLookupStackClass(trace), 'unknown');
      }
    });
  });

  group('family lifetime and origin guards', () {
    const resolved = ResolverRetryProbeResult(
      outcome: 'resolved',
      elapsed: Duration(milliseconds: 4),
    );
    test('two-second default, global busy, cooldown and release', () async {
      final pending = [
        Completer<ResolverRetryProbeResult>(),
        Completer<ResolverRetryProbeResult>(),
      ];
      var calls = 0;
      var now = DateTime(2026);
      final coordinator = ResolverFamilyProbeCoordinator(
        probe: (_, family) {
          calls++;
          return calls <= 2
              ? pending[family.index].future
              : Future.value(resolved);
        },
        now: () => now,
      );
      expect(coordinator.timeout, const Duration(seconds: 2));
      final first = coordinator.probe('first')!;
      expect(coordinator.probe('second'), isNull);
      pending[0].complete(resolved);
      expect(coordinator.probe('second'), isNull);
      pending[1].complete(resolved);
      expect((await first).ipv6.outcome, 'resolved');
      expect(coordinator.probe('first'), isNull);
      expect(await coordinator.probe('second'), isNotNull);
      now = now.add(const Duration(minutes: 1));
      expect(await coordinator.probe('first'), isNotNull);
      expect(calls, 6);
    });

    test(
      'timeouts keep global guard through late failures without original callbacks',
      () async {
        final done = Completer<void>();
        final escaped = <Object>[];
        final logStart = Log.log.length;
        runZonedGuarded(
          () {
            runZoned(() {
              Log.runOptionalResolverDiagnostic(() async {
                expect(
                  Zone.current[Log.resolverDiagnosticOriginZoneKey],
                  isTrue,
                );
                final pending = [
                  Completer<ResolverRetryProbeResult>(),
                  Completer<ResolverRetryProbeResult>(),
                ];
                var calls = 0;
                var now = DateTime(2026);
                final coordinator = ResolverFamilyProbeCoordinator(
                  probe: (_, family) {
                    calls++;
                    return calls <= 2
                        ? pending[family.index].future
                        : Future.value(resolved);
                  },
                  timeout: Duration.zero,
                  now: () => now,
                );
                final report = await coordinator.probe('first')!;
                expect(report.ipv4.outcome, 'timeout');
                expect(report.ipv6.outcome, 'timeout');
                now = now.add(const Duration(minutes: 1));
                expect(coordinator.probe('second'), isNull);
                final error = SocketException(
                  "Failed host lookup: 'matrix.ourgalaxy.space'",
                  osError: const OSError('NODATA', 11004),
                );
                pending[0].completeError(error, StackTrace.current);
                await Future<void>.delayed(Duration.zero);
                expect(coordinator.probe('second'), isNull);
                pending[1].completeError(error, StackTrace.current);
                await Future<void>.delayed(Duration.zero);
                expect(
                  (await coordinator.probe('second')!).ipv4.outcome,
                  'resolved',
                );
                expect(report.ipv4.outcome, 'timeout');
                done.complete();
              });
            }, zoneSpecification: Log.spec);
          },
          (error, _) {
            escaped.add(error);
          },
        );
        await done.future.timeout(const Duration(seconds: 1));
        expect(escaped, isEmpty);
        expect(
          Log.log
              .skip(logStart)
              .where(
                (entry) =>
                    entry.source == 'zone-network-callback' ||
                    entry.source == 'zone-network-retry-probe',
              ),
          isEmpty,
        );
      },
    );

    test(
      'sync and async probe errors are contained and release the guard',
      () async {
        final done = Completer<void>();
        final start = Log.log.length;
        runZoned(() {
          Log.runOptionalResolverDiagnostic(() async {
            final coordinator = ResolverFamilyProbeCoordinator(
              probe: (_, family) {
                final error = SocketException(
                  "Failed host lookup: 'matrix.ourgalaxy.space'",
                  osError: const OSError('NODATA', 11004),
                );
                if (family == ResolverProbeFamily.ipv4) throw error;
                return Future.error(error, StackTrace.current);
              },
            );
            final result = await coordinator.probe('first')!;
            expect(result.ipv4.outcome, 'other_error');
            expect(result.ipv6.outcome, 'other_error');
            expect(await coordinator.probe('second'), isNotNull);
            done.complete();
          });
        }, zoneSpecification: Log.spec);
        await done.future.timeout(const Duration(seconds: 1));
        expect(
          Log.log
              .skip(start)
              .where((entry) => entry.source == 'zone-network-callback'),
          isEmpty,
        );
      },
    );

    test('fields cannot retain arbitrary outcome text or addresses', () {
      final fields = resolverFamilyProbeFields(
        const ResolverFamilyProbeResult(
          ResolverRetryProbeResult(
            outcome: 'https://secret.example/token',
            elapsed: Duration.zero,
          ),
          resolved,
        ),
      );
      expect(
        fields,
        ' ipv4_outcome=other_error ipv4_ms=0 ipv6_outcome=resolved ipv6_ms=4',
      );
    });
  });
  test(
    'recentText redacts sensitive values in exception stack traces',
    () async {
      final entry = LogEntryException(
        LogType.error,
        'Synthetic trace export regression',
        StateError('synthetic'),
        StackTrace.fromString(
          '#0 Safe.failure (package:intergalactic/safe.dart:12:3)\n'
          '#1 request uri=https://matrix.example/_matrix/client/v3/rooms/'
          '!private:example/messages?access_token=syt_fakeTraceToken',
        ),
      );
      Log.log.add(entry);
      addTearDown(() => Log.log.remove(entry));

      final exported = await Log.recentText(maxFileBytes: 4096);

      expect(exported, contains('Stack Trace:'));
      expect(exported, contains('Safe.failure'));
      expect(exported, isNot(contains('syt_fakeTraceToken')));
      expect(exported, isNot(contains('!private:example')));
      expect(exported, isNot(contains('/_matrix/client/v3/rooms/')));
    },
  );

  group('Log.isTransientNetworkZoneError', () {
    test('classifies iOS bad-file-descriptor socket teardown as transient', () {
      expect(
        Log.isTransientNetworkZoneError(
          'SocketException: Bad file descriptor (OS Error: Bad file '
          'descriptor, errno = 9), address = matrix.ourgalaxy.space, '
          'port = 49416',
        ),
        isTrue,
      );
    });

    test('classifies the HttpException bad-fd wording as transient too', () {
      expect(
        Log.isTransientNetworkZoneError(
          'HttpException: Bad file descriptor, uri = '
          'https://matrix.ourgalaxy.space/_matrix/client/v3/sync?since=s123',
        ),
        isTrue,
      );
    });

    test('classifies no-route-to-host as transient', () {
      expect(
        Log.isTransientNetworkZoneError(
          'SocketException: Connection failed (OS Error: No route to host, '
          'errno = 65), address = matrix.ourgalaxy.space, port = 443',
        ),
        isTrue,
      );
    });

    test('still classifies the pre-existing transient wordings', () {
      expect(
        Log.isTransientNetworkZoneError(
          'HttpException: Connection closed before full header was received, '
          'uri = https://matrix.ourgalaxy.space/_matrix/client/v3/sync',
        ),
        isTrue,
      );
      expect(
        Log.isTransientNetworkZoneError(
          "SocketException: Failed host lookup: 'matrix.ourgalaxy.space'",
        ),
        isTrue,
      );
    });

    test('does not classify a genuine app error as transient', () {
      expect(
        Log.isTransientNetworkZoneError(
          "type 'Null' is not a subtype of type 'Map<String, dynamic>' "
          'in type cast',
        ),
        isFalse,
      );
      expect(
        Log.isTransientNetworkZoneError(
          'FormatException: Unexpected character',
        ),
        isFalse,
      );
    });
  });

  group('Log.matrixRequestPathHint', () {
    test('labels a sync request', () {
      expect(
        Log.matrixRequestPathHint(
          'HttpException: Connection closed before full header was received, '
          'uri = https://matrix.ourgalaxy.space/_matrix/client/v3/sync?since=x',
        ),
        'sync',
      );
    });

    test('labels a presence request', () {
      expect(
        Log.matrixRequestPathHint(
          'MatrixException: Too many requests, uri = '
          'https://matrix.ourgalaxy.space/_matrix/client/v3/presence/'
          '@user:ourgalaxy.space/status',
        ),
        'presence',
      );
    });

    test('labels a media request', () {
      expect(
        Log.matrixRequestPathHint(
          'ClientException: Failed, uri = '
          'https://matrix.ourgalaxy.space/_matrix/media/v3/download/'
          'ourgalaxy.space/abc123',
        ),
        'media',
      );
    });

    test('labels a key request', () {
      expect(
        Log.matrixRequestPathHint(
          'HttpException: Bad file descriptor, uri = '
          'https://matrix.ourgalaxy.space/_matrix/client/v3/keys/query',
        ),
        'keys',
      );
    });

    test('falls back to socket when the error carries no URI', () {
      expect(
        Log.matrixRequestPathHint(
          'SocketException: Bad file descriptor (OS Error: Bad file '
          'descriptor, errno = 9), address = matrix.ourgalaxy.space, '
          'port = 49416',
        ),
        'socket',
      );
    });

    test('separates DNS failures from the generic socket bucket', () {
      // Windows/Winsock wording (WSANO_DATA). A host lookup fails before any
      // connection exists, so it can never carry a URI.
      expect(
        Log.matrixRequestPathHint(
          "SocketException: Failed host lookup: 'matrix.ourgalaxy.space' "
          '(OS Error: The requested name is valid, but no data of the '
          'requested type was found, errno = 11004)',
        ),
        'dns',
      );
      // Darwin wording for the same class of failure.
      expect(
        Log.matrixRequestPathHint(
          "SocketException: Failed host lookup: 'matrix.ourgalaxy.space' "
          '(OS Error: nodename nor servname provided, errno = 8)',
        ),
        'dns',
      );
    });

    test('separates keep-alive teardown from the generic socket bucket', () {
      expect(
        Log.matrixRequestPathHint(
          'HttpException: Connection closed before full header was received',
        ),
        'http-keepalive',
      );
    });

    test('a known endpoint still wins over the failure-mode fallbacks', () {
      // The refined buckets only apply once no endpoint could be identified;
      // an error naming /sync must still report sync.
      expect(
        Log.matrixRequestPathHint(
          'HttpException: Connection closed before full header was received, '
          'uri = https://matrix.ourgalaxy.space/_matrix/client/v3/sync',
        ),
        'sync',
      );
    });

    test('labels an unclassified matrix client-api URI', () {
      expect(
        Log.matrixRequestPathHint(
          'HttpException: Connection reset, uri = '
          'https://matrix.ourgalaxy.space/_matrix/client/v3/capabilities',
        ),
        'client-api',
      );
    });
  });

  group('Log.matrixHttpOperationForRequestPath', () {
    test('maps the redacted request-path vocabulary to fixed operations', () {
      expect(Log.matrixHttpOperationForRequestPath('sync'), 'matrix_http_sync');
      expect(
        Log.matrixHttpOperationForRequestPath('client-api'),
        'matrix_http_client_api',
      );
      expect(
        Log.matrixHttpOperationForRequestPath('unknown-path'),
        'matrix_http_other',
      );
    });
  });

  group('Log.startupNetworkDiagnosticFields', () {
    test('uses the shared 45-minute diagnostic window', () {
      expect(Log.networkDiagnosticWindow, const Duration(minutes: 45));
    });

    test('adds only redacted phase and NODATA fields during startup', () {
      Log.beginStartupTelemetry();
      Log.recordStartupPhase('accounts');

      final fields = Log.startupNetworkDiagnosticFields(
        "SocketException: Failed host lookup: 'matrix.ourgalaxy.space' "
        '(OS Error: The requested name is valid, but no data of the '
        'requested type was found, errno = 11004)',
      );

      expect(fields, contains('startup_phase=accounts'));
      expect(fields, contains('resolver_outcome=nodata'));
      expect(fields, contains('resolver_target=matrix'));
      expect(fields, isNot(contains('matrix.ourgalaxy.space')));
    });

    test(
      'adds the allow-listed Matrix lifecycle operation from the request zone',
      () async {
        Log.beginStartupTelemetry();
        Log.recordStartupPhase('accounts');

        final fields = await runZoned(
          () async => Log.startupNetworkDiagnosticFields(
            "SocketException: Failed host lookup: 'matrix.ourgalaxy.space' "
            '(OS Error: The requested name is valid, but no data of the '
            'requested type was found, errno = 11004)',
          ),
          zoneValues: {
            Log.matrixNetworkOperationZoneKey: Log.matrixSdkLifecycleOperation,
          },
        );

        expect(fields, contains('matrix_operation=matrix_sdk_lifecycle'));
        expect(fields, isNot(contains('matrix.ourgalaxy.space')));
      },
    );

    test(
      'adds the bounded Matrix presence operation from the request zone',
      () async {
        Log.beginStartupTelemetry();
        Log.recordStartupPhase('accounts');

        final fields = await runZoned(
          () async => Log.startupNetworkDiagnosticFields(
            "SocketException: Failed host lookup: 'matrix.ourgalaxy.space' "
            '(OS Error: The requested name is valid, but no data of the '
            'requested type was found, errno = 11004)',
          ),
          zoneValues: {
            Log.matrixNetworkOperationZoneKey:
                Log.matrixPresenceUpdateOperation,
          },
        );

        expect(fields, contains('matrix_operation=matrix_presence_update'));
        expect(fields, isNot(contains('matrix.ourgalaxy.space')));
      },
    );

    test(
      'adds the bounded Matrix sync dispatch operation from the request zone',
      () async {
        Log.beginStartupTelemetry();
        Log.recordStartupPhase('appServices');

        final fields = await runZoned(
          () async => Log.startupNetworkDiagnosticFields(
            "SocketException: Failed host lookup: 'matrix.ourgalaxy.space' "
            '(OS Error: The requested name is valid, but no data of the '
            'requested type was found, errno = 11004)',
          ),
          zoneValues: {
            Log.matrixNetworkOperationZoneKey: Log.matrixSyncDispatchOperation,
          },
        );

        expect(fields, contains('matrix_operation=matrix_sync_dispatch'));
        expect(fields, isNot(contains('matrix.ourgalaxy.space')));
      },
    );

    test('does not attach a Matrix operation to a non-Matrix target', () async {
      Log.beginStartupTelemetry();
      Log.recordStartupPhase('localServices');

      final fields = await runZoned(
        () async => Log.startupNetworkDiagnosticFields(
          "SocketException: Failed host lookup: 'api.spotify.com' "
          '(OS Error: The requested name is valid, but no data of the '
          'requested type was found, errno = 11004)',
        ),
        zoneValues: {
          Log.matrixNetworkOperationZoneKey: Log.matrixSdkLifecycleOperation,
        },
      );

      expect(fields, isNot(contains('matrix_operation=')));
    });
  });

  group('Log.shouldLogTransientNetworkZoneError', () {
    test(
      'suppresses a handled optional request from generic zone diagnostics',
      () async {
        final error = SocketException(
          "Failed host lookup: 'ourgalaxy.space'",
          osError: const OSError('NODATA', 11004),
        );

        final shouldLog = await runZoned(
          () async =>
              Log.shouldLogTransientNetworkZoneError(error, Zone.current),
          zoneValues: {Log.handledOptionalNetworkRequestZoneKey: true},
        );

        expect(shouldLog, isFalse);
      },
    );

    test(
      'suppresses a controlled optional failure in the installed root callback',
      () async {
        final error = SocketException(
          "Failed host lookup: 'ourgalaxy.space'",
          osError: const OSError('NODATA', 11004),
        );
        final handled = Completer<void>();
        final logStart = Log.log.length;

        runZonedGuarded(
          () {
            runZoned(
              () => Future<void>.microtask(() => throw error),
              zoneValues: {Log.handledOptionalNetworkRequestZoneKey: true},
            );
          },
          (_, __) {
            if (!handled.isCompleted) {
              handled.complete();
            }
          },
          zoneSpecification: Log.spec,
        );

        await handled.future.timeout(const Duration(seconds: 1));
        final newEntries = Log.log.skip(logStart);
        expect(
          newEntries.where((entry) => entry.source == 'zone-network-callback'),
          isEmpty,
        );
      },
    );
  });

  group('Log.resolverTargetClass', () {
    test('maps watched names without retaining the hostname', () {
      expect(
        Log.resolverTargetClass(
          "SocketException: Failed host lookup: 'matrix.ourgalaxy.space'",
        ),
        'matrix',
      );
      expect(
        Log.resolverTargetClass(
          "SocketException: Failed host lookup: 'www.tiktok.com'",
        ),
        'third_party',
      );
    });

    test('fails closed to other for an unrecognized target', () {
      expect(
        Log.resolverTargetClass(
          "SocketException: Failed host lookup: 'unrecognized.example'",
        ),
        'other',
      );
    });
  });

  group('Log.resolverRetryProbeHost', () {
    test('retries only fixed allow-listed hosts', () {
      expect(
        Log.resolverRetryProbeHost(
          "SocketException: Failed host lookup: 'matrix.ourgalaxy.space'",
        ),
        'matrix.ourgalaxy.space',
      );
      expect(
        Log.resolverRetryProbeHost(
          "SocketException: Failed host lookup: 'unrecognized.example'",
        ),
        isNull,
      );
    });
  });

  group('Log.runOptionalResolverDiagnostic', () {
    test(
      'contains synchronous and asynchronous failures in the root zone',
      () async {
        final escaped = <Object>[];
        final settled = Completer<void>();

        runZonedGuarded(
          () {
            Log.runOptionalResolverDiagnostic(() => throw StateError('sync'));
            Log.runOptionalResolverDiagnostic(() async {
              throw StateError('async');
            });
            Future<void>.delayed(
              const Duration(milliseconds: 20),
              settled.complete,
            );
          },
          (error, _) => escaped.add(error),
          zoneSpecification: Log.spec,
        );

        await settled.future.timeout(const Duration(seconds: 1));
        expect(escaped, isEmpty);
      },
    );
  });

  group('Log.nativeResolverProbeFields', () {
    test('keeps native resolver evidence redacted to fixed fields', () {
      final fields = Log.nativeResolverProbeFields(
        const NativeResolverProbeResult(
          outcome: 'nodata',
          errorCode: 11004,
          elapsed: Duration(milliseconds: 12),
        ),
      );

      expect(fields, contains('native_outcome=nodata'));
      expect(fields, contains('native_code=11004'));
      expect(fields, contains('native_ms=12'));
      expect(fields, isNot(contains('matrix.ourgalaxy.space')));
    });
  });

  group('NativeResolverProbeCoordinator', () {
    test(
      'does not restart a native lookup after its bounded wait expires',
      () async {
        final pending = Completer<NativeResolverProbeResult>();
        var invocations = 0;
        final coordinator = NativeResolverProbeCoordinator(
          probe: (_) {
            invocations++;
            return pending.future;
          },
          timeout: Duration.zero,
        );

        final first = await coordinator.probe('matrix.ourgalaxy.space');
        final second = await coordinator.probe('matrix.ourgalaxy.space');

        expect(first.outcome, 'timeout');
        expect(second.outcome, 'timeout');
        expect(invocations, 1);
        pending.complete(
          const NativeResolverProbeResult(
            outcome: 'resolved',
            elapsed: Duration.zero,
          ),
        );
      },
    );
  });

  group('Log.transientNetworkCallerClass', () {
    test('returns an allow-listed class without retaining stack details', () {
      expect(
        Log.transientNetworkCallerClass(
          StackTrace.fromString(
            '#0 MatrixClient.sync (package:intergalactic/client/matrix/'
            'matrix_client.dart:42:7)',
          ),
        ),
        'matrix_client',
      );
      expect(
        Log.transientNetworkCallerClass(
          StackTrace.fromString(
            '#0 resolver (package:matrix/src/api.dart:1:1)',
          ),
        ),
        'matrix_sdk',
      );
      expect(Log.transientNetworkCallerClass(null), 'unknown');
    });
  });
}
