import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/server_discovery/server_discovery_controller.dart';
import 'package:intergalactic/client/components/server_discovery/server_discovery_models.dart';
import 'package:intergalactic/client/components/server_discovery/server_discovery_service_factory.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_mxc_image_provider.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/ui/pages/settings/settings_account_scope.dart';
import 'package:intergalactic/ui/pages/settings/settings_status_components.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class DiscoverSettingsPage extends StatefulWidget {
  const DiscoverSettingsPage({super.key});

  @override
  State<DiscoverSettingsPage> createState() => _DiscoverSettingsPageState();
}

class _DiscoverSettingsPageState extends State<DiscoverSettingsPage> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _joiningRoomIds = {};
  final Map<String, ServerDiscoveryJoinOutcome> _joinOutcomes = {};
  Client? _client;
  ServerDiscoveryController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final selectedClient =
        SettingsAccountScope.maybeOf(context)?.selectedClient;
    if (!identical(_client, selectedClient)) {
      final oldController = _controller;
      if (oldController != null) {
        oldController.cache.invalidateScope(oldController.scope);
        oldController.dispose();
      }
      _client = selectedClient;
      _searchController.clear();
      _joiningRoomIds.clear();
      _joinOutcomes.clear();
      if (selectedClient == null) {
        _controller = null;
      } else {
        _controller = ServerDiscoveryController(
          service: createServerDiscoveryService(selectedClient),
        );
        final controller = _controller!;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && identical(_controller, controller)) {
            unawaited(controller.loadInitial());
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_client == null || controller == null) {
      return const SettingsSection(
        title: 'Discover',
        children: [
          SettingsControlRow(
            title: 'No account selected',
            description: 'Choose an account to view its homeserver directory.',
          ),
        ],
      );
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsSection(
              title: 'Discover',
              showDivider: false,
              children: [
                SettingsControlRow(
                  title: 'Homeserver directory',
                  description:
                      'Browse rooms and spaces published by ${controller.scope.homeserver}. Search stays scoped to this account homeserver.',
                  trailing: Wrap(
                    spacing: 8,
                    children: [
                      tiamat.Button.secondary(
                        text: 'Refresh',
                        onTap: controller.isLoading
                            ? null
                            : () => unawaited(controller.refresh()),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SearchControls(
                        controller: _searchController,
                        filter: controller.filter,
                        accessFilter: controller.accessFilter,
                        sortMode: controller.sortMode,
                        onSearch: (query) =>
                            unawaited(controller.setQuery(query)),
                        onFilterChanged: (filter) =>
                            unawaited(controller.setFilter(filter)),
                        onAccessFilterChanged: (filter) =>
                            unawaited(controller.setAccessFilter(filter)),
                        onSortModeChanged: (sortMode) =>
                            unawaited(controller.setSortMode(sortMode)),
                      ),
                      const SizedBox(height: 12),
                      if (controller.isLoading)
                        const ClipRRect(
                          borderRadius: BorderRadius.all(Radius.circular(999)),
                          child: LinearProgressIndicator(minHeight: 2),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            _buildResultsSwitcher(controller),
          ],
        );
      },
    );
  }

  Widget _buildResultsSwitcher(ServerDiscoveryController controller) {
    return AnimatedSwitcher(
      duration: InterGalacticMotion.duration(
        context,
        InterGalacticMotion.standard,
      ),
      switchInCurve: InterGalacticMotion.standardOut,
      switchOutCurve: InterGalacticMotion.standardIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            axisAlignment: -1,
            child: child,
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(_resultsStateKey(controller)),
        child: _buildResults(controller),
      ),
    );
  }

  String _resultsStateKey(ServerDiscoveryController controller) {
    final suffix =
        '${controller.filter}:${controller.accessFilter}:${controller.sortMode}:${controller.query}';
    if (controller.error != null && controller.entries.isEmpty) {
      return 'error:$suffix';
    }
    if (controller.isEmpty) {
      return 'empty:$suffix';
    }
    return 'results:$suffix';
  }

  Widget _buildResults(ServerDiscoveryController controller) {
    final error = controller.error;
    if (error != null && controller.entries.isEmpty) {
      return SettingsSection(
        title: 'Results',
        children: [
          SettingsStatePanel(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load Discover',
            description: _errorDescription(error),
            tone: SettingsStatusTone.danger,
            action: tiamat.Button.secondary(
              text: 'Retry',
              onTap: () => unawaited(controller.retry()),
            ),
          ),
        ],
      );
    }

    if (controller.isLoading && controller.entries.isEmpty) {
      return const SettingsSection(
        title: 'Results',
        children: [
          SettingsStatePanel(
            icon: Icons.hourglass_empty,
            title: 'Loading Discover',
            description:
                'Checking this account homeserver directory for rooms and spaces.',
          ),
        ],
      );
    }

    if (controller.entries.isEmpty) {
      return _buildEmptyResultsSection(controller);
    }

    return SettingsSection(
      title: 'Results',
      children: [
        SettingsControlRow(
          title: _resultsTitle(controller),
          description:
              'Shows account-scoped directory results plus restricted rooms visible through spaces joined by this account.',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Column(
            children: [
              for (final entry in controller.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _DiscoveryResultCard(
                    entry: entry,
                    client: _client,
                    joining: _joiningRoomIds.contains(entry.roomId),
                    outcome: _joinOutcomes[entry.roomId],
                    onJoin: () => _join(controller, entry),
                  ),
                ),
            ],
          ),
        ),
        if (controller.error != null)
          SettingsStatePanel(
            icon: Icons.sync_problem_outlined,
            title: 'Could not load more results',
            description: _errorDescription(controller.error!),
            tone: SettingsStatusTone.danger,
            action: tiamat.Button.secondary(
              text: 'Retry',
              onTap: () => unawaited(controller.retry()),
            ),
          ),
        if (controller.hasMore) _buildLoadMorePanel(controller),
      ],
    );
  }

  Widget _buildEmptyResultsSection(ServerDiscoveryController controller) {
    final children = <Widget>[
      SettingsStatePanel(
        icon: Icons.travel_explore_outlined,
        title: _emptyResultsTitle(controller),
        description: _emptyResultsDescription(controller),
        action: _emptyResultsAction(controller),
      ),
      if (controller.hasMore) _buildLoadMorePanel(controller),
    ];

    return SettingsSection(
      title: 'Results',
      children: children,
    );
  }

  SettingsStatePanel _buildLoadMorePanel(
    ServerDiscoveryController controller,
  ) {
    return SettingsStatePanel(
      icon: Icons.expand_more,
      title: controller.entries.isEmpty
          ? 'More directory pages available'
          : 'More results available',
      description: controller.entries.isEmpty
          ? 'Load the next page without changing the current search or filters.'
          : 'Load the next page from this homeserver directory without changing the current search.',
      tone: SettingsStatusTone.accent,
      action: tiamat.Button.secondary(
        text: controller.isLoadingMore ? 'Loading...' : 'Load more',
        onTap: controller.isLoadingMore
            ? null
            : () => unawaited(controller.loadMore()),
      ),
    );
  }

  Future<void> _join(
    ServerDiscoveryController controller,
    ServerDiscoveryEntry entry,
  ) async {
    setState(() {
      _joiningRoomIds.add(entry.roomId);
      _joinOutcomes.remove(entry.roomId);
    });
    final result = await controller.join(entry);
    if (!mounted) return;
    setState(() {
      _joiningRoomIds.remove(entry.roomId);
      _joinOutcomes[entry.roomId] = result.outcome;
    });
  }

  String _errorDescription(ServerDiscoveryError error) {
    return switch (error.kind) {
      ServerDiscoveryFailureKind.authenticationInvalid =>
        'The selected account needs to sign in again.',
      ServerDiscoveryFailureKind.unsupportedClient =>
        'Discover is available for Matrix accounts.',
      ServerDiscoveryFailureKind.networkFailure =>
        'The homeserver directory could not be reached.',
      ServerDiscoveryFailureKind.serverRefused =>
        'The homeserver refused this directory request.',
      ServerDiscoveryFailureKind.unavailable =>
        'The homeserver directory is unavailable.',
      _ => 'Please try again.',
    };
  }

  String _resultsTitle(ServerDiscoveryController controller) {
    final count = controller.entries.length;
    final estimate = controller.totalEstimate;
    final accessPrefix =
        controller.accessFilter == ServerDiscoveryAccessFilter.unjoined
            ? 'unjoined '
            : '';
    final itemLabel = switch (controller.filter) {
      ServerDiscoveryFilter.rooms =>
        '$accessPrefix${count == 1 ? 'room' : 'rooms'}',
      ServerDiscoveryFilter.spaces =>
        '$accessPrefix${count == 1 ? 'space' : 'spaces'}',
      ServerDiscoveryFilter.all =>
        '$accessPrefix${count == 1 ? 'entry' : 'entries'}',
    };
    if (controller.accessFilter == ServerDiscoveryAccessFilter.all &&
        estimate != null &&
        estimate > count) {
      return '$count of about $estimate $itemLabel';
    }
    return '$count $itemLabel';
  }

  String _emptyResultsTitle(ServerDiscoveryController controller) {
    if (controller.accessFilter == ServerDiscoveryAccessFilter.unjoined) {
      return switch (controller.filter) {
        ServerDiscoveryFilter.rooms => 'No unjoined rooms found',
        ServerDiscoveryFilter.spaces => 'No unjoined spaces found',
        ServerDiscoveryFilter.all => 'No unjoined rooms or spaces found',
      };
    }

    return switch (controller.filter) {
      ServerDiscoveryFilter.rooms => 'No rooms found',
      ServerDiscoveryFilter.spaces => 'No spaces found',
      ServerDiscoveryFilter.all => 'No rooms or spaces found',
    };
  }

  String _emptyResultsDescription(ServerDiscoveryController controller) {
    final typeLabel = switch (controller.filter) {
      ServerDiscoveryFilter.rooms => 'rooms',
      ServerDiscoveryFilter.spaces => 'spaces',
      ServerDiscoveryFilter.all => 'rooms or spaces',
    };
    final accessLabel =
        controller.accessFilter == ServerDiscoveryAccessFilter.unjoined
            ? ' unjoined'
            : '';
    final search = controller.query;
    if (search.isNotEmpty) {
      return 'No$accessLabel $typeLabel matched "$search" on this account homeserver.';
    }
    return 'This homeserver did not return matching$accessLabel $typeLabel for the current filters.';
  }

  Widget? _emptyResultsAction(ServerDiscoveryController controller) {
    if (controller.query.isNotEmpty) {
      return tiamat.Button.secondary(
        text: 'Clear search',
        onTap: () {
          _searchController.clear();
          unawaited(controller.setQuery(''));
        },
      );
    }

    if (controller.accessFilter == ServerDiscoveryAccessFilter.unjoined) {
      return tiamat.Button.secondary(
        text: 'Show all',
        onTap: () => unawaited(
          controller.setAccessFilter(ServerDiscoveryAccessFilter.all),
        ),
      );
    }

    if (controller.filter != ServerDiscoveryFilter.all) {
      return tiamat.Button.secondary(
        text: 'Show all types',
        onTap: () => unawaited(
          controller.setFilter(ServerDiscoveryFilter.all),
        ),
      );
    }

    return null;
  }
}

bool _canJoinDiscoveryEntry(ServerDiscoveryEntry entry) {
  return switch (entry.joinRequirement) {
    ServerDiscoveryJoinRequirement.publicJoin ||
    ServerDiscoveryJoinRequirement.restricted ||
    ServerDiscoveryJoinRequirement.knockRequired =>
      true,
    _ => false,
  };
}

String _discoveryJoinActionLabel(ServerDiscoveryEntry entry) {
  return switch (entry.joinRequirement) {
    ServerDiscoveryJoinRequirement.alreadyJoined => 'Joined',
    ServerDiscoveryJoinRequirement.knockRequired => 'Knock',
    ServerDiscoveryJoinRequirement.inviteRequired => 'Invite only',
    ServerDiscoveryJoinRequirement.unsupported => 'Not supported',
    ServerDiscoveryJoinRequirement.unavailable => 'Unavailable',
    _ => 'Join',
  };
}

String _discoveryRunningJoinLabel(ServerDiscoveryEntry entry) {
  if (entry.joinRequirement == ServerDiscoveryJoinRequirement.knockRequired) {
    return 'Sending knock...';
  }
  return 'Joining...';
}

class _SearchControls extends StatelessWidget {
  const _SearchControls({
    required this.controller,
    required this.filter,
    required this.accessFilter,
    required this.sortMode,
    required this.onSearch,
    required this.onFilterChanged,
    required this.onAccessFilterChanged,
    required this.onSortModeChanged,
  });

  final TextEditingController controller;
  final ServerDiscoveryFilter filter;
  final ServerDiscoveryAccessFilter accessFilter;
  final ServerDiscoverySortMode sortMode;
  final ValueChanged<String> onSearch;
  final ValueChanged<ServerDiscoveryFilter> onFilterChanged;
  final ValueChanged<ServerDiscoveryAccessFilter> onAccessFilterChanged;
  final ValueChanged<ServerDiscoverySortMode> onSortModeChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 620;
        final search = TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          onSubmitted: onSearch,
          decoration: InputDecoration(
            labelText: 'Search',
            suffixIcon: IconButton(
              tooltip: 'Search',
              icon: const Icon(Icons.search),
              onPressed: () => onSearch(controller.text),
            ),
          ),
        );
        final filters = SegmentedButton<ServerDiscoveryFilter>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(
              value: ServerDiscoveryFilter.all,
              label: Text('All'),
            ),
            ButtonSegment(
              value: ServerDiscoveryFilter.rooms,
              label: Text('Rooms'),
            ),
            ButtonSegment(
              value: ServerDiscoveryFilter.spaces,
              label: Text('Spaces'),
            ),
          ],
          selected: {filter},
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) {
              onFilterChanged(selection.first);
            }
          },
        );
        final accessSelector = _LabeledDropdown<ServerDiscoveryAccessFilter>(
          label: 'Show',
          value: accessFilter,
          items: ServerDiscoveryAccessFilter.values,
          itemLabel: _accessFilterLabel,
          onChanged: onAccessFilterChanged,
        );
        final sortSelector = _LabeledDropdown<ServerDiscoverySortMode>(
          label: 'Sort',
          value: sortMode,
          items: ServerDiscoverySortMode.values,
          itemLabel: _sortModeLabel,
          onChanged: onSortModeChanged,
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: filters,
              ),
              const SizedBox(height: 10),
              accessSelector,
              const SizedBox(height: 10),
              sortSelector,
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: search),
                const SizedBox(width: 12),
                filters,
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 180,
                  child: accessSelector,
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 220,
                  child: sortSelector,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _LabeledDropdown<T> extends StatelessWidget {
  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> items;
  final String Function(T item) itemLabel;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w400,
              letterSpacing: 0,
            ),
          ),
        ),
        tiamat.DropdownSelector<T>(
          color: theme.colorScheme.surfaceContainer,
          items: items,
          itemBuilder: (item) => Text(itemLabel(item)),
          onItemSelected: (item) {
            if (item != null) {
              onChanged(item);
            }
          },
          value: value,
        ),
      ],
    );
  }
}

