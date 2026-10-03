/// The host-written key-backup version handoff the iOS Notification Service
/// Extension will consume for the bounded E1 room-key lookup.
///
/// The extension never discovers a version itself: it must not call the room
/// key-version endpoint. Non-iOS platforms get a no-op implementation.
export 'nse_backup_version_stub.dart'
    if (dart.library.io) 'nse_backup_version_io.dart';
