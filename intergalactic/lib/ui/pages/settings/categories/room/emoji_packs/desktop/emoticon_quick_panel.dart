import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_draft_store_models.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/controls/emoticon_editor_controls.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/desktop/emoticon_editor_desktop.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/emoticon_editor_controller.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:intergalactic/utils/picker_utils.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The desktop host for the two-UI split (R10): a compact Quick surface
/// (crop · name · usage · save) inside the existing `PopupDialog`, with an
/// "Advanced edit" affordance that swaps the dialog body to the two-pane
/// Editor (U10) and back. Presentation stays a desktop dialog (R12).
class EmoticonCreatorDesktop extends StatefulWidget {
  const EmoticonCreatorDesktop({
    required this.controller,
    this.creatingNew = false,
    this.pickSourceImage,
    super.key,
  });

  final EmoticonEditorController controller;
  final bool creatingNew;
  final Future<PickerResult?> Function()? pickSourceImage;

  @override
  State<EmoticonCreatorDesktop> createState() => _EmoticonCreatorDesktopState();
}

class _EmoticonCreatorDesktopState extends State<EmoticonCreatorDesktop> {
  bool editorOpen = false;

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
    } catch (_) {
      if (!mounted) {
        return;
      }
      controller.reportSourceImageError('This photo could not be loaded.');
    }
  }

  Future<void> _cropSourceImage() async {
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
    } catch (_) {
      if (!mounted) {
        return;
      }
      controller.reportSourceImageError('This image could not be cropped.');
    }
  }

  Future<bool> _confirmDeleteDraft(EmoticonDraft draft) async {
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

  Future<bool> _confirmDeleteDrafts(List<EmoticonDraft> drafts) async {
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

  void _openEditor() {
    controller.beginEditSession();
    setState(() {
      editorOpen = true;
    });
  }

  void _closeEditor({required bool commit}) {
    if (commit) {
      controller.commitEditSession();
    } else {
      controller.discardEditSession();
    }
    setState(() {
      editorOpen = false;
    });
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
    return AnimatedSize(
      duration: InterGalacticMotion.duration(
        context,
        InterGalacticMotion.standard,
      ),
      curve: InterGalacticMotion.standardOut,
      child: editorOpen
          ? EmoticonEditorDesktop(
              controller: controller,
              onDone: () => _closeEditor(commit: true),
              onBack: () => _closeEditor(commit: false),
              onPickSourceImage: () => unawaited(_pickSourceImage()),
              onCropRequested: () => unawaited(_cropSourceImage()),
              confirmDeleteDraft: _confirmDeleteDraft,
              confirmDeleteDrafts: _confirmDeleteDrafts,
            )
          : _buildQuickPanel(context),
    );
  }

  Widget _buildQuickPanel(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final validation = controller.validateShortcode();
        final hasSource = controller.sourceImageData != null;

        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedOpacity(
                opacity: controller.loading ? 0.55 : 1,
                duration: Durations.short2,
                child: IgnorePointer(
                  ignoring: controller.loading,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 64,
                              height: 64,
                              child: EmoticonImagePickTile(
                                image: controller.image,
                                tooltip: hasSource
                                    ? EmoticonCreatorStrings.promptChangePhoto
                                    : EmoticonCreatorStrings.promptSelectPhoto,
                                onTap: () => unawaited(_pickSourceImage()),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  tiamat.TextInput(
                                    maxLines: 1,
                                    placeholder:
                                        EmoticonCreatorStrings.promptEmoteName,
                                    controller: controller.shortcodeController,
                                    onChanged: (_) =>
                                        controller.notifyShortcodeChanged(),
                                  ),
                                  if (!validation.isValid &&
                                      controller
                                          .shortcodeController
                                          .text
                                          .isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      validation.message ?? '',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: theme.colorScheme.error,
                                            fontSize: 12,
                                          ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            SizedBox(
                              width: 200,
                              height: 42,
                              child: _buildUsageDropdown(),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 110,
                              height: 42,
                              child: tiamat.Button.secondary(
                                key: const ValueKey('emoticon-quick-crop'),
                                text: EmoticonCreatorStrings.promptCropPhoto,
                                onTap:
                                    !hasSource ||
                                        controller.loading ||
                                        controller.processingCutout
                                    ? null
                                    : () => unawaited(_cropSourceImage()),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 42,
                          child: tiamat.Button.secondary(
                            key: const ValueKey('emoticon-advanced-edit'),
                            // Always reachable: the Editor also hosts Drafts
                            // and photo actions, so it must open even before
                            // a source photo is chosen.
                            text:
                                '${EmoticonCreatorStrings.promptAdvancedEdit} — cutout & brush',
                            onTap: _openEditor,
                          ),
                        ),
                        EmoticonStatusMessages(controller: controller),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            if (!widget.creatingNew) ...[
                              SizedBox(
                                width: 132,
                                height: 44,
                                child: tiamat.Button.danger(
                                  key: const ValueKey('emoticon-quick-delete'),
                                  text: CommonStrings.promptDelete,
                                  onTap: controller.loading ? null : _delete,
                                ),
                              ),
                              const Spacer(),
                            ] else
                              const Spacer(),
                            SizedBox(
                              width: 180,
                              height: 44,
                              child: tiamat.Button(
                                key: const ValueKey('emoticon-quick-save'),
                                text: EmoticonCreatorStrings
                                    .promptConfirmSaveEmoticon,
                                isLoading: controller.loading,
                                onTap: controller.canSave ? _save : null,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (controller.loading)
                const Center(child: CircularProgressIndicator()),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUsageDropdown() {
    return tiamat.DropdownSelector(
      itemHeight: 40,
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
}
