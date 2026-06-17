import 'dart:async';
import 'dart:convert';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/atoms/room_text_button.dart';
import 'package:intergalactic/ui/molecules/image_select_dialog.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:intergalactic/utils/picker_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:implicitly_animated_list/implicitly_animated_list.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

const favoritesBannerMaxPreferenceChars = 350 * 1024;
const _favoritesBannerTargetWidth = 1400;
const _favoritesBannerTargetHeight = 460;
const _favoritesBannerMinWidth = 360;

@visibleForTesting
int favoritesBannerBase64LengthForBytes(int byteLength) {
  return ((byteLength + 2) ~/ 3) * 4;
}

@visibleForTesting
Uint8List normalizeFavoritesBannerImageBytes(
  Uint8List bytes, {
  int maxEncodedChars = favoritesBannerMaxPreferenceChars,
}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    return bytes;
  }

  img.Image working = decoded;
  final widthScale = _favoritesBannerTargetWidth / decoded.width;
  final heightScale = _favoritesBannerTargetHeight / decoded.height;
  final scale = widthScale < heightScale ? widthScale : heightScale;
  if (scale < 1) {
    working = img.copyResize(
      decoded,
      width: (decoded.width * scale).round().clamp(1, decoded.width).toInt(),
      height: (decoded.height * scale).round().clamp(1, decoded.height).toInt(),
      interpolation: img.Interpolation.average,
    );
  }

  Uint8List best = Uint8List.fromList(img.encodeJpg(working, quality: 86));
  for (final quality in const [86, 80, 74, 68, 62]) {
    final encoded = Uint8List.fromList(
      img.encodeJpg(working, quality: quality),
    );
    best = encoded;
    if (favoritesBannerBase64LengthForBytes(encoded.length) <=
        maxEncodedChars) {
      return encoded;
    }
  }

  var resizeWidth = working.width;
  var resizeHeight = working.height;
  while (resizeWidth > _favoritesBannerMinWidth) {
    resizeWidth =
        (resizeWidth * 0.82).round().clamp(1, resizeWidth - 1).toInt();
    resizeHeight =
        (resizeHeight * 0.82).round().clamp(1, resizeHeight - 1).toInt();
    working = img.copyResize(
      working,
      width: resizeWidth,
      height: resizeHeight,
      interpolation: img.Interpolation.average,
    );
    best = Uint8List.fromList(img.encodeJpg(working, quality: 70));
    if (favoritesBannerBase64LengthForBytes(best.length) <= maxEncodedChars) {
      return best;
    }
  }

  return best;
}

class FavoriteRoomsList extends StatefulWidget {
  const FavoriteRoomsList({
    super.key,
    required this.clientManager,
    this.filterClient,
    this.onRoomSelected,
    this.emptyMessage = "Star a room to add it to Favorites.",
    this.showHeader = false,
    this.header = "Favorites",
  });

  final ClientManager clientManager;
  final Client? filterClient;
  final Function(Room room, {bool bypassSpecialRoomType})? onRoomSelected;
  final String emptyMessage;
  final bool showHeader;
  final String header;

  @override
  State<FavoriteRoomsList> createState() => _FavoriteRoomsListState();
}

class _FavoriteRoomsListState extends State<FavoriteRoomsList> {
  late final List<StreamSubscription> subscriptions;
  Room? selectedRoom;

  @override
  void initState() {
    super.initState();
    subscriptions = [
      EventBus.onSelectedRoomChanged.stream.listen((room) {
        if (mounted) {
          setState(() {
            selectedRoom = room;
          });
        }
      }),
      preferences.onSettingChanged.listen((_) {
        if (mounted) {
          setState(() {});
        }
      }),
      widget.clientManager.onRoomAdded.listen((_) {
        if (mounted) {
          setState(() {});
        }
      }),
      widget.clientManager.onRoomRemoved.listen((_) {
        if (mounted) {
          setState(() {});
        }
      }),
    ];
  }

