import 'dart:async';
import 'package:collection/collection.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/activity/activity_service.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/components/invitation/invitation_component.dart';
import 'package:intergalactic/client/components/inbox/inbox_query.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_controller.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_delivery_gate.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_draft.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_handoff.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_lifecycle.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_payload.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intl/intl.dart';
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
import 'package:intergalactic/ui/pages/inbound_share/inbound_share_review_launcher.dart';
import 'package:intergalactic/ui/pages/inbox/inbox_navigation.dart';
import 'package:intergalactic/ui/pages/inbox/inbox_page.dart';
import 'package:intergalactic/ui/pages/setup/setup_page.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:intergalactic/ui/navigation/navigation_utils.dart';
import 'package:intergalactic/ui/pages/main/main_page_view_desktop.dart';
import 'package:intergalactic/ui/pages/main/main_page_view_mobile.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/settings_category_room.dart';
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

/// Resolves the call-room side rail for a room selection.
///
/// [asTextRoom] is the "Open as Text Chat" selection, which replaces the whole
/// main area with a chat. The rail must not add a second one: two independent
/// paths could each put a chat on screen for the same room, with nothing making
/// them exclusive, and users were seeing both at once. The rail owns call-room
/// chat, so the text-room selection loses its chat mode here and
/// `openCallRoomSideRail` clears `showAsTextRoom` in the other direction.
@visibleForTesting
({CallRoomSideRailMode mode, bool forcedOpen})
debugResolveCallRoomSideRailForSelection({
  required bool asTextRoom,
  required bool sameRailRoom,
  required CallRoomSideRailMode currentMode,
  required bool currentForcedOpen,
  required bool shouldAutoOpenChat,
}) {
  if (asTextRoom) {
    return (mode: CallRoomSideRailMode.members, forcedOpen: false);
  }

  if (shouldAutoOpenChat) {
    return (mode: CallRoomSideRailMode.chat, forcedOpen: true);
  }

  return (
    mode: sameRailRoom ? currentMode : CallRoomSideRailMode.members,
    forcedOpen: sameRailRoom && currentForcedOpen,
  );
}

class MainPageState extends State<MainPage> {
  static const int _notificationOpenRoomRetryLimit = 24;
  static const Duration _notificationOpenRoomRetryDelay = Duration(
    milliseconds: 500,
  );
  static const int _streamLabOpenRoomRetryLimit = 40;
  static const Duration _streamLabOpenRoomRetryDelay = Duration(
    milliseconds: 500,
  );
  static const int _inboxJumpListenerRetryLimit = 12;
  static const Duration _inboxJumpListenerRetryDelay = Duration(
    milliseconds: 50,
  );

  Space? _currentSpace;
  Room? _currentRoom;
  InboundShareDraft? _inboundShareDraft;
  final _inboundShareLifecycle = InboundShareLifecycle(
    const MethodChannelInboundShareStagingRootProvider(),
  );
  final _inboundShareDeliveryGate = InboundShareDeliveryGate();
  Future<void> _inboundSharePayloadHandling = Future.value();
  bool _inboundShareDisposed = false;
  final InboundShareHandoff _inboundShareHandoff = PlatformUtils.isIOS
      ? const MethodChannelInboundShareHandoff()
      : const NoopInboundShareHandoff();
  bool showAsTextRoom = false;
  Client? filterClient;
  CallRoomSideRailMode _callRoomSideRailMode = CallRoomSideRailMode.members;
  String? _callRoomSideRailRoomKey;
  bool _callRoomSideRailForcedOpen = false;
  final Set<String> _callRoomChatAutoOpenedRoomKeys = {};

  MainPageSubView _currentView = MainPageSubView.home;

