import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/organisms/call_view/call_view.dart';

void main() {
  test('hidden or unrelated tiles do not report a watcher', () {
    expect(
      shouldReportScreenShareViewer(
        isScreenShare: true,
        isIncoming: true,
        isVideoHidden: true,
        isPoppedOut: false,
      ),
      isFalse,
    );
    expect(
      shouldReportScreenShareViewer(
        isScreenShare: false,
        isIncoming: true,
        isVideoHidden: false,
        isPoppedOut: false,
      ),
      isFalse,
    );
    expect(
      shouldReportScreenShareViewer(
        isScreenShare: true,
        isIncoming: false,
        isVideoHidden: false,
        isPoppedOut: false,
      ),
      isFalse,
    );
  });

  test('revealed shares and open panel popouts report a watcher', () {
    expect(
      shouldReportScreenShareViewer(
        isScreenShare: true,
        isIncoming: true,
        isVideoHidden: false,
        isPoppedOut: false,
      ),
      isTrue,
    );
    expect(
      shouldReportScreenShareViewer(
        isScreenShare: true,
        isIncoming: true,
        isVideoHidden: true,
        isPoppedOut: true,
      ),
      isTrue,
    );
  });
}
