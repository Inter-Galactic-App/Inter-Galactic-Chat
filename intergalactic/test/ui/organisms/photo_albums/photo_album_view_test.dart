import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/photo_album_room/photo.dart';
import 'package:intergalactic/client/components/photo_album_room/photo_album_entry.dart';
import 'package:intergalactic/client/components/photo_album_room/photo_album_room_component.dart';
import 'package:intergalactic/client/components/photo_album_room/photo_album_timeline.dart';
import 'package:intergalactic/config/app_globals.dart' as globals;
import 'package:intergalactic/ui/organisms/photo_albums/photo_album_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.layoutOverride.set('desktop');
  });

  testWidgets('desktop add menu has a local Material ancestor', (tester) async {
    final component = _FakePhotoAlbumRoom();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(useMaterial3: true).copyWith(
          extensions: [
            const ThemeSettings(),
          ],
        ),
        home: SizedBox(
          width: 800,
          height: 600,
          child: PhotoAlbumView(component),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(PopupMenuButton<PhotoAlbumUploadMode>), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<PhotoAlbumUploadMode>));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Individual photo'), findsOneWidget);
    expect(find.text('Photo stack'), findsOneWidget);
  });
}

class _FakePhotoAlbumRoom implements PhotoAlbumRoom<Client, Room> {
  _FakePhotoAlbumRoom() : room = _FakeRoom(_FakeClient());

  @override
  final Room room;

  @override
  Client get client => room.client;

  @override
  bool get canUpload => true;

  @override
  Future<PhotoAlbumTimeline> getTimeline() async => _FakePhotoAlbumTimeline();

  @override
  Future<void> uploadPhotos(
    List<PickedPhoto> photos, {
    PhotoAlbumUploadMode mode = PhotoAlbumUploadMode.individual,
    bool sendOriginal = false,
    bool extractMetadata = true,
  }) async {}
}

class _FakePhotoAlbumTimeline implements PhotoAlbumTimeline {
  @override
  Stream<int> get onAdded => const Stream<int>.empty();

  @override
  Stream<int> get onChanged => const Stream<int>.empty();

  @override
  Stream<int> get onRemoved => const Stream<int>.empty();

  @override
  List<Photo> get photos => const [];

  @override
  List<PhotoAlbumEntry> get entries => const [];

  @override
  bool get canLoadMorePhotos => false;

  @override
  Future<void> loadMorePhotos() async {}
}

class _FakeRoom implements Room {
  _FakeRoom(this.client);

  @override
  final Client client;

  @override
  String get identifier => '!photo:example.org';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient implements Client {
  @override
  String get identifier => 'client-a';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
