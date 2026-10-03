import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/url_preview/url_preview_component.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/molecules/url_preview_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

/// A preview image failure has to leave a trace where it is FIRST seen.
///
/// REVIEW, 2026-09-11: the owner's capture was read as ruling a cause out
/// because it held no image-error lines - but nothing on this path could emit
/// one, so the absence proved nothing. The capture separately carries four
/// unattributed "Could not getPixels for frame N" decode failures that
/// preview images could well have produced.
///
/// These cases assert the LINE, because a capture is what anyone reads, and
/// they pin the two fields that decide what to do with a failure: which page
/// it belongs to (paired with the resolved line's `host=`) and whether the
/// image was the homeserver's or a third party's.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    Log.log.clear();
  });

  Future<void> pumpAndFail(WidgetTester tester, UrlPreviewData data) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
        home: Scaffold(body: UrlPreviewWidget(data, onImageError: (_, _) {})),
      ),
    );
    // No seam: the image is a real NetworkImage, which flutter_test answers
    // with a 400, so the widget's own errorBuilder runs the production path.
    // A test-only entry point would have proved the logging works without
    // proving anything is wired to it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  String imageErrorLine() {
    final lines = Log.log
        .where((entry) => entry.content.contains('URL preview image error'))
        .toList();
    // Arming: without this every `contains` below passes on an empty list.
    expect(
      lines,
      hasLength(1),
      reason: 'exactly one line per distinct failed image',
    );
    return lines.single.content;
  }

  testWidgets('a third-party image failure is logged with its page host', (
    tester,
  ) async {
    await pumpAndFail(
      tester,
      UrlPreviewData(
        Uri.parse('https://www.instagram.com/p/example'),
        siteName: 'Instagram',
        title: 'A post',
        image: NetworkImage('https://scontent-cdn.example/thumb.jpg'),
        imageUri: Uri.parse('https://scontent-cdn.example/thumb.jpg'),
      ),
    );

    final line = imageErrorLine();
    // host= matches the resolved line's field, so one preview can be followed
    // end to end through a capture.
    expect(line, contains('host=www.instagram.com'));
    expect(line, contains('image_kind=third_party'));
    expect(line, contains('image_host=scontent-cdn.example'));
  });

  testWidgets('a homeserver image failure is distinguished from a third-party '
      'one', (tester) async {
    await pumpAndFail(
      tester,
      UrlPreviewData(
        Uri.parse('https://example.org/article'),
        siteName: 'Example',
        title: 'An article',
        image: NetworkImage('https://ourgalaxy.space/_matrix/media/abc123'),
        imageUri: Uri.parse('mxc://ourgalaxy.space/abc123'),
      ),
    );

    // The distinction decides whose failure it is: an mxc failure is ours to
    // fix, a third-party one may be the CDN expiring a URL.
    expect(imageErrorLine(), contains('image_kind=mxc'));
  });

  testWidgets('the same failed image is not logged twice', (tester) async {
    final data = UrlPreviewData(
      Uri.parse('https://example.org/article'),
      siteName: 'Example',
      title: 'An article',
      image: NetworkImage('https://example.org/thumb.jpg'),
      imageUri: Uri.parse('https://example.org/thumb.jpg'),
    );

    await pumpAndFail(tester, data);
    // Rebuild with the same data: the error repeats on every rebuild, and a
    // line per rebuild would bury the capture this exists to make readable.
    await pumpAndFail(tester, data);

    imageErrorLine();
  });
}
