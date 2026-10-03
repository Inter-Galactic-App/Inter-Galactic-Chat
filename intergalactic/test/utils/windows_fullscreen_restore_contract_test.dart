import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  final currentDirectory = Directory.current;
  final nestedAppRoot = Directory(
    path.join(currentDirectory.path, 'intergalactic'),
  );
  final appRoot = nestedAppRoot.existsSync() ? nestedAppRoot : currentDirectory;
  final repositoryRoot = appRoot.parent;
  final windowsPluginRoot = path.join(
    repositoryRoot.path,
    'plugins',
    'window_manager',
    'windows',
  );

  test('maximized fullscreen exit recomputes the Windows work area', () {
    final windowManager = File(
      path.join(windowsPluginRoot, 'window_manager.cpp'),
    ).readAsStringSync();
    final plugin = File(
      path.join(windowsPluginRoot, 'window_manager_plugin.cpp'),
    ).readAsStringSync();
    final normalizedWindowManager = windowManager.replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    final normalizedPlugin = plugin.replaceAll(RegExp(r'\s+'), ' ');

    const restore = '::ShowWindow(mainWindow, SW_RESTORE);';
    const maximize = '::ShowWindow(mainWindow, SW_MAXIMIZE);';
    final restoreIndex = normalizedWindowManager.indexOf(restore);
    final maximizeIndex = normalizedWindowManager.indexOf(maximize);

    expect(restoreIndex, greaterThanOrEqualTo(0));
    expect(maximizeIndex, greaterThan(restoreIndex));
    expect(
      normalizedWindowManager,
      contains(
        'restoring_maximized_from_fullscreen = g_maximized_before_fullscreen;',
      ),
    );
    expect(
      normalizedWindowManager.indexOf(
        'restoring_maximized_from_fullscreen = false;',
        restoreIndex,
      ),
      greaterThan(maximizeIndex),
      reason: 'The transient-size guard must survive both ShowWindow calls.',
    );
    expect(
      normalizedWindowManager,
      isNot(contains('PostMessage(mainWindow, WM_SYSCOMMAND, SC_MAXIMIZE')),
      reason:
          'An asynchronous maximize races the Dart hidden-title-bar restore.',
    );
    expect(
      normalizedPlugin,
      contains(
        'if (window_manager->restoring_maximized_from_fullscreen && '
        'wParam == SIZE_RESTORED) {',
      ),
      reason: 'The intermediate normal state must not reach Dart listeners.',
    );
    final wmSizeIndex = normalizedPlugin.indexOf('message == WM_SIZE');
    final transientGuardIndex = normalizedPlugin.indexOf(
      'if (window_manager->restoring_maximized_from_fullscreen && '
      'wParam == SIZE_RESTORED) {',
      wmSizeIndex,
    );
    expect(wmSizeIndex, greaterThanOrEqualTo(0));
    expect(transientGuardIndex, greaterThan(wmSizeIndex));
    expect(
      transientGuardIndex,
      lessThan(
        normalizedPlugin.indexOf(
          'window_manager->ForceChildRefresh();',
          wmSizeIndex,
        ),
      ),
    );
    expect(
      normalizedPlugin,
      contains(
        '(wParam == SIZE_RESTORED || wParam == SIZE_MAXIMIZED) && '
        'window_manager->last_state == STATE_FULLSCREEN_ENTERED',
      ),
      reason: 'A maximized exit must clear the plugin fullscreen event state.',
    );
    expect(
      normalizedPlugin,
      contains('wParam == SIZE_MAXIMIZED ? STATE_MAXIMIZED : STATE_NORMAL;'),
    );
  });
}
