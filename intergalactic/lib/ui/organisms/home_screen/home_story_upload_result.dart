import 'package:intergalactic/client/components/stories/story_component.dart';

enum HomeStoryUploadFailureKind {
  sentNone,
  partiallyFailed,
}

class HomeStoryUploadFailure {
  const HomeStoryUploadFailure({
    required this.kind,
    required this.result,
    required this.retryDraftStartIndex,
    required this.retryVideoStartIndex,
  });

  final HomeStoryUploadFailureKind kind;
  final StoryUploadResult result;
  final int retryDraftStartIndex;
  final int retryVideoStartIndex;

  List<T> retryDrafts<T>(List<T> drafts) =>
      drafts.sublist(_safeRetryStart(retryDraftStartIndex, drafts.length));

  List<T> retryVideoDrafts<T>(List<T> videoDrafts) => videoDrafts.sublist(
        _safeRetryStart(retryVideoStartIndex, videoDrafts.length),
      );
}

HomeStoryUploadFailure? classifyHomeStoryUploadFailure({
  required StoryUploadResult result,
  required int nextPendingDraftIndex,
  required int nextPendingVideoIndex,
}) {
  if (!result.sentAny) {
    return HomeStoryUploadFailure(
      kind: HomeStoryUploadFailureKind.sentNone,
      result: result,
      retryDraftStartIndex: nextPendingDraftIndex,
      retryVideoStartIndex: nextPendingVideoIndex,
    );
  }

  if (result.failedEventCount > 0) {
    return HomeStoryUploadFailure(
      kind: HomeStoryUploadFailureKind.partiallyFailed,
      result: result,
      retryDraftStartIndex: nextPendingDraftIndex,
      retryVideoStartIndex: nextPendingVideoIndex,
    );
  }

  return null;
}

int _safeRetryStart(int startIndex, int itemCount) {
  if (startIndex <= 0) {
    return 0;
  }
  if (startIndex >= itemCount) {
    return itemCount;
  }
  return startIndex;
}
