import 'dart:async';
import 'dart:typed_data';

import 'package:intergalactic/cache/file_provider.dart';
import 'package:flutter/material.dart';

class VideoPlayerController {
  bool _disposed = false;

  Future<void> Function()? _onPause;

  Future<void> Function()? _onPlay;

  Future<void> Function()? _onReplay;

  Future<void> Function(Duration percent)? _seekTo;

  Future<void> Function(double volume)? _setVolume;

  Future<Uint8List?> Function()? _screenshot;

  Future<Size?> Function()? _getSize;

  Future<Duration> Function()? _getLength;

  final StreamController<bool> _isBuffering = StreamController.broadcast();

  final StreamController<DownloadProgress> _downloadProgress =
      StreamController.broadcast();

  final StreamController<bool> _isCompleted = StreamController.broadcast();

  final StreamController<Duration> _onProgressed = StreamController.broadcast();

  final StreamController<Object> _errors = StreamController.broadcast();

  final StreamController<void> _ready = StreamController.broadcast();

  Stream<bool> get isBuffering => _isBuffering.stream;

  Stream<bool> get isCompleted => _isCompleted.stream;

  Stream<void> get ready => _ready.stream;

  Stream<Duration> get onProgressed => _onProgressed.stream;

  Stream<DownloadProgress> get onDownloadProgressed => _downloadProgress.stream;

  Stream<Object> get errors => _errors.stream;

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _onPause = null;
    _onPlay = null;
    _onReplay = null;
    _seekTo = null;
    _setVolume = null;
    _screenshot = null;
    _getSize = null;
    _getLength = null;
    await Future.wait([
      _isBuffering.close(),
      _downloadProgress.close(),
      _isCompleted.close(),
      _onProgressed.close(),
      _errors.close(),
      _ready.close(),
    ]);
  }

  void attach(
      {required Future<void> Function() pause,
      required Future<void> Function() play,
      required Future<void> Function() replay,
      required Future<Duration> Function() getLength,
      required Future<Size?> Function() getSize,
      Future<Uint8List?> Function()? screenshot,
      Future<void> Function(double volume)? setVolume,
      required Future<void> Function(Duration percent) seekTo}) {
    _onPause = pause;
    _onPlay = play;
    _onReplay = replay;
    _seekTo = seekTo;
    _setVolume = setVolume;
    _getLength = getLength;
    _screenshot = screenshot;
    _getSize = getSize;
  }

  Future<void> pause() async {
    final onPause = _onPause;
    if (_disposed || onPause == null) {
      return;
    }
    await onPause.call();
  }

  Future<void> play() async {
    final onPlay = _onPlay;
    if (_disposed || onPlay == null) {
      return;
    }
    await onPlay.call();
  }

  Future<void> replay() async {
    final onReplay = _onReplay;
    if (_disposed || onReplay == null) {
      return;
    }
    await onReplay.call();
  }

  Future<void> seekTo(Duration duration) async {
    final seekTo = _seekTo;
    if (_disposed || seekTo == null) {
      return;
    }
    await seekTo.call(duration);
  }

  Future<void> setVolume(double volume) async {
    final setVolume = _setVolume;
    if (_disposed || setVolume == null) {
      return;
    }
    await setVolume.call(volume);
  }

  Future<Uint8List?> screenshot() async {
    final screenshot = _screenshot;
    if (_disposed || screenshot == null) {
      return null;
    }
    return screenshot.call();
  }

  void setBuffering(bool isBuffering) {
    if (_disposed || _isBuffering.isClosed) {
      return;
    }
    _isBuffering.add(isBuffering);
  }

  void setBufferingProgress(DownloadProgress progress) {
    if (_disposed || _downloadProgress.isClosed) {
      return;
    }
    _downloadProgress.add(progress);
  }

  void setCompleted(bool isBuffering) {
    if (_disposed || _isCompleted.isClosed) {
      return;
    }
    _isCompleted.add(isBuffering);
  }

  void setProgress(Duration progress) {
    if (_disposed || _onProgressed.isClosed) {
      return;
    }
    _onProgressed.add(progress);
  }

  void setError(Object error) {
    if (_disposed || _errors.isClosed) {
      return;
    }
    _errors.add(error);
  }

  void setReady() {
    if (_disposed || _ready.isClosed) {
      return;
    }
    _ready.add(null);
  }

  Future<Duration> getLength() async {
    final getLength = _getLength;
    if (_disposed || getLength == null) {
      return Duration.zero;
    }
    return await getLength.call();
  }

  Future<Size?> getSize() async {
    final getSize = _getSize;
    if (_disposed || getSize == null) {
      return null;
    }
    return await getSize.call();
  }
}