String _accessFilterLabel(ServerDiscoveryAccessFilter filter) {
  return switch (filter) {
    ServerDiscoveryAccessFilter.all => 'All results',
    ServerDiscoveryAccessFilter.unjoined => 'Unjoined only',
  };
}

String _sortModeLabel(ServerDiscoverySortMode sortMode) {
  return switch (sortMode) {
    ServerDiscoverySortMode.defaultOrder => 'Default',
    ServerDiscoverySortMode.alphabetical => 'Alphabetical',
    ServerDiscoverySortMode.space => 'By space',
    ServerDiscoverySortMode.joinedStatus => 'Joined status',
  };
}

class _DiscoveryResultCard extends StatelessWidget {
  const _DiscoveryResultCard({
    required this.entry,
    required this.client,
    required this.joining,
    required this.outcome,
    required this.onJoin,
  });

  final ServerDiscoveryEntry entry;
  final Client? client;
  final bool joining;
  final ServerDiscoveryJoinOutcome? outcome;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = _DiscoveryJoinActionButton(
      label: _discoveryJoinActionLabel(entry),
      runningLabel: _discoveryRunningJoinLabel(entry),
      joining: joining,
      canJoin: _canJoinDiscoveryEntry(entry),
      onJoin: onJoin,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.72),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 520;
            final details = _DiscoveryResultDetails(
              entry: entry,
              client: client,
              joining: joining,
              outcome: outcome,
            );

            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  details,
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: action,
                  ),
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: details),
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

