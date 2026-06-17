import 'dart:async';

import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/security/matrix/session/matrix_session_view.dart';
import 'package:flutter/widgets.dart';

import 'package:matrix/encryption/utils/key_verification.dart';
import 'package:matrix/matrix.dart';

import '../../../../../../matrix/verification/matrix_verification_page.dart';

class MatrixSession extends StatefulWidget {
  const MatrixSession(this.device, this.matrixClient,
      {super.key, this.appClient, this.onUpdated});
  final Device device;
  final Client matrixClient;
  final MatrixClient? appClient;
  final Function? onUpdated;

  @override
  State<MatrixSession> createState() => _MatrixSessionState();
}

class _MatrixSessionState extends State<MatrixSession> {
  Function()? previousOnUpdate;

  @override
  Widget build(BuildContext context) {
    return MatrixSessionView(
      deviceId: widget.device.deviceId,
      displayName: widget.device.displayName,
      lastSeenIp: widget.device.lastSeenIp,
      lastSeenTimestamp: widget.device.lastSeenTs,
      verified: isVerified(),
      isThisDevice: isCurrentDevice(),
      beginVerification: beginVerification,
      removeSession: removeSession,
    );
  }

  bool isVerified() {
    var keys = widget.matrixClient.userDeviceKeys[widget.matrixClient.userID]
        ?.deviceKeys[widget.device.deviceId];
    return keys?.verified ?? false;
  }

  bool isCurrentDevice() {
    return widget.device.deviceId == widget.matrixClient.deviceID;
  }

  void beginVerification() async {
    if (!widget.matrixClient.encryptionEnabled ||
        widget.matrixClient.encryption == null) {
      if (!mounted) {
        return;
      }

      AdaptiveDialog.show(
        context,
        title: 'Encryption unavailable',
        builder: (_) => const Text(
          'End to end encryption is not available for this session yet. Wait for the client to finish syncing, then try verification again. If this keeps happening, sign out and sign back in again.',
        ),
      );
      return;
    }

    final keys = widget.matrixClient.userDeviceKeys[widget.matrixClient.userID]
        ?.deviceKeys[widget.device.deviceId];
    if (keys == null) {
      if (!mounted) {
        return;
      }

      AdaptiveDialog.show(
        context,
        title: 'Verification unavailable',
        builder: (_) => const Text(
          'This device key is not available yet. Wait for the session list to finish loading, then try again.',
        ),
      );
      return;
    }

    try {
      final request = await keys.startVerification();
      var didCompleteVerification = false;
      void finishVerification() {
        if (request.state != KeyVerificationState.done ||
            didCompleteVerification) {
          return;
        }

        didCompleteVerification = true;
        final client = widget.appClient;
        if (client != null) {
          unawaited(client.retryDecryptAllRooms());
        }
      }

      previousOnUpdate = request.onUpdate;
      request.onUpdate = onRequestUpdate;

      if (mounted) {
        AdaptiveDialog.show(
          context,
          builder: (_) => MatrixVerificationPage(
            request: request,
            onComplete: finishVerification,
          ),
          title: "Verification Request",
        ).then((_) => finishVerification());
      }
    } catch (error, trace) {
      if (!mounted) {
        return;
      }

      AdaptiveDialog.showError(context, error, trace);
    }
  }

  void onRequestUpdate() {
    previousOnUpdate?.call();
    setState(() {});
  }

  void removeSession() async {
    await widget.matrixClient.uiaRequestBackground((auth) async {
      await widget.matrixClient
          .deleteDevice(widget.device.deviceId, auth: auth);
      widget.onUpdated?.call();
    });
  }
}
