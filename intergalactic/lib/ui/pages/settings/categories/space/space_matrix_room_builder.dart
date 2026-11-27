import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';

class SpaceMatrixRoomBuilder extends StatefulWidget {
  const SpaceMatrixRoomBuilder({
    required this.space,
    required this.builder,
    super.key,
  });

  final MatrixSpace space;
  final Widget Function(BuildContext context, MatrixRoom room) builder;

  @override
  State<SpaceMatrixRoomBuilder> createState() => _SpaceMatrixRoomBuilderState();
}

class _SpaceMatrixRoomBuilderState extends State<SpaceMatrixRoomBuilder> {
  MatrixRoom? _room;
  bool _ownsRoom = false;

  @override
  void initState() {
    super.initState();
    _attachToSpace(widget.space);
  }

  @override
  void didUpdateWidget(covariant SpaceMatrixRoomBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.space == widget.space &&
        oldWidget.space.matrixRoom.id == widget.space.matrixRoom.id) {
      return;
    }

    _releaseRoom();
    _attachToSpace(widget.space);
  }

  @override
  void dispose() {
    _releaseRoom();
    super.dispose();
  }

  void _attachToSpace(MatrixSpace space) {
    final existingRoom = space.client.getRoom(space.matrixRoom.id);
    if (existingRoom is MatrixRoom) {
      _room = existingRoom;
      _ownsRoom = false;
      return;
    }

    _room = MatrixRoom(
      space.client as MatrixClient,
      space.matrixRoom,
      space.matrixRoom.client,
    );
    _ownsRoom = true;
  }

  void _releaseRoom() {
    final room = _room;
    final ownsRoom = _ownsRoom;
    _room = null;
    _ownsRoom = false;

    if (ownsRoom && room != null) {
      unawaited(room.close());
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    if (room == null) {
      return const SizedBox.shrink();
    }

    return widget.builder(context, room);
  }
}
