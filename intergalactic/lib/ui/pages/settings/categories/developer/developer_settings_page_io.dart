import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/activity/activity_connection_alerts.dart';
import 'package:intergalactic/client/components/push_notification/ios/ios_notifier.dart';
import 'package:intergalactic/client/components/push_notification/ios/notification_policy_snapshot_io.dart';
import 'package:intergalactic/client/components/push_notification/notification_content.dart';
import 'package:intergalactic/client/components/push_notification/notification_manager.dart';
import 'package:intergalactic/client/matrix/database/app_group/drift_database_location.dart';
import 'package:intergalactic/config/app_config.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/diagnostic/diagnostics.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/atoms/code_block.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/navigation/navigation_utils.dart';
import 'package:intergalactic/ui/pages/developer/benchmarks/timeline_viewer_benchmark.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/boolean_toggle.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/double_preference_slider.dart';
import 'package:intergalactic/ui/pages/settings/categories/developer/cumulative_diagnostics_widget.dart';
import 'package:intergalactic/utils/background_tasks/background_task_manager.dart';
import 'package:intergalactic/utils/background_tasks/mock_tasks.dart';
import 'package:intergalactic/utils/system_processes_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:window_manager/window_manager.dart';

class DeveloperSettingsPage extends StatefulWidget {
  const DeveloperSettingsPage({super.key});

  @override
  State<DeveloperSettingsPage> createState() => _DeveloperSettingsPageState();
}

class _DeveloperSettingsPageState extends State<DeveloperSettingsPage> {
  final TextEditingController _iosApnsReplayController =
      TextEditingController();

