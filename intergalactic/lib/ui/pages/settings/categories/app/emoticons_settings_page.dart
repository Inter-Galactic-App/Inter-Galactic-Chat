import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_component.dart';
import 'package:intergalactic/client/components/emoticon_recent/recent_emoticon_component.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/account_emoji/account_emoji_view.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/account_emoji/account_quick_reactions_view.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/room_emoji_pack_settings_view.dart';
import 'package:intergalactic/ui/pages/settings/settings_account_scope.dart';

class EmoticonsSettingsPage extends StatefulWidget {
  const EmoticonsSettingsPage({required this.clientManager, super.key});

  final ClientManager clientManager;

  @override
  State<EmoticonsSettingsPage> createState() => _EmoticonsSettingsPageState();
}

class _EmoticonsSettingsPageState extends State<EmoticonsSettingsPage> {
  Client? _selectedClient;
  EmoticonComponent? _component;
  RecentEmoticonComponent? _recentEmoticonComponent;
  StreamSubscription? _componentSubscription;
  final List<StreamSubscription> _clientManagerSubscriptions = [];

  @override
  void initState() {
    super.initState();
    _selectedClient = SettingsAccountController.resolvePreferredClient(
      widget.clientManager,
    );
    _syncComponents();
    _subscribeToClientManager();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scopedClient = SettingsAccountScope.selectedClientOf(
      context,
      widget.clientManager,
    );
    if (!identical(scopedClient, _selectedClient)) {
      _selectedClient = scopedClient;
      _syncComponents();
    }
  }

