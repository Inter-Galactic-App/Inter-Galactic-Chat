import 'dart:async';
import 'dart:ui';

import 'package:intergalactic/utils/mime.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_blurhash/flutter_blurhash.dart';

enum LODImageType { blurhash, thumbnail, fullres }

class LODImageProvider extends ImageProvider<String> {
  LODImageProvider({
    this.blurhash,
    this.loadThumbnail,
    this.loadFullRes,
    this.thumbnailHeight,
    required this.id,
    this.fullResHeight,
    this.autoLoadFullRes = true,
  });
  String id;
  String? blurhash;
  String? get mimeType => completer?.mimeType;
  bool autoLoadFullRes;
  Future<Uint8List?> Function()? loadThumbnail;
  Future<Uint8List?> Function()? loadFullRes;

  StreamController<void> _lodChangedController = StreamController.broadcast();

  Stream<void> get onLODChanged => _lodChangedController.stream;
  LODImageCompleter? completer;
  int? thumbnailHeight;
  int? fullResHeight;

  Future<bool> hasCachedFullres() async {
    return false;
  }

  Future<bool> hasCachedThumbnail() async {
    return false;
  }

  @override
  Future<String> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<String>(id);
  }

  @override
  void resolveStreamForKey(
    ImageConfiguration configuration,
    ImageStream stream,
    String key,
    ImageErrorListener handleError,
  ) {
    super.resolveStreamForKey(configuration, stream, key, handleError);

    completer = stream.completer as LODImageCompleter;
  }

  @override
  ImageStreamCompleter loadImage(String key, ImageDecoderCallback decode) {
    completer = LODImageCompleter(
      blurhash: blurhash,
      loadThumbnail: loadThumbnail,
      loadFullRes: loadFullRes,
      callback: decode,
      onLODChanged: () {
        _lodChangedController.add(null);
      },
      hasCachedFullres: hasCachedFullres,
      hasCachedThumbnail: hasCachedThumbnail,
      thumbnailHeight: thumbnailHeight,
      fullResHeight: fullResHeight,
      autoLoadFullres: autoLoadFullRes,
    );
    return completer!;
  }

  Future<void> fetchThumbnail() async {
    if (completer == null) {
      // Only the side effect is wanted: resolving through the image cache
      // creates the completer. The first frame itself is not awaited here,
      // and now that imageProviderToImage can complete with an error, an
      // unawaited call to it would surface that error nowhere.
      resolve(const ImageConfiguration());
    }

    await completer?.fetchThumbnail();
  }

  Future<void> fetchFullRes() async {
    if (completer == null) {
      resolve(const ImageConfiguration());
    }

    await completer?.fetchFullRes();
  }
}

class LODImageCompleter extends ImageStreamCompleter {
  String? blurhash;
  Future<bool> Function()? hasCachedThumbnail;
  Future<bool> Function()? hasCachedFullres;
  Future<Uint8List?> Function()? loadThumbnail;
  Future<Uint8List?> Function()? loadFullRes;
  Function()? onLODChanged;
  LODImageType? currentlyLoadedImage;
  final double _scale = 1;
  ImageInfo? currentImage;
  FrameInfo? _nextFrame;
  Codec? _codec;
  late Duration _shownTimestamp;
  ImageDecoderCallback callback;
  Duration? _frameDuration;
  bool _frameCallbackScheduled = false;
  bool autoLoadFullres;
  String? mimeType;
  int _framesEmitted = 0;
  int? thumbnailHeight;
  int? fullResHeight;
  double scale = 1;
  Timer? _timer;
  Future? fullResLoading = null;
  Future? thumbnailLoading = null;
  int _codecGeneration = 0;

  LODImageCompleter({
    this.blurhash,
    required this.callback,
    this.loadThumbnail,
    this.loadFullRes,
    this.hasCachedFullres,
    this.hasCachedThumbnail,
    this.thumbnailHeight,
    this.onLODChanged,
    this.fullResHeight,
    this.autoLoadFullres = true,
  }) {
    unawaited(loadImages());
  }

