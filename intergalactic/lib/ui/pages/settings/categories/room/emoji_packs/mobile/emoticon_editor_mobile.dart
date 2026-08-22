import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_draft_store_models.dart';
import 'package:intergalactic/ui/atoms/scaled_safe_area.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/controls/emoticon_editor_controls.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/emoticon_editor_controller.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/mobile/emoticon_tool_tray.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Pushes the mobile Editor sub-mode as a full-height route. Returns after
/// the editor pops; the controller session is committed (Done) or discarded
/// (Back/system back) before the pop.
Future<void> showEmoticonEditorMobile(
  BuildContext context, {
  required EmoticonEditorController controller,
  required Future<void> Function(BuildContext context) onCropRequested,
  required Future<void> Function() onPickSourceImage,
  required Future<bool> Function(BuildContext context, EmoticonDraft draft)
  confirmDeleteDraft,
  required Future<bool> Function(
    BuildContext context,
    List<EmoticonDraft> drafts,
  )
  confirmDeleteDrafts,
}) {
  controller.beginEditSession();
  final duration = InterGalacticMotion.duration(
    context,
    InterGalacticMotion.mobileRoute,
  );

  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      fullscreenDialog: true,
      transitionDuration: duration,
      reverseTransitionDuration: duration,
      pageBuilder: (context, animation, secondaryAnimation) {
        return EmoticonEditorMobile(
          controller: controller,
          onCropRequested: onCropRequested,
          onPickSourceImage: onPickSourceImage,
          confirmDeleteDraft: confirmDeleteDraft,
          confirmDeleteDrafts: confirmDeleteDrafts,
        );
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (InterGalacticMotion.shouldReduce(context)) {
          return child;
        }
        return SlideTransition(
          position: animation.drive(
            Tween(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).chain(CurveTween(curve: InterGalacticMotion.emphasis)),
          ),
          child: child,
        );
      },
    ),
  );
}

/// The mobile canvas-dominant Editor (R2, R3): top bar with Back/Done, a
/// canvas that fills all space not used by chrome, and the bottom tab bar +
/// single tool tray above the system inset. Exposes no Save affordance —
/// naming and Save live only on the Quick card (R6).
class EmoticonEditorMobile extends StatelessWidget {
  const EmoticonEditorMobile({
    required this.controller,
    required this.onCropRequested,
    required this.onPickSourceImage,
    required this.confirmDeleteDraft,
    required this.confirmDeleteDrafts,
    super.key,
  });

  final EmoticonEditorController controller;
  final Future<void> Function(BuildContext context) onCropRequested;
  final Future<void> Function() onPickSourceImage;
  final Future<bool> Function(BuildContext context, EmoticonDraft draft)
  confirmDeleteDraft;
  final Future<bool> Function(BuildContext context, List<EmoticonDraft> drafts)
  confirmDeleteDrafts;

  void _close(BuildContext context, {required bool commit}) {
    if (commit) {
      controller.commitEditSession();
    } else {
      controller.discardEditSession();
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) {
              _close(context, commit: false);
            }
          },
          child: Scaffold(
            backgroundColor: theme.colorScheme.surface,
            body: ScaledSafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTopBar(context),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: EmoticonCutoutCanvas(
                              controller: controller,
                              square: false,
                              onPickSourceImage: () =>
                                  unawaited(onPickSourceImage()),
                            ),
                          ),
                          if (controller.loading)
                            const Center(child: CircularProgressIndicator()),
                        ],
                      ),
                    ),
                  ),
                  EmoticonToolTray(
                    controller: controller,
                    onCropRequested: () => onCropRequested(context),
                    onPickSourceImage: () => unawaited(onPickSourceImage()),
                    confirmDeleteDraft: (draft) =>
                        confirmDeleteDraft(context, draft),
                    confirmDeleteDrafts: (drafts) =>
                        confirmDeleteDrafts(context, drafts),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.22),
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          tiamat.IconButton(
            key: const ValueKey('emoticon-editor-back'),
            icon: Icons.arrow_back,
            tooltip: 'Discard edits',
            onPressed: () => _close(context, commit: false),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: tiamat.Text.labelEmphasised(
              EmoticonCreatorStrings.titleCutoutEditor,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          EmoticonMaskHistoryControls(controller: controller),
          const SizedBox(width: 4),
          SizedBox(
            height: 40,
            child: tiamat.Button(
              key: const ValueKey('emoticon-editor-done'),
              text: EmoticonCreatorStrings.promptDone,
              onTap: () => _close(context, commit: true),
            ),
          ),
        ],
      ),
    );
  }
}
