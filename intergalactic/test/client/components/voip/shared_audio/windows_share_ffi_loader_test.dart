import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:test/test.dart';
import 'package:intergalactic_windows_share/intergalactic_windows_share.dart';
import 'package:intergalactic_windows_share/src/intergalactic_windows_share_impl_ffi.dart';

void main() {
  final allocations = <Pointer<Utf8>>[];

  Pointer<Utf8> utf8(String value) {
    final pointer = value.toNativeUtf8();
    allocations.add(pointer);
    return pointer;
  }

  tearDown(() {
    for (final pointer in allocations) {
      malloc.free(pointer);
    }
    allocations.clear();
  });

  test(
    'missing audio endpoint export leaves core share exports available',
    () async {
      final lookup = _FakeWindowsShareSymbolLookup(
        missingSymbols: const {
          'intergalactic_windows_share_list_audio_endpoints_json',
        },
        utf8: utf8,
      );
      final binding = createWindowsShareNativeBindingForTesting(
        symbolLookup: lookup,
      );

      expect(await binding.listAudioEndpoints(), isEmpty);

      final capabilities = await binding.getCapabilities();
      expect(capabilities.supported, isTrue);
      expect(capabilities.processTreeLoopbackSupported, isTrue);

      final targets = await binding.listTargets();
      expect(targets, hasLength(1));
      expect(targets.single.title, 'Window under test');

      final sessionId = await binding.createSession(
        targetType: WindowsShareTargetType.window,
        audioMode: WindowsSharedAudioMode.processTreeLoopback,
        processId: 4242,
        requestSharedAudio: true,
      );
      expect(sessionId, 42);

      final status = await binding.startSharedAudio(sessionId);
      expect(status.supported, isTrue);
      expect(status.active, isTrue);
      expect(status.reason, 'capturing');
    },
  );

  test('missing core share export keeps the plugin failed closed', () async {
    final binding = createWindowsShareNativeBindingForTesting(
      symbolLookup: _FakeWindowsShareSymbolLookup(
        missingSymbols: const {'intergalactic_windows_share_create_session'},
        utf8: utf8,
      ),
    );

    final capabilities = await binding.getCapabilities();
    expect(capabilities.supported, isFalse);
    expect(capabilities.reason, 'native_library_load_failed');

    expect(
      await binding.createSession(
        targetType: WindowsShareTargetType.window,
        audioMode: WindowsSharedAudioMode.processTreeLoopback,
        processId: 4242,
        requestSharedAudio: true,
      ),
      0,
    );
    expect(await binding.listTargets(), isEmpty);
  });
}

class _FakeWindowsShareSymbolLookup implements WindowsShareNativeSymbolLookup {
  _FakeWindowsShareSymbolLookup({
    required this.missingSymbols,
    required this.utf8,
  });

  final Set<String> missingSymbols;
  final Pointer<Utf8> Function(String value) utf8;

  void _guard(String symbol) {
    if (missingSymbols.contains(symbol)) {
      throw ArgumentError('missing $symbol');
    }
  }

  @override
  WindowsShareGetJsonFunction lookupGetJson(String symbol) {
    _guard(symbol);
    return switch (symbol) {
      'intergalactic_windows_share_get_capabilities_json' => () => utf8(
        _capabilitiesJson,
      ),
      'intergalactic_windows_share_list_targets_json' => () => utf8(
        _targetsJson,
      ),
      'intergalactic_windows_share_list_audio_endpoints_json' => () => utf8(
        _endpointsJson,
      ),
      _ => throw ArgumentError('unexpected get-json symbol $symbol'),
    };
  }

  @override
  WindowsShareGetSessionJsonFunction lookupGetSessionJson(String symbol) {
    _guard(symbol);
    return switch (symbol) {
      'intergalactic_windows_share_create_shared_audio_stream_json' =>
        (sessionId) => utf8(_streamJson(sessionId)),
      'intergalactic_windows_share_get_session_status_json' =>
        (sessionId) => utf8(_statusJson(sessionId)),
      _ => throw ArgumentError('unexpected session-json symbol $symbol'),
    };
  }

  @override
  WindowsShareCreateSessionFunction lookupCreateSession(String symbol) {
    _guard(symbol);
    if (symbol != 'intergalactic_windows_share_create_session') {
      throw ArgumentError('unexpected create-session symbol $symbol');
    }
    return (targetType, audioMode, processId, requestSharedAudio, deviceId) =>
        42;
  }

  @override
  WindowsShareSessionCommandFunction lookupSessionCommand(String symbol) {
    _guard(symbol);
    switch (symbol) {
      case 'intergalactic_windows_share_start_shared_audio':
      case 'intergalactic_windows_share_stop_shared_audio':
      case 'intergalactic_windows_share_dispose_shared_audio_stream':
      case 'intergalactic_windows_share_dispose_session':
        return (sessionId) => 0;
    }
    throw ArgumentError('unexpected session-command symbol $symbol');
  }
}

const _capabilitiesJson = '''
{
  "supported": true,
  "applicationLoopbackSupported": true,
  "processTreeLoopbackSupported": true,
  "wgcSupported": true,
  "pcmBridgeSupported": true,
  "endpointLoopbackSupported": true,
  "deviceCaptureSupported": true,
  "hasVirtualAudioDevice": false,
  "osBuild": 22631,
  "documentedProcessLoopbackBuild": 20348,
  "processLoopbackHresult": "0x0",
  "processLoopbackStage": "none",
  "reason": "ready"
}
''';

const _targetsJson = '''
[
  {
    "windowHandle": 1234,
    "processId": 4242,
    "title": "Window under test"
  }
]
''';

const _endpointsJson = '''
[
  {
    "id": "endpoint",
    "name": "Speakers",
    "isCapture": false,
    "isDefault": true,
    "isLikelyVirtual": false,
    "virtualFamily": ""
  }
]
''';

String _streamJson(int sessionId) =>
    '''
{
  "sessionId": $sessionId,
  "supported": false,
  "reason": "not_used"
}
''';

String _statusJson(int sessionId) =>
    '''
{
  "sessionId": $sessionId,
  "supported": true,
  "requestedAudio": true,
  "targetType": "window",
  "audioMode": "processTreeLoopback",
  "audioState": "active",
  "active": true,
  "sampleRateHz": 48000,
  "numChannels": 2,
  "bitsPerSample": 16,
  "packetsCaptured": 1,
  "framesCaptured": 480,
  "bytesCaptured": 1920,
  "nonsilentBytesCaptured": 1920,
  "targetElevated": false,
  "targetElevationKnown": true,
  "pcmBridgeSupported": true,
  "wgcReady": true,
  "lastHresult": "0x0",
  "failureStage": "none",
  "selectedDeviceId": "",
  "reason": "capturing"
}
''';
