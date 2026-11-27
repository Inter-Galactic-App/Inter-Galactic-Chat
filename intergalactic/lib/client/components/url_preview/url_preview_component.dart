import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:flutter/widgets.dart';

abstract class UrlPreviewComponent<T extends Client> implements Component<T> {
  bool shouldGetPreviewDataForTimelineEvent(
      Timeline timeline, TimelineEvent event);

  bool shouldGetPreviewsInRoom(Room room);

  Future<UrlPreviewData?> getPreview(Timeline timeline, TimelineEvent event);

  Future<UrlPreviewData?> getPreviewForUrl(Room room, Uri url);

  UrlPreviewData? getCachedPreview(Timeline timeline, TimelineEvent event);

  Future<UrlPreviewData?> refreshPreviewAfterImageFailure(
    Timeline timeline,
    TimelineEvent event,
    UrlPreviewData failedData,
  );

  Future<void> warmTimelinePreviews(
    Timeline timeline, {
    int limit = 8,
    int concurrency = 2,
  });

  // This is a dummy value that we can store in the cache when we fail to get the url preview.
  // Instead of storing null, which is a bit confusing as if the cache returns null, does that mean we have
  // nothing cached, or the result was invalid? maybe this is dumb but it was the simplest way
  // to prevent weird ui glitches when failed fetches kept getting retried.
  static UrlPreviewData invalidPreviewData =
      UrlPreviewData(Uri.new(), title: "Unable to get url preview ");
}

class UrlPreviewData {
  final Uri uri;
  final String? siteName;
  final String? title;
  final String? description;
  final ImageProvider? image;
  final Uri? imageUri;
  final int? imageWidth;
  final int? imageHeight;
  final String? postingAccount;
  final String? stats;
  final bool volatileImageOmitted;

  const UrlPreviewData(
    this.uri, {
    this.siteName,
    this.title,
    this.description,
    this.image,
    this.imageUri,
    this.imageWidth,
    this.imageHeight,
    this.postingAccount,
    this.stats,
    this.volatileImageOmitted = false,
  });

  UrlPreviewData copyWith({
    Uri? uri,
    String? siteName,
    String? title,
    String? description,
    ImageProvider? image,
    Uri? imageUri,
    int? imageWidth,
    int? imageHeight,
    String? postingAccount,
    String? stats,
    bool? volatileImageOmitted,
  }) {
    return UrlPreviewData(
      uri ?? this.uri,
      siteName: siteName ?? this.siteName,
      title: title ?? this.title,
      description: description ?? this.description,
      image: image ?? this.image,
      imageUri: imageUri ?? this.imageUri,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      postingAccount: postingAccount ?? this.postingAccount,
      stats: stats ?? this.stats,
      volatileImageOmitted: volatileImageOmitted ?? this.volatileImageOmitted,
    );
  }
}
