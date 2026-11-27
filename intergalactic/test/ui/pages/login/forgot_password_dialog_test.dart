import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intergalactic/client/account_recovery/account_recovery_api_client.dart';
import 'package:intergalactic/ui/pages/login/forgot_password_dialog.dart';

void main() {
  testWidgets('forgot password can verify with authenticator factor',
      (tester) async {
    final seenBodies = <Map<String, dynamic>>[];
    final apiClient = AccountRecoveryApiClient(
      endpoint: Uri.parse(
        'https://ourgalaxy.space/api/intergalactic/account-recovery',
      ),
      httpClient: MockClient((request) async {
        final body = request.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(request.body) as Map<String, dynamic>;
        seenBodies.add(body);

        switch (request.url.path) {
          case '/api/intergalactic/account-recovery/reset/start':
            return http.Response('{"accepted":true}', 202);
          case '/api/intergalactic/account-recovery/reset/verify':
            return http.Response(
              jsonEncode({
                'verified': true,
                'reset_session_token': 'reset-session-token',
              }),
              200,
            );
        }

        return http.Response('{"error":{"code":"not_found"}}', 404);
      }),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ForgotPasswordDialog(
            homeserverInput: 'ourgalaxy.space',
            apiClient: apiClient,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'alice');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Use recovery code'), findsOneWidget);
    expect(find.text('Use authenticator app'), findsOneWidget);

    await tester.tap(find.text('Use authenticator app'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '123456');
    await tester.tap(find.text('Verify authenticator'));
    await tester.pumpAndSettle();

    expect(find.text('New password'), findsOneWidget);
    expect(seenBodies, [
      {'username': 'alice'},
      {
        'username': 'alice',
        'factor': 'totp',
        'otp': '123456',
      },
    ]);
  });
}