class _DiscoveryJoinActionButton extends StatelessWidget {
  const _DiscoveryJoinActionButton({
    required this.label,
    required this.runningLabel,
    required this.joining,
    required this.canJoin,
    required this.onJoin,
  });

  final String label;
  final String runningLabel;
  final bool joining;
  final bool canJoin;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: joining,
      button: true,
      label: joining ? runningLabel : label,
      child: AnimatedSwitcher(
        duration: InterGalacticMotion.duration(
          context,
          InterGalacticMotion.short,
        ),
        switchInCurve: InterGalacticMotion.standardOut,
        switchOutCurve: InterGalacticMotion.standardIn,
        child: ConstrainedBox(
          key: ValueKey('$label:$joining:$canJoin'),
          constraints: const BoxConstraints(minWidth: 112),
          child: tiamat.Button.secondary(
            text: label,
            isLoading: joining,
            onTap: joining || !canJoin ? null : onJoin,
          ),
        ),
      ),
    );
  }
}

class _DiscoveryResultDetails extends StatelessWidget {
  const _DiscoveryResultDetails({
    required this.entry,
    required this.client,
    required this.joining,
    required this.outcome,
  });

  final ServerDiscoveryEntry entry;
  final Client? client;
  final bool joining;
  final ServerDiscoveryJoinOutcome? outcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final alias = entry.canonicalAlias;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compactHeader = constraints.maxWidth < 420;
        final typeChip = _DiscoveryTypeChip(entry: entry);

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatar(entry: entry, client: client),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          entry.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                            fontSize: 15,
                            fontWeight: FontWeight.w400,
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      if (!compactHeader) ...[
                        const SizedBox(width: 8),
                        typeChip,
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  _DiscoveryMetadataChips(
                    entry: entry,
                    typeChip: typeChip,
                    showTypeChip: compactHeader,
                  ),
                  if (alias != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      alias,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        height: 1.25,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    _joinRequirementDescription(entry),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      height: 1.25,
                      letterSpacing: 0,
                    ),
                  ),
                  _JoinStatusSlot(
                    entry: entry,
                    joining: joining,
                    outcome: outcome,
                  ),
                  if (entry.topic != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      entry.topic!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        height: 1.25,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DiscoveryTypeChip extends StatelessWidget {
  const _DiscoveryTypeChip({required this.entry});

  final ServerDiscoveryEntry entry;

  @override
  Widget build(BuildContext context) {
    final isSpace = entry.type == ServerDiscoveryEntryType.space;
    final label = isSpace ? 'Space' : 'Room';

    return SettingsStatusChip(
      label: label,
      semanticLabel: 'Directory result type: $label',
      icon: isSpace ? Icons.hub_outlined : Icons.tag_outlined,
    );
  }
}

class _DiscoveryMetadataChips extends StatelessWidget {
  const _DiscoveryMetadataChips({
    required this.entry,
    required this.typeChip,
    required this.showTypeChip,
  });

  final ServerDiscoveryEntry entry;
  final Widget typeChip;
  final bool showTypeChip;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 380;
        final secondaryChips = _secondaryChips(compact);
        final chips = <Widget>[
          if (showTypeChip) typeChip,
          SettingsStatusChip(
            label: _joinRuleLabel(entry.joinRule),
            compactLabel: _joinRuleCompactLabel(entry.joinRule),
            semanticLabel: 'Access: ${_joinRuleLabel(entry.joinRule)}',
            icon: Icons.key_outlined,
          ),
          SettingsStatusChip(
            label:
                '${entry.memberCount} member${entry.memberCount == 1 ? '' : 's'}',
            compactLabel: _memberCountCompactLabel(entry.memberCount),
            semanticLabel:
                '${entry.memberCount} member${entry.memberCount == 1 ? '' : 's'}',
            icon: Icons.group_outlined,
          ),
          ...secondaryChips,
        ];

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: chips,
        );
      },
    );
  }

  List<Widget> _secondaryChips(bool compact) {
    final worldReadable = entry.worldReadable;
    final guestCanJoin = entry.guestCanJoin;

    if (compact && worldReadable && guestCanJoin) {
      return const [
        SettingsStatusChip(
          label: 'World readable + guest access',
          compactLabel: 'World + guest',
          semanticLabel: 'World readable and guest access are allowed.',
          icon: Icons.visibility_outlined,
        ),
      ];
    }

    return [
      if (worldReadable)
        const SettingsStatusChip(
          label: 'World readable',
          compactLabel: 'World',
          semanticLabel: 'World readable history is allowed.',
          icon: Icons.visibility_outlined,
        ),
      if (guestCanJoin)
        const SettingsStatusChip(
          label: 'Guest access',
          compactLabel: 'Guest',
          semanticLabel: 'Guest access is allowed.',
          icon: Icons.person_add_alt_outlined,
        ),
    ];
  }
}

