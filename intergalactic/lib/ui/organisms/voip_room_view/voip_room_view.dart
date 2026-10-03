import 'dart:async';

import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip_room/voip_room_component.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_backend.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:intergalactic/ui/atoms/shimmer_loading.dart';
import 'package:intergalactic/ui/layout/bento.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/organisms/call_view/call.dart';
import 'package:intergalactic/ui/organisms/call_view/call_popped_out_placeholder.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class VoipRoomView extends StatefulWidget {
  final VoipRoomComponent voip;
  final bool forceCallControlsVisible;
  const VoipRoomView(
    this.voip, {
    this.forceCallControlsVisible = false,
    super.key,
  });

  @override
  State<VoipRoomView> createState() => _VoipRoomViewState();
}

class _VoipRoomViewState extends State<VoipRoomView> {
  VoipSession? currentSession;
  String? callServerUrl;
  late List<String> participants;
  bool joining = false;
  StreamSubscription? sub;
  StreamSubscription? _popoutSub;

  @override
  void initState() {
    currentSession = widget.voip.currentSession;
    participants = widget.voip.getCurrentParticipants();

    sub = widget.voip.onParticipantsChanged.listen((_) {
      // when the participant list changes, the resolved focus may change
      updateCallUrl();

      if (!mounted) {
        return;
      }
      setState(() {
        participants = widget.voip.getCurrentParticipants();
      });
    });
    _popoutSub = callPopoutController.onChanged.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });

    updateCallUrl();
    super.initState();
  }

  void updateCallUrl() {
    widget.voip.getCallServerUrl().then((url) {
      if (!mounted) {
        return;
      }
      Log.i("Call server URL resolved.");
      setState(() {
        callServerUrl = url;
      });
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    _popoutSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _refreshCurrentSession();

    var color = Theme.of(context).colorScheme.surfaceContainer;

    if (currentSession == null) return unjoinedView(color);
    if (currentSession?.state == VoipState.ended) {
      currentSession = null;
      joining = false;
      return unjoinedView(color);
    }

    if (callPopoutController.isSessionPoppedOut(currentSession!.sessionId)) {
      return CallPoppedOutPlaceholder(currentSession!);
    }

    return CallWidget(
      currentSession!,
      forceControlsVisible: widget.forceCallControlsVisible,
    );
  }

  void _refreshCurrentSession() {
    final activeSession = widget.voip.currentSession;
    if (!identical(currentSession, activeSession)) {
      currentSession = activeSession;
      joining = false;
    }
  }

  Column unjoinedView(Color color) {
    final tokens = AccessibilityScope.tokensOf(context);
    final encrypted = widget.voip.room.isE2EE;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.max,
      children: [
        // BUG-335, and this was the owner's actual obstruction. Until now a
        // RELEASE build replaced the entire join view with "Sorry, End-to-end
        // encrypted voice rooms are not yet supported" whenever the ROOM was
        // encrypted, so there was no Join control at all - not a displaced one.
        // A dev build took the other branch, which is why the same room showed
        // different text on the owner's phone and their desktop.
        //
        // The block is removed rather than relocated. It gated on `isE2EE`,
        // which is the room's TIMELINE encryption, and a call in an encrypted
        // room is neither more nor less supported than one in an unencrypted
        // room: this app has no call-media E2EE on either path, so there was
        // nothing for the block to protect anyone from.
        Expanded(child: joinCallView()),
        Align(
          alignment: AlignmentGeometry.bottomLeft,
          child: tiamat.Tooltip(
            // BUG-335. This used to read "This room is encrypted, your call is
            // secure and private" for an encrypted room, which is the strongest
            // and most direct of the three false claims this surface carried:
            // call media is NOT end-to-end encrypted on either path. The
            // unencrypted variant was wrong by implication in the same
            // direction, since "may be accessible by the server operator" reads
            // as something an encrypted room would avoid, and it does not.
            //
            // The padlock still reflects the ROOM's encryption, which is true
            // and is what the icon has always meant; only the call claim is
            // corrected. Wording reviewed by S&C - it deliberately does not
            // name whose server, because the focus is whatever
            // `livekit_service_url` the room advertises
            // (matrix_livekit_backend.dart:299), not necessarily our own.
            text: widget.voip.room.isE2EE
                ? "Messages in this room are encrypted. Calls are not "
                      "end-to-end encrypted - the call server that relays them "
                      "can access them."
                : "This room is not encrypted, and calls are not end-to-end "
                      "encrypted - the call server that relays them can access "
                      "them.",
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    encrypted ? Icons.lock : Icons.lock_open,
                    color: encrypted ? tokens.success : tokens.danger,
                    semanticLabel: encrypted
                        ? "Encrypted call room"
                        : "Unencrypted call room",
                  ),
                  SizedBox(width: 3),
                  Shimmer(
                    child: ShimmerLoading(
                      isLoading: callServerUrl == null,
                      child: callServerUrl == null
                          ? Container(
                              height: 16,
                              width: 150,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                color: color,
                              ),
                            )
                          : tiamat.Text.labelLow(callServerUrl!),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Column joinCallView() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (participants.isNotEmpty)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: BentoLayout(
                participants.map((item) {
                  final member = widget.voip.room.getMemberOrFallback(item);
                  return Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: tiamat.Tile.low(
                      child: Center(
                        child: tiamat.Avatar(
                          radius: 50,
                          image: member.avatar,
                          placeholderColor: member.defaultColor,
                          placeholderText: member.displayName,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        // BUG-335. An inherited warning used to sit here whenever the ROOM was
        // encrypted: "End-to-end encrypted calls are still under development,
        // and may contain bugs or security issues."
        //
        // It was removed rather than relocated, because it was wrong in the
        // direction that OVERSTATES security - it asserts the calls ARE
        // end-to-end encrypted and merely immature. This app has no call-media
        // E2EE at all: no `e2eeOptions` reaches `lk.Room`
        // (matrix_livekit_room_factory_io.dart), and
        // `matrix_voip_component.dart:291` declines the Matrix SDK's group-call
        // key hook outright with `throw UnimplementedError()`. The condition
        // was wrong too - `room.isE2EE` is the room's TIMELINE encryption, and
        // call media is exposed identically either way, so this warned where
        // nothing had changed and stayed silent where the exposure was the
        // same.
        //
        // The true statement now lives in room security settings, where the
        // expectation is formed. It is NOT restated here: this surface is the
        // one the owner could not get past on mobile, which is the bug.
        if (participants.isEmpty)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: tiamat.Tile.surfaceContainer(
                  child: Center(
                    child: tiamat.Text.labelLow("No one's here..."),
                  ),
                ),
              ),
            ),
          ),
        if (widget.voip.canJoinCall)
          Center(
            child: tiamat.Button(
              isLoading: joining,
              text: CommonStrings.promptJoin,
              onTap: joinRoomCall,
            ),
          ),
        if (!widget.voip.canJoinCall)
          Center(
            child: tiamat.Text.labelLow(
              "You do not have permission to join this call",
            ),
          ),
      ],
    );
  }

  joinRoomCall() async {
    if (joining) {
      return;
    }

    setState(() {
      joining = true;
    });

    try {
      final session = await widget.voip.joinCall();
      if (!mounted) {
        return;
      }

      setState(() {
        joining = false;
        if (session != null) {
          currentSession = session;
        }
      });
    } catch (e, s) {
      if (e is MatrixLivekitCallJoinPreflightException) {
        Log.w(
          'Call join blocked by local E2EE trust preflight',
          category: LogCategory.livekit,
          source: 'voip-room-view',
        );
        if (!mounted) {
          return;
        }

        setState(() {
          joining = false;
        });

        await AdaptiveDialog.show(
          context,
          title: 'Verify this session',
          builder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [tiamat.Text.body(e.message)],
          ),
        );
        if (!mounted) {
          return;
        }
        return;
      }

      if (e is MatrixLivekitCallJoinTransientNetworkException) {
        final retryAfter = e.retryAfter;
        Log.w(
          'Call join failed after transient LiveKit retries '
          'attempts=${e.attempts}'
          '${retryAfter == null ? '' : ' retry_after_ms=${retryAfter.inMilliseconds}'}',
          category: LogCategory.livekit,
          source: 'voip-room-view',
        );
        if (!mounted) {
          return;
        }

        setState(() {
          joining = false;
        });

        await AdaptiveDialog.show(
          context,
          title: 'Call server connection failed',
          builder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [tiamat.Text.body(e.message)],
          ),
        );
        if (!mounted) {
          return;
        }
        return;
      }

      if (e is TimeoutException || _isLikelyNetworkFailure(e)) {
        // A raw timeout or socket/handshake failure escaping join() almost
        // always means the call or Matrix server was unreachable, not an app
        // fault. Show a plain "check your connection" message instead of a raw
        // exception dump.
        Log.w(
          'Call join failed, likely a network/connectivity problem '
          '(${e.runtimeType})',
          category: LogCategory.livekit,
          source: 'voip-room-view',
        );
        if (!mounted) {
          return;
        }

        setState(() {
          joining = false;
        });

        await AdaptiveDialog.show(
          context,
          title: "Couldn't connect to the call",
          builder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tiamat.Text.body(
                'Inter Galactic could not reach the call server. This usually '
                'means your internet connection dropped or is unstable. Check '
                'your connection and try joining again.',
              ),
            ],
          ),
        );
        if (!mounted) {
          return;
        }
        return;
      }

      Log.onError(
        e,
        s,
        content: 'Failed to join call',
        category: LogCategory.livekit,
        source: 'voip-room-view',
      );
      if (!mounted) {
        return;
      }

      AdaptiveDialog.showError(context, e, s);

      setState(() {
        joining = false;
      });
    }
  }

  /// Whether [error] looks like a transport/connectivity failure, matched by
  /// runtime type name so this stays web-safe (no `dart:io` import). Covers the
  /// socket, TLS handshake, and HTTP client failures that surface when the call
  /// or Matrix server is unreachable.
  static bool _isLikelyNetworkFailure(Object error) {
    const networkErrorTypes = {
      'SocketException',
      'HandshakeException',
      'ClientException',
      'HttpException',
    };
    return networkErrorTypes.contains(error.runtimeType.toString());
  }
}
