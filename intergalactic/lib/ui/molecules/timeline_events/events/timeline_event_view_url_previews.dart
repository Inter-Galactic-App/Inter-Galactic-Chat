import 'dart:async';

import 'package:intergalactic/client/components/url_preview/url_preview_component.dart';
import 'package:intergalactic/client/timeline.dart';
import 'package:intergalactic/diagnostic/benchmark_values.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_event_layout.dart';
import 'package:intergalactic/ui/molecules/url_preview_widget.dart';
import 'package:intergalactic/utils/links/link_utils.dart';
import 'package:flutter/material.dart';

class TimelineEventViewUrlPreviews extends StatefulWidget {
  const TimelineEventViewUrlPreviews(
      {required this.initialIndex,
      required this.timeline,
      required this.component,
      this.bubbleMessages = false,
      this.alignRight = false,
      super.key});

  final int initialIndex;
  final Timeline timeline;
  final UrlPreviewComponent component;
  final bool bubbleMessages;
  final bool alignRight;

  @override
  State<TimelineEventViewUrlPreviews> createState() =>
      _TimelineEventViewUrlPreviewsState();
}

class _TimelineEventViewUrlPreviewsState
    extends State<TimelineEventViewUrlPreviews>
    implements TimelineEventViewWidget {
  UrlPreviewData? data;
  bool loading = false;
  int _requestGeneration = 0;
  int _currentIndex = 0;
  final Set<String> _attemptedImageRefreshKeys = <String>{};

  GlobalKey key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    BenchmarkValues.numTimelineUrlPreviewBuilt += 1;

    if (data == UrlPreviewComponent.invalidPreviewData) {
      return const SizedBox.shrink();
    }

    if (data == null) {
      if (!loading) {
        return const SizedBox.shrink();
      }

      return Padding(
        padding: EdgeInsets.fromLTRB(
          widget.alignRight ? 40 : 0,
          2,
          widget.alignRight ? 0 : 40,
          2,
        ),
        child: UrlPreviewWidget(
          null,
          messageBubbleMode: widget.bubbleMessages,
          alignRight: widget.alignRight,
        ),
      );
    }

    final previewData = data;
    if (previewData == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.alignRight ? 40 : 0,
        2,
        widget.alignRight ? 0 : 40,
        2,
      ),
      child: UrlPreviewWidget(
        key: key,
        previewData,
        messageBubbleMode: widget.bubbleMessages,
        alignRight: widget.alignRight,
        onImageError: (_, __) {
          _handlePreviewImageError(previewData);
        },
        onTap: () {
          LinkUtils.open(previewData.uri, context: context);
        },
      ),
    );
  }

  @override
  void update(int newIndex) {
    setStateFromIndex(newIndex);
  }

  @override
  void initState() {
    setStateFromIndex(widget.initialIndex);
    super.initState();
  }

  void setStateFromIndex(int index) {
    _currentIndex = index;
    _attemptedImageRefreshKeys.clear();
    final requestGeneration = ++_requestGeneration;
    var event = widget.timeline.events[index];
    var cachedData = widget.component.getCachedPreview(widget.timeline, event);

    if (cachedData != null) {
      setState(() {
        loading = false;
        data = cachedData;
        key = GlobalKey();
      });
    } else {
      final isSynced = event.status == TimelineEventStatus.synced;
      setState(() {
        loading = isSynced;
        data = null;
      });

      if (isSynced) {
        widget.component.getPreview(widget.timeline, event).then(
          (value) async {
            if (mounted && requestGeneration == _requestGeneration) {
              final image = value?.image;
              if (image != null && context.mounted) {
                unawaited(precacheImage(image, context).catchError((_) {}));
              }

              if (mounted && requestGeneration == _requestGeneration) {
                final wasAttachedToBottom = _isAttachedToBottom();
                setState(() {
                  loading = false;
                  data = value;
                  key = GlobalKey();
                });
                _keepBottomAttachedAfterPreviewResizes(wasAttachedToBottom);
              }
            }
          },
        );
      }
    }
  }

  void _handlePreviewImageError(
    UrlPreviewData previewData,
  ) {
    final key = _previewImageFailureKey(previewData);
    if (key == null || !_attemptedImageRefreshKeys.add(key)) {
      return;
    }

    unawaited(_refreshPreviewAfterImageFailure(previewData));
  }

  Future<void> _refreshPreviewAfterImageFailure(
    UrlPreviewData previewData,
  ) async {
    if (_currentIndex < 0 || _currentIndex >= widget.timeline.events.length) {
      return;
    }

    final event = widget.timeline.events[_currentIndex];
    final requestGeneration = ++_requestGeneration;
    final refreshed = await widget.component.refreshPreviewAfterImageFailure(
      widget.timeline,
      event,
      previewData,
    );

    if (!mounted || requestGeneration != _requestGeneration) {
      return;
    }

    var nextData =
        refreshed == null ? _withoutPreviewImage(previewData) : refreshed;
    final image = nextData.image;
    if (image != null && context.mounted) {
      try {
        await precacheImage(image, context);
      } catch (_) {
        nextData = _withoutPreviewImage(nextData);
      }
    }

    if (!mounted || requestGeneration != _requestGeneration) {
      return;
    }

    final wasAttachedToBottom = _isAttachedToBottom();
    setState(() {
      loading = false;
      data = nextData;
      key = GlobalKey();
    });
    _keepBottomAttachedAfterPreviewResizes(wasAttachedToBottom);
  }

  String? _previewImageFailureKey(UrlPreviewData previewData) {
    return previewData.imageUri?.toString() ?? previewData.image?.toString();
  }

  UrlPreviewData _withoutPreviewImage(UrlPreviewData data) {
    return UrlPreviewData(
      data.uri,
      siteName: data.siteName,
      title: data.title,
      description: data.description,
      postingAccount: data.postingAccount,
      stats: data.stats,
    );
  }

  bool _isAttachedToBottom() {
    final position = Scrollable.maybeOf(context)?.position;
    if (position == null || !position.hasPixels) {
      return false;
    }

    return position.pixels - position.minScrollExtent < 50;
  }

  void _keepBottomAttachedAfterPreviewResizes(bool wasAttachedToBottom) {
    if (!wasAttachedToBottom) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final position = Scrollable.maybeOf(context)?.position;
      if (position == null || !position.hasPixels) {
        return;
      }

      position.animateTo(
        position.minScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }
}
