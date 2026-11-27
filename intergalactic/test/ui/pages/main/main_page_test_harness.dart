// A mountable [MainPage] for widget tests.
//
// WHY THIS EXISTS
// ---------------
// `MainPage` owns room navigation for the whole app, and until now nothing
// could mount it in a test. Two user-visible defects went out behind that gap:
// the compact desktop rail overflowed (see `desktop_rail_layout_test.dart`,
// which pins arithmetic because it could not render the panel), and BUG-317,
// where opening a conversation from the Inbox selected the right room but
// never revealed the mobile timeline panel. Neither was findable without a
// mount, and the second was not even expressible - the only harness-free test
// shape passes against the defect.
//
// WHAT IT MODELS, AND WHAT IT REFUSES
// -----------------------------------
// `ClientManager` is concrete and cheap, so this uses the real one and
// registers fake clients into it - the registration path, its per-client
// stream subscriptions, and the room/space aggregation are therefore real.
// `Client`, `Room` and `Space` are abstract, so those are fakes that model
// only the slice `MainPage` reads. Everything outside that slice routes to
// `noSuchMethod` and throws, so a test that wanders into unmodelled territory
// fails loudly rather than reading a plausible default.
//
// The harness deliberately does not fake `MainPageState` itself. The whole
// point is that the state object under test is the real one.
//
// WHAT IT IS NOT FOR
// ------------------
// Pixel layout. Widget tests render with a fallback font whose metrics are not
// the shipped font's, so text-driven widths here are indicative at best. That
// is not hypothetical: at a 390-wide surface the direct-messages panel header
// in `main_page_view_mobile.dart` overflows by 28px under the test font,
// because its title `Text` sits in a `spaceBetween` Row with nothing
// constraining it. Whether that also happens on a real 390-wide device, or at
// a large text scale, is UNRESOLVED - it has not been reproduced on hardware.
// The default surface below is 430 wide so navigation tests are not blocked by
// it. Do not read that default as a finding that 390 is broken, and do not
// treat a green run here as evidence that it is fine.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/inbox/inbox_query.dart';
import 'package:intergalactic/client/components/push_notification/room_notification_snooze.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/client/permissions.dart';
import 'package:intergalactic/client/role.dart';
import 'package:intergalactic/client/room_event_settings.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/config/app_globals.dart';
import 'package:intergalactic/main.dart' as app_globals;
import 'package:intergalactic/utils/stored_stream_controller.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/ui/pages/main/main_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

/// The layout `MainPage.build` should take.
///
/// `Layout` reads `preferences.layoutOverride`, which is the only lever a test
/// has over it - `BuildConfig.MOBILE`/`DESKTOP` are compile-time.
enum HarnessLayout {
  mobile('mobile'),
  desktop('desktop');

  const HarnessLayout(this.preferenceValue);

  final String preferenceValue;
}

/// Everything a mounted [MainPage] test needs to make assertions.
class MainPageHarness {
  MainPageHarness._({
    required this.tester,
    required this.clientManager,
    required this.state,
  });

  final WidgetTester tester;
  final ClientManager clientManager;
  final MainPageState state;

  /// The ceiling on [openInboxSnapshotAndSettle]'s pump loop.
  ///
  /// Generous on purpose. `main_page.dart`'s retry budget is 12 attempts 50 ms
  /// apart, so this is roughly five times it: growing that budget should keep
  /// working here, and only a call that never settles should reach the bound.
  ///
  /// Worth knowing before reasoning about this number: in these tests the
  /// listener registers on the FIRST attempt, so the retry loop exits without
  /// consuming its budget. Raising `_inboxJumpListenerRetryLimit` therefore
  /// changes nothing here on its own - the bound bites when the call takes
  /// longer than the pump budget for any reason, which is why the failure
  /// message names both the budget and "waiting on something no pump drives".
  static const int _maxSettlePumps = 60;
  static const Duration _settlePumpInterval = Duration(milliseconds: 50);

