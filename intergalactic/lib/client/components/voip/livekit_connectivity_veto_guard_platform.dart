/// The two `dart:io`-shaped facts the guard needs, behind a conditional import.
///
/// `main.dart` imports the guard unconditionally, so anything the guard's
/// library graph reaches is compiled for web too. `dart:io` there is a hard
/// compile error, not a runtime one - `Platform.isWindows` cannot gate it,
/// because the check happens after the import has already failed to resolve.
export 'livekit_connectivity_veto_guard_platform_stub.dart'
    if (dart.library.io) 'livekit_connectivity_veto_guard_platform_io.dart';
