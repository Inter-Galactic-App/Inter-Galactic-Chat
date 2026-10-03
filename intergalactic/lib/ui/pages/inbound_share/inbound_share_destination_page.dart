import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/ui/pages/inbound_share/inbound_share_destination_model.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class InboundShareDestinationPage extends StatefulWidget {
  const InboundShareDestinationPage({
    required this.destinations,
    required this.onSelected,
    required this.onCancelled,
    this.refreshDestinations,
    super.key,
  });

  final List<InboundShareDestination> destinations;

  /// Returns false when the destination became unwritable after it was listed.
  final bool Function(InboundShareDestination) onSelected;
  final VoidCallback onCancelled;
  final FutureOr<List<InboundShareDestination>> Function()? refreshDestinations;

  @override
  State<InboundShareDestinationPage> createState() =>
      _InboundShareDestinationPageState();
}

class _InboundShareDestinationPageState
    extends State<InboundShareDestinationPage> {
  String _query = '';
  late List<InboundShareDestination> _destinations;
  bool _refreshing = false;
  bool _destinationUnavailable = false;

  @override
  void initState() {
    super.initState();
    _destinations = widget.destinations;
  }

  Future<void> _refresh() async {
    final refreshDestinations = widget.refreshDestinations;
    if (refreshDestinations == null || _refreshing) return;
    setState(() => _refreshing = true);
    try {
      final refreshed = await Future.sync(refreshDestinations);
      if (mounted) {
        setState(() {
          _destinations = List.unmodifiable(refreshed);
          _destinationUnavailable = false;
        });
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _select(InboundShareDestination destination) {
    if (widget.onSelected(destination)) return;
    setState(() {
      _destinationUnavailable = true;
      _destinations = List.unmodifiable(
        _destinations.where((item) => !identical(item, destination)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = InboundShareDestinations.search(
      _destinations,
      _query,
      (destination, query) => destination.matches(query),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Share to Inter Galactic'),
        leading: IconButton(
          tooltip: 'Cancel share',
          icon: const Icon(Icons.close),
          onPressed: widget.onCancelled,
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Choose a conversation',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          if (_destinationUnavailable)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Semantics(
                liveRegion: true,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Conversation unavailable',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'That conversation can no longer receive this share. '
                          'Nothing was sent. Refresh or choose another conversation.',
                        ),
                        if (widget.refreshDestinations != null) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            onPressed: _refreshing ? null : _refresh,
                            icon: _refreshing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh),
                            label: const Text('Refresh'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
            child: visible.isEmpty
                ? _EmptyDestinations(
                    refreshing: _refreshing,
                    onRefresh:
                        widget.refreshDestinations == null ||
                            _destinationUnavailable
                        ? null
                        : _refresh,
                  )
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final destination = visible[index];
                      return Semantics(
                        label:
                            '${destination.roomName}, ${destination.conversationTypeLabel}, account ${destination.accountLabel}',
                        button: true,
                        child: ListTile(
                          title: Text(destination.roomName),
                          subtitle: Text(
                            '${destination.conversationTypeLabel} · ${destination.accountLabel}',
                          ),
                          // Show the room's own avatar, matching every other
                          // room list in the app. The generic visibility glyph
                          // made every row look alike, which is exactly the
                          // wrong thing in a picker whose only job is telling
                          // conversations apart. Falls back to the room's
                          // initial and colour when there is no avatar set,
                          // which is the same placeholder convention the rest
                          // of the app uses.
                          leading: tiamat.Avatar(
                            radius: 20,
                            image: destination.room.avatar,
                            placeholderText: destination.roomName,
                            placeholderColor: destination.room.defaultColor,
                          ),
                          onTap: () => _select(destination),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDestinations extends StatelessWidget {
  const _EmptyDestinations({required this.refreshing, this.onRefresh});

  final bool refreshing;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('No writable conversations found.'),
          if (onRefresh != null) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: refreshing ? null : onRefresh,
              icon: refreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ],
      ),
    );
  }
}