  /// Runs an Inbox open to completion, pumping frames while it waits.
  ///
  /// DO NOT `await state.openInboxSnapshot(...)` directly in a test body. It
  /// awaits `SchedulerBinding.instance.endOfFrame` and a `Future.delayed` in a
  /// retry loop, and under `testWidgets`' fake clock neither completes unless
  /// something pumps - so the bare await deadlocks and the test hangs rather
  /// than failing.
  ///
  /// Two things here are deliberate, and both exist so a change in
  /// `main_page.dart` surfaces as a failure rather than as something else:
  ///
  ///  - The loop stops when the call settles instead of pumping a fixed count,
  ///    and fails loudly if it never does. Measured, with a 10 s delay added
  ///    to the head of `openInboxSnapshot`: the old fixed-16-pump version ran
  ///    6 m 32 s and reported all three tests as "did not complete", which
  ///    reads like a wedged tool rather than a failing assertion. This version
  ///    fails in about a second and names the cause.
  ///  - The listener is attached before the loop runs, not after. An
  ///    unlistened future that completes with an error mid-loop delivers that
  ///    error to the zone as an unhandled async error, which is reported
  ///    detached from the test that caused it; with a listener the error
  ///    arrives at the caller's `await`.
  Future<bool> openInboxSnapshotAndSettle(
    InboxRoomSnapshot snapshot,
    InboxEventSnapshot event,
  ) async {
    var settled = false;
    // One callback for both outcomes: the loop only needs to know that the
    // call is no longer in flight. `Object?` takes either the value or the
    // error, so neither outcome can reach the zone unhandled.
    void markSettled(Object? _) {
      settled = true;
    }

    final result = state.openInboxSnapshot(snapshot, event)
      ..then<void>(markSettled, onError: markSettled);

    for (var pumped = 0; pumped < _maxSettlePumps && !settled; pumped++) {
      await tester.pump(_settlePumpInterval);
    }

    if (!settled) {
      fail(
        'openInboxSnapshot did not settle within $_maxSettlePumps pumped '
        'frames (${_maxSettlePumps * _settlePumpInterval.inMilliseconds} ms '
        'of fake clock). Its retry budget in main_page.dart has probably '
        'outgrown this helper, or it is waiting on something no pump drives.',
      );
    }

    // Awaited, not just returned: the error the listener above absorbed is
    // still on this future, and this is where the caller should see it.
    return result;
  }

  FakeHarnessClient client(String identifier) {
    final match = clientManager.getClient(identifier);
    if (match is! FakeHarnessClient) {
      throw StateError('No fake client registered for "$identifier".');
    }
    return match;
  }
}