  Future<void> loadImages() async {
    final fullResCached = await _safeCacheProbe(
      hasCachedFullres,
      'while checking cached full resolution LOD image',
    );
    if (loadFullRes != null && autoLoadFullres && fullResCached) {
      unawaited(_loadFullRes());
      return;
    }

    final thumbnailCached = await _safeCacheProbe(
      hasCachedThumbnail,
      'while checking cached thumbnail LOD image',
    );
    if (loadThumbnail != null && thumbnailCached) {
      unawaited(_loadThumbnail());
      if (loadFullRes != null && autoLoadFullres) {
        unawaited(_loadFullRes());
      }
      return;
    }

    if (blurhash != null) unawaited(_loadBlurhash());
    if (loadThumbnail != null) unawaited(_loadThumbnail());
    if (loadFullRes != null && autoLoadFullres) unawaited(_loadFullRes());
  }

  Future<bool> _safeCacheProbe(
    Future<bool> Function()? probe,
    String context,
  ) async {
    if (probe == null) return false;
    try {
      return await probe();
    } catch (error, stackTrace) {
      _reportLoadError(context, error, stackTrace);
      return false;
    }
  }

  Future<void> _loadBlurhash() async {
    try {
      var image = await blurHashDecodeImage(
        blurHash: blurhash!,
        width: 10,
        height: 10,
      );

      if (currentlyLoadedImage == null) {
        currentlyLoadedImage = LODImageType.blurhash;
        setImage(ImageInfo(image: image));
      }

      onLODChanged?.call();
    } catch (error, stackTrace) {
      _reportLoadError('while loading a LOD image blurhash', error, stackTrace);
    }
  }

  Future<void> _loadThumbnail() async {
    if (thumbnailLoading != null) return thumbnailLoading;
    if (currentlyLoadedImage == LODImageType.thumbnail) return;
    if (currentlyLoadedImage == LODImageType.fullres) return;

    thumbnailLoading = () async {
      try {
        var bytes = await loadThumbnail!.call();
        if (bytes == null) return;

        mimeType = Mime.lookupType("", data: bytes);

        var codec = await callback(
          await ImmutableBuffer.fromUint8List(bytes),
          getTargetSize: (intrinsicWidth, intrinsicHeight) {
            return TargetImageSize(height: thumbnailHeight);
          },
        );

        await _setCodec(LODImageType.thumbnail, codec);
      } catch (error, stackTrace) {
        _reportLoadError(
          'while loading a LOD image thumbnail',
          error,
          stackTrace,
        );
      }
    }();

    try {
      await thumbnailLoading;
    } finally {
      thumbnailLoading = null;
      onLODChanged?.call();
    }
  }

  Future<void> fetchFullRes() async {
    return _loadFullRes();
  }

  Future<void> fetchThumbnail() async {
    return _loadThumbnail();
  }

  Future<void> _loadFullRes() async {
    if (fullResLoading != null) {
      return fullResLoading;
    }

    if (currentlyLoadedImage == LODImageType.fullres) {
      return;
    }

    if (loadFullRes == null) {
      return;
    }

    fullResLoading = () async {
      try {
        var bytes = await loadFullRes!.call();
        if (bytes == null) return;

        mimeType = Mime.lookupType("", data: bytes);
        var codec = await callback(
          await ImmutableBuffer.fromUint8List(bytes),
          getTargetSize: (intrinsicWidth, intrinsicHeight) {
            return TargetImageSize(height: fullResHeight);
          },
        );

        await _setCodec(LODImageType.fullres, codec);
      } catch (error, stackTrace) {
        _reportLoadError(
          'while loading a LOD image full resolution asset',
          error,
          stackTrace,
        );
      }
    }();

    try {
      await fullResLoading;
    } finally {
      fullResLoading = null;
      onLODChanged?.call();
    }
  }

  void _reportLoadError(String context, Object error, StackTrace stackTrace) {
    reportError(
      context: ErrorDescription(context),
      exception: error,
      stack: stackTrace,
      silent: true,
    );
  }

