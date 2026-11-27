import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_draft_store_models.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/controls/emoticon_editor_controls.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/emoticon_editor_controller.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// The desktop two-pane Editor (R11): canvas left, a persistent docked
/// control panel right. The panel is an accordion over the same
/// [EmoticonToolGroup] set as the mobile trays, rendered from the same shared
/// control bodies — all groups stay reachable without a raise/collapse
/// interaction, because desktop space is not scarce (KTD-5). No Save lives
/// here; Done/Back return to the Quick panel (R10).
class EmoticonEditorDesktop extends StatelessWidget {
  const EmoticonEditorDesktop({
    required this.controller,
    required this.onDone,
    required this.onBack,
    required this.onPickSourceImage,
    required this.onCropRequested,
    required this.confirmDeleteDraft,
    required this.confirmDeleteDrafts,
    super.key,
  });

  final EmoticonEditorController controller;
  final VoidCallback onDone;
  final VoidCallback onBack;
  final VoidCallback onPickSourceImage;
  final VoidCallback onCropRequested;
  final Future<bool> Function(EmoticonDraft draft) confirmDeleteDraft;
  final Future<bool> Function(List<EmoticonDraft> drafts) confirmDeleteDrafts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final availableHeight =
        mediaQuery.size.height - mediaQuery.viewInsets.bottom - 148;
    final editorMaxHeight = math.min(720.0, math.max(340.0, availableHeight));

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 900,
            maxHeight: editorMaxHeight,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedOpacity(
                opacity: controller.loading ? 0.55 : 1,
                duration: Durations.short2,
                child: IgnorePointer(
                  ignoring: controller.loading,
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
                                  Expanded(
                                    child: SingleChildScrollView(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          _buildCanvasColumn(maxSide: 360),
                                          const SizedBox(height: 12),
                                          EmoticonPreviewMetadata(
                                            controller: controller,
                                          ),
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
                                  SizedBox(
                                    width: math.min(
                                      340.0,
                                      constraints.maxWidth * 0.45,
                                    ),
                                    child: Column(
                                      children: [
                                        Expanded(
                                          child: _buildToolPanel(context),
                                        ),
                                        _buildActionBar(context),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      12,
                                      12,
                                      8,
                                    ),
                                    child: _buildCanvasColumn(
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
                                  Expanded(child: _buildToolPanel(context)),
                                  _buildActionBar(context),
                                ],
                              ),
                      );
                    },
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

  Widget _buildCanvasColumn({required double maxSide}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : maxSide;
        final side = math.min(maxSide, availableWidth);

        // The preview row's fixed content is 32 + 8 + 72 = 112px of previews
        // plus the history controls. Below this the Row overflows, and `side`
        // genuinely can reach ~150px on a narrow desktop window - so the
        // controls move to their own line rather than being clipped.
        const previewRowMinWidth = 192.0;
        final stackHistoryControls = side < previewRowMinWidth;

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: side,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                EmoticonCutoutCanvas(
                  controller: controller,
                  onPickSourceImage: onPickSourceImage,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    EmoticonMiniPreview(
                      bytes:
                          controller.cutoutResult?.pngBytes ??
                          controller.imageData ??
                          controller.sourceImageData,
                      size: 32,
                      background: controller.previewBackground,
                    ),
                    const SizedBox(width: 8),
                    EmoticonMiniPreview(
                      bytes:
                          controller.cutoutResult?.pngBytes ??
                          controller.imageData ??
                          controller.sourceImageData,
                      size: 72,
                      background: controller.previewBackground,
                    ),
                    const Spacer(),
                    // Beside the canvas rather than in the action bar: that
                    // bar is only ~290px wide and Back + Done already fill it.
                    if (!stackHistoryControls)
                      EmoticonMaskHistoryControls(controller: controller),
                  ],
                ),
                if (stackHistoryControls) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: EmoticonMaskHistoryControls(controller: controller),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildToolPanel(BuildContext context) {
    return ListView(
      key: const ValueKey('emoticon-desktop-tool-panel'),
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      children: EmoticonToolGroup.values
          .map((group) => _buildToolGroupTile(context, group))
          .toList(growable: false),
    );
  }

  Widget _buildToolGroupTile(BuildContext context, EmoticonToolGroup group) {
    final theme = Theme.of(context);

    return Theme(
      data: theme.copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey('emoticon-desktop-group-${group.name}'),
        initiallyExpanded:
            group == (controller.activeToolGroup ?? EmoticonToolGroup.cutout),
        maintainState: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 10),
        childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
        leading: Icon(group.icon, size: 20),
        title: Text(
          group.label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        children: [_buildGroupBody(context, group)],
      ),
    );
  }

  Widget _buildGroupBody(BuildContext context, EmoticonToolGroup group) {
    switch (group) {
      case EmoticonToolGroup.cutout:
        return EmoticonAutoMaskControls(controller: controller);
      case EmoticonToolGroup.brush:
        return EmoticonBrushControls(controller: controller);
      case EmoticonToolGroup.crop:
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: 150,
              child: tiamat.Button.secondary(
                text: controller.sourceImageData == null
                    ? EmoticonCreatorStrings.promptEmoticonCreatorSelectPhoto
                    : EmoticonCreatorStrings.promptEmoticonCreatorChangePhoto,
                onTap: controller.loading ? null : onPickSourceImage,
              ),
            ),
            SizedBox(
              width: 110,
              child: tiamat.Button.secondary(
                text: EmoticonCreatorStrings.promptEmoticonCreatorCropPhoto,
                onTap:
                    controller.sourceImageData == null ||
                        controller.loading ||
                        controller.processingCutout
                    ? null
                    : onCropRequested,
              ),
            ),
          ],
        );
      case EmoticonToolGroup.output:
        return EmoticonOutputControls(controller: controller);
      case EmoticonToolGroup.preview:
        return EmoticonPreviewBackgroundPicker(controller: controller);
      case EmoticonToolGroup.drafts:
        return EmoticonDraftsPanel(
          controller: controller,
          confirmDeleteDraft: confirmDeleteDraft,
          confirmDeleteDrafts: confirmDeleteDrafts,
        );
    }
  }

  Widget _buildActionBar(BuildContext context) {
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            EmoticonStatusMessages(controller: controller),
            Row(
              children: [
                SizedBox(
                  width: 110,
                  height: 40,
                  child: tiamat.Button.secondary(
                    key: const ValueKey('emoticon-desktop-editor-back'),
                    text: 'Back',
                    onTap: controller.loading ? null : onBack,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 140,
                  height: 40,
                  child: tiamat.Button(
                    key: const ValueKey('emoticon-desktop-editor-done'),
                    text: EmoticonCreatorStrings.promptEmoticonEditorDone,
                    onTap: controller.loading ? null : onDone,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
