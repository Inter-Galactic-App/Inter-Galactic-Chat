import 'dart:async';
import 'package:collection/collection.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/activity/activity_service.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/components/invitation/invitation_component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/stories/story_component.dart';
import 'package:intergalactic/client/components/voip/voip_component.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip_room/voip_room_component.dart';
import 'package:intergalactic/client/demo/demo_client.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_backend.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/navigation/desktop_navigation_history.dart';
import 'package:intergalactic/ui/navigation/quick_switcher.dart';
import 'package:intergalactic/ui/molecules/dm_pin_dialog.dart';
import 'package:intergalactic/ui/onboarding/onboarding_page.dart';
import 'package:intergalactic/ui/onboarding/onboarding_service.dart';
import 'package:intergalactic/ui/organisms/invitation_view/send_invitation.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_viewer.dart';
import 'package:intergalactic/ui/organisms/user_profile/user_profile.dart';
import 'package:intergalactic/ui/pages/get_or_create_room/get_or_create_room.dart';
import 'package:intergalactic/ui/pages/setup/setup_page.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:intergalactic/ui/navigation/navigation_utils.dart';
import 'package:intergalactic/ui/pages/main/main_page_view_desktop.dart';
import 'package:intergalactic/ui/pages/main/main_page_view_mobile.dart';
import 'package:intergalactic/ui/pages/settings/room_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/settings_navigation.dart';
import 'package:intergalactic/utils/first_time_setup.dart';
import 'package:intergalactic/utils/image/lod_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class MainPage extends StatefulWidget {
  const MainPage(
    this.clientManager, {
    super.key,
    this.initialClientId,
    this.initialSpaceId,
    this.initialRoom,
    this.initialSidePanelState,
    this.initialSidePanelThreadId,
    this.forceRoomSidePanelVisible = false,
    this.forceRoomDecryptQuickAction = false,
    this.forceCallControlsVisible = false,
    this.forceCallPanelVisible = false,
    this.forceActivityPanelVisible = false,
    this.tutorialActivityService,
  });
  final ClientManager clientManager;
  final String? initialRoom;
  final String? initialSpaceId;
  final String? initialClientId;
  final String? initialSidePanelState;
  final String? initialSidePanelThreadId;
  final bool forceRoomSidePanelVisible;
  final bool forceRoomDecryptQuickAction;
  final bool forceCallControlsVisible;
  final bool forceCallPanelVisible;
  final bool forceActivityPanelVisible;
  final ActivityService? tutorialActivityService;

  @override
  State<MainPage> createState() => MainPageState();
}

enum MainPageSubView { space, home, favorites }

enum CallRoomSideRailMode { members, chat }

@visibleForTesting
bool debugShouldAutoOpenCallRoomChatForTesting({
  required int displayNotificationCount,
  required int displayHighlightedNotificationCount,
  required bool displayRoomWideMentionNotification,
  required bool alreadyAutoOpenedForRoom,
}) {
  if (alreadyAutoOpenedForRoom) {
    return false;
  }

  return displayNotificationCount > 0 ||
      displayHighlightedNotificationCount > 0 ||
      displayRoomWideMentionNotification;
}

class MainPageState extends State<MainPage> {
  static const int _notificationOpenRoomRetryLimit = 24;
  static const Duration _notificationOpenRoomRetryDelay = Duration(
    milliseconds: 500,
  );

  Space? _currentSpace;
  Room? _currentRoom;
  bool showAsTextRoom = false;
  Client? filterClient;
  CallRoomSideRailMode _callRoomSideRailMode = CallRoomSideRailMode.members;
  String? _callRoomSideRailRoomKey;
  bool _callRoomSideRailForcedOpen = false;
  final Set<String> _callRoomChatAutoOpenedRoomKeys = {};

  MainPageSubView _currentView = MainPageSubView.home;

  StreamSubscription? onSpaceUpdateSubscription;
  StreamSubscription? onRoomUpdateSubscription;
  StreamSubscription? onCallStartedSubscription;
  StreamSubscription? onClientRemovedSubscription;
  StreamSubscription? onClientAddedSubscription;
  StreamSubscription? onClientUpdatedSubscription;
  StreamSubscription? onDmLockChangedSubscription;
  StreamSubscription? onDesktopSmallWindowModeChangedSubscription;
  StreamSubscription<DesktopNavigationEntry>? onDesktopNavigationSubscription;
  StreamSubscription? onOpenRoomSubscription;
  StreamSubscription? onOpenStorySubscription;
  StreamSubscription? onOpenSpaceSubscription;
  bool _postLoginFlowStarted = false;
  final Map<String, int> _notificationOpenRoomRetryCounts = {};
  final Map<String, Timer> _notificationOpenRoomRetryTimers = {};

  MainPageSubView get currentView => _currentView;
  CallRoomSideRailMode get callRoomSideRailMode => _callRoomSideRailMode;

  ClientManager get clientManager => widget.clientManager;