String _memberCountCompactLabel(int count) {
  if (count >= 1000000) {
    return '${(count / 1000000).toStringAsFixed(count >= 10000000 ? 0 : 1)}M';
  }
  if (count >= 1000) {
    return '${(count / 1000).toStringAsFixed(count >= 10000 ? 0 : 1)}K';
  }
  return '$count';
}

String _joinRuleLabel(ServerDiscoveryJoinRule rule) {
  return switch (rule) {
    ServerDiscoveryJoinRule.public => 'Public',
    ServerDiscoveryJoinRule.knock => 'Knock',
    ServerDiscoveryJoinRule.invite => 'Invite only',
    ServerDiscoveryJoinRule.restricted => 'Restricted',
    ServerDiscoveryJoinRule.knockRestricted => 'Knock restricted',
    ServerDiscoveryJoinRule.private => 'Private',
    ServerDiscoveryJoinRule.unknown => 'Unknown access',
  };
}

String _joinRuleCompactLabel(ServerDiscoveryJoinRule rule) {
  return switch (rule) {
    ServerDiscoveryJoinRule.invite => 'Invite',
    ServerDiscoveryJoinRule.knockRestricted => 'Knock+',
    ServerDiscoveryJoinRule.unknown => 'Unknown',
    _ => _joinRuleLabel(rule),
  };
}

