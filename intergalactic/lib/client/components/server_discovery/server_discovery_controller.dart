import 'package:flutter/foundation.dart';

import 'server_discovery_cache.dart';
import 'server_discovery_models.dart';
import 'server_discovery_service.dart';

class ServerDiscoveryController extends ChangeNotifier {
  ServerDiscoveryController({
    required this.service,
    ServerDiscoveryPageCache? cache,
    this.pageSize = 20,
  }) : cache = cache ?? ServerDiscoveryCacheRegistry.instance;

  final ServerDiscoveryService service;
  final ServerDiscoveryPageCache cache;
  final int pageSize;

  final List<ServerDiscoveryEntry> _entries = [];
  String _query = '';
  ServerDiscoveryFilter _filter = ServerDiscoveryFilter.all;
  ServerDiscoveryAccessFilter _accessFilter = ServerDiscoveryAccessFilter.all;
  ServerDiscoverySortMode _sortMode = ServerDiscoverySortMode.defaultOrder;
  String? _nextBatch;
  int? _totalEstimate;
  ServerDiscoveryError? _error;
  bool _loading = false;
  bool _loadingMore = false;
  int _generation = 0;
  ServerDiscoveryRequest? _lastRequest;

  ServerDiscoveryScope get scope => service.scope;

  List<ServerDiscoveryEntry> get entries {
    final visibleEntries = _entries
        .where(_matchesAccessFilter)
        .toList(growable: false);
    _sortEntries(visibleEntries);
    return List.unmodifiable(visibleEntries);
  }

  String get query => _query;

  ServerDiscoveryFilter get filter => _filter;

  ServerDiscoveryAccessFilter get accessFilter => _accessFilter;

  ServerDiscoverySortMode get sortMode => _sortMode;

  String? get nextBatch => _nextBatch;

  int? get totalEstimate => _totalEstimate;

  ServerDiscoveryError? get error => _error;

  bool get isLoading => _loading;

  bool get isLoadingMore => _loadingMore;

  bool get hasMore => _nextBatch != null && _nextBatch!.isNotEmpty;

  bool get isEmpty => !_loading && _error == null && entries.isEmpty;

  Future<void> loadInitial({bool preferCache = true}) {
    final request = ServerDiscoveryRequest(
      query: _query,
      filter: _filter,
      limit: pageSize,
    );
    return _load(request, replace: true, preferCache: preferCache);
  }

  Future<void> setQuery(String value) {
    final normalized = value.trim();
    if (normalized == _query) {
      return Future.value();
    }
    _query = normalized;
    return loadInitial();
  }

  Future<void> setFilter(ServerDiscoveryFilter value) {
    if (value == _filter) {
      return Future.value();
    }
    _filter = value;
    return loadInitial();
  }

  Future<void> setAccessFilter(ServerDiscoveryAccessFilter value) {
    if (value == _accessFilter) {
      return Future.value();
    }
    _accessFilter = value;
    notifyListeners();
    return Future.value();
  }

  Future<void> setSortMode(ServerDiscoverySortMode value) {
    if (value == _sortMode) {
      return Future.value();
    }
    _sortMode = value;
    notifyListeners();
    return Future.value();
  }

  Future<void> refresh() {
    cache.invalidateQuery(scope: scope, query: _query, filter: _filter);
    return loadInitial(preferCache: false);
  }

  Future<void> retry() {
    final request =
        _lastRequest ??
        ServerDiscoveryRequest(query: _query, filter: _filter, limit: pageSize);
    return _load(request, replace: request.since == null, preferCache: false);
  }

  Future<void> loadMore() {
    final since = _nextBatch;
    if (since == null || since.isEmpty || _loading || _loadingMore) {
      return Future.value();
    }
    final request = ServerDiscoveryRequest(
      query: _query,
      filter: _filter,
      since: since,
      limit: pageSize,
    );
    return _load(request, replace: false);
  }

