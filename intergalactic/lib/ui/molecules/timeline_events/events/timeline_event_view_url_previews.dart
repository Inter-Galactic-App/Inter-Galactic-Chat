import 'dart:async';

import 'package:intergalactic/client/components/url_preview/url_preview_component.dart';
import 'package:intergalactic/client/components/url_preview/url_preview_utils.dart';
import 'package:intergalactic/client/timeline.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/diagnostic/benchmark_values.dart';
import 'package:intergalactic/ui/molecules/url_preview_widget.dart';
import 'package:intergalactic/utils/links/link_utils.dart';
import 'package:flutter/material.dart';

class TimelineEventViewUrlPreviews extends StatefulWidget {
  const TimelineEventViewUrlPreviews({
    required this.index,
    required this.timeline,
    required this.component,
    this.bubbleMessages = false,
    this.alignRight = false,
    this.bubbleColor,
    this.onPreviewVisibilityChanged,
    this.updateRevision = 0,
    super.key,
  });

  final int index;

  /// Bumped by the owning timeline entry whenever the event at [index] is
  /// refreshed in place. The index alone cannot say "same row, changed event".
  final int updateRevision;
  final Timeline timeline;
  final UrlPreviewComponent component;
  final bool bubbleMessages;
  final bool alignRight;
  final Color? bubbleColor;
  final ValueChanged<bool>? onPreviewVisibilityChanged;

  @override
  State<TimelineEventViewUrlPreviews> createState() =>
      _TimelineEventViewUrlPreviewsState();
}

