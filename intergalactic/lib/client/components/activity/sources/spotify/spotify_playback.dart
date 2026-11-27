import 'package:intergalactic/client/components/activity/activity_models.dart';

enum SpotifyPlaybackState {
  unavailable,
  notConnected,
  noActiveDevice,
  deviceAvailable,
  privateSession,
  playing,
  paused,
  tokenExpired,
  unauthorized,
  rateLimited,
  error,
}

class SpotifyPlaybackSnapshot {
  const SpotifyPlaybackSnapshot({
    required this.state,
    this.trackName,
    this.artistName,
    this.albumName,
    this.artworkUrl,
    this.externalUrl,
    this.trackId,
    this.trackUri,
    this.isSaved,
    this.progressMs,
    this.durationMs,
    this.reason,
  });

  final SpotifyPlaybackState state;
  final String? trackName;
  final String? artistName;
  final String? albumName;
  final String? artworkUrl;
  final String? externalUrl;
  final String? trackId;
  final String? trackUri;
  final bool? isSaved;
  final int? progressMs;
  final int? durationMs;
  final String? reason;

  bool get hasPlayableItem =>
      trackName != null &&
      trackName!.trim().isNotEmpty &&
      (state == SpotifyPlaybackState.playing ||
          state == SpotifyPlaybackState.paused);

  UserActivity toActivity({
    bool playbackControlsEnabled = false,
    bool libraryControlsEnabled = false,
  }) {
    if (hasPlayableItem) {
      return UserActivity(
        id: 'spotify',
        kind: ActivityKind.music,
        provider: 'spotify',
        title: trackName!,
        subtitle: artistName,
        details: albumName,
        status: state == SpotifyPlaybackState.playing ? 'Listening' : 'Paused',
        artworkUrl: artworkUrl,
        externalUrl: externalUrl,
        visibility: ActivityVisibility.selfOnly,
        metadata: {
          if (progressMs != null) 'progress_ms': progressMs,
          if (durationMs != null) 'duration_ms': durationMs,
          if (trackId != null) 'track_id': trackId,
          if (_resolvedTrackUri != null) 'track_uri': _resolvedTrackUri,
          if (isSaved != null) 'is_saved': isSaved,
          'state': state.name,
        },
        controls: _controls(
          playbackControlsEnabled: playbackControlsEnabled,
          libraryControlsEnabled: libraryControlsEnabled,
        ),
      );
    }

    return UserActivity(
      id: 'spotify',
      kind: ActivityKind.music,
      provider: 'spotify',
      title: _titleForState(),
      details: reason,
      status: 'Spotify',
      visibility: ActivityVisibility.off,
      metadata: {'state': state.name},
    );
  }

  SpotifyPlaybackSnapshot copyWith({
    bool? isSaved,
  }) {
    return SpotifyPlaybackSnapshot(
      state: state,
      trackName: trackName,
      artistName: artistName,
      albumName: albumName,
      artworkUrl: artworkUrl,
      externalUrl: externalUrl,
      trackId: trackId,
      trackUri: trackUri,
      isSaved: isSaved ?? this.isSaved,
      progressMs: progressMs,
      durationMs: durationMs,
      reason: reason,
    );
  }

  String? get _resolvedTrackUri {
    final uri = trackUri;
    if (uri != null && uri.trim().isNotEmpty) {
      return uri;
    }

    final id = trackId;
    if (id == null || id.trim().isEmpty) {
      return null;
    }

    return 'spotify:track:$id';
  }

  String _titleForState() {
    return switch (state) {
      SpotifyPlaybackState.notConnected => 'Spotify not connected',
      SpotifyPlaybackState.noActiveDevice => 'No active Spotify device',
      SpotifyPlaybackState.deviceAvailable => 'Spotify ready',
      SpotifyPlaybackState.privateSession => 'Spotify unavailable',
      SpotifyPlaybackState.tokenExpired => 'Spotify token expired',
      SpotifyPlaybackState.unauthorized => 'Spotify authorization required',
      SpotifyPlaybackState.rateLimited => 'Spotify rate limited',
      SpotifyPlaybackState.error => 'Spotify error',
      SpotifyPlaybackState.unavailable => 'Spotify unavailable',
      SpotifyPlaybackState.playing => trackName ?? 'Spotify playing',
      SpotifyPlaybackState.paused => trackName ?? 'Spotify paused',
    };
  }