  @override
  void dispose() {
    _iosApnsReplayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        performance(),
        benchmarks(),
        activityConnectionAlerts(),
        accessTokens(),
        if (BuildConfig.DESKTOP) windowSize(),
        notificationTests(),
        rendering(),
        error(),
        if (PlatformUtils.isAndroid) shortcuts(),
        backgroundTasks(),
        if (BuildConfig.DEBUG) dumpDatabases(),
        if (BuildConfig.DEBUG && PlatformUtils.isIOS)
          notificationPolicySnapshotTools(),
        if (BuildConfig.DEBUG) executeShellCommand(),
        otherSettings(),
      ],
    );
  }

  Widget developerUtilityGroup({
    required IconData icon,
    required String title,
    required String description,
    required List<Widget> children,
  }) {
    return _DeveloperUtilityGroup(
      icon: icon,
      title: title,
      description: description,
      children: children,
    );
  }

  Widget paddedButtonWrap(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 14),
      child: Wrap(spacing: 8, runSpacing: 8, children: children),
    );
  }

  Widget performance() {
    return developerUtilityGroup(
      icon: Icons.speed_outlined,
      title: "Performance",
      description:
          "Inspect cumulative app startup, database load, and general runtime diagnostics.",
      children: [
        Diagnostics.general,
        Diagnostics.initialLoadDatabaseDiagnostics,
        Diagnostics.postLoadDatabaseDiagnostics,
      ].map((e) => CumulativeDiagnosticsWidget(diagnostics: e)).toList(),
    );
  }

  Widget activityConnectionAlerts() {
    final simulation = activityConnectionAlertSimulation;

    return developerUtilityGroup(
      icon: Icons.warning_amber_outlined,
      title: 'Activity connection alerts',
      description:
          'Exercise the shared Activity warning and sidebar alert indicator without changing a real connection.',
      children: [
        _DeveloperActionRow(
          title: 'Connection warning simulator',
          description:
              'Adds a temporary local Spotify or Steam warning only. It never calls a provider, relay, or token store and does not change saved settings.',
          action: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              tiamat.Button(
                text:
                    simulation ==
                        ActivityConnectionAlertSimulation
                            .spotifyReconnectRequired
                    ? 'Spotify simulated'
                    : 'Simulate Spotify',
                onTap: () => _setActivityConnectionAlertSimulation(
                  ActivityConnectionAlertSimulation.spotifyReconnectRequired,
                ),
              ),
              tiamat.Button(
                text:
                    simulation ==
                        ActivityConnectionAlertSimulation.steamUnavailable
                    ? 'Steam simulated'
                    : 'Simulate Steam',
                onTap: () => _setActivityConnectionAlertSimulation(
                  ActivityConnectionAlertSimulation.steamUnavailable,
                ),
              ),
              tiamat.Button(
                text: 'Clear simulation',
                onTap: simulation == ActivityConnectionAlertSimulation.none
                    ? null
                    : () => _setActivityConnectionAlertSimulation(
                        ActivityConnectionAlertSimulation.none,
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _setActivityConnectionAlertSimulation(
    ActivityConnectionAlertSimulation simulation,
  ) {
    setActivityConnectionAlertSimulation(simulation);
    setState(() {});
  }

  Widget rendering() {
    return developerUtilityGroup(
      icon: Icons.visibility_outlined,
      title: "Rendering",
      description:
          "Toggle Flutter visual debug overlays for spotting repaint-heavy UI.",
      children: [
        _DeveloperActionRow(
          title: "Show repaints",
          description:
              "Enables Flutter's repaint rainbow so areas that redraw are tinted while the app runs.",
          action: tiamat.Switch(
            state: debugRepaintRainbowEnabled,
            onChanged: (value) {
              setState(() {
                debugRepaintRainbowEnabled = value;
              });
            },
          ),
        ),
      ],
    );
  }

  Widget benchmarks() {
    return developerUtilityGroup(
      icon: Icons.query_stats_outlined,
      title: "Benchmarks",
      description:
          "Open developer benchmark screens used to profile specific UI surfaces.",
      children: [
        _DeveloperActionRow(
          title: "Timeline Viewer",
          description:
              "Launches the timeline viewer benchmark page for measuring timeline rendering behavior.",
          action: tiamat.Button(
            text: "Open",
            onTap: () => NavigationUtils.navigateTo(
              context,
              const BenchmarkTimelineViewer(),
            ),
          ),
        ),
      ],
    );
  }

  Widget windowSize() {
    return developerUtilityGroup(
      icon: Icons.aspect_ratio_outlined,
      title: "Window Size",
      description:
          "Resize the desktop window to common QA targets without using OS window controls.",
      children: [
        paddedButtonWrap([
          tiamat.Button(
            text: "Maximize",
            onTap: () => windowManager.maximize(),
          ),
          tiamat.Button(
            text: "1280x720",
            onTap: () => windowManager.setSize(const Size(1280, 720)),
          ),
          tiamat.Button(
            text: "1280x800 (Steamdeck)",
            onTap: () => windowManager.setSize(const Size(1280, 800)),
          ),
          tiamat.Button(
            text: "1920x1080",
            onTap: () => windowManager.setSize(const Size(1920, 1080)),
          ),
          tiamat.Button(
            text: "2560x1440",
            onTap: () => windowManager.setSize(const Size(2560, 1440)),
          ),
          tiamat.Button(
            text: "3840x2160",
            onTap: () => windowManager.setSize(const Size(3840, 2160)),
          ),
          tiamat.Button(
            text: "1170x2532 (iPhone 12 Pro)",
            onTap: () => windowManager.setSize(const Size(1170, 2532)),
          ),
          tiamat.Button(text: "1:1", onTap: () => setAspectRatio(1)),
          tiamat.Button(text: "16:9", onTap: () => setAspectRatio(16 / 9)),
        ]),
      ],
    );
  }

  void setAspectRatio(double ratio) async {
    var size = await windowManager.getSize();
    var newWidth = size.height * ratio;
    await windowManager.setSize(Size(newWidth, size.height));
  }

  Widget notificationTests() {
    return developerUtilityGroup(
      icon: Icons.notifications_active_outlined,
      title: "Notifications",
      description:
          "Trigger local notification payloads without waiting for a real Matrix push.",
      children: [
        _DeveloperActionRow(
          title: "Message notification",
          description:
              "Creates a fake message notification from the first signed-in account and room.",
          action: tiamat.Button(
            text: "Send",
            onTap: () async {
              final target = _firstNotificationTarget();
              if (target == null) {
                return;
              }
              final client = target.client;
              final room = target.room;
              final user = target.user;
              NotificationManager.notify(
                MessageNotificationContent(
                  senderName: user.displayName,
                  senderImage: user.avatar,
                  senderId: user.identifier,
                  roomName: room.displayName,
                  roomId: room.identifier,
                  roomImage: await room.getShortcutImage(),
                  content: "Test Message!",
                  clientId: client.identifier,
                  eventId: "fake_event_id",
                  isDirectMessage: true,
                ),
              );
            },
          ),
        ),
        _DeveloperActionRow(
          title: "Call notification",
          description:
              "Creates a fake incoming-call notification and starts ringtone playback on desktop.",
          action: tiamat.Button(
            text: "Send",
            onTap: () async {
              final target = _firstNotificationTarget();
              if (target == null) {
                return;
              }
              final client = target.client;
              final room = target.room;
              final user = target.user;

              if (!BuildConfig.ANDROID) {
                clientManager?.callManager.startRingtone();
              }

              NotificationManager.notify(
                CallNotificationContent(
                  title: "Incoming Call!",
                  senderImage: user.avatar,
                  senderId: user.identifier,
                  roomName: room.displayName,
                  roomId: room.identifier,
                  senderName: user.displayName,
                  senderImageId: "fake_call_avatar_id",
                  roomImage: await room.getShortcutImage(),
                  content: "Test Call Notification",
                  clientId: client.identifier,
                  callId: "fake_call_id",
                  isDirectMessage: true,
                ),
              );
            },
          ),
        ),
        if ((BuildConfig.DEBUG || kDebugMode) && BuildConfig.IOS)
          _DeveloperActionRow(
            title: "Replay iOS APNs tap payload",
            description:
                "Paste a saved APNs userInfo JSON object and route it through the native iOS tap bridge.",
            action: SizedBox(
              width: 320,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _iosApnsReplayController,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText:
                          '{"room_id":"!room:example.org","client_id":"@user:example.org"}',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      tiamat.Button(
                        text: "Replay",
                        onTap: () async {
                          final payload = _iosApnsReplayController.text.trim();
                          if (payload.isEmpty) {
                            return;
                          }

                          final replayed =
                              await IosNotifier.replaySavedApnsPayloadForDebug(
                                payload,
                              );
                          _showSnackBar(
                            replayed
                                ? "Queued iOS notification replay."
                                : "iOS notification replay was not available.",
                          );
                        },
                      ),
                      tiamat.Button(
                        text: "Replay Last",
                        onTap: () async {
                          final replayed =
                              await IosNotifier.replayLastCapturedApnsPayloadForDebug();
                          _showSnackBar(
                            replayed
                                ? "Queued last captured iOS notification tap."
                                : "No captured iOS notification tap is available.",
                          );
                        },
                      ),
                      tiamat.Button(
                        text: "Load Last",
                        onTap: () async {
                          final payload =
                              await IosNotifier.lastCapturedApnsPayloadForDebug();
                          if (payload == null || payload.isEmpty) {
                            _showSnackBar(
                              "No captured iOS notification tap is available.",
                            );
                            return;
                          }

                          _iosApnsReplayController.text = payload;
                          _showSnackBar(
                            "Loaded last captured APNs payload locally.",
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  ({Client client, Room room, Profile user})? _firstNotificationTarget() {
    final manager = clientManager;
    if (manager == null) {
      return null;
    }

    for (final client in manager.clients) {
      final user = client.self;
      if (user == null) {
        continue;
      }

      for (final room in client.rooms) {
        return (client: client, room: room, user: user);
      }
    }

    return null;
  }

  Widget shortcuts() {
    return developerUtilityGroup(
      icon: Icons.keyboard_alt_outlined,
      title: "Shortcuts",
      description:
          "Reset Android shortcut registrations when testing launcher shortcut behavior.",
      children: [
        _DeveloperActionRow(
          title: "Clear shortcuts",
          description:
              "Removes every registered launcher shortcut from the Android shortcut manager.",
          action: tiamat.Button(
            text: "Clear",
            onTap: () async {
              await shortcutsManager.clearAllShortcuts();
            },
          ),
        ),
      ],
    );
  }

  Widget backgroundTasks() {
    return developerUtilityGroup(
      icon: Icons.task_alt_outlined,
      title: "Background Tasks",
      description:
          "Create fake background tasks to test progress banners, indeterminate tasks, and task failures.",
      children: [
        _DeveloperActionRow(
          title: "With progress",
          description:
              "Starts a mock background task that reports determinate progress.",
          action: tiamat.Button(
            text: "Start",
            onTap: () =>
                backgroundTaskManager.addTask(FakeBackgroundTaskWithProgress()),
          ),
        ),
        _DeveloperActionRow(
          title: "Indeterminate",
          description:
              "Starts a mock background task without a known completion percentage.",
          action: tiamat.Button(
            text: "Start",
            onTap: () => backgroundTaskManager.addTask(FakeBackgroundTask()),
          ),
        ),
        _DeveloperActionRow(
          title: "Background error notification",
          description:
              "Posts the fallback notification the background-service and "
              "push error paths use. Those paths run in the headless isolate "
              "and cannot be reached from here, so this checks the SHADE "
              "CONTENT - it must carry no exception text or stack trace.",
          action: tiamat.Button(
            text: "Post",
            onTap: () => NotificationManager.notify(
              ErrorNotificationContent(
                title: "Notification needs attention",
                content: "Open Inter Galactic to view the latest message.",
              ),
            ),
          ),
        ),
        _DeveloperActionRow(
          title: "Async task with crash",
          description:
              "Starts a delayed mock task that throws, for testing failure surfaces.",
          action: tiamat.Button(
            text: "Start",
            onTap: () => backgroundTaskManager.addTask(
              AsyncTask(() async {
                await Future.delayed(const Duration(seconds: 5));
                throw Exception("This background task failed!");
              }, "Async task"),
            ),
          ),
        ),
      ],
    );
  }

  Widget accessTokens() {
    final matrixClients = (clientManager?.clients ?? const <Client>[])
        .whereType<MatrixClient>();

    return developerUtilityGroup(
      icon: Icons.key_outlined,
      title: "Access Tokens",
      description:
          "Reveal the homeserver access token for each signed-in account. Useful for API/debug flows. Treat tokens like passwords - anyone with one has full access to that account.",
      children: [
        if (matrixClients.isEmpty)
          const _DeveloperActionRow(
            title: "No signed-in accounts",
            description: "Sign in to an account to view its access token.",
            action: SizedBox.shrink(),
          )
        else
          for (final client in matrixClients)
            _DeveloperActionRow(
              title: client.self?.identifier ?? client.identifier,
              description: [
                if (client.debugHomeserverUrl != null)
                  client.debugHomeserverUrl!,
                if (client.debugDeviceId != null)
                  "Device ${client.debugDeviceId}",
              ].join("  •  "),
              action: tiamat.Button(
                text: "Show token",
                onTap: () => _showAccessToken(client),
              ),
            ),
      ],
    );
  }

  Future<void> _showAccessToken(MatrixClient client) async {
    final token = client.debugAccessToken;
    if (token == null || token.isEmpty) {
      await AdaptiveDialog.show(
        context,
        builder: (context) => const Codeblock(
          text: "No access token is available for this session.",
        ),
      );
      return;
    }

    await AdaptiveDialog.show(
      context,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Codeblock(text: token),
            const SizedBox(height: 8),
            tiamat.Button(
              text: "Copy to clipboard",
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: token));
              },
            ),
          ],
        );
      },
    );
  }

  Widget error() {
    return developerUtilityGroup(
      icon: Icons.error_outline,
      title: "Error",
      description:
          "Intentionally throw an exception to test error logging and report flows.",
      children: [
        _DeveloperActionRow(
          title: "Throw an error",
          description:
              "Immediately throws a null access exception on the UI isolate.",
          action: tiamat.Button(
            text: "Throw",
            onTap: () {
              String? empty;
              empty!.split(" ");
            },
          ),
        ),
      ],
    );
  }

  Widget executeShellCommand() {
    return developerUtilityGroup(
      icon: Icons.terminal_outlined,
      title: "Dangerous",
      description:
          "Inspect local processes or run a raw shell command. Use only when debugging trusted local builds.",
      children: [
        _DeveloperActionRow(
          title: "Get process list",
          description:
              "Reads the local process list and opens it in a selectable output viewer.",
          action: tiamat.Button(
            text: "Open",
            onTap: () async {
              var list = await SystemProcessesUtils.getProcessList();
              AdaptiveDialog.show(
                context,
                builder: (context) {
                  return Codeblock(
                    text: list
                        .map(
                          (i) => "[${i.processId}] = ${i.command}  ${i.args}",
                        )
                        .join("\n"),
                  );
                },
              );
            },
          ),
        ),
        _DeveloperActionRow(
          title: "Execute shell command",
          description:
              "Prompts for an executable and arguments, then streams stdout in a dialog.",
          action: tiamat.Button(
            text: "Run",
            onTap: () async {
              var text = await AdaptiveDialog.textPrompt(
                context,
                title: "Execute Shell Command",
              );
              if (text != null) {
                var command = text.split(" ");
                var exe = command.first;
                var args = command.sublist(1);

                var process = await Process.start(exe, args);

                AdaptiveDialog.show(
                  context,
                  builder: (context) => ProcessOutputViewer(process),
                );
              }
            },
          ),
        ),
      ],
    );
  }

  /// S&C required check (1) for the Notification Service Extension: with the
  /// policy snapshot deleted, corrupted or truncated, the extension must
  /// deliver the gateway's generic payload. These act on the real file in the
  /// App Group so the check runs against the real read path; Rewrite restores
  /// it from the live preferences.
  Widget notificationPolicySnapshotTools() {
    // Every button here must run through this: a file-system failure that is
    // neither awaited nor caught reports success by showing nothing.
    Future<void> run(String action, Future<void> Function() change) async {
      try {
        await change();
        Log.i(
          'Notification policy snapshot developer action=$action',
          category: LogCategory.notifications,
          source: 'developer-tools',
        );
      } catch (error, stackTrace) {
        if (mounted) {
          await AdaptiveDialog.showError(context, error, stackTrace);
        }
      }
    }

    Future<void> tamper(
      String action,
      Future<void> Function(File file) change,
    ) async {
      final directory = await NotificationPolicySnapshot.developerDirectory();
      if (directory == null) {
        return;
      }
      final file = File(p.join(directory, NotificationPolicySnapshot.fileName));
      await run(action, () => change(file));
    }

    return developerUtilityGroup(
      icon: Icons.policy_outlined,
      title: "Notification Policy Snapshot",
      description:
          "Tamper with the extension's policy file to prove it fails closed (S&C check 1), then rewrite it.",
      children: [
        _DeveloperActionRow(
          title: "Rewrite",
          description: "Write the snapshot from the live preferences.",
          action: tiamat.Button(
            text: "Rewrite",
            onTap: () => run('rewrite', NotificationPolicySnapshot.write),
          ),
        ),
        _DeveloperActionRow(
          title: "Rewrite with images off",
          description:
              "Write the snapshot with media previews off (S&C check 2). Expect an image message without a picture.",
          action: tiamat.Button(
            text: "Images off",
            onTap: () => run(
              'rewrite_media_off',
              NotificationPolicySnapshot.developerWriteWithMediaOff,
            ),
          ),
        ),
        _DeveloperActionRow(
          title: "Delete",
          description: "Remove the file. Expect the generic notification.",
          action: tiamat.Button(
            text: "Delete",
            onTap: () => tamper('delete', (file) async {
              if (await file.exists()) {
                await file.delete();
              }
            }),
          ),
        ),
        _DeveloperActionRow(
          title: "Corrupt",
          description: "Replace the file with bytes that are not JSON.",
          action: tiamat.Button(
            text: "Corrupt",
            onTap: () => tamper('corrupt', (file) async {
              await file.writeAsString(
                '{"version": 1, "notifications_enabled": tru',
                flush: true,
              );
            }),
          ),
        ),
        _DeveloperActionRow(
          title: "Truncate",
          description: "Cut the file to half its length.",
          action: tiamat.Button(
            text: "Truncate",
            onTap: () => tamper('truncate', (file) async {
              final bytes = await file.readAsBytes();
              await file.writeAsBytes(
                bytes.sublist(0, bytes.length ~/ 2),
                flush: true,
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget dumpDatabases() {
    return developerUtilityGroup(
      icon: Icons.storage_outlined,
      title: "Dump Databases",
      description:
          "Copy local app database files to a folder for manual inspection or issue reproduction.",
      children: [
        _DeveloperActionRow(
          title: "Dump databases",
          description:
              "Copies database files from the app support directory into a chosen folder.",
          action: tiamat.Button(
            text: "Choose Folder",
            onTap: () async {
              var folder = await FilePicker.platform.getDirectoryPath();
              if (folder == null) {
                return;
              }

              var dbDir = Directory(await AppConfig.getDatabasePath());

              var files = await dbDir
                  .list(recursive: true)
                  .where((event) => event is File)
                  .toList();

              // On iOS the account databases live in the App Group container
              // once the migration has run, outside getDatabasePath(). Include
              // them, or the dump quietly stops containing the account data.
              List<FileSystemEntity>? appGroupFiles;
              final appGroupRoot = DriftDatabaseLocation.appGroupDriftRoot;
              if (appGroupRoot != null) {
                final appGroupDir = Directory(appGroupRoot);
                if (await appGroupDir.exists()) {
                  appGroupFiles = await appGroupDir
                      .list(recursive: true)
                      .where((event) => event is File)
                      .toList();
                }
              }

              Future<void> copyInto(
                String destinationRoot,
                List<FileSystemEntity> entries,
              ) async {
                for (var file in entries) {
                  var name = p.basename(file.path);
                  var dirname = p.basename(p.dirname(file.path));

                  var newFolder = Directory(p.join(destinationRoot, dirname));
                  if (!await newFolder.exists()) {
                    await newFolder.create(recursive: true);
                  }

                  var newFile = p.join(destinationRoot, dirname, name);
                  await (file as File).copy(newFile);
                }
              }

              try {
                await copyInto(folder, files);
                if (appGroupFiles != null) {
                  // After the migration both sources hold account databases
                  // with the same directory and file names, so the App Group
                  // copies need their own root or one silently overwrites the
                  // other and the dump contains only half the accounts.
                  await copyInto(p.join(folder, 'app-group'), appGroupFiles);
                }
              } catch (error, stackTrace) {
                if (mounted) {
                  await AdaptiveDialog.showError(context, error, stackTrace);
                }
              }
            },
          ),
        ),
      ],
    );
  }

  Widget otherSettings() {
    return developerUtilityGroup(
      icon: Icons.tune_outlined,
      title: "Other Settings",
      description:
          "Miscellaneous local debug toggles that affect editor behavior, translation display, timeline diagnostics, and keyboard positioning.",
      children: [
        if (!BuildConfig.MOBILE)
          BooleanPreferenceToggle(
            preference: preferences.disableTextCursorManagement,
            title: "Disable Text Cursor Management",
            description:
                "Stops the rich-text editor from making automatic cursor corrections while you debug composer selection behavior.",
          ),
        BooleanPreferenceToggle(
          preference: preferences.debugTranslations,
          title: "Debug Translations",
          description:
              "Shows translation/debug text so missing or incorrect localization strings are easier to spot.",
        ),
        BooleanPreferenceToggle(
          preference: preferences.showTimelineDiagnostics,
          title: "Show timeline diagnostics",
          description:
              "Show raw Matrix timeline events, reactions, hidden events, and parse failures in room message lists.",
        ),
        DoublePreferenceSlider(
          preference: preferences.customOnscreenKeyboardViewOffset,
          title: "Keyboard Offset",
          min: 0.0,
          max: 1000,
          description:
              "Manually shifts the app upward when the on-screen keyboard is shown, useful for debugging platform inset behavior.",
        ),
      ],
    );
  }
}

class _DeveloperUtilityGroup extends StatelessWidget {
  const _DeveloperUtilityGroup({
    required this.icon,
    required this.title,
    required this.description,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 10),
      child: Material(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.72),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ExpansionTile(
            leading: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
            title: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
              ),
            ),
            subtitle: Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 1.25,
                letterSpacing: 0,
              ),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(0, 0, 0, 12),
            children: children,
          ),
        ),
      ),
    );
  }
}

class _DeveloperActionRow extends StatelessWidget {
  const _DeveloperActionRow({
    required this.title,
    required this.description,
    required this.action,
  });

  final String title;
  final String description;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.72),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final label = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    height: 1.25,
                    letterSpacing: 0,
                  ),
                ),
              ],
            );

            if (constraints.maxWidth < 520) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  label,
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerRight, child: action),
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: label),
                const SizedBox(width: 16),
                action,
              ],
            );
          },
        ),
      ),
    );
  }
}

class ProcessOutputViewer extends StatefulWidget {
  const ProcessOutputViewer(this.process, {super.key});
  final Process process;

  @override
  State<ProcessOutputViewer> createState() => _ProcessOutputViewerState();
}

class _ProcessOutputViewerState extends State<ProcessOutputViewer> {
  String stdOut = "";
  String stdError = "";

  late List<StreamSubscription> subs;

  @override
  void initState() {
    super.initState();

    subs = [
      widget.process.stdout.transform(utf8.decoder).listen(onStdout),
      widget.process.stderr.transform(utf8.decoder).listen(onStderr),
    ];
  }

  @override
  void dispose() {
    for (var sub in subs) {
      sub.cancel();
    }

    widget.process.kill();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1000,
      child: SingleChildScrollView(
        child: Codeblock(
          text: stdOut,
          clipboardText: stdOut,
          language: "stdout",
        ),
      ),
    );
  }

  void onStderr(String event) {
    setState(() {
      stdError += event;
    });
  }

  void onStdout(String event) {
    setState(() {
      stdOut += event;
    });
  }
}
