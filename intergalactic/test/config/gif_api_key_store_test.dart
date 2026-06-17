import 'package:intergalactic/config/gif_api_key_store.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test/test.dart';

void main() {
  late Preferences testPreferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    testPreferences = Preferences();
    await testPreferences.init();
  });

  test('normalizes and stores a local GIF API key', () async {
    expect(GifApiKeyStore.hasApiKey, isFalse);

    await GifApiKeyStore.setApiKey('  local-key  ');

    expect(GifApiKeyStore.apiKey, 'local-key');
    expect(GifApiKeyStore.hasApiKey, isTrue);
    expect(GifApiKeyStore.statusLabel, 'Saved key ending in -key');
  });

  test('blank or cleared GIF API key disables key availability', () async {
    await GifApiKeyStore.setApiKey('local-key');
    await GifApiKeyStore.setApiKey('   ');

    expect(GifApiKeyStore.apiKey, isNull);
    expect(GifApiKeyStore.hasApiKey, isFalse);

    await GifApiKeyStore.setApiKey('local-key');
    await GifApiKeyStore.clearApiKey();

    expect(GifApiKeyStore.apiKey, isNull);
    expect(GifApiKeyStore.statusLabel, 'No API key saved');
  });

  test('normalizes and stores a local GIF relay URL', () async {
    expect(GifApiKeyStore.hasSearchProvider, isFalse);

    await GifApiKeyStore.setRelayBaseUrl('  https://example.com/api/gif///  ');

    expect(GifApiKeyStore.savedRelayBaseUrl, 'https://example.com/api/gif');
    expect(GifApiKeyStore.relayBaseUrl, 'https://example.com/api/gif');
    expect(GifApiKeyStore.hasRelayBaseUrl, isTrue);
    expect(GifApiKeyStore.hasSearchProvider, isTrue);
    expect(
      GifApiKeyStore.providerStatusLabel,
      'Using saved relay https://example.com/api/gif',
    );

    await GifApiKeyStore.clearRelayBaseUrl();

    expect(GifApiKeyStore.savedRelayBaseUrl, isNull);
    expect(GifApiKeyStore.hasSearchProvider, isFalse);
  });

  test('uses preserved previous-build GIF relay when build relay is missing',
      () async {
    await testPreferences.gifSearchLastBuildRelayBaseUrl
        .set('  https://previous.example/api/gif///  ');

    expect(GifApiKeyStore.savedRelayBaseUrl, isNull);
    expect(
      GifApiKeyStore.preservedRelayBaseUrl,
      'https://previous.example/api/gif',
    );
    expect(GifApiKeyStore.relayBaseUrl, 'https://previous.example/api/gif');
    expect(GifApiKeyStore.hasPreservedRelayBaseUrl, isTrue);
    expect(GifApiKeyStore.hasSearchProvider, isTrue);
    expect(
      GifApiKeyStore.providerStatusLabel,
      'Using relay preserved from previous build',
    );

    await GifApiKeyStore.clearRelayBaseUrl();

    expect(GifApiKeyStore.preservedRelayBaseUrl, isNull);
    expect(GifApiKeyStore.hasSearchProvider, isFalse);
  });

  test('rejects invalid GIF relay URLs', () async {
    expect(
      GifApiKeyStore.setRelayBaseUrl('ftp://example.com/api/gif'),
      throwsFormatException,
    );
    expect(GifApiKeyStore.normalizeRelayBaseUrl('not a url'), isNull);
  });
}