  List<ActivityControl> _controls({
    required bool playbackControlsEnabled,
    required bool libraryControlsEnabled,
  }) {
    final playbackState = playbackControlsEnabled
        ? ActivityControlState.available
        : ActivityControlState.disabled;
    final playbackTooltip = playbackControlsEnabled
        ? null
        : 'Reconnect Spotify to grant playback controls';
    final playPauseLabel =
        state == SpotifyPlaybackState.playing ? 'Pause' : 'Play';
    final playPauseAction =
        state == SpotifyPlaybackState.playing ? 'pause' : 'play';
    final controls = <ActivityControl>[
      ActivityControl(
        id: 'previous',
        kind: ActivityControlKind.previous,
        label: 'Previous',
        state: playbackState,
        tooltip: playbackTooltip,
      ),
      ActivityControl(
        id: 'play_pause',
        kind: ActivityControlKind.playPause,
        label: playPauseLabel,
        state: playbackState,
        tooltip: playbackTooltip,
        metadata: {'action': playPauseAction},
      ),
      ActivityControl(
        id: 'next',
        kind: ActivityControlKind.next,
        label: 'Next',
        state: playbackState,
        tooltip: playbackTooltip,
      ),
    ];

    final trackUri = _resolvedTrackUri;
    if (trackUri == null) {
      return controls;
    }

    final saved = isSaved == true;
    final libraryState = libraryControlsEnabled && isSaved != null
        ? ActivityControlState.available
        : ActivityControlState.disabled;
    final libraryTooltip = libraryControlsEnabled
        ? 'Spotify saved-track state is unavailable'
        : 'Reconnect Spotify to grant library controls';
    controls.add(
      ActivityControl(
        id: saved ? 'remove_saved_track' : 'save_track',
        kind: ActivityControlKind.like,
        label: saved ? 'Unlike' : 'Like',
        state: libraryState,
        tooltip: libraryState == ActivityControlState.available
            ? null
            : libraryTooltip,
        metadata: {
          'track_uri': trackUri,
          if (trackId != null) 'track_id': trackId,
          if (isSaved != null) 'is_saved': isSaved,
        },
      ),
    );

    return controls;
  }
}

class SpotifyPlaybackParser {
  const SpotifyPlaybackParser();

  SpotifyPlaybackSnapshot parseCurrentPlayback(Map<String, Object?> json) {
    final item = _map(json['item']);
    final device = _map(json['device']);
    if (device?['is_private_session'] == true) {
      return SpotifyPlaybackSnapshot(
        state: SpotifyPlaybackState.privateSession,
        reason: 'Spotify is in a private session on ${_deviceName(device)}.',
      );
    }

    if (item == null) {
      return SpotifyPlaybackSnapshot(
        state: device == null
            ? SpotifyPlaybackState.noActiveDevice
            : SpotifyPlaybackState.deviceAvailable,
        reason: device == null
            ? 'No Spotify playback state was returned.'
            : 'Spotify sees ${_deviceName(device)}, but no track is currently active.',
      );
    }

    final isPlaying = json['is_playing'] == true;
    final type = json['currently_playing_type'] as String?;
    if (type == 'ad' || type == 'unknown') {
      return SpotifyPlaybackSnapshot(
        state: SpotifyPlaybackState.privateSession,
        reason: 'Current playback type is $type.',
      );
    }

    final artists = _list(item['artists'])
        .map(_map)
        .whereType<Map<String, Object?>>()
        .map((artist) => artist['name'] as String?)
        .whereType<String>()
        .where((name) => name.trim().isNotEmpty)
        .toList(growable: false);
    final album = _map(item['album']);

    return SpotifyPlaybackSnapshot(
      state: isPlaying
          ? SpotifyPlaybackState.playing
          : SpotifyPlaybackState.paused,
      trackName: item['name'] as String?,
      artistName: artists.join(', '),
      albumName: album?['name'] as String?,
      artworkUrl: _largestImageUrl(_list(album?['images'])),
      externalUrl: _map(item['external_urls'])?['spotify'] as String?,
      trackId: type == 'track' ? item['id'] as String? : null,
      trackUri: type == 'track' ? item['uri'] as String? : null,
      progressMs: json['progress_ms'] as int?,
      durationMs: item['duration_ms'] as int?,
    );
  }

  SpotifyPlaybackSnapshot parseAvailableDevices(Map<String, Object?> json) {
    final devices = _list(json['devices'])
        .map(_map)
        .whereType<Map<String, Object?>>()
        .toList(growable: false);
    if (devices.isEmpty) {
      return const SpotifyPlaybackSnapshot(
        state: SpotifyPlaybackState.noActiveDevice,
        reason: 'Spotify did not report any available Spotify Connect devices.',
      );
    }

    Map<String, Object?>? activeDevice;
    for (final device in devices) {
      if (device['is_active'] == true) {
        activeDevice = device;
        break;
      }
    }
    final device = activeDevice ?? devices.first;
    if (device['is_private_session'] == true) {
      return SpotifyPlaybackSnapshot(
        state: SpotifyPlaybackState.privateSession,
        reason: 'Spotify is in a private session on ${_deviceName(device)}.',
      );
    }

    return SpotifyPlaybackSnapshot(
      state: SpotifyPlaybackState.deviceAvailable,
      reason: activeDevice == null
          ? 'Spotify sees ${_deviceName(device)}, but it is not active yet. Start playback in Spotify to activate it.'
          : 'Spotify is connected to ${_deviceName(device)}, but no track is currently active.',
    );
  }

  String? _largestImageUrl(List<Object?> images) {
    Map<String, Object?>? selected;
    for (final entry in images) {
      final image = _map(entry);
      if (image == null) {
        continue;
      }

      final currentWidth = selected?['width'] as int? ?? 0;
      final nextWidth = image['width'] as int? ?? 0;
      if (selected == null || nextWidth > currentWidth) {
        selected = image;
      }
    }

    return selected?['url'] as String?;
  }

  Map<String, Object?>? _map(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }

    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }

    return null;
  }

  List<Object?> _list(Object? value) {
    if (value is List) {
      return value.cast<Object?>();
    }

    return const [];
  }

  String _deviceName(Map<String, Object?>? device) {
    final name = device?['name'] as String?;
    if (name == null || name.trim().isEmpty) {
      return 'a Spotify device';
    }

    return name;
  }
}
