import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_component.dart';
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
  final TextEditingController _emojiController =
      TextEditingController(text: '🔊');
  StreamSubscription? _subscription;

  Uint8List? _selectedBytes;
  String? _selectedMimeType;
  String? _selectedFileName;
  double _uploadVolume = SoundboardSound.defaultVolume;
  final Map<String, double> _draftSoundVolumes = {};
  final Set<String> _savingSoundVolumeIds = {};
  bool _isUploading = false;
  bool _isSavingJoinSound = false;

  SoundboardComponent get soundboard =>
      widget.space.getComponent<SoundboardComponent>()!;

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
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _nameController.dispose();
    _emojiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = userId;
    final sounds = soundboard.sounds;
    final emojiPacks = soundboardEmojiPacksForSpace(widget.space);
    final selectedJoinSound =
        currentUserId == null ? null : soundboard.getJoinSoundId(currentUserId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          title: 'Available Sounds',
          showDivider: false,
          children: [
            SettingsControlRow(
              title: 'Uploaded sounds',
              description: sounds.isEmpty
                  ? 'No sounds have been uploaded yet.'
                  : 'Preview, tune, or remove sounds you can manage in this space.',
              child: sounds.isEmpty
                  ? null
                  : Column(
                      children: sounds
                          .map(
                            (sound) => _soundRow(
                              sound,
                              emojiPacks: emojiPacks,
                              canManage: currentUserId != null &&
                                  soundboard.canManageSound(
                                    sound,
                                    currentUserId,
                                  ),
                            ),
                          )
                          .toList(),
                    ),
            ),
          ],
        ),
      ],
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
        tiamat.Text.labelLow(
          'Change this from the server Permissions tab.',
        ),
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
          _uploadFileActions(),
        ],
      ),
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
            Expanded(
              child: tiamat.Text.labelLow(fileText),
            ),
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
    final selectedValue =
        sounds.any((sound) => sound.id == selectedId) ? selectedId! : '';

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
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.72),
        ),
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
                if (canManage)
                  IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteSound(sound),
                  ),
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
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing,
            ],
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
    if (!mounted) {
      return;
    }

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
              _emojiController.text = emoticon.slug;
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }
            },
          ),
        );
      },
    );
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
    final file =
        result == null || result.files.isEmpty ? null : result.files.first;
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
        content: 'Soundboard upload failed from settings for '
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
        content: 'Failed to set soundboard join sound for '
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
