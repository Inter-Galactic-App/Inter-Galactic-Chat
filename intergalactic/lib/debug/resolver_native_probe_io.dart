import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart' as pkg_ffi;
import 'package:intergalactic/debug/resolver_native_probe_result.dart';

const _nativeProbeTimeout = Duration(seconds: 2);
final _nativeProbeCoordinator = NativeResolverProbeCoordinator(
  probe: _startNativeResolverProbe,
  timeout: _nativeProbeTimeout,
);

/// Reads the Windows resolver from this application's process after an
/// observed transient failure. The isolate is still in-process; it keeps the
/// synchronous Winsock call off the UI isolate. No address or hostname leaves
/// this module.
Future<NativeResolverProbeResult> probeNativeResolver(String host) async {
  if (!Platform.isWindows) {
    return const NativeResolverProbeResult(
      outcome: 'unavailable',
      elapsed: Duration.zero,
    );
  }

  return _nativeProbeCoordinator.probe(host);
}

Future<NativeResolverProbeResult> _startNativeResolverProbe(String host) async {
  final stopwatch = Stopwatch()..start();
  try {
    final raw = await Isolate.run(() => _probeNativeResolverRaw(host));
    stopwatch.stop();
    return NativeResolverProbeResult(
      outcome: raw.outcome,
      elapsed: stopwatch.elapsed,
      errorCode: raw.errorCode,
    );
  } catch (_) {
    stopwatch.stop();
    return NativeResolverProbeResult(
      outcome: 'native_error',
      elapsed: stopwatch.elapsed,
    );
  }
}

({String outcome, int? errorCode}) _probeNativeResolverRaw(String host) {
  final ws2_32 = ffi.DynamicLibrary.open('ws2_32.dll');
  final startup = ws2_32.lookupFunction<_WsaStartupNative, _WsaStartupDart>(
    'WSAStartup',
  );
  final cleanup = ws2_32.lookupFunction<_WsaCleanupNative, _WsaCleanupDart>(
    'WSACleanup',
  );
  final getAddrInfo = ws2_32
      .lookupFunction<_GetAddrInfoNative, _GetAddrInfoDart>('GetAddrInfoW');
  final freeAddrInfo = ws2_32
      .lookupFunction<_FreeAddrInfoNative, _FreeAddrInfoDart>('FreeAddrInfoW');

  // WSADATA is 400 bytes on Winsock 2.2. We only need it to initialize the
  // process-local API and deliberately never inspect its provider details.
  final wsaData = pkg_ffi.calloc<ffi.Uint8>(400);
  final startupCode = startup(0x0202, wsaData.cast<ffi.Void>());
  if (startupCode != 0) {
    pkg_ffi.calloc.free(wsaData);
    return (outcome: 'wsa_startup_error', errorCode: startupCode);
  }

  final node = host.toNativeUtf16();
  final result = pkg_ffi.calloc<ffi.Pointer<ffi.Void>>();
  try {
    final code = getAddrInfo(node, ffi.nullptr, ffi.nullptr, result);
    if (code == 0) {
      if (result.value.address != 0) {
        freeAddrInfo(result.value);
      }
      return (outcome: 'resolved', errorCode: null);
    }
    return (outcome: _outcomeForCode(code), errorCode: code);
  } finally {
    pkg_ffi.calloc.free(result);
    pkg_ffi.calloc.free(node);
    cleanup();
    pkg_ffi.calloc.free(wsaData);
  }
}

String _outcomeForCode(int code) => switch (code) {
  11004 => 'nodata',
  11001 => 'name_not_found',
  _ => 'native_error',
};

typedef _WsaStartupNative =
    ffi.Int32 Function(
      ffi.Uint16 versionRequested,
      ffi.Pointer<ffi.Void> wsaData,
    );
typedef _WsaStartupDart =
    int Function(int versionRequested, ffi.Pointer<ffi.Void> wsaData);
typedef _WsaCleanupNative = ffi.Int32 Function();
typedef _WsaCleanupDart = int Function();
typedef _GetAddrInfoNative =
    ffi.Int32 Function(
      ffi.Pointer<pkg_ffi.Utf16> nodeName,
      ffi.Pointer<pkg_ffi.Utf16> serviceName,
      ffi.Pointer<ffi.Void> hints,
      ffi.Pointer<ffi.Pointer<ffi.Void>> result,
    );
typedef _GetAddrInfoDart =
    int Function(
      ffi.Pointer<pkg_ffi.Utf16> nodeName,
      ffi.Pointer<pkg_ffi.Utf16> serviceName,
      ffi.Pointer<ffi.Void> hints,
      ffi.Pointer<ffi.Pointer<ffi.Void>> result,
    );
typedef _FreeAddrInfoNative = ffi.Void Function(ffi.Pointer<ffi.Void> result);
typedef _FreeAddrInfoDart = void Function(ffi.Pointer<ffi.Void> result);
