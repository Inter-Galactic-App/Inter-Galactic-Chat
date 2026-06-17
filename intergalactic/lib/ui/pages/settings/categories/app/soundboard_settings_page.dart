import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/space.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/organisms/soundboard/soundboard_emoji_view.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/double_preference_slider.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/ui/pages/settings/categories/space/settings_category_space.dart';
import 'package:intergalactic/ui/pages/settings/settings_navigation.dart';
import 'package:intergalactic/ui/pages/settings/space_settings_page.dart';
import 'package:intl/intl.dart';

class SoundboardSettingsPage extends StatefulWidget {
  const SoundboardSettingsPage({
    required this.clientManager,
    super.key,
  });

  final ClientManager clientManager;

  @override
  State<SoundboardSettingsPage> createState() => _SoundboardSettingsPageState();
}

class _SoundboardSettingsPageState extends State<SoundboardSettingsPage> {
  final List<StreamSubscription> _managerSubscriptions = [];
  final List<StreamSubscription> _soundboardSubscriptions = [];

  String get labelSoundboardVolume => Intl.message(
        'Soundboard volume',
        name: 'labelSoundboardVolume',
        desc: 'Title for the local soundboard playback volume setting',
      );

  String get labelSoundboardVolumeDescription => Intl.message(
        'Controls how loud soundboard clips are on this device. Other people keep their own local volume.',
        name: 'labelSoundboardVolumeDescription',
        desc:
            'Description for the local-only soundboard playback volume setting',
      );

  @override
  void initState() {
    super.initState();
    _managerSubscriptions.addAll([
      widget.clientManager.onSpaceAdded.listen((_) => _refreshSubscriptions()),
      widget.clientManager.onSpaceRemoved
          .listen((_) => _refreshSubscriptions()),
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
    _refresh();
  }

  void _refresh() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final soundboards = collectVisibleSoundboards(widget.clientManager);

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
                  : 'Soundboards are managed from the space settings they belong to. This page shows what is available for calls on this device.',
            ),
            if (soundboards.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: Column(
                  children: [
                    for (final summary in soundboards)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _SoundboardSpaceCard(summary: summary),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

@visibleForTesting
List<SoundboardSpaceSummary> collectVisibleSoundboards(ClientManager manager) {
  final summaries = <SoundboardSpaceSummary>[];

  for (final space in manager.spaces) {
    final component = space.getComponent<SoundboardComponent>();
    if (component == null) {
      continue;
    }

    final sounds = component.sounds
        .where((sound) => sound.isAvailable)
        .toList(growable: false);
    if (sounds.isEmpty) {
      continue;
    }

    summaries.add(
      SoundboardSpaceSummary(
        space: space,
        component: component,
        sounds: sounds,
      ),
    );
  }

  summaries.sort(
    (a, b) => a.space.displayName.compareTo(b.space.displayName),
  );
  return summaries;
}

class SoundboardSpaceSummary {
  const SoundboardSpaceSummary({
    required this.space,
    required this.component,
    required this.sounds,
  });

  final Space space;
  final SoundboardComponent component;
  final List<SoundboardSound> sounds;
}

class _SoundboardSpaceCard extends StatelessWidget {
  const _SoundboardSpaceCard({required this.summary});

  final SoundboardSpaceSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final emojiPacks = soundboardEmojiPacksForSpace(summary.space);
    final avatar = summary.space.avatar;
    final previewSounds = summary.sounds.take(6).toList(growable: false);

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
                      '${summary.sounds.length} sounds • ${summary.space.roomsWithChildren.length} rooms in scope',
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final sound in previewSounds)
                _SoundPreviewChip(
                  sound: sound,
                  space: summary.space,
                  emojiPacks: emojiPacks,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SoundPreviewChip extends StatelessWidget {
  const _SoundPreviewChip({
    required this.sound,
    required this.space,
    required this.emojiPacks,
  });

  final SoundboardSound sound;
  final Space space;
  final List<EmoticonPack> emojiPacks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPreview = space.client is MatrixClient;

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: canPreview
            ? () => unawaited(
                  soundboardPlaybackService.playPreview(
                    space.client as MatrixClient,
                    sound,
                  ),
                )
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Center(
                  child: SoundboardEmojiView(
                    value: sound.emoji,
                    packs: emojiPacks,
                    size: 20,
                    textStyle: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  sound.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontSize: 12,
                    letterSpacing: 0,
                  ),
                ),
              ),
              if (canPreview) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.play_arrow_rounded,
                  size: 17,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
