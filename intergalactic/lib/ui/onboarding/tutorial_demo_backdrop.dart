import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/activity/activity_service.dart';
import 'package:intergalactic/client/components/activity/activity_settings.dart';
import 'package:intergalactic/client/components/activity/sources/mock_activity_source.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_component.dart';
import 'package:intergalactic/client/components/gif/gif_component.dart';
import 'package:intergalactic/client/components/gif/gif_search_result.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_component.dart';
import 'package:intergalactic/client/components/voip_room/voip_room_component.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/demo/demo_client.dart';
import 'package:intergalactic/config/custom_theme_definition.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/main.dart' as app_globals;
import 'package:intergalactic/ui/molecules/emoticon_picker.dart';
import 'package:intergalactic/ui/molecules/message_input.dart';
import 'package:intergalactic/ui/onboarding/tutorial_anchor.dart';
import 'package:intergalactic/ui/onboarding/tutorial_focus_overlay.dart';
import 'package:intergalactic/ui/onboarding/tutorial_scene.dart';
import 'package:intergalactic/ui/organisms/account_popup/account_popup.dart';
import 'package:intergalactic/ui/organisms/particle_player/particle_player.dart';
import 'package:intergalactic/ui/organisms/particle_player/particle_system_snow.dart';
import 'package:intergalactic/ui/organisms/soundboard/call_soundboard_panel.dart';
import 'package:intergalactic/ui/pages/main/main_page.dart';
import 'package:intergalactic/ui/pages/settings/app_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/settings_category_account.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/settings_category_app.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/theme_settings/custom_theme_editor.dart';
import 'package:intergalactic/ui/pages/settings/categories/help/help_faq_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/help/settings_category_help.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/settings_category_room.dart';
import 'package:intergalactic/ui/pages/settings/categories/space/settings_category_space.dart';
import 'package:intergalactic/ui/pages/settings/room_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/space_settings_page.dart';
import 'package:intergalactic/ui/windows/notification_companion/notification_companion_preview_widgets.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:provider/provider.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class TutorialDemoBackdrop extends StatefulWidget {
  const TutorialDemoBackdrop({required this.scene, super.key});

  final TutorialSceneSpec scene;

  @override
  State<TutorialDemoBackdrop> createState() => _TutorialDemoBackdropState();
}

