import 'package:flutter_vodozemac/flutter_vodozemac.dart' as fvod;
import 'package:intergalactic/client/matrix/vodozemac_single_flight.dart';
import 'package:vodozemac/vodozemac.dart' as vod;

/// One latch for the whole isolate: web has exactly one WASM runtime to
/// initialize, and the point is that two attempts can never run against it.
final VodozemacSingleFlight _singleFlight = VodozemacSingleFlight();

/// Initializes vodozemac for web using the generated WASM package.
///
/// Single-flight (CodeRabbit #8). The caller bounds each attempt with its own
/// timeout and retries, and a Dart timeout does not cancel the work it gave up
/// on, so a retry used to start a SECOND WASM download and bridge setup while
/// the first was still running. A retry now joins the attempt already in
/// flight; only a genuinely failed attempt starts a new one.
Future<void> initVodozemacForPlatform() {
  return _singleFlight.run(
    isInitialized: vod.isInitialized,
    initialize: () => fvod.init(wasmPath: './pkg/'),
  );
}
