import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/pages/main/main_page_view_desktop.dart';

/// Guards the one number that made the compact desktop rail overflow.
///
/// `_CompactUserRailPanel` stacks the Inbox and settings controls in a Column
/// inside a fixed-height box. Adding Inbox to that rail (when it still also
/// carried the small-window toggle) took its contents to 146 while the box
/// was still 132, so the last control clipped - and a clipped control in a
/// rail is an inaccessible one, not a cosmetic issue. The small-window toggle
/// has since moved to the Windows custom title bar
/// (`desktop_window_chrome_io.dart`), so the rail is back down to two
/// controls.
///
/// The panel is private and needs a full `MainPageState` to build, and this
/// repo has no main-page widget-test harness, so this pins the arithmetic
/// rather than the render. That is weaker than a layout assertion and is the
/// reason the defect reached review in the first place.
void main() {
  test('the compact rail is tall enough for everything stacked in it', () {
    // 13 * 2 + 6 + 38 * 2
    expect(DesktopCompactRailMetrics.requiredHeight, 108.0);
  });

  test('every stacked control is counted', () {
    // If a control is added to _CompactUserRailPanel's Column without bumping
    // controlCount, this stays green and the rail overflows again. The count
    // is the part a reader must keep honest by hand.
    expect(
      DesktopCompactRailMetrics.controlCount,
      2,
      reason: 'Inbox, settings',
    );
    expect(DesktopCompactRailMetrics.controlSize, 38.0);
  });
}
