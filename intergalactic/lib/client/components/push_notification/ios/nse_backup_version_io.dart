import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:intergalactic/client/matrix/database/app_group/app_group_storage.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:path/path.dart' as p;

class NseBackupVersionEntry {
  const NseBackupVersionEntry({required this.clientId, required this.version});

  final String clientId;
  final String version;
}

/// E3's host-only backup-version handoff.
///
/// This document deliberately carries only a Matrix client identifier and the
/// already-current backup version. It contains no key material, homeserver,
/// access token, room, session, or event data. The extension reads this file
/// only after local decryption reports a missing session; it never discovers a
/// version from the homeserver itself.
class NseBackupVersion {
  NseBackupVersion._();

  static const String directoryName = 'nse-key-backup';
  static const String fileName = 'versions.json';
  static const int documentVersion = 1;
  static const int maxBytes = 4 * 1024;
  static const int maxEntries = 16;
  static final RegExp _versionPattern = RegExp(r'^[A-Za-z0-9._-]{1,32}$');
  static const String _source = 'nse-key-backup';

  @visibleForTesting
  static AppGroupStorageHost? host;

  @visibleForTesting
  static bool? platformIsIOS;

  static bool get _enabled => platformIsIOS ?? PlatformUtils.isIOS;

  static Future<void> _mutations = Future<void>.value();

  /// Resolves every currently attached account before publishing one atomic
  /// document. A failed lookup omits that account rather than retaining a
  /// stale version: the later extension path must then keep the generic alert.
  static Future<void> synchronize(
    Iterable<Future<NseBackupVersionEntry?>> entries,
  ) {
    if (!_enabled) {
      return Future<void>.value();
    }
    final pending = entries
        .map(
          (candidate) => candidate.then<NseBackupVersionEntry?>(
            (entry) => entry,
            onError: (Object _, StackTrace __) => null,
          ),
        )
        .toList(growable: false);
    return _serialised(() => _synchronize(pending));
  }

  static Future<void> _synchronize(
    List<Future<NseBackupVersionEntry?>> pending,
  ) async {
    final entries = <NseBackupVersionEntry>[];
    for (final candidate in pending) {
      try {
        final entry = await candidate;
        if (entry != null) entries.add(entry);
      } catch (_) {
        // A failed host lookup deliberately leaves no version for that account.
      }
    }

    try {
      final directory = await _directory();
      if (directory == null) return;
      await writeEntries(entries, directory: directory);
    } catch (error) {
      Log.e(
        'NSE backup-version handoff failed: ${error.runtimeType}',
        category: LogCategory.notifications,
        source: _source,
      );
    }
  }

  @visibleForTesting
  static Map<String, Object?> build(Iterable<NseBackupVersionEntry> entries) {
    final versions = <String, String>{};
    for (final entry in entries) {
      if (_validClientId(entry.clientId) &&
          _versionPattern.hasMatch(entry.version)) {
        versions[entry.clientId] = entry.version;
      }
    }
    if (versions.length > maxEntries) {
      return <String, Object?>{'version': documentVersion, 'undecidable': true};
    }
    return <String, Object?>{
      'version': documentVersion,
      'versions': Map<String, String>.fromEntries(
        versions.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
      ),
    };
  }

  @visibleForTesting
  static Future<void> writeEntries(
    Iterable<NseBackupVersionEntry> entries, {
    required String directory,
    AppGroupStorageHost? storage,
  }) async {
    final target = storage ?? host ?? const ChannelAppGroupStorageHost();
    final document = build(entries);
    final versions = document['versions'] as Map<String, String>?;
    if (versions == null || versions.isEmpty) {
      await deleteIn(directory);
      return;
    }

    final encoded = jsonEncode(document);
    if (utf8.encode(encoded).length > maxBytes) {
      await deleteIn(directory);
      return;
    }

    final dir = Directory(directory);
    await dir.create(recursive: true);
    await _protect(target, directory);

    final path = p.join(directory, fileName);
    final staging = File('$path.tmp');
    await staging.writeAsString(encoded, flush: true);
    await staging.rename(path);
    try {
      await _protect(target, path);
      if (!await target.excludeFromBackup(path))
        throw StateError('backup flag');
    } catch (_) {
      try {
        await File(path).delete();
      } catch (_) {}
      rethrow;
    }
    Log.d(
      'NSE backup-version handoff updated accounts=${versions.length}',
      category: LogCategory.notifications,
      source: _source,
    );
  }

  @visibleForTesting
  static Future<void> deleteIn(String directory) async {
    for (final suffix in [fileName, '$fileName.tmp']) {
      final file = File(p.join(directory, suffix));
      if (await file.exists()) await file.delete();
    }
  }

  static Future<void> _protect(AppGroupStorageHost target, String path) async {
    if (await target.protectItem(path) !=
        AppGroupStorageHost.expectedProtectionClass) {
      throw StateError('protection class did not read back');
    }
  }

  static bool _validClientId(String value) =>
      value.isNotEmpty &&
      value.length <= 256 &&
      !value.contains(RegExp(r'[\u0000-\u001f]'));

  static Future<String?> _directory() async {
    final container = await (host ?? const ChannelAppGroupStorageHost())
        .containerPath();
    if (container == null || container.isEmpty) return null;
    return p.join(container, directoryName);
  }

  static Future<void> _serialised(Future<void> Function() action) {
    final next = _mutations.then((_) => action());
    _mutations = next.catchError((Object _) {});
    return next;
  }

  @visibleForTesting
  static void resetForTests() {
    host = null;
    platformIsIOS = null;
    _mutations = Future<void>.value();
  }
}
