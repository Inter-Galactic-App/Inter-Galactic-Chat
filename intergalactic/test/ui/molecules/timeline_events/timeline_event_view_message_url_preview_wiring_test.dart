// PR #387 CI failure (dart-gates run 2327), found by REVIEW: 09eb1931 added
// `onPreviewVisibilityChanged: _onPreviewVisibilityChanged` to the
// TimelineEventViewReply(...) call in timeline_event_view_message.dart
// instead of the TimelineEventViewUrlPreviews(...) call right below it, which
// is the widget that actually declares the parameter. That was a compile
// error (undefined_named_parameter on TimelineEventViewReply), and even fixed
// to compile, a copy-paste onto the wrong constructor would have left the
// callback silently never delivered - a link-only message's body would never
// come back once its preview loaded or failed.
//
// timeline_event_view_url_previews_test.dart could not have caught either
// shape: it passes the callback straight into TimelineEventViewUrlPreviews,
// so it tests that widget in isolation and has no way to see which
// constructor call in its PARENT actually received the callback. This test
// exercises the wiring one level up - TimelineEventViewMessage itself, with
// its previewMedia component faked so the whole path from "preview resolves"
// to "body text disappears" runs for real.
//
// SCOPE, per REVIEW (2026-09-10): this covers the HIDE direction
// (onPreviewVisibilityChanged(true)) with an armed assertion - remove the
// wiring and the body text stays, failing `findsNothing`. It does NOT cover
// RESTORE (a previously-hidden body coming back via
// onPreviewVisibilityChanged(false) on the SAME event), because
// TimelineEventViewUrlPreviews.refreshSameEvent has no path back to that:
// once `data` is non-null it deliberately keeps it rather than re-requesting
// (its own doc comment - "a preview is on screen, keep it", a real contract,
// not a gap here or in url_previews_test.dart, which also only exercises
// single cold-start true/false transitions, never true-then-false on one
// event). The second case below (a sibling event whose preview never
// resolves) is a no-regression check on a body that was never hidden - it
// passes with or without the fix under test, so do not read it as wiring
// coverage for the false direction.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/client/components/url_preview/url_preview_component.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/client/permissions.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_message.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

