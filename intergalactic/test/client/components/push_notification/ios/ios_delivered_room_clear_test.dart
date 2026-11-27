import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/push_notification/ios/ios_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('chat.intergalactic.app/ios_notifications');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return 2;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('room clear passes only the exact account and room route', () async {
    await IosNotifier.removeDeliveredRemoteNotificationsForRoom(
      clientId: 'account-a',
      roomId: 'room-a',
    );
    expect(calls, hasLength(1));
    expect(calls.single.method, 'removeDeliveredRemoteNotificationsForRoom');
    expect(calls.single.arguments, {
      'client_id': 'account-a',
      'room_id': 'room-a',
    });
  });

  test('missing route never asks native code to clear alerts', () async {
    await IosNotifier.removeDeliveredRemoteNotificationsForRoom(
      clientId: '',
      roomId: 'room-a',
    );
    await IosNotifier.removeDeliveredRemoteNotificationsForRoom(
      clientId: 'account-a',
      roomId: '',
    );
    expect(calls, isEmpty);
  });

  test('native clear requires a remote trigger and both route fields', () {
    final sourceFile = [
      File('ios/Runner/AppDelegate.swift'),
      File('intergalactic/ios/Runner/AppDelegate.swift'),
    ].firstWhere((file) => file.existsSync());
    final source = sourceFile.readAsStringSync();
    final handlerStart = source.indexOf(
      'private func handleRemoveDeliveredRemoteNotificationsForRoom(',
    );
    final handlerEnd = source.indexOf('private func configureAppIconChannel(');
    expect(handlerStart, greaterThanOrEqualTo(0));
    expect(handlerEnd, greaterThan(handlerStart));
    final handler = source.substring(handlerStart, handlerEnd);
    expect(
      handler,
      contains('notification.request.trigger is UNPushNotificationTrigger'),
    );
    expect(handler, contains('== clientId'));
    expect(handler, contains('== roomId'));
    expect(handler, isNot(contains('removeAllDeliveredNotifications')));
  });

  test('both room-read routes invoke remote clearing', () {
    final sourceFile = [
      File('lib/client/components/push_notification/ios/ios_notifier.dart'),
      File(
        'intergalactic/lib/client/components/push_notification/ios/ios_notifier.dart',
      ),
    ].firstWhere((file) => file.existsSync());
    final source = sourceFile.readAsStringSync();
    final clearMethodsStart = source.indexOf(
      'Future<void> clearNotifications(Room room)',
    );
    expect(clearMethodsStart, greaterThanOrEqualTo(0));
    final clearMethods = source.substring(clearMethodsStart);
    expect(
      'await removeDeliveredRemoteNotificationsForRoom('.allMatches(
        clearMethods,
      ),
      hasLength(2),
    );
  });
}
