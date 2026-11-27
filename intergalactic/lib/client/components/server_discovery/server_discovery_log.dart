import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'server_discovery_models.dart';

class ServerDiscoveryLogFormatter {
  const ServerDiscoveryLogFormatter._();

  static final String _processSalt = _newProcessSalt();

  static String fetchSuccess({
    required ServerDiscoveryScope scope,
    required ServerDiscoveryRequest request,
    required int resultCount,
    required bool hasMore,
  }) {
    return 'Server Discovery fetch success '
        'homeserver=${_hash(scope.homeserver)} '
        'filter=${request.filter.name} '
        'hasSearch=${request.hasSearch} '
        'count=$resultCount '
        'hasMore=$hasMore';
  }

  static String fetchFailure({
    required ServerDiscoveryScope scope,
    required ServerDiscoveryRequest request,
    required String? matrixErrorCode,
  }) {
    return 'Server Discovery fetch failed '
        'homeserver=${_hash(scope.homeserver)} '
        'filter=${request.filter.name} '
        'hasSearch=${request.hasSearch} '
        'matrixError=${_safeMatrixError(matrixErrorCode)}';
  }

  static String supplementalFailure({
    required ServerDiscoveryScope scope,
    required ServerDiscoveryRequest request,
    required String? matrixErrorCode,
  }) {
    return 'Server Discovery supplemental source failed '
        'homeserver=${_hash(scope.homeserver)} '
        'filter=${request.filter.name} '
        'hasSearch=${request.hasSearch} '
        'matrixError=${_safeMatrixError(matrixErrorCode)}';
  }

  static String joinOutcome({
    required ServerDiscoveryScope scope,
    required ServerDiscoveryEntry entry,
    required ServerDiscoveryJoinOutcome outcome,
    required String? matrixErrorCode,
  }) {
    return 'Server Discovery join outcome '
        'homeserver=${_hash(scope.homeserver)} '
        'room=${_hash(entry.roomId)} '
        'type=${entry.type.name} '
        'outcome=${outcome.name} '
        'matrixError=${_safeMatrixError(matrixErrorCode)}';
  }

  static String publicationOutcome({
    required ServerDiscoveryScope scope,
    required ServerDiscoveryPublicationTarget target,
    required ServerDiscoveryPublicationOutcome outcome,
    required String? matrixErrorCode,
  }) {
    return 'Server Discovery publication outcome '
        'homeserver=${_hash(scope.homeserver)} '
        'room=${_hash(target.identifier)} '
        'type=${target.type.name} '
        'outcome=${outcome.name} '
        'matrixError=${_safeMatrixError(matrixErrorCode)}';
  }

  static String _hash(String value) {
    final bytes = utf8.encode('$_processSalt:$value');
    return sha256.convert(bytes).toString().substring(0, 12);
  }

  static String _newProcessSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  static String _safeMatrixError(String? value) {
    if (value == null || value.isEmpty) {
      return 'none';
    }
    return value.replaceAll(RegExp(r'[^A-Z0-9_\.:-]'), '_');
  }
}