String _joinRequirementDescription(ServerDiscoveryEntry entry) {
  final target =
      entry.type == ServerDiscoveryEntryType.space ? 'space' : 'room';
  return switch (entry.joinRequirement) {
    ServerDiscoveryJoinRequirement.alreadyJoined =>
      'You are already in this $target.',
    ServerDiscoveryJoinRequirement.publicJoin =>
      'Open to join from this homeserver directory.',
    ServerDiscoveryJoinRequirement.restricted =>
      'Join normally; the homeserver may require allowed-space membership.',
    ServerDiscoveryJoinRequirement.knockRequired =>
      'Request access with a knock. A room admin can approve it.',
    ServerDiscoveryJoinRequirement.inviteRequired =>
      'Requires an invite. Discover cannot bypass homeserver access rules.',
    ServerDiscoveryJoinRequirement.unsupported =>
      'This listing uses an access rule Discover cannot join yet.',
    ServerDiscoveryJoinRequirement.unavailable =>
      'This listing is missing usable join information.',
  };
}

class _JoinStatusSlot extends StatelessWidget {
  const _JoinStatusSlot({
    required this.entry,
    required this.joining,
    required this.outcome,
  });

  final ServerDiscoveryEntry entry;
  final bool joining;
  final ServerDiscoveryJoinOutcome? outcome;

