import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/debug/log.dart';

class SteamApiClient {
  SteamApiClient({
    http.Client? httpClient,
    SteamPlayerSummaryParser? parser,
    Duration requestTimeout = const Duration(seconds: 8),
  }) : _httpClient = httpClient ?? http.Client(),
       _parser = parser ?? const SteamPlayerSummaryParser(),
       _requestTimeout = requestTimeout;

  final http.Client _httpClient;
  final SteamPlayerSummaryParser _parser;
  final Duration _requestTimeout;

  Future<SteamPlayerSummary?> getPlayerSummary({
    required Uri endpoint,
    required String steamId,
  }) async {
    final requestedSteamId = steamId.trim();
    if (requestedSteamId.isEmpty) {
      return null;
    }

    http.Response response;
    try {
      response = await runZoned(
        () => _httpClient
            .get(
              endpoint.replace(
                queryParameters: {
                  ...endpoint.queryParameters,
                  'steamids': requestedSteamId,
                },
              ),
            )
            .timeout(_requestTimeout),
        zoneValues: {Log.handledOptionalNetworkRequestZoneKey: true},
      );
    } catch (error) {
      Log.d(
        'Optional Steam activity summary request failed for host '
        '${endpoint.host}: ${error.runtimeType}',
        category: LogCategory.app,
        source: 'steam-activity',
      );
      throw SteamActivityNetworkException(
        host: endpoint.host,
        errorType: error.runtimeType.toString(),
      );
    }

    if (response.statusCode != 200) {
      return null;
    }

    try {
      final decoded = jsonDecode(response.body);
      SteamPlayerSummary? summary;
      if (decoded is Map<String, Object?>) {
        summary = _parser.parse(decoded);
      } else if (decoded is Map) {
        summary = _parser.parse(_objectMap(decoded));
      }
      return summary?.steamId == requestedSteamId ? summary : null;
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to parse Steam player summary',
        category: LogCategory.app,
        source: 'steam-activity',
      );
      return null;
    }
  }
}

class SteamActivityNetworkException implements Exception {
  const SteamActivityNetworkException({
    required this.host,
    required this.errorType,
  });

  final String host;
  final String errorType;

  @override
  String toString() {
    return 'Steam activity network request failed host=$host error=$errorType';
  }
}

class SteamPlayerSummary {
  const SteamPlayerSummary({
    required this.steamId,
    this.personaName,
    this.profileUrl,
    this.avatarUrl,
    this.communityVisibilityState,
    this.gameId,
    this.gameExtraInfo,
    this.gameIconUrl,
    this.gameArtworkUrl,
  });

  final String steamId;
  final String? personaName;
  final String? profileUrl;
  final String? avatarUrl;
  final int? communityVisibilityState;
  final String? gameId;
  final String? gameExtraInfo;
  final String? gameIconUrl;
  final String? gameArtworkUrl;

  bool get isPlayingGame => _hasText(gameId) && _hasText(gameExtraInfo);

  UserActivity? toActivity() {
    if (!isPlayingGame) {
      return null;
    }

    final appId = gameId!.trim();
    final gameTitle = gameExtraInfo!.trim();
    final iconUrl = _validAbsoluteUrl(gameIconUrl);
    final providerArtworkUrl = _validAbsoluteUrl(gameArtworkUrl);
    final artworkUrl =
        iconUrl ?? providerArtworkUrl ?? _steamAppArtworkUrl(appId);
    final metadata = <String, Object?>{
      'steam_id': steamId,
      'app_id': appId,
      'artwork_url': artworkUrl,
      if (iconUrl != null) 'game_icon_url': iconUrl,
      if (providerArtworkUrl != null) 'game_artwork_url': providerArtworkUrl,
      if (_hasText(personaName)) 'persona_name': personaName!.trim(),
      if (_hasText(profileUrl)) 'profile_url': profileUrl!.trim(),
      if (communityVisibilityState != null)
        'community_visibility_state': communityVisibilityState,
    };

    return UserActivity(
      id: 'steam',
      kind: ActivityKind.game,
      provider: 'steam',
      title: gameTitle,
      subtitle: 'Steam',
      status: 'Playing',
      artworkUrl: artworkUrl,
      externalUrl: 'https://store.steampowered.com/app/$appId',
      visibility: ActivityVisibility.selfOnly,
      metadata: metadata,
    );
  }

  static bool _hasText(String? value) =>
      value != null && value.trim().isNotEmpty;
}

String _steamAppArtworkUrl(String appId) =>
    'https://cdn.cloudflare.steamstatic.com/steam/apps/$appId/capsule_sm_120.jpg';

String? _validAbsoluteUrl(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      uri.host.isEmpty ||
      (uri.scheme != 'http' && uri.scheme != 'https')) {
    return null;
  }

  return trimmed;
}

class SteamPlayerSummaryParser {
  const SteamPlayerSummaryParser();

  SteamPlayerSummary? parse(Map<String, Object?> json) {
    final response = _map(json['response']);
    final players = response?['players'];
    if (players is! List || players.isEmpty) {
      return null;
    }

    final player = _map(players.first);
    if (player == null) {
      return null;
    }

    final steamId = _string(player['steamid']);
    if (steamId == null || steamId.trim().isEmpty) {
      return null;
    }

    return SteamPlayerSummary(
      steamId: steamId.trim(),
      personaName: _string(player['personaname']),
      profileUrl: _string(player['profileurl']),
      avatarUrl: _string(player['avatarfull']),
      communityVisibilityState: _int(player['communityvisibilitystate']),
      gameId: _string(player['gameid']),
      gameExtraInfo: _string(player['gameextrainfo']),
      gameIconUrl: _firstString(player, const [
        'game_icon_url',
        'game_square_icon_url',
        'icon_url',
        'square_icon_url',
      ]),
      gameArtworkUrl: _firstString(player, const [
        'game_artwork_url',
        'game_thumbnail_url',
        'artwork_url',
        'thumbnail_url',
        'gameimage',
      ]),
    );
  }

  Map<String, Object?>? _map(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }

    if (value is Map) {
      return _objectMap(value);
    }

    return null;
  }

  String? _string(Object? value) {
    if (value is String) {
      return value;
    }

    return value?.toString();
  }

  int? _int(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is String) {
      return int.tryParse(value);
    }

    return null;
  }

  String? _firstString(Map<String, Object?> json, List<String> keys) {
    for (final key in keys) {
      final value = _string(json[key])?.trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }

    return null;
  }
}

Map<String, Object?> _objectMap(Map value) {
  return value.map((key, value) => MapEntry(key.toString(), value));
}