class _TutorialDemoBackdropState extends State<TutorialDemoBackdrop> {
  late final ClientManager _clientManager;
  late final ActivityService _activityService;
  final TutorialAnchorRegistry _anchorRegistry = TutorialAnchorRegistry();
  bool _ready = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _clientManager = ClientManager();
    _activityService = ActivityService(
      settingsProvider: () => const ActivitySettings(
        showLocally: true,
        showSpotify: true,
        showGameActivity: true,
      ),
    );
    _seedDemoActivity();
    unawaited(app_globals.dmLockController.init(app_globals.preferences));
    unawaited(_loadDemoClient());
  }

  void _seedDemoActivity() {
    _activityService.registerSource(
      MockActivitySource.music(enabled: () => true),
    );
    unawaited(_activityService.start());
  }

  Future<void> _loadDemoClient() async {
    final demoClient = DemoClient.createOfflineDemo();

    try {
      await demoClient.init(false);
      await _startDemoVoiceRoom(demoClient);

      if (!mounted) {
        await demoClient.close();
        return;
      }

      _clientManager.addClient(demoClient);

      if (mounted) {
        setState(() {
          _ready = true;
        });
      }
    } catch (error) {
      await demoClient.close();

      if (mounted) {
        setState(() {
          _error = error;
        });
      }
    }
  }

  Future<void> _startDemoVoiceRoom(DemoClient demoClient) async {
    final room = demoClient.getRoom(DemoClient.demoVoiceRoomId);
    final voip = room?.getComponent<VoipRoomComponent>();
    final session = await voip?.joinCall();
    if (session == null) {
      return;
    }

    if (!_clientManager.callManager.currentSessions.contains(session)) {
      _clientManager.callManager.currentSessions.add(session);
    }
  }

  @override
  void dispose() {
    unawaited(_activityService.dispose());
    unawaited(_clientManager.close());
    _anchorRegistry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: IgnorePointer(child: _buildContent(context)),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_error != null) {
      return _DemoBackdropStatus(
        icon: Icons.warning_amber_rounded,
        title: "Demo preview unavailable",
        body:
            "The tutorial can still run, but the offline demo backdrop could not load.",
      );
    }

    if (!_ready) {
      return const _DemoBackdropStatus(
        icon: Icons.school_outlined,
        title: "Preparing demo preview",
        body: "Loading local demo rooms and messages.",
      );
    }

    return Provider<ClientManager>.value(
      value: _clientManager,
      child: TutorialAnchorScope(
        registry: _anchorRegistry,
        child: LayoutBuilder(
          builder: (context, constraints) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) {
                return;
              }

              _anchorRegistry.updateViewport(constraints.biggest);
            });

            return Stack(
              fit: StackFit.expand,
              children: [
                _buildMainPageBackdrop(),
                if (widget.scene.settingsSurface != null)
                  TutorialAnchor(
                    id: TutorialAnchorIds.settingsSurface,
                    padding: const EdgeInsets.all(4),
                    child: _TutorialSettingsOverlay(
                      surface: widget.scene.settingsSurface!,
                      clientManager: _clientManager,
                    ),
                  ),
                if (widget.scene.overlay != null)
                  _TutorialSceneOverlay(
                    overlay: widget.scene.overlay!,
                    clientManager: _clientManager,
                    activityService: _activityService,
                  ),
                if (widget.scene.focus != null)
                  TutorialFocusOverlay(focus: widget.scene.focus!),
              ],
            );
          },
        ),
      ),
    );
  }

  bool get _forceRoomDecryptQuickAction =>
      widget.scene.focus?.anchorId == TutorialAnchorIds.encryptedRoomPadlock;

  bool get _forceCallControlsVisible =>
      widget.scene.focus?.anchorId == TutorialAnchorIds.callView ||
      widget.scene.focus?.anchorId == TutorialAnchorIds.callPopoutButton ||
      widget.scene.overlay == TutorialDemoOverlay.callMemberControls ||
      widget.scene.overlay == TutorialDemoOverlay.callPopout;

  bool get _forceActivityPanelVisible =>
      widget.scene.focus?.anchorId == TutorialAnchorIds.activityCard ||
      widget.scene.overlay == TutorialDemoOverlay.activityCard;

  bool get _forceCallPanelVisible =>
      widget.scene.roomId == DemoClient.demoVoiceRoomId ||
      widget.scene.overlay == TutorialDemoOverlay.soundboardPopup ||
      _forceCallControlsVisible;

  Widget _buildMainPageBackdrop() {
    return MainPage(
      _clientManager,
      key: ValueKey(
        'tutorial-demo-${widget.scene.initialSpaceId}-${widget.scene.roomId}-${widget.scene.sidePanel}-${widget.scene.sidePanelThreadId}-${widget.scene.settingsSurface}',
      ),
      initialClientId: DemoClient.demoIdentifier,
      initialSpaceId: widget.scene.initialSpaceId,
      initialRoom: widget.scene.roomId,
      initialSidePanelState: _sidePanelStateName(widget.scene.sidePanel),
      initialSidePanelThreadId: widget.scene.sidePanelThreadId,
      forceRoomSidePanelVisible: widget.scene.sidePanel != null,
      forceRoomDecryptQuickAction: _forceRoomDecryptQuickAction,
      forceCallControlsVisible: _forceCallControlsVisible,
      forceCallPanelVisible: _forceCallPanelVisible,
      forceActivityPanelVisible: _forceActivityPanelVisible,
      tutorialActivityService: _activityService,
    );
  }

  String? _sidePanelStateName(TutorialDemoSidePanel? sidePanel) {
    return switch (sidePanel) {
      TutorialDemoSidePanel.defaultView => 'defaultView',
      TutorialDemoSidePanel.thread => 'thread',
      null => null,
    };
  }
}

class _TutorialSettingsOverlay extends StatelessWidget {
  const _TutorialSettingsOverlay({
    required this.surface,
    required this.clientManager,
  });

  final TutorialDemoSettingsSurface surface;
  final ClientManager clientManager;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = Layout.mobile ? 12.0 : 28.0;
        final maxWidth = math.max(260.0, constraints.maxWidth - inset * 2);
        final maxHeight = math.max(360.0, constraints.maxHeight - inset * 2);
        final width = Layout.mobile
            ? maxWidth
            : math.min(maxWidth, math.max(760.0, constraints.maxWidth * 0.74));
        final height = Layout.mobile
            ? math.min(maxHeight, constraints.maxHeight * 0.76)
            : math.min(maxHeight, constraints.maxHeight * 0.88);

