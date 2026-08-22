import 'package:flutter/foundation.dart';

import 'server_discovery_cache.dart';
import 'server_discovery_models.dart';
import 'server_discovery_service.dart';

enum _PublicationUpdateAction { publish, unpublish }

class ServerDiscoveryPublicationController extends ChangeNotifier {
  ServerDiscoveryPublicationController({
    required this.service,
    required this.target,
    ServerDiscoveryPageCache? cache,
  }) : cache = cache ?? ServerDiscoveryCacheRegistry.instance;

  final ServerDiscoveryService service;
  final ServerDiscoveryPublicationTarget target;
  final ServerDiscoveryPageCache cache;

  ServerDiscoveryPublicationState? _state;
  ServerDiscoveryPublicationResult? _lastResult;
  bool _loading = false;
  bool _updating = false;
  Future<ServerDiscoveryPublicationResult>? _inFlightUpdate;
  _PublicationUpdateAction? _inFlightAction;

  ServerDiscoveryPublicationState? get state => _state;

  ServerDiscoveryPublicationResult? get lastResult => _lastResult;

  bool get isLoading => _loading;

  bool get isUpdating => _updating;

  bool get isPublished => _state?.isPublished == true;

  bool get canManage => _state?.canManage ?? target.canManage;

  Future<void> refresh() async {
    _loading = true;
    notifyListeners();
    try {
      _state = await service.getPublicationState(target);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<ServerDiscoveryPublicationResult> publish() {
    return _update(
      _PublicationUpdateAction.publish,
      () => service.publish(target),
    );
  }

  Future<ServerDiscoveryPublicationResult> unpublish() {
    return _update(
      _PublicationUpdateAction.unpublish,
      () => service.unpublish(target),
    );
  }

  Future<ServerDiscoveryPublicationResult> _update(
    _PublicationUpdateAction updateAction,
    Future<ServerDiscoveryPublicationResult> Function() action,
  ) {
    final inFlight = _inFlightUpdate;
    if (inFlight != null) {
      if (_inFlightAction == updateAction) {
        return inFlight;
      }
      return Future<ServerDiscoveryPublicationResult>.error(StateError(
        'Cannot ${updateAction.name} while '
        '${_inFlightAction?.name ?? 'another publication action'} is in progress.',
      ));
    }

    _updating = true;
    _inFlightAction = updateAction;
    final future = Future<ServerDiscoveryPublicationResult>(() async {
      try {
        final result = await action();
        _lastResult = result;
        if (result.state != null) {
          _state = result.state;
        }
        if (result.success) {
          cache.invalidateScope(service.scope);
        }
        return result;
      } finally {
        _updating = false;
        _inFlightUpdate = null;
        _inFlightAction = null;
        notifyListeners();
      }
    });
    _inFlightUpdate = future;
    notifyListeners();
    return future;
  }
}
