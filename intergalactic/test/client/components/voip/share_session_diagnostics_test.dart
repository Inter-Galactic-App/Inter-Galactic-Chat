import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/share_session/share_session.dart';

void main() {
  group('ShareSession diagnostics', () {
    test('redacts source titles unless explicitly included', () {
      final session = ShareSession(
        target: const ShareTarget(
          type: ShareTargetType.window,
          sourceId: 'window:0x123456',
          title: 'Private Game Window Title',
          processId: 4321,
        ),
        videoSource: _FakeScreenVideoSource(
          const ShareTarget(
            type: ShareTargetType.window,
            sourceId: 'window:0x123456',
            title: 'Private Game Window Title',
            processId: 4321,
          ),
        ),
        sharedAudioSource: const DisabledSharedAudioSource(),
      );

      final redacted = session.diagnosticsSummary();
      final visible = session.diagnosticsSummary(includeTitle: true);

      expect(redacted.sourceIdHash, hasLength(8));
      expect(redacted.sourceLine, contains('sourceType=window'));
      expect(redacted.sourceLine, contains('pid=4321'));
      expect(redacted.sourceLine, isNot(contains('Private Game')));
      expect(redacted.audioLine, contains('audioRequested=false'));
      expect(visible.sourceLine, contains('Private Game Window Title'));
    });

    test('truncates long included source titles', () {
      final title =
          '${List.filled(8, 'Very Long Window Title').join(' ')} tail';

      final truncated = truncateShareSourceTitle(title, maxLength: 32);

      expect(truncated.length, 32);
      expect(truncated, endsWith('...'));
    });
  });
}

class _FakeScreenVideoSource implements ScreenVideoSource {
  const _FakeScreenVideoSource(this.target);

  @override
  final ShareTarget target;
}
