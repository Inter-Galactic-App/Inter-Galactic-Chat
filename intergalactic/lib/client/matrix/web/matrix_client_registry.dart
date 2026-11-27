import 'dart:convert';

import 'package:intergalactic/client/matrix/database/matrix_database.dart';
import 'package:crypto/crypto.dart';

import 'matrix_client_registry_stub.dart'
    if (dart.library.html) 'matrix_client_registry_html.dart' as platform;

class MatrixClientRegistry {
  static const String previewClientId = '__login_preview__';

  static String normalizeHomeserver(Uri homeserver) {
    final scheme = homeserver.scheme.isEmpty ? 'https' : homeserver.scheme;
    final host = homeserver.host.toLowerCase();
    final port = homeserver.hasPort ? ':${homeserver.port}' : '';
    return '$scheme://$host$port';
  }

  static String normalizeUserHint(String userIdOrHint) {
    return userIdOrHint.trim().toLowerCase();
  }

  static String localpartFromUserId(String userId) {
    final normalized = userId.startsWith('@') ? userId.substring(1) : userId;
    final separatorIndex = normalized.indexOf(':');
    if (separatorIndex == -1) {
      return normalized.toLowerCase();
    }

    return normalized.substring(0, separatorIndex).toLowerCase();
  }

  static String localpartFromUserHint(String userIdOrHint) {
    final normalized = normalizeUserHint(userIdOrHint);
    if (normalized.startsWith('@') && normalized.contains(':')) {
      return localpartFromUserId(normalized);
    }

    return normalized.startsWith('@') ? normalized.substring(1) : normalized;
  }

  static String deriveStableClientId({
    required Uri homeserver,
    required String userIdOrHint,
  }) {
    final payload =
        '${normalizeHomeserver(homeserver)}|${normalizeUserHint(userIdOrHint)}';
    final digest = sha256.convert(utf8.encode(payload)).toString();
    return 'mx_${digest.substring(0, 24)}';
  }

  static Future<void> upsert(Map<String, dynamic> record) {
    return platform.MatrixClientRegistryPlatform.upsert(
      _normalizeRecord(record),
    );
  }

  static Future<void> remove(String clientId) {
    return platform.MatrixClientRegistryPlatform.remove(clientId);
  }

  static Future<List<Map<String, dynamic>>> getStoredClients() async {
    final clients =
        await platform.MatrixClientRegistryPlatform.getStoredClients();
    final normalized = clients
        .map(_normalizeRecord)
        .where(
          (record) =>
              (record['clientId'] as String?)?.isNotEmpty == true &&
              record['clientId'] != previewClientId,
        )
        .toList();
    normalized.sort(_compareByUpdatedAtDescending);
    return normalized;
  }

  static Future<List<Map<String, dynamic>>> getStoredClientsForHomeserver(
    Uri homeserver,
  ) async {
    final normalizedHomeserver = normalizeHomeserver(homeserver);
    return (await getStoredClients())
        .where((record) => record['homeserver'] == normalizedHomeserver)
        .toList();
  }

  static Future<Map<String, dynamic>?> getStoredClientById(String clientId) async {
    for (final client in await getStoredClients()) {
      if (client['clientId'] == clientId) {
        return client;
      }
    }

    return null;
  }

  static Future<Map<String, dynamic>?> findStoredClientForLogin({
    required Uri homeserver,
    required String userIdOrHint,
  }) async {
    final normalizedUserId = normalizeUserHint(userIdOrHint);
    final normalizedLocalpart = localpartFromUserHint(userIdOrHint);

    final matches = (await getStoredClientsForHomeserver(homeserver)).where((record) {
      final recordUserId = (record['normalizedUserId'] as String?) ?? '';
      final recordLocalpart = (record['localpart'] as String?) ?? '';
      return recordUserId == normalizedUserId ||
          recordLocalpart == normalizedLocalpart;
    }).toList();

    if (matches.isEmpty) {
      return null;
    }

    matches.sort(_compareByUpdatedAtDescending);
    return matches.first;
  }

  static Future<List<String>> resolveRegisteredClientIds(
    List<String> preferenceClientIds,
  ) async {
    final resolved = <String>[];

    void addClientId(String? clientId) {
      if (clientId == null ||
          clientId.isEmpty ||
          clientId == previewClientId ||
          resolved.contains(clientId)) {
        return;
      }

      resolved.add(clientId);
    }

    for (final clientId in preferenceClientIds) {
      addClientId(clientId);
    }

    final storedClients = await getStoredClients();
    for (final client in storedClients) {
      addClientId(client['clientId'] as String?);
    }

    return resolved;
  }

  static Future<void> invalidateStoredDevice(String clientId) async {
    final storedClient = await getStoredClientById(clientId);
    if (storedClient == null) {
      return;
    }

    final sanitized = Map<String, dynamic>.from(storedClient)
      ..remove('deviceId')
      ..['updatedAt'] = DateTime.now().toUtc().toIso8601String();
    await upsert(sanitized);
  }

  static Future<Map<String, dynamic>> collectStorageDiagnostics() {
    return platform.MatrixClientRegistryPlatform.collectStorageDiagnostics();
  }

  static Future<Map<String, dynamic>> collectDiagnostics({
    required List<String> preferenceClientIds,
    required List<String> auditEvents,
    String? lastRestoreDecision,
  }) async {
    final resolvedClientIds =
        await resolveRegisteredClientIds(preferenceClientIds);
    final registryClients = await getStoredClients();
    final storage = await collectStorageDiagnostics();
    final dbOpenChecks = <Map<String, dynamic>>[];

    for (final clientId in resolvedClientIds) {
      try {
        final db = await getMatrixDatabase(clientId);
        try {
          final storedClient = await db.getClient(clientId);
          dbOpenChecks.add({
            'clientId': clientId,
            'opened': true,
            'hasStoredSession': storedClient != null,
          });
        } finally {
          await db.close();
        }
      } catch (error) {
        dbOpenChecks.add({
          'clientId': clientId,
          'opened': false,
          'error': error.toString(),
        });
      }
    }

    return {
      'storage': storage,
      'preferencesRegisteredClients': preferenceClientIds,
      'registryClients': registryClients,
      'resolvedClientIds': resolvedClientIds,
      'dbOpenChecks': dbOpenChecks,
      'lastRestoreDecision': lastRestoreDecision,
      'recentAuditEvents': auditEvents,
    };
  }

  static Map<String, dynamic> _normalizeRecord(Map<String, dynamic> record) {
    final normalized = Map<String, dynamic>.from(record);
    final userId = normalized['userId'] as String?;
    final localpart = normalized['localpart'] as String?;
    final homeserver = normalized['homeserver'] as String?;

    if (userId != null) {
      normalized['normalizedUserId'] = normalizeUserHint(userId);
      normalized['localpart'] = localpart ?? localpartFromUserId(userId);
    }

    if (homeserver != null && homeserver.isNotEmpty) {
      normalized['homeserver'] = homeserver.toLowerCase();
    }

    return normalized;
  }

  static int _compareByUpdatedAtDescending(
    Map<String, dynamic> left,
    Map<String, dynamic> right,
  ) {
    final leftTime = DateTime.tryParse(left['updatedAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final rightTime = DateTime.tryParse(right['updatedAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return rightTime.compareTo(leftTime);
  }
}
