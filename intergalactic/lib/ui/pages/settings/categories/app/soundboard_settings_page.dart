import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_library_component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/organisms/soundboard/soundboard_emoji_view.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/double_preference_slider.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/ui/pages/settings/categories/space/settings_category_space.dart';
import 'package:intergalactic/ui/pages/settings/settings_account_scope.dart';
import 'package:intergalactic/ui/pages/settings/settings_navigation.dart';
import 'package:intergalactic/ui/pages/settings/space_settings_page.dart';
import 'package:intl/intl.dart';

@visibleForTesting
Color soundboardPreviewPackSurface(ColorScheme scheme) =>
    scheme.surfaceContainer;

@visibleForTesting
Color soundboardPreviewPackOutline(ColorScheme scheme) =>
    scheme.outlineVariant.withValues(alpha: 0.42);

@visibleForTesting
Color soundboardPreviewTileSurface(ColorScheme scheme) =>
    scheme.surfaceContainerHigh.withValues(alpha: 0.62);

class SoundboardSettingsPage extends StatefulWidget {
  const SoundboardSettingsPage({required this.clientManager, super.key});

  final ClientManager clientManager;

  @override
  State<SoundboardSettingsPage> createState() => _SoundboardSettingsPageState();
}

class _SoundboardSettingsPageState extends State<SoundboardSettingsPage> {
  final List<StreamSubscription> _managerSubscriptions = [];
  final List<StreamSubscription> _soundboardSubscriptions = [];

  /// Key of the global-pack row with a write in flight, so the whole list
  /// disables while account data is being rewritten (the document is shared;
  /// overlapping writes would race each other's rebase).
  String? _busyGlobalPackKey;
  String? _globalLibraryError;
  Future<void> Function()? _lastGlobalLibraryAction;

  String get labelSoundboardVolume => Intl.message(
    'Soundboard volume',
    name: 'labelSoundboardVolume',
    desc: 'Title for the local soundboard playback volume setting',
  );

  String get labelSoundboardVolumeDescription => Intl.message(
    'Controls how loud soundboard clips are on this device. Other people keep their own local volume.',
    name: 'labelSoundboardVolumeDescription',
    desc: 'Description for the local-only soundboard playback volume setting',
  );

  @override
  void initState() {
    super.initState();
    _managerSubscriptions.addAll([
      widget.clientManager.onSpaceAdded.listen((_) => _refreshSubscriptions()),
      widget.clientManager.onSpaceRemoved.listen(
        (_) => _refreshSubscriptions(),
      ),
      widget.clientManager.onSpaceUpdated.stream.listen((_) => _refresh()),
      widget.clientManager.onSpaceChildUpdated.stream.listen((_) => _refresh()),
    ]);
    _refreshSubscriptions();
  }

  @override
  void dispose() {
    for (final subscription in _managerSubscriptions) {
      subscription.cancel();
    }
    _cancelSoundboardSubscriptions();
    super.dispose();
  }

  void _cancelSoundboardSubscriptions() {
    for (final subscription in _soundboardSubscriptions) {
      subscription.cancel();
    }
    _soundboardSubscriptions.clear();
  }