/// Initialises the globals `MainPage` reads before it can be built.
///
/// Call from `setUp`. `preferences` is a final global rather than an injected
/// dependency, so this mutates it in place; the layout override is reset by
/// [resetMainPageHarnessGlobals] so tests cannot leak a layout into each other.
Future<void> initMainPageHarnessGlobals({
  HarnessLayout layout = HarnessLayout.mobile,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(<String, Object>{});
  if (!preferences.isInit) {
    await preferences.init();
  }
  await preferences.layoutOverride.set(layout.preferenceValue);
}

/// Clears the layout override so the next test starts from a known state.
Future<void> resetMainPageHarnessGlobals() async {
  if (preferences.isInit) {
    await preferences.layoutOverride.set(null);
  }
}

/// Mounts a real [MainPage] over a real [ClientManager] holding [clients].
///
/// Returns once the first frame has settled. Pass [initialRoom]/[initialClientId]
/// to exercise the startup-target branch of `initState`.
Future<MainPageHarness> pumpMainPage(
  WidgetTester tester, {
  List<FakeHarnessClient> clients = const [],
  String? initialRoom,
  String? initialClientId,

  /// 430x932 by default - see the layout note in this file's header before
  /// narrowing it.
  Size surfaceSize = const Size(430, 932),
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final clientManager = ClientManager();
  for (final client in clients) {
    clientManager.addClient(client);
  }

  // `HeaderBurger` and other shell widgets reach for the `clientManager`
  // global with `!` rather than taking it from the widget tree, so the
  // Provider above is not enough on its own.
  final previousGlobal = app_globals.clientManager;
  app_globals.clientManager = clientManager;
  addTearDown(() => app_globals.clientManager = previousGlobal);

  await tester.pumpWidget(
    Provider<ClientManager>.value(
      value: clientManager,
      child: MaterialApp(
        theme: ThemeData.light().copyWith(
          extensions: const <ThemeExtension<dynamic>>[ThemeSettings()],
        ),
        // A Material ancestor, because the shell uses InkWell/InkResponse and
        // MaterialApp.home does not supply one on its own.
        home: Scaffold(
          body: MainPage(
            clientManager,
            initialRoom: initialRoom,
            initialClientId: initialClientId,
          ),
        ),
      ),
    ),
  );
  await tester.pump();

  return MainPageHarness._(
    tester: tester,
    clientManager: clientManager,
    state: tester.state<MainPageState>(find.byType(MainPage)),
  );
}

/// A [Client] that models only what `MainPage` reads from one.
///
/// Streams are broadcast controllers closed by [dispose] so a test that forgets
/// leaves no listener behind; `ClientManager.addClient` subscribes to six of
/// them, and an unclosed broadcast controller is the usual cause of a
/// `testWidgets` body that hangs in dispose rather than failing.
class FakeHarnessClient implements Client {
  FakeHarnessClient({
    required this.identifier,
    List<FakeHarnessRoom> rooms = const [],
    Profile? self,
  }) : _rooms = List<FakeHarnessRoom>.from(rooms) {
    // The room list and the room header both read `room.client.self!` without
    // a null guard, so a signed-in client is the only state that renders. A
    // test wanting the signed-out shell must pass a client with a null self
    // deliberately, not get there by forgetting.
    this.self = self ?? FakeHarnessProfile(identifier);
    for (final room in _rooms) {
      room.attach(this);
    }
  }

  @override
  final String identifier;

  @override
  Profile? self;

  final List<FakeHarnessRoom> _rooms;

  final StreamController<void> _onSelfUpdated =
      StreamController<void>.broadcast();
  final StreamController<void> _onSync = StreamController<void>.broadcast();
  final StreamController<int> _onRoomAdded = StreamController<int>.broadcast();
  final StreamController<int> _onRoomRemoved =
      StreamController<int>.broadcast();
  final StreamController<int> _onSpaceAdded = StreamController<int>.broadcast();
  final StreamController<int> _onSpaceRemoved =
      StreamController<int>.broadcast();
  final StreamController<int> _onPeerAdded = StreamController<int>.broadcast();

  @override
  List<Room> get rooms => _rooms;

  /// Populated only by the tests that need the space rail to have items in
  /// its ReorderableListView - see the rail tooltip test. Empty everywhere
  /// else, which is the quietest starting point for a navigation test.
  final List<FakeHarnessSpace> _spaces = [];

  @override
  List<Space> get spaces => _spaces;

  void addSpace(FakeHarnessSpace space) {
    space.attach(this);
    _spaces.add(space);
  }

  @override
  List<Room> get singleRooms => _rooms;

  @override
  List<Peer> get peers => const [];

  @override
  Stream<void> get onSelfUpdated => _onSelfUpdated.stream;

  @override
  Stream<void> get onSync => _onSync.stream;

  @override
  Stream<int> get onRoomAdded => _onRoomAdded.stream;

  @override
  Stream<int> get onRoomRemoved => _onRoomRemoved.stream;

  @override
  Stream<int> get onSpaceAdded => _onSpaceAdded.stream;

  @override
  Stream<int> get onSpaceRemoved => _onSpaceRemoved.stream;

  @override
  Stream<int> get onPeerAdded => _onPeerAdded.stream;

  @override
  bool get supportsE2EE => true;

  @override
  int? get maxFileSize => null;

  @override
  bool isLoggedIn() => true;

  /// Every component is absent.
  ///
  /// `ClientManager.addClient` drives `DirectMessagesAggregator` and
  /// `CallManager` straight into this, and both handle a null component - so
  /// absent is the honest default, and a test that needs a component should
  /// model that component rather than have the fake invent one.
  @override
  T? getComponent<T extends Component>() => null;

  @override
  final StoredStreamController<ClientConnectionStatusUpdate>
  connectionStatusChanged =
      StoredStreamController<ClientConnectionStatusUpdate>();

  @override
  bool hasRoom(String identifier) =>
      _rooms.any((room) => room.identifier == identifier);

  @override
  bool hasSpace(String identifier) => false;

  @override
  bool hasPeer(String identifier) => false;

  @override
  Room? getRoom(String identifier) {
    for (final room in _rooms) {
      if (room.identifier == identifier) {
        return room;
      }
    }
    return null;
  }

  Future<void> dispose() async {
    for (final room in _rooms) {
      await room.dispose();
    }
    await _onSelfUpdated.close();
    await _onSync.close();
    await _onRoomAdded.close();
    await _onRoomRemoved.close();
    await _onSpaceAdded.close();
    await _onSpaceRemoved.close();
    await _onPeerAdded.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      'FakeHarnessClient does not model ${invocation.memberName}. '
      'Add it to the harness rather than widening the fake at the call site.',
    );
  }
}

/// The [Profile] a signed-in [FakeHarnessClient] reports as its own.
class FakeHarnessProfile implements Profile {
  FakeHarnessProfile(this.identifier, {String? displayName})
    : displayName = displayName ?? identifier;

  @override
  final String identifier;

  @override
  final String displayName;

  @override
  String get userName => identifier;

  @override
  String? get detail => null;

  @override
  ImageProvider? get avatar => null;

  @override
  ImageProvider? get banner => null;

  @override
  Color get defaultColor => const Color(0xFF7F7F7F);

  @override
  String get source => 'harness';
}

/// An empty [Timeline] for a room that has no history in a test.
///
/// EXTENDS `Timeline`, which carries concrete event storage and the add/change/
/// remove controllers, so only the abstract members are supplied here.
class FakeHarnessTimeline extends Timeline {
  FakeHarnessTimeline({required Room room}) {
    this.room = room;
    client = room.client;
  }

  @override
  bool get isLoadingHistory => false;

  @override
  bool get isLoadingFuture => false;

  @override
  bool get canLoadFuture => false;

  @override
  bool get canLoadHistory => false;

  @override
  Stream<void> get onLoadingStatusChanged => const Stream<void>.empty();

  @override
  void markAsRead(TimelineEvent event) {}

  @override
  Future<void> loadMoreHistory() async {}

  @override
  Future<void> loadMoreFuture() async {}

  @override
  Future<TimelineEvent?> fetchEventByIdInternal(String eventId) async => null;

  @override
  bool canDeleteEvent(TimelineEvent event) => false;

  @override
  void deleteEvent(TimelineEvent event) {}

  @override
  bool isEventRedacted(TimelineEvent event) => false;

  @override
  Future<void> close() async {
    await onEventAdded.close();
    await onChange.close();
    await onRemove.close();
  }
}

/// A read-only member's permissions.
///
/// `Permissions` defaults every capability to false, so this EXTENDS it rather
/// than implementing it - extending keeps those defaults, implementing would
/// strip them and send each one to noSuchMethod.
class FakeHarnessPermissions extends Permissions {}

/// A [Room] that models only the slice the room list and room selection read.
///
/// Anything not listed here throws through [noSuchMethod]. When a new test
/// needs another member, add it here with a deliberate value rather than
/// letting the fake invent one - a fake that answers everything plausibly is
/// how a test ends up green against the defect it was written for.
class FakeHarnessRoom implements Room {
  FakeHarnessRoom({
    required this.identifier,
    String? displayName,
    this.notificationCount = 0,
    this.highlightedNotificationCount = 0,
    this.hasRoomWideMentionNotification = false,
    this.pushRule = PushRule.notify,
    DateTime? lastEventTimestamp,
  }) : displayName = displayName ?? identifier,
       lastEventTimestamp = lastEventTimestamp ?? DateTime(2026);

  @override
  final String identifier;

  @override
  final String displayName;

  /// Mutable, unlike the fields above it: a rail that only ever sees its
  /// unread state at construction time cannot be asked the question that
  /// matters, which is whether it notices a message arriving while it is on
  /// screen. Change one and call [emitUpdate].
  @override
  int notificationCount;

  @override
  int highlightedNotificationCount;

  @override
  bool hasRoomWideMentionNotification;

  @override
  PushRule pushRule;

  @override
  final DateTime lastEventTimestamp;

  final StreamController<void> _onUpdate = StreamController<void>.broadcast();

  FakeHarnessClient? _client;

  void attach(FakeHarnessClient client) => _client = client;

  @override
  Client get client {
    final attached = _client;
    if (attached == null) {
      throw StateError('FakeHarnessRoom "$identifier" was never attached.');
    }
    return attached;
  }

  @override
  Stream<void> get onUpdate => _onUpdate.stream;

  /// Null keeps this room out of the recent-activity list, which is the
  /// quietest starting point for a navigation test.
  @override
  TimelineEvent? get lastEvent => null;

  @override
  Timeline? get timeline => null;

  @override
  ImageProvider? get avatar => null;

  @override
  String? get avatarId => null;

  @override
  String? get topic => null;

  @override
  Iterable<String> get memberIds => const [];

  @override
  bool get isE2EE => false;

  @override
  bool get isSpecialRoomType => false;

  @override
  bool get shouldPreviewMedia => true;

  @override
  bool get isMembersListComplete => true;

  @override
  Color get defaultColor => const Color(0xFF7F7F7F);

  @override
  String get developerInfo => identifier;

  @override
  final Permissions permissions = FakeHarnessPermissions();

  // A fresh growable list each call: the members list mutates what it is
  // handed, so a `const []` here fails with "Cannot remove from an
  // unmodifiable list" rather than rendering empty.
  @override
  List<Member> membersList() => <Member>[];

  @override
  List<(Member, Role)> importantMembers() => <(Member, Role)>[];

  @override
  List<Role> get availableRoles => const [];

  FakeHarnessTimeline? _timeline;

  @override
  Future<Timeline> getTimeline({String contextEventId = ''}) async =>
      _timeline ??= FakeHarnessTimeline(room: this);

  /// Every room component is absent - this room is a plain text room.
  @override
  T? getComponent<T extends RoomComponent>() => null;

  // Everything below has a default implementation on `Room`, and `implements`
  // does not inherit those - so each one must be restated here or it reaches
  // noSuchMethod and throws. This is the single most common way a fake in this
  // codebase surprises whoever wrote it.

  @override
  String get localId => '${client.identifier}:$identifier';

  @override
  String get favoriteStorageId {
    final userId = client.self?.identifier;
    if (userId == null || userId.isEmpty || userId == 'Error') {
      return localId;
    }
    return '$userId:$identifier';
  }

  @override
  IconData get icon => Icons.tag;

  @override
  int get displayNotificationCount =>
      pushRule == PushRule.notify ? notificationCount : 0;

  @override
  int get displayHighlightedNotificationCount =>
      pushRule != PushRule.dontNotify ? highlightedNotificationCount : 0;

  @override
  bool get displayRoomWideMentionNotification =>
      pushRule != PushRule.dontNotify && hasRoomWideMentionNotification;

  @override
  RoomEventSettings get roomEventSettings => const RoomEventSettings();

  @override
  RoomNotificationSnooze? get notificationSnooze => null;

  /// Fires the room's update stream, the way a real room does when a message
  /// lands or is read elsewhere.
  void emitUpdate() => _onUpdate.add(null);

  Future<void> dispose() async {
    await _timeline?.close();
    await _onUpdate.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      'FakeHarnessRoom does not model ${invocation.memberName}. '
      'Add it to the harness rather than widening the fake at the call site.',
    );
  }
}