  @override
  void didUpdateWidget(covariant EmoticonsSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clientManager == widget.clientManager) {
      return;
    }
    _cancelClientManagerSubscriptions();
    _selectedClient = SettingsAccountController.resolvePreferredClient(
      widget.clientManager,
    );
    _syncComponents();
    _subscribeToClientManager();
  }

  @override
  void dispose() {
    unawaited(_componentSubscription?.cancel());
    _componentSubscription = null;
    _cancelClientManagerSubscriptions();
    super.dispose();
  }

  void _subscribeToClientManager() {
    _clientManagerSubscriptions.addAll([
      widget.clientManager.onRoomAdded.listen((_) => _refresh()),
      widget.clientManager.onRoomRemoved.listen((_) => _refresh()),
      widget.clientManager.onSpaceAdded.listen((_) => _refresh()),
      widget.clientManager.onSpaceRemoved.listen((_) => _refresh()),
      widget.clientManager.onSpaceUpdated.stream.listen((_) => _refresh()),
    ]);
  }

  void _cancelClientManagerSubscriptions() {
    for (final subscription in _clientManagerSubscriptions) {
      unawaited(subscription.cancel());
    }
    _clientManagerSubscriptions.clear();
  }

  void _refresh() {
    if (!mounted) {
      return;
    }

    setState(() {
      final previousSelectedClient = _selectedClient;
      if (_selectedClient != null &&
          !widget.clientManager.clients.contains(_selectedClient)) {
        _selectedClient = SettingsAccountController.resolvePreferredClient(
          widget.clientManager,
        );
      }
      _syncComponents(resubscribe: previousSelectedClient != _selectedClient);
    });
  }

  void _syncComponents({bool resubscribe = true}) {
    final selectedClient = _selectedClient;
    _component = selectedClient?.getComponent<EmoticonComponent>();
    _recentEmoticonComponent = selectedClient
        ?.getComponent<RecentEmoticonComponent>();

    if (!resubscribe) {
      return;
    }

    _componentSubscription?.cancel();
    _componentSubscription = _component?.onStateChanged.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedClient = _selectedClient;
    final component = _component;

    if (selectedClient == null || component == null) {
      return SettingsSection(
        title: 'Emoticons',
        showDivider: false,
        children: const [
          SettingsControlRow(
            title: 'No account selected',
            description:
                'Sign in to manage quick reactions, favorite packs, and emoji packs from joined rooms and spaces.',
          ),
        ],
      );
    }

    final recentEmoticons = _recentEmoticonComponent;
    final availablePacks = collectJoinedEmoticonPacks(selectedClient);
    final globalPacks = component.globalPacks();
    final pickerPacks = <String, EmoticonPack>{
      for (final pack in component.availablePacks) pack.orderKey: pack,
      for (final summary in availablePacks) summary.pack.orderKey: summary.pack,
    }.values.toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (recentEmoticons != null)
          AccountQuickReactionsView(
            client: selectedClient,
            component: component,
            recentEmoticons: recentEmoticons,
          ),
        const SizedBox(height: 12),
        SettingsSection(
          title: 'Personal Packs',
          children: [
            const SettingsControlRow(
              title: 'Create and edit packs',
              description:
                  'Personal emoji and sticker packs are stored for the selected Matrix account.',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: RoomEmojiPackSettingsView(
                component: component,
                editable: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SettingsSection(
          title: 'Picker order',
          children: [
            const SettingsControlRow(
              title: 'Emoji and sticker packs',
              description:
                  'Choose the order visible packs appear in pickers. This order follows your selected Matrix account.',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: PickerPackOrderList(
                component: component,
                initialPacks: pickerPacks,
              ),
            ),
          ],
        ),
        if (globalPacks.isNotEmpty) ...[
          AccountEmojiView(component),
          const SizedBox(height: 12),
        ],
        SettingsSection(
          title: 'Available Packs',
          showDivider: false,
          children: [
            SettingsControlRow(
              title: 'Joined room and space packs',
              description: availablePacks.isEmpty
                  ? 'No room or space emoji packs are visible for this account yet.'
                  : 'Favorite packs to make them available in the emoji and sticker pickers across the app.',
            ),
            if (availablePacks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: _AvailableEmoticonPackGrid(packs: availablePacks),
              ),
          ],
        ),
      ],
    );
  }
}

/// Optimistic reorder control for the picker pack order.
///
/// Public only so its persistence behaviour - the submitted key sequence, the
/// disabled controls mid-save, and the rollback on failure - can be driven
/// directly in tests without standing up a whole `ClientManager`.
@visibleForTesting
class PickerPackOrderList extends StatefulWidget {
  const PickerPackOrderList({
    required this.component,
    required this.initialPacks,
  });

  final EmoticonComponent component;
  final List<EmoticonPack> initialPacks;

  @override
  State<PickerPackOrderList> createState() => _PickerPackOrderListState();
}

class _PickerPackOrderListState extends State<PickerPackOrderList> {
  late List<EmoticonPack> _packs;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _packs = List.of(widget.initialPacks);
  }

  @override
  void didUpdateWidget(covariant PickerPackOrderList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_saving && oldWidget.initialPacks != widget.initialPacks) {
      _packs = List.of(widget.initialPacks);
    }
  }

  Future<void> _move(int index, int delta) async {
    final destination = index + delta;
    if (_saving || destination < 0 || destination >= _packs.length) return;

    final previous = List<EmoticonPack>.of(_packs);
    setState(() {
      final pack = _packs.removeAt(index);
      _packs.insert(destination, pack);
      _saving = true;
    });
    try {
      await widget.component.setPackOrder(
        _packs.map((pack) => pack.orderKey).toList(growable: false),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _packs = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save picker order.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_packs.length < 2) return const SizedBox.shrink();
    return Column(
      children: [
        for (var index = 0; index < _packs.length; index++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _PackAvatar(pack: _packs[index]),
            title: Text(_packs[index].displayName),
            subtitle: Text(_packs[index].ownerDisplayName),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Move ${_packs[index].displayName} up',
                  onPressed: index == 0 || _saving
                      ? null
                      : () => _move(index, -1),
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
                IconButton(
                  tooltip: 'Move ${_packs[index].displayName} down',
                  onPressed: index == _packs.length - 1 || _saving
                      ? null
                      : () => _move(index, 1),
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

@visibleForTesting
List<AvailableEmoticonPackSummary> collectJoinedEmoticonPacks(Client client) {
  final packs = <String, AvailableEmoticonPackSummary>{};

  void addPack(
    EmoticonPack pack, {
    required String sourceName,
    required IconData sourceIcon,
  }) {
    if (pack.emotes.isEmpty) {
      return;
    }

    final key = '${pack.ownerId}\u0000${pack.identifier}';
    packs.putIfAbsent(
      key,
      () => AvailableEmoticonPackSummary(
        pack: pack,
        sourceName: sourceName,
        sourceIcon: sourceIcon,
      ),
    );
  }

  for (final space in client.spaces) {
    final component = space.getComponent<SpaceEmoticonComponent>();
    if (component == null) {
      continue;
    }

    for (final pack in component.ownedPacks) {
      addPack(
        pack,
        sourceName: space.displayName,
        sourceIcon: Icons.grid_view_rounded,
      );
    }
  }

  for (final room in client.rooms) {
    final component = room.getComponent<RoomEmoticonComponent>();
    if (component == null) {
      continue;
    }

    for (final pack in component.ownedPacks) {
      addPack(
        pack,
        sourceName: room.displayName,
        sourceIcon: Icons.tag_rounded,
      );
    }
  }

  final result = packs.values.toList();
  result.sort((a, b) {
    final source = a.sourceName.compareTo(b.sourceName);
    if (source != 0) {
      return source;
    }
    return a.pack.displayName.compareTo(b.pack.displayName);
  });
  return result;
}

class AvailableEmoticonPackSummary {
  const AvailableEmoticonPackSummary({
    required this.pack,
    required this.sourceName,
    required this.sourceIcon,
  });

  final EmoticonPack pack;
  final String sourceName;
  final IconData sourceIcon;
}

class _AvailableEmoticonPackGrid extends StatelessWidget {
  const _AvailableEmoticonPackGrid({required this.packs});

  final List<AvailableEmoticonPackSummary> packs;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth < 620
            ? constraints.maxWidth
            : (constraints.maxWidth - 12) / 2;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final pack in packs)
              SizedBox(
                width: cardWidth,
                child: _AvailableEmoticonPackCard(summary: pack),
              ),
          ],
        );
      },
    );
  }
}

