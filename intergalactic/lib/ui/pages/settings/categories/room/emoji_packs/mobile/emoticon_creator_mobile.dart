import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_creator_validation.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_draft_store_models.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/ui/mobile/mobile_visuals.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/controls/emoticon_editor_controls.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/emoticon_editor_controller.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/mobile/emoticon_editor_mobile.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:intergalactic/utils/picker_utils.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The mobile Quick card (R1): image tile with inline Crop, shortcode field,
/// usage dropdown, and the only Save/Delete affordances. "Advanced edit"
/// opens the canvas-dominant Editor sub-mode (R2); the Editor returns the
/// shaped image and never saves (R6).
class EmoticonCreatorMobile extends StatefulWidget {
  const EmoticonCreatorMobile({
    required this.controller,
    this.creatingNew = false,
    this.pickSourceImage,
    super.key,
  });

  final EmoticonEditorController controller;
  final bool creatingNew;
  final Future<PickerResult?> Function()? pickSourceImage;

  @override
  State<EmoticonCreatorMobile> createState() => _EmoticonCreatorMobileState();
}

class _EmoticonCreatorMobileState extends State<EmoticonCreatorMobile> {
  EmoticonEditorController get controller => widget.controller;

  Future<void> _pickSourceImage() async {
    try {
      final picked = await (widget.pickSourceImage ?? PickerUtils.pickImage)();
      if (picked == null) {
        return;
      }

      final bytes = await picked.readAsBytes();
      if (!mounted) {
        return;
      }

      controller.setSourceImage(
        bytes,
        name: picked.name,
        seedShortcode: controller.shortcodeController.text.isEmpty,
      );
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to pick an emoticon source image',
      );
      if (!mounted) {
        return;
      }
      controller.reportSourceImageError('This photo could not be loaded.');
    }
  }

  Future<void> _cropSourceImage(BuildContext context) async {
    final source = controller.sourceImageData;
    if (source == null) {
      return;
    }
    try {
      final cropped = await PickerUtils.cropImageData(context, source);
      if (cropped == null || !mounted) {
        return;
      }
      // Re-seat the cropped image as the new source; this clears any cutout
      // so the user can re-run auto/brush on the crop, or save it unedited.
      controller.setSourceImage(cropped, name: controller.sourceImageName);
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to crop an emoticon source image',
      );
      if (!mounted) {
        return;
      }
      controller.reportSourceImageError('This image could not be cropped.');
    }
  }

  Future<bool> _confirmDeleteDraft(
    BuildContext context,
    EmoticonDraft draft,
  ) async {
    final confirmed = await AdaptiveDialog.confirmation(
      context,
      title: 'Delete local draft?',
      prompt:
          'This removes the saved PNG draft from this device only. It does not remove Matrix image packs or already uploaded images.',
      confirmationText: CommonStrings.promptDelete,
      cancelText: CommonStrings.promptCancel,
      dangerous: true,
    );
    return confirmed == true;
  }

  Future<bool> _confirmDeleteDrafts(
    BuildContext context,
    List<EmoticonDraft> drafts,
  ) async {
    final draftCount = drafts.length;
    final draftLabel = draftCount == 1 ? 'draft' : 'drafts';
    final pngDraftLabel = draftCount == 1 ? 'PNG draft' : 'PNG drafts';
    final hasSearch = controller.draftSearchQuery.trim().isNotEmpty;
    final confirmed = await AdaptiveDialog.confirmation(
      context,
      title: hasSearch
          ? 'Delete matching local $draftLabel?'
          : 'Delete all local drafts?',
      prompt:
          'This removes $draftCount saved $pngDraftLabel from this device only. It does not remove Matrix image packs or already uploaded images.',
      confirmationText: CommonStrings.promptDelete,
      cancelText: CommonStrings.promptCancel,
      dangerous: true,
    );
    return confirmed == true;
  }

  Future<void> _openEditor() {
    return showEmoticonEditorMobile(
      context,
      controller: controller,
      onCropRequested: _cropSourceImage,
      onPickSourceImage: _pickSourceImage,
      confirmDeleteDraft: _confirmDeleteDraft,
      confirmDeleteDrafts: _confirmDeleteDrafts,
    );
  }

  Future<void> _save() async {
    final didSave = await controller.save();
    if (didSave && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _delete() async {
    final confirm = await AdaptiveDialog.confirmation(context);
    if (confirm != true) {
      return;
    }
    final didDelete = await controller.delete();
    if (didDelete && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final validation = controller.validateShortcode();
        final hasSource = controller.sourceImageData != null;

        return Stack(
          alignment: Alignment.center,
          children: [
            AnimatedOpacity(
              opacity: controller.loading ? 0.55 : 1,
              duration: Durations.short2,
              child: IgnorePointer(
                ignoring: controller.loading,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: MobileVisuals.screenPadding,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildImageTile(context),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildNameField(theme, validation),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(height: 44, child: _buildUsageDropdown()),
                          const SizedBox(height: 12),
                          _buildAdvancedEditButton(theme, hasSource),
                          EmoticonStatusMessages(controller: controller),
                          const SizedBox(height: 12),
                          _buildActionRow(),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (controller.loading)
              const Center(child: CircularProgressIndicator()),
          ],
        );
      },
    );
  }

  Widget _buildImageTile(BuildContext context) {
    final theme = Theme.of(context);
    final hasSource = controller.sourceImageData != null;

    return SizedBox(
      width: 76,
      height: 76,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: EmoticonImagePickTile(
              image: controller.image,
              tooltip: hasSource
                  ? EmoticonCreatorStrings.promptChangePhoto
                  : EmoticonCreatorStrings.promptSelectPhoto,
              onTap: _pickSourceImage,
            ),
          ),
          if (hasSource)
            Positioned(
              right: -6,
              bottom: -6,
              child: Material(
                color: theme.colorScheme.surfaceContainerHigh,
                shape: StadiumBorder(
                  side: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.48),
                  ),
                ),
                child: InkWell(
                  key: const ValueKey('emoticon-quick-crop'),
                  customBorder: const StadiumBorder(),
                  onTap: controller.loading || controller.processingCutout
                      ? null
                      : () => _cropSourceImage(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Text(
                      EmoticonCreatorStrings.promptCropPhoto,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNameField(
    ThemeData theme,
    EmoticonShortcodeValidationResult validation,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tiamat.TextInput(
          maxLines: 1,
          placeholder: EmoticonCreatorStrings.promptEmoteName,
          controller: controller.shortcodeController,
          onChanged: (_) => controller.notifyShortcodeChanged(),
        ),
        if (!validation.isValid &&
            controller.shortcodeController.text.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            validation.message ?? '',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildUsageDropdown() {
    return tiamat.DropdownSelector(
      itemHeight: 44,
      items: [
        EmoticonUsage.emoji,
        EmoticonUsage.sticker,
        EmoticonUsage.all,
        EmoticonUsage.inherit,
      ],
      value: controller.usage,
      onItemSelected: (item) => controller.setUsage(item!),
      itemBuilder: (item) {
        return Row(
          children: [
            Icon(switch (item) {
              EmoticonUsage.sticker => Icons.sticky_note_2,
              EmoticonUsage.emoji => Icons.emoji_emotions,
              EmoticonUsage.inherit => Icons.arrow_downward,
              EmoticonUsage.all => Icons.star,
            }),
            const SizedBox(width: 8),
            Flexible(
              child: tiamat.Text.label(switch (item) {
                EmoticonUsage.sticker => "Sticker",
                EmoticonUsage.emoji => "Emoji",
                EmoticonUsage.inherit => "Follow Pack",
                EmoticonUsage.all => "Emoji & Sticker",
              }, overflow: TextOverflow.ellipsis),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAdvancedEditButton(ThemeData theme, bool hasSource) {
    // Always reachable: the Editor hosts Drafts and — since the Photo tray and
    // the tappable empty canvas landed — photo selection, so it must open even
    // before a source photo is chosen.
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('emoticon-advanced-edit'),
        onTap: () => unawaited(_openEditor()),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.edit_outlined,
                size: 18,
                color: theme.colorScheme.onSurface,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${EmoticonCreatorStrings.promptAdvancedEdit} — cutout & brush',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionRow() {
    final saveButton = SizedBox(
      height: 44,
      child: tiamat.Button(
        key: const ValueKey('emoticon-quick-save'),
        text: EmoticonCreatorStrings.promptConfirmSaveEmoticon,
        isLoading: controller.loading,
        onTap: controller.canSave ? _save : null,
      ),
    );
    final saveToPhotosButton = controller.onSaveToPhotos == null
        ? null
        : SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              key: const ValueKey('emoticon-save-to-photos'),
              tooltip: 'Save cutout to Photos',
              onPressed: controller.canSaveToPhotos
                  ? () => unawaited(controller.saveCutoutToPhotos())
                  : null,
              icon: controller.savingToPhotos
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_rounded),
            ),
          );

    if (widget.creatingNew) {
      return Row(
        children: [
          if (saveToPhotosButton != null) ...[
            saveToPhotosButton,
            const SizedBox(width: 10),
          ],
          Expanded(child: saveButton),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 44,
            child: tiamat.Button.danger(
              key: const ValueKey('emoticon-quick-delete'),
              text: CommonStrings.promptDelete,
              onTap: controller.loading ? null : _delete,
            ),
          ),
        ),
        const SizedBox(width: 10),
        if (saveToPhotosButton != null) ...[
          saveToPhotosButton,
          const SizedBox(width: 10),
        ],
        Expanded(flex: 2, child: saveButton),
      ],
    );
  }
}