  Future<ServerDiscoveryJoinResult> join(ServerDiscoveryEntry entry) async {
    if (!entry.belongsToScope(scope)) {
      return const ServerDiscoveryJoinResult(
        outcome: ServerDiscoveryJoinOutcome.staleEntry,
      );
    }

    final result = await service.join(entry);
    if (result.outcome == ServerDiscoveryJoinOutcome.joined ||
        result.outcome == ServerDiscoveryJoinOutcome.alreadyJoined) {
      cache.invalidateScope(scope);
      final index = _entries.indexWhere((item) => item.roomId == entry.roomId);
      if (index != -1) {
        _entries[index] = entry.copyWith(alreadyJoined: true);
        notifyListeners();
      }
    }
    return result;
  }

  Future<void> _load(
    ServerDiscoveryRequest request, {
    required bool replace,
    bool preferCache = true,
  }) async {
    final generation = ++_generation;
    _lastRequest = request;

    if (preferCache) {
      final cached = cache.read(scope: scope, request: request);
      if (cached != null) {
        final page = await _withSupplementalEntries(cached);
        if (generation == _generation) {
          _applyPage(page, replace: replace);
        }
        return;
      }
    }

    if (replace) {
      _loading = true;
    } else {
      _loadingMore = true;
    }
    _error = null;
    notifyListeners();

    try {
      final page = await service.fetchPage(request);
      if (generation != _generation) {
        return;
      }
      final pageWithSupplemental = await _withSupplementalEntries(page);
      if (generation != _generation) {
        return;
      }
      cache.store(pageWithSupplemental);
      _applyPage(pageWithSupplemental, replace: replace);
    } on ServerDiscoveryError catch (error) {
      if (generation != _generation) {
        return;
      }
      _error = error;
      if (error.kind == ServerDiscoveryFailureKind.authenticationInvalid) {
        cache.invalidateScope(scope);
      }
    } catch (_) {
      if (generation != _generation) {
        return;
      }
      _error = const ServerDiscoveryError(
        kind: ServerDiscoveryFailureKind.unknown,
        message: 'Could not load Discover results.',
      );
    } finally {
      if (generation == _generation) {
        _loading = false;
        _loadingMore = false;
        notifyListeners();
      }
    }
  }

  void _applyPage(ServerDiscoveryPage page, {required bool replace}) {
    final scopedEntries = page.entries
        .where((entry) => entry.belongsToScope(scope))
        .toList(growable: false);
    final nextEntries = replace
        ? _dedupeEntries(scopedEntries)
        : _mergeEntries(_entries, scopedEntries);
    if (replace) {
      _entries
        ..clear()
        ..addAll(nextEntries);
    } else {
      _entries
        ..clear()
        ..addAll(nextEntries);
    }
    _nextBatch = page.nextBatch;
    _totalEstimate = page.totalEstimate;
    _error = null;
    _loading = false;
    _loadingMore = false;
    notifyListeners();
  }

  Future<ServerDiscoveryPage> _withSupplementalEntries(
    ServerDiscoveryPage page,
  ) async {
    if (page.request.since != null) {
      return page;
    }

    final directoryEntries = page.entries
        .where((entry) => entry.source == ServerDiscoveryEntrySource.directory)
        .toList(growable: false);

    try {
      if (service is! ServerDiscoverySupplementalService) {
        if (directoryEntries.length == page.entries.length) {
          return page;
        }
        return _copyPageWithEntries(page, directoryEntries);
      }
      final supplementalService = service as ServerDiscoverySupplementalService;
      final supplementalEntries = _entriesWithSpaceGroupOrder(
        await supplementalService.fetchSupplementalEntries(page.request),
      );
      if (supplementalEntries.isEmpty) {
        if (directoryEntries.length == page.entries.length) {
          return page;
        }
        return _copyPageWithEntries(page, directoryEntries);
      }
      final entries = _mergeEntries(directoryEntries, supplementalEntries);
      return _copyPageWithEntries(page, entries);
    } catch (_) {
      if (directoryEntries.length == page.entries.length) {
        return page;
      }
      return _copyPageWithEntries(page, directoryEntries);
    }
  }

  ServerDiscoveryPage _copyPageWithEntries(
    ServerDiscoveryPage page,
    List<ServerDiscoveryEntry> entries,
  ) {
    return ServerDiscoveryPage(
      scope: page.scope,
      request: page.request,
      entries: entries,
      nextBatch: page.nextBatch,
      prevBatch: page.prevBatch,
      totalEstimate: _mergedTotalEstimate(page.totalEstimate, entries.length),
    );
  }

