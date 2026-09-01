import 'package:intergalactic/client/components/voip/mobile_call_popout_controller.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
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
    final isMobilePopout =
        !BuildConfig.DESKTOP &&
        (PlatformUtils.isAndroid || PlatformUtils.isIOS);
    final body = isMobilePopout
        ? "The live call is open in picture in picture."
        : usesDetachedWindow
        ? "The live call is open in a separate window."
        : "The live call is floating in the app window.";
    final restoreLabel = isMobilePopout
        ? "Return to call"
        : "Dock back to room";
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
        const Center(child: tiamat.Text.label("Call popped out")),
        const SizedBox(height: 4),
        Center(child: tiamat.Text.labelLow(body)),
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
              text: restoreLabel,
              onTap: () async {
                if (isMobilePopout) {
                  final exited =
                      await MobileCallPopoutController.exitPictureInPicture(
                        reason: 'placeholder_restore',
                      );
                  if (!exited) {
                    await MobileCallPopoutController.refreshPresentationState();
                    if (MobileCallPopoutController
                        .presentationState
                        .isPictureInPicture) {
                      Log.w(
                        'Skipped restoring mobile call placeholder because native PiP exit did not confirm',
                        category: LogCategory.livekit,
                        source: 'mobile-call-popout',
                      );
                      return;
                    }
                  }
                }
                callPopoutController.restoreSession(session.sessionId);
              },
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
