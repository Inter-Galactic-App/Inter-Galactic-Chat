import 'package:flutter/material.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_draft_store_models.dart';
import 'package:intergalactic/ui/mobile/mobile_visuals.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/controls/emoticon_editor_controls.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/emoticon_editor_controller.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Bottom tab bar plus the single raised tool tray for the mobile Editor.
///
/// Exactly one tray is open at a time, keyed by
/// [EmoticonEditorController.activeToolGroup]; re-tapping the active tab
/// closes the tray so the canvas is fully maximal (KTD-3). Brush renders the
/// thin-strip tray variant so mask painting keeps the canvas clear (R5). The
/// host wraps this widget in `ScaledSafeArea(bottom)` so neither the tab bar
/// nor the tray sits under the Android nav bar / iOS home indicator (R7).
class EmoticonToolTray extends StatelessWidget {
  const EmoticonToolTray({
    required this.controller,
    required this.onCropRequested,
    required this.onPickSourceImage,
    required this.confirmDeleteDraft,
    required this.confirmDeleteDrafts,
    super.key,
  });

  final EmoticonEditorController controller;
  final VoidCallback onCropRequested;
  final VoidCallback onPickSourceImage;
  final Future<bool> Function(EmoticonDraft draft) confirmDeleteDraft;
  final Future<bool> Function(List<EmoticonDraft> drafts) confirmDeleteDrafts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = controller.activeToolGroup;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSize(
          duration: InterGalacticMotion.duration(
            context,
            InterGalacticMotion.standard,
          ),
          curve: InterGalacticMotion.standardOut,
          alignment: Alignment.bottomCenter,
          child: active == null
              ? const SizedBox(width: double.infinity, height: 0)
              : _buildTray(context, active),
        ),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outline.withValues(alpha: 0.22),
              ),
            ),
          ),
          child: Row(
            children: EmoticonToolGroup.values
                .map((group) => Expanded(child: _buildTab(context, group)))
                .toList(growable: false),
          ),
        ),
      ],
    );
  }

  Widget _buildTab(BuildContext context, EmoticonToolGroup group) {
    final theme = Theme.of(context);
    final selected = controller.activeToolGroup == group;
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: '${group.label} tools',
      child: InkWell(
        key: ValueKey('emoticon-tool-tab-${group.name}'),
        onTap: () => controller.toggleToolGroup(group),
        child: Container(
          // >= 40px tap target plus the selected underline accent.
          constraints: const BoxConstraints(minHeight: 48),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                width: 2,
                color: selected
                    ? theme.colorScheme.primary
                    : Colors.transparent,
              ),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(group.icon, size: 20, color: color),
              const SizedBox(height: 2),
              Text(
                group.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: selected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTray(BuildContext context, EmoticonToolGroup group) {
    final theme = Theme.of(context);
    final compact = group == EmoticonToolGroup.brush;

    return Container(
      key: ValueKey('emoticon-tool-tray-${group.name}'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.22),
          ),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        MobileVisuals.screenPadding,
        compact ? 6 : 12,
        MobileVisuals.screenPadding,
        compact ? 4 : 10,
      ),
      child: ConstrainedBox(
        // The tray is one tool group at full width; non-brush trays scroll if
        // they would otherwise starve the canvas.
        constraints: BoxConstraints(
          maxHeight: compact ? 132 : MediaQuery.of(context).size.height * 0.38,
        ),
        child: SingleChildScrollView(child: _buildTrayBody(context, group)),
      ),
    );
  }

  Widget _buildTrayBody(BuildContext context, EmoticonToolGroup group) {
    final theme = Theme.of(context);

    switch (group) {
      case EmoticonToolGroup.cutout:
        return EmoticonAutoMaskControls(controller: controller);
      case EmoticonToolGroup.brush:
        return EmoticonBrushControls(controller: controller, compact: true);
      case EmoticonToolGroup.crop:
        final hasSource = controller.sourceImageData != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Photo sourcing above cropping: with no image the user is here to
            // pick one, and Crop is disabled until they do. Desktop's Photo
            // group already carried both actions (KTD-3).
            SizedBox(
              height: 44,
              child: tiamat.Button.secondary(
                key: const ValueKey('emoticon-editor-pick-photo'),
                text: hasSource
                    ? EmoticonCreatorStrings.promptChangePhoto
                    : EmoticonCreatorStrings.promptSelectPhoto,
                onTap: controller.loading ? null : onPickSourceImage,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: tiamat.Button.secondary(
                text: EmoticonCreatorStrings.promptCropPhoto,
                onTap:
                    !hasSource ||
                        controller.loading ||
                        controller.processingCutout
                    ? null
                    : onCropRequested,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Cropping re-seats the image as the new source; run Auto again '
              'to rebuild the cutout.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      case EmoticonToolGroup.output:
        return EmoticonOutputControls(controller: controller);
      case EmoticonToolGroup.preview:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EmoticonPreviewBackgroundPicker(controller: controller),
            const SizedBox(height: 10),
            Row(
              children: [
                EmoticonMiniPreview(
                  bytes:
                      controller.cutoutResult?.pngBytes ?? controller.imageData,
                  size: 32,
                  background: controller.previewBackground,
                ),
                const SizedBox(width: 8),
                EmoticonMiniPreview(
                  bytes:
                      controller.cutoutResult?.pngBytes ?? controller.imageData,
                  size: 72,
                  background: controller.previewBackground,
                ),
              ],
            ),
          ],
        );
      case EmoticonToolGroup.drafts:
        return EmoticonDraftsPanel(
          controller: controller,
          confirmDeleteDraft: confirmDeleteDraft,
          confirmDeleteDrafts: confirmDeleteDrafts,
        );
    }
  }
}
