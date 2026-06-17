import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/main.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class CallPoppedOutPlaceholder extends StatelessWidget {
  const CallPoppedOutPlaceholder(
    this.session, {
    super.key,
    this.compact = false,
  });

  final VoipSession session;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final usesDetachedWindow =
        callPopoutController.usesNativeDetachedSessionPopouts;
    final content = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          Icons.open_in_new_rounded,
          size: compact ? 20 : 28,
          color: Theme.of(context).colorScheme.primary,
        ),
        SizedBox(height: compact ? 8 : 12),
        const Center(
          child: tiamat.Text.label(
            "Call popped out",
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: tiamat.Text.labelLow(
            usesDetachedWindow
                ? "The live call is open in a separate window."
                : "The live call is floating in the app window.",
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            if (BuildConfig.DESKTOP && usesDetachedWindow)
              tiamat.Button.secondary(
                text: "Focus call window",
                onTap: () {
                  callPopoutController.focusSessionWindow(session.sessionId);
                },
              ),
            tiamat.Button.secondary(
              text: "Dock back to room",
              onTap: BuildConfig.DESKTOP
                  ? () {
                      callPopoutController.restoreSession(session.sessionId);
                    }
                  : null,
            ),
          ],
        ),
      ],
    );

    return Padding(
      padding: EdgeInsets.all(compact ? 8 : 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: tiamat.Tile.low(
          child: Padding(
            padding: EdgeInsets.all(compact ? 16 : 24),
            child: content,
          ),
        ),
      ),
    );
  }
}