        return Align(
          alignment: Layout.mobile
              ? Alignment.bottomCenter
              : Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.all(inset),
            child: SizedBox(
              width: width,
              height: height,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(Layout.mobile ? 28 : 20),
                  border: Border.all(
                    color: scheme.outline.withValues(alpha: 0.42),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.scrim.withValues(alpha: 0.34),
                      blurRadius: 34,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Layout.mobile ? 27 : 19),
                  child: _settingsBody(context),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _settingsBody(BuildContext context) {
    final demoClient =
        clientManager.getClient(DemoClient.demoIdentifier) as DemoClient?;
    final demoSpace = demoClient?.getSpace(DemoClient.demoSpaceId);

    final roomSurface =
        surface == TutorialDemoSettingsSurface.roomEmoticons ||
        surface == TutorialDemoSettingsSurface.roomAppearance;
    final spaceSurface = surface == TutorialDemoSettingsSurface.spaceSoundboard;

    if (roomSurface) {
      final room = demoClient?.getRoom(DemoClient.demoLoungeRoomId);
      if (room != null) {
        return RoomSettingsPage(
          room: room,
          contextSpace: demoSpace,
          initialTabId: _settingsInitialTabId(surface),
        );
      }
    }

    if (spaceSurface && demoSpace != null) {
      return SpaceSettingsPage(
        space: demoSpace,
        initialTabId: _settingsInitialTabId(surface),
      );
    }

    if (surface == TutorialDemoSettingsSurface.themeEditor) {
      final draft = CustomThemeDraft.fromThemeData(
        name: 'Demo Theme',
        base: 'dark',
        theme: defaultThemeForCustomBase('dark'),
      );

      return Padding(
        padding: const EdgeInsets.all(16),
        child: CustomThemeEditorPage(initialDraft: draft),
      );
    }

    return AppSettingsPage(
      initialTabId: _settingsInitialTabId(surface),
      includeTutorialPreviewTabs: true,
    );
  }

  String? _settingsInitialTabId(TutorialDemoSettingsSurface surface) {
    return switch (surface) {
      TutorialDemoSettingsSurface.appAppearance =>
        SettingsCategoryApp.tabIdAppearance,
      TutorialDemoSettingsSurface.appActivity =>
        SettingsCategoryApp.tabIdActivity,
      TutorialDemoSettingsSurface.appVoiceAndVideo =>
        SettingsCategoryApp.tabIdVoiceAndVideo,
      TutorialDemoSettingsSurface.appSoundboard =>
        SettingsCategoryApp.tabIdSoundboard,
      TutorialDemoSettingsSurface.appNotifications =>
        SettingsCategoryApp.tabIdNotifications,
      TutorialDemoSettingsSurface.appDesktopCompanion =>
        SettingsCategoryApp.tabIdDesktopCompanion,
      TutorialDemoSettingsSurface.appEmoticons =>
        SettingsCategoryApp.tabIdEmoticons,
      TutorialDemoSettingsSurface.accountSecurity =>
        SettingsCategoryAccount.accountSecurityTabId,
      TutorialDemoSettingsSurface.helpSafety =>
        SettingsCategoryHelp.tabIdSafety,
      TutorialDemoSettingsSurface.helpReportBug =>
        SettingsCategoryHelp.tabIdReportBug,
      TutorialDemoSettingsSurface.helpFaq => SettingsCategoryHelp.tabIdFaq,
      TutorialDemoSettingsSurface.helpTutorial =>
        SettingsCategoryHelp.tabIdTutorial,
      TutorialDemoSettingsSurface.roomEmoticons =>
        SettingsCategoryRoom.tabIdEmoticons,
      TutorialDemoSettingsSurface.roomAppearance =>
        SettingsCategoryRoom.tabIdAppearance,
      TutorialDemoSettingsSurface.spaceSoundboard =>
        SettingsCategorySpace.tabIdSoundboard,
      TutorialDemoSettingsSurface.themeEditor => null,
    };
  }
}

class _TutorialSceneOverlay extends StatelessWidget {
  const _TutorialSceneOverlay({
    required this.overlay,
    required this.clientManager,
    required this.activityService,
  });

  final TutorialDemoOverlay overlay;
  final ClientManager clientManager;
  final ActivityService activityService;

  @override
  Widget build(BuildContext context) {
    return switch (overlay) {
      TutorialDemoOverlay.spaceRail ||
      TutorialDemoOverlay.roomList ||
      TutorialDemoOverlay.photoThreadPanel ||
      TutorialDemoOverlay.composer ||
      TutorialDemoOverlay.membersNicknames => const SizedBox.shrink(),
      TutorialDemoOverlay.emoticonHeart => const SizedBox.shrink(),
      TutorialDemoOverlay.tutorialReplay => const SizedBox.shrink(),
      TutorialDemoOverlay.securityVerify ||
      TutorialDemoOverlay.securityDecryption ||
      TutorialDemoOverlay.securitySessions => const SizedBox.shrink(),
      TutorialDemoOverlay.emoticonPacks => const SizedBox.shrink(),
      TutorialDemoOverlay.mediaMenuCycle => _ComposerMediaMenuCycleOverlay(
        clientManager: clientManager,
      ),
      TutorialDemoOverlay.effectsMenu => const _ComposerEffectsMenuOverlay(),
      TutorialDemoOverlay.snowEffect => const _TimelineSnowEffectOverlay(),
      TutorialDemoOverlay.callMemberControls => const SizedBox.shrink(),
      TutorialDemoOverlay.callPopout => const SizedBox.shrink(),
      TutorialDemoOverlay.soundboardPopup => _SoundboardMenuOverlay(
        clientManager: clientManager,
      ),
      TutorialDemoOverlay.companionAnimation => const _DesktopCompanionPreview(
        active: false,
        title: '',
        count: '0',
      ),
      TutorialDemoOverlay.companionActiveNotification =>
        const _DesktopCompanionPreview(
          active: true,
          title:
              'Mira: Hey, how are you doing today? Want to go grab some lunch later?',
          count: '1',
        ),
      TutorialDemoOverlay.companionNeutral => const _DesktopCompanionPreview(
        active: false,
        title: '',
        count: '0',
      ),
      TutorialDemoOverlay.activityCard => const SizedBox.shrink(),
      TutorialDemoOverlay.accountPopup => _AccountPopupOverlay(
        clientManager: clientManager,
        activityService: activityService,
      ),
      TutorialDemoOverlay.encryptionPadlock => const SizedBox.shrink(),
      TutorialDemoOverlay.faqAnswer => const _FaqAnswerOverlay(),
    };
  }
}

enum _TutorialPopupAnchorEdge { left, center, right }

class _TutorialAnchoredPopup extends StatelessWidget {
  const _TutorialAnchoredPopup({
    required this.anchorId,
    required this.width,
    required this.child,
    this.fallbackAnchorIds = const [],
    this.anchorEdge = _TutorialPopupAnchorEdge.left,
    this.fallbackAlignment = Alignment.bottomLeft,
    this.fallbackPadding = EdgeInsets.zero,
  });

  final String anchorId;
  final List<String> fallbackAnchorIds;
  final double width;
  final Widget child;
  final _TutorialPopupAnchorEdge anchorEdge;
  final Alignment fallbackAlignment;
  final EdgeInsets fallbackPadding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rect = _rectFor(context);

        if (rect == null) {
          return Align(
            alignment: fallbackAlignment,
            child: Padding(padding: fallbackPadding, child: child),
          );
        }

        final maxLeft = math.max(8.0, constraints.maxWidth - width - 8);
        final rawLeft = switch (anchorEdge) {
          _TutorialPopupAnchorEdge.left => rect.left,
          _TutorialPopupAnchorEdge.center => rect.center.dx - (width / 2),
          _TutorialPopupAnchorEdge.right => rect.right - width,
        };
        final left = rawLeft.clamp(8.0, maxLeft).toDouble();
        final bottom = (constraints.maxHeight - rect.top + 8)
            .clamp(8.0, math.max(8.0, constraints.maxHeight - 64))
            .toDouble();

        return Stack(
          fit: StackFit.expand,
          children: [Positioned(left: left, bottom: bottom, child: child)],
        );
      },
    );
  }

  Rect? _rectFor(BuildContext context) {
    final registry = TutorialAnchorScope.maybeOf(context);
    final primary = registry?.rectFor(anchorId);
    if (primary != null) {
      return primary;
    }

    for (final fallbackId in fallbackAnchorIds) {
      final fallback = registry?.rectFor(fallbackId);
      if (fallback != null) {
        return fallback;
      }
    }

    return null;
  }
}

