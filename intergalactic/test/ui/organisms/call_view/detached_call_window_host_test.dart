import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/organisms/call_view/call_view.dart';
import 'package:intergalactic/ui/windows/detached_call_window/detached_call_window_host_io.dart';

void main() {
  test('detached custom title bar shows only for opaque custom chrome', () {
    expect(
      debugShouldShowDetachedWindowTitleBarForTesting(transparentChrome: false),
      isTrue,
    );
    expect(
      debugShouldShowDetachedWindowTitleBarForTesting(transparentChrome: true),
      isFalse,
    );
    expect(
      debugShouldShowDetachedWindowTitleBarForTesting(
        transparentChrome: false,
        usesCustomChrome: false,
      ),
      isFalse,
    );
  });

  test('detached popout backgrounds avoid native white edge blending', () {
    final scheme = ColorScheme.fromSeed(
      seedColor: Colors.cyan,
      brightness: Brightness.dark,
    );

    final opaque = debugDetachedWindowBackgroundColorForTesting(
      scheme,
      transparentChrome: false,
    );
    final transparent = debugDetachedWindowBackgroundColorForTesting(
      scheme,
      transparentChrome: true,
    );

    expect(opaque, scheme.surfaceContainerLowest);
    expect(opaque, isNot(Colors.white));
    expect(transparent, Colors.transparent);
    expect(transparent.a, isZero);
  });

  test('detached root inserts a local overlay before paint', () {
    for (final transparentChrome in <bool>[false, true]) {
      final dynamic root = debugBuildDetachedWindowRootForTesting(
        transparentChrome: transparentChrome,
        child: const SizedBox.shrink(),
      );

      expect(root.transparentChrome, transparentChrome);
      expect(root.child.runtimeType.toString(), contains('Overlay'));
    }
  });

  test(
    'transparent detached call surfaces keep tile geometry with local menus',
    () {
      final opaque = debugResolveCallTileSurfaceTreatmentForTesting(
        transparentBackground: false,
      );
      final transparent = debugResolveCallTileSurfaceTreatmentForTesting(
        transparentBackground: true,
      );

      expect(opaque.edgeToEdge, isFalse);
      expect(opaque.showTileScrim, isTrue);
      expect(opaque.useRootOverlayForMenus, isTrue);
      expect(
        debugShouldUseCallMenuRootOverlayForTesting(
          transparentBackground: false,
        ),
        isTrue,
      );

      expect(transparent.edgeToEdge, isFalse);
      expect(transparent.showTileScrim, isTrue);
      expect(transparent.useRootOverlayForMenus, isFalse);
      expect(
        debugShouldUseCallMenuRootOverlayForTesting(
          transparentBackground: true,
        ),
        isFalse,
      );
    },
  );

  test('collapsed transparent chrome fits centered icon target', () {
    final metrics = debugDetachedWindowCollapsedChromeMetricsForTesting();
    final collapsedInnerWidth =
        metrics.collapsedMaxWidth -
        metrics.borderWidth * 2 -
        metrics.collapsedHorizontalPadding * 2;
    final transitionInnerWidth =
        metrics.collapsedMaxWidth -
        metrics.borderWidth * 2 -
        metrics.expandedHorizontalPadding * 2;
    final expandedInnerWidth =
        metrics.expandedMaxWidth -
        metrics.borderWidth * 2 -
        metrics.expandedHorizontalPadding * 2;

    expect(
      collapsedInnerWidth,
      greaterThanOrEqualTo(metrics.buttonMinimumSize),
    );
    expect(
      transitionInnerWidth,
      greaterThanOrEqualTo(metrics.buttonMinimumSize),
    );
    expect(
      expandedInnerWidth,
      greaterThanOrEqualTo(metrics.expandedControlsWidth),
    );
    expect(
      debugShouldShowDetachedWindowExpandedChromeForTesting(
        expanded: true,
        availableWidth: transitionInnerWidth,
      ),
      isFalse,
    );
    expect(
      debugShouldShowDetachedWindowExpandedChromeForTesting(
        expanded: true,
        availableWidth: metrics.expandedControlsWidth,
      ),
      isTrue,
    );
  });

  test(
    'detached window native style follows custom and transparent chrome',
    () {
      const caption = 0x00C00000;
      const border = 0x00800000;
      const thickFrame = 0x00040000;
      const minimizeBox = 0x00020000;
      const maximizeBox = 0x00010000;
      const sysMenu = 0x00080000;
      const popup = 0x80000000;
      const nativeStyle =
          caption | border | thickFrame | minimizeBox | maximizeBox | sysMenu;

      final opaque = debugResolveDetachedWindowStyleForTesting(
        nativeStyle,
        transparentChrome: false,
      );
      final transparent = debugResolveDetachedWindowStyleForTesting(
        nativeStyle,
        transparentChrome: true,
      );

      expect(opaque & caption, isZero);
      expect(opaque & border, isZero);
      expect(opaque & thickFrame, thickFrame);
      expect(opaque & minimizeBox, minimizeBox);
      expect(opaque & maximizeBox, maximizeBox);
      expect(opaque & sysMenu, sysMenu);

      expect(transparent & caption, isZero);
      expect(transparent & border, isZero);
      expect(transparent & thickFrame, isZero);
      expect(transparent & minimizeBox, isZero);
      expect(transparent & maximizeBox, isZero);
      expect(transparent & sysMenu, isZero);
      expect(transparent & popup, popup);
    },
  );

  test('detached custom chrome strips extended edge chrome', () {
    const dlgModalFrame = 0x00000001;
    const windowEdge = 0x00000100;
    const clientEdge = 0x00000200;
    const staticEdge = 0x00020000;
    const appWindow = 0x00040000;
    const nativeExStyle =
        dlgModalFrame | windowEdge | clientEdge | staticEdge | appWindow;

    final opaque = debugResolveDetachedWindowExStyleForTesting(
      nativeExStyle,
      transparentChrome: false,
    );
    final transparent = debugResolveDetachedWindowExStyleForTesting(
      nativeExStyle,
      transparentChrome: true,
    );

    expect(opaque & dlgModalFrame, isZero);
    expect(opaque & windowEdge, isZero);
    expect(opaque & clientEdge, isZero);
    expect(opaque & staticEdge, isZero);
    expect(opaque & appWindow, appWindow);
    expect(transparent & dlgModalFrame, isZero);
    expect(transparent & windowEdge, isZero);
    expect(transparent & clientEdge, isZero);
    expect(transparent & staticEdge, isZero);
    expect(transparent & appWindow, appWindow);
  });

  test(
    'detached window chrome profile uses profile-specific frame margins',
    () {
      const caption = 0x00C00000;
      const border = 0x00800000;
      const thickFrame = 0x00040000;
      const sysMenu = 0x00080000;
      const popup = 0x80000000;
      const nativeStyle = caption | border | thickFrame | sysMenu;

      final opaque = debugResolveDetachedWindowChromeProfileForTesting(
        style: nativeStyle,
        exStyle: 0,
        transparentChrome: false,
      );
      final transparent = debugResolveDetachedWindowChromeProfileForTesting(
        style: nativeStyle,
        exStyle: 0,
        transparentChrome: true,
      );

      expect(opaque.profileName, 'opaque_custom_chrome');
      expect(opaque.frameLeft, isZero);
      expect(opaque.frameRight, isZero);
      expect(opaque.frameTop, isZero);
      expect(opaque.frameBottom, isZero);
      expect(opaque.style & thickFrame, thickFrame);

      expect(transparent.profileName, 'transparent_locked_chrome');
      expect(transparent.frameLeft, -1);
      expect(transparent.frameRight, -1);
      expect(transparent.frameTop, -1);
      expect(transparent.frameBottom, -1);
      expect(transparent.style & thickFrame, isZero);
      expect(transparent.style & sysMenu, isZero);
      expect(transparent.style & popup, popup);
    },
  );

  test('detached edge classifier distinguishes native and DWM owners', () {
    const caption = 0x00C00000;
    const border = 0x00800000;

    expect(
      debugClassifyDetachedWindowEdgeOwnershipForTesting(
        transparentChrome: true,
        style: caption | border,
        exStyle: 0,
      ),
      'state_leakage_owned',
    );

    expect(
      debugClassifyDetachedWindowEdgeOwnershipForTesting(
        transparentChrome: true,
        style: 0,
        exStyle: 0,
        visibleFrameBorderThickness: 1,
        dwmBorderColor: 0x00FFFFFF,
        sampledWindowEdgeIsLight: true,
      ),
      'shadow_or_compositor_owned',
    );

    expect(
      debugClassifyDetachedWindowEdgeOwnershipForTesting(
        transparentChrome: true,
        style: 0,
        exStyle: 0,
        sampledFlutterSceneEdgeIsLight: true,
      ),
      'flutter_scene_owned',
    );
  });
}
