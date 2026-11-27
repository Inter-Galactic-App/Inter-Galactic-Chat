import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final sourceFile = [
    File('ios/InterGalactic Notification Extension/NotificationService.swift'),
    File(
      'intergalactic/ios/InterGalactic Notification Extension/NotificationService.swift',
    ),
  ].firstWhere((file) => file.existsSync());
  final source = sourceFile.readAsStringSync();

  test('event fetch retries only an iOS request timeout', () {
    final eventFetch = source.substring(
      source.indexOf('func event(homeserver:'),
      source.indexOf('private func eventAttempt('),
    );

    expect(eventFetch, contains('failure.reason == "transport"'));
    expect(eventFetch, contains('failure.code == NSURLErrorTimedOut'));
    expect(
      'eventAttempt('.allMatches(eventFetch),
      hasLength(2),
      reason: 'the event path must make at most two attempts',
    );
  });

  test('retry remains inside the original event-fetch envelope', () {
    expect(
      source,
      contains(
        'private static let eventFetchWindow: TimeInterval = resourceTimeout + 1',
      ),
    );
    expect(
      source,
      contains(
        'Date().addingTimeInterval(budget.clamp(Self.eventFetchWindow))',
      ),
    );
    expect(
      source,
      contains('deadline.timeIntervalSinceNow >= NSEBudget.minimumRequest + 1'),
    );
    expect(
      source,
      contains(
        'let available = min(deadline.timeIntervalSinceNow, budget.remaining())',
      ),
    );
  });
}
