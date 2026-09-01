import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  final appRoot = Directory.current;
  final repositoryRoot = appRoot.parent;
  final pluginRoot = Directory(
    path.join(
      repositoryRoot.path,
      'plugins',
      'intergalactic_notification_preview',
    ),
  );

  test('notification preview bridge is registered for every Flutter engine', () {
    final workspacePubspec = File(
      path.join(repositoryRoot.path, 'pubspec.yaml'),
    ).readAsStringSync();
    final appPubspec = File(
      path.join(appRoot.path, 'pubspec.yaml'),
    ).readAsStringSync();
    final pluginPubspec = File(
      path.join(pluginRoot.path, 'pubspec.yaml'),
    ).readAsStringSync();
    final pluginSource = File(
      path.join(
        pluginRoot.path,
        'android',
        'src',
        'main',
        'kotlin',
        'chat',
        'intergalactic',
        'notification_preview',
        'IntergalacticNotificationPreviewPlugin.kt',
      ),
    ).readAsStringSync();
    final manifest = File(
      path.join(
        appRoot.path,
        'android',
        'app',
        'src',
        'main',
        'AndroidManifest.xml',
      ),
    ).readAsStringSync();
    final sharePaths = File(
      path.join(
        appRoot.path,
        'android',
        'app',
        'src',
        'main',
        'res',
        'xml',
        'intergalactic_share_paths.xml',
      ),
    );
    final mainActivity = File(
      path.join(
        appRoot.path,
        'android',
        'app',
        'src',
        'main',
        'kotlin',
        'chat',
        'intergalactic',
        'app',
        'MainActivity.kt',
      ),
    ).readAsStringSync();

    expect(
      workspacePubspec,
      contains('- plugins/intergalactic_notification_preview'),
    );
    // Matched independently rather than as one exact-whitespace block: a
    // pubspec reformat, or another key landing under the dependency before
    // `path:`, used to fail this as a contract break that had not happened.
    expect(appPubspec, contains('intergalactic_notification_preview:'));
    expect(
      appPubspec,
      contains('path: ../plugins/intergalactic_notification_preview'),
    );
    expect(
      pluginPubspec,
      contains('pluginClass: IntergalacticNotificationPreviewPlugin'),
    );
    expect(
      pluginSource,
      allOf(
        contains(
          'class IntergalacticNotificationPreviewPlugin : FlutterPlugin',
        ),
        contains('binding.applicationContext'),
        contains('chat.intergalactic.app/notification_preview'),
        contains('contentUriForNotificationPreview'),
        contains('FileProvider.getUriForFile'),
        contains('grantUriPermission'),
      ),
    );
    expect(
      mainActivity,
      isNot(contains('contentUriForNotificationPreview')),
      reason:
          'The Activity-only handler is unavailable to Firebase headless engines.',
    );

    // The plugin builds its authority from the package name; the manifest
    // declares it from the applicationId. They agree today and nothing
    // enforced that, and a preview whose authority does not match its provider
    // fails at the moment a notification tries to render it.
    expect(pluginSource, contains('.fileprovider'));
    expect(manifest, contains('.fileprovider'));
    expect(manifest, contains('@xml/intergalactic_share_paths'));
    expect(
      sharePaths.existsSync(),
      isTrue,
      reason: 'The provider names this resource, so it has to exist.',
    );

    // Every staged preview grants SystemUI a read permission, and nothing
    // released it: the grants outlived the files, which the Dart sweep deletes
    // after two days. The revoke has to exist on BOTH sides - a plugin method
    // no caller invokes is the same leak with more code - so the pairing is
    // pinned here rather than in either file alone.
    expect(
      pluginSource,
      allOf(
        contains(
          'const val REVOKE_URI_METHOD = "revokeNotificationPreviewGrants"',
        ),
        contains('revokeUriPermission'),
        // The DISPATCH, not just the presence of the two symbols. A plugin can
        // define REVOKE_URI_METHOD and implement revokePreviewGrants and still
        // reject the call, because `onMethodCall` opens by returning
        // `notImplemented()` for anything that is not one of the two named
        // methods. Without these two the test stayed green with the method
        // unreachable - defined, implemented, and never routed to.
        contains('call.method != REVOKE_URI_METHOD'),
        contains('revokePreviewGrants(applicationContext, call, result)'),
      ),
      reason: 'the plugin grants a read permission it never releases',
    );
    // The QUOTED method name, not the identifier: `_revokeNotificationPreview-
    // Grants` contains the bare name as a substring, so a check for that alone
    // stayed green with the channel call renamed and its invocation removed.
    expect(
      File(
        'lib/client/components/push_notification/android/android_notifier.dart',
      ).readAsStringSync(),
      contains("'revokeNotificationPreviewGrants',"),
      reason: 'the sweep deletes the files but never asks for the revoke',
    );
  });
}