/// A [Space] that models only what the space rail reads from one.
///
/// EXTENDS rather than implements: `Space` computes its notification counts
/// from `roomsWithChildren` and `pushRule` in concrete getters, and
/// `implements` would leave those unimplemented and force this fake to restate
/// the aggregation it is meant to be standing in for.
class FakeHarnessSpace extends Space {
  FakeHarnessSpace({
    required this.identifier,
    String? displayName,
    List<FakeHarnessRoom> rooms = const [],
    this.pushRule = PushRule.notify,
  }) : displayName = displayName ?? identifier,
       _rooms = List<FakeHarnessRoom>.from(rooms);

  @override
  final String identifier;

  @override
  final String displayName;

  @override
  PushRule pushRule;

  final List<FakeHarnessRoom> _rooms;

  final StreamController<void> _onUpdate = StreamController<void>.broadcast();

  FakeHarnessClient? _client;

  void attach(FakeHarnessClient client) {
    _client = client;
    for (final room in _rooms) {
      room.attach(client);
    }
  }

  @override
  Client get client {
    final attached = _client;
    if (attached == null) {
      throw StateError('FakeHarnessSpace "$identifier" was never attached.');
    }
    return attached;
  }

  @override
  List<Room> get rooms => _rooms;

  @override
  List<Space> get subspaces => const [];

  @override
  bool get isTopLevel => true;

  @override
  ImageProvider? get avatar => null;

  @override
  Color get color => const Color(0xFF5C56F5);

  @override
  Stream<void> get onUpdate => _onUpdate.stream;

  /// ClientManager.addClient subscribes to this on every space it adds - see
  /// _addSpace - so it must exist even though nothing in this harness fires it.
  @override
  Stream<Room> get onChildRoomUpdated => const Stream<Room>.empty();

  void emitUpdate() => _onUpdate.add(null);

  Future<void> dispose() async => _onUpdate.close();

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      'FakeHarnessSpace does not model ${invocation.memberName}. '
      'Add it to the harness rather than widening the fake at the call site.',
    );
  }
}
