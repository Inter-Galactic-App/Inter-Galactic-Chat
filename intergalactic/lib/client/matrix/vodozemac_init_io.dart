import 'dart:io' show Platform;

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as fvod;
import 'package:vodozemac/src/generated/frb_generated.dart' as vodozemac_gen;
import 'package:vodozemac/vodozemac.dart' as vod;

/// Initializes vodozemac for the current non-web platform.
///
/// On iOS the Rust library is force-loaded into the main binary, so the
/// generated bindings need to resolve symbols from the current process instead
/// of trying to dlopen a static framework archive.
Future<void> initVodozemacForPlatform() async {
  if (vod.isInitialized()) return;

  if (Platform.isIOS) {
    await vodozemac_gen.RustLib.init(
      externalLibrary: ExternalLibrary.process(iKnowHowToUseIt: true),
    );
  } else {
    await fvod.init();
  }
}