  @override
  Widget build(BuildContext context) {
    final Widget child;
    if (joining) {
      child = Padding(
        key: ValueKey('joining:${entry.roomId}'),
        padding: const EdgeInsets.only(top: 8),
        child: _RunningJoinLine(label: _discoveryRunningJoinLabel(entry)),
      );
    } else if (outcome != null) {
      child = Padding(
        key: ValueKey('outcome:${entry.roomId}:$outcome'),
        padding: const EdgeInsets.only(top: 8),
        child: _OutcomeLine(outcome: outcome!),
      );
    } else {
      child = const SizedBox.shrink(key: ValueKey('idle'));
    }

    return AnimatedSwitcher(
      duration: InterGalacticMotion.duration(
        context,
        InterGalacticMotion.standard,
      ),
      switchInCurve: InterGalacticMotion.standardOut,
      switchOutCurve: InterGalacticMotion.standardIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            axisAlignment: -1,
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _RunningJoinLine extends StatelessWidget {
  const _RunningJoinLine({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;

    return Row(
      children: [
        Icon(
          Icons.hourglass_empty,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w400,
              height: 1.25,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class _OutcomeLine extends StatelessWidget {
  const _OutcomeLine({required this.outcome});

  final ServerDiscoveryJoinOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final success = switch (outcome) {
      ServerDiscoveryJoinOutcome.joined ||
      ServerDiscoveryJoinOutcome.knockRequested ||
      ServerDiscoveryJoinOutcome.alreadyJoined =>
        true,
      _ => false,
    };
    final color = success ? theme.colorScheme.primary : theme.colorScheme.error;

    return Row(
      children: [
        Icon(
          success ? Icons.check_circle_outline : Icons.error_outline,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            _joinOutcomeLabel(outcome),
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w400,
              height: 1.25,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }

  String _joinOutcomeLabel(ServerDiscoveryJoinOutcome outcome) {
    return switch (outcome) {
      ServerDiscoveryJoinOutcome.joined => 'Joined successfully.',
      ServerDiscoveryJoinOutcome.knockRequested =>
        'Knock sent. An admin can approve access.',
      ServerDiscoveryJoinOutcome.alreadyJoined => 'You are already joined.',
      ServerDiscoveryJoinOutcome.inviteRequired =>
        'This entry requires an invite.',
      ServerDiscoveryJoinOutcome.serverRefused =>
        'The homeserver refused this join.',
      ServerDiscoveryJoinOutcome.bannedUser => 'The homeserver refused access.',
      ServerDiscoveryJoinOutcome.staleEntry =>
        'This directory entry may be stale.',
      ServerDiscoveryJoinOutcome.networkFailure =>
        'Network failure while joining.',
      ServerDiscoveryJoinOutcome.restrictedRefused =>
        'The homeserver refused the restricted join.',
      ServerDiscoveryJoinOutcome.unavailableRoom =>
        'This room is no longer available.',
      ServerDiscoveryJoinOutcome.unsupportedJoinRule =>
        'This access rule is not supported here.',
      ServerDiscoveryJoinOutcome.failed => 'Join failed.',
    };
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.entry,
    required this.client,
  });

  final ServerDiscoveryEntry entry;
  final Client? client;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = entry.avatarUrl;
    final selectedClient = client;
    ImageProvider? image;
    if (avatarUrl != null && selectedClient is MatrixClient) {
      image = MatrixMxcImage(
        avatarUrl,
        selectedClient.matrixClient,
        autoLoadFullRes: false,
      );
    }

    final theme = Theme.of(context);

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        image: image == null
            ? null
            : DecorationImage(
                image: image,
                fit: BoxFit.cover,
              ),
      ),
      clipBehavior: Clip.antiAlias,
      child: image == null
          ? Icon(
              entry.type == ServerDiscoveryEntryType.space
                  ? Icons.hub_outlined
                  : Icons.tag_outlined,
              color: theme.colorScheme.onSurfaceVariant,
              size: 20,
            )
          : null,
    );
  }
}
