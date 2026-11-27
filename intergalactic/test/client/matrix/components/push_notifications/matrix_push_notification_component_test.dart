import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/push_notifications/matrix_push_notification_component.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:matrix/matrix.dart';

void main() {
  group('MatrixPushNotificationComponent', () {
    test('marks legacy Android app ids stale before device matching', () {
      final reason =
          MatrixPushNotificationComponent.stalePusherReasonForTesting(
        _pusher(
          appId: 'chat.commet.commetapp.android',
          pushkey: 'legacy-token',
          deviceDisplayName: 'Old Android install',
          additionalData: const {'device_id': 'old-device'},
        ),
        currentAppId: BuildConfig.androidPushAppId,
        currentPushKey: 'current-fcm-token',
        deviceName: 'Current Android install',
        pushGateway: _pushGateway,
        extraData: const {
          'device_id': 'current-device',
          'registration_schema':
              MatrixPushNotificationComponent.androidFcmPusherSchema,
        },
        isAndroid: true,
        isIos: false,
        googleServicesEnabled: true,
      );

      expect(reason, 'legacy Android app id');
    });

    test('marks Android URL push keys stale before device matching', () {
      final reason =
          MatrixPushNotificationComponent.stalePusherReasonForTesting(
        _pusher(
          appId: BuildConfig.androidPushAppId,
          pushkey: 'https://push.ourgalaxy.space/_matrix/push/v1/notify',
          deviceDisplayName: 'Old Android install',
          additionalData: const {'device_id': 'old-device'},
        ),
        currentAppId: BuildConfig.androidPushAppId,
        currentPushKey: 'current-fcm-token',
        deviceName: 'Current Android install',
        pushGateway: _pushGateway,
        extraData: const {
          'device_id': 'current-device',
          'registration_schema':
              MatrixPushNotificationComponent.androidFcmPusherSchema,
        },
        isAndroid: true,
        isIos: false,
        googleServicesEnabled: true,
      );

      expect(reason, 'Android FCM build cannot use URL push key');
    });

    test('marks Android FCM pushers missing data-only format stale', () {
      final reason =
          MatrixPushNotificationComponent.stalePusherReasonForTesting(
        _pusher(
          appId: BuildConfig.androidPushAppId,
          pushkey: 'current-fcm-token',
          deviceDisplayName: 'Current Android install',
          additionalData: const {'device_id': 'current-device'},
        ),
        currentAppId: BuildConfig.androidPushAppId,
        currentPushKey: 'current-fcm-token',
        deviceName: 'Current Android install',
        pushGateway: _pushGateway,
        extraData: const {
          'device_id': 'current-device',
          'registration_schema':
              MatrixPushNotificationComponent.androidFcmPusherSchema,
        },
        isAndroid: true,
        isIos: false,
        googleServicesEnabled: true,
      );

      expect(
        reason,
        'different push format (actual=default, expected=data_only)',
      );
    });

    test('leaves unrelated pushers alone before per-device checks', () {
      final reason =
          MatrixPushNotificationComponent.stalePusherReasonForTesting(
        _pusher(
          appId: 'org.example.other.android',
          pushkey: 'other-token',
          deviceDisplayName: 'Other install',
          additionalData: const {'device_id': 'other-device'},
        ),
        currentAppId: BuildConfig.androidPushAppId,
        currentPushKey: 'current-fcm-token',
        deviceName: 'Current Android install',
        pushGateway: _pushGateway,
        extraData: const {
          'device_id': 'current-device',
          'registration_schema':
              MatrixPushNotificationComponent.androidFcmPusherSchema,
        },
        isAndroid: true,
        isIos: false,
        googleServicesEnabled: true,
      );

      expect(reason, isNull);
    });

    test('marks same-token iOS pushers missing APNs metadata stale', () {
      final reason =
          MatrixPushNotificationComponent.stalePusherReasonForTesting(
        _pusher(
          appId: BuildConfig.iosPushAppId,
          pushkey: _apnsToken,
          deviceDisplayName: 'Current iPhone',
        ),
        currentAppId: BuildConfig.iosPushAppId,
        currentPushKey: _apnsToken,
        deviceName: 'Current iPhone',
        pushGateway: _pushGateway,
        extraData: const {
          'platform': 'ios',
          'push_provider': 'apns',
          'apns_topic': BuildConfig.iosBundleId,
          'client_id': 'client-a',
        },
        isAndroid: false,
        isIos: true,
        googleServicesEnabled: false,
      );

      expect(reason, 'different push metadata');
    });

    test('leaves same-install iOS pushers alone when APNs has no token', () {
      final reason =
          MatrixPushNotificationComponent.stalePusherReasonForTesting(
        _pusher(
          appId: BuildConfig.iosPushAppId,
          pushkey: _apnsToken,
          deviceDisplayName: 'Current iPhone',
          additionalData: const {
            'platform': 'ios',
            'push_provider': 'apns',
          },
        ),
        currentAppId: BuildConfig.iosPushAppId,
        currentPushKey: null,
        deviceName: 'Current iPhone',
        pushGateway: _pushGateway,
        extraData: const {
          'platform': 'ios',
          'push_provider': 'apns',
          'apns_topic': BuildConfig.iosBundleId,
          'client_id': 'client-a',
        },
        isAndroid: false,
        isIos: true,
        googleServicesEnabled: false,
      );

      expect(reason, isNull);
    });

    test('leaves unrelated iOS pushers alone when APNs has no token', () {
      final reason =
          MatrixPushNotificationComponent.stalePusherReasonForTesting(
        _pusher(
          appId: 'org.example.other.ios',
          pushkey: _apnsToken,
          deviceDisplayName: 'Other iPhone',
          additionalData: const {
            'platform': 'ios',
            'push_provider': 'apns',
          },
        ),
        currentAppId: BuildConfig.iosPushAppId,
        currentPushKey: null,
        deviceName: 'Current iPhone',
        pushGateway: _pushGateway,
        extraData: const {
          'platform': 'ios',
          'push_provider': 'apns',
          'apns_topic': BuildConfig.iosBundleId,
          'client_id': 'client-a',
        },
        isAndroid: false,
        isIos: true,
        googleServicesEnabled: false,
      );

      expect(reason, isNull);
    });
  });
}

final Uri _pushGateway = Uri.parse(
  'https://push.ourgalaxy.space/_matrix/push/v1/notify',
);
const String _apnsToken =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

Pusher _pusher({
  required String appId,
  required String pushkey,
  required String deviceDisplayName,
  Map<String, Object?> additionalData = const {},
}) {
  return Pusher(
    appId: appId,
    pushkey: pushkey,
    appDisplayName: 'Inter Galactic',
    data: PusherData(url: _pushGateway, additionalProperties: additionalData),
    deviceDisplayName: deviceDisplayName,
    kind: 'http',
    lang: 'en',
  );
}