  StreamSubscription? onSpaceUpdateSubscription;
  StreamSubscription? onRoomUpdateSubscription;
  StreamSubscription<InboundShareDraft>? _inboundShareDraftSubscription;
  StreamSubscription<InboundSharePayload>? _inboundSharePayloadSubscription;
  StreamSubscription<InboundShareFailure>? _inboundShareFailureSubscription;
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
  final Map<String, int> _streamLabOpenRoomRetryCounts = {};
  final Map<String, Timer> _streamLabOpenRoomRetryTimers = {};
  int _inboxNavigationRequestId = 0;

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
    _inboundShareDraftSubscription = EventBus.inboundShareDraft.stream.listen(
      (draft) => unawaited(_onInboundShareDraft(draft)),
    );
    _inboundSharePayloadSubscription = EventBus.inboundSharePayload.stream
        .listen(_receiveInboundSharePayload);
    _inboundShareFailureSubscription = EventBus.inboundShareFailure.stream
        .listen((failure) => unawaited(_showInboundShareFailure(failure)));
    for (final pending in EventBus.pendingInboundSharePayloads) {
      _inboundShareDeliveryGate.enqueue(pending);
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _inboundShareDeliveryGate.markHostReady();
      Log.i('inbound_share event=main_page_host_ready');
      _drainInboundShareDeliveryGate();
      // Drained in the post-frame callback, not in initState: presenting a
      // dialog needs a Navigator, which is not usable until this host has
      // built. A share that failed during a cold start is waiting here.
      for (final pending in EventBus.pendingInboundShareFailures) {
        unawaited(_showInboundShareFailure(pending));
      }
    });

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
    // Set first: an admission already in flight checks this after its await to
    // decide whether the session it just claimed can still be reviewed.
    _inboundShareDisposed = true;
    _inboundShareDraftSubscription?.cancel();
    _inboundSharePayloadSubscription?.cancel();
    // Not drained here: an unclaimed failure stays retained in EventBus so a
    // replacement MainPage still reports it, exactly like an unclaimed payload.
    _inboundShareFailureSubscription?.cancel();
    // Payloads stay retained by EventBus until admission starts, so a
    // replacement MainPage can recover anything this host did not claim.
    _inboundShareDeliveryGate.takeAll();
    unawaited(_inboundShareLifecycle.cancelAll());
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
    for (final timer in _streamLabOpenRoomRetryTimers.values) {
      timer.cancel();
    }
    _streamLabOpenRoomRetryTimers.clear();
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

  /// Opens Inbox with this main page as the single owner of room navigation.
  ///
  /// The Inbox only supplies immutable room/event snapshots. Keeping selection
  /// here preserves the existing account switch and direct-message unlock flow
  /// before the destination timeline receives its event jump.
  Future<void> openInbox(BuildContext context) {
    return InboxNavigation.show<void>(
      context,
      InboxPage(
        clientManager: clientManager,
        filterClient: filterClient,
        onOpen: _openInboxSnapshot,
      ),
    );
  }

  Future<bool> _openInboxSnapshot(
    InboxRoomSnapshot snapshot,
    InboxEventSnapshot event,
  ) async {
    final requestId = ++_inboxNavigationRequestId;
    bool isCurrentRequest() =>
        mounted && requestId == _inboxNavigationRequestId;
    final client = clientManager.getClient(snapshot.clientIdentifier);
    final room = client?.getRoom(snapshot.roomId);
    if (client == null || room == null) {
      return false;
    }

    // A row from another account becomes the active scope before normal room
    // selection. _selectRoom retains the normal DM PIN/biometric gate.
    if (!identical(filterClient, client)) {
      setFilterClient(client);
    }
    await _selectRoom(
      room,
      bypassSpecialRoomType: true,
      shouldContinue: isCurrentRequest,
    );
    if (!isCurrentRequest() || !identical(currentRoom, room)) {
      return false;
    }

    // The timeline subscribes after Chat is mounted. Wait for that listener
    // instead of dropping the event while the normal room transition settles.
    for (var attempt = 0; attempt < _inboxJumpListenerRetryLimit; attempt++) {
      await SchedulerBinding.instance.endOfFrame;
      if (!isCurrentRequest()) {
        return false;
      }
      if (EventBus.jumpToInboxEvent(
        clientIdentifier: client.identifier,
        roomIdentifier: room.identifier,
        eventId: event.eventId,
      )) {
        return true;
      }
      await Future<void>.delayed(_inboxJumpListenerRetryDelay);
    }

    return false;
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

      // The side rail owns call-room chat. "Open as Text Chat" replaces the
      // whole main area with a chat, so leaving it on here would render two
      // chats for one room side by side - which is what users were seeing.
      if (mode == CallRoomSideRailMode.chat) {
        showAsTextRoom = false;
      }
    });
  }

  void toggleRoomSidePanelFromHeader() {
    dismissCallRoomSideRail();

    EventBus.toggleRoomSidePanel.add(null);
  }

  void dismissCallRoomSideRail() {
    if (!_callRoomSideRailForcedOpen) {
      return;
    }

    setState(() {
      _callRoomSideRailForcedOpen = false;
    });
  }

  /// [asTextRoom] is the "Open as Text Chat" selection, which puts a chat in
  /// the main area. The side rail must not add a second one, so chat mode is
  /// suppressed for that selection - see [openCallRoomSideRail] for the same
  /// rule in the other direction.
  void _prepareCallRoomSideRailForSelection(
    Room room, {
    bool asTextRoom = false,
  }) {
    if (room.getComponent<VoipRoomComponent>() == null) {
      _callRoomSideRailMode = CallRoomSideRailMode.members;
      _callRoomSideRailRoomKey = null;
      _callRoomSideRailForcedOpen = false;
      return;
    }

    final roomKey = _callRoomSideRailKey(room);
    final sameRailRoom = roomKey == _callRoomSideRailRoomKey;

    final shouldAutoOpenChat =
        !asTextRoom &&
        debugShouldAutoOpenCallRoomChatForTesting(
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
    }

    final resolved = debugResolveCallRoomSideRailForSelection(
      asTextRoom: asTextRoom,
      sameRailRoom: sameRailRoom,
      currentMode: _callRoomSideRailMode,
      currentForcedOpen: _callRoomSideRailForcedOpen,
      shouldAutoOpenChat: shouldAutoOpenChat,
    );

    _callRoomSideRailRoomKey = roomKey;
    _callRoomSideRailMode = resolved.mode;
    _callRoomSideRailForcedOpen = resolved.forcedOpen;
  }

  String _callRoomSideRailKey(Room room) {
    return "${room.client.identifier}\u0000${room.identifier}";
  }

  Future<void> _selectRoom(
    Room room, {
    bool bypassSpecialRoomType = false,
    bool recordHistory = true,
    bool Function()? shouldContinue,
  }) async {
    if (shouldContinue?.call() == false) return;
    if (room == currentRoom && bypassSpecialRoomType == showAsTextRoom) return;

    if (dmLockController.isRoomLocked(room) &&
        !dmLockController.isRoomUnlocked(room)) {
      await SchedulerBinding.instance.endOfFrame;
      if (shouldContinue?.call() == false) return;

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
      if (shouldContinue?.call() == false) return;

      if (pinResult?.usedBiometrics == true) {
        final unlocked = await dmLockController
            .unlockRoomForSessionWithBiometrics(room);
        if (shouldContinue?.call() == false) return;
        if (!unlocked) {
          return;
        }
      } else {
        final pin = pinResult?.newPin;
        if (pin == null || pin.isEmpty) {
          return;
        }

        final verified = await dmLockController.unlockRoomForSession(room, pin);
        if (shouldContinue?.call() == false) return;
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
    if (shouldContinue?.call() == false) return;

    setState(() {
      _currentRoom = room;
      showAsTextRoom = bypassSpecialRoomType;
      _prepareCallRoomSideRailForSelection(
        room,
        asTextRoom: bypassSpecialRoomType,
      );
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

  void _receiveInboundSharePayload(InboundSharePayload payload) {
    if (!mounted) return;
    _inboundShareDeliveryGate.enqueue(payload);
    Log.i(
      'inbound_share event=main_page_received result=queued '
      'host_ready=${_inboundShareDeliveryGate.isHostReady} '
      'item_count=${payload.itemCount}',
    );
    _drainInboundShareDeliveryGate();
  }

  String get _inboundSharePermissionDeniedMessage => Intl.message(
    "Couldn't read what was shared. The app you shared from didn't grant "
    "access to it - try sharing a link instead.",
    name: 'inboundSharePermissionDenied',
    desc:
        'Shown when a share fails because the sending app refused read access '
        'to the file. Sharing a link from the same app usually works.',
  );

  String get _inboundShareTooLargeMessage => Intl.message(
    'That share is too large. Files are limited to 100 MB each, and 250 MB '
    'per share.',
    name: 'inboundShareTooLarge',
    desc: 'Shown when a share is refused for exceeding the size limits.',
  );

  String get _inboundShareUnreadableMessage => Intl.message(
    "Couldn't read what was shared.",
    name: 'inboundShareUnreadable',
    desc:
        'Shown when a share fails for a reason with no more specific message.',
  );

  String get _inboundShareFailedTitle => Intl.message(
    'Share failed',
    name: 'inboundShareFailedTitle',
    desc: 'Title of the dialog shown when an incoming share could not be read.',
  );

  /// Tells the user a share produced nothing, instead of letting it vanish.
  ///
  /// Before this, a share that failed every item was swallowed and nothing
  /// appeared - which on device was indistinguishable from the app ignoring
  /// the share entirely. Confirmed 2026-08-05 with Chrome's FileProvider,
  /// which refuses the read grant, so sharing an image from Google Images did
  /// nothing at all while the same image from the gallery worked.
  ///
  /// Uses [AdaptiveDialog] rather than a SnackBar, and that is not a style
  /// preference. A SnackBar is drawn by a Scaffold registered with the
  /// ScaffoldMessenger, and there is no Scaffold anywhere on this page - the
  /// whole app contains 14 and none are on the main navigation path. So
  /// `ScaffoldMessenger.maybeOf(context)?.showSnackBar(...)` here is a silent
  /// no-op: on device it logged `failure_shown` and drew nothing, reproducing
  /// the exact silent failure this exists to remove. AdaptiveDialog presents a
  /// route - bottom sheet on mobile, popup on desktop - and needs no Scaffold.
  Future<void> _showInboundShareFailure(InboundShareFailure failure) async {
    // Claimed before displaying so a replacement MainPage does not repeat a
    // message this one already showed.
    if (!EventBus.claimPendingInboundShareFailure(failure)) return;
    if (!mounted) return;
    Log.w('inbound_share event=failure_shown reason=${failure.name}');
    final message = switch (failure) {
      InboundShareFailure.permissionDenied =>
        _inboundSharePermissionDeniedMessage,
      InboundShareFailure.tooLarge => _inboundShareTooLargeMessage,
      InboundShareFailure.unreadable => _inboundShareUnreadableMessage,
    };
    await AdaptiveDialog.show(
      context,
      title: _inboundShareFailedTitle,
      initialHeightMobile: 0.25,
      builder: (_) => tiamat.Text.body(message),
    );
  }

  void _drainInboundShareDeliveryGate() {
    while (true) {
      final payload = _inboundShareDeliveryGate.takeNext();
      if (payload == null) return;
      _enqueueInboundSharePayload(payload);
    }
  }

  void _enqueueInboundSharePayload(InboundSharePayload payload) {
    _inboundSharePayloadHandling = _inboundSharePayloadHandling.then<void>((
      _,
    ) async {
      try {
        await _onInboundSharePayload(payload);
      } catch (error, stackTrace) {
        Log.onError(
          error,
          stackTrace,
          content: 'Failed to handle inbound share',
        );
      }
    });
  }

  Future<void> _onInboundSharePayload(InboundSharePayload payload) async {
    if (!mounted || !EventBus.claimPendingInboundSharePayload(payload)) return;
    Log.i(
      'inbound_share event=main_page_admission result=started '
      'item_count=${payload.itemCount}',
    );
    final admission = await _inboundShareLifecycle.admit(payload);
    final session = admission.session;
    // Settle the native staging reservation HERE, on the admission outcome -
    // not when the payload was emitted onto the in-memory bus. Acknowledging at
    // emission meant a process death between emit and admit left a session
    // marked accepted that nothing would ever pick up. REVIEW, 2026-08-02.
    await settleInboundShareAdmission(
      admission: admission,
      token: payload.stagingToken,
      handoff: _inboundShareHandoff,
    );
    if (admission.admission == InboundShareAdmission.rejected ||
        session == null) {
      Log.w('inbound_share event=main_page_admission result=rejected');
      return;
    }
    Log.i(
      'inbound_share event=main_page_admission '
      'result=${admission.admission.name}',
    );
    if (_inboundShareDisposed) {
      // The payload was claimed from EventBus before this await, so no
      // replacement host can recover it, and dispose's un-awaited cancelAll may
      // have run before this session existed. Release it here rather than
      // leaving staged content owned by a controller nothing will ever review.
      Log.w('inbound_share event=main_page_admission result=host_disposed');
      await _inboundShareLifecycle.cancelAll();
      return;
    }
    if (admission.admission == InboundShareAdmission.active) {
      await _launchInboundShareReview(session);
    }
  }

  Future<void> _launchInboundShareReview(InboundShareSession session) async {
    if (!mounted) return;
    Log.i('inbound_share event=selector_launch result=requested');
    await InboundShareReviewLauncher.launch(
      context,
      session: session,
      clients: widget.clientManager.clients,
      accountLabel: (client) => client.self?.identifier ?? client.identifier,
      onTerminal: (terminal) => _finishInboundShare(session, terminal),
    );
  }

  Future<void> _finishInboundShare(
    InboundShareSession session,
    InboundShareSessionState terminal,
  ) async {
    // Donate the conversation only for a share that actually completed, and
    // only when the user has opted into richer previews - a donation surfaces
    // the room name in the iOS share sheet and Siri suggestions, which is the
    // same disclosure a notification preview makes. The preference defaults to
    // private, so the default is not to donate.
    final donationRoom =
        terminal == InboundShareSessionState.completed &&
            identical(_inboundShareDraft?.session, session)
        ? _inboundShareDraft?.room
        : null;
    if (donationRoom != null &&
        PlatformUtils.isIOS &&
        !preferences.usePrivateNotificationPreviews) {
      unawaited(
        const InboundShareConversationDonor().donate(
          roomId: donationRoom.identifier,
          displayName: donationRoom.displayName,
        ),
      );
    }

    final promoted = await _inboundShareLifecycle.finish(session, terminal);
    if (!mounted) return;
    if (identical(_inboundShareDraft?.session, session)) {
      setState(() => _inboundShareDraft = null);
    }
    if (promoted != null) {
      _relaunchInboundShareReview(promoted);
    }
  }

  /// Reopens review on a detached microtask, with the same error routing every
  /// other inbound-share path here uses.
  ///
  /// The delay exists so the relaunch happens after the current navigation
  /// settles; without a handler on that chain a throw inside the awaited review
  /// flow becomes an uncaught async error and the share just stops.
  void _relaunchInboundShareReview(InboundShareSession session) {
    unawaited(
      Future<void>.delayed(Duration.zero)
          .then((_) => _launchInboundShareReview(session))
          .catchError((Object error, StackTrace stackTrace) {
            Log.onError(
              error,
              stackTrace,
              content: 'Failed to relaunch inbound share review',
            );
          }),
    );
  }

  /// The listener detaches this future, so it owns its own error reporting.
  Future<void> _onInboundShareDraft(InboundShareDraft draft) async {
    // A queued event still arrives after dispose cancels the subscription, and
    // this handler calls setState.
    if (!mounted) return;
    try {
      if (!draft.room.permissions.canSendMessage) {
        Log.w(
          'Inbound share destination became unavailable: '
          '${draft.room.identifier}',
        );
        _relaunchInboundShareReview(draft.session);
        return;
      }
      // Awaited: _selectRoom can return without selecting anything (a cancelled
      // or failed DM PIN prompt). Storing the draft anyway strands it, because
      // draftFor only matches the room that is actually current.
      await _selectRoom(draft.room, bypassSpecialRoomType: true);
      if (!mounted) return;
      // Identity, not ==: draftFor matches by identity, so an equal-but-other
      // Room instance would hold a draft the composer can never receive.
      if (!identical(_currentRoom, draft.room)) {
        Log.w('inbound_share event=draft result=selection_abandoned');
        await _launchInboundShareReview(draft.session);
        return;
      }
      setState(() => _inboundShareDraft = draft);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to handle inbound share draft',
      );
    }
  }

  InboundShareDraft? draftFor(Room room) =>
      identical(_inboundShareDraft?.room, room) ? _inboundShareDraft : null;
  void clearRoomSelection() {
    final draft = _inboundShareDraft;
    onRoomUpdateSubscription?.cancel();
    setState(() {
      _inboundShareDraft = null;
      _currentRoom = null;
      _callRoomSideRailMode = CallRoomSideRailMode.members;
      _callRoomSideRailRoomKey = null;
      _callRoomSideRailForcedOpen = false;
    });

    EventBus.onSelectedRoomChanged.add(null);
    if (draft != null) {
      unawaited(draft.onTerminal(InboundShareSessionState.cancelled));
    }
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
    final opensNotificationSettings = EventBus.hasNotificationOpenRoomSettings(
      strings,
    );
    final isShortcutOpen = EventBus.consumeShortcutOpenRoom(strings);
    final isStreamLabOpen = EventBus.consumeStreamLabOpenRoom(strings);
    final streamLabMetadata = isStreamLabOpen
        ? EventBus.takeStreamLabOpenRoomMetadata(strings)
        : null;
    final shouldAutoJoinCall = isShortcutOpen || isStreamLabOpen;
    final roomAddress = strings.$1;
    var clientId = strings.$2;

    var resolved = _resolveRoomTarget(roomAddress, clientId);
    if (resolved == null && isStreamLabOpen && clientId != null) {
      final roomResolvedWithoutClient = _resolveRoomTarget(roomAddress, null);
      if (roomResolvedWithoutClient != null) {
        Log.w(
          'Stream-lab open-room configured account is unavailable; '
          'using the loaded account that owns the target room.',
          category: LogCategory.livekit,
          source: 'stream-lab-open-room',
        );
        clientId = roomResolvedWithoutClient.client.identifier;
        resolved = roomResolvedWithoutClient;
      }
    }

    final client =
        resolved?.client ??
        (clientId != null
            ? clientManager.getClient(clientId)
            : filterClient ?? clientManager.clients.firstOrNull);

    if (filterClient != null && client != filterClient) {
      if (client == null) {
        if (isNotificationOpen) {
          _scheduleNotificationOpenRoomRetry(strings);
        } else if (isStreamLabOpen) {
          _scheduleStreamLabOpenRoomRetry(
            strings,
            reason: 'target client is not ready',
            metadata: streamLabMetadata,
          );
        }
        return;
      }
      if (isNotificationOpen) {
        setFilterClient(client);
        unawaited(preferences.filterClient.set(client.identifier));
        EventBus.openRoomFromNotification(strings);
        return;
      }
      if (isStreamLabOpen) {
        Log.i(
          'Stream-lab open-room switching to configured account.',
          category: LogCategory.livekit,
          source: 'stream-lab-open-room',
        );
        setFilterClient(client);
        unawaited(preferences.filterClient.set(client.identifier));
        EventBus.openRoomFromStreamLab(
          strings,
          requestNonce: streamLabMetadata?.requestNonce,
          roomHash: streamLabMetadata?.roomHash,
        );
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
      _clearStreamLabOpenRoomRetry(strings);
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
      if (opensNotificationSettings) {
        // The intent belongs to ONE notification delivery, and it was keyed by
        // route alone. Consumed unconditionally so an abandoned one cannot
        // linger; acted on only when THIS open actually came from the
        // notification, so a later manual open of the same room does not pop
        // settings on its own.
        final consumed = EventBus.consumeNotificationOpenRoomSettings(strings);
        // `currentRoom == room` is the check that the selection above actually
        // HAPPENED. `_selectRoom` returns early without selecting when a
        // locked DM's PIN dialog is cancelled or the PIN is wrong - and this
        // branch used to open RoomSettingsPage anyway, showing the room's name
        // and notification settings for a direct message the user had just
        // failed to unlock. The consume stays unconditional above so an
        // abandoned intent still cannot linger.
        if (consumed && isNotificationOpen && mounted && currentRoom == room) {
          SettingsNavigation.show(
            context,
            RoomSettingsPage(
              room: room,
              contextSpace: currentSpace,
              onLeaveRoom: clearRoomSelection,
              initialTabId: SettingsCategoryRoom.tabIdNotifications,
            ),
          );
        }
      }
      if (shouldAutoJoinCall) {
        await _joinShortcutCallRoom(
          room,
          logSource: isStreamLabOpen
              ? 'stream-lab-open-room'
              : 'main-page-shortcut',
          streamLab: isStreamLabOpen,
          streamLabRequestNonce: streamLabMetadata?.requestNonce,
          streamLabRoomHash: streamLabMetadata?.roomHash,
        );
      }
    } else if (isNotificationOpen) {
      _scheduleNotificationOpenRoomRetry(strings);
    } else if (isStreamLabOpen) {
      _scheduleStreamLabOpenRoomRetry(
        strings,
        reason: 'target room is not ready',
        metadata: streamLabMetadata,
      );
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

  Future<void> _joinShortcutCallRoom(
    Room room, {
    String logSource = 'main-page-shortcut',
    bool streamLab = false,
    String? streamLabRequestNonce,
    String? streamLabRoomHash,
  }) async {
    final sourceLabel = streamLab ? 'Stream-lab' : 'Shortcut';
    final voipRoom = room.getComponent<VoipRoomComponent>();
    if (voipRoom == null) {
      Log.w(
        '$sourceLabel opened call room but no VoIP room component was available.',
        category: LogCategory.livekit,
        source: logSource,
      );
      return;
    }

    if (!voipRoom.canJoinCall) {
      Log.w(
        '$sourceLabel opened call room but local user cannot join.',
        category: LogCategory.livekit,
        source: logSource,
      );
      return;
    }

    try {
      await voipRoom.joinCall();
      Log.i(
        streamLab
            ? _streamLabCallRoomJoinedMessage(
                requestNonce: streamLabRequestNonce,
                roomHash: streamLabRoomHash,
              )
            : 'Shortcut call room joined.',
        category: LogCategory.livekit,
        source: logSource,
      );
      if (!mounted) {
        return;
      }
      setState(() {});
    } catch (error, stackTrace) {
      if (error is MatrixLivekitCallJoinPreflightException) {
        Log.w(
          '$sourceLabel call auto-join blocked by local E2EE trust preflight.',
          category: LogCategory.livekit,
          source: logSource,
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
        content: streamLab
            ? 'Failed to auto-join call from stream-lab room open'
            : 'Failed to auto-join call from room shortcut',
        category: LogCategory.livekit,
        source: logSource,
      );
      if (!mounted) {
        return;
      }
      await AdaptiveDialog.showError(context, error, stackTrace);
    }
  }

  String _streamLabCallRoomJoinedMessage({
    String? requestNonce,
    String? roomHash,
  }) {
    final details = <String>[];
    if (requestNonce != null && requestNonce.isNotEmpty) {
      details.add('requestNonce=$requestNonce');
    }
    if (roomHash != null && roomHash.isNotEmpty) {
      details.add('roomHash=$roomHash');
    }
    if (details.isEmpty) {
      return 'Stream-lab call room joined.';
    }
    return 'Stream-lab call room joined; ${details.join(' ')}.';
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

  void _scheduleStreamLabOpenRoomRetry(
    (String, String?) room, {
    required String reason,
    StreamLabOpenRoomMetadata? metadata,
  }) {
    final retryKey = _streamLabOpenRoomRetryKey(room);
    final roomDiagnostic = MatrixClient.hash(room.$1).substring(0, 12);
    final attempts = _streamLabOpenRoomRetryCounts[retryKey] ?? 0;
    if (attempts >= _streamLabOpenRoomRetryLimit) {
      Log.w(
        'Giving up stream-lab room open for $roomDiagnostic '
        'after $_streamLabOpenRoomRetryLimit attempts; reason=$reason',
        category: LogCategory.livekit,
        source: 'stream-lab-open-room',
      );
      _clearStreamLabOpenRoomRetry(room);
      return;
    }

    if (_streamLabOpenRoomRetryTimers.containsKey(retryKey)) {
      return;
    }

    if (attempts == 0) {
      Log.i(
        'Stream-lab room $roomDiagnostic is not ready yet; '
        'retrying room open; reason=$reason',
        category: LogCategory.livekit,
        source: 'stream-lab-open-room',
      );
    }

    _streamLabOpenRoomRetryCounts[retryKey] = attempts + 1;
    _streamLabOpenRoomRetryTimers[retryKey] = Timer(
      _streamLabOpenRoomRetryDelay,
      () {
        _streamLabOpenRoomRetryTimers.remove(retryKey);
        if (!mounted) {
          return;
        }
        EventBus.openRoomFromStreamLab(
          room,
          requestNonce: metadata?.requestNonce,
          roomHash: metadata?.roomHash,
        );
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

  void _clearStreamLabOpenRoomRetry((String, String?) room) {
    final retryKey = _streamLabOpenRoomRetryKey(room);
    _streamLabOpenRoomRetryCounts.remove(retryKey);
    _streamLabOpenRoomRetryTimers.remove(retryKey)?.cancel();
  }

  String _notificationOpenRoomRetryKey((String, String?) room) {
    return "${room.$2 ?? ''}\u0000${room.$1}";
  }

  String _streamLabOpenRoomRetryKey((String, String?) room) {
    return "stream-lab\u0000${room.$2 ?? ''}\u0000${room.$1}";
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