class _TimelineEventViewUrlPreviewsState
    extends State<TimelineEventViewUrlPreviews> {
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
          bubbleColor: widget.bubbleColor,
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
        bubbleColor: widget.bubbleColor,
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
  void initState() {
    setStateFromIndex(widget.index);
    super.initState();
  }

  @override
  void didUpdateWidget(TimelineEventViewUrlPreviews oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index ||
        widget.timeline != oldWidget.timeline) {
      setStateFromIndex(widget.index);
    } else if (widget.updateRevision != oldWidget.updateRevision) {
      refreshSameEvent(widget.index);
    }
  }

  /// This row now shows a different event. Everything starts over, including
  /// which preview images have already had their one refresh attempt.
  void setStateFromIndex(int index) {
    _currentIndex = index;
    _attemptedImageRefreshKeys.clear();
    // Anything still in flight was for the previous event.
    _requestGeneration++;

    // The index the entry handed over can be stale by the time this runs: a
    // redaction removes an event and this row is rebuilt before it is given a
    // new index. There is no event to preview, so show none - keeping the
    // previous one would attach a preview to a message that is not there.
    if (index < 0 || index >= widget.timeline.events.length) {
      setState(() {
        loading = false;
        data = null;
      });
      return;
    }

    final event = widget.timeline.events[index];
    final cachedData = widget.component.getCachedPreview(
      widget.timeline,
      event,
    );

    if (cachedData != null) {
      setState(() {
        loading = false;
        data = cachedData;
        key = GlobalKey();
      });
      return;
    }

    setState(() {
      loading = false;
      data = null;
    });
    _startPreviewRequest(event);
  }

  /// Same row, same event, but the event was replaced in place: a local echo
  /// that synced, an edit, a redaction.
  ///
  /// The BUG-298 refactor lost this path. [_startPreviewRequest] is gated on
  /// the event being synced, and a sender's own message is mounted here while
  /// it is still `sending`, so the preview for your own link was never
  /// requested until the room was reopened. The imperative `update()` cascade
  /// used to re-run [setStateFromIndex] on every change; a `didUpdateWidget`
  /// that compares only the index cannot see one.
  ///
  /// Deliberately NOT [setStateFromIndex]. Room updates arrive many times a
  /// minute in a busy room - a typing notification is one - and each reaches
  /// here through the entry's revision bump. Restarting the request on every
  /// one would discard the result in flight, and handing out a fresh
  /// [GlobalKey] would re-inflate the preview image each time, which is what
  /// dropped images look like.
  void refreshSameEvent(int index) {
    _currentIndex = index;
    // Unlike setStateFromIndex this path does not clear on an unresolvable
    // index. It runs on every revision bump - many a minute in a busy room -
    // and its whole contract is to leave the row alone unless the event it
    // already shows has something new. Nothing to re-read is nothing to do.
    if (loading || index < 0 || index >= widget.timeline.events.length) {
      return;
    }

    final event = widget.timeline.events[index];
    final cachedData = widget.component.getCachedPreview(
      widget.timeline,
      event,
    );

    if (cachedData != null) {
      if (identical(cachedData, data)) {
        return;
      }
      setState(() {
        data = cachedData;
        key = GlobalKey();
      });
      return;
    }

    // `data` can hold UrlPreviewComponent.invalidPreviewData - the FAILURE
    // sentinel, assigned above by an earlier revision bump while
    // the component's own invalid-cache TTL had not yet expired. That is not
    // "a preview is on screen" in the sense the comment below means, and
    // treating it as one meant this row never retried a failed link once the
    // sentinel expired: getCachedPreview then returns null (the TTL is gone
    // on the component's side too), this check saw a non-null `data` and kept
    // it forever, and only a full remount (setStateFromIndex) ever tried
    // again.
    if (data != null && data != UrlPreviewComponent.invalidPreviewData) {
      // A real preview is on screen and nothing is cached for it any more.
      // Keep it: an image failure is handled by
      // _refreshPreviewAfterImageFailure, and this is not that.
      return;
    }

    _startPreviewRequest(event);
  }

  void _startPreviewRequest(TimelineEvent event) {
    if (event.status != TimelineEventStatus.synced) {
      return;
    }

    final requestGeneration = ++_requestGeneration;
    setState(() {
      loading = true;
      data = null;
    });

    widget.component
        .getPreview(widget.timeline, event)
        .then((value) async {
          if (!mounted || requestGeneration != _requestGeneration) {
            return;
          }

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
            _reportPreviewVisibility(value);
            _keepBottomAttachedAfterPreviewResizes(wasAttachedToBottom);
          }
        })
        .catchError((Object error, StackTrace stackTrace) {
          // `refreshSameEvent` skips a row while `loading` is set, so a
          // rejected request that left it set would ignore every later
          // revision bump and spin forever. The old imperative cascade
          // retried on every change; this path is that retry. `data` stays
          // null so the next revision can request again.
          Log.onError(
            error,
            stackTrace,
            content: 'Failed to load a timeline URL preview',
            category: LogCategory.media,
            source: 'url-preview',
          );
          if (mounted && requestGeneration == _requestGeneration) {
            setState(() {
              loading = false;
            });
            _reportPreviewVisibility(null);
          }
        });
  }

  void _handlePreviewImageError(UrlPreviewData previewData) {
    final key = _previewImageFailureKey(previewData);
    if (key == null || !_attemptedImageRefreshKeys.add(key)) {
      // A repeat for an image already refreshed once is deliberate, but it
      // used to be silent, so a capture showed the error and no refresh and
      // could not say which of the two reasons applied.
      _logImageRefresh(
        previewData,
        key == null ? 'skipped_no_image_key' : 'skipped_already_attempted',
      );
      return;
    }

    _logImageRefresh(previewData, 'started');
    unawaited(_refreshPreviewAfterImageFailure(previewData));
  }

  /// One line per outcome of an image failure, paired with the widget's
  /// `URL preview image error` line by `host=`.
  void _logImageRefresh(UrlPreviewData previewData, String outcome) {
    final host = previewData.uri.host;
    Log.d(
      'URL preview image refresh '
      'host=${host.isEmpty ? "unknown" : host.toLowerCase()} '
      'outcome=$outcome',
      category: LogCategory.media,
      source: 'url-preview',
    );
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

    var nextData = refreshed == null
        ? _withoutPreviewImage(previewData)
        : refreshed;
    var precacheFailed = false;
    final image = nextData.image;
    if (image != null && context.mounted) {
      try {
        await precacheImage(image, context);
      } catch (_) {
        precacheFailed = true;
        nextData = _withoutPreviewImage(nextData);
      }
    }

    // Named outcomes rather than a boolean, because 'dropped' is the route
    // REVIEW could not confirm ever fires - _withoutPreviewImage can reduce a
    // card to the invalid sentinel, and nothing recorded when it did.
    _logImageRefresh(
      previewData,
      refreshed == null
          ? 'failed_no_replacement'
          : precacheFailed
          ? 'replacement_image_failed'
          : 'recovered',
    );
    if (identical(nextData, UrlPreviewComponent.invalidPreviewData)) {
      _logImageRefresh(previewData, 'card_dropped_nothing_survived');
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
    _reportPreviewVisibility(nextData);
    _keepBottomAttachedAfterPreviewResizes(wasAttachedToBottom);
  }

  void _reportPreviewVisibility(UrlPreviewData? previewData) {
    widget.onPreviewVisibilityChanged?.call(
      previewData != null &&
          previewData != UrlPreviewComponent.invalidPreviewData,
    );
  }

  String? _previewImageFailureKey(UrlPreviewData previewData) {
    return previewData.imageUri?.toString() ?? previewData.image?.toString();
  }

  /// [data] with its image dropped after a load failure.
  ///
  /// REVIEW 2026-09-11: if nothing else on the card survives - no title, no
  /// description, no posting account, no stats - the result is a card with
  /// only a site name (or the URL-derived fallback url_preview_widget.dart
  /// falls back to), which reads as blank. That is not a preview any more,
  /// so this reports the same [UrlPreviewComponent.invalidPreviewData]
  /// sentinel a fetch that returned nothing already uses, rather than a
  /// [UrlPreviewData] indistinguishable from one legitimately carrying only
  /// a site name.
  UrlPreviewData _withoutPreviewImage(UrlPreviewData data) {
    final title = normalizeUrlPreviewText(data.title);
    final description = normalizeUrlPreviewText(data.description);
    final postingAccount = normalizeUrlPreviewText(data.postingAccount);
    final stats = normalizeUrlPreviewText(data.stats);

    if (title == null &&
        description == null &&
        postingAccount == null &&
        stats == null) {
      return UrlPreviewComponent.invalidPreviewData;
    }

    return UrlPreviewData(
      data.uri,
      siteName: data.siteName,
      title: title,
      description: description,
      postingAccount: postingAccount,
      stats: stats,
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
