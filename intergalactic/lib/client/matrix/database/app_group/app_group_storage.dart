import 'package:flutter/services.dart';

/// The native half of the App Group storage that the account database moves
/// into on iOS (NSE Phase B).
///
/// Three calls, and nothing else: resolve the shared container, set the
/// data-protection class on one item and hand back what the filesystem reports
/// afterwards, and read that class without changing it. The migration owes
/// S&C condition B1 - `completeUntilFirstUserAuthentication` on every moved
/// file AND its directory, verified by read-back, re-asserted on every launch,
/// and the move aborted if the class cannot be set - and every one of those
/// obligations is a call through this interface. Tests supply a fake.
abstract class AppGroupStorageHost {
  /// The App Group container path, or null when the group is unavailable.
  Future<String?> containerPath();

  /// Sets `completeUntilFirstUserAuthentication` on [path] and returns the
  /// protection class the filesystem reports afterwards, or null when no class
  /// is reported at all. The caller compares it against
  /// [expectedProtectionClass]; anything else is a failed read-back.
  ///
  /// Throws when the item is missing, outside the container, or the attribute
  /// cannot be set. The native side never writes outside the container.
  Future<String?> protectItem(String path);

  /// Reads the protection class of [path] without changing it. Also answers
  /// for the app-private Application Support tree, which is what lets the
  /// class of the not-yet-moved database be measured before the move.
  Future<String?> readProtectionClass(String path);

  /// Marks [path], inside the App Group container, as excluded from backup
  /// (S&C D3 / C3: the policy snapshot carries no user value and must not
  /// reach backup media). Returns what the resource reports afterwards.
  Future<bool> excludeFromBackup(String path);

  /// The raw value iOS reports for
  /// `FileProtectionType.completeUntilFirstUserAuthentication`.
  static const String expectedProtectionClass =
      'NSFileProtectionCompleteUntilFirstUserAuthentication';
}

/// The iOS bridge, backed by the `app_group_storage` channel in
/// `AppDelegate.swift`.
class ChannelAppGroupStorageHost implements AppGroupStorageHost {
  const ChannelAppGroupStorageHost();

  static const MethodChannel channel = MethodChannel(
    'chat.intergalactic.app/app_group_storage',
  );

  @override
  Future<String?> containerPath() =>
      channel.invokeMethod<String>('getContainerPath');

  @override
  Future<String?> protectItem(String path) =>
      channel.invokeMethod<String>('protectItem', {'path': path});

  @override
  Future<String?> readProtectionClass(String path) =>
      channel.invokeMethod<String>('readProtectionClass', {'path': path});

  @override
  Future<bool> excludeFromBackup(String path) async =>
      await channel.invokeMethod<bool>('excludeFromBackup', {'path': path}) ??
      false;
}
