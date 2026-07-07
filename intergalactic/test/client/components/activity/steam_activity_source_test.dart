import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/activity/sources/steam/steam_activity_source.dart';
import 'package:intergalactic/client/components/activity/sources/steam/steam_api_client.dart';

void main() {
  group('SteamPlayerSummaryParser', () {
    test('parses active game summaries into game activity', () {
      final summary = const SteamPlayerSummaryParser().parse({
        'response': {
          'players': [
            {
              'steamid': '76561198000000000',
              'personaname': 'Pilot',
              'profileurl': 'https://steamcommunity.com/id/pilot/',
              'communityvisibilitystate': 3,
              'gameid': '730',
              'gameextrainfo': 'Counter-Strike 2',
              'game_thumbnail_url':
                  'https://activity.example.test/thumbs/cs2.jpg',
            },
          ],
        },
      });

      final activity = summary?.toActivity();

      expect(activity, isNotNull);
      expect(activity!.id, 'steam');
      expect(activity.kind, ActivityKind.game);
      expect(activity.provider, 'steam');
      expect(activity.title, 'Counter-Strike 2');
      expect(activity.subtitle, 'Steam');
      expect(activity.status, 'Playing');
      expect(
        activity.artworkUrl,
        'https://activity.example.test/thumbs/cs2.jpg',
      );
      expect(activity.externalUrl, 'https://store.steampowered.com/app/730');
      expect(activity.metadata['steam_id'], '76561198000000000');
      expect(activity.metadata['app_id'], '730');
      expect(
        activity.metadata['artwork_url'],
        'https://activity.example.test/thumbs/cs2.jpg',
      );
      expect(activity.metadata['persona_name'], 'Pilot');
    });

    test('prefers relay compact game icons over wide artwork', () {
      final summary = const SteamPlayerSummaryParser().parse({
        'response': {
          'players': [
            {
              'steamid': '76561198000000000',
              'gameid': '730',
              'gameextrainfo': 'Counter-Strike 2',
              'game_icon_url': 'https://activity.example.test/icons/cs2.png',
              'game_artwork_url':
                  'https://activity.example.test/capsules/cs2.jpg',
            },
          ],
        },
      });

      final activity = summary?.toActivity();

      expect(
        activity?.artworkUrl,
        'https://activity.example.test/icons/cs2.png',
      );
      expect(
        activity?.metadata['game_icon_url'],
        'https://activity.example.test/icons/cs2.png',
      );
      expect(
        activity?.metadata['game_artwork_url'],
        'https://activity.example.test/capsules/cs2.jpg',
      );
    });

    test(
      'falls back to valid relay artwork when compact icons are invalid',
      () {
        final summary = const SteamPlayerSummaryParser().parse({
          'response': {
            'players': [
              {
                'steamid': '76561198000000000',
                'gameid': '730',
                'gameextrainfo': 'Counter-Strike 2',
                'game_icon_url': 'javascript:alert(1)',
                'game_artwork_url':
                    'https://activity.example.test/capsules/cs2.jpg',
              },
            ],
          },
        });

        final activity = summary?.toActivity();

        expect(
          activity?.artworkUrl,
          'https://activity.example.test/capsules/cs2.jpg',
        );
        expect(activity?.metadata.containsKey('game_icon_url'), isFalse);
      },
    );

    test(
      'falls back to deterministic Steam artwork when no thumbnail is sent',
      () {
        final summary = const SteamPlayerSummaryParser().parse({
          'response': {
            'players': [
              {
                'steamid': '76561198000000000',
                'gameid': '730',
                'gameextrainfo': 'Counter-Strike 2',
              },
            ],
          },
        });

        final activity = summary?.toActivity();

        expect(
          activity?.artworkUrl,
          'https://cdn.cloudflare.steamstatic.com/steam/apps/730/capsule_sm_120.jpg',
        );
      },
    );

    test('rejects non-HTTP artwork URLs from provider payloads', () {
      final summary = const SteamPlayerSummaryParser().parse({
        'response': {
          'players': [
            {
              'steamid': '76561198000000000',
              'gameid': '730',
              'gameextrainfo': 'Counter-Strike 2',
              'game_thumbnail_url': 'javascript:alert(1)',
              'avatarfull': 'asset://repo-fixtures/avatar.png',
            },
          ],
        },
      });

      final activity = summary?.toActivity();

      expect(
        activity?.artworkUrl,
        'https://cdn.cloudflare.steamstatic.com/steam/apps/730/capsule_sm_120.jpg',
      );
    });

    test('returns no activity when summary has no active game', () {
      final summary = const SteamPlayerSummaryParser().parse({
        'response': {
          'players': [
            {
              'steamid': '76561198000000000',
              'personaname': 'Pilot',
              'communityvisibilitystate': 3,
            },
          ],
        },
      });

      expect(summary, isNotNull);
      expect(summary?.toActivity(), isNull);
    });
  });

  group('SteamApiClient', () {
    test('requests configured proxy endpoint with steam id', () async {
      final client = SteamApiClient(
        httpClient: MockClient((request) async {
          expect(request.url.host, 'activity.example.test');
          expect(request.url.path, '/steam/player-summary');
          expect(request.url.queryParameters['steamids'], 'steam-id');
          return http.Response('''
            {
              "response": {
                "players": [
                  {
                    "steamid": "steam-id",
                    "gameid": "10",
                    "gameextrainfo": "Half-Life"
                  }
                ]
              }
            }
            ''', 200);
        }),
      );

      final summary = await client.getPlayerSummary(
        endpoint: Uri.https('activity.example.test', '/steam/player-summary'),
        steamId: 'steam-id',
      );

      expect(summary?.gameExtraInfo, 'Half-Life');
    });

    test('returns null for unsuccessful responses', () async {
      final client = SteamApiClient(
        httpClient: MockClient((request) async {
          return http.Response('Forbidden', 403);
        }),
      );

      expect(
        await client.getPlayerSummary(
          endpoint: Uri.https('activity.example.test', '/steam/player-summary'),
          steamId: 'steam-id',
        ),
        isNull,
      );
    });
  });

  group('SteamActivitySource', () {
    test('does not poll when disabled or missing configuration', () async {
      var requests = 0;
      final source = SteamActivitySource(
        summaryEndpoint: () => '',
        steamId: () => 'steam-id',
        enabled: () => false,
        apiClient: SteamApiClient(
          httpClient: MockClient((request) async {
            requests++;
            return http.Response('{}', 200);
          }),
        ),
      );

      await source.start();

      expect(source.currentActivity, isNull);
      expect(requests, 0);
      await source.dispose();
    });

    test(
      'keeps polling stopped while disabled and restarts on enable',
      () async {
        var enabled = false;
        var steamId = 'steam-id';
        var requests = 0;
        final source = SteamActivitySource(
          summaryEndpoint: () => 'https://activity.example.test/steam',
          steamId: () => steamId,
          enabled: () => enabled,
          pollInterval: const Duration(minutes: 1),
          apiClient: SteamApiClient(
            httpClient: MockClient((request) async {
              requests++;
              return http.Response('''
              {
                "response": {
                  "players": [
                    {
                      "steamid": "steam-id",
                      "gameid": "220",
                      "gameextrainfo": "Half-Life 2"
                    }
                  ]
                }
              }
              ''', 200);
            }),
          ),
        );

        await source.start();

        expect(source.currentActivity, isNull);
        expect(source.debugHasActiveTimer, isFalse);
        expect(requests, 0);

        final started = source.onActivityChanged.firstWhere(
          (activity) => activity?.title == 'Half-Life 2',
        );
        enabled = true;
        source.notifySettingsChanged();
        await started;

        expect(source.currentActivity?.title, 'Half-Life 2');
        expect(source.debugHasActiveTimer, isTrue);
        expect(requests, 1);

        final stopped = source.onActivityChanged.firstWhere(
          (activity) => activity == null,
        );
        enabled = false;
        source.notifySettingsChanged();
        await stopped;

        expect(source.currentActivity, isNull);
        expect(source.debugHasActiveTimer, isFalse);
        expect(steamId, 'steam-id');
        await source.dispose();
      },
    );

    test('polls current game when configured', () async {
      final source = SteamActivitySource(
        summaryEndpoint: () => 'https://activity.example.test/steam',
        steamId: () => 'steam-id',
        enabled: () => true,
        apiClient: SteamApiClient(
          httpClient: MockClient((request) async {
            return http.Response('''
              {
                "response": {
                  "players": [
                    {
                      "steamid": "steam-id",
                      "personaname": "Pilot",
                      "gameid": "220",
                      "gameextrainfo": "Half-Life 2"
                    }
                  ]
                }
              }
              ''', 200);
          }),
        ),
      );

      await source.start();

      expect(source.currentActivity?.kind, ActivityKind.game);
      expect(source.currentActivity?.title, 'Half-Life 2');
      expect(source.currentActivity?.metadata['app_id'], '220');
      await source.dispose();
    });

    test('keeps current game through transient network failure', () async {
      var poll = 0;
      final source = SteamActivitySource(
        summaryEndpoint: () => 'https://activity.example.test/steam',
        steamId: () => 'steam-id',
        enabled: () => true,
        apiClient: SteamApiClient(
          httpClient: MockClient((request) async {
            poll++;
            if (poll == 1) {
              return http.Response('''
                {
                  "response": {
                    "players": [
                      {
                        "steamid": "steam-id",
                        "gameid": "70",
                        "gameextrainfo": "Half-Life"
                      }
                    ]
                  }
                }
                ''', 200);
            }

            throw http.ClientException('Failed host lookup');
          }),
        ),
      );

      await source.start();
      expect(source.currentActivity?.title, 'Half-Life');

      await source.refresh();

      expect(source.currentActivity?.title, 'Half-Life');
      await source.dispose();
    });

    test('renews transient hold window on matching active game', () async {
      var now = DateTime.utc(2026);
      var poll = 0;
      final source = SteamActivitySource(
        summaryEndpoint: () => 'https://activity.example.test/steam',
        steamId: () => 'steam-id',
        enabled: () => true,
        transientFailureGrace: const Duration(minutes: 3),
        clock: () => now,
        apiClient: SteamApiClient(
          httpClient: MockClient((request) async {
            poll++;
            if (poll <= 2) {
              return http.Response('''
                {
                  "response": {
                    "players": [
                      {
                        "steamid": "steam-id",
                        "gameid": "70",
                        "gameextrainfo": "Half-Life"
                      }
                    ]
                  }
                }
                ''', 200);
            }

            throw http.ClientException('Failed host lookup');
          }),
        ),
      );

      await source.start();
      expect(source.currentActivity?.title, 'Half-Life');

      now = now.add(const Duration(minutes: 4));
      await source.refresh();
      now = now.add(const Duration(minutes: 2));
      await source.refresh();

      expect(source.currentActivity?.title, 'Half-Life');
      await source.dispose();
    });

    test('clears activity when Steam reports no active game', () async {
      var poll = 0;
      final source = SteamActivitySource(
        summaryEndpoint: () => 'https://activity.example.test/steam',
        steamId: () => 'steam-id',
        enabled: () => true,
        apiClient: SteamApiClient(
          httpClient: MockClient((request) async {
            poll++;
            if (poll == 1) {
              return http.Response('''
                {
                  "response": {
                    "players": [
                      {
                        "steamid": "steam-id",
                        "gameid": "70",
                        "gameextrainfo": "Half-Life"
                      }
                    ]
                  }
                }
                ''', 200);
            }

            return http.Response('''
              {
                "response": {
                  "players": [
                    {
                      "steamid": "steam-id"
                    }
                  ]
                }
              }
              ''', 200);
          }),
        ),
      );

      await source.start();
      expect(source.currentActivity?.title, 'Half-Life');

      final events = <UserActivity?>[];
      final subscription = source.onActivityChanged.listen(events.add);
      await source.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(source.currentActivity, isNull);
      expect(events, contains(isNull));
      await subscription.cancel();
      await source.dispose();
    });
  });
}
