import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_creator_validation.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_draft_store.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_draft_store_models.dart';
import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_component.dart';
import 'package:intergalactic/client/components/emoticon/image_cutout_service.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/onboarding/tutorial_anchor.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/bulk_import_view.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:intergalactic/utils/picker_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

enum _CutoutPreviewBackground { checkerboard, dark, light }

const int _draftPanelDisplayLimit = 12;
const int _draftThumbnailReadLimit = 16;

extension _CutoutPreviewBackgroundLabel on _CutoutPreviewBackground {
  String get label {
    return switch (this) {
      _CutoutPreviewBackground.checkerboard => 'Checkerboard',
      _CutoutPreviewBackground.dark => 'Dark',
      _CutoutPreviewBackground.light => 'Light',
    };
  }

  String get semanticLabel {
    return switch (this) {
      _CutoutPreviewBackground.checkerboard => 'checkerboard',
      _CutoutPreviewBackground.dark => 'dark',
      _CutoutPreviewBackground.light => 'light',
    };
  }

  IconData get icon {
    return switch (this) {
      _CutoutPreviewBackground.checkerboard => Icons.grid_4x4_rounded,
      _CutoutPreviewBackground.dark => Icons.dark_mode_outlined,
      _CutoutPreviewBackground.light => Icons.light_mode_outlined,
    };
  }
}

bool _hasManualCutoutMask(CutoutMask? workingMask, CutoutMask? autoMask) {
  if (workingMask == null || autoMask == null) {
    return false;
  }
  if (workingMask.width != autoMask.width ||
      workingMask.height != autoMask.height ||
      workingMask.alpha.length != autoMask.alpha.length) {
    return true;
  }
  for (var index = 0; index < workingMask.alpha.length; index++) {
    if (workingMask.alpha[index] != autoMask.alpha[index]) {
      return true;
    }
  }
  return false;
}

class RoomEmojiPackSettingsView extends StatefulWidget {
  const RoomEmojiPackSettingsView({
    required this.component,
    this.editable = true,
    super.key,
  });
  final EmoticonComponent component;
  final bool editable;
  @override
  State<RoomEmojiPackSettingsView> createState() =>
      _RoomEmojiPackSettingsViewState();
}

class _RoomEmojiPackSettingsViewState extends State<RoomEmojiPackSettingsView> {
  late List<EmoticonPack> packs;

  StreamSubscription? sub;
  bool canCreatePack = false;

  String get promptImportPack => Intl.message(
    "Import pack",
    name: "promptImportPack",
    desc: "Prompt to import a set of emoticons from an existing pack",
  );

  @override
  void initState() {
    super.initState();

    sub = widget.component.onStateChanged.listen((_) => updateState());

    updateState();
  }

  void updateState() {
    if (!mounted) {
      return;
    }

    setState(() {
      packs = widget.component.ownedPacks;
      canCreatePack = widget.component.canCreatePack;
    });
  }

  @override
  void dispose() {
    unawaited(sub?.cancel());
    sub = null;
    super.dispose();
  }

