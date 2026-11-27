import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/pages/login/login_page_view.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('shows the account-creation guidance text', (tester) async {
    await tester.pumpWidget(
      host(
        AccountCreationNoticeCard(
          message: LoginPageView.defaultMobileAccountCreationNotice,
        ),
      ),
    );

    // The whole message renders, and it names both routes users can take.
    expect(
      find.text(LoginPageView.defaultMobileAccountCreationNotice),
      findsOneWidget,
    );
    expect(
      LoginPageView.defaultMobileAccountCreationNotice,
      contains('chat.ourgalaxy.space'),
    );
    expect(
      LoginPageView.defaultMobileAccountCreationNotice.toLowerCase(),
      contains('desktop'),
    );
  });

  testWidgets(
    'renders as selectable text with no tappable link (mobile browser gate)',
    (tester) async {
      await tester.pumpWidget(
        host(
          AccountCreationNoticeCard(
            message: LoginPageView.defaultMobileAccountCreationNotice,
          ),
        ),
      );

      // Selectable so the address can be copied by hand...
      expect(find.byType(SelectableText), findsOneWidget);

      // ...but nothing that presents itself as a tappable link/button that
      // could launch the browser to register.
      expect(find.byType(InkWell), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    },
  );
}
