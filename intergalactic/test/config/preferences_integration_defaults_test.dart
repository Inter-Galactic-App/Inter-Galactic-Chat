import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/integration_defaults.dart';
import 'package:test/test.dart';

void main() {
  test('GIF relay uses managed build default for fresh installs', () {
    expect(resolveGifRelayBaseUrl(), BuildConfig.defaultGifApiBaseUrl);
  });

  test('GIF relay falls back to previous build default after update', () {
    expect(
      resolveGifRelayBaseUrl(
        bundled: '',
        preserved: '  https://previous.example/api/gif///  ',
      ),
      'https://previous.example/api/gif',
    );

    expect(
      resolveGifRelayBaseUrl(
        saved: 'https://user.example/gif',
        bundled: 'https://build.example/gif',
        preserved: 'https://previous.example/gif',
      ),
      'https://user.example/gif',
    );
  });

  test('Spotify auth falls back to previous build defaults after update', () {
    final config = resolveSpotifyAuthConfig(
      bundledClientId: '',
      bundledRedirectUri: '',
      preservedClientId: '  previous-client-id  ',
      preservedRedirectUri: '  intergalactic-spotify://previous-callback  ',
    );

    expect(config.clientId, 'previous-client-id');
    expect(config.redirectUri, 'intergalactic-spotify://previous-callback');
    expect(config.isConfigured, isTrue);
  });

  test('saved Spotify developer settings override preserved build defaults',
      () {
    final config = resolveSpotifyAuthConfig(
      storedClientId: '  user-client-id  ',
      storedRedirectUri: '  intergalactic-spotify://user-callback  ',
      bundledClientId: '',
      bundledRedirectUri: '',
      preservedClientId: 'previous-client-id',
      preservedRedirectUri: 'intergalactic-spotify://previous-callback',
    );

    expect(config.clientId, 'user-client-id');
    expect(config.redirectUri, 'intergalactic-spotify://user-callback');
  });

  test('Steam activity proxy falls back to previous build default after update',
      () {
    expect(
      resolveSteamActivityApiBaseUrl(
        bundled: '',
        preserved: '  https://activity.previous.example/steam  ',
      ),
      'https://activity.previous.example/steam',
    );
  });
}