const String _linkOnlyBody = 'https://example.org/interesting-article';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.layoutOverride.set('mobile');
    await globals.preferences.bubbleMessages.set(true);
  });

  Widget subject({
    required Timeline timeline,
    required int index,
    required int updateRevision,
  }) {
    return MaterialApp(
      theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
        body: SizedBox(
          width: 800,
          child: TimelineEventViewMessage(
            timeline: timeline,
            index: index,
            updateRevision: updateRevision,
            previewMedia: true,
          ),
        ),
      ),
    );
  }

  testWidgets(
    "a link-only message's body hides once its preview resolves (a sibling "
    "message whose preview never resolves is a no-regression check, not "
    'wiring coverage - see the file header)',
    (tester) async {
      // Two events rather than one event reused: TimelineEventViewUrlPreviews
      // deliberately does NOT re-request once it already holds a resolved
      // preview (refreshSameEvent's "a preview is on screen, keep it" branch;
      // that is a real, separate contract, not a gap in this test) - so
      // driving a second preview outcome on the SAME event under an
      // updateRevision bump would never call getPreview again and would
      // prove nothing. A second event at a different index forces a fresh
      // setStateFromIndex, which is the realistic way this widget starts a
      // new preview request.
      final resolvingCompleter = Completer<UrlPreviewData?>();
      final failingCompleter = Completer<UrlPreviewData?>();
      final resolvingEvent = _FakeLinkOnlyMessageEvent(id: r'$resolving');
      final failingEvent = _FakeLinkOnlyMessageEvent(id: r'$failing');
      final previewComponent = _FakeUrlPreviewComponent(
        onGetPreview: (_, event) => event.eventId == resolvingEvent.eventId
            ? resolvingCompleter.future
            : failingCompleter.future,
      );
      final client = _FakeClient(previewComponent: previewComponent);
      final timeline = _FakeTimeline(
        client: client,
        events: [resolvingEvent, failingEvent],
      );

      await tester.pumpWidget(
        subject(timeline: timeline, index: 0, updateRevision: 0),
      );
      await tester.pump();

      expect(
        find.text(_linkOnlyBody),
        findsOneWidget,
        reason:
            'no preview has resolved yet - the link text is the only '
            'content this message has, so it must still be shown while the '
            'preview loads',
      );

      resolvingCompleter.complete(
        UrlPreviewData(
          Uri.parse(_linkOnlyBody),
          title: 'An interesting article',
        ),
      );
      // Two pumps: one for the Future to complete, one for the setState it
      // triggers via onPreviewVisibilityChanged.
      await tester.pump();
      await tester.pump();

      expect(
        find.text(_linkOnlyBody),
        findsNothing,
        reason:
            'this is the exact wiring the CI failure broke: '
            'TimelineEventViewUrlPreviews reporting a resolved preview must '
            'reach TimelineEventViewMessage._onPreviewVisibilityChanged and '
            'hide the redundant link text',
      );

      // Switch to the sibling event, whose preview will fail to resolve.
      await tester.pumpWidget(
        subject(timeline: timeline, index: 1, updateRevision: 0),
      );
      await tester.pump();

      failingCompleter.complete(null);
      await tester.pump();
      await tester.pump();

      expect(
        find.text(_linkOnlyBody),
        findsOneWidget,
        reason:
            'NOT armed for the false direction: this body was never hidden '
            'to begin with (knownPreviewData was null at load), so this '
            'passes whether or not onPreviewVisibilityChanged is wired at '
            'all. It only proves the fix does not regress a message whose '
            'preview never resolves - see the file header for why a genuine '
            'hidden-then-restored case is not reachable here.',
      );
    },
  );

  testWidgets(
    "a link-only message hides its body even when getLinks' HTML-derived "
    'URL is truncated at an entity-encoded query parameter',
    (tester) async {
      // Owner-reported, 2026-09-11: a TikTok link with an `&` in its query
      // string (`?is_from_webapp=1&sender_device=pc`) kept its raw URL
      // visible next to the resolved preview. Root cause: getLinks reads the
      // HTML formatted body, where `&` is entity-encoded as `&amp;`, and the
      // URL regex does not match `;` - so the HTML-derived link truncates at
      // `&amp` while the plaintext body has the real, untruncated URL with a
      // literal `&`. The truncated string is never a substring of the real
      // one, so the old _messageIsOnlyPreviewLinks (which compared getLinks'
      // Uris against the plaintext) found "leftover" text and never hid the
      // body - even though the preview loaded for the wrong, truncated URL.
      //
      // This fake models exactly that mismatch: getLinks returns the
      // truncated Uri a pre-fix reading of an HTML body would produce, while
      // plainTextBody carries the real one. The fix must decide link-only-
      // ness from plainTextBody alone, so this must hide the body regardless
      // of what getLinks returns.
      const realUrl =
          'https://www.tiktok.com/@u/video/1?is_from_webapp=1&sender_device=pc';
      const truncatedFromHtml =
          'https://www.tiktok.com/@u/video/1?is_from_webapp=1&amp';
      final resolvingCompleter = Completer<UrlPreviewData?>();
      final event = _FakeAmpTruncatedLinkEvent(
        id: r'$amp-truncated',
        plainText: realUrl,
        truncatedLink: Uri.parse(truncatedFromHtml),
      );
      final previewComponent = _FakeUrlPreviewComponent(
        onGetPreview: (_, __) => resolvingCompleter.future,
      );
      final client = _FakeClient(previewComponent: previewComponent);
      final timeline = _FakeTimeline(client: client, events: [event]);

      await tester.pumpWidget(
        subject(timeline: timeline, index: 0, updateRevision: 0),
      );
      await tester.pump();
      expect(find.text(realUrl), findsOneWidget);

      resolvingCompleter.complete(
        UrlPreviewData(Uri.parse(realUrl), title: 'A TikTok video'),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.text(realUrl),
        findsNothing,
        reason:
            'link-only-ness must be decided from plainTextBody alone, not '
            "by comparing getLinks' HTML-derived (and here, truncated) Uri "
            'against it',
      );
    },
  );
}

class _FakeUrlPreviewComponent implements UrlPreviewComponent<_FakeClient> {
  _FakeUrlPreviewComponent({
    required Future<UrlPreviewData?> Function(
      Timeline timeline,
      TimelineEvent event,
    )
    onGetPreview,
  }) : _onGetPreview = onGetPreview;

  final Future<UrlPreviewData?> Function(Timeline timeline, TimelineEvent event)
  _onGetPreview;

  @override
  late final _FakeClient client;

  @override
  Future<UrlPreviewData?> getPreview(Timeline timeline, TimelineEvent event) =>
      _onGetPreview(timeline, event);

  @override
  bool shouldGetPreviewDataForTimelineEvent(
    Timeline timeline,
    TimelineEvent event,
  ) => true;

  @override
  bool shouldGetPreviewsInRoom(Room room) => true;

  @override
  UrlPreviewData? getCachedPreview(Timeline timeline, TimelineEvent event) =>
      null;

  @override
  Future<UrlPreviewData?> getPreviewForUrl(Room room, Uri url) async => null;

  @override
  Future<UrlPreviewData?> refreshPreviewAfterImageFailure(
    Timeline timeline,
    TimelineEvent event,
    UrlPreviewData failedData,
  ) async => null;

  @override
  Future<void> warmTimelinePreviews(
    Timeline timeline, {
    int limit = 8,
    int concurrency = 2,
  }) async {}
}

class _FakeLinkOnlyMessageEvent implements TimelineEventMessage {
  _FakeLinkOnlyMessageEvent({required String id}) : _id = id;

  final String _id;

  @override
  String get eventId => _id;