  Future<void> _setCodec(LODImageType type, Codec codec) async {
    _codecGeneration += 1;
    _timer?.cancel();
    _timer = null;
    _frameCallbackScheduled = false;
    _frameDuration = null;
    _framesEmitted = 0;
    _nextFrame?.image.dispose();
    _nextFrame = null;
    _codec = codec;
    await _decodeNextFrameAndSchedule(_codecGeneration);
    currentlyLoadedImage = type;
  }

  Future<void> _decodeNextFrameAndSchedule(int generation) async {
    try {
      final codec = _codec;
      if (generation != _codecGeneration || codec == null || !hasListeners) {
        return;
      }

      _nextFrame?.image.dispose();
      _nextFrame = null;

      final nextFrame = await codec.getNextFrame();
      if (generation != _codecGeneration || _codec != codec || !hasListeners) {
        nextFrame.image.dispose();
        return;
      }

      _nextFrame = nextFrame;

      _emitFrame(
        ImageInfo(
          image: _nextFrame!.image.clone(),
          scale: _scale,
          debugLabel: debugLabel,
        ),
      );

      if (codec.frameCount == 1) {
        _nextFrame!.image.dispose();
        _nextFrame = null;
        return;
      }

      _scheduleAppFrame(generation);
    } catch (error, stackTrace) {
      _timer?.cancel();
      _timer = null;
      _nextFrame?.image.dispose();
      _nextFrame = null;
      reportError(
        context: ErrorDescription('while decoding a LOD image frame'),
        exception: error,
        stack: stackTrace,
        silent: true,
      );
    }
  }

  void _scheduleAppFrame(int generation) {
    if (generation != _codecGeneration) {
      return;
    }
    if (_frameCallbackScheduled) {
      return;
    }
    _frameCallbackScheduled = true;
    SchedulerBinding.instance.scheduleFrameCallback(
      (timestamp) => _handleAppFrame(timestamp, generation),
    );
  }

  void _handleAppFrame(Duration timestamp, int generation) {
    _frameCallbackScheduled = false;
    if (generation != _codecGeneration || !hasListeners) {
      return;
    }
    final codec = _codec;
    final nextFrame = _nextFrame;
    if (codec == null || nextFrame == null) {
      return;
    }
    if (_isFirstFrame() || _hasFrameDurationPassed(timestamp)) {
      _emitFrame(
        ImageInfo(
          image: nextFrame.image.clone(),
          scale: _scale,
          debugLabel: debugLabel,
        ),
      );
      _shownTimestamp = timestamp;
      _frameDuration = nextFrame.duration;
      nextFrame.image.dispose();
      _nextFrame = null;
      final int completedCycles = _framesEmitted ~/ codec.frameCount;
      if (codec.repetitionCount == -1 ||
          completedCycles <= codec.repetitionCount) {
        unawaited(_decodeNextFrameAndSchedule(generation));
      }
      return;
    }
    final Duration delay = _frameDuration! - (timestamp - _shownTimestamp);
    _timer = Timer(delay * timeDilation, () {
      _scheduleAppFrame(generation);
    });
  }

  @override
  void addListener(ImageStreamListener listener) {
    final hadListeners = hasListeners;
    super.addListener(listener);
    if (!hadListeners &&
        _codec != null &&
        (currentImage == null || _codec!.frameCount > 1)) {
      unawaited(_decodeNextFrameAndSchedule(_codecGeneration));
    }
  }

  @override
  void removeListener(ImageStreamListener listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _timer?.cancel();
      _timer = null;
    }
  }

  bool _isFirstFrame() {
    return _frameDuration == null;
  }

  bool _hasFrameDurationPassed(Duration timestamp) {
    return timestamp - _shownTimestamp >= _frameDuration!;
  }

  void _emitFrame(ImageInfo imageInfo) {
    if (!hasListeners) return;
    setImage(imageInfo);
    _framesEmitted += 1;
  }
}