  List<ServerDiscoveryEntry> _dedupeEntries(
    Iterable<ServerDiscoveryEntry> entries,
  ) {
    return _mergeEntries(const [], entries);
  }

  List<ServerDiscoveryEntry> _mergeEntries(
    Iterable<ServerDiscoveryEntry> existing,
    Iterable<ServerDiscoveryEntry> incoming,
  ) {
    final merged = <ServerDiscoveryEntry>[];
    final indexesByRoomId = <String, int>{};

    void add(ServerDiscoveryEntry entry) {
      final roomId = entry.roomId;
      final index = indexesByRoomId[roomId];
      if (index == null) {
        indexesByRoomId[roomId] = merged.length;
        merged.add(entry);
        return;
      }

      final previous = merged[index];
      if (previous.source == ServerDiscoveryEntrySource.directory &&
          entry.source != ServerDiscoveryEntrySource.directory) {
        merged[index] = _directoryEntryWithSupplementalFallback(
          previous,
          entry,
        );
      } else if (previous.source != ServerDiscoveryEntrySource.directory &&
          entry.source == ServerDiscoveryEntrySource.directory) {
        merged[index] = _directoryEntryWithSupplementalFallback(
          entry,
          previous,
        );
      }
    }

    existing.forEach(add);
    incoming.forEach(add);
    return List.unmodifiable(merged);
  }

  ServerDiscoveryEntry _directoryEntryWithSupplementalFallback(
    ServerDiscoveryEntry directoryEntry,
    ServerDiscoveryEntry supplementalEntry,
  ) {
    return directoryEntry.copyWith(
      avatarUrl: directoryEntry.avatarUrl ?? supplementalEntry.avatarUrl,
      via: directoryEntry.via.isEmpty ? supplementalEntry.via : null,
      parentSpaceId:
          directoryEntry.parentSpaceId ?? supplementalEntry.parentSpaceId,
      parentSpaceName:
          directoryEntry.parentSpaceName ?? supplementalEntry.parentSpaceName,
      spaceGroupOrder:
          directoryEntry.spaceGroupOrder ?? supplementalEntry.spaceGroupOrder,
    );
  }

  List<ServerDiscoveryEntry> _entriesWithSpaceGroupOrder(
    Iterable<ServerDiscoveryEntry> entries,
  ) {
    final groupOrder = <String, int>{};
    return entries
        .map((entry) {
          if (!_isGroupedSpaceEntry(entry)) {
            return entry;
          }
          final order = groupOrder.putIfAbsent(
            _spaceGroupId(entry),
            () => groupOrder.length,
          );
          return entry.copyWith(spaceGroupOrder: order);
        })
        .toList(growable: false);
  }

  int? _mergedTotalEstimate(int? totalEstimate, int entryCount) {
    if (totalEstimate == null) {
      return null;
    }
    return totalEstimate < entryCount ? entryCount : totalEstimate;
  }

  bool _matchesAccessFilter(ServerDiscoveryEntry entry) {
    return switch (_accessFilter) {
      ServerDiscoveryAccessFilter.all => true,
      ServerDiscoveryAccessFilter.unjoined => !entry.alreadyJoined,
    };
  }

  void _sortEntries(List<ServerDiscoveryEntry> entries) {
    switch (_sortMode) {
      case ServerDiscoverySortMode.defaultOrder:
        return;
      case ServerDiscoverySortMode.alphabetical:
        entries.sort(_compareByName);
        return;
      case ServerDiscoverySortMode.space:
        final groupOrder = _spaceGroupOrder(entries);
        entries.sort((a, b) => _compareBySpaceGroup(a, b, groupOrder));
        return;
      case ServerDiscoverySortMode.joinedStatus:
        entries.sort((a, b) {
          final joinedCompare = _joinedSortRank(
            a,
          ).compareTo(_joinedSortRank(b));
          if (joinedCompare != 0) {
            return joinedCompare;
          }
          return _compareByName(a, b);
        });
        return;
    }
  }

