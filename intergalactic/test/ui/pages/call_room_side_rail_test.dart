import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/demo/demo_client.dart';
import 'package:intergalactic/ui/molecules/overlapping_panels.dart';
import 'package:intergalactic/ui/organisms/room_quick_access_menu/room_quick_access_menu.dart';
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

  group('the side rail and "Open as Text Chat" cannot both show a chat', () {
    // Two independent paths could each put a chat on screen for the same room
    // and nothing made them exclusive, so users saw two chats side by side.
    // The owner chose the side rail as the owner of call-room chat.
    test('a text-room selection never leaves the rail in chat mode', () {
      final resolved = debugResolveCallRoomSideRailForSelection(
        asTextRoom: true,
        sameRailRoom: true,
        currentMode: CallRoomSideRailMode.chat,
        currentForcedOpen: true,
        shouldAutoOpenChat: false,
      );

      expect(resolved.mode, CallRoomSideRailMode.members);
      expect(
        resolved.forcedOpen,
        isFalse,
        reason:
            'the main area already shows a chat for this room, so a forced-open '
            'rail chat is the second one',
      );
    });

    test('a text-room selection outranks the unread auto-open', () {
      final resolved = debugResolveCallRoomSideRailForSelection(
        asTextRoom: true,
        sameRailRoom: false,
        currentMode: CallRoomSideRailMode.members,
        currentForcedOpen: false,
        shouldAutoOpenChat: true,
      );

      expect(
        resolved.mode,
        CallRoomSideRailMode.members,
        reason:
            'auto-open on unread must not reintroduce the duplicate the '
            'text-room branch just suppressed',
      );
      expect(resolved.forcedOpen, isFalse);
    });

    test('an ordinary selection still auto-opens chat on unread', () {
      final resolved = debugResolveCallRoomSideRailForSelection(
        asTextRoom: false,
        sameRailRoom: false,
        currentMode: CallRoomSideRailMode.members,
        currentForcedOpen: false,
        shouldAutoOpenChat: true,
      );

      expect(resolved.mode, CallRoomSideRailMode.chat);
      expect(resolved.forcedOpen, isTrue);
    });

    test('returning to the same room keeps the rail as the user left it', () {
      final resolved = debugResolveCallRoomSideRailForSelection(
        asTextRoom: false,
        sameRailRoom: true,
        currentMode: CallRoomSideRailMode.chat,
        currentForcedOpen: true,
        shouldAutoOpenChat: false,
      );

      expect(resolved.mode, CallRoomSideRailMode.chat);
      expect(resolved.forcedOpen, isTrue);
    });

    test('switching to a different call room resets the rail', () {
      final resolved = debugResolveCallRoomSideRailForSelection(
        asTextRoom: false,
        sameRailRoom: false,
        currentMode: CallRoomSideRailMode.chat,
        currentForcedOpen: true,
        shouldAutoOpenChat: false,
      );

      expect(resolved.mode, CallRoomSideRailMode.members);
      expect(resolved.forcedOpen, isFalse);
    });
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

  test('mobile call side rail dismissal clears the forced-open state', () {
    expect(
      debugShouldDismissForcedCallRoomRailOnMobileSideChange(
        side: RevealSide.main,
        forcedOpen: true,
      ),
      isTrue,
    );
    expect(
      debugShouldDismissForcedCallRoomRailOnMobileSideChange(
        side: RevealSide.right,
        forcedOpen: true,
      ),
      isFalse,
    );
    expect(
      debugShouldDismissForcedCallRoomRailOnMobileSideChange(
        side: RevealSide.left,
        forcedOpen: true,
      ),
      isTrue,
    );
    expect(
      debugShouldDismissForcedCallRoomRailOnMobileSideChange(
        side: RevealSide.main,
        forcedOpen: false,
      ),
      isFalse,
    );
  });
}