class _FloatingDemoMenu extends StatelessWidget {
  const _FloatingDemoMenu({
    required this.alignment,
    required this.title,
    required this.rows,
    this.margin = EdgeInsets.zero,
  });

  final Alignment alignment;
  final String title;
  final List<(String, String)> rows;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: alignment,
      child: Padding(
        padding: margin + const EdgeInsets.all(18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.46)),
            boxShadow: [
              BoxShadow(
                color: scheme.scrim.withValues(alpha: 0.34),
                blurRadius: 26,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: SizedBox(
              width: 250,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  tiamat.Text.labelEmphasised(title),
                  const SizedBox(height: 10),
                  ...rows.map(
                    (row) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainer,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.38,
                                ),
                              ),
                            ),
                            child: SizedBox(
                              width: 34,
                              height: 34,
                              child: Center(child: Text(row.$1)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: tiamat.Text.label(row.$2)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _ComposerDemoPanelMode { attachments, emoticons }

class _ComposerMediaMenuCycleOverlay extends StatefulWidget {
  const _ComposerMediaMenuCycleOverlay({required this.clientManager});

  final ClientManager clientManager;

  @override
  State<_ComposerMediaMenuCycleOverlay> createState() =>
      _ComposerMediaMenuCycleOverlayState();
}

class _ComposerMediaMenuCycleOverlayState
    extends State<_ComposerMediaMenuCycleOverlay> {
  static const _modes = [
    _ComposerDemoPanelMode.attachments,
    _ComposerDemoPanelMode.emoticons,
  ];

  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      setState(() {
        _index = (_index + 1) % _modes.length;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mode = _modes[_index];
    final isPicker = mode == _ComposerDemoPanelMode.emoticons;
    final panel = TutorialAnchor(
      id: TutorialAnchorIds.composerPopup,
      padding: const EdgeInsets.all(4),
      child: _buildPanel(context, mode),
    );

    if (isPicker) {
      return _TutorialAnchoredPopup(
        anchorId: TutorialAnchorIds.composerEmojiButton,
        fallbackAnchorIds: const [TutorialAnchorIds.composer],
        width: 420,
        anchorEdge: _TutorialPopupAnchorEdge.right,
        fallbackAlignment: Alignment.bottomRight,
        fallbackPadding: const EdgeInsets.fromLTRB(0, 0, 22, 88),
        child: panel,
      );
    }

    return _TutorialAnchoredPopup(
      anchorId: TutorialAnchorIds.composerPlusButton,
      fallbackAnchorIds: const [TutorialAnchorIds.composer],
      width: 244,
      anchorEdge: _TutorialPopupAnchorEdge.left,
      fallbackAlignment: Alignment.bottomLeft,
      fallbackPadding: const EdgeInsets.fromLTRB(22, 0, 0, 88),
      child: panel,
    );
  }

  Widget _buildPanel(BuildContext context, _ComposerDemoPanelMode mode) {
    return KeyedSubtree(
      key: ValueKey(mode),
      child: switch (mode) {
        _ComposerDemoPanelMode.attachments => ComposerPopupCard(
          preferredWidth: 244,
          maxHeight: 260,
          child: ComposerAttachmentMenuContent(
            pickers: [
              AttachmentPicker(
                icon: Icons.photo_camera_outlined,
                label: 'Take a photo',
                execute: () {},
              ),
              AttachmentPicker(
                icon: Icons.photo_library_outlined,
                label: 'Gallery',
                execute: () {},
              ),
              AttachmentPicker(
                icon: Icons.attach_file_outlined,
                label: 'File',
                execute: () {},
              ),
              AttachmentPicker(
                icon: Icons.poll_outlined,
                label: 'Poll',
                execute: () {},
              ),
            ],
            onPickerSelected: (_) {},
          ),
        ),
        _ComposerDemoPanelMode.emoticons => _ComposerUnifiedPickerPanel(
          clientManager: widget.clientManager,
        ),
      },
    );
  }
}

class _ComposerUnifiedPickerPanel extends StatelessWidget {
  const _ComposerUnifiedPickerPanel({required this.clientManager});

  final ClientManager clientManager;

  @override
  Widget build(BuildContext context) {
    final client =
        clientManager.getClient(DemoClient.demoIdentifier) as DemoClient?;
    final room = client?.getRoom(DemoClient.demoLoungeRoomId);
    final packs =
        room?.getComponent<RoomEmoticonComponent>()?.availablePacks ?? const [];
    final gifComponent = client != null && room is DemoRoom
        ? _DemoTutorialGifComponent(client, room)
        : null;

    return ComposerPopupCard(
      preferredWidth: 420,
      maxHeight: 340,
      child: EmoticonPicker(
        emoji: packs,
        stickers: packs,
        allowGifSearch: gifComponent != null,
        gifComponent: gifComponent,
        onGifPressed: (_) async {},
        onStickerPressed: (_) {},
        onEmojiPressed: (_) {},
        onCreatePressed: () {},
        packListAxis: Axis.vertical,
      ),
    );
  }
}

class _DemoTutorialGifComponent implements GifComponent<DemoClient, DemoRoom> {
  _DemoTutorialGifComponent(this.client, this.room);

  @override
  DemoClient client;

  @override
  DemoRoom room;

  @override
  String get searchPlaceholder => 'Search GIFs';

  @override
  Future<List<GifSearchResult>> search(String query) async => const [];

  @override
  Future<TimelineEvent?> sendGif(
    GifSearchResult gif,
    TimelineEvent? inReplyTo, {
    String? threadRootEventId,
    String? threadLastEventId,
  }) async {
    return null;
  }
}

class _ComposerEffectsMenuOverlay extends StatelessWidget {
  const _ComposerEffectsMenuOverlay();

  @override
  Widget build(BuildContext context) {
    return _TutorialAnchoredPopup(
      anchorId: TutorialAnchorIds.composerEffectsButton,
      fallbackAnchorIds: const [
        TutorialAnchorIds.composerEmojiButton,
        TutorialAnchorIds.composer,
      ],
      width: 276,
      anchorEdge: _TutorialPopupAnchorEdge.right,
      fallbackAlignment: Alignment.bottomRight,
      fallbackPadding: const EdgeInsets.fromLTRB(0, 0, 230, 88),
      child: TutorialAnchor(
        id: TutorialAnchorIds.effectsMenu,
        padding: const EdgeInsets.all(4),
        child: ComposerPopupCard(
          preferredWidth: 276,
          maxHeight: 244,
          child: ComposerEffectsMenuContent(onSelected: (_) {}),
        ),
      ),
    );
  }
}

class _SoundboardMenuOverlay extends StatelessWidget {
  const _SoundboardMenuOverlay({required this.clientManager});

  final ClientManager clientManager;

  @override
  Widget build(BuildContext context) {
    final client =
        clientManager.getClient(DemoClient.demoIdentifier) as DemoClient?;
    final space = client?.getSpace(DemoClient.demoSpaceId);
    final soundboard = space?.getComponent<SoundboardComponent>();

    if (soundboard == null) {
      return const SizedBox.shrink();
    }

    return _TutorialAnchoredPopup(
      anchorId: TutorialAnchorIds.callSoundboardButton,
      fallbackAnchorIds: const [
        TutorialAnchorIds.callPanel,
        TutorialAnchorIds.accountPanel,
      ],
      width: 560,
      anchorEdge: _TutorialPopupAnchorEdge.left,
      fallbackAlignment: Alignment.bottomLeft,
      fallbackPadding: const EdgeInsets.fromLTRB(74, 0, 0, 96),
      child: TutorialAnchor(
        id: TutorialAnchorIds.soundboardPopup,
        padding: const EdgeInsets.all(6),
        child: ComposerPopupCard(
          preferredWidth: 560,
          maxHeight: 430,
          child: CallSoundboardMenu(
            soundboard: soundboard,
            compact: true,
            onSoundPressed: (_, _) {},
            onAddSoundPressed: () {},
          ),
        ),
      ),
    );
  }
}

class _TimelineSnowEffectOverlay extends StatefulWidget {
  const _TimelineSnowEffectOverlay();

  @override
  State<_TimelineSnowEffectOverlay> createState() =>
      _TimelineSnowEffectOverlayState();
}

class _TimelineSnowEffectOverlayState
    extends State<_TimelineSnowEffectOverlay> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  Future<void> _play() async {
    final effect = MessageEffectSnow();
    await effect.init();
    if (!mounted) return;
    EventBus.doMessageEffect.add(effect);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          left: Layout.mobile ? 0 : 340,
          right: Layout.mobile ? 0 : 18,
          top: 70,
          bottom: 86,
          child: TutorialAnchor(
            id: TutorialAnchorIds.timeline,
            padding: const EdgeInsets.all(4),
            child: ClipRect(child: ParticlePlayer()),
          ),
        ),
        const _FloatingDemoMenu(
          alignment: Alignment.bottomRight,
          margin: EdgeInsets.fromLTRB(0, 0, 230, 88),
          title: 'Snowfall sent',
          rows: [
            ('❄', 'Effect playing in the timeline'),
            ('💬', 'Message delivered'),
          ],
        ),
      ],
    );
  }
}

class _DesktopCompanionPreview extends StatelessWidget {
  const _DesktopCompanionPreview({
    required this.active,
    required this.title,
    required this.count,
  });