  int _compareByName(ServerDiscoveryEntry a, ServerDiscoveryEntry b) {
    final nameCompare = a.displayName.toLowerCase().compareTo(
      b.displayName.toLowerCase(),
    );
    if (nameCompare != 0) {
      return nameCompare;
    }
    final aliasCompare = (a.canonicalAlias ?? '').toLowerCase().compareTo(
      (b.canonicalAlias ?? '').toLowerCase(),
    );
    if (aliasCompare != 0) {
      return aliasCompare;
    }
    return a.roomId.compareTo(b.roomId);
  }

  int _compareBySpaceGroup(
    ServerDiscoveryEntry a,
    ServerDiscoveryEntry b,
    Map<String, int> groupOrder,
  ) {
    final groupCompare = _spaceGroupSortRank(
      a,
    ).compareTo(_spaceGroupSortRank(b));
    if (groupCompare != 0) {
      return groupCompare;
    }

    if (_spaceGroupSortRank(a) != 0) {
      return _compareByName(a, b);
    }

    final orderCompare = (_spaceGroupOrderRank(
      a,
      groupOrder,
    )).compareTo(_spaceGroupOrderRank(b, groupOrder));
    if (orderCompare != 0) {
      return orderCompare;
    }

    final labelCompare = _spaceGroupLabel(a).compareTo(_spaceGroupLabel(b));
    if (labelCompare != 0) {
      return labelCompare;
    }

    final idCompare = _spaceGroupId(a).compareTo(_spaceGroupId(b));
    if (idCompare != 0) {
      return idCompare;
    }

    final rowCompare = _spaceGroupRowRank(a).compareTo(_spaceGroupRowRank(b));
    if (rowCompare != 0) {
      return rowCompare;
    }

    return _compareByName(a, b);
  }

  Map<String, int> _spaceGroupOrder(Iterable<ServerDiscoveryEntry> entries) {
    final order = <String, int>{};
    final hintedEntries =
        entries
            .where((entry) => entry.spaceGroupOrder != null)
            .toList(growable: false)
          ..sort((a, b) => a.spaceGroupOrder!.compareTo(b.spaceGroupOrder!));

    for (final entry in hintedEntries) {
      order.putIfAbsent(_spaceGroupId(entry), () => order.length);
    }

    for (final entry in entries) {
      if (entry.parentSpaceId == null && entry.parentSpaceName == null) {
        continue;
      }
      order.putIfAbsent(_spaceGroupId(entry), () => order.length);
    }

    for (final entry in entries) {
      if (entry.type != ServerDiscoveryEntryType.space) {
        continue;
      }
      order.putIfAbsent(_spaceGroupId(entry), () => order.length);
    }

    return order;
  }

  int _spaceGroupOrderRank(
    ServerDiscoveryEntry entry,
    Map<String, int> groupOrder,
  ) {
    return groupOrder[_spaceGroupId(entry)] ?? groupOrder.length;
  }

  int _spaceGroupSortRank(ServerDiscoveryEntry entry) {
    return _isGroupedSpaceEntry(entry) ? 0 : 1;
  }

  bool _isGroupedSpaceEntry(ServerDiscoveryEntry entry) {
    return entry.type == ServerDiscoveryEntryType.space ||
        entry.parentSpaceId != null ||
        entry.parentSpaceName != null;
  }

  String _spaceGroupLabel(ServerDiscoveryEntry entry) {
    final label = entry.type == ServerDiscoveryEntryType.space
        ? entry.displayName
        : entry.parentSpaceName ?? entry.parentSpaceId ?? entry.displayName;
    return label.toLowerCase();
  }

  String _spaceGroupId(ServerDiscoveryEntry entry) {
    return (entry.type == ServerDiscoveryEntryType.space
            ? entry.roomId
            : entry.parentSpaceId ?? entry.parentSpaceName ?? '')
        .toLowerCase();
  }

  int _spaceGroupRowRank(ServerDiscoveryEntry entry) {
    return entry.type == ServerDiscoveryEntryType.space ? 0 : 1;
  }

  int _joinedSortRank(ServerDiscoveryEntry entry) {
    return entry.alreadyJoined ? 1 : 0;
  }
}
