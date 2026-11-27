import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';

enum DesktopNavigationDestinationType { home, favorites, space, room }

@immutable
class DesktopNavigationEntry {
  const DesktopNavigationEntry._(
    this.type, {
    this.clientId,
    this.spaceId,
    this.roomId,
    this.bypassSpecialRoomType = false,
  });

  const DesktopNavigationEntry.home()
    : this._(DesktopNavigationDestinationType.home);

  const DesktopNavigationEntry.favorites()
    : this._(DesktopNavigationDestinationType.favorites);

  const DesktopNavigationEntry.space({
    required String clientId,
    required String spaceId,
  }) : this._(
         DesktopNavigationDestinationType.space,
         clientId: clientId,
         spaceId: spaceId,
       );

  const DesktopNavigationEntry.room({
    required String clientId,
    required String roomId,
    bool bypassSpecialRoomType = false,
  }) : this._(
         DesktopNavigationDestinationType.room,
         clientId: clientId,
         roomId: roomId,
         bypassSpecialRoomType: bypassSpecialRoomType,
       );

  final DesktopNavigationDestinationType type;
  final String? clientId;
  final String? spaceId;
  final String? roomId;
  final bool bypassSpecialRoomType;

  @override
  bool operator ==(Object other) {
    return other is DesktopNavigationEntry &&
        other.type == type &&
        other.clientId == clientId &&
        other.spaceId == spaceId &&
        other.roomId == roomId &&
        other.bypassSpecialRoomType == bypassSpecialRoomType;
  }

  @override
  int get hashCode =>
      Object.hash(type, clientId, spaceId, roomId, bypassSpecialRoomType);
}

class DesktopNavigationHistoryController extends ChangeNotifier {
  DesktopNavigationHistoryController({int maxEntries = 80})
    : _maxEntries = maxEntries;

  static final DesktopNavigationHistoryController instance =
      DesktopNavigationHistoryController();

  final int _maxEntries;
  final ListQueue<DesktopNavigationEntry> _backStack = ListQueue();
  final ListQueue<DesktopNavigationEntry> _forwardStack = ListQueue();
  final StreamController<DesktopNavigationEntry> _requests =
      StreamController<DesktopNavigationEntry>.broadcast();

  DesktopNavigationEntry? _current;

  Stream<DesktopNavigationEntry> get requests => _requests.stream;

  DesktopNavigationEntry? get current => _current;
  bool get canGoBack => _backStack.isNotEmpty;
  bool get canGoForward => _forwardStack.isNotEmpty;

  void record(DesktopNavigationEntry entry) {
    if (_current == entry) {
      return;
    }

    final previous = _current;
    if (previous != null) {
      _backStack.addLast(previous);
      _trimBackStack();
    }

    _current = entry;
    _forwardStack.clear();
    notifyListeners();
  }

  void reset() {
    if (_current == null && _backStack.isEmpty && _forwardStack.isEmpty) {
      return;
    }

    _current = null;
    _backStack.clear();
    _forwardStack.clear();
    notifyListeners();
  }

  void restoreCurrent(DesktopNavigationEntry? entry) {
    if (entry == null) {
      reset();
      return;
    }

    _current = entry;
    _backStack.removeWhere((candidate) => candidate == entry);
    _forwardStack.removeWhere((candidate) => candidate == entry);
    notifyListeners();
  }

  void goBack() {
    if (!canGoBack) {
      return;
    }

    final next = _backStack.removeLast();
    final current = _current;
    if (current != null) {
      _forwardStack.addLast(current);
    }
    _current = next;
    notifyListeners();
    _requests.add(next);
  }

  void goForward() {
    if (!canGoForward) {
      return;
    }

    final next = _forwardStack.removeLast();
    final current = _current;
    if (current != null) {
      _backStack.addLast(current);
      _trimBackStack();
    }
    _current = next;
    notifyListeners();
    _requests.add(next);
  }

  void _trimBackStack() {
    while (_backStack.length > _maxEntries) {
      _backStack.removeFirst();
    }
  }

  @override
  void dispose() {
    _requests.close();
    super.dispose();
  }
}

class DesktopRouteStackController extends NavigatorObserver
    with ChangeNotifier {
  static final DesktopRouteStackController instance =
      DesktopRouteStackController();

  bool _canPop = false;

  bool get canPop => _canPop;

  void refresh() {
    final next = navigator?.canPop() ?? false;
    if (next == _canPop) {
      return;
    }

    _canPop = next;
    notifyListeners();
  }

  void _refreshSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) => refresh());
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _refreshSoon();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _refreshSoon();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _refreshSoon();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _refreshSoon();
  }
}
