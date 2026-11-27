import 'dart:async';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_library_component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/molecules/emoji_picker.dart';
import 'package:intergalactic/ui/organisms/soundboard/soundboard_emoji_view.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/utils/autofill_utils.dart';
import 'package:intergalactic/utils/custom_sound_manager.dart';
import 'package:mime/mime.dart' as mime;
import 'package:tiamat/tiamat.dart' as tiamat;

class SpaceSoundboardSettingsPage extends StatefulWidget {
  const SpaceSoundboardSettingsPage({required this.space, super.key});

  final Space space;

  @override
  State<SpaceSoundboardSettingsPage> createState() =>
      _SpaceSoundboardSettingsPageState();
}

class _SpaceSoundboardSettingsPageState
    extends State<SpaceSoundboardSettingsPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emojiController = TextEditingController(
    text: '🔊',
  );
  final TextEditingController _packNameController = TextEditingController();
  StreamSubscription? _subscription;
  StreamSubscription? _globalLibrarySubscription;

  Uint8List? _selectedBytes;
  String? _selectedMimeType;
  String? _selectedFileName;
  double _uploadVolume = SoundboardSound.defaultVolume;
  String _uploadPackId = '';
  final Map<String, double> _draftSoundVolumes = {};
  final Set<String> _expandedPackIds = {};
  final Set<String> _savingSoundVolumeIds = {};
  final Set<String> _savingPackIds = {};
  final Set<String> _savingGlobalPackIds = {};
  bool _isUploading = false;
  bool _isSavingJoinSound = false;
  bool _isCreatingPack = false;
  bool _isSavingProtection = false;
  bool _isSavingExternalPackPolicy = false;
  String? _externalPackPolicyError;
  String? _protectionError;

  SoundboardComponent get soundboard =>
      widget.space.getComponent<SoundboardComponent>()!;

  SoundboardLibraryComponent? get globalLibrary =>
      widget.space.client.getComponent<SoundboardLibraryComponent>();

  String? get userId {
    final client = widget.space.client;
    if (client is MatrixClient) {
      return client.matrixClient.userID ?? client.self?.identifier;
    }

    return client.self?.identifier;
  }

  @override
  void initState() {
    super.initState();
    _subscription = soundboard.onChanged.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
    _globalLibrarySubscription = globalLibrary?.onChanged.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _globalLibrarySubscription?.cancel();
    _nameController.dispose();
    _emojiController.dispose();
    _packNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = userId;
    final sounds = soundboard.sounds;
    final emojiPacks = soundboardEmojiPacksForSpace(widget.space);
    final selectedJoinSound = currentUserId == null
        ? null
        : soundboard.getJoinSoundId(currentUserId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _protectionSection(),
        _externalPackPolicySection(),
        SettingsSection(
          title: 'Call Soundboard',
          children: [
            SettingsControlRow(
              title: 'Shared call sounds',
              description:
                  'Sounds are shared across this server and appear in the call panel while you are connected to a voice room.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _uploadPermissionStatus(),
                  const SizedBox(height: 12),
                  if (!soundboard.canUploadSound) _uploadPermissionNotice(),
                  if (soundboard.canUploadSound) _uploadForm(emojiPacks),
                  const SizedBox(height: 20),
                  _joinSoundPicker(sounds, selectedJoinSound, emojiPacks),
                ],
              ),
            ),
          ],
        ),
        SettingsSection(
          title: 'Sound Packs',
          showDivider: false,
          children: [
            SettingsControlRow(
              title: 'Packs in this space',
              description:
                  'Sounds are grouped into packs. Your packs are active for you automatically; turn other members’ packs on to add them to your call soundboard.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_showPackPermissionRepair) ...[
                    _packPermissionRepairCard(),
                    const SizedBox(height: 12),
                  ],
                  if (soundboard.canCreatePack) ...[
                    _createPackCard(),
                    const SizedBox(height: 12),
                  ],
                  if (soundboard.packs.isEmpty)
                    tiamat.Text.labelLow('No sounds have been uploaded yet.')
                  else
                    ...soundboard.packs.map(
                      (pack) => _packCard(
                        pack,
                        emojiPacks: emojiPacks,
                        currentUserId: currentUserId,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// U6: whether packs owned by *other* spaces may be played into this one.
  /// Separate from Enhanced Protection — that governs who may write this
  /// space's own sounds, this governs what may be played here from elsewhere.
  Widget _externalPackPolicySection() {
    if (!soundboard.canManageDestinationPolicy) {
      return const SizedBox.shrink();
    }
    final allowed = soundboard.destinationPolicy.allowExternalPacks;
    return SettingsSection(
      title: 'External Sound Packs',
      children: [
        SettingsControlRow(
          title: 'Packs from other spaces',
          description:
              'Members can enable sound packs from their other spaces and bring '
              'them into calls. Turn this off to allow only packs that belong to '
              'this space. This does not change this space\'s own soundboard.',
          child: _settingsSurfaceCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      tiamat.Text.labelEmphasised(
                        allowed
                            ? 'External packs are allowed'
                            : 'External packs are blocked',
                      ),
                      const SizedBox(height: 2),
                      tiamat.Text.labelLow(
                        allowed
                            ? 'Members may play packs they enabled from other spaces.'
                            : 'Only this space\'s own sound packs can be played here.',
                      ),
                    ],
                  ),
                ),
                if (_isSavingExternalPackPolicy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch.adaptive(
                    key: const ValueKey('soundboard-external-packs-toggle'),
                    value: allowed,
                    onChanged: _setAllowExternalPacks,
                  ),
              ],
            ),
          ),
        ),
        if (_externalPackPolicyError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: tiamat.Text.labelLow(_externalPackPolicyError!),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _setAllowExternalPacks(bool allow) async {
    setState(() {
      _isSavingExternalPackPolicy = true;
      _externalPackPolicyError = null;
    });
    try {
      await soundboard.setAllowExternalPacks(allow);
      if (mounted) {
        _showSnack(
          allow
              ? 'External sound packs allowed.'
              : 'External sound packs blocked.',
        );
      }
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to change the soundboard external pack policy in '
            '${widget.space.identifier}',
      );
      if (mounted) {
        setState(() => _externalPackPolicyError = _stripExceptionPrefix(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingExternalPackPolicy = false);
      }
    }
  }

  /// Admin-only opt-in toggle for service-backed enhanced protection. Hidden
  /// for clients that do not support it and for members who cannot manage it.
  Widget _protectionSection() {
    if (!soundboard.supportsProtection || !soundboard.canManageProtection) {
      return const SizedBox.shrink();
    }
    final isProtected = soundboard.isProtected;
    return SettingsSection(
      title: 'Enhanced Protection',
      children: [
        SettingsControlRow(
          title: 'Server-managed sounds',
          description:
              'When on, sound packs and sounds in this space are written through '
              'the Inter Galactic soundboard service and authorized server-side, '
              'protecting shared sounds from tampering. Turn it off to let '
              'members write sound state directly again.',
          child: _settingsSurfaceCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      tiamat.Text.labelEmphasised(
                        isProtected ? 'Protection is on' : 'Protection is off',
                      ),
                      const SizedBox(height: 2),
                      tiamat.Text.labelLow(
                        isProtected
                            ? 'Shared changes go through the soundboard service.'
                            : 'Invite the soundboard service user to this space '
                                  'with admin power before turning this on.',
                      ),
                    ],
                  ),
                ),
                if (_isSavingProtection)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Switch.adaptive(
                    key: const ValueKey('soundboard-protection-toggle'),
                    value: isProtected,
                    onChanged: _setProtection,
                  ),
              ],
            ),
          ),
        ),
        if (_protectionError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _protectionError!,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  bool get _showPackPermissionRepair {
    // Spaces that opened sound uploads before packs shipped still gate pack
    // state at the default threshold; only an authorized admin can align it.
    return soundboard.canEnableMemberUploads &&
        !soundboard.canCreatePack &&
        soundboard.canUploadSound;
  }

  Widget _packPermissionRepairCard() {
    return _settingsSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tiamat.Text.labelLow(
            'Members can upload sounds here but cannot create packs yet. '
            'Align pack permissions with sound uploads to enable pack '
            'creation.',
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: tiamat.Button.secondary(
              text: 'Enable pack creation',
              onTap: _alignPackPermissions,
            ),
          ),
        ],
      ),
    );
  }

  Widget _createPackCard() {
    return _settingsSurfaceCard(
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('soundboard-create-pack-name'),
              controller: _packNameController,
              decoration: const InputDecoration(labelText: 'New pack name'),
              maxLength: 64,
              buildCounter:
                  (
                    context, {
                    required currentLength,
                    required isFocused,
                    required maxLength,
                  }) => null,
            ),
          ),
          const SizedBox(width: 12),
          tiamat.Button.secondary(
            key: const ValueKey('soundboard-create-pack'),
            text: 'Create Pack',
            isLoading: _isCreatingPack,
            onTap: _isCreatingPack ? null : _createPack,
          ),
        ],
      ),
    );
  }

  void _togglePackExpansion(String packId) {
    setState(() {
      if (!_expandedPackIds.add(packId)) {
        _expandedPackIds.remove(packId);
      }
    });
  }

  Widget _packCard(
    SoundboardPack pack, {
    required List<EmoticonPack> emojiPacks,
    required String? currentUserId,
  }) {
    final packSounds = soundboard.soundsInPack(pack.id);
    final canManagePack =
        currentUserId != null && soundboard.canManagePack(pack, currentUserId);
    final isOwn = pack.createdBy == currentUserId;
    final isActive = soundboard.isPackActive(pack);
    final isExpanded = _expandedPackIds.contains(pack.id);
    final isSaving = _savingPackIds.contains(pack.id);
    final library = globalLibrary;
    final isGlobal =
        library?.isEnabled(widget.space.identifier, pack.id) ?? false;
    final isSavingGlobal = _savingGlobalPackIds.contains(pack.id);
    final theme = Theme.of(context);
    final displayName = soundboardPackDisplayName(pack, soundboard.packs);

    // Disabled packs stay visible to their managers so they can be re-enabled,
    // but disappear for everyone else.
    if (!pack.isAvailable && !canManagePack) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: _settingsSurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _packIcon(pack, emojiPacks, theme),
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    button: true,
                    expanded: isExpanded,
                    label: '$displayName sound pack',
                    value:
                        '${packSounds.length} sound'
                        '${packSounds.length == 1 ? '' : 's'}'
                        '${!pack.isAvailable
                            ? ', disabled'
                            : isOwn
                            ? ', yours'
                            : ''}',
                    hint: isExpanded ? 'Collapse sounds' : 'Expand sounds',
                    onTap: () => _togglePackExpansion(pack.id),
                    child: ExcludeSemantics(
                      child: InkWell(
                        key: ValueKey('soundboard-pack-toggle-${pack.id}'),
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => _togglePackExpansion(pack.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            displayName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ),
                                        if (!pack.isAvailable) ...[
                                          const SizedBox(width: 8),
                                          _packBadge(
                                            'Disabled',
                                            theme.colorScheme.error,
                                          ),
                                        ] else if (isOwn) ...[
                                          const SizedBox(width: 8),
                                          _packBadge(
                                            'Yours',
                                            theme.colorScheme.primary,
                                          ),
                                        ],
                                      ],
                                    ),
                                    tiamat.Text.labelLow(
                                      '${packSounds.length} sound'
                                      '${packSounds.length == 1 ? '' : 's'} • ${pack.createdBy}',
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                isExpanded
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (isSaving)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else ...[
                  tiamat.Tooltip(
                    text: isGlobal
                        ? 'Remove pack from favorites'
                        : 'Add pack to favorites',
                    child: IconButton(
                      key: ValueKey(
                        'soundboard-global-pack-${widget.space.identifier}-${pack.id}',
                      ),
                      onPressed:
                          library == null ||
                              !pack.isAvailable ||
                              (!isGlobal &&
                                  !library.canEnable(
                                    widget.space.identifier,
                                    pack.id,
                                  )) ||
                              isSavingGlobal
                          ? null
                          : () => _setGlobalPackFavorite(pack, !isGlobal),
                      icon: isSavingGlobal
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              isGlobal ? Icons.favorite : Icons.favorite_border,
                            ),
                    ),
                  ),
                  tiamat.Tooltip(
                    text: isActive
                        ? 'Active in your call soundboard'
                        : 'Not in your call soundboard',
                    child: Switch.adaptive(
                      value: isActive,
                      onChanged: pack.isAvailable
                          ? (value) => _setPackActive(pack, value)
                          : null,
                    ),
                  ),
                  if (canManagePack)
                    PopupMenuButton<String>(
                      key: ValueKey('soundboard-pack-menu-${pack.id}'),
                      tooltip: 'Manage pack',
                      icon: const Icon(Icons.more_vert, size: 20),
                      onSelected: (action) => _handlePackAction(pack, action),
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'rename',
                          child: Text('Rename'),
                        ),
                        PopupMenuItem(
                          value: 'set_icon',
                          child: Text(
                            pack.emoji == null ? 'Set icon…' : 'Change icon…',
                          ),
                        ),
                        if (pack.emoji != null)
                          const PopupMenuItem(
                            value: 'clear_icon',
                            child: Text('Remove icon'),
                          ),
                        PopupMenuItem(
                          value: pack.enabled ? 'disable' : 'enable',
                          child: Text(
                            pack.enabled
                                ? 'Disable for everyone'
                                : 'Enable for everyone',
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete pack…'),
                        ),
                      ],
                    ),
                ],
              ],
            ),
            if (isExpanded)
              ...packSounds.map(
                (sound) => _soundRow(
                  sound,
                  emojiPacks: emojiPacks,
                  canManage:
                      currentUserId != null &&
                      soundboard.canManageSound(sound, currentUserId),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The pack's chosen emoji icon, or the default folder/legacy glyph when
  /// none is set.
  Widget _packIcon(
    SoundboardPack pack,
    List<EmoticonPack> emojiPacks,
    ThemeData theme,
  ) {
    final emoji = pack.emoji;
    if (emoji != null && emoji.isNotEmpty) {
      return SizedBox(
        width: 20,
        height: 20,
        child: Center(
          child: SoundboardEmojiView(
            value: emoji,
            packs: emojiPacks,
            size: 20,
            textStyle: theme.textTheme.bodyMedium,
          ),
        ),
      );
    }
    return Icon(
      pack.isLegacy ? Icons.history_rounded : Icons.folder_outlined,
      size: 20,
      color: theme.colorScheme.onSurfaceVariant,
    );
  }

  Widget _packBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _uploadPermissionNotice() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tiamat.Text.labelLow(
          soundboard.canEnableMemberUploads
              ? 'Your account can manage this server, but member uploads are not open yet. Enable uploads to let everyone add sounds.'
              : 'Your account does not currently have permission to upload sounds in this server.',
        ),
      ],
    );
  }

  Widget _uploadPermissionStatus() {
    final uploadLevel = soundboard.soundUploadPowerLevel;
    final userLevel = soundboard.currentUserPowerLevel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tiamat.Text.labelLow(
          soundboard.memberUploadsEnabled
              ? 'Sound uploads are open to server members.'
              : 'Sound uploads are limited to users with power level $uploadLevel or higher.',
        ),
        tiamat.Text.labelLow(
          'Your level: ${userLevel ?? 'unknown'} • Default member level: ${soundboard.defaultUserPowerLevel}',
        ),
        tiamat.Text.labelLow('Change this from the server Permissions tab.'),
      ],
    );
  }

  Widget _uploadForm(List<EmoticonPack> emojiPacks) {
    return _settingsSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 112,
                child: TextField(
                  controller: _emojiController,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    labelText: 'Emoji',
                    counterText: '',
                    suffixIcon: IconButton(
                      tooltip: 'Choose emoji',
                      icon: const Icon(Icons.emoji_emotions_outlined),
                      onPressed: () => _showEmojiPicker(emojiPacks),
                    ),
                  ),
                  maxLength: 64,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Sound name'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _volumeSlider(
            label: 'Sound volume',
            value: _uploadVolume,
            onChanged: (value) {
              setState(() => _uploadVolume = value);
            },
          ),
          const SizedBox(height: 8),
          _uploadPackPicker(),
          const SizedBox(height: 8),
          _uploadFileActions(),
        ],
      ),
    );
  }

  Widget _uploadPackPicker() {
    final currentUserId = userId;
    if (currentUserId == null) {
      return const SizedBox.shrink();
    }

    final ownLegacyId = SoundboardPack.legacyIdForUploader(currentUserId);
    final allPacks = soundboard.packs;
    final destinations = allPacks
        .where(
          (pack) =>
              pack.isAvailable &&
              pack.id != ownLegacyId &&
              soundboard.canManagePack(pack, currentUserId),
        )
        .toList();
    // The empty option targets the uploader's own legacy pack (reference-free
    // upload). Show that pack's current name so renaming it is reflected here,
    // instead of a hardcoded label that drifts from the pack list.
    final ownLegacyPack = allPacks.firstWhereOrNull(
      (pack) => pack.id == ownLegacyId,
    );
    final ownLegacyName = ownLegacyPack == null
        ? null
        : soundboardPackDisplayName(ownLegacyPack, allPacks);
    final items = ['', ...destinations.map((pack) => pack.id)];
    final selectedValue = items.contains(_uploadPackId) ? _uploadPackId : '';

    return Row(
      children: [
        tiamat.Text.labelLow('Add to pack'),
        const SizedBox(width: 12),
        Expanded(
          child: tiamat.DropdownSelector<String>(
            color: Theme.of(context).colorScheme.surfaceContainer,
            value: selectedValue,
            items: items,
            itemBuilder: (item) {
              if (item.isEmpty) {
                return Text(
                  ownLegacyName ?? 'My sounds',
                  overflow: TextOverflow.ellipsis,
                );
              }
              final pack = destinations.firstWhereOrNull(
                (candidate) => candidate.id == item,
              );
              return Text(
                pack == null ? item : soundboardPackDisplayName(pack, allPacks),
                overflow: TextOverflow.ellipsis,
              );
            },
            onItemSelected: (value) {
              setState(() => _uploadPackId = value ?? '');
            },
          ),
        ),
      ],
    );
  }

  Widget _uploadFileActions() {
    final fileText = _selectedFileName == null
        ? 'MP3, OGG, WAV, M4A, FLAC, AAC, or WEBM up to 2 MB.'
        : 'Selected $_selectedFileName (${_formatBytes(_selectedBytes?.length ?? 0)})';

    return LayoutBuilder(
      builder: (context, constraints) {
        final useCompactLayout = Layout.mobile || constraints.maxWidth < 520;
        final chooseButton = tiamat.Button.secondary(
          text: 'Choose Audio',
          onTap: _pickAudio,
        );
        final uploadButton = tiamat.Button(
          text: 'Upload',
          isLoading: _isUploading,
          onTap: _selectedBytes == null ? null : _uploadSound,
        );

        if (useCompactLayout) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tiamat.Text.labelLow(fileText),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: chooseButton),
                  const SizedBox(width: 10),
                  Expanded(child: uploadButton),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: tiamat.Text.labelLow(fileText)),
            const SizedBox(width: 8),
            chooseButton,
            const SizedBox(width: 8),
            uploadButton,
          ],
        );
      },
    );
  }

  Widget _joinSoundPicker(
    List<SoundboardSound> sounds,
    String? selectedId,
    List<EmoticonPack> emojiPacks,
  ) {
    final items = ['', ...sounds.map((sound) => sound.id)];
    final selectedValue = sounds.any((sound) => sound.id == selectedId)
        ? selectedId!
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tiamat.Text.labelEmphasised('Join Sound'),
        tiamat.Text.labelLow(
          'Pick a sound that plays for people in the call when you enter a voice room.',
        ),
        const SizedBox(height: 8),
        _settingsSurfaceCard(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Expanded(
                child: tiamat.DropdownSelector<String>(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  value: selectedValue,
                  items: items,
                  itemBuilder: (item) {
                    if (item.isEmpty) {
                      return const Text('No join sound');
                    }

                    final sound = _soundById(sounds, item);
                    if (sound == null) {
                      return Text(item, overflow: TextOverflow.ellipsis);
                    }

                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SoundboardEmojiView(
                          value: sound.emoji,
                          packs: emojiPacks,
                          size: 20,
                          textStyle: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            sound.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    );
                  },
                  onItemSelected: (value) {
                    if (_isSavingJoinSound) {
                      return;
                    }
                    _setJoinSound(value);
                  },
                ),
              ),
              if (_isSavingJoinSound) ...[
                const SizedBox(width: 12),
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  SoundboardSound? _soundById(List<SoundboardSound> sounds, String id) {
    for (final sound in sounds) {
      if (sound.id == id) {
        return sound;
      }
    }

    return null;
  }

  Widget _settingsSurfaceCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.72)),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: padding,
      child: child,
    );
  }

  Widget _soundRow(
    SoundboardSound sound, {
    required List<EmoticonPack> emojiPacks,
    required bool canManage,
  }) {
    final draftVolume = _draftSoundVolumes[sound.id] ?? sound.volume;
    final isSavingVolume = _savingSoundVolumeIds.contains(sound.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: _settingsSurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 42,
                  height: 42,
                  child: Center(
                    child: SoundboardEmojiView(
                      value: sound.emoji,
                      packs: emojiPacks,
                      size: 28,
                      textStyle: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sound.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      tiamat.Text.labelLow(
                        '${_formatBytes(sound.sizeBytes)} • ${_formatVolume(sound.volume)} • ${sound.uploadedBy}',
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Preview',
                  icon: const Icon(Icons.play_arrow),
                  onPressed: () => soundboardPlaybackService.playPreview(
                    widget.space.client as MatrixClient,
                    sound.copyWith(volume: draftVolume),
                  ),
                ),
                if (canManage) ...[
                  IconButton(
                    tooltip: 'Move to pack',
                    icon: const Icon(Icons.drive_file_move_outline),
                    onPressed: () => _moveSound(sound),
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteSound(sound),
                  ),
                ],
              ],
            ),
            if (canManage)
              Padding(
                padding: const EdgeInsets.only(left: 52, top: 4),
                child: _volumeSlider(
                  label: 'Shared volume',
                  value: draftVolume,
                  enabled: !isSavingVolume,
                  trailing: isSavingVolume
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onChanged: (value) {
                    setState(() {
                      _draftSoundVolumes[sound.id] =
                          SoundboardSound.normalizeVolume(value);
                    });
                  },
                  onChangeEnd: (value) => _setSoundVolume(sound, value),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _volumeSlider({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    ValueChanged<double>? onChangeEnd,
    bool enabled = true,
    Widget? trailing,
  }) {
    final normalizedValue = SoundboardSound.normalizeVolume(value);
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: labelStyle?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              _formatVolume(normalizedValue),
              style: labelStyle?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing],
          ],
        ),
        Slider(
          value: normalizedValue,
          min: SoundboardSound.minVolume,
          max: SoundboardSound.maxVolume,
          divisions: 30,
          label: _formatVolume(normalizedValue),
          onChanged: enabled ? onChanged : null,
          onChangeEnd: enabled ? onChangeEnd : null,
        ),
      ],
    );
  }

  Future<void> _showEmojiPicker(List<EmoticonPack> packs) async {
    final slug = await _pickEmoji(packs);
    if (slug != null) {
      _emojiController.text = slug;
    }
  }

  /// Opens the shared soundboard emoji picker and returns the chosen slug, or
  /// null if dismissed. Used both by the sound upload form and the pack icon.
  Future<String?> _pickEmoji(List<EmoticonPack> packs) async {
    if (!mounted) {
      return null;
    }

    String? selected;
    await AdaptiveDialog.show(
      context,
      title: 'Choose Emoji',
      scrollable: false,
      builder: (dialogContext) {
        return SizedBox(
          width: Layout.desktop ? 560 : null,
          height: 420,
          child: EmojiPicker(
            packs,
            onlyEmoji: true,
            preferredTooltipDirection: AxisDirection.down,
            packListAxis: Axis.horizontal,
            searchDelegate: (search) => _searchSoundboardEmoji(search, packs),
            onEmoticonPressed: (emoticon) {
              selected = emoticon.slug;
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
          ),
        );
      },
    );
    return selected;
  }

  List<AutofillSearchResultEmoticon> _searchSoundboardEmoji(
    String search,
    List<EmoticonPack> packs,
  ) {
    final query = search.toLowerCase().trim();
    if (query.isEmpty) {
      return const [];
    }

    final results = <AutofillSearchResultEmoticon>[];
    var searchOrder = 0;
    for (final pack in packs) {
      for (final emoji in pack.emoji) {
        final order = searchOrder++;
        final shortcode = emoji.shortcode;
        final slug = _safeEmoticonSlug(emoji);
        final effectiveShortcode = shortcode ?? slug;
        final score = _scoreSoundboardEmojiMatch(
          query: query,
          shortcode: effectiveShortcode,
          slug: slug,
          order: order,
        );
        if (score == null) {
          continue;
        }
        results.add(
          AutofillSearchResultEmoticon(
            effectiveShortcode,
            slug,
            emoji,
            score: score,
          ),
        );
      }
    }

    results.sort((a, b) => a.score.compareTo(b.score));
    return results.take(50).toList(growable: false);
  }

  String _safeEmoticonSlug(Emoticon emoji) {
    try {
      return emoji.slug;
    } catch (_) {
      final shortcode = emoji.shortcode;
      if (shortcode != null) {
        return ':$shortcode:';
      }
      return emoji.key;
    }
  }

  double? _scoreSoundboardEmojiMatch({
    required String query,
    required String shortcode,
    required String slug,
    required int order,
  }) {
    final normalizedShortcode = shortcode.toLowerCase();
    final normalizedSlug = slug.toLowerCase();
    final shortcodeIndex = normalizedShortcode.indexOf(query);
    final slugIndex = normalizedSlug.indexOf(query);

    if (shortcodeIndex < 0 && slugIndex < 0) {
      return null;
    }

    final orderTieBreak = order / 1000000;
    if (normalizedShortcode == query || normalizedSlug == query) {
      return orderTieBreak;
    }

    if (normalizedShortcode.startsWith(query)) {
      return 10 + orderTieBreak;
    }

    if (normalizedSlug.startsWith(query)) {
      return 20 + orderTieBreak;
    }

    if (shortcodeIndex >= 0 && slugIndex >= 0) {
      final bestIndex = shortcodeIndex < slugIndex ? shortcodeIndex : slugIndex;
      final slugOnlyPenalty = slugIndex < shortcodeIndex ? 0.25 : 0;
      return 100 + bestIndex + slugOnlyPenalty + orderTieBreak;
    }

    if (shortcodeIndex >= 0) {
      return 100 + shortcodeIndex + orderTieBreak;
    }

    return 100 + slugIndex + 0.25 + orderTieBreak;
  }

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: CustomSoundManager.allowedExtensions,
      withData: true,
      dialogTitle: 'Pick soundboard audio',
    );
    final file = result == null || result.files.isEmpty
        ? null
        : result.files.first;
    final bytes = file?.bytes;
    if (file == null || bytes == null) {
      return;
    }

    if (bytes.length > SoundboardComponent.maxSoundBytes) {
      _showSnack('Soundboard sounds must be 2 MB or smaller.');
      return;
    }

    final detectedMime = mime.lookupMimeType(
      file.name,
      headerBytes: bytes.take(24).toList(),
    );
    if (detectedMime == null || !detectedMime.startsWith('audio/')) {
      _showSnack('Please choose an audio file.');
      return;
    }

    setState(() {
      _selectedBytes = bytes;
      _selectedMimeType = detectedMime;
      _selectedFileName = file.name;
      if (_nameController.text.trim().isEmpty) {
        _nameController.text = _nameFromFile(file);
      }
    });
  }

  /// The selected upload pack, but only when it is still an available,
  /// manageable destination. Mirrors the dropdown's `destinations` filter so a
  /// pack that dropped out of the list (deleted, disabled, or no longer
  /// manageable) falls back to "My sounds" instead of targeting a stale hidden
  /// pack.
  String? _availableUploadPackId() {
    if (_uploadPackId.isEmpty) {
      return null;
    }
    final currentUserId = userId;
    if (currentUserId == null) {
      return null;
    }
    final ownLegacyId = SoundboardPack.legacyIdForUploader(currentUserId);
    final stillAvailable = soundboard.packs.any(
      (pack) =>
          pack.id == _uploadPackId &&
          pack.isAvailable &&
          pack.id != ownLegacyId &&
          soundboard.canManagePack(pack, currentUserId),
    );
    return stillAvailable ? _uploadPackId : null;
  }

  Future<void> _uploadSound() async {
    final bytes = _selectedBytes;
    final mimeType = _selectedMimeType;
    if (bytes == null || mimeType == null) {
      return;
    }

    final name = _nameController.text.trim();
    final emoji = _emojiController.text.trim();
    if (name.isEmpty || emoji.isEmpty) {
      _showSnack('Add a name and emoji for this sound.');
      return;
    }

    setState(() => _isUploading = true);
    try {
      await soundboard.uploadSound(
        name: name,
        emoji: emoji,
        bytes: bytes,
        mimeType: mimeType,
        volume: _uploadVolume,
        packId: _availableUploadPackId(),
      );
      if (!mounted) return;
      setState(() {
        _selectedBytes = null;
        _selectedMimeType = null;
        _selectedFileName = null;
        _uploadVolume = SoundboardSound.defaultVolume;
        _nameController.clear();
        _emojiController.text = '🔊';
      });
      _showSnack('Sound uploaded.');
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Soundboard upload failed from settings for '
            '${widget.space.identifier}',
      );
      _showSnack(error.toString());
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<void> _setSoundVolume(SoundboardSound sound, double volume) async {
    final normalizedVolume = SoundboardSound.normalizeVolume(volume);
    setState(() {
      _draftSoundVolumes[sound.id] = normalizedVolume;
      _savingSoundVolumeIds.add(sound.id);
    });
    try {
      await soundboard.updateSoundVolume(sound, normalizedVolume);
      if (!mounted) return;
      setState(() {
        _draftSoundVolumes.remove(sound.id);
      });
      _showSnack('Sound volume updated.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _draftSoundVolumes.remove(sound.id);
      });
      _showSnack(error.toString());
    } finally {
      if (mounted) {
        setState(() => _savingSoundVolumeIds.remove(sound.id));
      }
    }
  }

  Future<void> _deleteSound(SoundboardSound sound) async {
    try {
      await soundboard.deleteSound(sound);
      if (mounted) {
        _showSnack('Sound deleted.');
      }
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  Future<void> _createPack() async {
    final name = _packNameController.text.trim();
    if (name.isEmpty) {
      _showSnack('Add a name for this pack.');
      return;
    }

    setState(() => _isCreatingPack = true);
    try {
      await soundboard.createPack(name);
      if (!mounted) return;
      _packNameController.clear();
      _showSnack('Pack created.');
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to create soundboard pack in '
            '${widget.space.identifier}',
      );
      _showSnack(error.toString());
    } finally {
      if (mounted) {
        setState(() => _isCreatingPack = false);
      }
    }
  }

  Future<void> _alignPackPermissions() async {
    try {
      await soundboard.alignPackCreationPermission();
      if (mounted) {
        _showSnack('Pack creation now follows the sound-upload permission.');
      }
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  Future<void> _setProtection(bool enable) async {
    if (!enable) {
      final confirmed = await AdaptiveDialog.confirmation(
        context,
        title: 'Turn off enhanced protection?',
        prompt:
            'Members will be able to write sound packs and sounds in this space '
            'directly again. Existing sounds are unaffected.',
        confirmationText: 'Turn off',
        dangerous: true,
      );
      if (confirmed != true) {
        return;
      }
      if (!mounted) {
        return;
      }
    }

    setState(() {
      _isSavingProtection = true;
      _protectionError = null;
    });
    try {
      if (enable) {
        await soundboard.enableProtection();
      } else {
        await soundboard.disableProtection();
      }
      if (mounted) {
        _showSnack(
          enable
              ? 'Enhanced protection enabled.'
              : 'Enhanced protection turned off.',
        );
      }
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to change soundboard protection in '
            '${widget.space.identifier}',
      );
      // Keep the failure visible under the toggle: enable failures are usually
      // an actionable setup step (e.g. "Grant the service user power level N")
      // that a transient snackbar loses.
      if (mounted) {
        setState(() => _protectionError = _stripExceptionPrefix(error));
      }
      _showSnack(error.toString());
    } finally {
      if (mounted) {
        setState(() => _isSavingProtection = false);
      }
    }
  }

  /// Trims the leading "Exception: " that `Object.toString()` adds so the inline
  /// message reads as plain guidance.
  String _stripExceptionPrefix(Object error) {
    const prefix = 'Exception: ';
    final text = error.toString();
    return text.startsWith(prefix) ? text.substring(prefix.length) : text;
  }

  Future<void> _setPackActive(SoundboardPack pack, bool active) async {
    setState(() => _savingPackIds.add(pack.id));
    try {
      await soundboard.setPackActive(pack, active);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to change personal soundboard pack activation in '
            '${widget.space.identifier}',
      );
      _showSnack(error.toString());
    } finally {
      if (mounted) {
        setState(() => _savingPackIds.remove(pack.id));
      }
    }
  }

  /// Mirrors the emoji-pack heart: this is account-global discovery, not the
  /// per-space active switch beside it. The pack remains owned by this space
  /// and can only play elsewhere when that destination permits external packs.
  Future<void> _setGlobalPackFavorite(SoundboardPack pack, bool enabled) async {
    final library = globalLibrary;
    if (library == null) {
      return;
    }

    setState(() => _savingGlobalPackIds.add(pack.id));
    try {
      if (enabled) {
        await library.enablePack(widget.space.identifier, pack.id);
      } else {
        await library.disablePack(widget.space.identifier, pack.id);
      }
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to change global soundboard pack favorite in '
            '${widget.space.identifier}',
      );
      if (mounted) {
        _showSnack('Could not update pack favorite state.');
      }
    } finally {
      if (mounted) {
        setState(() => _savingGlobalPackIds.remove(pack.id));
      }
    }
  }

  Future<void> _handlePackAction(SoundboardPack pack, String action) async {
    switch (action) {
      case 'rename':
        await _renamePack(pack);
      case 'set_icon':
        await _setPackIcon(pack);
      case 'clear_icon':
        await _savePackEmoji(pack, null);
      case 'enable':
        await _setPackEnabled(pack, true);
      case 'disable':
        await _setPackEnabled(pack, false);
      case 'delete':
        await _deletePack(pack);
    }
  }

  Future<void> _setPackIcon(SoundboardPack pack) async {
    final slug = await _pickEmoji(soundboardEmojiPacksForSpace(widget.space));
    if (slug == null) {
      return;
    }
    await _savePackEmoji(pack, slug);
  }

  Future<void> _savePackEmoji(SoundboardPack pack, String? emoji) async {
    setState(() => _savingPackIds.add(pack.id));
    try {
      await soundboard.setPackEmoji(pack, emoji);
    } catch (error) {
      _showSnack(error.toString());
    } finally {
      if (mounted) {
        setState(() => _savingPackIds.remove(pack.id));
      }
    }
  }

  Future<void> _renamePack(SoundboardPack pack) async {
    final name = await AdaptiveDialog.textPrompt(
      context,
      title: 'Rename Pack',
      initialText: pack.name,
    );
    if (name == null || name.trim().isEmpty || name.trim() == pack.name) {
      return;
    }

    setState(() => _savingPackIds.add(pack.id));
    try {
      await soundboard.renamePack(pack, name);
    } catch (error) {
      _showSnack(error.toString());
    } finally {
      if (mounted) {
        setState(() => _savingPackIds.remove(pack.id));
      }
    }
  }

  Future<void> _setPackEnabled(SoundboardPack pack, bool enabled) async {
    setState(() => _savingPackIds.add(pack.id));
    try {
      await soundboard.setPackEnabled(pack, enabled);
      if (mounted) {
        _showSnack(
          enabled
              ? 'Pack enabled for everyone.'
              : 'Pack disabled. Its sounds no longer play until it is '
                    'enabled again.',
        );
      }
    } catch (error) {
      _showSnack(error.toString());
    } finally {
      if (mounted) {
        setState(() => _savingPackIds.remove(pack.id));
      }
    }
  }

  Future<void> _deletePack(SoundboardPack pack) async {
    final soundCount = soundboard.soundsInPack(pack.id).length;
    final confirmed = await AdaptiveDialog.confirmation(
      context,
      title: 'Delete sound pack?',
      prompt:
          'Deleting **${pack.name}** permanently removes the pack and its '
          '$soundCount sound${soundCount == 1 ? '' : 's'} for everyone in '
          'this space. This cannot be undone.',
      confirmationText: 'Delete pack',
      dangerous: true,
    );
    if (confirmed != true) {
      return;
    }

    setState(() => _savingPackIds.add(pack.id));
    try {
      await soundboard.deletePack(pack);
      if (mounted) {
        _showSnack('Pack and contained sounds deleted.');
      }
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to delete soundboard pack in '
            '${widget.space.identifier}',
      );
      _showSnack(error.toString());
    } finally {
      if (mounted) {
        setState(() => _savingPackIds.remove(pack.id));
      }
    }
  }

  Future<void> _moveSound(SoundboardSound sound) async {
    final currentUserId = userId;
    if (currentUserId == null) {
      return;
    }

    final currentPackId = soundboard.effectivePackIdFor(sound);
    final targets = soundboard.packs
        .where(
          (pack) =>
              pack.isAvailable &&
              pack.id != currentPackId &&
              (soundboard.canManagePack(pack, currentUserId) ||
                  pack.id ==
                      SoundboardPack.legacyIdForUploader(sound.uploadedBy)),
        )
        .toList();
    if (targets.isEmpty) {
      _showSnack('There is no other pack you can move this sound into.');
      return;
    }

    final target = await AdaptiveDialog.pickOne<SoundboardPack>(
      context,
      title: 'Move to Pack',
      items: targets,
      itemBuilder: (dialogContext, pack, callback) {
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(
            pack.isLegacy ? Icons.history_rounded : Icons.folder_outlined,
            size: 18,
          ),
          title: Text(soundboardPackDisplayName(pack, soundboard.packs)),
          onTap: callback,
        );
      },
    );
    if (target == null) {
      return;
    }

    // Resolve the caption the member actually picked, before the move. The
    // dialog rows above are captioned with `soundboardPackDisplayName`, which
    // numbers duplicate `Legacy sounds` packs; `target.name` is the raw stored
    // name, so choosing `Legacy sounds 2` used to confirm `Moved to Legacy
    // sounds.` Resolving beforehand also keeps the caption stable if the pack
    // list shifts while the move is in flight.
    final targetDisplayName = soundboardPackDisplayName(
      target,
      soundboard.packs,
    );

    try {
      await soundboard.moveSoundToPack(sound, target.id);
      if (mounted) {
        _showSnack('Moved to $targetDisplayName.');
      }
    } catch (error) {
      _showSnack(error.toString());
    }
  }

  Future<void> _setJoinSound(String? value) async {
    final currentUserId = userId;
    if (currentUserId == null) {
      return;
    }

    setState(() => _isSavingJoinSound = true);
    try {
      await soundboard.setJoinSoundForUser(
        currentUserId,
        value == null || value.isEmpty ? null : value,
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content:
            'Failed to set soundboard join sound for '
            '${widget.space.identifier}',
      );
      _showSnack(error.toString());
    } finally {
      if (mounted) {
        setState(() => _isSavingJoinSound = false);
      }
    }
  }

  String _nameFromFile(PlatformFile file) {
    final dot = file.name.lastIndexOf('.');
    if (dot <= 0) {
      return file.name;
    }
    return file.name.substring(0, dot);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatVolume(double volume) {
    return '${SoundboardSound.normalizeVolume(volume).round()}%';
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    // Some actions (notably enabling enhanced protection) trigger a space
    // update that briefly rebuilds this surface. Presenting a SnackBar during
    // that gap throws "no descendant Scaffolds to present to". Defer to the
    // next frame and only present once a Scaffold is available again, so the
    // confirmation still shows without crashing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || Scaffold.maybeOf(context) == null) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    });
  }
}