  Profile? get currentUser => getCurrentUser();
  Space? get currentSpace => _currentSpace;
  Room? get currentRoom => _currentRoom;

  VoipSession? get currentCall => currentRoom == null
      ? null
      : widget.clientManager.callManager.getCallInRoom(
          currentRoom!.client,
          currentRoom!.identifier,
        );
  bool get isCurrentRoomCallRoom =>
      currentRoom?.getComponent<VoipRoomComponent>() != null;
  bool get forceCallRoomSideRailVisible =>
      isCurrentRoomCallRoom && _callRoomSideRailForcedOpen;
  String? get initialSidePanelState => widget.initialSidePanelState;
  String? get initialSidePanelThreadId => widget.initialSidePanelThreadId;
  bool get forceRoomSidePanelVisible => widget.forceRoomSidePanelVisible;
  bool get forceRoomDecryptQuickAction => widget.forceRoomDecryptQuickAction;
  bool get forceCallControlsVisible => widget.forceCallControlsVisible;
  bool get forceCallPanelVisible => widget.forceCallPanelVisible;
  bool get forceActivityPanelVisible => widget.forceActivityPanelVisible;
  ActivityService? get tutorialActivityService =>
      widget.tutorialActivityService;

  @override
  void initState() {
    super.initState();

    Client? client;
    var hasExplicitStartupTarget = false;

    if (widget.initialClientId != null) {
      client = clientManager.getClient(widget.initialClientId!);
      hasExplicitStartupTarget = client != null;
    }

    if (widget.initialSpaceId != null) {
      final initialSpace = clientManager.spaces
          .where((space) => space.identifier == widget.initialSpaceId)
          .firstOrNull;

      if (initialSpace != null) {
        if (!initialSpace.fullyLoaded) initialSpace.loadExtra();

        _currentSpace = initialSpace;
        _currentView = MainPageSubView.space;
        client = initialSpace.client;
        hasExplicitStartupTarget = true;
      }
    }

    if (client == null && widget.initialRoom != null) {
      client = clientManager.clients
          .where((element) => element.getRoom(widget.initialRoom!) != null)
          .firstOrNull;
    }

    if (client != null && widget.initialRoom != null) {
      var room = client.getRoom(widget.initialRoom!);

      if (room != null) {
        setFilterClient(room.client);
        selectRoom(room);
        hasExplicitStartupTarget = true;
      }
    }

    if (!hasExplicitStartupTarget) {
      _restorePersistedFilterClient();
    } else if (client != null) {
      setFilterClient(client);
    }

    ServicesBinding.instance.keyboard.addHandler(_onKeyPressed);

    // backgroundTaskManager.onListUpdate.listen((event) {
    //   setState(() {});
    // });

    onCallStartedSubscription = clientManager
        .callManager
        .currentSessions
        .onListUpdated
        .listen((event) {
          setState(() {});
        });

    onOpenRoomSubscription = EventBus.openRoom.stream.listen(onOpenRoomSignal);
    while (true) {
      final pendingOpenRoom = EventBus.takePendingOpenRoom();
      if (pendingOpenRoom == null) {
        break;
      }
      EventBus.openRoom.add(pendingOpenRoom);
    }

    onOpenStorySubscription = EventBus.openStory.stream.listen(
      onOpenStorySignal,
    );
    while (true) {
      final pendingOpenStory = EventBus.takePendingOpenStory();
      if (pendingOpenStory == null) {
        break;
      }
      EventBus.openStory.add(pendingOpenStory);
    }

    onOpenSpaceSubscription = EventBus.openSpace.stream.listen(
      onOpenSpaceSignal,
    );
    while (true) {
      final pendingOpenSpace = EventBus.takePendingOpenSpace();
      if (pendingOpenSpace == null) {
        break;
      }
      EventBus.openSpace.add(pendingOpenSpace);
    }

    EventBus.setFilterClient.stream.listen(setFilterClient);

    EventBus.openUserProfile.stream.listen(onOpenUserProfileSignal);

    onDesktopNavigationSubscription = DesktopNavigationHistoryController
        .instance
        .requests
        .listen(onDesktopNavigationRequest);

    onClientRemovedSubscription = clientManager.onClientRemoved.stream.listen(
      onClientRemoved,
    );

    onClientAddedSubscription = clientManager.onClientAdded.stream.listen((_) {
      if (!mounted) return;

      final restoredFilterClient = _restorePersistedFilterClient();
      if (restoredFilterClient != null) {
        EventBus.setFilterClient.add(restoredFilterClient);
      }

      setState(() {});
    });

    onClientUpdatedSubscription = clientManager.onClientUpdated.stream.listen((
      _,
    ) {
      if (!mounted) {
        return;
      }

      setState(() {});
    });

    onDmLockChangedSubscription = dmLockController.onChanged.listen((_) {
      if (!mounted) {
        return;
      }

      if (_currentRoom != null &&
          dmLockController.shouldMaskRoomPreview(_currentRoom!)) {
        clearRoomSelection();
        return;
      }

      setState(() {});
    });

    onDesktopSmallWindowModeChangedSubscription = preferences
        .desktopSmallWindowMode
        .onChanged
        .listen((_) {
          if (mounted) {
            setState(() {});
          }
        });

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _recordCurrentDesktopNavigationEntry();
      }
    });
    SchedulerBinding.instance.scheduleFrameCallback(onFirstFrame);
  }

  void onFirstFrame(Duration timeStamp) {
    unawaited(_runPostLoginFlow());
  }

  Future<void> _runPostLoginFlow() async {
    if (_postLoginFlowStarted || !mounted) {
      return;
    }

    if (!widget.clientManager.isLoggedIn()) {
      return;
    }

    final onlyDemoClients =
        widget.clientManager.clients.isNotEmpty &&
        widget.clientManager.clients.every((client) => client is DemoClient);
    if (onlyDemoClients) {
      return;
    }

    _postLoginFlowStarted = true;
    try {
      final onboardingService = OnboardingService(preferences);
      if (!Layout.mobile && onboardingService.shouldShow(isLoggedIn: true)) {
        await OnboardingPage.show(context, service: onboardingService);

        if (!mounted) {
          return;
        }
      }

      var menus = FirstTimeSetup.postLogin;
      if (menus.isNotEmpty) {
        NavigationUtils.navigateTo(context, SetupPage(menus));
      }
    } catch (error, stackTrace) {
      _postLoginFlowStarted = false;
      Log.onError(error, stackTrace, content: 'Failed to run post-login flow');
    }
  }

  @override
  void dispose() {
    onSpaceUpdateSubscription?.cancel();
    onRoomUpdateSubscription?.cancel();
    onCallStartedSubscription?.cancel();
    onClientRemovedSubscription?.cancel();
    onClientAddedSubscription?.cancel();
    onClientUpdatedSubscription?.cancel();
    onDmLockChangedSubscription?.cancel();
    onDesktopSmallWindowModeChangedSubscription?.cancel();
    onDesktopNavigationSubscription?.cancel();
    onOpenRoomSubscription?.cancel();
    onOpenStorySubscription?.cancel();
    onOpenSpaceSubscription?.cancel();
    for (final timer in _notificationOpenRoomRetryTimers.values) {
      timer.cancel();
    }
    _notificationOpenRoomRetryTimers.clear();
    ServicesBinding.instance.keyboard.removeHandler(_onKeyPressed);
    super.dispose();
  }

  void onClientRemoved(dynamic event) {
    if (!mounted) return;

    var clearPersistedFilter = false;

    setState(() {
      if (_currentRoom != null && !clientManager.rooms.contains(_currentRoom)) {
        _currentRoom = null;
      }

      if (_currentSpace != null &&
          !clientManager.spaces.contains(_currentSpace)) {
        _currentSpace = null;
        _currentView = MainPageSubView.home;
      }

      if (filterClient != null &&
          !clientManager.clients.contains(filterClient)) {
        filterClient = null;
        clearPersistedFilter = true;
        EventBus.setFilterClient.add(null);
      }
    });

    if (clearPersistedFilter) {
      unawaited(preferences.filterClient.set(null));
    }
  }

  Profile? getCurrentUser() {
    if (currentRoom != null) return currentRoom!.client.self!;

    if (currentSpace != null) return currentSpace!.client.self!;

    if (filterClient != null) return filterClient!.self!;

    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (Layout.mobile) {
      return MainPageViewMobile(this);
    } else {
      return MainPageViewDesktop(this);
    }
  }

  void selectSpace(Space? space, {bool recordHistory = true}) {
    if (space == currentSpace) return;

    if (space != null && !space.fullyLoaded) space.loadExtra();
    clearRoomSelection();

    if (space?.avatar is LODImageProvider) {
      (space!.avatar as LODImageProvider).fetchFullRes();
    }

    onSpaceUpdateSubscription?.cancel();
    setState(() {
      _currentSpace = space;
      _currentView = MainPageSubView.space;
    });

    EventBus.onSelectedSpaceChanged.add(space);
    if (recordHistory && space != null) {
      _recordDesktopNavigationEntry(
        DesktopNavigationEntry.space(
          clientId: space.client.identifier,
          spaceId: space.identifier,
        ),
      );
    }
  }

  void selectRoom(
    Room room, {
    bool bypassSpecialRoomType = false,
    bool recordHistory = true,
  }) {
    unawaited(
      _selectRoom(
        room,
        bypassSpecialRoomType: bypassSpecialRoomType,
        recordHistory: recordHistory,
      ),
    );
  }

  void openCallRoomSideRail(CallRoomSideRailMode mode) {
    final room = currentRoom;
    if (room?.getComponent<VoipRoomComponent>() == null) {
      return;
    }

    setState(() {
      _callRoomSideRailRoomKey = _callRoomSideRailKey(room!);
      _callRoomSideRailMode = mode;
      _callRoomSideRailForcedOpen = true;
    });
  }

  void toggleRoomSidePanelFromHeader() {
    if (_callRoomSideRailForcedOpen) {
      setState(() {
        _callRoomSideRailForcedOpen = false;
      });
    }

    EventBus.toggleRoomSidePanel.add(null);
  }

  void _prepareCallRoomSideRailForSelection(Room room) {
    if (room.getComponent<VoipRoomComponent>() == null) {
      _callRoomSideRailMode = CallRoomSideRailMode.members;
      _callRoomSideRailRoomKey = null;
      _callRoomSideRailForcedOpen = false;
      return;
    }

    final roomKey = _callRoomSideRailKey(room);
    final sameRailRoom = roomKey == _callRoomSideRailRoomKey;
    var nextMode = sameRailRoom
        ? _callRoomSideRailMode
        : CallRoomSideRailMode.members;
    var nextForcedOpen = sameRailRoom ? _callRoomSideRailForcedOpen : false;

    final shouldAutoOpenChat = debugShouldAutoOpenCallRoomChatForTesting(
      displayNotificationCount: room.displayNotificationCount,
      displayHighlightedNotificationCount:
          room.displayHighlightedNotificationCount,
      displayRoomWideMentionNotification:
          room.displayRoomWideMentionNotification,
      alreadyAutoOpenedForRoom: _callRoomChatAutoOpenedRoomKeys.contains(
        roomKey,
      ),
    );

    if (shouldAutoOpenChat) {
      _callRoomChatAutoOpenedRoomKeys.add(roomKey);
      nextMode = CallRoomSideRailMode.chat;
      nextForcedOpen = true;
    }

    _callRoomSideRailRoomKey = roomKey;
    _callRoomSideRailMode = nextMode;
    _callRoomSideRailForcedOpen = nextForcedOpen;
  }

  String _callRoomSideRailKey(Room room) {
    return "${room.client.identifier}\u0000${room.identifier}";
  }

  Future<void> _selectRoom(
    Room room, {
    bool bypassSpecialRoomType = false,
    bool recordHistory = true,
  }) async {
    if (room == currentRoom && bypassSpecialRoomType == showAsTextRoom) return;

    if (dmLockController.isRoomLocked(room) &&
        !dmLockController.isRoomUnlocked(room)) {
      await SchedulerBinding.instance.endOfFrame;

      final pinResult = await AdaptiveDialog.show<DmPinDialogResult>(
        context,
        title: "Unlock ${room.displayName}",
        builder: (_) => DmPinDialog(
          mode: DmPinDialogMode.verify,
          description:
              "Enter your local PIN to open this direct message. This PIN never leaves this device.",
          submitLabel: "Unlock",
          allowBiometricFallback: true,
          biometricReason:
              "Use biometrics to unlock this direct message on this device.",
        ),
      );

      if (pinResult?.usedBiometrics == true) {
        final unlocked = await dmLockController
            .unlockRoomForSessionWithBiometrics(room);
        if (!unlocked) {
          return;
        }
      } else {
        final pin = pinResult?.newPin;
        if (pin == null || pin.isEmpty) {
          return;
        }

        final verified = await dmLockController.unlockRoomForSession(room, pin);
        if (!verified) {
          if (!mounted) {
            return;
          }

          await AdaptiveDialog.show(
            context,
            title: "Incorrect PIN",
            builder: (_) =>
                tiamat.Text.label("That PIN did not match. Please try again."),
          );
          return;
        }
      }
    }

    onRoomUpdateSubscription?.cancel();

    setState(() {
      _currentRoom = room;
      showAsTextRoom = bypassSpecialRoomType;
      _prepareCallRoomSideRailForSelection(room);
    });

    EventBus.onSelectedRoomChanged.add(room);
    EventBus.onSelectedSpaceChanged.add(currentSpace);
    if (recordHistory) {
      _recordDesktopNavigationEntry(
        DesktopNavigationEntry.room(
          clientId: room.client.identifier,
          roomId: room.identifier,
          bypassSpecialRoomType: bypassSpecialRoomType,
        ),
      );
    }
  }

  void clearRoomSelection() {
    onRoomUpdateSubscription?.cancel();
    setState(() {
      _currentRoom = null;
      _callRoomSideRailMode = CallRoomSideRailMode.members;
      _callRoomSideRailRoomKey = null;
      _callRoomSideRailForcedOpen = false;
    });

    EventBus.onSelectedRoomChanged.add(null);
  }

  void clearSpaceSelection() {
    setState(() {
      clearRoomSelection();

      _currentSpace = null;
      _currentView = MainPageSubView.home;
    });

    EventBus.onSelectedSpaceChanged.add(null);
  }

  void setFilterClient(Client? event) {
    setState(() {
      filterClient = event;

      if (event != null) {
        if (_currentRoom?.client != event) {
          clearRoomSelection();
        }

        if (_currentSpace != null && _currentSpace?.client != event) {
          clearSpaceSelection();
        }
      }
    });

    unawaited(preferences.filterClient.set(event?.identifier));
  }

  Client? _restorePersistedFilterClient() {
    final persistedClientId = preferences.filterClient.value;
    if (persistedClientId == null) {
      return null;
    }

    final persistedClient = clientManager.clients.firstWhereOrNull(
      (client) => client.identifier == persistedClientId,
    );
    if (persistedClient == null || filterClient == persistedClient) {
      return null;
    }

    filterClient = persistedClient;
    return persistedClient;
  }

  void callRoom(Room room) {
    var component = room.client.getComponent<VoipComponent>();
    if (component == null) {
      return;
    }

    var direct = room.client.getComponent<DirectMessagesComponent>();
    if (direct == null) {
      Log.w("VOIP Only supports direct messages!!");
      return;
    }

    var partner = direct.getDirectMessagePartnerId(room);

    component.startCall(room.identifier, CallType.voice, userId: partner);
  }

  void selectHome({bool recordHistory = true}) {
    setState(() {
      _currentView = MainPageSubView.home;
      clearSpaceSelection();
    });
    if (recordHistory) {
      _recordDesktopNavigationEntry(const DesktopNavigationEntry.home());
    }
  }

  void selectFavorites({bool recordHistory = true}) {
    onRoomUpdateSubscription?.cancel();

    setState(() {
      _currentRoom = null;
      _currentSpace = null;
      _currentView = MainPageSubView.favorites;
    });

    EventBus.onSelectedRoomChanged.add(null);
    EventBus.onSelectedSpaceChanged.add(null);
    if (recordHistory) {
      _recordDesktopNavigationEntry(const DesktopNavigationEntry.favorites());
    }
  }

  void onDesktopNavigationRequest(DesktopNavigationEntry entry) {
    if (!mounted) {
      return;
    }

    switch (entry.type) {
      case DesktopNavigationDestinationType.home:
        selectHome(recordHistory: false);
        return;
      case DesktopNavigationDestinationType.favorites:
        selectFavorites(recordHistory: false);
        return;
      case DesktopNavigationDestinationType.space:
        final spaceId = entry.spaceId;
        if (spaceId == null) {
          _restoreDesktopNavigationHistoryToCurrent();
          return;
        }
        final space = _resolveSpaceTarget(spaceId, entry.clientId)?.space;
        if (space != null) {
          selectSpace(space, recordHistory: false);
        } else {
          _restoreDesktopNavigationHistoryToCurrent();
        }
        return;
      case DesktopNavigationDestinationType.room:
        final roomId = entry.roomId;
        if (roomId == null) {
          _restoreDesktopNavigationHistoryToCurrent();
          return;
        }
        final room = _resolveRoomTarget(roomId, entry.clientId)?.room;
        if (room != null) {
          unawaited(
            _selectRoom(
              room,
              bypassSpecialRoomType: entry.bypassSpecialRoomType,
              recordHistory: false,
            ),
          );
        } else {
          _restoreDesktopNavigationHistoryToCurrent();
        }
        return;
    }
  }

  void _recordCurrentDesktopNavigationEntry() {
    final entry = _desktopNavigationEntryForCurrentState();
    if (entry != null) {
      _recordDesktopNavigationEntry(entry);
    }
  }

  DesktopNavigationEntry? _desktopNavigationEntryForCurrentState() {
    final room = currentRoom;
    if (room != null) {
      return DesktopNavigationEntry.room(
        clientId: room.client.identifier,
        roomId: room.identifier,
        bypassSpecialRoomType: showAsTextRoom,
      );
    }

    final space = currentSpace;
    if (space != null) {
      return DesktopNavigationEntry.space(
        clientId: space.client.identifier,
        spaceId: space.identifier,
      );
    }

    return switch (currentView) {
      MainPageSubView.home => const DesktopNavigationEntry.home(),
      MainPageSubView.favorites => const DesktopNavigationEntry.favorites(),
      MainPageSubView.space => null,
    };
  }

  void _recordDesktopNavigationEntry(DesktopNavigationEntry entry) {
    if (!BuildConfig.DESKTOP) {
      return;
    }

    DesktopNavigationHistoryController.instance.record(entry);
  }

  void _restoreDesktopNavigationHistoryToCurrent() {
    if (!BuildConfig.DESKTOP) {
      return;
    }

    DesktopNavigationHistoryController.instance.restoreCurrent(
      _desktopNavigationEntryForCurrentState(),
    );
  }

  Future<void> onOpenRoomSignal((String, String?) strings) async {
    final isNotificationOpen = EventBus.consumeNotificationOpenRoom(strings);
    final isShortcutOpen = EventBus.consumeShortcutOpenRoom(strings);
    final roomAddress = strings.$1;
    var clientId = strings.$2;

    final resolved = _resolveRoomTarget(roomAddress, clientId);
    final client =
        resolved?.client ??
        (clientId != null
            ? clientManager.getClient(clientId)
            : filterClient ?? clientManager.clients.firstOrNull);

    if (filterClient != null && client != filterClient) {
      if (client == null) {
        if (isNotificationOpen) {
          _scheduleNotificationOpenRoomRetry(strings);
        }
        return;
      }
      if (isNotificationOpen) {
        setFilterClient(client);
        unawaited(preferences.filterClient.set(client.identifier));
        EventBus.openRoomFromNotification(strings);
        return;
      }
      if (await askSwitchAccount(client)) {
        if (isShortcutOpen) {
          EventBus.openRoomFromShortcut(strings);
        } else {
          EventBus.openRoom.add(strings);
        }
      }
      return;
    }

    final room = resolved?.room;

    if (room != null) {
      _clearNotificationOpenRoomRetry(strings);
      if (preferences.automaticallyOpenSpace.value) {
        var spacesWithRoom = room.client.spaces.where(
          (space) => space.containsRoom(room.identifier),
        );

        if (spacesWithRoom.isNotEmpty) {
          selectSpace(spacesWithRoom.first);
        }
      }

      final notificationTargetAlreadySelected =
          isNotificationOpen && room == currentRoom && !showAsTextRoom;
      await _selectRoom(room);
      if (isNotificationOpen) {
        if (notificationTargetAlreadySelected) {
          EventBus.onSelectedRoomChanged.add(room);
        }
        _surfaceNotificationRoomSelection();
      }
      if (isShortcutOpen) {
        await _joinShortcutCallRoom(room);
      }
    } else if (isNotificationOpen) {
      _scheduleNotificationOpenRoomRetry(strings);
    } else if (client != null) {
      GetOrCreateRoom.show(
        client,
        context,
        pickExisting: false,
        showAllRoomTypes: false,
        initialRoomAddress: roomAddress,
      );
    }
  }

  Future<void> onOpenStorySignal(StoryOpenRequest request) async {
    final isNotificationOpen = EventBus.consumeNotificationOpenStory(request);
    final client = clientManager.getClient(request.clientId);

    if (client == null) {
      if (isNotificationOpen) {
        _scheduleNotificationOpenStoryRetry(request);
      }
      return;
    }

    if (filterClient != null && client != filterClient) {
      if (isNotificationOpen) {
        setFilterClient(client);
        unawaited(preferences.filterClient.set(client.identifier));
        EventBus.openStoryFromNotification(request);
        return;
      }
      if (await askSwitchAccount(client)) {
        EventBus.openStory.add(request);
      }
      return;
    }

    final storyComponent = client.getComponent<StoryComponent>();
    if (storyComponent == null) {
      _openStoryFallbackRoom(
        request,
        reason: 'story_component_unavailable',
        openedFromNotification: isNotificationOpen,
      );
      return;
    }

    try {
      await storyComponent.refreshStories();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to refresh stories for notification route',
        category: LogCategory.notifications,
        source: 'story-notification-route',
      );
    }

    final stories = storyComponent.activeStoriesForUser(request.storySenderId);
    final targetIndex = stories.indexWhere(
      (story) =>
          story.storyId == request.storyId ||
          (request.storyEventId != null &&
              story.eventId == request.storyEventId),
    );
    if (targetIndex < 0) {
      _openStoryFallbackRoom(
        request,
        reason: 'story_not_available',
        openedFromNotification: isNotificationOpen,
      );
      return;
    }

    if (!mounted) {
      return;
    }

    final room = client.getRoom(request.roomId);
    final member = room?.getMember(request.storySenderId);
    Profile? profile;
    try {
      profile = await client.getComponent<UserProfileComponent>()?.getProfile(
        request.storySenderId,
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to load story notification profile',
        category: LogCategory.notifications,
        source: 'story-notification-route',
      );
    }

    if (!mounted) {
      return;
    }

    Navigator.of(context).popUntil((route) => route.isFirst);
    final viewer = HomeStoryViewer.show(
      context,
      client: client,
      userId: request.storySenderId,
      stories: stories,
      displayName:
          profile?.displayName ?? member?.displayName ?? request.storySenderId,
      avatar: profile?.avatar ?? member?.avatar,
      avatarColor:
          profile?.defaultColor ??
          member?.defaultColor ??
          _storyFallbackColor(request.storySenderId),
      initialStoryId: request.storyId,
      initialStoryEventId: request.storyEventId,
    );
    _clearNotificationOpenStoryRetry(request);
    EventBus.onStoryOpened.add(request);
    await viewer;
  }

  void _openStoryFallbackRoom(
    StoryOpenRequest request, {
    required String reason,
    required bool openedFromNotification,
  }) {
    Log.i(
      "Story notification falling back to room route "
      "reason=$reason story=${MatrixClient.hash(request.storyId).substring(0, 12)} "
      "room=${MatrixClient.hash(request.roomId).substring(0, 12)}",
      category: LogCategory.notifications,
      source: 'story-notification-route',
    );
    if (openedFromNotification) {
      _clearNotificationOpenStoryRetry(request);
      EventBus.openRoomFromNotification(request.roomRoute);
    } else {
      EventBus.openRoom.add(request.roomRoute);
    }
  }

  Color _storyFallbackColor(String userId) {
    final hash = userId.codeUnits.fold<int>(
      0,
      (value, codeUnit) => (value * 31 + codeUnit) & 0x7fffffff,
    );
    return Colors.primaries[hash % Colors.primaries.length].shade400;
  }

  Future<void> _joinShortcutCallRoom(Room room) async {
    final voipRoom = room.getComponent<VoipRoomComponent>();
    if (voipRoom == null) {
      return;
    }

    if (!voipRoom.canJoinCall) {
      Log.w(
        'Shortcut opened call room but local user cannot join.',
        category: LogCategory.livekit,
        source: 'main-page-shortcut',
      );
      return;
    }

    try {
      await voipRoom.joinCall();
      if (!mounted) {
        return;
      }
      setState(() {});
    } catch (error, stackTrace) {
      if (error is MatrixLivekitCallJoinPreflightException) {
        Log.w(
          'Shortcut call auto-join blocked by local E2EE trust preflight.',
          category: LogCategory.livekit,
          source: 'main-page-shortcut',
        );
        if (!mounted) {
          return;
        }
        await AdaptiveDialog.show(
          context,
          title: 'Verify this session',
          builder: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [tiamat.Text.body(error.message)],
          ),
        );
        return;
      }

      Log.onError(
        error,
        stackTrace,
        content: 'Failed to auto-join call from room shortcut',
        category: LogCategory.livekit,
        source: 'main-page-shortcut',
      );
      if (!mounted) {
        return;
      }
      await AdaptiveDialog.showError(context, error, stackTrace);
    }
  }

  void _scheduleNotificationOpenRoomRetry((String, String?) room) {
    final retryKey = _notificationOpenRoomRetryKey(room);
    final roomDiagnostic = MatrixClient.hash(room.$1).substring(0, 12);
    final attempts = _notificationOpenRoomRetryCounts[retryKey] ?? 0;
    if (attempts >= _notificationOpenRoomRetryLimit) {
      Log.w(
        "Giving up notification room open for $roomDiagnostic "
        "after $_notificationOpenRoomRetryLimit attempts",
      );
      _clearNotificationOpenRoomRetry(room);
      return;
    }

    if (_notificationOpenRoomRetryTimers.containsKey(retryKey)) {
      return;
    }

    if (attempts == 0) {
      Log.i(
        "Notification room $roomDiagnostic is not ready yet; "
        "retrying room open",
      );
    }

    _notificationOpenRoomRetryCounts[retryKey] = attempts + 1;
    _notificationOpenRoomRetryTimers[retryKey] = Timer(
      _notificationOpenRoomRetryDelay,
      () {
        _notificationOpenRoomRetryTimers.remove(retryKey);
        if (!mounted) {
          return;
        }
        EventBus.openRoomFromNotification(room);
      },
    );
  }

  void _scheduleNotificationOpenStoryRetry(StoryOpenRequest request) {
    final room = request.roomRoute;
    final retryKey = _notificationOpenStoryRetryKey(request);
    final roomDiagnostic = MatrixClient.hash(room.$1).substring(0, 12);
    final attempts = _notificationOpenRoomRetryCounts[retryKey] ?? 0;
    if (attempts >= _notificationOpenRoomRetryLimit) {
      Log.w(
        "Giving up notification story open for $roomDiagnostic "
        "after $_notificationOpenRoomRetryLimit attempts",
      );
      _clearNotificationOpenStoryRetry(request);
      return;
    }

    if (_notificationOpenRoomRetryTimers.containsKey(retryKey)) {
      return;
    }

    if (attempts == 0) {
      Log.i(
        "Notification story $roomDiagnostic is not ready yet; "
        "retrying story open",
      );
    }

    _notificationOpenRoomRetryCounts[retryKey] = attempts + 1;
    _notificationOpenRoomRetryTimers[retryKey] = Timer(
      _notificationOpenRoomRetryDelay,
      () {
        _notificationOpenRoomRetryTimers.remove(retryKey);
        if (!mounted) {
          return;
        }
        EventBus.openStoryFromNotification(request);
      },
    );
  }

  void _clearNotificationOpenRoomRetry((String, String?) room) {
    final retryKey = _notificationOpenRoomRetryKey(room);
    _notificationOpenRoomRetryCounts.remove(retryKey);
    _notificationOpenRoomRetryTimers.remove(retryKey)?.cancel();
  }

  void _clearNotificationOpenStoryRetry(StoryOpenRequest request) {
    final retryKey = _notificationOpenStoryRetryKey(request);
    _notificationOpenRoomRetryCounts.remove(retryKey);
    _notificationOpenRoomRetryTimers.remove(retryKey)?.cancel();
  }

  String _notificationOpenRoomRetryKey((String, String?) room) {
    return "${room.$2 ?? ''}\u0000${room.$1}";
  }

  String _notificationOpenStoryRetryKey(StoryOpenRequest request) {
    return "story\u0000${request.routeKey}";
  }

  void _surfaceNotificationRoomSelection() {
    if (!mounted) {
      return;
    }

    Navigator.of(context).popUntil((route) => route.isFirst);
    EventBus.focusTimeline.add(null);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      EventBus.focusTimeline.add(null);
    });
  }

  void onOpenSpaceSignal((String, String?) strings) async {
    final resolved = _resolveSpaceTarget(strings.$1, strings.$2);
    final space = resolved?.space;
    final client = resolved?.client;
    if (space == null || client == null) {
      return;
    }

    if (filterClient != null && client != filterClient) {
      if (await askSwitchAccount(client)) {
        EventBus.openSpace.add(strings);
      }
      return;
    }

    selectSpace(space);
  }

  _ResolvedRoomTarget? _resolveRoomTarget(String address, String? clientId) {
    final clients = clientId != null
        ? [clientManager.getClient(clientId)].whereType<Client>()
        : clientManager.clients;

    for (final client in clients) {
      var roomId = address;
      if (client is MatrixClient) {
        final info = client.parseAddressToIdAndVia(address);
        if (info != null) {
          roomId = info.$1;
        }
      }

      final room =
          client.getRoom(roomId) ??
          client.getRoomByAlias(address) ??
          client.getRoomByAlias(roomId);
      if (room != null) {
        return _ResolvedRoomTarget(client: client, room: room);
      }
    }

    return null;
  }

  _ResolvedSpaceTarget? _resolveSpaceTarget(String address, String? clientId) {
    final clients = clientId != null
        ? [clientManager.getClient(clientId)].whereType<Client>()
        : clientManager.clients;

    for (final client in clients) {
      var spaceId = address;
      if (client is MatrixClient) {
        final info = client.parseAddressToIdAndVia(address);
        if (info != null) {
          spaceId = info.$1;
        }
      }

      final space =
          client.getSpace(spaceId) ??
          _getSpaceByAlias(client, address) ??
          _getSpaceByAlias(client, spaceId);
      if (space != null) {
        return _ResolvedSpaceTarget(client: client, space: space);
      }
    }

    return null;
  }

  Space? _getSpaceByAlias(Client client, String alias) {
    return client.spaces.firstWhereOrNull((space) {
      if (space is! MatrixSpace) {
        return false;
      }

      final state = space.matrixRoom.getState("m.room.canonical_alias");
      if (state == null) {
        return false;
      }

      if (state.content["alias"] == alias) {
        return true;
      }

      final alts = state.content["alt_aliases"];
      return alts is List<dynamic> && alts.contains(alias);
    });
  }

  Future<bool> askSwitchAccount(Client newClient) async {
    var confirm = await AdaptiveDialog.confirmation(
      context,
      prompt:
          "You tried to open something for another account (${newClient.self?.identifier}), would you like to switch?",
      title: "Switch Account",
    );
    if (confirm != true) return false;

    EventBus.setFilterClient.add(newClient);
    preferences.filterClient.set(newClient.identifier);
    return true;
  }

  void navigateRoomSettings() {
    if (currentRoom != null) {
      SettingsNavigation.show(
        context,
        RoomSettingsPage(
          room: currentRoom!,
          contextSpace: currentSpace,
          onLeaveRoom: clearRoomSelection,
        ),
      );
    }
  }

  void onOpenUserProfileSignal((String, String, String?) event) {
    var userId = event.$1;
    var clientId = event.$2;

    var client = clientManager.getClient(clientId);
    if (client != null) {
      UserProfile.show(context, client: client, userId: userId);
    }
  }

  void searchUserToDm() async {
    var client = filterClient;
    if (client == null) client = await AdaptiveDialog.pickClient(context);

    if (client == null) {
      return;
    }

    final invitation = client.getComponent<InvitationComponent>();
    if (invitation == null) return;

    AdaptiveDialog.show(
      context,
      builder: (context) => SendInvitationWidget(
        client!,
        invitation,
        showSuggestions: false,
        onUserPicked: (userId) async {
          final confirm = await AdaptiveDialog.confirmation(
            context,
            prompt: "Are you sure you want to invite $userId to chat?",
            title: "Invitation",
          );
          if (confirm != true) {
            return;
          }

          var comp = client!.getComponent<DirectMessagesComponent>();
          await comp?.createDirectMessage(userId);
        },
      ),
      title: "Start Direct Message",
    );
  }

  bool _onKeyPressed(KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.keyK &&
          ServicesBinding.instance.keyboard.isControlPressed) {
        QuickSwitcher.show(context);
      }
    }

    return false;
  }
}

class _ResolvedRoomTarget {
  const _ResolvedRoomTarget({required this.client, required this.room});

  final Client client;
  final Room room;
}

class _ResolvedSpaceTarget {
  const _ResolvedSpaceTarget({required this.client, required this.space});

  final Client client;
  final Space space;
}