class _AvailableEmoticonPackCard extends StatefulWidget {
  const _AvailableEmoticonPackCard({required this.summary});

  final AvailableEmoticonPackSummary summary;

  @override
  State<_AvailableEmoticonPackCard> createState() =>
      _AvailableEmoticonPackCardState();
}

class _AvailableEmoticonPackCardState
    extends State<_AvailableEmoticonPackCard> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pack = widget.summary.pack;
    final previewEmotes = pack.emotes.take(8).toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.72),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PackAvatar(pack: pack),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pack.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          widget.summary.sourceIcon,
                          size: 14,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            widget.summary.sourceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 12,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: pack.isGloballyAvailable
                    ? 'Remove from favorites'
                    : 'Add to favorites',
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        pack.isGloballyAvailable
                            ? Icons.favorite
                            : Icons.favorite_border,
                      ),
                onPressed: _saving ? null : _toggleFavorite,
              ),
            ],
          ),
          if (previewEmotes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final emote in previewEmotes)
                  _EmoticonPreviewChip(emoticon: emote),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleFavorite() async {
    setState(() => _saving = true);
    try {
      await widget.summary.pack.markAsGlobal(
        !widget.summary.pack.isGloballyAvailable,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text('Could not update pack favorite state.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class _PackAvatar extends StatelessWidget {
  const _PackAvatar({required this.pack});

  final EmoticonPack pack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = pack.image;

    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: image == null
          ? Icon(
              pack.icon ?? Icons.emoji_emotions_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            )
          : Image(
              image: image,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
            ),
    );
  }
}

class _EmoticonPreviewChip extends StatelessWidget {
  const _EmoticonPreviewChip({required this.emoticon});

  final Emoticon emoticon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = emoticon.image;

    return Container(
      width: 34,
      height: 34,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: image == null
          ? Center(
              child: Text(
                emoticon.shortcode ?? emoticon.key,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall,
              ),
            )
          : Image(image: image, filterQuality: FilterQuality.medium),
    );
  }
}
