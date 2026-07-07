import 'package:intergalactic/client/components/calendar_room/calendar_room_component.dart';
import 'package:intergalactic/client/components/forum_room/forum_room_component.dart';
import 'package:intergalactic/client/components/photo_album_room/photo_album_room_component.dart';
import 'package:intergalactic/client/components/voip_room/voip_room_component.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/atoms/scaled_safe_area.dart';
import 'package:intergalactic/ui/organisms/calendar_view/calendar_room_view.dart';
import 'package:intergalactic/ui/organisms/call_view/call.dart';
import 'package:intergalactic/ui/organisms/forum/forum_room_view.dart';
import 'package:intergalactic/ui/organisms/call_view/call_popped_out_placeholder.dart';
import 'package:intergalactic/ui/organisms/chat/chat.dart';
import 'package:intergalactic/ui/organisms/photo_albums/photo_album_view.dart';
import 'package:intergalactic/ui/organisms/voip_room_view/voip_room_view.dart';
import 'package:intergalactic/ui/onboarding/tutorial_anchor.dart';
import 'package:flutter/material.dart';

class RoomPrimaryView extends StatelessWidget {
  const RoomPrimaryView(
    this.room, {
    super.key,
    this.bypassSpecialRoomTypes = false,
    this.forceCallControlsVisible = false,
  });
  final Room room;
  final bool bypassSpecialRoomTypes;
  final bool forceCallControlsVisible;

  @override
  Widget build(BuildContext context) {
    final key = ValueKey("room-primary-view-${room.localId}");

    if (!bypassSpecialRoomTypes) {
      var photos = room.getComponent<PhotoAlbumRoom>();
      var voip = room.getComponent<VoipRoomComponent>();
      var calendar = room.getComponent<CalendarRoom>();
      var forum = room.getComponent<ForumRoomComponent>();

      if (forum != null) {
        return ForumRoomView(forum, key: key);
      }

      if (voip != null) {
        return ScaledSafeArea(
          bottom: true,
          top: false,
          child: TutorialAnchor(
            id: TutorialAnchorIds.callView,
            child: VoipRoomView(
              voip,
              key: key,
              forceCallControlsVisible: forceCallControlsVisible,
            ),
          ),
        );
      }

      if (photos != null) {
        return PhotoAlbumView(photos, key: key);
      }

      if (calendar?.isCalendarRoom == true) {
        return CalendarRoomView(calendar!, key: key);
      }
    }

    final call = clientManager?.callManager.getCallInRoom(
      room.client,
      room.identifier,
    );

    return Column(
      children: [
        if (call != null)
          Flexible(
            child: StreamBuilder<void>(
              stream: callPopoutController.onChanged,
              builder: (context, _) {
                return callPopoutController.isSessionPoppedOut(call.sessionId)
                    ? CallPoppedOutPlaceholder(call, compact: true)
                    : TutorialAnchor(
                        id: TutorialAnchorIds.callView,
                        child: CallWidget(
                          call,
                          forceControlsVisible: forceCallControlsVisible,
                        ),
                      );
              },
            ),
          ),
        Flexible(child: Chat(room, key: key)),
      ],
    );
  }
}
