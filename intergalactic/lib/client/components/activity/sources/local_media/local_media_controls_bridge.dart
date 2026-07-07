import 'package:flutter/services.dart';
import 'package:intergalactic/config/platform_utils.dart';

enum LocalMediaPlaybackState {
  unsupported,
  stopped,
  playing,
  paused,
  interrupted,
  seekingForward,
  seekingBackward,
  unknown,
}

extension LocalMediaPlaybackStateJson on LocalMediaPlaybackState {
  static LocalMediaPlaybackState fromJson(String? value) {
    return switch (value) {
      'stopped' => LocalMediaPlaybackState.stopped,
      'playing' => LocalMediaPlaybackState.playing,
      'paused' => LocalMediaPlaybackState.paused,
      'interrupted' => LocalMediaPlaybackState.interrupted,
      'seeking_forward' => LocalMediaPlaybackState.seekingForward,
      'seeking_backward' => LocalMediaPlaybackState.seekingBackward,
      'unsupported' => LocalMediaPlaybackState.unsupported,
      _ => LocalMediaPlaybackState.unknown,
    };
  }
}

class LocalMediaPlaybackSnapshot {
  const LocalMediaPlaybackSnapshot({
    required this.supported,
    required this.state,
    this.title,
    this.artist,
    this.album,
    this.artworkUrl,
    this.authorizationStatus,
    this.durationMs,
  });

  const LocalMediaPlaybackSnapshot.unsupported()
      : supported = false,
        state = LocalMediaPlaybackState.unsupported,
        title = null,
        artist = null,
        album = null,
        artworkUrl = null,
        authorizationStatus = null,
        durationMs = null;

  final bool supported;
  final LocalMediaPlaybackState state;
  final String? title;
  final String? artist;
  final String? album;
  final String? artworkUrl;
  final String? authorizationStatus;
  final int? durationMs;

  bool get hasPlayableItem =>
      supported &&
      (state == LocalMediaPlaybackState.playing ||
          state == LocalMediaPlaybackState.paused);

  static LocalMediaPlaybackSnapshot fromMap(Map<String, Object?> data) {
    return LocalMediaPlaybackSnapshot(
      supported: data['supported'] == true,
      state: LocalMediaPlaybackStateJson.fromJson(data['state'] as String?),
      title: _string(data['title']),
      artist: _string(data['artist']),
      album: _string(data['album']),
      artworkUrl: _string(data['artwork_url']),
      authorizationStatus: _string(data['authorization_status']),
      durationMs: _int(data['duration_ms']),
    );
  }

  static String? _string(Object? value) {
    if (value == null) {
      return null;
    }

    final string = value.toString().trim();
    return string.isEmpty ? null : string;
  }

  static int? _int(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.round();
    }

    return int.tryParse(value?.toString() ?? '');
  }
}

enum LocalMediaControlAction {
  play,
  pause,
  togglePlayPause,
  skipPrevious,
  skipNext,
}

extension LocalMediaControlActionMethod on LocalMediaControlAction {
  String get methodName {
    return switch (this) {
      LocalMediaControlAction.play => 'play',
      LocalMediaControlAction.pause => 'pause',
      LocalMediaControlAction.togglePlayPause => 'togglePlayPause',
      LocalMediaControlAction.skipPrevious => 'skipPrevious',
      LocalMediaControlAction.skipNext => 'skipNext',
    };
  }
}

class LocalMediaControlsBridge {
  LocalMediaControlsBridge({
    MethodChannel? channel,
    bool Function()? isSupportedPlatform,
  })  : _channel = channel ??
            const MethodChannel(
              'chat.intergalactic.app/local_media_controls',
            ),
        _isSupportedPlatform =
            isSupportedPlatform ?? (() => PlatformUtils.isIOS);

  final MethodChannel _channel;
  final bool Function() _isSupportedPlatform;

  bool get supportedPlatform => _isSupportedPlatform();

  Future<String?> requestAuthorization() async {
    if (!supportedPlatform) {
      return null;
    }

    try {
      return await _channel.invokeMethod<String>('requestAuthorization');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<LocalMediaPlaybackSnapshot> getSnapshot() async {
    if (!supportedPlatform) {
      return const LocalMediaPlaybackSnapshot.unsupported();
    }

    try {
      final result = await _channel.invokeMethod<Object?>('getSnapshot');
      final data = _normalizeMap(result);
      if (data == null) {
        return const LocalMediaPlaybackSnapshot.unsupported();
      }

      return LocalMediaPlaybackSnapshot.fromMap(data);
    } on MissingPluginException {
      return const LocalMediaPlaybackSnapshot.unsupported();
    } on PlatformException {
      return const LocalMediaPlaybackSnapshot.unsupported();
    }
  }

  Future<bool> execute(LocalMediaControlAction action) async {
    if (!supportedPlatform) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>(action.methodName) == true;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Map<String, Object?>? _normalizeMap(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }

    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }

    return null;
  }
}
