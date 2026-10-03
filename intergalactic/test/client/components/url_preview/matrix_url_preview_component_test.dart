import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/url_preview/url_preview_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/components/url_preview/matrix_url_preview_component.dart';
import 'package:intergalactic/client/matrix/components/url_preview/url_preview_durable_cache.dart';
import 'package:intergalactic/client/matrix/components/url_preview/url_preview_direct_fetch_resolver.dart';
import 'package:intergalactic/client/matrix/components/url_preview/url_preview_fallback_fetcher.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/config/app_globals.dart' as globals;
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_url_previews.dart';
import 'package:intergalactic/ui/molecules/url_preview_widget.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.applyUrlPreviewE2EEConsentChoice(allow: true);
    // Direct-fetch fallback is opt-in per room encryption state as of
    // 2026-09-09 (owner decision, url-preview-privacy-routing). This suite
    // predates that gate and exercises the FALLBACK MECHANICS assuming it is
    // available - granting both here keeps its existing coverage meaningful
    // rather than silently degrading it to server-only. The gate itself is
    // pinned in url_preview_direct_fallback_consent_test.dart, including
    // that leaving it ungranted (the real default) blocks the fallback.
    await globals.preferences.allowDirectUrlPreviewFallbackInE2EEChat.set(true);
    await globals.preferences.allowDirectUrlPreviewFallbackInUnencryptedChat
        .set(true);
  });

  group('MatrixUrlPreviewComponent', () {
    test('configured Inter Galactic preview service is homeserver-scoped', () {
      expect(
        MatrixUrlPreviewComponent.canUseIntergalacticPreviewServiceForIdentity(
          homeserver: Uri.parse('https://matrix.ourgalaxy.space'),
          userId: '@preview:ourgalaxy.space',
        ),
        isTrue,
      );
      expect(
        MatrixUrlPreviewComponent.canUseIntergalacticPreviewServiceForIdentity(
          homeserver: Uri.parse('https://example.org'),
          userId: '@preview:ourgalaxy.space',
        ),
        isTrue,
      );
      expect(
        MatrixUrlPreviewComponent.canUseIntergalacticPreviewServiceForIdentity(
          homeserver: Uri.parse('https://example.org'),
          userId: '@preview:example.org',
        ),
        isFalse,
      );
      expect(
        MatrixUrlPreviewComponent.canUseIntergalacticPreviewServiceForIdentity(
          homeserver: Uri.parse('https://example.org'),
          userId: '@preview:example.org',
          allowedHomeservers: 'example.org',
        ),
        isTrue,
      );
      expect(
        MatrixUrlPreviewComponent.canUseIntergalacticPreviewServiceForIdentity(
          homeserver: Uri.parse('https://elsewhere.example'),
          userId: '@preview:example.org:8448',
          allowedHomeservers: 'example.org',
        ),
        isTrue,
      );
    });

    test('Inter Galactic preview HTTP cooldown statuses are explicit', () {
      expect(
        MatrixUrlPreviewComponent.shouldTemporarilyDisableIntergalacticPreviewServiceForStatus(
          404,
        ),
        isTrue,
      );
      expect(
        MatrixUrlPreviewComponent.shouldTemporarilyDisableIntergalacticPreviewServiceForStatus(
          429,
        ),
        isTrue,
      );
      expect(
        MatrixUrlPreviewComponent.shouldTemporarilyDisableIntergalacticPreviewServiceForStatus(
          500,
        ),
        isTrue,
      );
      expect(
        MatrixUrlPreviewComponent.shouldTemporarilyDisableIntergalacticPreviewServiceForStatus(
          400,
        ),
        isFalse,
      );
      expect(
        MatrixUrlPreviewComponent.shouldTemporarilyDisableIntergalacticPreviewServiceForStatus(
          418,
        ),
        isFalse,
      );
    });

    test(
      'warms synced link previews, dedupes URLs, and caches by event',
      () async {
        final mxClient = _FakeMatrixClient('client-a');
        final sdkClient = _FakeSdkClient();
        final room = _FakeRoom(
          identifier: '!room:example.org',
          client: mxClient,
        );
        final link = Uri.parse('https://example.org/article');
        final duplicateLink = Uri.parse('https://example.org/article');
        final skippedLink = Uri.parse('https://example.org/skipped');
        final events = [
          _FakeMessageEvent(eventId: r'$1', links: [link]),
          _FakeMessageEvent(eventId: r'$2', links: [duplicateLink]),
          _FakeMessageEvent(
            eventId: r'$3',
            links: [skippedLink],
            status: TimelineEventStatus.sent,
          ),
          _FakeMessageEvent(eventId: r'$4', links: const []),
        ];
        final timeline = _FakeTimeline(room: room, events: events);

        var responseCalls = 0;
        final component = MatrixUrlPreviewComponent(
          mxClient,
          responseFetcher: (_, __) async {
            responseCalls += 1;
            return {
              'og:title': 'Cached title',
              'og:description': 'Cached description',
            };
          },
          directFetcher: (_) async => null,
          uriNormalizer: (uri) async => uri,
          matrixClientProvider: (_) => sdkClient,
        );

        await component.warmTimelinePreviews(
          timeline,
          limit: 3,
          concurrency: 2,
        );

        expect(responseCalls, 1);
        expect(
          component.getCachedPreview(timeline, events.first)?.title,
          'Cached title',
        );
        expect(component.getCachedPreview(timeline, events[2]), isNull);
      },
    );

    test(
      'warmup caches normalized previews under original event link',
      () async {
        final mxClient = _FakeMatrixClient('client-a');
        final sdkClient = _FakeSdkClient();
        final room = _FakeRoom(
          identifier: '!room:example.org',
          client: mxClient,
        );
        final event = _FakeMessageEvent(
          eventId: r'$1',
          links: [
            Uri.parse(
              'https://alias-cache.example/article?utm_source=timeline',
            ),
          ],
        );
        final timeline = _FakeTimeline(room: room, events: [event]);

        var responseCalls = 0;
        final component = MatrixUrlPreviewComponent(
          mxClient,
          responseFetcher: (_, __) async {
            responseCalls += 1;
            return {
              'og:title': 'Normalized title',
              'og:description': 'Cached description',
            };
          },
          directFetcher: (_) async => null,
          uriNormalizer: (uri) async =>
              Uri(scheme: uri.scheme, host: uri.host, path: uri.path),
          matrixClientProvider: (_) => sdkClient,
        );

        await component.warmTimelinePreviews(timeline);

        expect(responseCalls, 1);
        expect(
          component.getCachedPreview(timeline, event)?.title,
          'Normalized title',
        );
      },
    );

    test(
      'warmup reruns when new requests arrive during an active pass',
      () async {
        final mxClient = _FakeMatrixClient('client-a');
        final sdkClient = _FakeSdkClient();
        final room = _FakeRoom(
          identifier: '!room:example.org',
          client: mxClient,
        );
        final firstEvent = _FakeMessageEvent(
          eventId: r'$1',
          links: [Uri.parse('https://example.org/first')],
        );
        final secondEvent = _FakeMessageEvent(
          eventId: r'$2',
          links: [Uri.parse('https://example.org/second')],
        );
        final timeline = _FakeTimeline(room: room, events: [firstEvent]);
        final firstResponse = Completer<Map<String, Object?>?>();

        var responseCalls = 0;
        final component = MatrixUrlPreviewComponent(
          mxClient,
          responseFetcher: (_, uri) {
            responseCalls += 1;
            if (uri.pathSegments.last == 'first') {
              return firstResponse.future;
            }
            return Future.value({
              'og:title': uri.pathSegments.last,
              'og:description': 'Cached description',
            });
          },
          directFetcher: (_) async => null,
          uriNormalizer: (uri) async => uri,
          matrixClientProvider: (_) => sdkClient,
        );

        final firstWarmup = component.warmTimelinePreviews(
          timeline,
          limit: 1,
          concurrency: 1,
        );
        await _waitFor(() => responseCalls == 1);

        timeline.events.insert(0, secondEvent);
        final secondWarmup = component.warmTimelinePreviews(
          timeline,
          limit: 1,
          concurrency: 1,
        );
        firstResponse.complete({
          'og:title': 'first',
          'og:description': 'Cached description',
        });
        await firstWarmup;
        await secondWarmup;
        await _waitFor(
          () =>
              component.getCachedPreview(timeline, secondEvent)?.title ==
              'second',
        );

        expect(responseCalls, 2);
      },
    );

    test('warmup snapshots events before awaited normalization', () async {
      final mxClient = _FakeMatrixClient('client-a');
      final sdkClient = _FakeSdkClient();
      final room = _FakeRoom(identifier: '!room:example.org', client: mxClient);
      final timeline = _FakeTimeline(
        room: room,
        events: [
          _FakeMessageEvent(
            eventId: r'$1',
            links: [Uri.parse('https://snapshot.example/first')],
          ),
          _FakeMessageEvent(
            eventId: r'$2',
            links: [Uri.parse('https://snapshot.example/second')],
          ),
        ],
      );

      var normalizedCalls = 0;
      var responseCalls = 0;
      final component = MatrixUrlPreviewComponent(
        mxClient,
        responseFetcher: (_, uri) async {
          responseCalls += 1;
          return {
            'og:title': uri.pathSegments.last,
            'og:description': 'Cached description',
          };
        },
        directFetcher: (_) async => null,
        uriNormalizer: (uri) async {
          normalizedCalls += 1;
          if (normalizedCalls == 1) {
            timeline.events.add(
              _FakeMessageEvent(
                eventId: r'$3',
                links: [Uri.parse('https://snapshot.example/third')],
              ),
            );
          }
          await Future<void>.delayed(Duration.zero);
          return uri;
        },
        matrixClientProvider: (_) => sdkClient,
      );

      await component.warmTimelinePreviews(timeline, limit: 2, concurrency: 1);

      expect(responseCalls, 2);
      expect(component.getCachedPreview(timeline, timeline.events[2]), isNull);
    });

    test('warmup respects encrypted-room URL preview preference', () async {
      await globals.preferences.applyUrlPreviewE2EEConsentChoice(allow: false);

      final mxClient = _FakeMatrixClient('client-a');
      final room = _FakeRoom(
        identifier: '!room:example.org',
        client: mxClient,
        isE2EE: true,
      );
      final timeline = _FakeTimeline(
        room: room,
        events: [
          _FakeMessageEvent(
            eventId: r'$1',
            links: [Uri.parse('https://example.org/article')],
          ),
        ],
      );

      var responseCalls = 0;
      final component = MatrixUrlPreviewComponent(
        mxClient,
        responseFetcher: (_, __) async {
          responseCalls += 1;
          return {'og:title': 'Should not load'};
        },
        directFetcher: (_) async => null,
        uriNormalizer: (uri) async => uri,
        matrixClientProvider: (_) => _FakeSdkClient(),
      );

      await component.warmTimelinePreviews(timeline);

      expect(responseCalls, 0);
    });

    test('warmup waits for encrypted-room first-use consent', () async {
      SharedPreferences.setMockInitialValues({});
      await globals.preferences.init();

      final mxClient = _FakeMatrixClient('client-a');
      final room = _FakeRoom(
        identifier: '!room:example.org',
        client: mxClient,
        isE2EE: true,
      );
      final timeline = _FakeTimeline(
        room: room,
        events: [
          _FakeMessageEvent(
            eventId: r'$1',
            links: [Uri.parse('https://example.org/article')],
          ),
        ],
      );

      var responseCalls = 0;
      final component = MatrixUrlPreviewComponent(
        mxClient,
        responseFetcher: (_, __) async {
          responseCalls += 1;
          return {'og:title': 'Should not load'};
        },
        directFetcher: (_) async => null,
        uriNormalizer: (uri) async => uri,
        matrixClientProvider: (_) => _FakeSdkClient(),
      );

      await component.warmTimelinePreviews(timeline);

      expect(
        component.shouldGetPreviewDataForTimelineEvent(
          timeline,
          timeline.events.first,
        ),
        isFalse,
      );
      expect(responseCalls, 0);
    });

    test(
      'encrypted-room cached previews hide when consent is revoked',
      () async {
        final mxClient = _FakeMatrixClient('client-revoked');
        final room = _FakeRoom(
          identifier: '!revoked:example.org',
          client: mxClient,
          isE2EE: true,
        );
        final link = Uri.parse('https://revoked.example/article');
        final event = _FakeMessageEvent(eventId: r'$revoked', links: [link]);
        final timeline = _FakeTimeline(room: room, events: [event]);

        var responseCalls = 0;
        final component = MatrixUrlPreviewComponent(
          mxClient,
          responseFetcher: (_, __) async {
            responseCalls += 1;
            return {
              'og:title': 'Allowed title',
              'og:description': 'Allowed description',
            };
          },
          directFetcher: (_) async => null,
          uriNormalizer: (uri) async => uri,
          matrixClientProvider: (_) => _FakeSdkClient(),
        );

        await component.warmTimelinePreviews(timeline);

        expect(
          component.getCachedPreview(timeline, event)?.title,
          'Allowed title',
        );

        await globals.preferences.applyUrlPreviewE2EEConsentChoice(
          allow: false,
        );

        expect(component.getCachedPreview(timeline, event), isNull);
        expect(
          await component.refreshPreviewAfterImageFailure(
            timeline,
            event,
            UrlPreviewData(link, title: 'Failed image'),
          ),
          isNull,
        );
        expect(responseCalls, 1);
      },
    );

    test(
      'a refresh skipped because previews are off for the room says so',
      () async {
        // Three early returns in refreshPreviewAfterImageFailure run BEFORE
        // its existing 'refreshing cached preview' line, so a capture showing
        // an image error and no refresh line could not distinguish a skip
        // here from a refresh that was never requested. That ambiguity is the
        // whole reason this row exists.
        final mxClient = _FakeMatrixClient('client-a');
        final room = _FakeRoom(
          identifier: '!room:example.org',
          client: mxClient,
          shouldPreviewMedia: false,
        );
        final link = Uri.parse('https://example.org/article');
        final event = _FakeMessageEvent(eventId: r'$1', links: [link]);
        final timeline = _FakeTimeline(room: room, events: [event]);
        final component = MatrixUrlPreviewComponent(
          mxClient,
          responseFetcher: (_, _) async => fail('nothing may be fetched'),
          directFetcher: (_) async => null,
          uriNormalizer: (uri) async => uri,
          matrixClientProvider: (_) => _FakeSdkClient(),
        );

        Log.log.clear();
        expect(
          await component.refreshPreviewAfterImageFailure(
            timeline,
            event,
            UrlPreviewData(link, title: 'Failed image'),
          ),
          isNull,
        );

        final skipped = Log.log
            .where(
              (entry) =>
                  entry.content.contains('URL preview image refresh skipped'),
            )
            .toList();
        expect(skipped, hasLength(1));
        expect(
          skipped.single.content,
          contains('reason=previews_off_for_room'),
        );
        expect(skipped.single.content, contains('host=example.org'));
      },
    );

    test(
      'room media preview preference prevents URL preview fetches',
      () async {
        final mxClient = _FakeMatrixClient('client-a');
        final room = _FakeRoom(
          identifier: '!room:example.org',
          client: mxClient,
          shouldPreviewMedia: false,
        );
        final timeline = _FakeTimeline(
          room: room,
          events: [
            _FakeMessageEvent(
              eventId: r'$1',
              links: [Uri.parse('https://example.org/article')],
            ),
          ],
        );

        var responseCalls = 0;
        final component = MatrixUrlPreviewComponent(
          mxClient,
          responseFetcher: (_, __) async {
            responseCalls += 1;
            return {'og:title': 'Should not load'};
          },
          directFetcher: (_) async => null,
          uriNormalizer: (uri) async => uri,
          matrixClientProvider: (_) => _FakeSdkClient(),
        );

        await component.warmTimelinePreviews(timeline);

        expect(
          component.shouldGetPreviewDataForTimelineEvent(
            timeline,
            timeline.events.first,
          ),
          isFalse,
        );
        expect(responseCalls, 0);
      },
    );

    test('getPreview ignores events with no current links', () async {
      final mxClient = _FakeMatrixClient('client-a');
      final room = _FakeRoom(identifier: '!room:example.org', client: mxClient);
      final event = _FakeMessageEvent(eventId: r'$no-link', links: const []);
      final timeline = _FakeTimeline(room: room, events: [event]);

      var responseCalls = 0;
      final component = MatrixUrlPreviewComponent(
        mxClient,
        responseFetcher: (_, __) async {
          responseCalls += 1;
          return {'og:title': 'Should not load'};
        },
        directFetcher: (_) async => null,
        uriNormalizer: (uri) async => uri,
        matrixClientProvider: (_) => _FakeSdkClient(),
      );

      final preview = await component.getPreview(timeline, event);

      expect(preview, isNull);
      expect(responseCalls, 0);
    });

    test('durable cache hit returns preview without network fetch', () async {
      final prefs = await SharedPreferences.getInstance();
      final durableCache = UrlPreviewDurableCache(
        preferences: prefs,
        prefix: 'url-preview-hit-test',
      );
      final mxClient = _FakeMatrixClient('client-a');
      final sdkClient = _FakeSdkClient();
      final room = _FakeRoom(identifier: '!room:example.org', client: mxClient);
      final event = _FakeMessageEvent(
        eventId: r'$durable-hit',
        links: [Uri.parse('https://durable.example/article')],
      );
      final timeline = _FakeTimeline(room: room, events: [event]);

      await durableCache.put(
        Uri.parse('https://durable.example/article'),
        UrlPreviewData(
          Uri.parse('https://durable.example/article'),
          siteName: 'Durable',
          title: 'Stored title',
          description: 'Stored description',
        ),
      );

      var responseCalls = 0;
      final component = MatrixUrlPreviewComponent(
        mxClient,
        responseFetcher: (_, __) async {
          responseCalls += 1;
          return {'og:title': 'Network title'};
        },
        directFetcher: (_) async => null,
        uriNormalizer: (uri) async => uri,
        matrixClientProvider: (_) => sdkClient,
        durableCache: durableCache,
      );

      final preview = await component.getPreview(timeline, event);

      expect(preview?.title, 'Stored title');
      expect(responseCalls, 0);
      expect(
        component.getCachedPreview(timeline, event)?.title,
        'Stored title',
      );
    });

    test(
      'legacy site-name-only durable preview is evicted and refreshed',
      () async {
        final prefs = await SharedPreferences.getInstance();
        const cachePrefix = 'url-preview-legacy-contentless-test';
        final durableCache = UrlPreviewDurableCache(
          preferences: prefs,
          prefix: cachePrefix,
        );
        final previewUri = Uri.parse('https://www.tiktok.com/@demo/video/123');
        final mxClient = _FakeMatrixClient('client-a');
        final room = _FakeRoom(
          identifier: '!room:example.org',
          client: mxClient,
        );
        final event = _FakeMessageEvent(
          eventId: r'$legacy-tiktok-preview',
          links: [previewUri],
        );
        final timeline = _FakeTimeline(room: room, events: [event]);

        // Seed a current entry, then make its persisted shape match the
        // version-1 generic TikTok fallback seen in the owner capture.
        await durableCache.put(
          previewUri,
          UrlPreviewData(
            previewUri,
            siteName: 'TikTok',
            title: 'Temporary seed title',
          ),
        );
        final entryKey = prefs.getStringList('$cachePrefix.index')!.single;
        final legacy =
            jsonDecode(prefs.getString(entryKey)!) as Map<String, dynamic>;
        legacy
          ..['version'] = 1
          ..['title'] = null
          ..['description'] = null
          ..['posting_account'] = null
          ..['stats'] = null
          ..['image'] = null
          ..['volatile_image'] = null
          ..['volatile_image_omitted'] = false;
        await prefs.setString(entryKey, jsonEncode(legacy));

        var networkCalls = 0;
        final component = MatrixUrlPreviewComponent(
          mxClient,
          responseFetcher: (_, __) async {
            networkCalls += 1;
            return {'og:site_name': 'TikTok', 'og:title': 'Fresh video'};
          },
          directFetcher: (_) async => null,
          uriNormalizer: (uri) async => uri,
          matrixClientProvider: (_) => _FakeSdkClient(),
          durableCache: durableCache,
        );

        final preview = await component.getPreview(timeline, event);

        expect(preview?.title, 'Fresh video');
        expect(networkCalls, 1);
        final refreshed =
            jsonDecode(prefs.getString(entryKey)!) as Map<String, dynamic>;
        expect(refreshed['version'], 2);
      },
    );

    test(
      'TikTok direct preview restores signed thumbnail after restart',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final durableCache = UrlPreviewDurableCache(
          preferences: prefs,
          prefix: 'url-preview-tiktok-image-test',
        );
        final previewUri = Uri.parse(
          'https://www.tiktok.com/@demo/video/1234567890',
        );
        final thumbnailUri = Uri.parse(
          'https://p16-sign-va.tiktokcdn.com/obj/tos-maliva-p-0068/demo.jpeg'
          '?x-expires=1893456000&x-signature=public-cdn-signature',
        );
        final firstClient = _FakeMatrixClient('client-a');
        final secondClient = _FakeMatrixClient('client-b');
        final firstRoom = _FakeRoom(
          identifier: '!room:example.org',
          client: firstClient,
        );
        final secondRoom = _FakeRoom(
          identifier: '!room:example.org',
          client: secondClient,
        );
        final firstEvent = _FakeMessageEvent(
          eventId: r'$tiktok-first',
          links: [previewUri],
        );
        final secondEvent = _FakeMessageEvent(
          eventId: r'$tiktok-second',
          links: [previewUri],
        );
        final firstTimeline = _FakeTimeline(
          room: firstRoom,
          events: [firstEvent],
        );
        final secondTimeline = _FakeTimeline(
          room: secondRoom,
          events: [secondEvent],
        );

        var directCalls = 0;
        var networkCalls = 0;
        final firstComponent = MatrixUrlPreviewComponent(
          firstClient,
          responseFetcher: (_, __) async {
            networkCalls += 1;
            return null;
          },
          directFetcher: (uri) async {
            directCalls += 1;
            return UrlPreviewData(
              uri,
              siteName: 'TikTok',
              title: 'Fresh TikTok preview',
              image: MemoryImage(_transparentPng),
              imageUri: thumbnailUri,
              imageWidth: 1,
              imageHeight: 1,
            );
          },
          uriNormalizer: (uri) async => uri,
          matrixClientProvider: (_) => _FakeSdkClient(),
          durableCache: durableCache,
        );

        final firstPreview = await firstComponent.getPreview(
          firstTimeline,
          firstEvent,
        );

        expect(firstPreview?.image, isA<MemoryImage>());
        expect(directCalls, 1);
        expect(networkCalls, 1);

        final secondComponent = MatrixUrlPreviewComponent(
          secondClient,
          responseFetcher: (_, __) async {
            networkCalls += 1;
            return null;
          },
          directFetcher: (_) async {
            directCalls += 1;
            return null;
          },
          uriNormalizer: (uri) async => uri,
          matrixClientProvider: (_) => _FakeSdkClient(),
          durableCache: durableCache,
        );

        final restoredPreview = await secondComponent.getPreview(
          secondTimeline,
          secondEvent,
        );

        expect(restoredPreview?.title, 'Fresh TikTok preview');
        expect(restoredPreview?.image, isA<NetworkImage>());
        expect(restoredPreview?.imageUri, thumbnailUri);
        expect(directCalls, 1);
        expect(networkCalls, 1);
      },
    );

    test(
      'text-only durable social previews do not refresh missing images',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final durableCache = UrlPreviewDurableCache(
          preferences: prefs,
          prefix: 'url-preview-text-only-social-test',
        );
        final previewUri = Uri.parse('https://www.instagram.com/p/demo/');
        final mxClient = _FakeMatrixClient('client-a');
        final room = _FakeRoom(
          identifier: '!room:example.org',
          client: mxClient,
        );
        final event = _FakeMessageEvent(
          eventId: r'$instagram-text-only',
          links: [previewUri],
        );
        final timeline = _FakeTimeline(room: room, events: [event]);

        await durableCache.put(
          previewUri,
          UrlPreviewData(previewUri, title: 'Text-only social preview'),
        );

        var directCalls = 0;
        var networkCalls = 0;
        final component = MatrixUrlPreviewComponent(
          mxClient,
          responseFetcher: (_, __) async {
            networkCalls += 1;
            return null;
          },
          directFetcher: (_) async {
            directCalls += 1;
            return null;
          },
          uriNormalizer: (uri) async => uri,
          matrixClientProvider: (_) => _FakeSdkClient(),
          durableCache: durableCache,
        );

        final preview = await component.getPreview(timeline, event);

        expect(preview?.title, 'Text-only social preview');
        expect(directCalls, 0);
        expect(networkCalls, 0);
      },
    );

    test(
      'failed missing social thumbnail refresh enters retry cooldown',
      () async {
        final prefs = await SharedPreferences.getInstance();
        final durableCache = UrlPreviewDurableCache(
          preferences: prefs,
          prefix: 'url-preview-missing-image-cooldown-test',
        );
        final previewUri = Uri.parse('https://www.instagram.com/reel/demo/');
        final mxClient = _FakeMatrixClient('client-a');
        final room = _FakeRoom(
          identifier: '!room:example.org',
          client: mxClient,
        );
        final event = _FakeMessageEvent(
          eventId: r'$instagram-missing-image',
          links: [previewUri],
        );
        final timeline = _FakeTimeline(room: room, events: [event]);
        var now = DateTime(2026, 6, 24, 12);

        await durableCache.put(
          previewUri,
          UrlPreviewData(
            previewUri,
            siteName: 'Instagram',
            title: 'Stored reel',
            volatileImageOmitted: true,
          ),
        );

        var directCalls = 0;
        var networkCalls = 0;
        final component = MatrixUrlPreviewComponent(
          mxClient,
          responseFetcher: (_, __) async {
            networkCalls += 1;
            return null;
          },
          directFetcher: (_) async {
            directCalls += 1;
            return null;
          },
          uriNormalizer: (uri) async => uri,
          matrixClientProvider: (_) => _FakeSdkClient(),
          durableCache: durableCache,
          now: () => now,
        );

        final firstPreview = await component.getPreview(timeline, event);
        final secondPreview = await component.getPreview(timeline, event);

        expect(firstPreview?.title, 'Stored reel');
        expect(secondPreview?.title, 'Stored reel');
        expect(directCalls, 1);
        expect(networkCalls, 0);

        now = now.add(const Duration(minutes: 6));
        await component.getPreview(timeline, event);

        expect(directCalls, 2);
        expect(networkCalls, 0);
      },
    );

    test(
      'a durable preview whose only content was a volatile image expires '
      'and retries rather than returning a blank site-name-only card',
      () async {
        // REVIEW, 2026-09-11 (queue row "URL preview: blank TikTok and
        // Instagram cards..."): the emptiness guard in
        // buildPreviewFromResponse only runs when a preview is built fresh
        // from a network response - a durable-cache hit is reconstructed
        // directly from storage and never passes through it. A preview whose
        // only content was a volatile social-CDN image (typical for
        // TikTok/Instagram) has nothing else once that image's TTL expires,
        // and if the refresh that would normally restore it also fails, the
        // cache returned a technically non-null UrlPreviewData with
        // everything null - a card with only a site name. No image error is
        // ever logged for this path, which is why the 2026-09-11 capture
        // showed none: the image was silently dropped by TTL, not by a
        // failed load.
        var now = DateTime(2026, 6, 24, 12);
        final prefs = await SharedPreferences.getInstance();
        final durableCache = UrlPreviewDurableCache(
          preferences: prefs,
          prefix: 'url-preview-durable-empty-after-expiry-test',
          now: () => now,
        );
        final previewUri = Uri.parse('https://www.instagram.com/p/image-only/');
        final mxClient = _FakeMatrixClient('client-a');
        final room = _FakeRoom(
          identifier: '!room:example.org',
          client: mxClient,
        );
        final event = _FakeMessageEvent(
          eventId: r'$instagram-image-only',
          links: [previewUri],
        );
        final timeline = _FakeTimeline(room: room, events: [event]);
        final volatileImageUri = Uri.parse(
          'https://scontent-abc1.cdninstagram.com/pic.jpg?oe=64AB1234',
        );

        await durableCache.put(
          previewUri,
          UrlPreviewData(
            previewUri,
            siteName: 'Instagram',
            imageUri: volatileImageUri,
            image: NetworkImage(volatileImageUri.toString()),
          ),
        );

        // Past the 12-hour volatile-image TTL, but well within the 5-day
        // validTtl - the record is not stale, only its image is gone.
        now = now.add(const Duration(hours: 13));

        var responseCalls = 0;
        final component = MatrixUrlPreviewComponent(
          mxClient,
          responseFetcher: (_, __) async {
            responseCalls += 1;
            return null;
          },
          directFetcher: (_) async => null,
          uriNormalizer: (uri) async => uri,
          matrixClientProvider: (_) => _FakeSdkClient(),
          durableCache: durableCache,
          now: () => now,
        );

        final preview = await component.getPreview(timeline, event);

        expect(preview, isNull);
        expect(responseCalls, 1);
      },
    );

    test('image failure refreshes stale durable thumbnail', () async {
      final prefs = await SharedPreferences.getInstance();
      final durableCache = UrlPreviewDurableCache(
        preferences: prefs,
        prefix: 'url-preview-image-refresh-test',
      );
      final previewUri = Uri.parse('https://example.org/article/42');
      final staleThumbnailUri = Uri.parse(
        'https://static.example.org/stale.jpeg',
      );
      // mxc, because this test is about the REFRESH replacing a stale
      // thumbnail. A third-party https image is now dropped before it can be
      // stored, so an https fixture here would refresh to no image and the
      // test would stop covering what it names.
      final freshThumbnailUri = Uri.parse(
        'mxc://ourgalaxy.space/freshThumbnail',
      );
      final mxClient = _FakeMatrixClient('client-a');
      final sdkClient = _FakeSdkClient();
      final room = _FakeRoom(identifier: '!room:example.org', client: mxClient);
      final event = _FakeMessageEvent(
        eventId: r'$image-refresh',
        links: [previewUri],
      );
      final timeline = _FakeTimeline(room: room, events: [event]);

      await durableCache.put(
        previewUri,
        UrlPreviewData(
          previewUri,
          siteName: 'Example',
          title: 'Stored stale preview',
          image: NetworkImage(staleThumbnailUri.toString()),
          imageUri: staleThumbnailUri,
          imageWidth: 1,
          imageHeight: 1,
        ),
      );

      var networkCalls = 0;
      final component = MatrixUrlPreviewComponent(
        mxClient,
        responseFetcher: (_, __) async {
          networkCalls += 1;
          return {
            'og:site_name': 'Example',
            'og:title': 'Fresh preview',
            'og:image': freshThumbnailUri.toString(),
            'og:image:width': 1,
            'og:image:height': 1,
          };
        },
        directFetcher: (_) async => null,
        uriNormalizer: (uri) async => uri,
        matrixClientProvider: (_) => sdkClient,
        durableCache: durableCache,
      );

      final restoredPreview = await component.getPreview(timeline, event);
      expect(
        (restoredPreview!.image as NetworkImage).url,
        staleThumbnailUri.toString(),
      );
      expect(networkCalls, 0);

      final refreshedPreview = await component.refreshPreviewAfterImageFailure(
        timeline,
        event,
        restoredPreview,
      );

      expect(refreshedPreview?.title, 'Fresh preview');
      // Asserted through imageUri rather than by casting the provider: a
      // homeserver-routed image is a MatrixMxcImage, and the identity that
      // matters here is which image was stored, not which widget renders it.
      expect(refreshedPreview!.image, isNotNull);
      expect(refreshedPreview.imageUri, freshThumbnailUri);
      expect(
        component.getCachedPreview(timeline, event)!.imageUri,
        freshThumbnailUri,
      );
      expect(networkCalls, 1);
    });

    test('expired durable preview returns stale data and refreshes', () async {
      var now = DateTime(2026, 5, 1, 12);
      final prefs = await SharedPreferences.getInstance();
      final durableCache = UrlPreviewDurableCache(
        preferences: prefs,
        prefix: 'url-preview-stale-test',
        now: () => now,
        validTtl: const Duration(days: 1),
      );
      final mxClient = _FakeMatrixClient('client-a');
      final sdkClient = _FakeSdkClient();
      final room = _FakeRoom(identifier: '!room:example.org', client: mxClient);
      final event = _FakeMessageEvent(
        eventId: r'$durable-stale',
        links: [Uri.parse('https://stale.example/article')],
      );
      final timeline = _FakeTimeline(room: room, events: [event]);

      await durableCache.put(
        Uri.parse('https://stale.example/article'),
        UrlPreviewData(
          Uri.parse('https://stale.example/article'),
          siteName: 'Stale',
          title: 'Stored stale title',
        ),
      );
      now = now.add(const Duration(days: 2));

      var responseCalls = 0;
      final component = MatrixUrlPreviewComponent(
        mxClient,
        responseFetcher: (_, __) async {
          responseCalls += 1;
          return {
            'og:title': 'Fresh title',
            'og:description': 'Fresh description',
          };
        },
        directFetcher: (_) async => null,
        uriNormalizer: (uri) async => uri,
        matrixClientProvider: (_) => sdkClient,
        durableCache: durableCache,
        now: () => now,
      );

      final preview = await component.getPreview(timeline, event);

      expect(preview?.title, 'Stored stale title');
      await _waitFor(
        () =>
            component.getCachedPreview(timeline, event)?.title == 'Fresh title',
      );
      expect(responseCalls, 1);
    });

    test('durable invalid sentinel prevents repeated fetch spam', () async {
      final prefs = await SharedPreferences.getInstance();
      final durableCache = UrlPreviewDurableCache(
        preferences: prefs,
        prefix: 'url-preview-invalid-test',
      );
      final mxClient = _FakeMatrixClient('client-a');
      final sdkClient = _FakeSdkClient();
      final room = _FakeRoom(identifier: '!room:example.org', client: mxClient);
      final event = _FakeMessageEvent(
        eventId: r'$durable-invalid',
        links: [Uri.parse('https://invalid.example/article')],
      );
      final timeline = _FakeTimeline(room: room, events: [event]);

      await durableCache.put(
        Uri.parse('https://invalid.example/article'),
        UrlPreviewComponent.invalidPreviewData,
      );

      var responseCalls = 0;
      final component = MatrixUrlPreviewComponent(
        mxClient,
        responseFetcher: (_, __) async {
          responseCalls += 1;
          return {'og:title': 'Should not load'};
        },
        directFetcher: (_) async => null,
        uriNormalizer: (uri) async => uri,
        matrixClientProvider: (_) => sdkClient,
        durableCache: durableCache,
      );

      final first = await component.getPreview(timeline, event);
      final second = await component.getPreview(timeline, event);

      expect(first, UrlPreviewComponent.invalidPreviewData);
      expect(second, UrlPreviewComponent.invalidPreviewData);
      expect(responseCalls, 0);
    });

    test('durable cache refuses URLs with access tokens', () async {
      final prefs = await SharedPreferences.getInstance();
      final durableCache = UrlPreviewDurableCache(
        preferences: prefs,
        prefix: 'url-preview-secret-test',
      );
      final url = Uri.parse(
        'https://secret.example/article?access_token=super-secret',
      );

      await durableCache.put(
        url,
        UrlPreviewData(url, title: 'Should not persist'),
      );

      final hit = await durableCache.get(url, _FakeSdkClient());

      expect(hit, isNull);
      expect(
        prefs.getStringList('url-preview-secret-test.index'),
        anyOf(isNull, isEmpty),
      );
    });

    test('a generic TikTok server preview salvages into a site-name card on '
        'desktop, not only on web', () async {
      // REVIEW, 2026-09-11 (queue row "URL preview: blank TikTok and
      // Instagram cards..."), FEATURES item 1. This salvage branch was
      // gated `kIsWeb &&`, on the assumption its own comment stated - that
      // only web reaches it with directData null, because CORS always
      // blocks a direct TikTok fetch there. The 2026-09-09 consent gate
      // falsified that: a desktop/mobile room with the direct-fetch
      // fallback declined reaches this branch with directData null too,
      // and previously fell through to sanitizeUrlPreviewDataForUri
      // returning null (nothing else survived stripping TikTok's generic
      // marketing title/description) - a blank tile instead of the site
      // name the server actually gave it. kIsWeb is false in this (non-web)
      // test target, so this scenario alone distinguishes the two: it only
      // passes once the gate no longer excludes desktop/mobile.
      final mxClient = _FakeMatrixClient('client-a');
      await globals.preferences.allowDirectUrlPreviewFallbackInUnencryptedChat
          .set(false);

      final component = MatrixUrlPreviewComponent(
        mxClient,
        intergalacticPreviewFetcher: (_) async => null,
        responseFetcher: (_, __) async => {
          'og:title': 'TikTok - Make Your Day',
          'og:description':
              'Watch and discover millions of personalized short videos '
              'on TikTok, trends start here.',
        },
        directFetcher: (_) async {
          fail(
            'directFetcher must not be called once the fallback is '
            'declined',
          );
        },
        uriNormalizer: (uri) async => uri,
      );

      final result = await component.buildPreviewData(
        _FakeSdkClient(),
        Uri.parse('https://www.tiktok.com/@someuser/video/123'),
        roomIsE2EE: false,
      );

      expect(
        result,
        isNotNull,
        reason:
            'the server gave us a site name; that is something, not '
            'nothing, and should render as such on every platform',
      );
      expect(result?.siteName, 'TikTok');
      expect(result?.title, isNull);
      expect(result?.description, isNull);
    });

    test(
      'transient server preview failures keep retrying before cooldown',
      () async {
        final mxClient = _FakeMatrixClient('client-a');
        var intergalacticCalls = 0;
        var homeserverCalls = 0;
        final component = MatrixUrlPreviewComponent(
          mxClient,
          intergalacticPreviewFetcher: (_) async {
            intergalacticCalls += 1;
            throw StateError('preview service unavailable');
          },
          responseFetcher: (_, __) async {
            homeserverCalls += 1;
            return {
              'og:title': 'Homeserver title',
              'og:description': 'Homeserver description',
            };
          },
          directFetcher: (_) async => null,
          uriNormalizer: (uri) async => uri,
        );

        final firstResult = await component.buildPreviewData(
          _FakeSdkClient(),
          Uri.parse('https://fallback.example/article'),
          roomIsE2EE: false,
        );
        final secondResult = await component.buildPreviewData(
          _FakeSdkClient(),
          Uri.parse('https://fallback.example/second'),
          roomIsE2EE: false,
        );

        expect(firstResult?.title, 'Homeserver title');
        expect(secondResult?.title, 'Homeserver title');
        expect(intergalacticCalls, 2);
        expect(homeserverCalls, 2);
        expect(
          component.isIntergalacticPreviewTemporarilyUnavailableForTesting,
          isFalse,
        );
      },
    );

    test('repeated server preview transient failures enter cooldown', () async {
      final mxClient = _FakeMatrixClient('client-a');
      var intergalacticCalls = 0;
      var homeserverCalls = 0;
      final component = MatrixUrlPreviewComponent(
        mxClient,
        intergalacticPreviewFetcher: (_) async {
          intergalacticCalls += 1;
          throw StateError('preview service connection reset');
        },
        responseFetcher: (_, __) async {
          homeserverCalls += 1;
          return {
            'og:title': 'Homeserver title',
            'og:description': 'Homeserver description',
          };
        },
        directFetcher: (_) async => null,
        uriNormalizer: (uri) async => uri,
      );

      for (var i = 0; i < 3; i += 1) {
        await component.buildPreviewData(
          _FakeSdkClient(),
          Uri.parse('https://fallback.example/article-$i'),
          roomIsE2EE: false,
        );
      }

      expect(
        component.isIntergalacticPreviewTemporarilyUnavailableForTesting,
        isTrue,
      );

      await component.buildPreviewData(
        _FakeSdkClient(),
        Uri.parse('https://fallback.example/after-cooldown-started'),
        roomIsE2EE: false,
      );

      expect(intergalacticCalls, 3);
      expect(homeserverCalls, 4);
    });

    test('server preview rejects canonical URLs on a different host', () async {
      final mxClient = _FakeMatrixClient('client-a');
      final originalUrl = Uri.parse('https://safe.example/article');
      final component = MatrixUrlPreviewComponent(
        mxClient,
        responseFetcher: (_, __) async => {
          'og:title': 'Safe title',
          'og:url': 'https://evil.example/phish',
        },
        directFetcher: (_) async => null,
        uriNormalizer: (uri) async => uri,
      );

      final result = await component.buildPreviewData(
        _FakeSdkClient(),
        originalUrl,
        roomIsE2EE: false,
      );

      expect(result?.uri, originalUrl);
    });

    test('server preview accepts same-origin canonical URLs', () async {
      final mxClient = _FakeMatrixClient('client-a');
      final canonicalUrl = Uri.parse('https://www.example.com/article');
      final component = MatrixUrlPreviewComponent(
        mxClient,
        responseFetcher: (_, __) async => {
          'og:title': 'Canonical title',
          'og:url': canonicalUrl.toString(),
        },
        directFetcher: (_) async => null,
        uriNormalizer: (uri) async => uri,
      );

      final result = await component.buildPreviewData(
        _FakeSdkClient(),
        Uri.parse('https://example.com/article?utm_source=chat'),
        roomIsE2EE: false,
      );

      expect(result?.uri, canonicalUrl);
    });

    test('event cache misses when an edited event changes links', () async {
      final mxClient = _FakeMatrixClient('client-a');
      final sdkClient = _FakeSdkClient();
      final room = _FakeRoom(identifier: '!room:example.org', client: mxClient);
      final timeline = _FakeTimeline(room: room, events: const []);
      final originalEvent = _FakeMessageEvent(
        eventId: r'$1',
        links: [Uri.parse('https://example.org/original')],
      );
      final editedEvent = _FakeMessageEvent(
        eventId: r'$1',
        links: [Uri.parse('https://example.org/edited')],
      );

      var responseCalls = 0;
      final component = MatrixUrlPreviewComponent(
        mxClient,
        responseFetcher: (_, uri) async {
          responseCalls += 1;
          return {
            'og:title': uri.pathSegments.last,
            'og:description': 'Cached description',
          };
        },
        directFetcher: (_) async => null,
        uriNormalizer: (uri) async => uri,
        matrixClientProvider: (_) => sdkClient,
      );

      final originalPreview = await component.getPreview(
        timeline,
        originalEvent,
      );
      final editedPreview = await component.getPreview(timeline, editedEvent);

      expect(originalPreview?.title, 'original');
      expect(editedPreview?.title, 'edited');
      expect(responseCalls, 2);
    });

    // Owner decision A, 2026-09-09: this used to be the opposite assertion -
    // a fast direct fetch for a preferred provider was allowed to win a race
    // against a still-pending homeserver/service response, which meant BOTH
    // the provider's CDN and our own service received the request every
    // time, regardless of which answer was used. The service is now awaited
    // FIRST and fully, so a complete server result means direct is never
    // even attempted - proven here by a server response that never resolves
    // slowly, it simply must be given the chance to answer before anything
    // else happens, and completing it with enough data must mean the direct
    // fetcher is never called.
    test('a preferred provider does not start a direct fetch until the service '
        'has answered', () async {
      final mxClient = _FakeMatrixClient('client-a');
      var directCalls = 0;
      var serverCalls = 0;
      final component = MatrixUrlPreviewComponent(
        mxClient,
        responseFetcher: (_, __) async {
          serverCalls += 1;
          return {
            'og:site_name': 'Instagram',
            'og:title': 'Instagram post',
            'og:description': 'Service metadata',
          };
        },
        directFetcher: (uri) {
          directCalls += 1;
          return Future<UrlPreviewData?>.value(
            UrlPreviewData(
              uri,
              siteName: 'Instagram',
              title: 'Instagram post',
              postingAccount: '@example',
              description: 'Direct metadata',
            ),
          );
        },
        uriNormalizer: (uri) async => uri,
      );

      final result = await component.buildPreviewData(
        _FakeSdkClient(),
        Uri.parse('https://www.instagram.com/p/example'),
        roomIsE2EE: false,
      );

      expect(serverCalls, 1);
      expect(
        directCalls,
        0,
        reason:
            'the service answer was complete (score >= 4), so the direct '
            'fallback must never have been attempted at all - not raced, '
            'not started and discarded',
      );
      expect(result?.description, 'Service metadata');
    });

    test('direct fallback waits for a pending preferred response', () async {
      final responseStarted = Completer<void>();
      final response = Completer<Map<String, Object?>?>();
      var directCalls = 0;
      final component = MatrixUrlPreviewComponent(
        _FakeMatrixClient('client-a'),
        responseFetcher: (_, __) {
          responseStarted.complete();
          return response.future;
        },
        directFetcher: (_) async {
          directCalls += 1;
          return null;
        },
      );

      final preview = component.buildPreviewData(
        _FakeSdkClient(),
        Uri.parse('https://www.instagram.com/p/example'),
        roomIsE2EE: false,
      );
      await responseStarted.future;
      expect(directCalls, 0);

      response.complete({'og:title': 'Instagram'});
      await preview;
      expect(directCalls, 1);
    });

    // The other half: when the service answer is genuinely insufficient, the
    // opted-in fallback still runs - this is not a regression to "never use
    // direct", only to "never use it in parallel or without consent".
    test(
      'an insufficient service answer still allows the opted-in fallback',
      () async {
        final mxClient = _FakeMatrixClient('client-a');
        var directCalls = 0;
        final component = MatrixUrlPreviewComponent(
          mxClient,
          responseFetcher: (_, __) async => {'og:title': 'Instagram'},
          directFetcher: (uri) {
            directCalls += 1;
            return Future<UrlPreviewData?>.value(
              UrlPreviewData(
                uri,
                siteName: 'Instagram',
                title: 'Instagram post',
                postingAccount: '@example',
                description: 'Direct metadata',
              ),
            );
          },
          uriNormalizer: (uri) async => uri,
        );

        final result = await component.buildPreviewData(
          _FakeSdkClient(),
          Uri.parse('https://www.instagram.com/p/example'),
          roomIsE2EE: false,
        );

        expect(directCalls, 1);
        expect(result?.description, 'Direct metadata');
      },
    );

    test('expired preview budget does not start a direct fallback', () async {
      final mxClient = _FakeMatrixClient('client-a');
      var directCalls = 0;
      final component = MatrixUrlPreviewComponent(
        mxClient,
        previewBuildDeadline: const Duration(milliseconds: 10),
        responseFetcher: (_, __) async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return {'og:title': 'Instagram'};
        },
        directFetcher: (_) async {
          directCalls += 1;
          return null;
        },
      );

      await component.buildPreviewData(
        _FakeSdkClient(),
        Uri.parse('https://www.instagram.com/p/example'),
        roomIsE2EE: false,
      );

      expect(directCalls, 0);
    });

    test(
      'unsupported homeserver preview endpoint still allows direct fallback',
      () async {
        final mxClient = _FakeMatrixClient('client-a');
        final room = _FakeRoom(
          identifier: '!room:example.org',
          client: mxClient,
        );
        final previewUri = Uri.parse('https://www.instagram.com/reel/demo/');
        final event = _FakeMessageEvent(
          eventId: r'$direct-after-unsupported',
          links: [previewUri],
        );
        final timeline = _FakeTimeline(room: room, events: [event]);

        var directCalls = 0;
        var homeserverCalls = 0;
        final component = MatrixUrlPreviewComponent(
          mxClient,
          responseFetcher: (_, __) async {
            homeserverCalls += 1;
            return {'og:title': 'Homeserver should not be used'};
          },
          directFetcher: (uri) async {
            directCalls += 1;
            return UrlPreviewData(
              uri,
              siteName: 'Instagram',
              title: 'Instagram reel',
            );
          },
          uriNormalizer: (uri) async => uri,
          matrixClientProvider: (_) => _FakeSdkClient(),
        )..serverSupportsUrlPreview = false;

        expect(
          component.shouldGetPreviewDataForTimelineEvent(timeline, event),
          isTrue,
        );

        final result = await component.getPreview(timeline, event);

        expect(result?.title, 'Instagram reel');
        expect(directCalls, 1);
        expect(homeserverCalls, 0);
      },
    );

    test(
      'unsupported homeserver preview endpoint skips generic network fetch',
      () async {
        final mxClient = _FakeMatrixClient('client-a');
        final room = _FakeRoom(
          identifier: '!room:example.org',
          client: mxClient,
        );
        final event = _FakeMessageEvent(
          eventId: r'$generic-after-unsupported',
          links: [Uri.parse('https://x.com/example/status/123')],
        );
        final timeline = _FakeTimeline(room: room, events: [event]);

        var directCalls = 0;
        var homeserverCalls = 0;
        final component = MatrixUrlPreviewComponent(
          mxClient,
          responseFetcher: (_, __) async {
            homeserverCalls += 1;
            return {'og:title': 'Homeserver should not be used'};
          },
          directFetcher: (_) async {
            directCalls += 1;
            return null;
          },
          uriNormalizer: (uri) async => uri,
          matrixClientProvider: (_) => _FakeSdkClient(),
        )..serverSupportsUrlPreview = false;

        expect(
          component.shouldGetPreviewDataForTimelineEvent(timeline, event),
          isFalse,
        );

        final result = await component.getPreview(timeline, event);

        expect(result, isNull);
        expect(directCalls, 0);
        expect(homeserverCalls, 0);
      },
    );

    test(
      'configured preview service still runs after homeserver unsupported',
      () async {
        final mxClient = _FakeMatrixClient('client-a');
        final room = _FakeRoom(
          identifier: '!room:example.org',
          client: mxClient,
        );
        final event = _FakeMessageEvent(
          eventId: r'$service-after-unsupported',
          links: [Uri.parse('https://www.facebook.com/reel/123')],
        );
        final timeline = _FakeTimeline(room: room, events: [event]);

        var intergalacticCalls = 0;
        var homeserverCalls = 0;
        final component = MatrixUrlPreviewComponent(
          mxClient,
          intergalacticPreviewFetcher: (_) async {
            intergalacticCalls += 1;
            return {
              'og:title': 'Service title',
              'og:description': 'Service description',
            };
          },
          responseFetcher: (_, __) async {
            homeserverCalls += 1;
            return {'og:title': 'Homeserver should not be used'};
          },
          directFetcher: (_) async => null,
          uriNormalizer: (uri) async => uri,
          matrixClientProvider: (_) => _FakeSdkClient(),
        )..serverSupportsUrlPreview = false;

        expect(
          component.shouldGetPreviewDataForTimelineEvent(timeline, event),
          isTrue,
        );

        final result = await component.getPreview(timeline, event);

        expect(result?.title, 'Service title');
        expect(intergalacticCalls, 1);
        expect(homeserverCalls, 0);
      },
    );

    // REVERSED AGAIN 2026-09-07, back to dropping. The 2026-09-03 reversal
    // was made on a true symptom - Facebook cards rendered text-only - but its
    // stated reason was false: "no new fetch is introduced, this URL arrives
    // in the homeserver response" confuses a URL with bytes. The homeserver
    // returned a STRING; NetworkImage then made THIS CLIENT connect to fbcdn,
    // handing it the user's IP, TLS fingerprint and User-Agent for a link that
    // may only have been read inside an encrypted room.
    //
    // The text-only symptom had a different cause, fixed separately: the image
    // keys were read in an order that took `og:image:secure_url` (the origin's
    // raw https URL, passed through unrewritten) in preference to `og:image`
    // (which the homeserver rewrites to `mxc://`), so the routable value was
    // discarded and the unroutable one was all that was left to drop.
    test(
      'server previews drop a third-party CDN image rather than fetch it',
      () {
        final component = MatrixUrlPreviewComponent(
          _FakeMatrixClient('client-a'),
        );
        const volatileImageUrl =
            'https://scontent.cdninstagram.com/v/t51.29350/demo.jpg'
            '?stp=dst-jpg&_nc_cat=1&oh=signed-hash&oe=expiry';
        final result = component.buildPreviewFromResponse(
          _FakeSdkClient(),
          Uri.parse('https://www.instagram.com/p/example'),
          {
            'og:site_name': 'Instagram',
            'og:title': 'Instagram post',
            'og:image': volatileImageUrl,
          },
        );

        expect(result?.siteName, 'Instagram');
        expect(result?.title, 'Instagram post');
        expect(
          result?.image,
          isNull,
          reason:
              'rendering this would make the client itself connect to the CDN',
        );
        expect(result?.imageUri, isNull);
        expect(
          result?.volatileImageOmitted,
          isTrue,
          reason:
              'arms the missing-image refresh path, which for Instagram may '
              'recover an image through the direct fetch already allowed',
        );
      },
    );

    // Owner QA 2026-09-03. The site-icon fallback originally lived only inside
    // UrlPreviewFallbackFetcher.fetchPreview, so it decorated the DIRECT
    // fetch's result and nothing else. TikTok and Instagram routinely block a
    // client-side fetch; the card is then assembled from homeserver metadata
    // and never passed through the fallback. Symptom: a card rendering as the
    // bare word "Instagram", or "TikTok @".
    test(
      'a provider preview built from server text still gets the site icon',
      () async {
        final mxClient = _FakeMatrixClient('client-a');
        final sdkClient = _FakeSdkClient();
        final iconUri = Uri.parse(
          'https://www.instagram.com/apple-touch-icon.png',
        );
        var iconCalls = 0;
        final component = MatrixUrlPreviewComponent(
          mxClient,
          responseFetcher: (_, __) async => {
            'og:site_name': 'Instagram',
            'og:title': 'A reel',
          },
          directFetcher: (_) async => null,
          siteIconFetcher: (uri) async {
            iconCalls += 1;
            return UrlPreviewSiteIcon(
              provider: NetworkImage(iconUri.toString()),
              uri: iconUri,
              width: 180,
              height: 180,
            );
          },
          uriNormalizer: (uri) async => uri,
          matrixClientProvider: (_) => sdkClient,
        );

        final result = await component.buildPreviewData(
          sdkClient,
          Uri.parse('https://www.instagram.com/p/example'),
          roomIsE2EE: false,
        );

        expect(result?.siteName, 'Instagram');
        expect(
          result?.imageUri,
          iconUri,
          reason:
              'the direct fetch returned null, which is exactly the case '
              'that used to render as the bare word "Instagram"',
        );
        expect(iconCalls, 1);
      },
    );

    test('a non-provider host is never decorated with a site icon', () async {
      final mxClient = _FakeMatrixClient('client-a');
      final sdkClient = _FakeSdkClient();
      var iconCalls = 0;
      final component = MatrixUrlPreviewComponent(
        mxClient,
        responseFetcher: (_, __) async => {'og:title': 'An article'},
        directFetcher: (_) async => null,
        siteIconFetcher: (uri) async {
          iconCalls += 1;
          return null;
        },
        uriNormalizer: (uri) async => uri,
        matrixClientProvider: (_) => sdkClient,
      );

      final result = await component.buildPreviewData(
        sdkClient,
        Uri.parse('https://example.org/article'),
        roomIsE2EE: false,
      );

      expect(result?.title, 'An article');
      expect(result?.imageUri, isNull);
      expect(
        iconCalls,
        0,
        reason:
            'the icon fetch must stay inside the provider allowlist that '
            '90f75c96 established; an arbitrary host is never fetched',
      );
    });

    test(
      'a server preview that already has an image is not decorated',
      () async {
        final mxClient = _FakeMatrixClient('client-a');
        final sdkClient = _FakeSdkClient();
        var iconCalls = 0;
        final component = MatrixUrlPreviewComponent(
          mxClient,
          responseFetcher: (_, __) async => {
            'og:site_name': 'Instagram',
            'og:title': 'A reel',
            // mxc, because the point of this test is that a real thumbnail is
            // not displaced by the site icon. A third-party https URL is now
            // dropped before it gets that far, which would make this pass for
            // the wrong reason.
            'og:image': 'mxc://ourgalaxy.space/realThumbnail',
          },
          directFetcher: (_) async => null,
          siteIconFetcher: (uri) async {
            iconCalls += 1;
            return null;
          },
          uriNormalizer: (uri) async => uri,
          matrixClientProvider: (_) => sdkClient,
        );

        final result = await component.buildPreviewData(
          sdkClient,
          Uri.parse('https://www.instagram.com/p/example'),
          roomIsE2EE: false,
        );

        expect(
          result?.imageUri.toString(),
          'mxc://ourgalaxy.space/realThumbnail',
        );
        expect(iconCalls, 0, reason: 'a real thumbnail is never displaced');
      },
    );

    test('a slow site icon cannot take the preview down with it', () async {
      // The icon is decoration on a card that is otherwise complete, and it
      // used to be able to destroy one. fetchSiteIcon tries three paths in
      // sequence and each can redirect up to six times at four seconds a hop,
      // so it can outlast the whole build budget - and _fetchAndCachePreview
      // answers that timeout by caching the URL as invalidPreviewData for ten
      // minutes, removing a preview that was complete except for the image and
      // suppressing the retry that would have fixed it.
      final sdkClient = _FakeSdkClient();
      final component = MatrixUrlPreviewComponent(
        _FakeMatrixClient('client-a'),
        responseFetcher: (_, __) async => {
          'og:site_name': 'Instagram',
          'og:title': 'A reel',
        },
        directFetcher: (_) async => null,
        // Never completes: the defect is that the caller waits on it.
        siteIconFetcher: (_) => Completer<UrlPreviewSiteIcon?>().future,
        uriNormalizer: (uri) async => uri,
        matrixClientProvider: (_) => sdkClient,
      );

      final result = await component
          .buildPreviewData(
            sdkClient,
            Uri.parse('https://www.instagram.com/p/example'),
            roomIsE2EE: false,
          )
          // Fails fast rather than hanging the suite if the bound is removed.
          .timeout(const Duration(seconds: 20));

      expect(
        result?.title,
        'A reel',
        reason: 'the preview was complete; only its decoration was missing',
      );
      expect(result?.image, isNull);
    });

    test('a timed-out site icon leaves the text preview cached', () async {
      final mxClient = _FakeMatrixClient('client-a');
      final sdkClient = _FakeSdkClient();
      final previewUri = Uri.parse('https://www.instagram.com/p/slow-icon');
      final room = _FakeRoom(identifier: '!room:example.org', client: mxClient);
      final event = _FakeMessageEvent(
        eventId: r'$slow-icon',
        links: [previewUri],
      );
      final timeline = _FakeTimeline(room: room, events: [event]);
      var responseCalls = 0;
      var iconCalls = 0;
      final component = MatrixUrlPreviewComponent(
        mxClient,
        previewBuildDeadline: const Duration(milliseconds: 750),
        responseFetcher: (_, __) async {
          responseCalls += 1;
          return {'og:site_name': 'Instagram', 'og:title': 'A reel'};
        },
        directFetcher: (_) async => null,
        siteIconFetcher: (_) {
          iconCalls += 1;
          return Completer<UrlPreviewSiteIcon?>().future;
        },
        uriNormalizer: (uri) async => uri,
        matrixClientProvider: (_) => sdkClient,
      );

      final first = await component.getPreview(timeline, event);
      final cached = await component.getPreview(timeline, event);

      expect(first?.title, 'A reel');
      expect(cached?.title, 'A reel');
      expect(iconCalls, 1);
      expect(responseCalls, 1);
    });

    test('a Facebook CDN thumbnail is dropped, not fetched by the client', () {
      // The reported case. Facebook is NOT in shouldPreferDirectFetch, so
      // unlike Instagram there is no recovery path: if the homeserver does not
      // give this image as `mxc://`, the card renders without one. That is the
      // cost of not connecting to fbcdn from the user's device, and it is the
      // right side of the trade - the alternative discloses the user's IP to
      // Meta for a link they may only have read in an encrypted room.
      final component = MatrixUrlPreviewComponent(
        _FakeMatrixClient('client-a'),
      );
      const fbImageUrl =
          'https://scontent-lhr8-1.xx.fbcdn.net/v/t39.30808-6/demo.jpg'
          '?_nc_cat=100&ccb=1-7&_nc_ohc=abc&oh=signed&oe=6700AAAA';
      final result = component.buildPreviewFromResponse(
        _FakeSdkClient(),
        Uri.parse('https://www.facebook.com/some/post/1234'),
        {
          'og:site_name': 'Facebook',
          'og:title': 'Facebook post',
          'og:image': fbImageUrl,
        },
      );

      expect(result?.image, isNull);
      expect(result?.imageUri, isNull);
      expect(result?.title, 'Facebook post', reason: 'the card still renders');
    });

    test('a Facebook preview keeps its image when the homeserver rewrote it', () {
      // The other half of the same reported case, and the one that should be
      // the common shape: `/preview_url` downloads the origin image into the
      // homeserver's own media repository and returns `mxc://`. Rendering that
      // fetches from the homeserver, so the image survives AND Meta never sees
      // the client. This is what the image-key ordering used to throw away.
      final component = MatrixUrlPreviewComponent(
        _FakeMatrixClient('client-a'),
      );
      final result = component.buildPreviewFromResponse(
        _FakeSdkClient(),
        Uri.parse('https://www.facebook.com/some/post/1234'),
        {
          'og:site_name': 'Facebook',
          'og:title': 'Facebook post',
          'og:image:secure_url':
              'https://scontent-lhr8-1.xx.fbcdn.net/v/demo.jpg?oh=signed',
          'og:image': 'mxc://ourgalaxy.space/facebookThumb',
        },
      );

      expect(result?.image, isNotNull);
      expect(
        result?.imageUri.toString(),
        'mxc://ourgalaxy.space/facebookThumb',
        reason: 'the unrewritten secure_url must not win over the routable mxc',
      );
    });

    test(
      'generic complete server previews do not start direct fallback',
      () async {
        final mxClient = _FakeMatrixClient('client-a');
        var directCalls = 0;
        final component = MatrixUrlPreviewComponent(
          mxClient,
          responseFetcher: (_, __) async => {
            'og:site_name': 'Example',
            'og:title': 'Server title',
            'og:description': 'Server description',
          },
          directFetcher: (_) async {
            directCalls += 1;
            return null;
          },
          uriNormalizer: (uri) async => uri,
        );

        final result = await component.buildPreviewData(
          _FakeSdkClient(),
          Uri.parse('https://example.org/article'),
          roomIsE2EE: false,
        );

        expect(result?.title, 'Server title');
        expect(directCalls, 0);
      },
    );

    test(
      'generic incomplete server previews do not start direct fallback',
      () async {
        final mxClient = _FakeMatrixClient('client-a');
        var directCalls = 0;
        final component = MatrixUrlPreviewComponent(
          mxClient,
          responseFetcher: (_, __) async => {'og:title': 'Server title'},
          directFetcher: (_) async {
            directCalls += 1;
            return UrlPreviewData(
              Uri.parse('https://example.org/article'),
              title: 'Direct title',
              description: 'Direct description',
            );
          },
          uriNormalizer: (uri) async => uri,
        );

        final result = await component.buildPreviewData(
          _FakeSdkClient(),
          Uri.parse('https://example.org/article'),
          roomIsE2EE: false,
        );

        expect(result?.title, 'Server title');
        expect(directCalls, 0);
      },
    );

    test('direct fallback fetcher ignores unsupported generic hosts', () async {
      final result = await UrlPreviewFallbackFetcher.fetchPreview(
        Uri.parse('https://example.org/article'),
      ).timeout(const Duration(seconds: 1));

      expect(result, isNull);
    });

    test('direct fallback rejects local and private network URLs', () {
      final blockedUrls = [
        'http://localhost:8080/status',
        'http://service.localhost/status',
        'http://preview.local/status',
        'http://metadata/latest/meta-data',
        'http://metadata.google.internal/computeMetadata/v1/',
        'http://127.0.0.1:8080/status',
        'http://10.0.0.12/status',
        'http://100.64.0.1/status',
        'http://169.254.169.254/latest/meta-data',
        'http://172.16.0.12/status',
        'http://172.31.255.255/status',
        'http://192.168.1.20/status',
        'http://198.18.0.1/status',
        'http://[::1]/status',
        'http://[::ffff:127.0.0.1]/status',
        'http://[fd00::1]/status',
        'http://[fe80::1]/status',
      ];

      for (final value in blockedUrls) {
        expect(
          UrlPreviewFallbackFetcher.isSafeDirectFetchUri(Uri.parse(value)),
          isFalse,
          reason: value,
        );
      }

      final allowedUrls = [
        'https://www.tiktok.com/@demo/video/123456',
        'https://www.instagram.com/p/example',
        'https://example.org/article',
      ];

      for (final value in allowedUrls) {
        expect(
          UrlPreviewFallbackFetcher.isSafeDirectFetchUri(Uri.parse(value)),
          isTrue,
          reason: value,
        );
      }
    });

    test(
      'direct fallback DNS guard rejects local resolved addresses',
      () async {
        expect(
          await isDirectFetchDnsSafe(Uri.parse('http://127.0.0.1/status')),
          isFalse,
        );
        expect(
          await isDirectFetchDnsSafe(Uri.parse('http://[::1]/status')),
          isFalse,
        );
      },
    );
  });

  group('UrlPreviewWidget', () {
    testWidgets('uses supplied bubble color in message mode', (tester) async {
      const bubbleColor = Color(0xFF123456);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(
            useMaterial3: true,
          ).copyWith(extensions: [const ThemeSettings()]),
          home: Scaffold(
            body: UrlPreviewWidget(
              UrlPreviewData(
                Uri.parse('https://example.org/preview'),
                siteName: 'Example',
                title: 'Preview title',
              ),
              messageBubbleMode: true,
              bubbleColor: bubbleColor,
            ),
          ),
        ),
      );

      expect(_hasDecoratedBoxColor(tester, bubbleColor), isTrue);
    });

    testWidgets('falls back to surfaceContainerLow in message mode', (
      tester,
    ) async {
      const fallbackColor = Color(0xFF654321);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(useMaterial3: true).copyWith(
            colorScheme: ThemeData.light(
              useMaterial3: true,
            ).colorScheme.copyWith(surfaceContainerLow: fallbackColor),
            extensions: [const ThemeSettings()],
          ),
          home: Scaffold(
            body: UrlPreviewWidget(
              UrlPreviewData(
                Uri.parse('https://example.org/preview'),
                siteName: 'Example',
                title: 'Preview title',
              ),
              messageBubbleMode: true,
            ),
          ),
        ),
      );

      expect(_hasDecoratedBoxColor(tester, fallbackColor), isTrue);
    });
  });

  group('TimelineEventViewUrlPreviews', () {
    testWidgets('keeps the timeline at bottom when preview data arrives', (
      tester,
    ) async {
      final controller = ScrollController();
      final completer = Completer<UrlPreviewData?>();
      final timeline = _previewTimeline();
      final component = _CompleterUrlPreviewComponent(completer);

      await _pumpPreviewList(
        tester,
        controller: controller,
        timeline: timeline,
        component: component,
      );

      expect(controller.offset, controller.position.minScrollExtent);

      completer.complete(_previewDataWithImage());
      await tester.pump();
      await tester.pumpAndSettle();

      expect(controller.offset, controller.position.minScrollExtent);
    });

    testWidgets('does not snap to bottom when the user has scrolled up', (
      tester,
    ) async {
      final controller = ScrollController();
      final completer = Completer<UrlPreviewData?>();
      final timeline = _previewTimeline();
      final component = _CompleterUrlPreviewComponent(completer);

      await _pumpPreviewList(
        tester,
        controller: controller,
        timeline: timeline,
        component: component,
      );

      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      final scrolledOffset = controller.offset;

      completer.complete(_previewDataWithImage());
      await tester.pump();
      await tester.pumpAndSettle();

      expect(controller.offset, greaterThan(50));
      expect(controller.offset, greaterThanOrEqualTo(scrolledOffset));
    });

    testWidgets('uses the URL preview skeleton while preview is loading', (
      tester,
    ) async {
      final controller = ScrollController();
      final completer = Completer<UrlPreviewData?>();
      final timeline = _previewTimeline();
      final component = _CompleterUrlPreviewComponent(completer);

      await _pumpPreviewList(
        tester,
        controller: controller,
        timeline: timeline,
        component: component,
      );

      expect(find.byType(UrlPreviewWidget), findsOneWidget);
      expect(
        tester.getSize(find.byType(UrlPreviewWidget)).height,
        greaterThan(100),
      );

      completer.complete(null);
      await tester.pump();
      await tester.pumpAndSettle();
    });
  });
}

