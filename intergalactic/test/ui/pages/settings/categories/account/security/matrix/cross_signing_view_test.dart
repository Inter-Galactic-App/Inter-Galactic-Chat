import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/security/matrix/cross_signing/cross_signing_view.dart';
import 'package:matrix/encryption.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

void main() {
  testWidgets('cross-signing controllers are quiet during disposal',
      (tester) async {
    await tester.pumpWidget(
      const _Host(
        child: MatrixCrossSigningView(BootstrapState.loading),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      const _Host(
        child: SizedBox.shrink(),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

class _Host extends StatelessWidget {
  const _Host({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.light(useMaterial3: true).copyWith(
        extensions: [
          const ThemeSettings(),
        ],
      ),
      home: Scaffold(
        body: Center(
          child: child,
        ),
      ),
    );
  }
}
