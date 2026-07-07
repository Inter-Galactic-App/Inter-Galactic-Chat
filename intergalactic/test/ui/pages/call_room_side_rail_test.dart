import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/demo/demo_client.dart';
import 'package:intergalactic/ui/molecules/overlapping_panels.dart';
import 'package:intergalactic/ui/organisms/room_quick_access_menu/room_quick_access_menu.dart';
import 'package:intergalactic/ui/organisms/room_side_panel/room_side_panel.dart';
import 'package:intergalactic/ui/pages/main/main_page.dart';
import 'package:intergalactic/ui/pages/main/main_page_view_mobile.dart';

void main() {
  test('call-room quick actions insert side rail modes together', () async {
    final client = DemoClient.createOfflineDemo();
    await client.init(false);
    addTearDown(client.close);

    final room = client.getRoom(DemoClient.demoVoiceRoomId)!;
    final menu = RoomQuickAccessMenu(
      room: room,
      actionsAfterInvite: [
        RoomQuickAccessMenuEntry(
          name: 'Chat',
          action: (_) {},
          icon: Icons.chat_bubble_outline_rounded,
        ),
        RoomQuickAccessMenuEntry(
          name: 'Members',
          action: (_) {},
          icon: Icons.people_alt_outlined,
        ),
      ],
    );

    final actionNames = menu.actions.map((entry) => entry.name).toList();
    final inviteIndex = actionNames.indexOf('Invite');
    final chatIndex = actionNames.indexOf('Chat');

    expect(chatIndex, greaterThanOrEqualTo(0));
    if (inviteIndex >= 0) {
      expect(chatIndex, inviteIndex + 1);
    }
    expect(actionNames.sublist(chatIndex, chatIndex + 2), ['Chat', 'Members']);
  });

  test(
    'call-room chat side rail auto-open uses existing unread state once',
    () {
      expect(
        debugShouldAutoOpenCallRoomChatForTesting(
          displayNotificationCount: 1,
          displayHighlightedNotificationCount: 0,
          displayRoomWideMentionNotification: false,
          alreadyAutoOpenedForRoom: false,
        ),
        isTrue,
      );

      expect(
        debugShouldAutoOpenCallRoomChatForTesting(
          displayNotificationCount: 1,
          displayHighlightedNotificationCount: 1,
          displayRoomWideMentionNotification: true,
          alreadyAutoOpenedForRoom: true,
        ),
        isFalse,
      );
    },
  );

  test('call-room side rail chat suppresses timeline boundary loading', () {
    final chatBehavior =
        debugCallRoomSidePanelChatTimelineBoundaryBehaviorForTesting(
          sidePanelState: SidePanelState.chat,
          isCallRoom: true,
        );

    expect(chatBehavior.autoLoadTimelineBoundaries, isTrue);
    expect(chatBehavior.showTimelineBoundaryLoadingIndicators, isFalse);

    final normalRoomBehavior =
        debugCallRoomSidePanelChatTimelineBoundaryBehaviorForTesting(
          sidePanelState: SidePanelState.chat,
          isCallRoom: false,
        );

    expect(normalRoomBehavior.autoLoadTimelineBoundaries, isTrue);
    expect(normalRoomBehavior.showTimelineBoundaryLoadingIndicators, isTrue);

    expect(
      debugShouldSuppressCallRoomSidePanelChatTimelineLoading(
        sidePanelState: SidePanelState.chat,
        isCallRoom: true,
      ),
      isTrue,
    );

    expect(
      debugShouldSuppressCallRoomSidePanelChatTimelineLoading(
        sidePanelState: SidePanelState.defaultView,
        isCallRoom: true,
      ),
      isFalse,
    );

    expect(
      debugShouldSuppressCallRoomSidePanelChatTimelineLoading(
        sidePanelState: SidePanelState.chat,
        isCallRoom: false,
      ),
      isFalse,
    );
  });

  test('force-open side rail keeps the quick action toggle in close state', () {
    expect(
      debugRoomQuickAccessPanelToggleIconForTesting(
        hideSidePanel: true,
        forceSidePanelVisible: false,
      ),
      Icons.chevron_left,
    );
    expect(
      debugRoomQuickAccessPanelToggleIconForTesting(
        hideSidePanel: true,
        forceSidePanelVisible: true,
      ),
      Icons.chevron_right,
    );
  });

  test('mobile call side rail returns to main when right panel disappears', () {
    expect(
      debugShouldRevealMainWhenRightPanelUnavailable(
        currentSide: RevealSide.right,
        hasCurrentRoom: false,
      ),
      isTrue,
    );

    expect(
      debugShouldRevealMainWhenRightPanelUnavailable(
        currentSide: RevealSide.right,
        hasCurrentRoom: true,
      ),
      isFalse,
    );

    expect(
      debugShouldRevealMainWhenRightPanelUnavailable(
        currentSide: RevealSide.main,
        hasCurrentRoom: false,
      ),
      isFalse,
    );
  });
}
