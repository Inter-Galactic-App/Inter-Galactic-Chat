import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/stories/story_component.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_upload_result.dart';

void main() {
  test('classifies fully successful story uploads as no failure', () {
    final failure = classifyHomeStoryUploadFailure(
      result: const StoryUploadResult(
        storyCount: 2,
        sentEventCount: 4,
        targetRoomCount: 2,
        failedEventCount: 0,
      ),
      nextPendingDraftIndex: 1,
      nextPendingVideoIndex: 1,
    );

    expect(failure, isNull);
  });

  test('classifies no-send story uploads and retries pending drafts', () {
    final failure = classifyHomeStoryUploadFailure(
      result: const StoryUploadResult(
        storyCount: 2,
        sentEventCount: 0,
        targetRoomCount: 2,
        failedEventCount: 2,
      ),
      nextPendingDraftIndex: 0,
      nextPendingVideoIndex: 1,
    );

    expect(failure, isNotNull);
    expect(failure!.kind, HomeStoryUploadFailureKind.sentNone);
    expect(failure.result.storyCount, 2);
    expect(failure.retryDrafts(['photo-a', 'photo-b']), [
      'photo-a',
      'photo-b',
    ]);
    expect(failure.retryVideoDrafts(['video-a', 'video-b']), ['video-b']);
  });

  test('classifies partial failures and retries only unsent drafts', () {
    final failure = classifyHomeStoryUploadFailure(
      result: const StoryUploadResult(
        storyCount: 3,
        sentEventCount: 4,
        targetRoomCount: 2,
        failedEventCount: 1,
      ),
      nextPendingDraftIndex: 2,
      nextPendingVideoIndex: 0,
    );

    expect(failure, isNotNull);
    expect(failure!.kind, HomeStoryUploadFailureKind.partiallyFailed);
    expect(failure.retryDrafts(['photo-a', 'photo-b', 'photo-c']), [
      'photo-c',
    ]);
    expect(failure.retryVideoDrafts(['video-a']), ['video-a']);
  });

  test('retry ranges clamp to available draft lists', () {
    final failure = classifyHomeStoryUploadFailure(
      result: const StoryUploadResult(
        storyCount: 1,
        sentEventCount: 0,
        targetRoomCount: 1,
        failedEventCount: 1,
      ),
      nextPendingDraftIndex: 4,
      nextPendingVideoIndex: -2,
    );

    expect(failure, isNotNull);
    expect(failure!.retryDrafts(['photo-a']), isEmpty);
    expect(failure.retryVideoDrafts(['video-a', 'video-b']), [
      'video-a',
      'video-b',
    ]);
  });
}
