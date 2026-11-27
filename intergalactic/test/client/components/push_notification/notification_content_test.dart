import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/cache/file_provider.dart';
import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_sticker.dart';

void main() {
  group('NotificationAttachmentPresentation', () {
    test('uses type-first wording for an image filename', () {
      final presentation = NotificationAttachmentPresentation.fromAttachments([
        _imageAttachment(name: 'vacation.png', mimeType: 'image/png'),
      ], body: 'vacation.png');

      expect(presentation?.type, NotificationAttachmentType.image);
      expect(presentation?.typeLabel, 'Sent an image');
      expect(presentation?.caption, isNull);
      expect(presentation?.displayText, 'Sent an image');
      expect(presentation?.preview, isNotNull);
    });

    test('treats a whitespace-only body as no caption at all', () {
      final presentation = NotificationAttachmentPresentation.fromAttachments([
        _imageAttachment(name: 'vacation.png', mimeType: 'image/png'),
      ], body: '   ');

      // An empty trimmed body used to come back as '', which put a bare
      // newline after the label and showed a blank second line in the shade.
      expect(presentation?.caption, isNull);
      expect(presentation?.displayText, 'Sent an image');
      expect(
        presentation?.displayText.endsWith(String.fromCharCode(10)),
        isFalse,
      );
    });

    test('retains a real attachment caption without the filename', () {
      final presentation = NotificationAttachmentPresentation.fromAttachments([
        _imageAttachment(name: 'vacation.png', mimeType: 'image/png'),
      ], body: 'Look at this sunset');

      expect(presentation?.caption, 'Look at this sunset');
      expect(presentation?.displayText, 'Sent an image\nLook at this sunset');
      expect(presentation?.displayText, isNot(contains('vacation.png')));
    });

    test('classifies videos, files, and GIFs', () {
      final video = NotificationAttachmentPresentation.fromAttachments([
        VideoAttachment(
          _FakeFileProvider('clip.mp4'),
          name: 'clip.mp4',
          mimeType: 'video/mp4',
        ),
      ]);
      final file = NotificationAttachmentPresentation.fromAttachments([
        FileAttachment(
          _FakeFileProvider('brief.pdf'),
          name: 'brief.pdf',
          mimeType: 'application/pdf',
        ),
      ]);
      final gif = NotificationAttachmentPresentation.fromAttachments([
        _imageAttachment(name: 'party.gif', mimeType: 'image/gif'),
      ]);

      expect(video?.typeLabel, 'Sent a video');
      expect(file?.typeLabel, 'Sent a file');
      expect(gif?.typeLabel, 'Sent a GIF');
    });

    test('uses a video thumbnail when one is available', () {
      final thumbnail = MemoryImage(Uint8List.fromList(const [1, 2, 3, 4]));
      final presentation = NotificationAttachmentPresentation.fromAttachments([
        VideoAttachment(
          _FakeFileProvider('clip.mp4'),
          name: 'clip.mp4',
          mimeType: 'video/mp4',
          thumbnail: thumbnail,
        ),
      ]);

      expect(presentation?.preview, same(thumbnail));
    });
  });

  group('MessageNotificationContent attachment body', () {
    test(
      'resolves content to the attachment label, not the filename',
      () async {
        final content = await MessageNotificationContent.fromEvent(
          _FakeMessageEvent(
            attachments: [
              _imageAttachment(name: 'photo_2024.jpg', mimeType: 'image/jpeg'),
            ],
            body: 'photo_2024.jpg',
          ),
          _FakeRoom(),
        );

        // macOS, Linux, Windows and web read `content` directly rather than the
        // presentation, so leaving the raw body here showed them the filename
        // while Android and iOS showed the label.
        expect(content?.content, 'Sent an image');
        expect(content?.content, isNot(contains('photo_2024.jpg')));
      },
    );

    test('leaves a plain message body alone', () async {
      final content = await MessageNotificationContent.fromEvent(
        _FakeMessageEvent(attachments: null, body: 'see you at six'),
        _FakeRoom(),
      );

      expect(content?.content, 'see you at six');
    });
  });

  group('MessageNotificationContent sticker presentation', () {
    test('uses semantic sticker text and retains PNG/WebP previews', () async {
      final room = _FakeRoom();

      for (final name in ['sticker.png', 'sticker.webp']) {
        final image = MemoryImage(Uint8List.fromList(const [1, 2, 3, 4]));
        final content = await MessageNotificationContent.fromEvent(
          _FakeStickerEvent(name: name, image: image),
          room,
        );

        expect(content?.attachmentPresentation?.displayText, 'Sent a sticker');
        expect(content?.attachedImage, same(image));
        expect(content?.attachmentPresentation?.preview, same(image));
        expect(
          content?.attachmentPresentation?.displayText,
          isNot(contains(name)),
        );
      }
    });

    test('uses semantic GIF text and retains the GIF preview', () async {
      final image = MemoryImage(Uint8List.fromList(const [1, 2, 3, 4]));
      final content = await MessageNotificationContent.fromEvent(
        _FakeStickerEvent(name: 'picker.gif', image: image, isAnimated: true),
        _FakeRoom(),
      );

      expect(content?.attachmentPresentation?.displayText, 'Sent a GIF');
      expect(content?.attachedImage, same(image));
      expect(content?.attachmentPresentation?.preview, same(image));
      expect(
        content?.attachmentPresentation?.displayText,
        isNot(contains('picker.gif')),
      );
    });

    test('uses GIF semantics for animated WebP picker media', () async {
      final image = MemoryImage(Uint8List.fromList(const [1, 2, 3, 4]));
      final content = await MessageNotificationContent.fromEvent(
        _FakeStickerEvent(name: 'picker.webp', image: image, isAnimated: true),
        _FakeRoom(),
      );

      expect(content?.attachmentPresentation?.displayText, 'Sent a GIF');
      expect(content?.attachmentPresentation?.preview, same(image));
    });
  });
}

