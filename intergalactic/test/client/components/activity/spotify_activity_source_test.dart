import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intergalactic/client/components/activity/activity_models.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_activity_source.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_api_client.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_auth.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_connection_service.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_playback.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_token_store.dart';

void main() {
  group('SpotifyPlaybackParser', () {
    test('parses currently playing track into activity', () {
      final snapshot = const SpotifyPlaybackParser().parseCurrentPlayback({
        'is_playing': true,
        'currently_playing_type': 'track',
        'progress_ms': 12000,
        'item': {
          'name': 'The Song',
          'duration_ms': 180000,
          'artists': [
            {'name': 'Artist One'},
            {'name': 'Artist Two'},
          ],
          'album': {
            'name': 'The Album',
            'images': [
              {'url': 'small.jpg', 'width': 64},
              {'url': 'large.jpg', 'width': 640},
            ],
          },
          'id': '123',
          'uri': 'spotify:track:123',
          'external_urls': {'spotify': 'https://open.spotify.com/track/123'},
        },
      });

      final activity = snapshot
          .copyWith(isSaved: false)
          .toActivity(
            playbackControlsEnabled: true,
            libraryControlsEnabled: true,
          );

      expect(snapshot.state, SpotifyPlaybackState.playing);
      expect(snapshot.trackId, '123');
      expect(snapshot.trackUri, 'spotify:track:123');
      expect(activity.kind, ActivityKind.music);
      expect(activity.title, 'The Song');
      expect(activity.subtitle, 'Artist One, Artist Two');
      expect(activity.details, 'The Album');
      expect(activity.artworkUrl, 'large.jpg');
      expect(activity.externalUrl, 'https://open.spotify.com/track/123');
      expect(activity.controls.map((control) => control.id), [
        'previous',
        'play_pause',
        'next',
        'save_track',
      ]);
      expect(activity.controls.last.kind, ActivityControlKind.like);
      expect(activity.controls.last.enabled, isTrue);
    });

    test('treats ad playback as unavailable private session state', () {
      final snapshot = const SpotifyPlaybackParser().parseCurrentPlayback({
        'is_playing': true,
        'currently_playing_type': 'ad',
        'item': {'name': 'Ad'},
      });

      expect(snapshot.state, SpotifyPlaybackState.privateSession);
      expect(snapshot.toActivity().title, 'Spotify unavailable');
    });

    test('distinguishes available device from missing active playback', () {
      final snapshot = const SpotifyPlaybackParser().parseCurrentPlayback({
        'is_playing': false,
        'currently_playing_type': 'track',
        'device': {
          'name': 'Desktop Spotify',
          'is_active': true,
          'is_private_session': false,
        },
        'item': null,
      });

      final activity = snapshot.toActivity();

      expect(snapshot.state, SpotifyPlaybackState.deviceAvailable);
      expect(activity.title, 'Spotify ready');
      expect(activity.details, contains('Desktop Spotify'));
    });
  });

  group('SpotifyPkceAuth', () {
    test('builds authorization request with activity and control scopes', () {
      final request = const SpotifyPkceAuth().createAuthorizationRequest(
        const SpotifyAuthConfig(
          clientId: 'client-id',
          redirectUri: 'space.ourgalaxy://spotify-auth',
        ),
      );

      expect(request.uri.host, 'accounts.spotify.com');
      expect(request.uri.path, '/authorize');
      expect(request.uri.queryParameters['response_type'], 'code');
      expect(request.uri.queryParameters['client_id'], 'client-id');
      expect(
        request.uri.queryParameters['scope'],
        contains('user-read-currently-playing'),
      );
      expect(
        request.uri.queryParameters['scope'],
        contains('user-modify-playback-state'),
      );
      expect(
        request.uri.queryParameters['scope'],
        contains('user-library-modify'),
      );
      expect(request.uri.queryParameters['code_challenge_method'], 'S256');
      expect(request.pkce.verifier, isNotEmpty);
      expect(request.pkce.challenge, isNotEmpty);
    });
  });

  group('SpotifyAccountsClient', () {
    test('exchanges authorization code for tokens', () async {
      final client = SpotifyAccountsClient(
        httpClient: MockClient((request) async {
          expect(request.url.path, '/api/token');
          expect(request.bodyFields['grant_type'], 'authorization_code');
          expect(request.bodyFields['code'], 'auth-code');
          expect(request.bodyFields['code_verifier'], 'verifier');
          return http.Response('''
            {
              "access_token": "access",
              "refresh_token": "refresh",
              "expires_in": 3600,
              "scope": "user-read-currently-playing user-read-playback-state user-modify-playback-state user-library-read user-library-modify"
            }
            ''', 200);
        }),
      );

      final tokens = await client.exchangeCode(
        config: const SpotifyAuthConfig(
          clientId: 'client-id',
          redirectUri: 'http://127.0.0.1:3001/spotify',
        ),
        code: 'auth-code',
        codeVerifier: 'verifier',
      );

      expect(tokens.accessToken, 'access');
      expect(tokens.refreshToken, 'refresh');
      expect(tokens.scopes, contains('user-read-currently-playing'));
      expect(tokens.scopes, contains('user-modify-playback-state'));
      expect(tokens.scopes, contains('user-library-modify'));
      expect(tokens.expiresAt, isNotNull);
    });

    test('refreshes tokens while preserving refresh token', () async {
      final client = SpotifyAccountsClient(
        httpClient: MockClient((request) async {
          expect(request.bodyFields['grant_type'], 'refresh_token');
          expect(request.bodyFields['refresh_token'], 'refresh');
          return http.Response('''
            {
              "access_token": "new-access",
              "expires_in": 3600
            }
            ''', 200);
        }),
      );

      final tokens = await client.refreshToken(
        config: const SpotifyAuthConfig(
          clientId: 'client-id',
          redirectUri: 'http://127.0.0.1:3001/spotify',
        ),
        refreshToken: 'refresh',
        previousScopes: SpotifyAuthScopes.activityPresenceAndControls,
      );

      expect(tokens.accessToken, 'new-access');
      expect(tokens.refreshToken, 'refresh');
      expect(tokens.scopes, SpotifyAuthScopes.activityPresenceAndControls);
    });

    test('classifies invalid grant refresh failure', () async {
      final client = SpotifyAccountsClient(
        httpClient: MockClient((request) async {
          expect(request.bodyFields['grant_type'], 'refresh_token');
          return http.Response('''
            {
              "error": "invalid_grant",
              "error_description": "Refresh token expired"
            }
            ''', 400);
        }),
      );

      await expectLater(
        client.refreshToken(
          config: const SpotifyAuthConfig(
            clientId: 'client-id',
            redirectUri: 'http://127.0.0.1:3001/spotify',
          ),
          refreshToken: 'expired-refresh',
        ),
        throwsA(
          isA<SpotifyAuthException>()
              .having((error) => error.errorCode, 'errorCode', 'invalid_grant')
              .having(
                (error) => error.isInvalidGrant,
                'isInvalidGrant',
                isTrue,
              ),
        ),
      );
    });
  });

  group('SpotifyApiClient', () {
    test('reads current user display name with id fallback', () async {
      final client = SpotifyApiClient(
        httpClient: MockClient((request) async {
          expect(request.url.path, '/v1/me');
          expect(request.headers['Authorization'], 'Bearer token');
          return http.Response('''
            {
              "id": "pilot-id",
              "display_name": "Pilot"
            }
            ''', 200);
        }),
      );

      expect(await client.getCurrentUserDisplayName('token'), 'Pilot');
    });

    test('uses account id when display name is empty', () async {
      final client = SpotifyApiClient(
        httpClient: MockClient((request) async {
          return http.Response('''
            {
              "id": "pilot-id",
              "display_name": ""
            }
            ''', 200);
        }),
      );

      expect(await client.getCurrentUserDisplayName('token'), 'pilot-id');
    });
  });

  group('SpotifyActivitySource', () {
    test('reports not connected when no token is stored', () async {
      final source = SpotifyActivitySource(
        authConfig: const SpotifyAuthConfig(
          clientId: 'client-id',
          redirectUri: 'space.ourgalaxy://spotify-auth',
        ),
        tokenStore: InMemorySpotifyTokenStore(),
        enabled: () => true,
      );

      await source.start();

      expect(source.currentActivity?.title, 'Spotify not connected');
      await source.dispose();
    });

    test('polls playback when token is available', () async {
      final tokenStore = InMemorySpotifyTokenStore();
      await tokenStore.write(
        SpotifyTokenSet(
          accessToken: 'token',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          scopes: SpotifyAuthScopes.activityPresenceAndControls,
        ),
      );
      final requests = <String>[];
      final source = SpotifyActivitySource(
        authConfig: const SpotifyAuthConfig(
          clientId: 'client-id',
          redirectUri: 'space.ourgalaxy://spotify-auth',
        ),
        tokenStore: tokenStore,
        enabled: () => true,
        apiClient: SpotifyApiClient(
          httpClient: MockClient((request) async {
            expect(request.headers['Authorization'], 'Bearer token');
            requests.add('${request.method} ${request.url.path}');
            if (request.url.path == '/v1/me/library/contains') {
              expect(request.url.queryParameters['uris'], 'spotify:track:p');
              return http.Response('[false]', 200);
            }

            return http.Response('''
              {
                "is_playing": false,
                "currently_playing_type": "track",
                "progress_ms": 24000,
                "item": {
                  "name": "Paused Song",
                  "duration_ms": 200000,
                  "artists": [{"name": "Paused Artist"}],
                  "album": {"name": "Paused Album", "images": []},
                  "id": "p",
                  "uri": "spotify:track:p",
                  "external_urls": {"spotify": "https://open.spotify.com/track/p"}
                }
              }
              ''', 200);
          }),
        ),
      );

      await source.start();

      expect(source.currentActivity?.title, 'Paused Song');
      expect(source.currentActivity?.status, 'Paused');
      expect(source.currentActivity?.controls.last.id, 'save_track');
      expect(source.currentActivity?.controls.last.enabled, isTrue);
      expect(requests, ['GET /v1/me/player', 'GET /v1/me/library/contains']);
      await source.dispose();
    });

    test('keeps current playback through transient polling failure', () async {
      final tokenStore = InMemorySpotifyTokenStore();
      await tokenStore.write(
        SpotifyTokenSet(
          accessToken: 'token',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          scopes: SpotifyAuthScopes.activityPresenceAndControls,
        ),
      );
      var pollCount = 0;
      final source = SpotifyActivitySource(
        authConfig: const SpotifyAuthConfig(
          clientId: 'client-id',
          redirectUri: 'space.ourgalaxy://spotify-auth',
        ),
        tokenStore: tokenStore,
        enabled: () => true,
        apiClient: SpotifyApiClient(
          httpClient: MockClient((request) async {
            if (request.url.path == '/v1/me/library/contains') {
              return http.Response('[false]', 200);
            }

            pollCount++;
            if (pollCount == 1) {
              return http.Response(_playbackBody(isPlaying: true), 200);
            }

            throw http.ClientException('Failed host lookup');
          }),
        ),
      );

      await source.start();
      expect(source.currentActivity?.title, 'Paused Song');

      await source.refresh();

      expect(source.currentActivity?.title, 'Paused Song');
      expect(source.currentActivity?.metadata['state'], 'playing');
      await source.dispose();
    });

    test('renews transient hold window on matching playback', () async {
      final tokenStore = InMemorySpotifyTokenStore();
      await tokenStore.write(
        SpotifyTokenSet(
          accessToken: 'token',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          scopes: SpotifyAuthScopes.activityPresenceAndControls,
        ),
      );
      var now = DateTime.utc(2026);
      var pollCount = 0;
      final source = SpotifyActivitySource(
        authConfig: const SpotifyAuthConfig(
          clientId: 'client-id',
          redirectUri: 'space.ourgalaxy://spotify-auth',
        ),
        tokenStore: tokenStore,
        enabled: () => true,
        transientFailureGrace: const Duration(minutes: 3),
        clock: () => now,
        apiClient: SpotifyApiClient(
          httpClient: MockClient((request) async {
            if (request.url.path == '/v1/me/library/contains') {
              return http.Response('[false]', 200);
            }

            pollCount++;
            if (pollCount <= 2) {
              return http.Response(_playbackBody(isPlaying: true), 200);
            }

            throw http.ClientException('Failed host lookup');
          }),
        ),
      );

      await source.start();
      expect(source.currentActivity?.title, 'Paused Song');

      now = now.add(const Duration(minutes: 4));
      await source.refresh();
      now = now.add(const Duration(minutes: 2));
      await source.refresh();

      expect(source.currentActivity?.title, 'Paused Song');
      expect(source.currentActivity?.metadata['state'], 'playing');
      await source.dispose();
    });

    test(
      'falls back to available devices when playback state is empty',
      () async {
        final tokenStore = InMemorySpotifyTokenStore();
        await tokenStore.write(
          SpotifyTokenSet(
            accessToken: 'token',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
            scopes: SpotifyAuthScopes.activityPresenceAndControls,
          ),
        );
        final requests = <String>[];
        final source = SpotifyActivitySource(
          authConfig: const SpotifyAuthConfig(
            clientId: 'client-id',
            redirectUri: 'space.ourgalaxy://spotify-auth',
          ),
          tokenStore: tokenStore,
          enabled: () => true,
          apiClient: SpotifyApiClient(
            httpClient: MockClient((request) async {
              requests.add('${request.method} ${request.url.path}');
              expect(request.headers['Authorization'], 'Bearer token');
              if (request.url.path == '/v1/me/player') {
                return http.Response('', 204);
              }

              if (request.url.path == '/v1/me/player/devices') {
                return http.Response('''
                {
                  "devices": [
                    {
                      "id": "desktop",
                      "name": "Desktop Spotify",
                      "type": "computer",
                      "is_active": false,
                      "is_private_session": false,
                      "is_restricted": false
                    }
                  ]
                }
                ''', 200);
              }

              fail(
                'Unexpected Spotify request: ${request.method} ${request.url}',
              );
            }),
          ),
        );

        await source.start();

        expect(source.currentActivity?.title, 'Spotify ready');
        expect(source.currentActivity?.details, contains('Desktop Spotify'));
        expect(requests, ['GET /v1/me/player', 'GET /v1/me/player/devices']);
        await source.dispose();
      },
    );

    test('sends playback controls through the Spotify player API', () async {
      final tokenStore = InMemorySpotifyTokenStore();
      await tokenStore.write(
        SpotifyTokenSet(
          accessToken: 'token',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          scopes: SpotifyAuthScopes.activityPresenceAndControls,
        ),
      );
      var playbackPolls = 0;
      final requests = <String>[];
      final source = SpotifyActivitySource(
        authConfig: const SpotifyAuthConfig(
          clientId: 'client-id',
          redirectUri: 'space.ourgalaxy://spotify-auth',
        ),
        tokenStore: tokenStore,
        enabled: () => true,
        apiClient: SpotifyApiClient(
          httpClient: MockClient((request) async {
            requests.add('${request.method} ${request.url.path}');
            expect(request.headers['Authorization'], 'Bearer token');
            if (request.url.path == '/v1/me/library/contains') {
              return http.Response('[false]', 200);
            }

            if (request.method == 'PUT' &&
                request.url.path == '/v1/me/player/pause') {
              return http.Response('', 204);
            }

            if (request.url.path == '/v1/me/player') {
              playbackPolls++;
              return http.Response(
                _playbackBody(isPlaying: playbackPolls == 1),
                200,
              );
            }

            fail(
              'Unexpected Spotify request: ${request.method} ${request.url}',
            );
          }),
        ),
      );

      await source.start();
      await source.executeControl('play_pause');

      expect(requests, contains('PUT /v1/me/player/pause'));
      expect(source.currentActivity?.status, 'Paused');
      await source.dispose();
    });

    test(
      'saves and unsaves the current Spotify track from activity controls',
      () async {
        final tokenStore = InMemorySpotifyTokenStore();
        await tokenStore.write(
          SpotifyTokenSet(
            accessToken: 'token',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
            scopes: SpotifyAuthScopes.activityPresenceAndControls,
          ),
        );
        var saved = false;
        final requests = <String>[];
        final source = SpotifyActivitySource(
          authConfig: const SpotifyAuthConfig(
            clientId: 'client-id',
            redirectUri: 'space.ourgalaxy://spotify-auth',
          ),
          tokenStore: tokenStore,
          enabled: () => true,
          apiClient: SpotifyApiClient(
            httpClient: MockClient((request) async {
              requests.add('${request.method} ${request.url.path}');
              expect(request.headers['Authorization'], 'Bearer token');
              if (request.url.path == '/v1/me/player') {
                return http.Response(_playbackBody(isPlaying: false), 200);
              }

              if (request.url.path == '/v1/me/library/contains') {
                expect(request.url.queryParameters['uris'], 'spotify:track:p');
                return http.Response('[$saved]', 200);
              }

              if (request.method == 'PUT' &&
                  request.url.path == '/v1/me/library') {
                expect(request.url.queryParameters['uris'], 'spotify:track:p');
                saved = true;
                return http.Response('', 200);
              }

              if (request.method == 'DELETE' &&
                  request.url.path == '/v1/me/library') {
                expect(request.url.queryParameters['uris'], 'spotify:track:p');
                saved = false;
                return http.Response('', 200);
              }

              fail(
                'Unexpected Spotify request: ${request.method} ${request.url}',
              );
            }),
          ),
        );

        await source.start();
        expect(source.currentActivity?.controls.last.id, 'save_track');

        await source.executeControl('save_track');
        expect(source.currentActivity?.controls.last.id, 'remove_saved_track');

        await source.executeControl('remove_saved_track');
        expect(source.currentActivity?.controls.last.id, 'save_track');
        expect(requests, contains('PUT /v1/me/library'));
        expect(requests, contains('DELETE /v1/me/library'));
        await source.dispose();
      },
    );

    test('refreshes expired token before polling playback', () async {
      final tokenStore = InMemorySpotifyTokenStore();
      await tokenStore.write(
        SpotifyTokenSet(
          accessToken: 'old-token',
          refreshToken: 'refresh',
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      );
      final source = SpotifyActivitySource(
        authConfig: const SpotifyAuthConfig(
          clientId: 'client-id',
          redirectUri: 'space.ourgalaxy://spotify-auth',
        ),
        tokenStore: tokenStore,
        enabled: () => true,
        accountsClient: SpotifyAccountsClient(
          httpClient: MockClient((request) async {
            return http.Response('''
              {
                "access_token": "new-token",
                "expires_in": 3600
              }
              ''', 200);
          }),
        ),
        apiClient: SpotifyApiClient(
          httpClient: MockClient((request) async {
            expect(request.headers['Authorization'], 'Bearer new-token');
            return http.Response('''
              {
                "is_playing": true,
                "currently_playing_type": "track",
                "item": {
                  "name": "Fresh Song",
                  "artists": [{"name": "Fresh Artist"}],
                  "album": {"name": "Fresh Album", "images": []}
                }
              }
              ''', 200);
          }),
        ),
      );

      await source.start();

      expect(source.currentActivity?.title, 'Fresh Song');
      expect((await tokenStore.read())?.accessToken, 'new-token');
      await source.dispose();
    });

    test('clears stored token when refresh returns invalid grant', () async {
      final tokenStore = InMemorySpotifyTokenStore();
      await tokenStore.write(
        SpotifyTokenSet(
          accessToken: 'old-token',
          refreshToken: 'expired-refresh',
          expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
        ),
      );
      var refreshAttempts = 0;
      final source = SpotifyActivitySource(
        authConfig: const SpotifyAuthConfig(
          clientId: 'client-id',
          redirectUri: 'space.ourgalaxy://spotify-auth',
        ),
        tokenStore: tokenStore,
        enabled: () => true,
        accountsClient: SpotifyAccountsClient(
          httpClient: MockClient((request) async {
            refreshAttempts++;
            return http.Response('''
              {
                "error": "invalid_grant",
                "error_description": "Refresh token expired"
              }
              ''', 400);
          }),
        ),
        apiClient: SpotifyApiClient(
          httpClient: MockClient((request) async {
            fail('Playback polling should not run after invalid_grant');
          }),
        ),
      );

      await source.start();

      expect(refreshAttempts, 1);
      expect(await tokenStore.read(), isNull);
      expect(source.currentActivity?.title, 'Spotify not connected');
      expect(
        source.currentActivity?.details,
        'Spotify authorization expired. Connect Spotify again.',
      );

      await source.refresh();

      expect(refreshAttempts, 1);
      await source.dispose();
    });

    test('does not expose activity when source is disabled', () async {
      final source = SpotifyActivitySource(
        authConfig: const SpotifyAuthConfig(
          clientId: 'client-id',
          redirectUri: 'space.ourgalaxy://spotify-auth',
        ),
        tokenStore: InMemorySpotifyTokenStore(),
        enabled: () => false,
      );

      await source.start();

      expect(source.currentActivity, isNull);
      await source.dispose();
    });

    test(
      'keeps polling stopped while disabled and restarts on enable',
      () async {
        var enabled = false;
        var playbackRequests = 0;
        final tokenStore = InMemorySpotifyTokenStore();
        await tokenStore.write(
          SpotifyTokenSet(
            accessToken: 'token',
            refreshToken: 'refresh-token',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );
        final source = SpotifyActivitySource(
          authConfig: const SpotifyAuthConfig(
            clientId: 'client-id',
            redirectUri: 'space.ourgalaxy://spotify-auth',
          ),
          tokenStore: tokenStore,
          enabled: () => enabled,
          pollInterval: const Duration(minutes: 1),
          apiClient: SpotifyApiClient(
            httpClient: MockClient((request) async {
              playbackRequests++;
              return http.Response(_playbackBody(isPlaying: true), 200);
            }),
          ),
        );

        await source.start();

        expect(source.currentActivity, isNull);
        expect(source.debugHasActiveTimer, isFalse);
        expect(playbackRequests, 0);
        expect((await tokenStore.read())?.refreshToken, 'refresh-token');

        final started = source.onActivityChanged.firstWhere(
          (activity) => activity?.title == 'Paused Song',
        );
        enabled = true;
        source.notifySettingsChanged();
        await started;

        expect(source.currentActivity?.title, 'Paused Song');
        expect(source.debugHasActiveTimer, isTrue);
        expect(playbackRequests, 1);

        final stopped = source.onActivityChanged.firstWhere(
          (activity) => activity == null,
        );
        enabled = false;
        source.notifySettingsChanged();
        await stopped;

        expect(source.currentActivity, isNull);
        expect(source.debugHasActiveTimer, isFalse);
        expect((await tokenStore.read())?.refreshToken, 'refresh-token');
        await source.dispose();
      },
    );
  });

  group('SpotifyConnectionService', () {
    test(
      'reports reconnect required when startup refresh cannot renew token',
      () async {
        final tokenStore = InMemorySpotifyTokenStore();
        await tokenStore.write(
          SpotifyTokenSet(
            accessToken: 'expired-access',
            refreshToken: 'expired-refresh',
            expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
          ),
        );
        final service = SpotifyConnectionService(
          authConfig: const SpotifyAuthConfig(
            clientId: 'client-id',
            redirectUri: 'space.ourgalaxy://spotify-auth',
          ),
          tokenStore: tokenStore,
          accountsClient: SpotifyAccountsClient(
            httpClient: MockClient((request) async {
              return http.Response(
                '{"error":"invalid_grant","error_description":"expired"}',
                400,
              );
            }),
          ),
        );

        final status = await service.refreshStatus();
        final repeatedStatus = await service.refreshStatus();

        expect(status.state, SpotifyConnectionState.reconnectRequired);
        expect(repeatedStatus.state, SpotifyConnectionState.reconnectRequired);
        expect(status.message, contains('Reconnect Spotify'));
        expect(await tokenStore.read(), isNull);
        await service.dispose();
      },
    );

    test(
      'clears the token store when the playback check answers unauthorized',
      () async {
        final tokenStore = InMemorySpotifyTokenStore();
        await tokenStore.write(
          SpotifyTokenSet(
            accessToken: 'valid-access',
            refreshToken: 'valid-refresh',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );
        final service = SpotifyConnectionService(
          authConfig: const SpotifyAuthConfig(
            clientId: 'client-id',
            redirectUri: 'space.ourgalaxy://spotify-auth',
          ),
          tokenStore: tokenStore,
          apiClient: SpotifyApiClient(
            httpClient: MockClient((request) async => http.Response('', 401)),
          ),
        );

        final status = await service.refreshStatus();

        // The tokens are unexpired, so nothing before the playback call would
        // have caught this: only the 401 answer does.
        expect(status.state, SpotifyConnectionState.reconnectRequired);
        expect(await tokenStore.read(), isNull);
        await service.dispose();
      },
    );

    test('reports failed, and keeps the tokens, when the playback check cannot '
        'complete', () async {
      final tokenStore = InMemorySpotifyTokenStore();
      await tokenStore.write(
        SpotifyTokenSet(
          accessToken: 'valid-access',
          refreshToken: 'valid-refresh',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        ),
      );
      final service = SpotifyConnectionService(
        authConfig: const SpotifyAuthConfig(
          clientId: 'client-id',
          redirectUri: 'space.ourgalaxy://spotify-auth',
        ),
        tokenStore: tokenStore,
        apiClient: SpotifyApiClient(
          httpClient: MockClient((request) async {
            throw http.ClientException('connection closed');
          }),
        ),
      );

      // A transport failure used to reach the end of refreshStatus unchanged
      // and be announced as `connected` - the connection reported active on
      // the strength of a request that never landed.
      final status = await service.refreshStatus();

      expect(status.state, SpotifyConnectionState.failed);
      expect(status.message, contains('could not be checked'));
      expect((await tokenStore.read())?.refreshToken, 'valid-refresh');
      await service.dispose();
    });

    test(
      'reports failed, not reconnect-required, when clearing tokens throws',
      () async {
        // refreshStatus is driven from an unawaited call in main.dart, so a
        // clear that threw became an unhandled asynchronous error at startup
        // and left the status stale. And `reconnectRequired` is only honest
        // once the credentials are actually gone.
        final tokenStore = _ThrowingClearTokenStore();
        await tokenStore.write(
          SpotifyTokenSet(
            accessToken: 'valid-access',
            refreshToken: 'valid-refresh',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        );
        final service = SpotifyConnectionService(
          authConfig: const SpotifyAuthConfig(
            clientId: 'client-id',
            redirectUri: 'space.ourgalaxy://spotify-auth',
          ),
          tokenStore: tokenStore,
          apiClient: SpotifyApiClient(
            httpClient: MockClient((request) async => http.Response('', 401)),
          ),
        );

        final status = await service.refreshStatus();

        expect(status.state, SpotifyConnectionState.failed);
        await service.dispose();
      },
    );

    test('reports not configured without client id and redirect uri', () async {
      final service = SpotifyConnectionService(
        authConfig: const SpotifyAuthConfig(clientId: '', redirectUri: ''),
        tokenStore: InMemorySpotifyTokenStore(),
      );

      final status = await service.connect();

      expect(status.state, SpotifyConnectionState.notConfigured);
    });
  });
}

String _playbackBody({required bool isPlaying}) {
  return '''
  {
    "is_playing": $isPlaying,
    "currently_playing_type": "track",
    "progress_ms": 24000,
    "item": {
      "name": "Paused Song",
      "duration_ms": 200000,
      "artists": [{"name": "Paused Artist"}],
      "album": {"name": "Paused Album", "images": []},
      "id": "p",
      "uri": "spotify:track:p",
      "external_urls": {"spotify": "https://open.spotify.com/track/p"}
    }
  }
  ''';
}

class _ThrowingClearTokenStore extends InMemorySpotifyTokenStore {
  @override
  Future<void> clear() async => throw StateError('secure storage unavailable');
}
