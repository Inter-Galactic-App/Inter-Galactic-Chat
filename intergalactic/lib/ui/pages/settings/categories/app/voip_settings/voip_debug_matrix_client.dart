import 'dart:convert';

import 'package:intergalactic/client/alert.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_capture_profile.dart';
import 'package:intergalactic/client/matrix/components/voip/matrix_voip_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/molecules/alert_view.dart';
import 'package:intergalactic/utils/local_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart' as mx;

import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;

class VoipDebugMatrixClient extends StatefulWidget {
  const VoipDebugMatrixClient(this.client, {super.key});
  final MatrixClient client;
  @override
  State<VoipDebugMatrixClient> createState() => _VoipDebugMatrixClientState();
}

class _VoipDebugMatrixClientState extends State<VoipDebugMatrixClient> {
  bool loading = true;
  bool homeserverHasTurnServer = false;
  mx.TurnServerCredentials? credentials;
  webrtc.RTCPeerConnection? connection;
  List<webrtc.RTCIceCandidate> foundCandidates = List.empty(growable: true);
  webrtc.RTCSessionDescription? description;
  webrtc.RTCIceGatheringState? gatheringState;
  Map<String, dynamic>? connectionConfiguration;
  bool savingLog = false;

  @override
  void initState() {
    super.initState();

    load();
  }

  @override
  void dispose() {
    connection?.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      var turnServer = await widget.client.getMatrixClient().getTurnServer();
      setState(() {
        credentials = turnServer;
        loading = false;
        homeserverHasTurnServer = true;
      });
    } catch (_) {
      setState(() {
        loading = false;
        homeserverHasTurnServer = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        height: 500,
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    return Column(
      children: [
        if (homeserverHasTurnServer == false)
          AlertView(Alert(AlertType.warning,
              messageGetter: () =>
                  "Your homeserver (${widget.client.getMatrixClient().homeserver}) does not have a TURN server configured",
              titleGetter: () => "TURN Error")),
        tiamat.Panel(
          mode: tiamat.TileType.surfaceContainerLow,
          header: "TURN Server (Homeserver Configuration)",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (credentials != null) showTurnServerCredentials(),
              testTurnServer(),
            ],
          ),
        )
      ],
    );
  }