  @override
  void dispose() {
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  List<Room> get favoriteRooms {
    final favoriteIds = preferences.getFavoriteRoomIds();
    final order = <String, int>{
      for (var i = 0; i < favoriteIds.length; i++) favoriteIds[i]: i,
    };

    final rooms = widget.clientManager.rooms.where((room) {
      if (widget.filterClient != null && room.client != widget.filterClient) {
        return false;
      }

      return preferences.isRoomFavorite(
        room.favoriteStorageId,
        legacyRoomId: room.localId,
      );
    }).toList();

    int sortOrder(Room room) {
      final stableOrder = order[room.favoriteStorageId];
      final legacyOrder = order[room.localId];
      if (stableOrder == null) return legacyOrder ?? favoriteIds.length;
      if (legacyOrder == null) return stableOrder;
      return stableOrder < legacyOrder ? stableOrder : legacyOrder;
    }

    rooms.sort((a, b) => sortOrder(a).compareTo(sortOrder(b)));

    return rooms;
  }

  @override
  Widget build(BuildContext context) {
    final rooms = favoriteRooms;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showHeader) _buildFavoritesHeader(context),
        if (rooms.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: tiamat.Text.labelLow(widget.emptyMessage),
          )
        else
          ImplicitlyAnimatedList(
            itemData: rooms,
            shrinkWrap: true,
            initialAnimation: false,
            padding: const EdgeInsets.all(0),
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (context, room) {
              return RoomTextButton(
                room,
                onTap: widget.onRoomSelected,
                highlight: selectedRoom == room,
              );
            },
          ),
      ],
    );
  }

  ImageProvider? _favoritesBannerImage() {
    final data = preferences.favoritesBannerImageData.value;
    if (data == null || data.isEmpty) {
      return null;
    }

    try {
      return Image.memory(base64Decode(data)).image;
    } catch (_) {
      return null;
    }
  }

  Widget _buildFavoritesHeader(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final banner = _favoritesBannerImage();

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 132,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: banner != null ? scheme.surfaceContainerHighest : null,
                  image: banner != null
                      ? DecorationImage(image: banner, fit: BoxFit.contain)
                      : null,
                  gradient: banner == null
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            scheme.primary,
                            Color.lerp(scheme.primary, scheme.secondary, 0.55)!,
                            scheme.secondaryContainer,
                          ],
                        )
                      : null,
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.55),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    widget.header,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: tiamat.CircleButton(
                    icon: Icons.photo,
                    onPressed: () => _changeFavoritesBanner(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _changeFavoritesBanner(BuildContext context) async {
    final currentImage = _favoritesBannerImage();
    final action = await ImageSelectDialog.show(
      context,
      image: currentImage,
      title: "Favorites Banner",
    );
    if (!mounted || action == null || action == ImageEditAction.cancel) {
      return;
    }

    if (action == ImageEditAction.remove) {
      await preferences.favoritesBannerImageData.set(null);
      return;
    }

    final bytes = await PickerUtils.pickImageAndCrop(
      context,
      aspectRatio: 700 / 230,
    );
    if (bytes == null) {
      return;
    }

    final normalizedBytes = normalizeFavoritesBannerImageBytes(bytes);
    final encoded = base64Encode(normalizedBytes);
    if (encoded.length > favoritesBannerMaxPreferenceChars) {
      Log.w(
        "favoritesBanner: selected image still too large "
        "inputBytes=${bytes.length} storedBytes=${normalizedBytes.length} "
        "encodedChars=${encoded.length}",
        category: LogCategory.media,
        source: "favorites-banner",
      );
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text("Banner is too large. Please pick a smaller image."),
        ),
      );
      return;
    }

    if (normalizedBytes.length != bytes.length) {
      Log.i(
        "favoritesBanner: normalized selected image "
        "inputBytes=${bytes.length} storedBytes=${normalizedBytes.length}",
        category: LogCategory.media,
        source: "favorites-banner",
      );
    }

    await preferences.favoritesBannerImageData.set(encoded);
  }
}
