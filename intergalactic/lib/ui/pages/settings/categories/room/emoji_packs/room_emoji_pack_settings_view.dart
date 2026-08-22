import 'dart:async';
import 'dart:typed_data';

import 'package:intergalactic/client/components/emoticon/emoticon_draft_store.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_draft_store_models.dart';
import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_component.dart';
import 'package:intergalactic/client/components/emoticon/image_cutout_service.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/onboarding/tutorial_anchor.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/bulk_import_view.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/controls/emoticon_editor_controls.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/desktop/emoticon_quick_panel.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/emoticon_editor_controller.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/mobile/emoticon_creator_mobile.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:intergalactic/utils/download_utils.dart';
import 'package:intergalactic/utils/picker_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

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

class EmoticonPackEditor extends StatefulWidget {
  const EmoticonPackEditor({
    required this.pack,
    this.editable = false,
    super.key,
  });
  final EmoticonPack pack;
  final bool editable;

  @override
  State<EmoticonPackEditor> createState() => _EmoticonPackEditorState();
}

class _EmoticonPackEditorState extends State<EmoticonPackEditor> {
  bool _reordering = false;

  EmoticonPack get pack => widget.pack;

  bool get editable => widget.editable;

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

  Future<void> _moveEmoticon(int index, int delta) async {
    if (_reordering) return;
    // Copied, not aliased: `EmoticonPack.emotes` is only contractually a
    // `List<Emoticon>`, and `DemoEmoticonPack` returns `List.unmodifiable`,
    // so the `removeAt`/`insert` below would throw before `reorderEmoticons`
    // was ever reached.
    final emotes = List<Emoticon>.of(pack.emotes);
    final destination = index + delta;
    if (destination < 0 || destination >= emotes.length) return;
    setState(() => _reordering = true);
    try {
      final moved = emotes.removeAt(index);
      emotes.insert(destination, moved);
      await pack.reorderEmoticons(
        emotes.map((emoticon) => emoticon.shortcode!).toList(growable: false),
      );
    } finally {
      if (mounted) {
        setState(() => _reordering = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Column(
          children: pack.emotes.asMap().entries.map((entry) {
            final index = entry.key;
            final e = entry.value;
            return Padding(
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
                              if (editable)
                                IconButton(
                                  tooltip: 'Move ${e.shortcode} up',
                                  onPressed: _reordering || index == 0
                                      ? null
                                      : () => _moveEmoticon(index, -1),
                                  icon: const Icon(Icons.keyboard_arrow_up),
                                ),
                              if (editable)
                                IconButton(
                                  tooltip: 'Move ${e.shortcode} down',
                                  onPressed:
                                      _reordering ||
                                          index == pack.emotes.length - 1
                                      ? null
                                      : () => _moveEmoticon(index, 1),
                                  icon: const Icon(Icons.keyboard_arrow_down),
                                ),
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
            );
          }).toList(),
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

/// Entry point for creating/editing emoticon packs and emoticons.
///
/// The pack path (`createPack: true`) keeps its simple local form. The
/// emoticon (cutout) path runs on a shared [EmoticonEditorController] with
/// two presentation layers: the mobile Quick card + canvas-dominant Editor
/// ([EmoticonCreatorMobile]) and the desktop Quick panel + two-pane Editor
/// ([EmoticonCreatorDesktop]). The cutout engine, draft store, and shortcode
/// validation are shared through the controller — no per-platform engine
/// wiring.
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
    this.onSaveToPhotos,
    this.mobileLayout,
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
  final EmoticonSaveToPhotosCallback? onSaveToPhotos;

  /// Overrides the platform presentation branch. `null` follows
  /// [Layout.mobile].
  final bool? mobileLayout;

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
  // Pack-editor path state (createPack only).
  late EmoticonUsage usage;
  ImageProvider? image;
  Uint8List? imageData;
  TextEditingController controller = TextEditingController();
  bool loading = false;
  String? errorText;
  String? statusText;

  // Emoticon (cutout) path: the shared controller both presentation layers
  // bind to.
  EmoticonEditorController? editorController;

  String get promptEmoticonPackName => Intl.message(
    "Pack name",
    name: "promptEmoticonPackName",
    desc: "Prompt for the input of the name of an emoticon pack",
  );

  @override
  void initState() {
    super.initState();

    if (widget.createPack) {
      if (widget.pack != null) {
        usage = widget.pack!.usage;
        controller.text = widget.pack!.displayName;
        image = widget.pack!.image;
      } else {
        usage = EmoticonUsage.all;
      }
      return;
    }

    usage = widget.initialEmoticon?.usage ?? EmoticonUsage.inherit;
    final editor = EmoticonEditorController(
      cutoutService: widget.cutoutService ?? ImageCutoutService(),
      draftStore: widget.draftStore ?? createEmoticonDraftStore(),
      pack: widget.pack,
      initialEmoticon: widget.initialEmoticon,
      creatingNew: widget.creatingNew,
      onCreate: widget.onCreate,
      onDelete: widget.onDelete,
      onSaveToPhotos: widget.onSaveToPhotos ?? _platformSaveToPhotos,
    );
    editorController = editor;
    unawaited(editor.loadDrafts());

    final initialSource = widget.initialSourceImageData;
    if (initialSource != null) {
      editor.setSourceImage(
        initialSource,
        name: widget.initialSourceImageName,
        seedShortcode: editor.shortcodeController.text.isEmpty,
      );
      if (widget.autoRunInitialCutout) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(editor.runAutoCutout());
          }
        });
      }
    }
  }

  EmoticonSaveToPhotosCallback? get _platformSaveToPhotos {
    if (!PlatformUtils.isAndroid && !PlatformUtils.isIOS) {
      return null;
    }
    return (filename, data) => DownloadUtils.saveMediaToPhotosIfSupported(
      bytes: data,
      filename: filename,
      mimeType: 'image/png',
    );
  }

  @override
  void dispose() {
    controller.dispose();
    editorController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.createPack) {
      return _buildPackEditor(context);
    }

    final editor = editorController!;
    final mobileLayout = widget.mobileLayout ?? Layout.mobile;

    if (mobileLayout) {
      return EmoticonCreatorMobile(
        controller: editor,
        creatingNew: widget.creatingNew,
        pickSourceImage: widget.pickSourceImage,
      );
    }

    return EmoticonCreatorDesktop(
      controller: editor,
      creatingNew: widget.creatingNew,
      pickSourceImage: widget.pickSourceImage,
    );
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
                        child: EmoticonImagePickTile(
                          image: image,
                          tooltip: EmoticonCreatorStrings.promptSelectPhoto,
                          onTap: _pickPackImage,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minWidth: 300),
                          child: tiamat.TextInput(
                            maxLines: 1,
                            placeholder: promptEmoticonPackName,
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
                      text: EmoticonCreatorStrings.promptConfirmSaveEmoticon,
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
                    EmoticonStatusText(text: errorText!, isError: true),
                  ],
                  if (statusText != null) ...[
                    const SizedBox(height: 10),
                    EmoticonStatusText(text: statusText!, isError: false),
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
}
