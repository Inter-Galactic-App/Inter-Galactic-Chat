import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class ScreenCaptureSourceWidget extends StatefulWidget {
  const ScreenCaptureSourceWidget(
    this.source,
    this.onThumbnailChanged, {
    required this.refreshThumbnailEvents,
    this.onTap,
    super.key,
  });
  final DesktopCapturerSource source;
  final Stream<DesktopCapturerSource> onThumbnailChanged;
  final Future<void> Function(SourceType type) refreshThumbnailEvents;
  final Function()? onTap;

  @override
  State<ScreenCaptureSourceWidget> createState() =>
      _ScreenCaptureSourceWidgetState();
}

class _ScreenCaptureSourceWidgetState extends State<ScreenCaptureSourceWidget> {
  static const int _maxThumbnailRetries = 8;

  late List<StreamSubscription> subs;
  Uint8List? thumbnailData = null;
  Timer? _thumbnailRetryTimer;
  int _thumbnailRetryAttempts = 0;
  bool _thumbnailLoadInFlight = false;
  bool _thumbnailUnavailable = false;

  @override
  void initState() {
    super.initState();

    // Read any thumbnail already populated on the source object.  getSources()
    // populates source.thumbnail inline from the native response, and
    // desktopSourceThumbnailChanged events mutate the source object before
    // firing the broadcast streams.  Both can arrive before this widget's
    // initState() has a chance to subscribe, so the stream events are missed,
    // but the source object is already up to date.
    thumbnailData = _validThumbnail(widget.source.thumbnail);
    _thumbnailUnavailable = false;

    subs = [
      widget.source.onThumbnailChanged.stream.listen((event) {
        if (!mounted) {
          return;
        }
        final thumbnail = _validThumbnail(event);
        if (thumbnail == null) {
          return;
        }
        setState(() {
          thumbnailData = thumbnail;
          _thumbnailUnavailable = false;
        });
      }),
      widget.onThumbnailChanged.listen((source) {
        if (source.id == widget.source.id) {
          if (!mounted) {
            return;
          }
          final thumbnail = _validThumbnail(source.thumbnail);
          if (thumbnail == null) {
            return;
          }
          setState(() {
            // Use = not ??= so that subsequent thumbnail refreshes are shown
            // even when thumbnailData is already non-null.
            thumbnailData = thumbnail;
            _thumbnailUnavailable = false;
          });
        }
      })
    ];

    if (thumbnailData == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduleThumbnailRetry(Duration.zero);
      });
    }
  }

  @override
  void didUpdateWidget(covariant ScreenCaptureSourceWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.id == widget.source.id) {
      return;
    }

    _thumbnailRetryTimer?.cancel();
    _thumbnailRetryAttempts = 0;
    _thumbnailLoadInFlight = false;
    thumbnailData = _validThumbnail(widget.source.thumbnail);
    _thumbnailUnavailable = false;
    if (thumbnailData == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduleThumbnailRetry(Duration.zero);
      });
    }
  }

  @override
  void dispose() {
    _thumbnailRetryTimer?.cancel();
    for (var sub in subs) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: tiamat.Tile.low(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: buildImage()),
                ),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: tiamat.Text.labelLow(widget.source.name),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildImage() {
    if (thumbnailData != null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Image.memory(
          thumbnailData!,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: _thumbnailUnavailable
              ? Icon(
                  widget.source.type == SourceType.Window
                      ? Icons.web_asset_outlined
                      : Icons.monitor_outlined,
                  size: 36,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )
              : const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
        ),
      ),
    );
  }

  Uint8List? _validThumbnail(Uint8List? data) {
    if (data == null || data.isEmpty) {
      return null;
    }
    return data;
  }

  void _scheduleThumbnailRetry(Duration delay) {
    if (!mounted ||
        thumbnailData != null ||
        _thumbnailLoadInFlight ||
        _thumbnailRetryAttempts >= _maxThumbnailRetries) {
      return;
    }

    _thumbnailRetryTimer?.cancel();
    _thumbnailRetryTimer = Timer(delay, _loadThumbnailFromCapturer);
  }

  Future<void> _loadThumbnailFromCapturer() async {
    if (!mounted ||
        thumbnailData != null ||
        _thumbnailLoadInFlight ||
        _thumbnailRetryAttempts >= _maxThumbnailRetries) {
      return;
    }

    _thumbnailLoadInFlight = true;
    _thumbnailRetryAttempts++;

    Uint8List? thumbnail;
    try {
      final rawThumbnail =
          await (desktopCapturer as dynamic).getThumbnail(widget.source);
      if (rawThumbnail is Uint8List) {
        thumbnail = _validThumbnail(rawThumbnail);
      }
    } catch (_) {
      // Some desktop capturer backends only update thumbnails through the
      // stream. Keep the picker usable when the direct refresh API is missing.
    } finally {
      _thumbnailLoadInFlight = false;
    }

    if (!mounted || thumbnailData != null) {
      return;
    }

    if (thumbnail != null) {
      setState(() {
        thumbnailData = thumbnail;
        _thumbnailUnavailable = false;
      });
      return;
    }

    await widget.refreshThumbnailEvents(widget.source.type);

    if (!mounted || thumbnailData != null) {
      return;
    }

    if (_thumbnailRetryAttempts >= _maxThumbnailRetries) {
      setState(() {
        _thumbnailUnavailable = true;
      });
      return;
    }

    setState(() {
      _thumbnailUnavailable = false;
    });
    final retryDelayMs =
        (250 * (_thumbnailRetryAttempts + 1)).clamp(250, 1500).toInt();
    _scheduleThumbnailRetry(Duration(milliseconds: retryDelayMs));
  }
}
