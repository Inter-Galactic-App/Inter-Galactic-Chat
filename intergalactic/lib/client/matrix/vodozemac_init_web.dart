import 'package:flutter_vodozemac/flutter_vodozemac.dart' as fvod;

/// Initializes vodozemac for web using the generated WASM package.
Future<void> initVodozemacForPlatform() async {
  await fvod.init(wasmPath: './pkg/');
}
