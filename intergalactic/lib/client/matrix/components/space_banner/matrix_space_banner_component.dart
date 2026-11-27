import 'dart:typed_data';

import 'package:intergalactic/client/components/space_banner/space_banner_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_mxc_image_provider.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';
import 'package:flutter/painting.dart';

class MatrixSpaceBannerComponent
    implements SpaceBannerComponent<MatrixClient, MatrixSpace> {
  static const String key = "page.codeberg.everypizza.room.banner";

  Uri? _cachedBannerUri;
  ImageProvider<Object>? _cachedBanner;

  @override
  ImageProvider<Object>? get banner {
    final state = space.matrixRoom.getState(key);
    if (state == null) {
      _clearCachedBanner();
      return null;
    }

    final url = state.content["url"] as String?;
    if (url == null) {
      _clearCachedBanner();
      return null;
    }

    if (!url.startsWith("mxc://")) {
      _clearCachedBanner();
      return null;
    }

    final uri = Uri.parse(url);
    if (_cachedBannerUri == uri && _cachedBanner != null) {
      return _cachedBanner;
    }

    _cachedBannerUri = uri;
    _cachedBanner = MatrixMxcImage(uri, client.matrixClient);
    return _cachedBanner;
  }

  @override
  MatrixClient client;

  @override
  MatrixSpace space;

  MatrixSpaceBannerComponent(this.client, this.space);

  void _clearCachedBanner() {
    _cachedBannerUri = null;
    _cachedBanner = null;
  }

  @override
  Future<void> setBanner(Uint8List data, {String? mimeType}) async {
    var uploadResponse =
        await client.matrixClient.uploadContent(data, contentType: mimeType);

    await client.matrixClient.setRoomStateWithKey(
      space.matrixRoom.id,
      key,
      '',
      {
        'url': uploadResponse.toString(),
        if (mimeType != null) 'mimetype': mimeType,
      },
    );
    space.notifyUpdate();
  }

  @override
  Future<void> removeBanner() async {
    await client.matrixClient.setRoomStateWithKey(
      space.matrixRoom.id,
      key,
      '',
      {},
    );
    space.notifyUpdate();
  }

  @override
  bool get canEditBanner => space.matrixRoom.canChangeStateEvent(key);
}