Future<void> _pumpPreviewList(
  WidgetTester tester, {
  required ScrollController controller,
  required Timeline timeline,
  required UrlPreviewComponent component,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.light(
        useMaterial3: true,
      ).copyWith(extensions: [const ThemeSettings()]),
      home: Scaffold(
        body: SizedBox(
          height: 220,
          child: ListView(
            controller: controller,
            reverse: true,
            children: [
              TimelineEventViewUrlPreviews(
                index: 0,
                timeline: timeline,
                component: component,
              ),
              const SizedBox(height: 520),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

bool _hasDecoratedBoxColor(WidgetTester tester, Color color) {
  return tester
      .widgetList<DecoratedBox>(find.byType(DecoratedBox))
      .map((box) => box.decoration)
      .whereType<BoxDecoration>()
      .any((decoration) => decoration.color == color);
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not met before timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

_FakeTimeline _previewTimeline() {
  final client = _FakeMatrixClient('client-a');
  final room = _FakeRoom(identifier: '!room:example.org', client: client);
  return _FakeTimeline(
    room: room,
    events: [
      _FakeMessageEvent(
        eventId: r'$preview',
        links: [Uri.parse('https://example.org/preview')],
      ),
    ],
  );
}

UrlPreviewData _previewDataWithImage() {
  return UrlPreviewData(
    Uri.parse('https://example.org/preview'),
    siteName: 'Example',
    title: 'Preview title',
    description: 'Preview description',
    image: MemoryImage(_transparentPng),
    imageWidth: 1,
    imageHeight: 1,
  );
}

final Uint8List _transparentPng = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1f,
  0x15,
  0xc4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0a,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9c,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0d,
  0x0a,
  0x2d,
  0xb4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4e,
  0x44,
  0xae,
  0x42,
  0x60,
  0x82,
]);

class _FakeMatrixClient implements MatrixClient {
  _FakeMatrixClient(this.identifier);

  @override
  final String identifier;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSdkClient implements matrix.Client {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRoom implements Room {
  _FakeRoom({
    required this.identifier,
    required this.client,
    this.isE2EE = false,
    this.shouldPreviewMedia = true,
  });

  @override
  final String identifier;

  @override
  final Client client;

  @override
  final bool isE2EE;

  @override
  final bool shouldPreviewMedia;

  @override
  Timeline? get timeline => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTimeline extends Timeline {
  _FakeTimeline({required Room room, required List<TimelineEvent> events}) {
    this.room = room;
    client = room.client;
    this.events = List<TimelineEvent>.from(events);
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
  Stream<void> get onLoadingStatusChanged => const Stream.empty();

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

class _FakeMessageEvent implements TimelineEventMessage {
  _FakeMessageEvent({
    required this.eventId,
    required List<Uri> links,
    this.status = TimelineEventStatus.synced,
  }) : _links = links;

  final List<Uri> _links;

  @override
  final String eventId;

  @override
  final TimelineEventStatus status;

  @override
  String get senderId => '@sender:example.org';

  @override
  DateTime get originServerTs => DateTime(2026, 5, 5);

  @override
  String get plainTextBody => _links.map((uri) => uri.toString()).join(' ');

  @override
  String get source => plainTextBody;

  @override
  bool get editable => true;

  @override
  String? get body => plainTextBody;

  @override
  String? get bodyFormat => null;

  @override
  String? get formattedBody => plainTextBody;

  @override
  List<Attachment>? get attachments => null;

  @override
  Widget? buildFormattedContent({Timeline? timeline}) => null;

  @override
  List<Uri>? getLinks({Timeline? timeline}) =>
      _links.isEmpty ? null : List<Uri>.from(_links);

  @override
  String getPlaintextBody(Timeline timeline) => plainTextBody;

  @override
  bool isEdited(Timeline timeline) => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CompleterUrlPreviewComponent implements UrlPreviewComponent {
  _CompleterUrlPreviewComponent(this.completer);

  final Completer<UrlPreviewData?> completer;

  @override
  Client get client => _FakeMatrixClient('client-a');

  @override
  Future<UrlPreviewData?> getPreview(Timeline timeline, TimelineEvent event) {
    return completer.future;
  }

  @override
  UrlPreviewData? getCachedPreview(Timeline timeline, TimelineEvent event) {
    return null;
  }

  @override
  Future<UrlPreviewData?> getPreviewForUrl(Room room, Uri url) async {
    return null;
  }

  @override
  Future<UrlPreviewData?> refreshPreviewAfterImageFailure(
    Timeline timeline,
    TimelineEvent event,
    UrlPreviewData failedData,
  ) async {
    return null;
  }

  @override
  bool shouldGetPreviewDataForTimelineEvent(
    Timeline timeline,
    TimelineEvent event,
  ) {
    return true;
  }

  @override
  bool shouldGetPreviewsInRoom(Room room) {
    return true;
  }

  @override
  Future<void> warmTimelinePreviews(
    Timeline timeline, {
    int limit = 8,
    int concurrency = 2,
  }) async {}
}
