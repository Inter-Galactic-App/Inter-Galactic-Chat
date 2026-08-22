import 'package:flutter_vodozemac/flutter_vodozemac.dart' as fvod;
import 'package:vodozemac/vodozemac.dart' as vod;

/// Initializes vodozemac for web using the generated WASM package.
///
/// Guarded so a retry after a slow first attempt cannot re-run WASM
/// initialization once it has already succeeded (mirrors the non-web variant).
Future<void> initVodozemacForPlatform() async {
  if (vod.isInitialized()) return;
  await fvod.init(wasmPath: './pkg/');
}
