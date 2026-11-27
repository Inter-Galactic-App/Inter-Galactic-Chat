import 'dart:async';

import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/matrix/authentication/matrix_uia_request.dart';
import 'package:intergalactic/ui/pages/matrix/verification/matrix_verification_page.dart';

import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/encryption/utils/key_verification.dart';

class MatrixKeyVerificationComponent
    implements Component<MatrixClient>, NeedsPostLoginInit {
  @override
  MatrixClient client;
  bool _didRegisterListeners = false;

  MatrixKeyVerificationComponent(this.client);

  @override
  void postLoginInit() {
    if (_didRegisterListeners) {
      return;
    }
    _didRegisterListeners = true;

    Log.i("Registering key verification listeners");
    client.matrixClient.onKeyVerificationRequest.stream.listen((event) {
      final context = navigator.currentContext;
      if (context == null) {
        Log.w(
            'Skipping verification dialog because no navigator context is available.');
        return;
      }

      if (!client.matrixClient.encryptionEnabled ||
          client.matrixClient.encryption == null) {
        Log.w(
          'Ignoring a Matrix verification request because encryption is not available for the current client state.',
        );
        return;
      }

      client.setVerificationInProgress(true);
      var didCompleteVerification = false;

      void finishVerification() {
        client.setVerificationInProgress(false);

        if (event.state != KeyVerificationState.done ||
            didCompleteVerification) {
          return;
        }

        didCompleteVerification = true;
        unawaited(client.retryDecryptAllRooms());
      }

      AdaptiveDialog.show(
        context,
        builder: (_) => MatrixVerificationPage(
          request: event,
          onComplete: finishVerification,
        ),
        title: "Verification Request",
      ).then((_) {
        // Safety net: clear the guard even if onComplete was not fired
        finishVerification();
      });
    });

    client.matrixClient.onUiaRequest.stream.listen((event) {
      if (event.state == matrix.UiaRequestState.waitForUser) {
        final context = navigator.currentContext;
        if (context == null) {
          Log.w(
              'Skipping UIA dialog because no navigator context is available.');
          return;
        }

        AdaptiveDialog.show(
          context,
          builder: (_) => MatrixUIARequest(event, client),
          title: "Authentication Request",
        );
      }
    });
  }
}
