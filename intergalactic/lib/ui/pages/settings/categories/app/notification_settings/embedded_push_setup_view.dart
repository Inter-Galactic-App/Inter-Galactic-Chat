import 'package:intergalactic/client/components/push_notification/android/embedded_ntfy_notifier.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/main.dart';
import 'package:flutter/material.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class EmbeddedPushSetupView extends StatefulWidget {
  const EmbeddedPushSetupView({
    super.key,
    required this.notifier,
    this.onChanged,
  });

  final EmbeddedNtfyNotifier notifier;
  final VoidCallback? onChanged;

  @override
  State<EmbeddedPushSetupView> createState() => _EmbeddedPushSetupViewState();
}

class _EmbeddedPushSetupViewState extends State<EmbeddedPushSetupView> {
  bool isResetting = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tiamat.Text.labelLow(
          "Push notifications are delivered directly via ${BuildConfig.androidPushGatewayHost}. No distributor app is required.",
        ),
        const SizedBox(height: 12),
        tiamat.Text.label("Gateway:"),
        tiamat.Text.labelLow(preferences.pushGateway),
        const SizedBox(height: 8),
        tiamat.Text.label("Topic:"),
        tiamat.Text.labelLow(widget.notifier.topic),
        const SizedBox(height: 8),
        tiamat.Text.label("Endpoint:"),
        tiamat.Text.labelLow(widget.notifier.endpoint),
        const SizedBox(height: 12),
        tiamat.Button.secondary(
          text: isResetting ? "Resetting..." : "Reset Push Token",
          onTap: isResetting ? null : _resetPushToken,
        ),
      ],
    );
  }

  Future<void> _resetPushToken() async {
    setState(() {
      isResetting = true;
    });

    try {
      await widget.notifier.resetTopic();
      widget.onChanged?.call();
    } finally {
      if (!mounted) {
        return;
      }

      setState(() {
        isResetting = false;
      });
    }
  }
}
