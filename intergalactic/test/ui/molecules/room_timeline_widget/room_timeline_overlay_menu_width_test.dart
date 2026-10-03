import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/emoticon_recent/recent_emoticon_component.dart';
import 'package:intergalactic/ui/molecules/room_timeline_widget/room_timeline_overlay.dart';

/// The hover menu is anchored at the message's right edge and grows leftwards
/// inside the timeline's own clip. In the call-room side rail the timeline is
/// 280-340 px wide and the full menu is wider, so its left end was cut off.
/// Quick reactions are the only part that can give.
void main() {
  // Edit, reply, delete: what a sender sees on their own message.
  const primaryActions = 3;

  test('a full-width timeline shows every quick reaction', () {
    expect(
      TimelineOverlayState.quickReactionsThatFit(
        maxWidth: 900,
        quickReactionCount: RecentEmoticonComponent.quickReactionCount,
        primaryActionCount: primaryActions,
        hasAddReaction: true,
      ),
      RecentEmoticonComponent.quickReactionCount,
    );
  });

  test('the wide side rail drops reactions until the menu fits', () {
    // 340 px, minus the 40 px outer padding, 10 px inner padding and border,
    // the add-reaction button and divider (46), three actions and the options
    // button (120): 124 px left, which is four 30 px reactions.
    expect(
      TimelineOverlayState.quickReactionsThatFit(
        maxWidth: 340,
        quickReactionCount: 8,
        primaryActionCount: primaryActions,
        hasAddReaction: true,
      ),
      4,
    );
  });

  test('the compact side rail keeps the fixed actions and drops more', () {
    expect(
      TimelineOverlayState.quickReactionsThatFit(
        maxWidth: 280,
        quickReactionCount: 8,
        primaryActionCount: primaryActions,
        hasAddReaction: true,
      ),
      2,
    );
  });

  test('an unbounded width fits everything instead of throwing', () {
    // A LayoutBuilder under a horizontally unconstrained parent reports
    // infinity, and (infinity / size).floor() is an unsupported operation.
    // Review finding, 2026-09-02: the guard covered room <= 0 only.
    expect(
      TimelineOverlayState.quickReactionsThatFit(
        maxWidth: double.infinity,
        quickReactionCount: 8,
        primaryActionCount: primaryActions,
        hasAddReaction: true,
      ),
      8,
    );
  });

  test('never goes negative and never exceeds what is available', () {
    expect(
      TimelineOverlayState.quickReactionsThatFit(
        maxWidth: 100,
        quickReactionCount: 8,
        primaryActionCount: primaryActions,
        hasAddReaction: true,
      ),
      0,
    );
    expect(
      TimelineOverlayState.quickReactionsThatFit(
        maxWidth: 900,
        quickReactionCount: 3,
        primaryActionCount: primaryActions,
        hasAddReaction: false,
      ),
      3,
    );
  });
}
