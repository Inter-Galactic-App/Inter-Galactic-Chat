/// The notification policy snapshot the iOS Notification Service Extension
/// reads (NSE Phase C, S&C condition C3).
///
/// On iOS the host writes a compact, policy-only file into the App Group
/// every time one of the local notification preferences changes, and the
/// extension looks it up before it renders anything event-derived. Every
/// other platform gets the no-op stub.
export 'notification_policy_snapshot_stub.dart'
    if (dart.library.io) 'notification_policy_snapshot_io.dart';
