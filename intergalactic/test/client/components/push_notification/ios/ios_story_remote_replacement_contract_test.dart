import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sourceFile = [
    File('lib/client/components/push_notification/ios/ios_notifier.dart'),
    File(
      'intergalactic/lib/client/components/push_notification/ios/ios_notifier.dart',
    ),
  ].firstWhere((file) => file.existsSync());
  final source = sourceFile.readAsStringSync();

  test('a policy-approved story replaces its earlier remote generic', () {
    final storyStart = source.indexOf('case StoryNotificationContent _:');
    final storyEnd = source.indexOf(
      'case CallNotificationContent _:',
      storyStart,
    );
    expect(storyStart, greaterThanOrEqualTo(0));
    expect(storyEnd, greaterThan(storyStart));

    final storyCase = source.substring(storyStart, storyEnd);
    final removal = storyCase.indexOf(
      'await removeDeliveredRemoteNotification(notification.eventId);',
    );
    final display = storyCase.indexOf('return _showNotification(');

    expect(removal, greaterThanOrEqualTo(0));
    expect(display, greaterThan(removal));
  });
}
