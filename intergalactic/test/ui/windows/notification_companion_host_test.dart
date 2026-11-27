import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/windows/notification_companion/notification_companion_host_io.dart';

void main() {
  testWidgets('notification companion root keeps a transparent local overlay', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 100,
          height: 100,
          child: debugBuildNotificationCompanionRootForTesting(
            child: const SizedBox.shrink(),
          ),
        ),
      ),
    );

    final material = tester.widget<Material>(find.byType(Material).first);
    final coloredBox = tester.widget<ColoredBox>(find.byType(ColoredBox).first);

    expect(material.type, MaterialType.transparency);
    expect(coloredBox.color, Colors.transparent);
    expect(find.byType(Overlay), findsOneWidget);
  });

  test('notification companion native profile is transparent popup chrome', () {
    const caption = 0x00C00000;
    const border = 0x00800000;
    const thickFrame = 0x00040000;
    const minimizeBox = 0x00020000;
    const maximizeBox = 0x00010000;
    const sysMenu = 0x00080000;
    const popup = 0x80000000;
    const dlgModalFrame = 0x00000001;
    const windowEdge = 0x00000100;
    const clientEdge = 0x00000200;
    const staticEdge = 0x00020000;
    const toolWindow = 0x00000080;
    const appWindow = 0x00040000;
    const nativeStyle =
        caption | border | thickFrame | minimizeBox | maximizeBox | sysMenu;
    const nativeExStyle =
        dlgModalFrame | windowEdge | clientEdge | staticEdge | appWindow;

    final profile = debugResolveNotificationCompanionChromeProfileForTesting(
      style: nativeStyle,
      exStyle: nativeExStyle,
    );

    expect(profile.style & caption, isZero);
    expect(profile.style & border, isZero);
    expect(profile.style & thickFrame, isZero);
    expect(profile.style & minimizeBox, isZero);
    expect(profile.style & maximizeBox, isZero);
    expect(profile.style & sysMenu, isZero);
    expect(profile.style & popup, popup);
    expect(profile.exStyle & dlgModalFrame, isZero);
    expect(profile.exStyle & windowEdge, isZero);
    expect(profile.exStyle & clientEdge, isZero);
    expect(profile.exStyle & staticEdge, isZero);
    expect(profile.exStyle & appWindow, isZero);
    expect(profile.exStyle & toolWindow, toolWindow);
    expect(profile.frameLeft, -1);
    expect(profile.frameRight, -1);
    expect(profile.frameTop, -1);
    expect(profile.frameBottom, -1);
  });
}