  Widget testTurnServer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              tiamat.Button.secondary(
                text: "Test TURN Server",
                onTap: testTurn,
              ),
              if (connection != null)
                tiamat.Button.secondary(
                  text: savingLog ? "Saving Log..." : "Save Test Log",
                  isLoading: savingLog,
                  onTap: savingLog ? null : saveConnectionLog,
                ),
            ],
          ),
        ),
        if (connection != null) showTestConnectionInfo()
      ],
    );
  }

  Widget showTurnServerCredentials() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tiamat.Text.labelLow("username: ${credentials!.username}"),
        tiamat.Text.labelLow("password: ${"•" * credentials!.password.length}"),
        const tiamat.Seperator(),
        for (var item in credentials!.uris) tiamat.Text.labelLow(item)
      ],
    );
  }

  Widget showTestConnectionInfo() {
    return Column(
      children: [
        tiamat.Panel(
          mode: tiamat.TileType.surfaceContainerLow,
          header: "Connection Test",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (connectionConfiguration != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                  child: tiamat.Panel(
                    mode: tiamat.TileType.surfaceContainerLow,
                    header: "Connecting with config:",
                    child: tiamat.Text.tiny(const JsonEncoder.withIndent('  ')
                        .convert(connectionConfiguration!)
                        .replaceAll(credentials?.password ?? "",
                            "•" * (credentials?.password.length ?? 0))),
                  ),
                ),
              if (foundCandidates.isNotEmpty)
                tiamat.Panel(
                  header: "Candidates",
                  mode: tiamat.TileType.surfaceContainerLowest,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var candidate in foundCandidates)
                          Padding(
                              padding: const EdgeInsets.all(8),
                              child: tiamat.Text.label(
                                  candidate.candidate ?? "ERROR")),
                        if (gatheringState ==
                            webrtc.RTCIceGatheringState
                                .RTCIceGatheringStateGathering)
                          const Align(
                            alignment: Alignment.topCenter,
                            child: CircularProgressIndicator(),
                          )
                      ]),
                ),
              if (description != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                  child: tiamat.Panel(
                      header: "Offer",
                      mode: tiamat.TileType.surfaceContainerLowest,
                      child: tiamat.Text.tiny(description!.sdp ?? "")),
                )
            ],
          ),
        )
      ],
    );
  }

  Future<void> testTurn() async {
    foundCandidates = List.empty(growable: true);

    var servers = credentials == null
        ? []
        : [
            {
              'username': credentials!.username,
              'credential': credentials!.password,
              'urls': List.from(credentials!.uris)
            },
          ];

    var configuration = <String, dynamic>{
      'iceServers': servers,
      'sdpSemantics': 'unified-plan',
    };

    var component = widget.client.getComponent<MatrixVoipComponent>();
    configuration = await component!.alterPeerConfiguration(configuration);

    setState(() {
      connectionConfiguration = configuration;
    });

    connection = await webrtc.createPeerConnection(configuration);

    var mediaConstraints = {
      'audio': NoiseSuppressionCaptureProfile.buildWebrtcAudioConstraints(),
      'video': false,
    };

    connection!.onIceCandidate = onIceCandidate;
    connection!.onIceGatheringState = onIceGatheringState;

    var media =
        await webrtc.navigator.mediaDevices.getUserMedia(mediaConstraints);
    for (var track in media.getTracks()) {
      await connection!.addTrack(track, media);
    }

    var offer = await connection!.createOffer({});
    await connection!.setLocalDescription(offer);
  }

  Future<void> saveConnectionLog() async {
    setState(() => savingLog = true);
    try {
      final log = buildConnectionLog();
      final bytes = Uint8List.fromList(utf8.encode(log));
      final fileName = _connectionLogFileName();
      String? destinationPath;

      if (PlatformUtils.isAndroid || kIsWeb) {
        destinationPath = await FilePicker.platform.saveFile(
          fileName: fileName,
          initialDirectory: preferences.lastDownloadLocation.value,
          bytes: bytes,
        );
      } else {
        destinationPath = await FilePicker.platform.saveFile(
          fileName: fileName,
          initialDirectory: preferences.lastDownloadLocation.value,
        );
        if (destinationPath != null) {
          await writeLocalFileBytes(destinationPath, bytes);
        }
      }

      if (!mounted || destinationPath == null) {
        return;
      }
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text("Saved WebRTC log to $destinationPath")),
      );
    } catch (error, stackTrace) {
      Log.onError(error, stackTrace, content: "Failed to save WebRTC log");
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text("Failed to save WebRTC log")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => savingLog = false);
      }
    }
  }

  String buildConnectionLog() {
    final buffer = StringBuffer()
      ..writeln("Inter Galactic WebRTC TURN diagnostics")
      ..writeln("Generated: ${DateTime.now().toIso8601String()}")
      ..writeln("Client: ${Log.redactSensitiveInfo(widget.client.identifier)}")
      ..writeln("Homeserver configured: yes")
      ..writeln("TURN configured: $homeserverHasTurnServer")
      ..writeln("ICE gathering state: ${gatheringState?.name ?? "unknown"}")
      ..writeln();

    if (credentials != null) {
      buffer
        ..writeln("TURN username: [TURN_USERNAME]")
        ..writeln("TURN password: [REDACTED]")
        ..writeln("TURN URI count: ${credentials!.uris.length}")
        ..writeln("TURN URI schemes: ${_turnUriSchemes().join(", ")}")
        ..writeln()
        ..writeln();
    }

    if (connectionConfiguration != null) {
      buffer
        ..writeln("Peer connection configuration:")
        ..writeln(_connectionConfigurationSummary())
        ..writeln();
    }

    buffer
      ..writeln("Candidates (${foundCandidates.length}):")
      ..writeAll(
        foundCandidates.map((candidate) => "- ${_candidateSummary(candidate)}"),
        "\n",
      )
      ..writeln()
      ..writeln();

    if (description != null) {
      buffer
        ..writeln("Offer:")
        ..writeln(_offerSummary(description!.sdp));
    }

    return Log.redactSensitiveInfo(_redactSecrets(buffer.toString()));
  }

  String _connectionLogFileName() {
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(":", "-")
        .replaceAll(".", "-");
    return "intergalactic-webrtc-turn-$timestamp.log";
  }

  String _redactedPassword() {
    return "•" * (credentials?.password.length ?? 0);
  }

  String _redactSecrets(String value) {
    final password = credentials?.password;
    if (password == null || password.isEmpty) {
      return value;
    }
    return value.replaceAll(password, _redactedPassword());
  }

  List<String> _turnUriSchemes() {
    final schemes = credentials!.uris
        .map((uri) {
          final separator = uri.indexOf(":");
          if (separator <= 0) {
            return "unknown";
          }
          return uri.substring(0, separator).toLowerCase();
        })
        .toSet()
        .toList()
      ..sort();
    return schemes;
  }

  String _connectionConfigurationSummary() {
    final config = connectionConfiguration;
    if (config == null) {
      return "- unavailable";
    }

    final iceServers = config["iceServers"];
    final iceServerCount = iceServers is List ? iceServers.length : 0;
    final sdpSemantics = config["sdpSemantics"]?.toString() ?? "unknown";
    return "- ICE server count: $iceServerCount\n"
        "- SDP semantics: $sdpSemantics";
  }

  String _candidateSummary(webrtc.RTCIceCandidate candidate) {
    final raw = candidate.candidate ?? "";
    final type =
        _firstCandidateMatch(raw, RegExp(r"\btyp\s+([^\s]+)")) ?? "unknown";
    final protocol =
        _firstCandidateMatch(raw, RegExp(r"candidate:\S+\s+\d+\s+([^\s]+)")) ??
            "unknown";
    return "mid=${candidate.sdpMid ?? "unknown"} "
        "mLine=${candidate.sdpMLineIndex ?? "unknown"} "
        "protocol=${protocol.toLowerCase()} type=${type.toLowerCase()}";
  }

  String? _firstCandidateMatch(String value, RegExp pattern) {
    final match = pattern.firstMatch(value);
    return match?.group(1);
  }

  String _offerSummary(String? sdp) {
    if (sdp == null || sdp.trim().isEmpty) {
      return "- SDP unavailable";
    }
    final lines = const LineSplitter().convert(sdp);
    final candidateLines =
        lines.where((line) => line.startsWith("a=candidate:"));
    return "- SDP redacted\n"
        "- Line count: ${lines.length}\n"
        "- Candidate line count: ${candidateLines.length}";
  }

  void onIceCandidate(webrtc.RTCIceCandidate candidate) {
    setState(() {
      foundCandidates.add(candidate);
    });
  }

  void onIceGatheringState(webrtc.RTCIceGatheringState state) {
    setState(() {
      gatheringState = state;
    });
  }
}
