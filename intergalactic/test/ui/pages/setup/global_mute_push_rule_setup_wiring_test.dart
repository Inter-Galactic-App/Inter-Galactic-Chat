import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/ui/pages/setup/menus/global_mute_push_rule_setup.dart';
import 'package:intergalactic/ui/pages/setup/setup_menu.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

/// Guards the WIRING and the rendered copy, not the orchestration.
///
/// `global_mute_push_rule_preferences_test.dart` drives the menu through
/// `forTesting`, which injects `setMuted` as a closure. That proves the
/// write-then-mark ordering but says nothing about what the production
/// constructor binds: replacing the `setMuteAllPushNotifications` tear-off with
/// a no-op keeps every one of those cases green while the master rule is never
/// written and every account is marked migrated on the strength of nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Preferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = Preferences();
    await preferences.init();
  });

  // The request `setMuteAllPushNotifications` makes. Naming it is the whole
  // point: an earlier version of this test inferred the binding from
  // `choose()` reaching its failure path, which ANY throwing call satisfies -
  // including a stray `_FakeMatrixDatabase` member, since every one of those
  // throws. A binding to the wrong SDK call passed that test.
  const masterRulePath =
      '/_matrix/client/v3/pushrules/global/override/.m.rule.master/enabled';

  /// A [MatrixClient] whose SDK client still builds its own requests but sends
  /// them to [transport] instead of a socket.
  ///
  /// A homeserver and a token are required for the SDK to get as far as
  /// sending: without them `setPushRuleEnabled` throws on `baseUri!` before it
  /// reaches the http client, which is also why the old construction never
  /// touched the network. Neither does this one - [transport] answers every
  /// request itself.
  MatrixClient wiredClient(_RecordingTransport transport) {
    final client = MatrixClient(
      identifier: 'wiring-account',
      database: _FakeMatrixDatabase(),
    );
    client.getMatrixClient()
      ..httpClient = transport
      ..homeserver = Uri.parse('https://homeserver.invalid')
      ..accessToken = 'wiring-token';
    return client;
  }

  test('the production constructor binds the master push rule', () async {
    final transport = _RecordingTransport();
    final setup = GlobalMutePushRuleSetup(
      wiredClient(transport),
      preferences: preferences,
    );

    await setup.choose(true);

    expect(
      transport.paths,
      [masterRulePath],
      reason:
          'setMuted must be bound to setMuteAllPushNotifications - the master '
          'rule is the only write that mutes the whole account, so any other '
          'request here means the menu is wired to something else',
    );
    expect(transport.requests.single.method, 'PUT');
    expect(
      transport.bodies.single,
      '{"enabled":true}',
      reason: 'choose(true) must ask the server to ENABLE the master rule',
    );

    // The server write is what the migration flag stands for. An account
    // marked migrated on the strength of a write that never landed is
    // silently unmuted on every other device.
    expect(setup.state, SetupMenuState.canProgress);
    expect(setup.errorMessage, isNull);
    expect(preferences.isGlobalMutePushRuleMigrated('wiring-account'), isTrue);
  });

  test('a refused master-rule write leaves the account unmigrated', () async {
    final transport = _RecordingTransport(statusCode: 502);
    final setup = GlobalMutePushRuleSetup(
      wiredClient(transport),
      preferences: preferences,
    );

    await setup.choose(true);

    // Asserting the path here too keeps the failure attributable: without it
    // this case would again pass for a binding to any other failing call.
    expect(transport.paths, [masterRulePath]);
    expect(
      setup.state,
      SetupMenuState.cannotProgress,
      reason:
          'choose() reported success while the server refused the write, so '
          'the master rule was never set',
    );
    expect(setup.errorMessage, isNotNull);
    expect(preferences.isGlobalMutePushRuleMigrated('wiring-account'), isFalse);
  });

  test('submit refuses to advance until a choice is applied', () async {
    final setup = GlobalMutePushRuleSetup.forTesting(
      clientIdentifier: 'account-a',
      setMuted: (_) async {},
      preferences: preferences,
    );

    await expectLater(setup.submit(), throwsStateError);

    await setup.choose(false);

    await expectLater(setup.submit(), completes);
  });

  // The account label is the only part of this screen that identifies WHICH
  // account the choice applies to, and it reached the widget through a bare
  // `$menu.accountLabel`, which interpolates the menu object and appends the
  // field name as literal text.
  testWidgets('the prompt names the account rather than the menu object', (
    tester,
  ) async {
    final setup = GlobalMutePushRuleSetup.forTesting(
      clientIdentifier: '@alice:example.org',
      setMuted: (_) async {},
      preferences: preferences,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(
          useMaterial3: true,
        ).copyWith(extensions: [const ThemeSettings()]),
        home: Scaffold(
          body: Builder(builder: (context) => setup.builder(context)),
        ),
      ),
    );

    expect(
      find.textContaining('This sets @alice:example.org\'s notification rule'),
      findsOneWidget,
    );
    expect(find.textContaining('.accountLabel'), findsNothing);
    expect(find.textContaining("Instance of '"), findsNothing);
  });

  testWidgets(
    'a successful choice shows Selected and keeps the other choice available',
    (tester) async {
      final setup = GlobalMutePushRuleSetup.forTesting(
        clientIdentifier: '@alice:example.org',
        setMuted: (_) async {},
        preferences: preferences,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.light(
            useMaterial3: true,
          ).copyWith(extensions: [const ThemeSettings()]),
          home: Scaffold(
            body: Builder(builder: (context) => setup.builder(context)),
          ),
        ),
      );

      await setup.choose(false);
      await tester.pump();

      expect(find.text('Selected'), findsOneWidget);
      expect(find.text('Keep on'), findsNothing);
      expect(find.text('Mute account'), findsOneWidget);
      expect(
        find.textContaining('whole account. It applies everywhere'),
        findsOneWidget,
      );
    },
  );
}

class _FakeMatrixDatabase implements matrix.DatabaseApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records what the SDK put on the wire, and answers it without a socket.
///
/// Replacing only the transport keeps the SDK's own request construction - the
/// method, the path and the body are the real ones, which is what makes the
/// assertions above specific to `setMuteAllPushNotifications`.
class _RecordingTransport extends http.BaseClient {
  _RecordingTransport({this.statusCode = 200});

  final int statusCode;
  final List<http.BaseRequest> requests = [];
  final List<String> bodies = [];

  List<String> get paths =>
      requests.map((request) => request.url.path).toList();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    bodies.add(request is http.Request ? request.body : '');
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('{}')),
      statusCode,
      request: request,
    );
  }
}
