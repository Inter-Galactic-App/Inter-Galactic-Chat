import 'dart:async';
import 'dart:math';

import 'package:intergalactic/ui/organisms/call_view/screen_capture_source_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class ScreenCaptureSourceSelection {
  const ScreenCaptureSourceSelection({
    required this.source,
    required this.shareAudio,
  });

  final DesktopCapturerSource source;
  final bool shareAudio;
}

class ScreenCaptureSourceDialog extends StatefulWidget {
  const ScreenCaptureSourceDialog(this.sources, this.onThumbnailChanged,
      {super.key});
  final List<DesktopCapturerSource> sources;
  final Stream<DesktopCapturerSource> onThumbnailChanged;

  @override
  State<ScreenCaptureSourceDialog> createState() =>
      _ScreenCaptureSourceDialogState();
}

class _ScreenCaptureSourceDialogState extends State<ScreenCaptureSourceDialog> {
  final ScreenCaptureThumbnailRefreshGate _thumbnailRefreshGate =
      ScreenCaptureThumbnailRefreshGate();
  bool shareAudio = true;

  @override
  void dispose() {
    _thumbnailRefreshGate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = min(700.0, screenSize.width * 0.9);
    final dialogHeight = min(700.0, screenSize.height * 0.9);
    final screens =
        widget.sources.where((s) => s.type == SourceType.Screen).toList();
    final windows =
        widget.sources.where((s) => s.type == SourceType.Window).toList();

    return DefaultTabController(
      length: 2,
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            TabBar(
              tabs: const [
                Tab(text: 'Share Window'),
                Tab(text: 'Share Screen'),
              ],
            ),
            SwitchListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              value: shareAudio,
              title: const Text('Share audio'),
              onChanged: (value) {
                setState(() {
                  shareAudio = value;
                });
              },
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _SourceGrid(
                    windows,
                    widget.onThumbnailChanged,
                    refreshThumbnailEvents: _thumbnailRefreshGate.refresh,
                    shareAudio: shareAudio,
                  ),
                  _SourceGrid(
                    screens,
                    widget.onThumbnailChanged,
                    refreshThumbnailEvents: _thumbnailRefreshGate.refresh,
                    shareAudio: shareAudio,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceGrid extends StatelessWidget {
  const _SourceGrid(
    this.sources,
    this.onThumbnailChanged, {
    required this.refreshThumbnailEvents,
    required this.shareAudio,
  });

  final List<DesktopCapturerSource> sources;
  final Stream<DesktopCapturerSource> onThumbnailChanged;
  final Future<void> Function(SourceType type) refreshThumbnailEvents;
  final bool shareAudio;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) {
      return const Center(
        child: Text('No sources available'),
      );
    }

    return SingleChildScrollView(
      child: MasonryGridView.count(
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        physics: const NeverScrollableScrollPhysics(),
        addAutomaticKeepAlives: false,
        crossAxisCount: 2,
        shrinkWrap: true,
        itemCount: sources.length,
        itemBuilder: (context, index) {
          return ScreenCaptureSourceWidget(
            sources[index],
            onThumbnailChanged,
            refreshThumbnailEvents: refreshThumbnailEvents,
            onTap: () => Navigator.of(context).pop(
              ScreenCaptureSourceSelection(
                source: sources[index],
                shareAudio: shareAudio,
              ),
            ),
          );
        },
      ),
    );
  }
}

class ScreenCaptureThumbnailRefreshGate {
  static const Duration _coalesceWindow = Duration(milliseconds: 500);

  final Map<SourceType, Future<void>> _refreshes = {};
  final Map<SourceType, Timer> _releaseTimers = {};
  bool _disposed = false;

  Future<void> refresh(SourceType type) {
    if (_disposed) {
      return Future.value();
    }

    final existing = _refreshes[type];
    if (existing != null) {
      return existing;
    }

    _releaseTimers.remove(type)?.cancel();
    late final Future<void> refreshTask;
    refreshTask = _refreshSourceType(type).whenComplete(() {
      if (_disposed) {
        _refreshes.remove(type);
        return;
      }

      _releaseTimers[type] = Timer(_coalesceWindow, () {
        if (identical(_refreshes[type], refreshTask)) {
          _refreshes.remove(type);
        }
        _releaseTimers.remove(type);
      });
    });
    _refreshes[type] = refreshTask;
    return refreshTask;
  }

  Future<void> _refreshSourceType(SourceType _) async {
    try {
      // flutter_webrtc's desktop bridge replaces its native source cache on
      // each update. Refresh both desktop source families so thumbnail retries
      // cannot evict screens before the user selects one to publish.
      await desktopCapturer.updateSources(
        types: const [SourceType.Window, SourceType.Screen],
      );
    } catch (_) {
      // Some backends only expose direct thumbnail refreshes. The retry loop
      // handles either path without blocking source selection.
    }
  }

  void dispose() {
    _disposed = true;
    for (final timer in _releaseTimers.values) {
      timer.cancel();
    }
    _releaseTimers.clear();
    _refreshes.clear();
  }
}