ImageAttachment _imageAttachment({
  required String name,
  required String mimeType,
}) => ImageAttachment(
  MemoryImage(Uint8List.fromList(const [1, 2, 3, 4])),
  _FakeFileProvider(name),
  name: name,
  mimeType: mimeType,
);

class _FakeFileProvider implements FileProvider {
  const _FakeFileProvider(this.fileIdentifier);

  @override
  final String fileIdentifier;

  @override
  Stream<DownloadProgress>? get onProgressChanged => null;

  @override
  Future<Uint8List?> getFileData() async => Uint8List(0);

  @override
  Future<Uri?> resolve() async => Uri.parse('memory:$fileIdentifier');

  @override
  Future<void> save(String filepath) async {}
}

class _FakeStickerEvent
    implements TimelineEventSticker, TimelineEventAnimatedSticker {
  _FakeStickerEvent({
    required this.name,
    required this.image,
    this.isAnimated = false,
  });

  final String name;
  final ImageProvider image;
  final bool isAnimated;

  @override
  String get stickerName => name;

  @override
  ImageProvider get stickerImage => image;

  @override
  bool get isAnimatedSticker => isAnimated;

  @override
  String get plainTextBody => name;

  @override
  String get eventId => r'$sticker-event';

  @override
  String get senderId => '@sender:example.org';

  @override
  DateTime get originServerTs => DateTime.utc(2026, 8, 13);

  @override
  String get source => '';

  @override
  TimelineEventStatus get status => TimelineEventStatus.synced;

  @override
  bool get editable => false;
}

class _FakeRoom implements Room {
  _FakeRoom() : client = _FakeClient();

  @override
  final _FakeClient client;

  @override
  String get displayName => 'Room';

  @override
  String get identifier => '!room:example.org';

  @override
  Future<Member> fetchMember(String id) async => _FakeMember(id);

  @override
  Future<ImageProvider<Object>?> getShortcutImage() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient implements Client {
  @override
  String get identifier => 'client';

  @override
  T? getComponent<T extends Component>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMember implements Member {
  _FakeMember(this.identifier);

  @override
  final String identifier;

  @override
  String get displayName => 'Sender';

  @override
  ImageProvider<Object>? get avatar => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMessageEvent implements TimelineEventMessage {
  _FakeMessageEvent({required this.attachments, required String body})
    : _body = body;

  final String _body;

  @override
  final List<Attachment>? attachments;

  @override
  String? get body => _body;

  @override
  String get plainTextBody => _body;

  @override
  String? get bodyFormat => null;

  @override
  String? get formattedBody => null;

  @override
  String get eventId => r'$message-event';

  @override
  String get senderId => '@sender:example.org';

  @override
  DateTime get originServerTs => DateTime.utc(2026, 8, 17);

  @override
  String get source => '';

  @override
  TimelineEventStatus get status => TimelineEventStatus.synced;

  @override
  bool get editable => true;

  @override
  String getPlaintextBody(Timeline timeline) => _body;

  @override
  Widget? buildFormattedContent({Timeline? timeline}) => null;

  @override
  bool isEdited(Timeline timeline) => false;

  @override
  List<Uri>? getLinks({Timeline? timeline}) => null;
}