  void promptBulkImport() async {
    await AdaptiveDialog.show(
      context,
      title: promptImportPack,
      builder: (context) {
        return EmoticonBulkImportDialog(
          importPack: (name, avatarIndex, names, imageDatas) {
            widget.component.importEmoticonPack(
              name,
              avatarIndex,
              names,
              imageDatas,
            );
            Navigator.pop(context);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Column(
          children: packs
              .map(
                (e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withValues(alpha: 0.72),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Theme(
                      data: Theme.of(
                        context,
                      ).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        collapsedBackgroundColor: Colors.transparent,
                        backgroundColor: Colors.transparent,
                        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          12,
                          0,
                          12,
                          12,
                        ),
                        title: SizedBox(
                          height: 54,
                          child: Row(
                            children: [
                              _PackArtwork(pack: e),
                              const SizedBox(width: 12),
                              Expanded(
                                child: tiamat.Text.label(
                                  e.displayName,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (widget.editable)
                                tiamat.IconButton(
                                  size: 20,
                                  icon: Icons.edit,
                                  onPressed: () => AdaptiveDialog.show(
                                    context,
                                    builder: (context) => EmoticonCreator(
                                      pack: e,
                                      createPack: true,
                                      onCreate:
                                          (name, usage, newImageData) async {
                                            await e.updatePack(
                                              name: name,
                                              usage: usage,
                                              imageData: newImageData,
                                            );
                                            return true;
                                          },
                                      onDelete: () {
                                        return widget.component
                                            .deleteEmoticonPack(e);
                                      },
                                    ),
                                  ),
                                ),
                              if (e.isEmojiPack)
                                Icon(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.secondaryContainer,
                                  size: 20,
                                  Icons.emoji_emotions,
                                ),
                              if (e.isStickerPack)
                                Icon(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.secondaryContainer,
                                  Icons.sticky_note_2_rounded,
                                ),
                              _PackGlobalToggleAnchor(
                                enabled: identical(e, packs.first),
                                child: tiamat.IconToggle(
                                  icon: Icons.favorite,
                                  size: 17,
                                  state: e.isGloballyAvailable,
                                  onPressed: (newState) async {
                                    await e.markAsGlobal(newState);
                                    updateState();
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                        children: [
                          EmoticonPackEditor(
                            pack: e,
                            editable: widget.editable,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        if (canCreatePack)
          Align(
            alignment: Alignment.topRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                tiamat.CircleButton(
                  icon: Icons.auto_awesome_motion,
                  onPressed: promptBulkImport,
                ),
                const SizedBox(width: 10),
                tiamat.CircleButton(
                  icon: Icons.add,
                  onPressed: () => AdaptiveDialog.show(
                    context,
                    builder: (context) => EmoticonCreator(
                      createPack: true,
                      creatingNew: true,
                      onCreate: (name, usage, newImageData) async {
                        await widget.component.createEmoticonPack(
                          name,
                          newImageData,
                        );

                        return true;
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PackGlobalToggleAnchor extends StatelessWidget {
  const _PackGlobalToggleAnchor({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return child;
    }

    return TutorialAnchor(
      id: TutorialAnchorIds.emoticonHeart,
      padding: const EdgeInsets.all(6),
      child: child,
    );
  }
}

class _PackArtwork extends StatelessWidget {
  const _PackArtwork({required this.pack});

  final EmoticonPack pack;

  @override
  Widget build(BuildContext context) {
    final icon = pack.isStickerPack && !pack.isEmojiPack
        ? Icons.sticky_note_2_rounded
        : Icons.emoji_emotions_outlined;

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.48),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: pack.image == null
          ? Icon(icon, color: Theme.of(context).colorScheme.onSurfaceVariant)
          : Image(
              image: pack.image!,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
            ),
    );
  }
}

class _EmoticonArtwork extends StatelessWidget {
  const _EmoticonArtwork({required this.emoticon});

  final Emoticon emoticon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: emoticon.image == null
          ? Icon(
              emoticon.isSticker
                  ? Icons.sticky_note_2_rounded
                  : Icons.emoji_emotions_outlined,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            )
          : Image(
              image: emoticon.image!,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, error, stackTrace) {
                return Icon(
                  emoticon.isSticker
                      ? Icons.sticky_note_2_rounded
                      : Icons.emoji_emotions_outlined,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                );
              },
            ),
    );
  }
}

class EmoticonPackEditor extends StatelessWidget {
  const EmoticonPackEditor({
    required this.pack,
    this.editable = false,
    super.key,
  });
  final EmoticonPack pack;
  final bool editable;

  String get createEmoticonDialogTitle => Intl.message(
    "Create Emote",
    name: "createEmoticonDialogTitle",
    desc:
        "Title of a dialog that pops up when choosing to create a new emoticon",
  );

  String get editEmoticonDialogTitle => Intl.message(
    "Edit Emote",
    name: "editEmoticonDialogTitle",
    desc:
        "Title of a dialog that pops up when choosing to edit an existing emoticon",
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Column(
          children: pack.emotes
              .map(
                (e) => Padding(
                  padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Material(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      child: InkWell(
                        onTap: !editable
                            ? null
                            : () => AdaptiveDialog.show(
                                context,
                                title: editEmoticonDialogTitle,
                                builder: (context) => EmoticonCreator(
                                  pack: pack,
                                  initialEmoticon: e,
                                  onCreate: (name, usage, newImageData) async {
                                    await pack.updateEmoticon(
                                      previous: e,
                                      shortcode: name,
                                      usage: usage,
                                      data: newImageData,
                                    );
                                    return true;
                                  },
                                  onDelete: () async {
                                    await pack.deleteEmoticon(e);
                                  },
                                ),
                                dismissible: true,
                                scrollable: false,
                              ),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  _EmoticonArtwork(emoticon: e),
                                  const SizedBox(width: 10),
                                  tiamat.Text.label(e.shortcode!),
                                ],
                              ),
                              Row(
                                children: [
                                  if (e.isEmoji)
                                    Icon(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.secondaryContainer,
                                      size: 20,
                                      Icons.emoji_emotions,
                                    ),
                                  if (e.isSticker)
                                    Icon(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.secondaryContainer,
                                      Icons.sticky_note_2_rounded,
                                    ),
                                  if (e.usage == EmoticonUsage.inherit)
                                    Icon(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.secondaryContainer,
                                      Icons.arrow_downward,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        if (editable)
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
              child: tiamat.CircleButton(
                icon: Icons.add,
                onPressed: () => AdaptiveDialog.show(
                  context,
                  title: createEmoticonDialogTitle,
                  builder: (context) => EmoticonCreator(
                    pack: pack,
                    creatingNew: true,
                    onCreate: (name, usage, newImageData) async {
                      await pack.addEmoticon(
                        slug: name,
                        shortcode: name,
                        data: newImageData!,
                        usage: usage,
                      );

                      return true;
                    },
                  ),
                  dismissible: true,
                  scrollable: false,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class EmoticonCreator extends StatefulWidget {
  const EmoticonCreator({
    this.initialEmoticon,
    this.pack,
    this.createPack = false,
    this.onCreate,
    this.onDelete,
    this.creatingNew = false,
    this.cutoutService,
    this.draftStore,
    this.initialSourceImageData,
    this.initialSourceImageName,
    this.autoRunInitialCutout = false,
    this.pickSourceImage,
    super.key,
  });

  final Emoticon? initialEmoticon;
  final EmoticonPack? pack;
  final bool createPack;
  final bool creatingNew;
  final ImageCutoutService? cutoutService;
  final EmoticonDraftStore? draftStore;
  final Uint8List? initialSourceImageData;
  final String? initialSourceImageName;
  final bool autoRunInitialCutout;
  final Future<PickerResult?> Function()? pickSourceImage;

  final Future<bool> Function(
    String name,
    EmoticonUsage usage,
    Uint8List? newImageData,
  )?
  onCreate;

  final Future<void> Function()? onDelete;

  @override
  State<EmoticonCreator> createState() => _EmoticonCreatorState();
}

class _EmoticonCreatorState extends State<EmoticonCreator> {
  late EmoticonUsage usage;
  late final ImageCutoutService cutoutService;
  late final EmoticonDraftStore draftStore;
  ImageProvider? image;

  Uint8List? sourceImageData;
  String? sourceImageName;
  Uint8List? imageData;
  CutoutResult? cutoutResult;
  CutoutMask? autoCutoutMask;
  CutoutMask? workingMask;
  EmoticonDraft? savedDraft;
  List<EmoticonDraft> drafts = const [];
  Map<String, Uint8List> draftThumbnails = const {};
  CutoutSettings cutoutSettings = const CutoutSettings();
  ImageCutoutDiagnosticEvent? lastCutoutDiagnostic;
  _CutoutPreviewBackground previewBackground =
      _CutoutPreviewBackground.checkerboard;
  CutoutBrushMode brushMode = CutoutBrushMode.erase;
  double brushRadius = 0.05;
  double brushStrength = 1.0;
  TextEditingController controller = TextEditingController();
  bool loading = false;
  bool processingCutout = false;
  bool draftsLoading = false;
  String? errorText;
  String? statusText;
  String? draftErrorText;
  String draftSearchQuery = '';
  final TextEditingController draftSearchController = TextEditingController();
  bool brushRendering = false;
  bool brushRenderQueued = false;
  Offset? brushPreviewPosition;

  String get promptEmoticonPackName => Intl.message(
    "Pack name",
    name: "promptEmoticonPackName",
    desc: "Prompt for the input of the name of an emoticon pack",
  );

  String get promptEmoteName => Intl.message(
    "Emote name",
    name: "promptEmoteName",
    desc: "Prompt for the input of the name of an emoji",
  );

  String get promptConfirmSaveEmoticon => Intl.message(
    "Save!",
    name: "promptConfirmSaveEmoticon",
    desc:
        "Prompt to confirm the creation of an Emoticon Pack, Emoji, or Sticker",
  );

  String get promptSelectPhoto => Intl.message(
    "Select photo",
    name: "promptEmoticonCreatorSelectPhoto",
    desc: "Button text for picking a source photo for emoticon creation",
  );

  String get promptChangePhoto => Intl.message(
    "Change photo",
    name: "promptEmoticonCreatorChangePhoto",
    desc: "Button text for replacing the source photo",
  );

  String get promptCropPhoto => Intl.message(
    "Crop",
    name: "promptEmoticonCreatorCropPhoto",
    desc: "Button text for cropping the selected source photo",
  );

  String get promptAutoCutout => Intl.message(
    "Auto",
    name: "promptEmoticonCreatorAutoCutout",
    desc: "Button text for automatic background removal",
  );

  String get promptEraseBrush => Intl.message(
    "Erase",
    name: "promptEmoticonCreatorEraseBrush",
    desc: "Button text for manual erase brush",
  );

  String get promptRestoreBrush => Intl.message(
    "Restore",
    name: "promptEmoticonCreatorRestoreBrush",
    desc: "Button text for manual restore brush",
  );

  String get promptResetCutout => Intl.message(
    "Reset",
    name: "promptEmoticonCreatorResetCutout",
    desc: "Button text for resetting the generated cutout",
  );

  @override
  void initState() {
    super.initState();
    cutoutService = (widget.cutoutService ?? ImageCutoutService())
        .withAdditionalDiagnostics(_handleCutoutDiagnostics);
    draftStore = widget.draftStore ?? createEmoticonDraftStore();

    if (widget.createPack) {
      if (widget.pack != null) {
        usage = widget.pack!.usage;
        controller.text = widget.pack!.displayName;
        image = widget.pack!.image;
      } else {
        usage = EmoticonUsage.all;
      }
    } else {
      if (widget.initialEmoticon != null) {
        usage = widget.initialEmoticon!.usage;
      } else {
        usage = EmoticonUsage.inherit;
      }
      controller.text = widget.initialEmoticon?.shortcode ?? "";
      image = widget.initialEmoticon?.image;
      unawaited(_loadDrafts());
    }

    final initialSource = widget.initialSourceImageData;
    if (initialSource != null) {
      _setSourceImage(
        initialSource,
        name: widget.initialSourceImageName,
        seedShortcode: controller.text.isEmpty && !widget.createPack,
      );
      if (widget.autoRunInitialCutout) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(_runAutoCutout());
          }
        });
      }
    }
  }

  @override
  void dispose() {
    brushRenderQueued = false;
    controller.dispose();
    draftSearchController.dispose();
    super.dispose();
  }

  void _handleCutoutDiagnostics(ImageCutoutDiagnosticEvent event) {
    if (!mounted) {
      return;
    }

    setState(() {
      lastCutoutDiagnostic = event;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.createPack) {
      return _buildPackEditor(context);
    }

    return _buildCutoutEditor(context);
  }

  Widget _buildPackEditor(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedOpacity(
          opacity: loading ? 0.5 : 1,
          duration: Durations.short2,
          child: IgnorePointer(
            ignoring: loading,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 50,
                        height: 50,
                        child: _ImagePickTile(
                          image: image,
                          tooltip: promptSelectPhoto,
                          onTap: _pickPackImage,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 300),
                          child: tiamat.TextInput(
                            maxLines: 1,
                            placeholder: widget.createPack
                                ? promptEmoticonPackName
                                : promptEmoteName,
                            controller: controller,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 40,
                    width: 40,
                    child: tiamat.DropdownSelector(
                      itemHeight: 40,
                      items: [
                        EmoticonUsage.emoji,
                        EmoticonUsage.sticker,
                        EmoticonUsage.all,
                        if (!widget.createPack) EmoticonUsage.inherit,
                      ],
                      value: usage,
                      onItemSelected: (item) {
                        setState(() {
                          usage = item!;
                        });
                      },
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
                            tiamat.Text.label(switch (item) {
                              EmoticonUsage.sticker => "Sticker",
                              EmoticonUsage.emoji => "Emoji",
                              EmoticonUsage.inherit => "Follow Pack Settings",
                              EmoticonUsage.all => "Emoji & Sticker",
                            }),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 48,
                    child: tiamat.Button(
                      text: promptConfirmSaveEmoticon,
                      onTap: () async {
                        if (controller.text.isNotEmpty) {
                          setState(() {
                            loading = true;
                            errorText = null;
                            statusText = null;
                          });

                          try {
                            final didSave =
                                await widget.onCreate?.call(
                                  controller.text,
                                  usage,
                                  imageData,
                                ) ??
                                true;
                            if (didSave && context.mounted) {
                              Navigator.of(context).pop();
                            } else if (mounted) {
                              setState(() {
                                statusText = 'Save was not completed.';
                              });
                            }
                          } catch (_) {
                            if (mounted) {
                              setState(() {
                                errorText = 'This pack could not be saved.';
                              });
                            }
                          } finally {
                            if (mounted) {
                              setState(() {
                                loading = false;
                              });
                            }
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (!widget.creatingNew)
                    tiamat.Button.danger(
                      text: CommonStrings.promptDelete,
                      onTap: () async {
                        final confirm = await AdaptiveDialog.confirmation(
                          context,
                        );

                        if (confirm == true) {
                          setState(() {
                            loading = true;
                            errorText = null;
                            statusText = null;
                          });

                          try {
                            await widget.onDelete?.call();
                            if (context.mounted) Navigator.of(context).pop();
                          } catch (_) {
                            if (mounted) {
                              setState(() {
                                errorText = 'This pack could not be deleted.';
                              });
                            }
                          } finally {
                            if (mounted) {
                              setState(() {
                                loading = false;
                              });
                            }
                          }
                        }
                      },
                    ),
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    _StatusText(text: errorText!, isError: true),
                  ],
                  if (statusText != null) ...[
                    const SizedBox(height: 10),
                    _StatusText(text: statusText!, isError: false),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (loading) const Center(child: CircularProgressIndicator()),
      ],
    );
  }

  Widget _buildCutoutEditor(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final validation = _validateShortcode();
    final canSave =
        !loading &&
        !processingCutout &&
        !brushRendering &&
        validation.isValid &&
        // An unedited source photo is enough to save; a cutout is optional.
        (imageData != null || sourceImageData != null || !widget.creatingNew);
    final keyboardOpen = mediaQuery.viewInsets.bottom > 0;
    final availableHeight =
        mediaQuery.size.height - mediaQuery.viewInsets.bottom - 148;
    final editorMaxHeight = math.min(720.0, math.max(340.0, availableHeight));

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 900, maxHeight: editorMaxHeight),
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedOpacity(
            opacity: loading ? 0.55 : 1,
            duration: Durations.short2,
            child: IgnorePointer(
              ignoring: loading,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final editorHeight = constraints.maxHeight.isFinite
                      ? constraints.maxHeight
                      : editorMaxHeight;
                  final isWide = constraints.maxWidth >= 640;

                  return SizedBox(
                    height: editorHeight,
                    child: isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                width: math.min(
                                  340.0,
                                  constraints.maxWidth * 0.45,
                                ),
                                child: SingleChildScrollView(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    12,
                                    12,
                                    12,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _buildCutoutPreview(maxSide: 320),
                                      const SizedBox(height: 12),
                                      _buildPreviewMetadata(),
                                    ],
                                  ),
                                ),
                              ),
                              Container(
                                width: 1,
                                color: theme.colorScheme.outline.withValues(
                                  alpha: 0.18,
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: _buildCutoutControlList(
                                        validation,
                                        includeMetadata: false,
                                      ),
                                    ),
                                    _buildEditorActionBar(canSave),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // While the keyboard is up the large preview is
                              // dropped so the scrollable controls (name field
                              // first) stay visible above the keyboard and the
                              // action bar instead of being squeezed off-screen.
                              if (!keyboardOpen) ...[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    12,
                                    12,
                                    8,
                                  ),
                                  child: _buildCutoutPreview(
                                    maxSide: math.min(
                                      220.0,
                                      math.max(150.0, editorHeight * 0.42),
                                    ),
                                  ),
                                ),
                                Container(
                                  height: 1,
                                  color: theme.colorScheme.outline.withValues(
                                    alpha: 0.18,
                                  ),
                                ),
                              ],
                              Expanded(
                                child: _buildCutoutControlList(
                                  validation,
                                  includeMetadata: true,
                                ),
                              ),
                              _buildEditorActionBar(canSave),
                            ],
                          ),
                  );
                },
              ),
            ),
          ),
          if (loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  Widget _buildCutoutControlList(
    EmoticonShortcodeValidationResult validation, {
    required bool includeMetadata,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      children: [
        _buildNameAndUsage(validation),
        if (includeMetadata) ...[
          const SizedBox(height: 12),
          _buildPreviewMetadata(),
        ],
        _buildControlSection(title: 'Source', child: _buildCutoutActions()),
        _buildControlSection(
          title: 'Auto cutout',
          child: _buildAutoMaskControls(),
        ),
        _buildControlSection(title: 'Brush', child: _buildManualControls()),
        _buildControlSection(title: 'Output', child: _buildOutputControls()),
        _buildDraftsPanel(),
        _buildStatusMessages(),
      ],
    );
  }

  Widget _buildControlSection({required String title, required Widget child}) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          child,
          const SizedBox(height: 14),
          Divider(
            height: 1,
            color: theme.colorScheme.outline.withValues(alpha: 0.18),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewMetadata() {
    return _PreviewMetadata(
      result: cutoutResult,
      draft: savedDraft,
      pngBytes: imageData,
      diagnostic: lastCutoutDiagnostic,
    );
  }

  Widget _buildStatusMessages() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (errorText != null) ...[
          const SizedBox(height: 10),
          _StatusText(text: errorText!, isError: true),
        ],
        if (statusText != null) ...[
          const SizedBox(height: 10),
          _StatusText(text: statusText!, isError: false),
        ],
      ],
    );
  }

  Widget _buildEditorActionBar(bool canSave) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.22),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final saveButton = SizedBox(
              height: 44,
              child: tiamat.Button(
                text: promptConfirmSaveEmoticon,
                isLoading: loading,
                onTap: canSave ? _saveEmoticon : null,
              ),
            );
            final deleteButton = !widget.creatingNew
                ? SizedBox(
                    height: 44,
                    child: tiamat.Button.danger(
                      text: CommonStrings.promptDelete,
                      onTap: loading ? null : _deleteEmoticon,
                    ),
                  )
                : null;

            if (constraints.maxWidth < 420) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  saveButton,
                  if (deleteButton != null) ...[
                    const SizedBox(height: 8),
                    deleteButton,
                  ],
                ],
              );
            }

            return Row(
              children: [
                if (deleteButton != null) ...[
                  SizedBox(width: 132, child: deleteButton),
                  const Spacer(),
                ] else
                  const Spacer(),
                SizedBox(width: 180, child: saveButton),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildNameAndUsage(EmoticonShortcodeValidationResult validation) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final imageTile = SizedBox(
          width: 56,
          height: 56,
          child: _ImagePickTile(
            image: image,
            tooltip: sourceImageData == null
                ? promptSelectPhoto
                : promptChangePhoto,
            onTap: _pickSourceImage,
          ),
        );
        final nameField = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            tiamat.TextInput(
              maxLines: 1,
              placeholder: promptEmoteName,
              controller: controller,
              onChanged: (_) => setState(() {}),
            ),
            if (!validation.isValid && controller.text.isNotEmpty) ...[
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
        final nameRow = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            imageTile,
            const SizedBox(width: 8),
            Expanded(child: nameField),
          ],
        );

        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              nameRow,
              const SizedBox(height: 8),
              SizedBox(height: 42, child: _buildUsageDropdown()),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            imageTile,
            const SizedBox(width: 8),
            Expanded(child: nameField),
            const SizedBox(width: 8),
            SizedBox(width: 176, height: 42, child: _buildUsageDropdown()),
          ],
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
      value: usage,
      onItemSelected: (item) {
        setState(() {
          usage = item!;
        });
      },
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

  Widget _buildCutoutPreview({double maxSide = 360}) {
    final theme = Theme.of(context);
    final previewBytes = cutoutResult?.pngBytes ?? imageData ?? sourceImageData;
    final previewLabel =
        'Transparent cutout preview on ${previewBackground.semanticLabel} background. Drag on the image to refine the mask.';
    final canEditMask = cutoutResult != null && !loading && !processingCutout;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : maxSide;
        final side = math.min(maxSide, availableWidth);

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: side,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  label: previewLabel,
                  liveRegion: processingCutout,
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: LayoutBuilder(
                      builder: (context, previewConstraints) {
                        final size = Size(
                          previewConstraints.maxWidth,
                          previewConstraints.maxHeight,
                        );
                        final imageRect = cutoutResult == null
                            ? Rect.fromLTWH(0, 0, size.width, size.height)
                            : _containedImageRect(
                                containerSize: size,
                                imageWidth: cutoutResult!.width,
                                imageHeight: cutoutResult!.height,
                              );
                        final brushPosition = canEditMask
                            ? brushPreviewPosition
                            : null;
                        final brushRadiusPixels = math.max(
                          6.0,
                          imageRect.shortestSide * brushRadius,
                        );

                        return MouseRegion(
                          cursor: canEditMask
                              ? SystemMouseCursors.precise
                              : MouseCursor.defer,
                          onHover: !canEditMask
                              ? null
                              : (event) => _setBrushPreviewPosition(
                                  event.localPosition,
                                  imageRect,
                                ),
                          onExit: (_) => _clearBrushPreviewPosition(),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: !canEditMask
                                ? null
                                : (details) {
                                    _setBrushPreviewPosition(
                                      details.localPosition,
                                      imageRect,
                                    );
                                    _applyBrush(
                                      details.localPosition,
                                      imageRect,
                                    );
                                  },
                            onTapUp: !canEditMask
                                ? null
                                : (_) => _clearBrushPreviewPosition(),
                            onTapCancel: !canEditMask
                                ? null
                                : _clearBrushPreviewPosition,
                            onPanStart: !canEditMask
                                ? null
                                : (details) => _setBrushPreviewPosition(
                                    details.localPosition,
                                    imageRect,
                                  ),
                            onPanUpdate: !canEditMask
                                ? null
                                : (details) {
                                    _setBrushPreviewPosition(
                                      details.localPosition,
                                      imageRect,
                                    );
                                    _applyBrush(
                                      details.localPosition,
                                      imageRect,
                                    );
                                  },
                            onPanEnd: (_) => _clearBrushPreviewPosition(),
                            onPanCancel: _clearBrushPreviewPosition,
                            child: _PreviewBackgroundSurface(
                              mode: previewBackground,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: theme.colorScheme.outline.withValues(
                                      alpha: 0.48,
                                    ),
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      previewBytes == null
                                          ? Icon(
                                              Icons
                                                  .add_photo_alternate_outlined,
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                              size: 54,
                                            )
                                          : Image.memory(
                                              previewBytes,
                                              fit: BoxFit.contain,
                                              filterQuality:
                                                  FilterQuality.medium,
                                            ),
                                      if (brushPosition != null)
                                        IgnorePointer(
                                          child: CustomPaint(
                                            painter: _BrushCursorPainter(
                                              center: brushPosition,
                                              radius: brushRadiusPixels,
                                              color: theme.colorScheme.primary,
                                              outlineColor:
                                                  theme.colorScheme.onSurface,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _buildPreviewBackgroundPicker(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _MiniPreview(
                      bytes: previewBytes,
                      size: 32,
                      background: previewBackground,
                    ),
                    const SizedBox(width: 8),
                    _MiniPreview(
                      bytes: previewBytes,
                      size: 72,
                      background: previewBackground,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPreviewBackgroundPicker() {
    return Semantics(
      label: 'Preview background mode',
      value: previewBackground.label,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: _CutoutPreviewBackground.values
            .map((mode) {
              return FilterChip(
                label: Text(mode.label),
                avatar: Icon(mode.icon, size: 16),
                selected: previewBackground == mode,
                onSelected: loading
                    ? null
                    : (_) => setState(() => previewBackground = mode),
              );
            })
            .toList(growable: false),
      ),
    );
  }

  Widget _buildCutoutActions() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        SizedBox(
          width: 150,
          child: tiamat.Button.secondary(
            text: sourceImageData == null
                ? promptSelectPhoto
                : promptChangePhoto,
            onTap: loading ? null : _pickSourceImage,
          ),
        ),
        SizedBox(
          width: 110,
          child: tiamat.Button.secondary(
            text: promptCropPhoto,
            onTap: sourceImageData == null || loading || processingCutout
                ? null
                : _cropSourceImage,
          ),
        ),
        SizedBox(
          width: 110,
          child: tiamat.Button(
            text: processingCutout ? 'Processing...' : promptAutoCutout,
            isLoading: processingCutout,
            onTap: sourceImageData == null || loading || processingCutout
                ? null
                : _runAutoCutout,
          ),
        ),
        SizedBox(
          width: 110,
          child: tiamat.Button.secondary(
            text: promptResetCutout,
            onTap: sourceImageData == null || loading || processingCutout
                ? null
                : _resetCutout,
          ),
        ),
      ],
    );
  }

  Widget _buildManualControls() {
    final enabled = cutoutResult != null && !loading && !processingCutout;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              label: Text(promptEraseBrush),
              selected: brushMode == CutoutBrushMode.erase,
              onSelected: enabled
                  ? (_) => setState(() => brushMode = CutoutBrushMode.erase)
                  : null,
              avatar: const Icon(Icons.cleaning_services_outlined, size: 18),
            ),
            FilterChip(
              label: Text(promptRestoreBrush),
              selected: brushMode == CutoutBrushMode.restore,
              onSelected: enabled
                  ? (_) => setState(() => brushMode = CutoutBrushMode.restore)
                  : null,
              avatar: const Icon(Icons.brush_outlined, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _SliderRow(
          label: 'Brush size',
          value: brushRadius,
          min: 0.02,
          max: 0.12,
          divisions: 10,
          enabled: enabled,
          onChanged: (value) => setState(() => brushRadius = value),
        ),
        _SliderRow(
          label: 'Brush opacity',
          value: brushStrength,
          min: 0.1,
          max: 1.0,
          divisions: 9,
          valueText: '${(brushStrength * 100).round()}%',
          enabled: enabled,
          onChanged: (value) => setState(() => brushStrength = value),
        ),
      ],
    );
  }

  Widget _buildAutoMaskControls() {
    final enabled = sourceImageData != null && !loading && !processingCutout;
    final edgeExpansion = cutoutSettings.edgeExpansion;
    final edgeExpansionLabel = edgeExpansion == 0
        ? '0'
        : edgeExpansion > 0
        ? '+$edgeExpansion'
        : '$edgeExpansion';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SliderRow(
          label: 'Sensitivity',
          value: cutoutSettings.backgroundTolerance.toDouble(),
          min: 20,
          max: 96,
          divisions: 19,
          valueText: '${cutoutSettings.backgroundTolerance}',
          enabled: enabled,
          onChanged: (value) => setState(
            () => cutoutSettings = cutoutSettings.copyWith(
              backgroundTolerance: value.round(),
            ),
          ),
          onChangeEnd: (_) => _rerunAutoCutoutAfterMaskChange(),
        ),
        _SliderRow(
          label: 'Softness',
          value: cutoutSettings.edgeSoftness.toDouble(),
          min: 0,
          max: 4,
          divisions: 4,
          valueText: '${cutoutSettings.edgeSoftness}',
          enabled: enabled,
          onChanged: (value) => setState(
            () => cutoutSettings = cutoutSettings.copyWith(
              edgeSoftness: value.round(),
            ),
          ),
          onChangeEnd: (_) => _rerunAutoCutoutAfterMaskChange(),
        ),
        _SliderRow(
          label: 'Edge offset',
          value: edgeExpansion.toDouble(),
          min: -4,
          max: 4,
          divisions: 8,
          valueText: edgeExpansionLabel,
          enabled: enabled,
          onChanged: (value) => setState(
            () => cutoutSettings = cutoutSettings.copyWith(
              edgeExpansion: value.round(),
            ),
          ),
          onChangeEnd: (_) => _rerunAutoCutoutAfterMaskChange(),
        ),
      ],
    );
  }

  void _setSquareCanvas(bool squareCanvas) {
    if (cutoutSettings.squareCanvas == squareCanvas) {
      return;
    }
    setState(() {
      cutoutSettings = cutoutSettings.copyWith(squareCanvas: squareCanvas);
    });
    _rerenderCutout();
  }

  Widget _buildOutputControls() {
    final canUpdateOutput =
        cutoutResult != null && !loading && !processingCutout;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'Crop framing',
          value: cutoutSettings.squareCanvas ? 'Square crop' : 'Tight crop',
          enabled: canUpdateOutput,
          child: _ChoiceRow(
            label: 'Crop',
            children: [
              FilterChip(
                label: const Text('Square crop'),
                avatar: const Icon(Icons.crop_square_rounded, size: 18),
                selected: cutoutSettings.squareCanvas,
                onSelected: canUpdateOutput
                    ? (_) => _setSquareCanvas(true)
                    : null,
              ),
              FilterChip(
                label: const Text('Tight crop'),
                avatar: const Icon(Icons.crop_free_rounded, size: 18),
                selected: !cutoutSettings.squareCanvas,
                onSelected: canUpdateOutput
                    ? (_) => _setSquareCanvas(false)
                    : null,
              ),
            ],
          ),
        ),
        _SliderRow(
          label: 'Padding',
          value: cutoutSettings.paddingFraction,
          min: 0,
          max: 0.32,
          divisions: 16,
          enabled: canUpdateOutput,
          onChanged: (value) => setState(
            () => cutoutSettings = cutoutSettings.copyWith(
              paddingFraction: value,
            ),
          ),
          onChangeEnd: (_) => _rerenderCutout(),
        ),
        _SliderRow(
          label: 'Outline',
          value: cutoutSettings.outlineWidth.toDouble(),
          min: 0,
          max: 10,
          divisions: 10,
          enabled: canUpdateOutput,
          onChanged: (value) => setState(
            () => cutoutSettings = cutoutSettings.copyWith(
              outlineWidth: value.round(),
            ),
          ),
          onChangeEnd: (_) => _rerenderCutout(),
        ),
        SwitchListTile.adaptive(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Shadow'),
          value: cutoutSettings.shadow,
          onChanged: !canUpdateOutput
              ? null
              : (value) {
                  setState(() {
                    cutoutSettings = cutoutSettings.copyWith(shadow: value);
                  });
                  _rerenderCutout();
                },
        ),
      ],
    );
  }

  Widget _buildDraftsPanel() {
    final theme = Theme.of(context);
    final filteredDrafts = _filteredDrafts();
    final visibleDrafts = filteredDrafts
        .take(_draftPanelDisplayLimit)
        .toList(growable: false);
    final hiddenMatchCount = math.max(
      0,
      filteredDrafts.length - visibleDrafts.length,
    );
    final hasSearch = draftSearchQuery.trim().isNotEmpty;

    if (!draftsLoading && drafts.isEmpty && draftErrorText == null) {
      return const SizedBox.shrink();
    }

    return Semantics(
      label: 'Local emoticon drafts',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.28),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.history_rounded, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Recent drafts',
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  if (draftsLoading)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    IconButton(
                      tooltip: 'Refresh drafts',
                      onPressed: loading ? null : _loadDrafts,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                    ),
                ],
              ),
              if (drafts.isNotEmpty) ...[
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('emoticon-draft-search'),
                  controller: draftSearchController,
                  enabled: !loading && !draftsLoading,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    suffixIcon: hasSearch
                        ? IconButton(
                            tooltip: 'Clear draft search',
                            onPressed: loading ? null : _clearDraftSearch,
                            icon: const Icon(Icons.close_rounded, size: 18),
                          )
                        : null,
                    labelText: 'Search local drafts',
                    hintText: 'Shortcode, size, or backend',
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setState(() {
                      draftSearchQuery = value;
                    });
                  },
                ),
              ],
              if (draftErrorText != null) ...[
                const SizedBox(height: 6),
                _StatusText(text: draftErrorText!, isError: true),
              ],
              if (drafts.isNotEmpty && filteredDrafts.isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const ValueKey('emoticon-draft-bulk-delete'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    onPressed: loading || draftsLoading
                        ? null
                        : () => _deleteDrafts(filteredDrafts),
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: Text(hasSearch ? 'Delete matching' : 'Delete all'),
                  ),
                ),
              ],
              if (visibleDrafts.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...visibleDrafts.map(
                  (draft) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _DraftTile(
                      draft: draft,
                      thumbnailBytes: draftThumbnails[draft.id],
                      selected: savedDraft?.id == draft.id,
                      onLoad: loading ? null : () => _loadDraft(draft),
                      onDelete: loading ? null : () => _deleteDraft(draft),
                    ),
                  ),
                ),
                if (hiddenMatchCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      hasSearch
                          ? '$hiddenMatchCount more local drafts match this search.'
                          : '$hiddenMatchCount more local drafts saved. Search to narrow them down.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ] else if (!draftsLoading && hasSearch) ...[
                const SizedBox(height: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No local drafts found.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: loading ? null : _clearDraftSearch,
                          child: const Text('Clear search'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<EmoticonDraft> _filteredDrafts() {
    final query = draftSearchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return drafts;
    }
    return drafts
        .where((draft) => _draftMatchesSearch(draft, query))
        .toList(growable: false);
  }

  bool _draftMatchesSearch(EmoticonDraft draft, String query) {
    final searchText = [
      draft.shortcode,
      draft.backend.name,
      '${draft.width}x${draft.height}',
      '${draft.width} x ${draft.height}',
      _formatByteSize(draft.fileSize),
    ].join(' ').toLowerCase();
    return searchText.contains(query);
  }

  void _clearDraftSearch() {
    draftSearchController.clear();
    setState(() {
      draftSearchQuery = '';
    });
  }

  Future<void> _loadDrafts() async {
    if (widget.createPack) {
      return;
    }

    setState(() {
      draftsLoading = true;
      draftErrorText = null;
    });

    try {
      final loadedDrafts = await draftStore.listDrafts();
      final thumbnails = <String, Uint8List>{};
      for (final draft in loadedDrafts.take(_draftThumbnailReadLimit)) {
        final thumbnail = await draftStore.readDraftThumbnail(draft.id);
        if (thumbnail != null) {
          thumbnails[draft.id] = thumbnail;
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        drafts = loadedDrafts;
        draftThumbnails = thumbnails;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        draftErrorText = 'Local drafts could not be loaded.';
      });
    } finally {
      if (mounted) {
        setState(() {
          draftsLoading = false;
        });
      }
    }
  }

  Future<void> _loadDraft(EmoticonDraft draft) async {
    setState(() {
      loading = true;
      errorText = null;
      statusText = 'Loading local draft...';
    });

    try {
      final loaded = await draftStore.loadDraft(draft.id);
      if (!mounted) {
        return;
      }
      if (loaded == null) {
        setState(() {
          errorText = 'This local draft is no longer available.';
        });
        await _loadDrafts();
        return;
      }

      setState(() {
        controller.text = loaded.draft.shortcode;
        sourceImageData = null;
        sourceImageName = null;
        cutoutResult = null;
        autoCutoutMask = null;
        workingMask = null;
        imageData = loaded.pngBytes;
        image = Image.memory(loaded.pngBytes).image;
        savedDraft = loaded.draft;
        statusText = 'Loaded local draft. Save to add it to this pack.';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        errorText = 'This local draft could not be loaded.';
      });
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  Future<void> _deleteDraft(EmoticonDraft draft) async {
    final confirmed = await AdaptiveDialog.confirmation(
      context,
      title: 'Delete local draft?',
      prompt:
          'This removes the saved PNG draft from this device only. It does not remove Matrix image packs or already uploaded images.',
      confirmationText: CommonStrings.promptDelete,
      cancelText: CommonStrings.promptCancel,
      dangerous: true,
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      loading = true;
      errorText = null;
      statusText = 'Deleting local draft...';
    });

    try {
      await draftStore.deleteDraft(draft.id);
      if (!mounted) {
        return;
      }
      setState(() {
        if (savedDraft?.id == draft.id) {
          savedDraft = null;
          statusText =
              'Local draft deleted. The current preview remains until changed.';
        } else {
          statusText = 'Local draft deleted.';
        }
      });
      await _loadDrafts();
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        errorText = 'This local draft could not be deleted.';
      });
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  Future<void> _deleteDrafts(List<EmoticonDraft> targetDrafts) async {
    if (targetDrafts.isEmpty) {
      return;
    }

    final draftCount = targetDrafts.length;
    final draftLabel = draftCount == 1 ? 'draft' : 'drafts';
    final pngDraftLabel = draftCount == 1 ? 'PNG draft' : 'PNG drafts';
    final hasSearch = draftSearchQuery.trim().isNotEmpty;
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
    if (confirmed != true) {
      return;
    }

    final targetIds = targetDrafts.map((draft) => draft.id).toSet();
    setState(() {
      loading = true;
      errorText = null;
      statusText = 'Deleting local drafts...';
    });

    try {
      for (final draftId in targetIds) {
        await draftStore.deleteDraft(draftId);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        if (targetIds.contains(savedDraft?.id)) {
          savedDraft = null;
          statusText =
              'Local drafts deleted. The current preview remains until changed.';
        } else {
          statusText = 'Local drafts deleted.';
        }
      });
      await _loadDrafts();
    } catch (_) {
      if (!mounted) {
        return;
      }
      await _loadDrafts();
      if (!mounted) {
        return;
      }
      setState(() {
        errorText = 'These local drafts could not be deleted.';
      });
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  Future<void> _pickPackImage() async {
    try {
      final result = await PickerUtils.pickImageAndCrop(
        context,
        aspectRatio: 1,
      );
      if (result == null || !mounted) {
        return;
      }
      setState(() {
        imageData = result;
        image = Image.memory(result).image;
        errorText = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        errorText = 'This image could not be loaded.';
        statusText = null;
      });
    }
  }

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

      setState(() {
        _setSourceImage(
          bytes,
          name: picked.name,
          seedShortcode: controller.text.isEmpty && !widget.createPack,
        );
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        errorText = 'This photo could not be loaded.';
        statusText = null;
      });
    }
  }

  Future<void> _cropSourceImage() async {
    final source = sourceImageData;
    if (source == null) {
      return;
    }
    try {
      final cropped = await PickerUtils.cropImageData(context, source);
      if (cropped == null || !mounted) {
        return;
      }
      setState(() {
        // Re-seat the cropped image as the new source; this clears any cutout
        // so the user can re-run auto/brush on the crop, or save it unedited.
        _setSourceImage(cropped, name: sourceImageName);
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        errorText = 'This image could not be cropped.';
        statusText = null;
      });
    }
  }

  void _setSourceImage(
    Uint8List bytes, {
    String? name,
    bool seedShortcode = false,
  }) {
    sourceImageData = bytes;
    sourceImageName = name;
    cutoutResult = null;
    autoCutoutMask = null;
    workingMask = null;
    brushPreviewPosition = null;
    lastCutoutDiagnostic = null;
    imageData = null;
    savedDraft = null;
    image = Image.memory(bytes).image;
    errorText = null;
    statusText = null;
    if (seedShortcode) {
      final shortcode = _shortcodeSeedFromImageName(name);
      if (shortcode.isNotEmpty) {
        controller.text = shortcode;
      }
    }
  }

  String _shortcodeSeedFromImageName(String? name) {
    final rawName = name?.trim();
    if (rawName == null || rawName.isEmpty) {
      return '';
    }

    final slashIndex = math.max(
      rawName.lastIndexOf('/'),
      rawName.lastIndexOf(r'\'),
    );
    final filename = slashIndex == -1
        ? rawName
        : rawName.substring(slashIndex + 1);
    final dotIndex = filename.lastIndexOf('.');
    final base = (dotIndex > 0 ? filename.substring(0, dotIndex) : filename)
        .toLowerCase();

    return base
        .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  Future<void> _runAutoCutout({bool preserveManualMask = false}) async {
    final source = sourceImageData;
    if (source == null) {
      return;
    }
    final preservedWorkingMask =
        preserveManualMask && _hasManualCutoutMask(workingMask, autoCutoutMask)
        ? workingMask
        : null;

    setState(() {
      loading = true;
      processingCutout = true;
      errorText = null;
      lastCutoutDiagnostic = null;
      statusText = 'Preparing local background removal...';
    });

    try {
      final result = await cutoutService.generate(
        imageBytes: source,
        settings: cutoutSettings,
      );
      final canPreserveWorkingMask =
          preservedWorkingMask != null &&
          preservedWorkingMask.width == result.mask.width &&
          preservedWorkingMask.height == result.mask.height;
      final displayResult = canPreserveWorkingMask
          ? await cutoutService.render(
              imageBytes: source,
              mask: preservedWorkingMask,
              settings: cutoutSettings,
            )
          : result;
      if (!mounted) {
        return;
      }
      setState(() {
        cutoutResult = displayResult;
        autoCutoutMask = result.mask;
        workingMask = canPreserveWorkingMask
            ? preservedWorkingMask
            : result.mask;
        imageData = displayResult.pngBytes;
        image = Image.memory(displayResult.pngBytes).image;
        statusText = 'Transparent PNG ready. Backend: ${result.backend.name}.';
      });
    } on ImageCutoutException catch (exception) {
      if (!mounted) {
        return;
      }
      setState(() {
        errorText = exception.message;
        statusText = null;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        errorText = 'This photo could not be processed.';
        statusText = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
          processingCutout = false;
        });
      }
    }
  }

  Future<void> _rerunAutoCutoutAfterMaskChange() async {
    if (sourceImageData == null ||
        cutoutResult == null ||
        loading ||
        processingCutout) {
      return;
    }
    await _runAutoCutout(preserveManualMask: true);
  }

  Future<void> _rerenderCutout({
    CutoutMask? mask,
    String? successStatusText,
  }) async {
    final source = sourceImageData;
    final current = cutoutResult;
    final nextMask = mask ?? workingMask ?? current?.mask;
    if (source == null ||
        current == null ||
        nextMask == null ||
        processingCutout) {
      return;
    }

    setState(() {
      processingCutout = true;
      lastCutoutDiagnostic = null;
      statusText = 'Updating transparent PNG...';
    });

    try {
      final result = await cutoutService.render(
        imageBytes: source,
        mask: nextMask,
        settings: cutoutSettings,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        cutoutResult = result;
        workingMask = result.mask;
        imageData = result.pngBytes;
        image = Image.memory(result.pngBytes).image;
        statusText = successStatusText ?? 'Transparent PNG updated.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          errorText = 'This edit could not be applied.';
          statusText = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          processingCutout = false;
        });
      }
    }
  }

  void _setBrushPreviewPosition(Offset position, Rect imageRect) {
    final nextPosition = imageRect.contains(position) ? position : null;
    if (brushPreviewPosition == nextPosition || !mounted) {
      return;
    }

    setState(() {
      brushPreviewPosition = nextPosition;
    });
  }

  void _clearBrushPreviewPosition() {
    if (brushPreviewPosition == null || !mounted) {
      return;
    }

    setState(() {
      brushPreviewPosition = null;
    });
  }

  void _applyBrush(Offset position, Rect imageRect) {
    final result = cutoutResult;
    final source = sourceImageData;
    if (result == null ||
        source == null ||
        imageRect.isEmpty ||
        !imageRect.contains(position)) {
      return;
    }

    final x = ((position.dx - imageRect.left) / imageRect.width).clamp(
      0.0,
      1.0,
    );
    final y = ((position.dy - imageRect.top) / imageRect.height).clamp(
      0.0,
      1.0,
    );
    final crop = result.cropBounds;
    final sourceX = crop.left + (crop.width * x);
    final sourceY = crop.top + (crop.height * y);
    final normalizedSourceX = (sourceX / math.max(1, result.sourceWidth - 1))
        .clamp(0.0, 1.0);
    final normalizedSourceY = (sourceY / math.max(1, result.sourceHeight - 1))
        .clamp(0.0, 1.0);
    final nextMask = (workingMask ?? result.mask).applyBrush(
      normalizedX: normalizedSourceX,
      normalizedY: normalizedSourceY,
      radiusFraction: brushRadius,
      mode: brushMode,
      strength: brushStrength,
    );

    workingMask = nextMask;
    _scheduleBrushRender();
  }

  /// Renders the current brush mask live during a stroke. Unlike the slider
  /// re-render this does not set [processingCutout] (which would disable the
  /// brush mid-stroke) and does not overwrite [workingMask] from the rendered
  /// result, so dabs added while a render is in flight are preserved. Renders
  /// are throttled to one in flight with a single trailing render queued, so
  /// the preview keeps up with the stroke instead of only updating on pause.
  void _scheduleBrushRender() {
    if (brushRendering) {
      brushRenderQueued = true;
      return;
    }
    unawaited(_runBrushRender());
  }

  Future<void> _runBrushRender() async {
    final source = sourceImageData;
    final mask = workingMask;
    if (source == null || mask == null || cutoutResult == null) {
      return;
    }

    brushRendering = true;
    try {
      final result = await cutoutService.render(
        imageBytes: source,
        mask: mask,
        settings: cutoutSettings,
      );
      // Drop the render if the image was reset or replaced while it ran.
      if (!mounted ||
          !identical(sourceImageData, source) ||
          cutoutResult == null) {
        return;
      }
      setState(() {
        cutoutResult = result;
        imageData = result.pngBytes;
        image = Image.memory(result.pngBytes).image;
        errorText = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          errorText = 'This edit could not be applied.';
        });
      }
    } finally {
      brushRendering = false;
      if (brushRenderQueued && mounted && identical(sourceImageData, source)) {
        brushRenderQueued = false;
        unawaited(_runBrushRender());
      } else {
        brushRenderQueued = false;
      }
    }
  }

  Future<void> _resetCutout() async {
    brushRenderQueued = false;
    final autoMask = autoCutoutMask;
    if (sourceImageData != null && cutoutResult != null && autoMask != null) {
      setState(() {
        workingMask = autoMask;
        errorText = null;
      });
      await _rerenderCutout(
        mask: autoMask,
        successStatusText: 'Auto mask restored.',
      );
      return;
    }

    setState(() {
      cutoutResult = null;
      autoCutoutMask = null;
      workingMask = null;
      lastCutoutDiagnostic = null;
      imageData = null;
      image = sourceImageData == null
          ? image
          : Image.memory(sourceImageData!).image;
      statusText = null;
      errorText = null;
    });
  }

  EmoticonShortcodeValidationResult _validateShortcode() {
    if (widget.createPack) {
      return EmoticonShortcodeValidationResult(
        code: controller.text.trim().isEmpty
            ? EmoticonShortcodeValidationCode.empty
            : EmoticonShortcodeValidationCode.valid,
        normalized: controller.text.trim(),
      );
    }

    return validateEmoticonShortcode(
      controller.text,
      existingShortcodes: widget.pack?.getShortcodes() ?? const [],
      previousShortcode: widget.initialEmoticon?.shortcode,
    );
  }

  Future<void> _saveEmoticon() async {
    final validation = _validateShortcode();
    if (!validation.isValid) {
      setState(() => errorText = validation.message);
      return;
    }

    setState(() {
      loading = true;
      errorText = null;
      statusText = 'Saving local draft...';
    });

    try {
      final result = cutoutResult;
      // Fall back to the raw source photo when the user chose not to run a
      // cutout, so unedited images can still be submitted.
      final bytes = imageData ?? sourceImageData;
      if (!widget.createPack && result != null && imageData != null) {
        savedDraft = await draftStore.saveDraft(
          shortcode: validation.normalized,
          pngBytes: imageData!,
          thumbnailBytes: result.thumbnailBytes,
          backend: result.backend,
          width: result.width,
          height: result.height,
          sourceImageHash: sourceImageData == null
              ? null
              : sha256.convert(sourceImageData!).toString(),
          packId: widget.pack?.identifier,
        );
      }

      final didSave =
          await widget.onCreate?.call(validation.normalized, usage, bytes) ??
          true;

      if (didSave && context.mounted) {
        Navigator.of(context).pop();
      } else if (mounted) {
        setState(() {
          statusText = savedDraft == null
              ? 'Save was not completed.'
              : 'Local draft saved. Pack update was not completed.';
        });
        if (savedDraft != null) {
          await _loadDrafts();
        }
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        errorText = 'This emoticon could not be saved.';
        statusText = savedDraft == null
            ? null
            : 'Local draft saved. Pack update was not completed.';
      });
      if (savedDraft != null) {
        await _loadDrafts();
      }
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  Future<void> _deleteEmoticon() async {
    final confirm = await AdaptiveDialog.confirmation(context);

    if (confirm == true) {
      setState(() {
        loading = true;
        errorText = null;
      });

      try {
        await widget.onDelete?.call();
        if (context.mounted) Navigator.of(context).pop();
      } catch (_) {
        if (mounted) {
          setState(() {
            errorText = 'This emoticon could not be deleted.';
          });
        }
      } finally {
        if (mounted) {
          setState(() {
            loading = false;
          });
        }
      }
    }
  }
}

Rect _containedImageRect({
  required Size containerSize,
  required int imageWidth,
  required int imageHeight,
}) {
  if (containerSize.isEmpty || imageWidth <= 0 || imageHeight <= 0) {
    return Rect.zero;
  }

  final scale = math.min(
    containerSize.width / imageWidth,
    containerSize.height / imageHeight,
  );
  final fittedWidth = imageWidth * scale;
  final fittedHeight = imageHeight * scale;
  return Rect.fromLTWH(
    (containerSize.width - fittedWidth) / 2,
    (containerSize.height - fittedHeight) / 2,
    fittedWidth,
    fittedHeight,
  );
}

class _ImagePickTile extends StatelessWidget {
  const _ImagePickTile({
    required this.image,
    required this.tooltip,
    required this.onTap,
  });

  final ImageProvider? image;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: image == null
              ? Icon(
                  Icons.add_a_photo,
                  color: theme.colorScheme.onSurfaceVariant,
                )
              : Image(
                  image: image!,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                ),
        ),
      ),
    );
  }
}

class _CheckerboardPainter extends CustomPainter {
  const _CheckerboardPainter({required this.light, required this.dark});

  final Color light;
  final Color dark;

  @override
  void paint(Canvas canvas, Size size) {
    const tile = 12.0;
    final paint = Paint();
    for (var y = 0.0; y < size.height; y += tile) {
      for (var x = 0.0; x < size.width; x += tile) {
        final even = ((x / tile).floor() + (y / tile).floor()).isEven;
        paint.color = even ? light : dark;
        canvas.drawRect(Rect.fromLTWH(x, y, tile, tile), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerboardPainter oldDelegate) {
    return oldDelegate.light != light || oldDelegate.dark != dark;
  }
}

class _BrushCursorPainter extends CustomPainter {
  const _BrushCursorPainter({
    required this.center,
    required this.radius,
    required this.color,
    required this.outlineColor,
  });

  final Offset center;
  final double radius;
  final Color color;
  final Color outlineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final outerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = outlineColor.withValues(alpha: 0.72);
    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color.withValues(alpha: 0.95);

    canvas
      ..drawCircle(center, radius, outerPaint)
      ..drawCircle(center, radius, innerPaint);
  }

  @override
  bool shouldRepaint(covariant _BrushCursorPainter oldDelegate) {
    return oldDelegate.center != center ||
        oldDelegate.radius != radius ||
        oldDelegate.color != color ||
        oldDelegate.outlineColor != outlineColor;
  }
}

class _PreviewBackgroundSurface extends StatelessWidget {
  const _PreviewBackgroundSurface({required this.mode, required this.child});

  final _CutoutPreviewBackground mode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return switch (mode) {
      _CutoutPreviewBackground.checkerboard => CustomPaint(
        painter: _CheckerboardPainter(
          light: theme.colorScheme.surfaceContainerHigh,
          dark: theme.colorScheme.surfaceContainerLow,
        ),
        child: child,
      ),
      _CutoutPreviewBackground.dark => ColoredBox(
        // Fixed neutral mattes help users inspect transparent edges regardless
        // of whether the current app theme is light, dark, or custom.
        color: const Color(0xFF151515),
        child: child,
      ),
      _CutoutPreviewBackground.light => ColoredBox(
        color: const Color(0xFFF6F6F6),
        child: child,
      ),
    };
  }
}

class _MiniPreview extends StatelessWidget {
  const _MiniPreview({
    required this.bytes,
    required this.size,
    required this.background,
  });

  final Uint8List? bytes;
  final double size;
  final _CutoutPreviewBackground background;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: size <= 40
          ? 'Emoji-size preview on ${background.semanticLabel} background'
          : 'Sticker-size preview on ${background.semanticLabel} background',
      child: _PreviewBackgroundSurface(
        mode: background,
        child: SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.38),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: bytes == null
                ? Icon(
                    Icons.image_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: size * 0.42,
                  )
                : Image.memory(bytes!, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

class _PreviewMetadata extends StatelessWidget {
  const _PreviewMetadata({
    required this.result,
    required this.draft,
    required this.pngBytes,
    required this.diagnostic,
  });

  final CutoutResult? result;
  final EmoticonDraft? draft;
  final Uint8List? pngBytes;
  final ImageCutoutDiagnosticEvent? diagnostic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = this.result;
    final draft = this.draft;
    final pngBytes = this.pngBytes;
    final diagnostic = this.diagnostic;
    final lines = result != null
        ? [
            '${result.width} x ${result.height} PNG',
            _formatByteSize(result.pngBytes.length),
            'Backend: ${result.backend.name}',
            'Metadata stripped on export',
          ]
        : draft != null
        ? [
            '${draft.width} x ${draft.height} PNG',
            _formatByteSize(draft.fileSize),
            'Draft: ${draft.shortcode}',
            'Backend: ${draft.backend.name}',
            'Saved locally ${DateFormat.yMMMd().add_jm().format(draft.createdAt.toLocal())}',
            'Metadata stripped on export',
          ]
        : pngBytes != null
        ? [
            'Loaded transparent PNG',
            _formatByteSize(pngBytes.length),
            'Photos stay local until you save.',
          ]
        : const ['No cutout yet.', 'Photos stay local until you save.'];
    final diagnosticLines = diagnostic == null
        ? const <String>[]
        : _cutoutDiagnosticLines(diagnostic);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.42),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Output',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                line,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (diagnosticLines.isNotEmpty) ...[
            const SizedBox(height: 8),
            Divider(
              height: 1,
              color: theme.colorScheme.outline.withValues(alpha: 0.24),
            ),
            const SizedBox(height: 8),
            Semantics(
              label: 'Cutout diagnostics',
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Cutout details',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final line in diagnosticLines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        line,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static List<String> _cutoutDiagnosticLines(
    ImageCutoutDiagnosticEvent diagnostic,
  ) {
    return [
      'Operation: ${diagnostic.operation.name}',
      'Host: ${diagnostic.hostPlatform.name}',
      'Preferred: ${diagnostic.preferredBackend.name}',
      'Selected: ${diagnostic.selectedBackend.name}',
      'Runtime backend: ${diagnostic.backend.name}',
      'Fallback: ${diagnostic.usesFallback ? 'yes' : 'no'}',
      if (diagnostic.requiresNativeBridge) 'Native bridge required',
      if (diagnostic.requiresModelArtifact) 'Model artifact required',
      'Result: ${diagnostic.success ? 'success' : diagnostic.failureCode?.name ?? 'failed'}',
      'Duration: ${_formatDuration(diagnostic.duration)}',
      if (diagnostic.sourceWidth != null && diagnostic.sourceHeight != null)
        'Source: ${diagnostic.sourceWidth} x ${diagnostic.sourceHeight}',
      if (diagnostic.outputWidth != null && diagnostic.outputHeight != null)
        'Output: ${diagnostic.outputWidth} x ${diagnostic.outputHeight}',
      if (diagnostic.maskWidth != null && diagnostic.maskHeight != null)
        'Mask: ${diagnostic.maskWidth} x ${diagnostic.maskHeight}',
      if (diagnostic.outputPngByteCount != null)
        'PNG: ${_formatByteSize(diagnostic.outputPngByteCount!)}',
      if (diagnostic.thumbnailByteCount != null)
        'Thumbnail: ${_formatByteSize(diagnostic.thumbnailByteCount!)}',
    ];
  }
}

class _DraftTile extends StatelessWidget {
  const _DraftTile({
    required this.draft,
    required this.thumbnailBytes,
    required this.selected,
    required this.onLoad,
    required this.onDelete,
  });

  final EmoticonDraft draft;
  final Uint8List? thumbnailBytes;
  final bool selected;
  final VoidCallback? onLoad;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = [
      '${draft.width} x ${draft.height}',
      _formatByteSize(draft.fileSize),
      draft.backend.name,
    ].join(' | ');
    final created = DateFormat.MMMd().add_jm().format(
      draft.createdAt.toLocal(),
    );

    return Semantics(
      selected: selected,
      label: 'Local draft ${draft.shortcode}, $subtitle',
      child: Material(
        color: Colors.transparent,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.surfaceContainerHigh
                : theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline.withValues(alpha: 0.28),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                _DraftThumbnail(bytes: thumbnailBytes),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              draft.shortcode,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge,
                            ),
                          ),
                          if (selected) ...[
                            const SizedBox(width: 6),
                            Icon(
                              Icons.check_circle_rounded,
                              size: 14,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Loaded',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        created,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(onPressed: onLoad, child: const Text('Load')),
                Tooltip(
                  message: 'Delete local draft',
                  child: IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
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

class _DraftThumbnail extends StatelessWidget {
  const _DraftThumbnail({required this.bytes});

  final Uint8List? bytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CustomPaint(
        painter: _CheckerboardPainter(
          light: theme.colorScheme.surfaceContainerHigh,
          dark: theme.colorScheme.surfaceContainerLow,
        ),
        child: SizedBox(
          width: 44,
          height: 44,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.32),
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: bytes == null
                ? Icon(
                    Icons.image_outlined,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                : Image.memory(
                    bytes!,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
          ),
        ),
      ),
    );
  }
}

String _formatByteSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kib = bytes / 1024;
  if (kib < 1024) {
    return '${kib.toStringAsFixed(1)} KB';
  }
  return '${(kib / 1024).toStringAsFixed(1)} MB';
}

String _formatDuration(Duration duration) {
  final milliseconds = duration.inMilliseconds;
  if (milliseconds < 1000) {
    return '$milliseconds ms';
  }

  final seconds = milliseconds / Duration.millisecondsPerSecond;
  return '${seconds.toStringAsFixed(seconds < 10 ? 1 : 0)} s';
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelWidget = SizedBox(width: 92, child: Text(label));
        final choices = Wrap(spacing: 8, runSpacing: 8, children: children);

        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(label), const SizedBox(height: 8), choices],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            labelWidget,
            Expanded(child: choices),
          ],
        );
      },
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
    this.divisions,
    this.valueText,
    this.onChangeEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? valueText;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final semanticValue = valueText ?? value.toStringAsFixed(2);
    final theme = Theme.of(context);
    final labelWidget = Text(label);
    final slider = Slider(
      value: value.clamp(min, max),
      min: min,
      max: max,
      divisions: divisions,
      semanticFormatterCallback: (_) => '$label $semanticValue',
      onChanged: enabled ? onChanged : null,
      onChangeEnd: enabled ? onChangeEnd : null,
    );
    final valueWidget = valueText == null
        ? null
        : Text(
            valueText!,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: labelWidget),
                  if (valueWidget != null)
                    SizedBox(width: 44, child: valueWidget),
                ],
              ),
              slider,
            ],
          );
        }

        return Row(
          children: [
            SizedBox(width: 92, child: labelWidget),
            Expanded(child: slider),
            if (valueWidget != null) SizedBox(width: 40, child: valueWidget),
          ],
        );
      },
    );
  }
}

class _StatusText extends StatelessWidget {
  const _StatusText({required this.text, required this.isError});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: isError
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
