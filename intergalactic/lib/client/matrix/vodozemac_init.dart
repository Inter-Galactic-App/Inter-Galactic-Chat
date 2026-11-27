// Selects the correct vodozemac init implementation based on platform.
// On iOS the Rust library is statically linked into the main binary via
// Cargokit/CocoaPods (-force_load libvodozemac_bindings_dart.a).
// Because the Podfile uses `use_frameworks! :linkage => :static`, the
// flutter_vodozemac.framework binary is a static archive; dlopen() cannot
// open it. DynamicLibrary.process() resolves symbols already present in the
// running process.
// The platform split is required so dart:ffi is only imported on non-web.
export 'vodozemac_init_io.dart'
    if (dart.library.js_interop) 'vodozemac_init_web.dart';