  @override
  String get senderId => '@alice:example.org';

  @override
  DateTime get originServerTs => DateTime.utc(2026, 9, 10, 10);

  @override
  TimelineEventStatus get status => TimelineEventStatus.synced;

  @override
  String get plainTextBody => _linkOnlyBody;

  @override
  String get source => '{}';

  @override
  bool get editable => false;

  @override
  String? get body => _linkOnlyBody;

  @override
  String? get bodyFormat => null;

  @override
  String? get formattedBody => null;

  @override
  List<Attachment>? get attachments => null;

  @override
  Widget? buildFormattedContent({Timeline? timeline}) => Text(_linkOnlyBody);

  @override
  String getPlaintextBody(Timeline timeline) => _linkOnlyBody;

  @override
  bool isEdited(Timeline timeline) => false;

  @override
  List<Uri>? getLinks({Timeline? timeline}) => [Uri.parse(_linkOnlyBody)];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Models the mismatch a truncated, HTML-entity-decoded getLinks Uri leaves
/// against the real plainTextBody - see the test that constructs this.
class _FakeAmpTruncatedLinkEvent implements TimelineEventMessage {
  _FakeAmpTruncatedLinkEvent({
    required String id,
    required String plainText,
    required Uri truncatedLink,
  }) : _id = id,
       _plainText = plainText,
       _truncatedLink = truncatedLink;

  final String _id;
  final String _plainText;
  final Uri _truncatedLink;

  @override
  String get eventId => _id;

  @override
  String get senderId => '@alice:example.org';

  @override
  DateTime get originServerTs => DateTime.utc(2026, 9, 11, 10);

  @override
  TimelineEventStatus get status => TimelineEventStatus.synced;

  @override
  String get plainTextBody => _plainText;

  @override
  String get source => '{}';

  @override
  bool get editable => false;

  @override
  String? get body => _plainText;

  @override
  String? get bodyFormat => 'org.matrix.custom.html';

  @override
  String? get formattedBody => _plainText;

  @override
  List<Attachment>? get attachments => null;

  @override
  Widget? buildFormattedContent({Timeline? timeline}) => Text(_plainText);

  @override
  String getPlaintextBody(Timeline timeline) => _plainText;

  @override
  bool isEdited(Timeline timeline) => false;

  @override
  List<Uri>? getLinks({Timeline? timeline}) => [_truncatedLink];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTimeline extends Timeline {
  _FakeTimeline({
    required _FakeClient client,
    required List<TimelineEvent> events,
  }) {
    room = _FakeRoom(client: client);
    this.client = client;
    this.events = List<TimelineEvent>.of(events);
  }

  @override
  bool get canLoadFuture => false;

  @override
  bool get canLoadHistory => false;

  @override
  bool get isLoadingFuture => false;

  @override
  bool get isLoadingHistory => false;

  @override
  Stream<void> get onLoadingStatusChanged => const Stream<void>.empty();

  @override
  Future<void> close() async {}

  @override
  bool canDeleteEvent(TimelineEvent event) => false;

  @override
  void deleteEvent(TimelineEvent event) {}

  @override
  Future<TimelineEvent?> fetchEventByIdInternal(String eventId) async => null;

  @override
  bool isEventRedacted(TimelineEvent event) => false;

  @override
  Future<void> loadMoreFuture() async {}

  @override
  Future<void> loadMoreHistory() async {}

  @override
  void markAsRead(TimelineEvent event) {}
}

class _FakeRoom implements Room {
  _FakeRoom({required this.client});

  @override
  final Client client;

  @override
  String get identifier => '!room:example.org';

  @override
  String get localId => '${client.identifier}:$identifier';

  @override
  bool get shouldPreviewMedia => true;

  @override
  Stream<void> get onUpdate => const Stream<void>.empty();

  @override
  Permissions get permissions => _FakePermissions();

  @override
  Member getMemberOrFallback(String id) => _FakeMember(id);

  @override
  T? getComponent<T extends RoomComponent>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePermissions extends Permissions {}

class _FakeClient implements Client {
  _FakeClient({required _FakeUrlPreviewComponent previewComponent})
    : _previewComponent = previewComponent,
      self = const _FakeProfile('@self:example.org') {
    previewComponent.client = this;
  }

  final _FakeUrlPreviewComponent _previewComponent;

  @override
  final Profile self;

  @override
  String get identifier => 'client-${self.identifier}';

  @override
  bool get supportsE2EE => true;

  @override
  T? getComponent<T extends Component>() =>
      _previewComponent is T ? _previewComponent as T : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfile implements Profile {
  const _FakeProfile(this.identifier);

  @override
  final String identifier;

  @override
  String get displayName => identifier;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMember implements Member {
  _FakeMember(this.identifier);

  @override
  final String identifier;

  @override
  String get displayName => identifier;

  @override
  String get userName => identifier;

  @override
  ImageProvider? get avatar => null;

  @override
  Color get defaultColor => Colors.blue;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