  final bool active;
  final String title;
  final String count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: TutorialAnchor(
        id: TutorialAnchorIds.companionPreview,
        padding: const EdgeInsets.all(10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.52)),
            boxShadow: [
              BoxShadow(
                color: scheme.scrim.withValues(alpha: 0.32),
                blurRadius: 30,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: SizedBox(
            width: Layout.mobile ? 300 : 420,
            height: Layout.mobile ? 300 : 360,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Positioned(
                  left: 18,
                  top: active ? 124 : 136,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainer,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.42),
                      ),
                    ),
                    child: SizedBox(
                      width: Layout.mobile ? 42 : 54,
                      height: Layout.mobile ? 42 : 54,
                      child: Icon(
                        Icons.keyboard_arrow_up_rounded,
                        size: Layout.mobile ? 26 : 34,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: active ? 78 : 68,
                  child: NotificationCompanionAvatarPreview(
                    notificationCount: int.tryParse(count) ?? 0,
                    size: Layout.mobile ? 188 : 236,
                  ),
                ),
                if (active)
                  Positioned(
                    top: 24,
                    left: 52,
                    right: 52,
                    child: NotificationCompanionBubblePreview(
                      roomName: 'lounge',
                      senderName: 'Mira',
                      body: title.replaceFirst('Mira: ', ''),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountPopupOverlay extends StatelessWidget {
  const _AccountPopupOverlay({
    required this.clientManager,
    required this.activityService,
  });

  final ClientManager clientManager;
  final ActivityService activityService;

  @override
  Widget build(BuildContext context) {
    final client = clientManager.getClient(DemoClient.demoIdentifier);
    if (client == null) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 0, 74),
        child: TutorialAnchor(
          id: TutorialAnchorIds.accountPopup,
          padding: const EdgeInsets.all(6),
          child: AccountPopup(
            width: 360,
            client: client,
            clientManager: clientManager,
            activityService: activityService,
            navigationContext: context,
            onDismiss: () {},
          ),
        ),
      ),
    );
  }
}

class _FaqAnswerOverlay extends StatelessWidget {
  const _FaqAnswerOverlay();

  @override
  Widget build(BuildContext context) {
    final entry = faqEntries.firstWhere(
      (entry) => entry.question.toLowerCase().contains('encrypted'),
      orElse: () => faqEntries.first,
    );

    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(right: 70),
        child: TutorialAnchor(
          id: TutorialAnchorIds.faqAnswer,
          padding: const EdgeInsets.all(6),
          child: SizedBox(
            width: 440,
            height: 300,
            child: FaqAnswerCard(entry: entry, showCloseButton: false),
          ),
        ),
      ),
    );
  }
}

class _DemoBackdropStatus extends StatelessWidget {
  const _DemoBackdropStatus({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return tiamat.Foundation(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: tiamat.Tile.surfaceContainer(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 36,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 14),
                  tiamat.Text.largeTitle(title),
                  const SizedBox(height: 8),
                  Center(child: tiamat.Text.body(body, softwrap: true)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