  void _refreshSubscriptions() {
    _cancelSoundboardSubscriptions();
    for (final space in widget.clientManager.spaces) {
      final component = space.getComponent<SoundboardComponent>();
      if (component == null) {
        continue;
      }
      _soundboardSubscriptions.add(
        component.onChanged.listen((_) => _refresh()),
      );
    }
    // The global library is account data, so it changes independently of any
    // space's soundboard state (another device can toggle a pack).
    for (final client in widget.clientManager.clients) {
      final library = client.getComponent<SoundboardLibraryComponent>();
      if (library == null) {
        continue;
      }
      _soundboardSubscriptions.add(library.onChanged.listen((_) => _refresh()));
    }
    _refresh();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedClient = SettingsAccountScope.selectedClientOf(
      context,
      widget.clientManager,
    );
    final soundboards = collectVisibleSoundboards(
      widget.clientManager,
      client: selectedClient,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Soundboard',
          children: [
            DoublePreferenceSlider(
              preference: preferences.soundboardVolume,
              min: SoundboardSound.minVolume,
              max: SoundboardSound.maxVolume,
              numDecimals: 0,
              units: '%',
              title: labelSoundboardVolume,
              description: labelSoundboardVolumeDescription,
            ),
          ],
        ),
        SettingsSection(
          title: 'Soundboards',
          showDivider: false,
          children: [
            SettingsControlRow(
              title: 'Joined space soundboards',
              description: soundboards.isEmpty
                  ? 'No shared soundboards with sounds are visible from joined spaces yet.'
                  : 'Packs stay grouped by their source space. Favorite a pack to make it available in calls across spaces that allow external packs.',
            ),
            if (soundboards.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Column(
                  children: [
                    for (final summary in soundboards)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _SoundboardSpaceCard(
                          summary: summary,
                          library: selectedClient
                              ?.getComponent<SoundboardLibraryComponent>(),
                          busyGlobalPackKey: _busyGlobalPackKey,
                          onGlobalPackChanged: selectedClient == null
                              ? null
                              : (space, pack, enabled) {
                                  final library = selectedClient
                                      .getComponent<
                                        SoundboardLibraryComponent
                                      >();
                                  if (library == null) {
                                    return;
                                  }
                                  _setGlobalPack(
                                    library,
                                    space.identifier,
                                    pack.id,
                                    enabled,
                                  );
                                },
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
        if (_globalLibraryError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _globalLibraryError!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _retryGlobalLibraryAction,
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _setGlobalPack(
    SoundboardLibraryComponent library,
    String sourceSpaceId,
    String packId,
    bool enable,
  ) async {
    await _runGlobalLibraryAction(
      key: '$sourceSpaceId|$packId',
      action: () => enable
          ? library.enablePack(sourceSpaceId, packId)
          : library.disablePack(sourceSpaceId, packId),
    );
  }

  /// Runs a library mutation, keeping the failure on screen with a retry
  /// instead of a transient snack: the component rolls the document back on
  /// failure, so the member needs to know the toggle they flipped did not
  /// stick.
  Future<void> _runGlobalLibraryAction({
    required String key,
    required Future<void> Function() action,
  }) async {
    setState(() {
      _busyGlobalPackKey = key;
      _globalLibraryError = null;
    });
    try {
      await action();
      _lastGlobalLibraryAction = null;
    } catch (error, stackTrace) {
      // Surfaced on screen AND logged: the on-screen text is deliberately a
      // short user-facing message, so without this a bug report about a toggle
      // that would not stick carries nothing to diagnose it with.
      Log.onError(
        error,
        stackTrace,
        content: 'Soundboard global library mutation failed (key=$key)',
      );
      _lastGlobalLibraryAction = action;
      if (mounted) {
        setState(() {
          _globalLibraryError = _describeGlobalLibraryError(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busyGlobalPackKey = null);
      }
    }
  }

  void _retryGlobalLibraryAction() {
    final action = _lastGlobalLibraryAction;
    if (action == null) {
      setState(() => _globalLibraryError = null);
      return;
    }
    unawaited(_runGlobalLibraryAction(key: '__retry__', action: action));
  }

  static String _describeGlobalLibraryError(Object error) {
    final message = error is Exception
        ? error.toString().replaceFirst('Exception: ', '')
        : error.toString();
    return message.isEmpty ? 'That change could not be saved.' : message;
  }
}

/// A pack in one of this account's spaces that could be enabled globally,
/// paired with the space that owns it so the UI can name the source.
class SoundboardGlobalPackCandidate {
  const SoundboardGlobalPackCandidate({
    required this.space,
    required this.pack,
    required this.soundCount,
  });

  final Space space;
  final SoundboardPack pack;
  final int soundCount;
}

/// Every pack the selected account could enable globally: packs it can read
/// today, in the spaces that account has joined.
///
/// Scoped to [client] rather than the manager — the library is account data,
/// so offering another signed-in account's packs here would write a reference
/// this account cannot resolve.
@visibleForTesting
List<SoundboardGlobalPackCandidate> collectGlobalPackCandidates(Client client) {
  final candidates = <SoundboardGlobalPackCandidate>[];
  for (final space in client.spaces) {
    final soundboard = space.getComponent<SoundboardComponent>();
    if (soundboard == null) {
      continue;
    }
    for (final pack in soundboard.packs) {
      if (pack.deleted || !pack.enabled) {
        continue;
      }
      // Count by EFFECTIVE pack id, not the raw reference. A sound with no
      // pack_id belongs to its uploader's derived legacy pack, and matching on
      // the raw field counted zero for every legacy pack — so the packs most
      // members actually have (their own uploads) were silently absent from
      // this list and could never be enabled globally.
      final soundCount = soundboard.sounds
          .where(
            (sound) =>
                soundboard.effectivePackIdFor(sound) == pack.id &&
                sound.isAvailable,
          )
          .length;
      if (soundCount == 0) {
        continue;
      }
      candidates.add(
        SoundboardGlobalPackCandidate(
          space: space,
          pack: pack,
          soundCount: soundCount,
        ),
      );
    }
  }
  candidates.sort((a, b) {
    final bySpace = a.space.displayName.compareTo(b.space.displayName);
    return bySpace != 0 ? bySpace : a.pack.name.compareTo(b.pack.name);
  });
  return candidates;
}

@visibleForTesting
List<SoundboardSpaceSummary> collectVisibleSoundboards(
  ClientManager manager, {
  Client? client,
}) {
  final summaries = <SoundboardSpaceSummary>[];

  for (final space in client?.spaces ?? manager.spaces) {
    final component = space.getComponent<SoundboardComponent>();
    if (component == null) {
      continue;
    }

    final allPacks = component.packs;
    final packs = allPacks
        .where((pack) => pack.isAvailable)
        .map((pack) {
          final sounds = component.sounds
              .where(
                (sound) =>
                    sound.isAvailable &&
                    component.effectivePackIdFor(sound) == pack.id,
              )
              .toList(growable: false);
          return SoundboardPackSummary(
            pack: pack,
            displayName: soundboardPackDisplayName(pack, allPacks),
            sounds: sounds,
          );
        })
        .where((summary) => summary.sounds.isNotEmpty)
        .toList(growable: false);
    if (packs.isEmpty) {
      continue;
    }

    summaries.add(
      SoundboardSpaceSummary(space: space, component: component, packs: packs),
    );
  }

  summaries.sort((a, b) => a.space.displayName.compareTo(b.space.displayName));
  return summaries;
}

class SoundboardSpaceSummary {
  const SoundboardSpaceSummary({
    required this.space,
    required this.component,
    required this.packs,
  });

  final Space space;
  final SoundboardComponent component;
  final List<SoundboardPackSummary> packs;

  int get soundCount =>
      packs.fold(0, (count, pack) => count + pack.sounds.length);
}

class SoundboardPackSummary {
  const SoundboardPackSummary({
    required this.pack,
    required this.displayName,
    required this.sounds,
  });

  final SoundboardPack pack;
  final String displayName;
  final List<SoundboardSound> sounds;
}

class _SoundboardSpaceCard extends StatelessWidget {
  const _SoundboardSpaceCard({
    required this.summary,
    this.library,
    this.busyGlobalPackKey,
    this.onGlobalPackChanged,
  });

  final SoundboardSpaceSummary summary;
  final SoundboardLibraryComponent? library;
  final String? busyGlobalPackKey;
  final void Function(Space space, SoundboardPack pack, bool enabled)?
  onGlobalPackChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emojiPacks = soundboardEmojiPacksForSpace(summary.space);
    final avatar = summary.space.avatar;

    return Container(
      padding: const EdgeInsets.all(14),
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
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: avatar == null
                    ? Icon(
                        Icons.grid_view_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                      )
                    : Image(
                        image: avatar,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.medium,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary.space.displayName,
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
                    Text(
                      '${summary.soundCount} sounds • ${summary.packs.length} ${summary.packs.length == 1 ? 'pack' : 'packs'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: () {
                  SettingsNavigation.show(
                    context,
                    SpaceSettingsPage(
                      space: summary.space,
                      initialTabId: SettingsCategorySpace.tabIdSoundboard,
                    ),
                  );
                },
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Manage'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final packSummary in summary.packs)
            _SoundboardPackPreview(
              summary: packSummary,
              space: summary.space,
              emojiPacks: emojiPacks,
              library: library,
              isSaving:
                  busyGlobalPackKey ==
                  '${summary.space.identifier}|${packSummary.pack.id}',
              onGlobalPackChanged: onGlobalPackChanged,
            ),
        ],
      ),
    );
  }
}

class _SoundboardPackPreview extends StatelessWidget {
  const _SoundboardPackPreview({
    required this.summary,
    required this.space,
    required this.emojiPacks,
    required this.library,
    required this.isSaving,
    required this.onGlobalPackChanged,
  });

  final SoundboardPackSummary summary;
  final Space space;
  final List<EmoticonPack> emojiPacks;
  final SoundboardLibraryComponent? library;
  final bool isSaving;
  final void Function(Space space, SoundboardPack pack, bool enabled)?
  onGlobalPackChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pack = summary.pack;
    final globalLibrary = library;
    final enabled =
        globalLibrary?.isEnabled(space.identifier, pack.id) ?? false;
    final canToggle =
        globalLibrary != null &&
        onGlobalPackChanged != null &&
        (enabled || globalLibrary.canEnable(space.identifier, pack.id));

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: soundboardPreviewPackSurface(scheme),
          border: Border.all(color: soundboardPreviewPackOutline(scheme)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  pack.isLegacy ? Icons.history_rounded : Icons.folder_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    summary.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Tooltip(
                  message: enabled
                      ? 'Remove pack from favorites'
                      : 'Add pack to favorites',
                  child: IconButton(
                    key: ValueKey(
                      'soundboard-global-pack-${space.identifier}-${pack.id}',
                    ),
                    onPressed: !canToggle || isSaving
                        ? null
                        : () => onGlobalPackChanged!(space, pack, !enabled),
                    icon: isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            enabled ? Icons.favorite : Icons.favorite_border,
                          ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 8.0;
                final columnCount = constraints.maxWidth >= 640
                    ? 4
                    : constraints.maxWidth >= 440
                    ? 3
                    : 2;
                final tileWidth =
                    (constraints.maxWidth - spacing * (columnCount - 1)) /
                    columnCount;

                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final sound in summary.sounds.take(6))
                      SizedBox(
                        width: tileWidth,
                        child: SoundboardPreviewTile(
                          sound: sound,
                          emojiPacks: emojiPacks,
                          onPressed: space.client is MatrixClient
                              ? () => unawaited(
                                  soundboardPlaybackService.playPreview(
                                    space.client as MatrixClient,
                                    sound,
                                  ),
                                )
                              : null,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class SoundboardPreviewTile extends StatelessWidget {
  const SoundboardPreviewTile({
    required this.sound,
    required this.emojiPacks,
    required this.onPressed,
    super.key,
  });

  final SoundboardSound sound;
  final List<EmoticonPack> emojiPacks;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(8);

    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: 'Play ${sound.name}',
      child: Material(
        color: soundboardPreviewTileSurface(scheme),
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                SoundboardEmojiView(
                  value: sound.emoji,
                  packs: emojiPacks,
                  size: 24,
                  textStyle: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sound.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.05,
                    ),
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
