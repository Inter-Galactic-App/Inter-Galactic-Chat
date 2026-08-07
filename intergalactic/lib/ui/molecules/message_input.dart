import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/emoticon/dynamic_emoticon_pack.dart';
import 'package:intergalactic/client/components/emoticon_recent/recent_emoticon_component.dart';
import 'package:intergalactic/client/components/gif/gif_component.dart';
import 'package:intergalactic/client/components/polls/poll_component.dart';
import 'package:intergalactic/client/components/voice/voice_recorder_bridge.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/gif_api_key_store.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/accessibility/accessible_interactive_region.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:intergalactic/ui/mobile/mobile_surface.dart';
import 'package:intergalactic/ui/mobile/mobile_visuals.dart';
import 'package:intergalactic/ui/atoms/emoji_widget.dart';
import 'package:intergalactic/ui/atoms/keyboard_adaptor.dart';
import 'package:intergalactic/ui/atoms/random_emoji_button.dart';
import 'package:intergalactic/ui/atoms/rich_text_field.dart';
import 'package:intergalactic/ui/molecules/attachment_icon.dart';
import 'package:intergalactic/ui/molecules/composer_bracket_formatter.dart';
import 'package:intergalactic/ui/molecules/markdown_selection_toolbar.dart';
import 'package:intergalactic/ui/molecules/overlapping_panels.dart';
import 'package:intergalactic/ui/molecules/poll_creator.dart';
import 'package:intergalactic/ui/organisms/attachment_processor/attachment_processor.dart';
import 'package:intergalactic/ui/molecules/emoticon_picker.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/onboarding/tutorial_anchor.dart';
import 'package:intergalactic/ui/organisms/chat/chat.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/settings_category_room.dart';
import 'package:intergalactic/ui/pages/settings/room_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/settings_navigation.dart';
import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/client/components/gif/gif_search_result.dart';
import 'package:intergalactic/utils/autofill_utils.dart';
import 'package:intergalactic/utils/debounce.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:intergalactic/utils/room_mention_utils.dart';
import 'package:intergalactic/utils/scaled_app.dart';
import 'package:intergalactic/utils/text_utils.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:pasteboard/pasteboard.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import '../../client/attachment.dart';
import '../../client/components/emoticon/emoticon.dart';

enum MessageInputSendResult { success, unhandled }

TextEditingValue insertEmoticonIntoComposerValue(
  TextEditingValue value,
  Emoticon emote,
) {
  var text = value.text;
  var selection = value.selection;
  var start = selection.start;
  var end = selection.end;
  var slug = emote.slug;

  if (start == -1 && end == -1) {
    if (text.isNotEmpty && !text.endsWith(" ")) {
      text += " ";
    }
    text += slug;
    return value.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange.empty,
    );
  }

  if (start < 0 || end < 0) {
    start = text.length;
    end = text.length;
  }

  final replacementStart = math.min(start, end);
  final replacementEnd = math.max(start, end);

  // Add whitespace where necessary.
  if (emote.slug.startsWith(":") || emote.slug.endsWith(":")) {
    if (replacementStart > 0) {
      var startChar = text[replacementStart - 1];
      if (startChar != " ") slug = " $slug";
    }

    if (replacementEnd < text.length) {
      var endChar = text[replacementEnd];
      if (endChar != " ") slug = "$slug ";
    } else {
      slug = "$slug ";
    }
  }

  final newText = text.replaceRange(replacementStart, replacementEnd, slug);
  final newOffset = replacementStart + slug.length;
  return value.copyWith(
    text: newText,
    selection: TextSelection.collapsed(offset: newOffset),
    composing: TextRange.empty,
  );
}

class AttachmentPicker {
  IconData icon;
  String label;

  FutureOr<void> Function() execute;

  AttachmentPicker({
    required this.icon,
    required this.label,
    required this.execute,
  });
}

const composerCameraAttachmentLabel = "Camera";
const composerMobileCameraAttachmentLabel = composerCameraAttachmentLabel;
const composerCameraCapturePhotoLabel = "Take photo";
const composerCameraCaptureVideoLabel = "Record video";
const _iosCameraMediaPickerChannel = MethodChannel(
  "chat.intergalactic.app/ios_camera_media_picker",
);
const _androidCameraMediaPickerChannel = MethodChannel(
  "chat.intergalactic.app/android_camera_media_picker",
);

enum ComposerCameraCaptureKind { photo, video }

class ComposerCameraCaptureChoice {
  const ComposerCameraCaptureChoice({
    required this.kind,
    required this.icon,
    required this.label,
  });

  final ComposerCameraCaptureKind kind;
  final IconData icon;
  final String label;
}

const composerCameraCaptureChoices = [
  ComposerCameraCaptureChoice(
    kind: ComposerCameraCaptureKind.photo,
    icon: Icons.camera_alt_rounded,
    label: composerCameraCapturePhotoLabel,
  ),
  ComposerCameraCaptureChoice(
    kind: ComposerCameraCaptureKind.video,
    icon: Icons.videocam_rounded,
    label: composerCameraCaptureVideoLabel,
  ),
];

Future<PendingFileAttachment?> pickComposerCameraAttachment({
  required ImagePicker picker,
  required ComposerCameraCaptureKind kind,
  required bool includePath,
}) async {
  final file = switch (kind) {
    ComposerCameraCaptureKind.photo => await picker.pickImage(
      source: ImageSource.camera,
    ),
    ComposerCameraCaptureKind.video => await picker.pickVideo(
      source: ImageSource.camera,
    ),
  };

  return pendingAttachmentFromPickedComposerCameraMedia(
    file,
    includePath: includePath,
  );
}

Future<PendingFileAttachment?> pickComposerIosCameraAttachment({
  required bool includePath,
}) async {
  return pickComposerNativeCameraAttachment(
    channel: _iosCameraMediaPickerChannel,
    includePath: includePath,
  );
}

Future<PendingFileAttachment?> pickComposerAndroidCameraAttachment({
  required ComposerCameraCaptureKind kind,
  required bool includePath,
}) async {
  return pickComposerNativeCameraAttachment(
    channel: _androidCameraMediaPickerChannel,
    kind: kind,
    includePath: includePath,
  );
}

Future<PendingFileAttachment?> pickComposerNativeCameraAttachment({
  required MethodChannel channel,
  ComposerCameraCaptureKind? kind,
  required bool includePath,
}) async {
  final result = await channel.invokeMapMethod<String, Object?>(
    "pickCameraMedia",
    kind == null ? null : {"kind": composerCameraCaptureKindNativeValue(kind)},
  );
  if (result == null) {
    return null;
  }

  final path = result["path"] as String?;
  if (path == null || path.isEmpty) {
    return null;
  }

  final file = XFile(
    path,
    name:
        (result["name"] as String?) ??
        path.replaceAll(r'\', '/').split('/').last,
    mimeType: result["mimeType"] as String?,
  );

  return pendingAttachmentFromPickedComposerCameraMedia(
    file,
    includePath: includePath,
  );
}

String composerCameraCaptureKindNativeValue(ComposerCameraCaptureKind kind) {
  return switch (kind) {
    ComposerCameraCaptureKind.photo => "photo",
    ComposerCameraCaptureKind.video => "video",
  };
}

bool composerUsesNativeCameraPicker({
  required bool isAndroid,
  required bool isIOS,
}) {
  return isAndroid || isIOS;
}

bool composerShowsCameraCaptureChoiceBeforeNativePicker({
  required bool isAndroid,
  required bool isIOS,
}) {
  return isAndroid && !isIOS;
}

bool shouldRetainMobilePickerSpaceForAttachmentMenu({
  required bool isAndroid,
  required bool isIOS,
  required bool isMobile,
  required bool shouldOpen,
  required bool showEmotePicker,
  required bool isPickerSearchFocused,
}) {
  return (isAndroid || isIOS) &&
      isMobile &&
      shouldOpen &&
      (showEmotePicker || isPickerSearchFocused);
}

Future<PendingFileAttachment?> pendingAttachmentFromPickedComposerCameraMedia(
  XFile? file, {
  required bool includePath,
}) async {
  if (file == null) {
    return null;
  }

  final data = await file.readAsBytes();
  return PendingFileAttachment(
    name: composerPickedCameraFileName(file),
    path: includePath ? file.path : null,
    mimeType: file.mimeType,
    size: data.lengthInBytes,
    data: data,
  );
}

String composerPickedCameraFileName(XFile file) {
  final name = file.name.trim();
  final normalized = name.replaceAll(r'\', '/');
  final segment = normalized.split('/').last.trim();
  if (segment.isNotEmpty) {
    return segment;
  }

  final pathSegment = file.path.replaceAll(r'\', '/').split('/').last.trim();
  return pathSegment.isEmpty ? 'camera-media' : pathSegment;
}

enum ComposerEffectKind {
  commandMessage,
  commandOnly,
  wrapMessage,
  prefixMessage,
}

class ComposerEffectOption {
  const ComposerEffectOption({
    required this.emoji,
    required this.label,
    required this.kind,
    this.command,
    this.wrapper,
    this.prefix,
    this.emptyDraftText,
    this.emptyDraftCursorOffset,
  });

  final String emoji;
  final String label;
  final ComposerEffectKind kind;
  final String? command;
  final String? wrapper;
  final String? prefix;
  final String? emptyDraftText;
  final int? emptyDraftCursorOffset;
}

const composerMessageEffects = [
  ComposerEffectOption(
    emoji: "🎉",
    label: "Confetti",
    kind: ComposerEffectKind.commandMessage,
    command: "confetti",
    emptyDraftText: "/confetti ",
  ),
  ComposerEffectOption(
    emoji: "🌈",
    label: "Rainbow",
    kind: ComposerEffectKind.commandMessage,
    command: "rainbow",
    emptyDraftText: "/rainbow ",
  ),
  ComposerEffectOption(
    emoji: "❄️",
    label: "Snowfall",
    kind: ComposerEffectKind.commandMessage,
    command: "snowfall",
    emptyDraftText: "/snowfall ",
  ),
  ComposerEffectOption(
    emoji: "👾",
    label: "Space invaders",
    kind: ComposerEffectKind.commandMessage,
    command: "spaceinvaders",
    emptyDraftText: "/spaceinvaders ",
  ),
  ComposerEffectOption(
    emoji: "🙈",
    label: "Hidden",
    kind: ComposerEffectKind.wrapMessage,
    wrapper: "||",
    emptyDraftText: "||||",
    emptyDraftCursorOffset: 2,
  ),
  ComposerEffectOption(
    emoji: "📣",
    label: "Loud",
    kind: ComposerEffectKind.prefixMessage,
    prefix: "### ",
    emptyDraftText: "### ",
  ),
];

const composerEmojiEffects = [
  ComposerEffectOption(
    emoji: "🤗",
    label: "Cuddle",
    kind: ComposerEffectKind.commandOnly,
    command: "cuddle",
  ),
  ComposerEffectOption(
    emoji: "👀",
    label: "Googly",
    kind: ComposerEffectKind.commandOnly,
    command: "googly",
  ),
  ComposerEffectOption(
    emoji: "🫂",
    label: "Hug",
    kind: ComposerEffectKind.commandOnly,
    command: "hug",
  ),
];

String? composerEffectSendText(
  ComposerEffectOption option,
  String currentText,
) {
  final text = currentText.trim();

  switch (option.kind) {
    case ComposerEffectKind.commandOnly:
      final command = option.command;
      return command == null ? null : "/$command";
    case ComposerEffectKind.commandMessage:
      if (text.isEmpty) return null;
      final command = option.command;
      return command == null ? null : "/$command $text";
    case ComposerEffectKind.wrapMessage:
      if (text.isEmpty) return null;
      final wrapper = option.wrapper;
      return wrapper == null ? null : "$wrapper$text$wrapper";
    case ComposerEffectKind.prefixMessage:
      if (text.isEmpty) return null;
      final prefix = option.prefix;
      return prefix == null ? null : "$prefix$text";
  }
}

TextEditingValue? composerEffectDraftValue(ComposerEffectOption option) {
  final draft = option.emptyDraftText;
  if (draft == null) {
    return null;
  }

  return TextEditingValue(
    text: draft,
    selection: TextSelection.collapsed(
      offset: option.emptyDraftCursorOffset ?? draft.length,
    ),
  );
}

class ComposerPopupCard extends StatelessWidget {
  const ComposerPopupCard({
    required this.preferredWidth,
    required this.maxHeight,
    required this.child,
    this.safeHorizontalPadding = 24,
    super.key,
  });

  final double preferredWidth;
  final double maxHeight;
  final double safeHorizontalPadding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mediaWidth = MediaQuery.of(context).size.width;
    final safeWidth = math.max(160.0, mediaWidth - safeHorizontalPadding);
    final width = math.min(preferredWidth, safeWidth);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SizedBox(
        width: width,
        child: ComposerPopupSurface(child: child),
      ),
    );
  }
}

class ComposerPopupSurface extends StatelessWidget {
  const ComposerPopupSurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDesktopPopup = Layout.desktop;
    final radius = BorderRadius.circular(isDesktopPopup ? 12 : 24);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDesktopPopup ? 0.2 : 0.18),
            blurRadius: isDesktopPopup ? 18 : 22,
            offset: Offset(0, isDesktopPopup ? 8 : 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: isDesktopPopup
            ? DesktopPanelEdgeHighlight(
                borderRadius: radius,
                child: _ComposerDesktopPopupBody(
                  child: child,
                  radius: radius,
                  scheme: scheme,
                ),
              )
            : MobileGlassEdgeHighlight(
                borderRadius: radius,
                style: MobileGlassHighlightStyle.composer,
                intensity: 0.8,
                child: _ComposerMobilePopupBody(
                  child: child,
                  radius: radius,
                  scheme: scheme,
                ),
              ),
      ),
    );
  }
}

class ComposerPopupSectionLabel extends StatelessWidget {
  const ComposerPopupSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDesktopLabel = Layout.desktop;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isDesktopLabel ? 12 : 16,
        isDesktopLabel ? 6 : 8,
        isDesktopLabel ? 12 : 16,
        5,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontSize: isDesktopLabel ? 11 : 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class ComposerPopupDivider extends StatelessWidget {
  const ComposerPopupDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Layout.desktop ? 12 : 16,
        7,
        Layout.desktop ? 12 : 16,
        5,
      ),
      child: Divider(
        height: 1,
        thickness: 1,
        color: scheme.outlineVariant.withValues(
          alpha: Layout.desktop ? 0.38 : 0.24,
        ),
      ),
    );
  }
}

class ComposerPopupAction extends StatelessWidget {
  const ComposerPopupAction({
    this.icon,
    this.emoji,
    required this.label,
    required this.onTap,
    this.selected = false,
    super.key,
  });

  final IconData? icon;
  final String? emoji;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDesktopAction = Layout.desktop;
    final accent = isDesktopAction
        ? scheme.outline
        : selected
        ? scheme.primary
        : scheme.secondary;
    final textColor = isDesktopAction
        ? scheme.onSurface
        : selected
        ? scheme.onPrimaryContainer
        : scheme.onSurface;
    final emojiIconStyle = TextStyle(
      fontSize: isDesktopAction ? 15 : 17,
      height: 1,
    );
    final resolvedEmojiIconStyle = !isDesktopAction && PlatformUtils.isIOS
        ? TextUtils.withNativeEmojiFallback(emojiIconStyle)
        : emojiIconStyle;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isDesktopAction ? 4 : 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isDesktopAction ? 9 : 16),
        child: Material(
          color: selected
              ? (isDesktopAction
                    ? scheme.outline.withValues(alpha: 0.14)
                    : scheme.primaryContainer.withValues(alpha: 0.34))
              : Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: isDesktopAction ? 38 : 44,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isDesktopAction ? 8 : 10,
                  0,
                  isDesktopAction ? 10 : 12,
                  0,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: isDesktopAction ? 26 : 30,
                      height: isDesktopAction ? 26 : 30,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                            isDesktopAction ? 7 : 999,
                          ),
                          color: accent.withValues(alpha: 0.12),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.18),
                          ),
                        ),
                        child: emoji == null
                            ? Icon(
                                icon,
                                size: isDesktopAction ? 15 : 16,
                                color: accent,
                              )
                            : Center(
                                child: Text(
                                  emoji!,
                                  style: resolvedEmojiIconStyle,
                                ),
                              ),
                      ),
                    ),
                    SizedBox(width: isDesktopAction ? 8 : 10),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: textColor,
                          fontSize: isDesktopAction ? 13 : null,
                          fontWeight: isDesktopAction
                              ? FontWeight.w500
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ComposerAttachmentMenuContent extends StatelessWidget {
  const ComposerAttachmentMenuContent({
    required this.pickers,
    required this.onPickerSelected,
    super.key,
  });

  final List<AttachmentPicker> pickers;
  final ValueChanged<AttachmentPicker> onPickerSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6),
      shrinkWrap: true,
      itemCount: pickers.length,
      separatorBuilder: (context, index) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final picker = pickers[index];
        return ComposerPopupAction(
          icon: picker.icon,
          label: picker.label,
          onTap: () => onPickerSelected(picker),
        );
      },
    );
  }
}

class ComposerCameraCaptureSheet extends StatelessWidget {
  const ComposerCameraCaptureSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final choice in composerCameraCaptureChoices)
              ComposerPopupAction(
                icon: choice.icon,
                label: choice.label,
                onTap: () => Navigator.of(context).pop(choice.kind),
              ),
          ],
        ),
      ),
    );
  }
}

class ComposerCommandMenuContent extends StatelessWidget {
  const ComposerCommandMenuContent({
    required this.results,
    required this.onSelected,
    this.selectedIndex,
    super.key,
  });

  final List<AutofillSearchResult> results;
  final int? selectedIndex;
  final ValueChanged<AutofillSearchResult> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6),
      shrinkWrap: true,
      itemCount: results.length,
      separatorBuilder: (context, index) => const SizedBox(height: 2),
      itemBuilder: (context, index) {
        final data = results[index];
        final selected =
            selectedIndex != null &&
            selectedIndex! < results.length &&
            data == results[selectedIndex!];

        return ComposerPopupAction(
          icon: Icons.terminal_rounded,
          label: data.result,
          selected: selected,
          onTap: () => onSelected(data),
        );
      },
    );
  }
}

class ComposerEffectsMenuContent extends StatelessWidget {
  const ComposerEffectsMenuContent({required this.onSelected, super.key});

  final ValueChanged<ComposerEffectOption> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      primary: false,
      shrinkWrap: true,
      children: [
        const ComposerPopupSectionLabel("Send message with:"),
        for (final effect in composerMessageEffects)
          ComposerPopupAction(
            emoji: effect.emoji,
            label: effect.label,
            onTap: () => onSelected(effect),
          ),
        const ComposerPopupDivider(),
        const ComposerPopupSectionLabel("Send emoji effect:"),
        for (final effect in composerEmojiEffects)
          ComposerPopupAction(
            emoji: effect.emoji,
            label: effect.label,
            onTap: () => onSelected(effect),
          ),
      ],
    );
  }
}

class _ComposerDesktopPopupBody extends StatelessWidget {
  const _ComposerDesktopPopupBody({
    required this.child,
    required this.radius,
    required this.scheme,
  });

  final Widget child;
  final BorderRadius radius;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: radius,
      ),
      child: Material(color: Colors.transparent, child: child),
    );
  }
}

class _ComposerMobilePopupBody extends StatelessWidget {
  const _ComposerMobilePopupBody({
    required this.child,
    required this.radius,
    required this.scheme,
  });

  final Widget child;
  final BorderRadius radius;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [scheme.surfaceContainerHigh, scheme.surfaceContainerLow],
        ),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.16)),
      ),
      child: Material(color: Colors.transparent, child: child),
    );
  }
}

class MessageInput extends StatefulWidget {
  const MessageInput({
    super.key,
    required this.client,
    this.room,
    this.maxHeight = 200,
    this.onSendMessage,
    this.isRoomE2EE = false,
    this.onFocusChanged,
    this.readIndicator,
    this.relatedEventBody,
    this.relatedEventSenderColor,
    this.relatedEventSenderName,
    this.interactionType,
    this.focusKeyboard,
    this.setInputText,
    this.isProcessing = false,
    this.initialText,
    this.enabled = true,
    this.editLastMessage,
    this.hintText,
    this.attachments,
    this.addAttachment,
    this.onTextUpdated,
    this.removeAttachment,
    this.typingIndicatorWidget,
    this.availibleEmoticons,
    this.availibleStickers,
    this.compact = false,
    this.gifComponent,
    this.enableKeyboardAdapter = true,
    this.onReadReceiptsClicked,
    this.findOverrideClient,
    this.onTapOverrideClient,
    this.disableEnterToSend = false,
    this.sendGif,
    this.showGifSearch = true,
    this.size = 35,
    this.iconScale = 0.5,
    this.showAttachmentButton = true,
    this.sendSticker,
    this.processAutofill,
    this.onHeightChanged,
    this.cancelReply,
  });
  final double maxHeight;
  final double size;
  final double iconScale;
  final bool isRoomE2EE;
  final bool disableEnterToSend;
  final MessageInputSendResult Function(
    String message, {
    Client? overrideClient,
  })?
  onSendMessage;
  final Widget? readIndicator;
  final String? relatedEventBody;
  final String? relatedEventSenderName;
  final String? hintText;
  final String? initialText;
  final bool showAttachmentButton;
  final bool compact;
  final bool enableKeyboardAdapter;
  final Color? relatedEventSenderColor;
  final List<PendingFileAttachment>? attachments;
  final EventInteractionType? interactionType;
  final Stream<void>? focusKeyboard;
  final bool showGifSearch;
  final Stream<String>? setInputText;
  final bool isProcessing;
  final bool enabled;
  final Room? room;
  final Client client;
  final Widget? typingIndicatorWidget;
  final List<EmoticonPack>? availibleEmoticons;
  final List<EmoticonPack>? availibleStickers;
  final GifComponent? gifComponent;
  final void Function()? onReadReceiptsClicked;
  final void Function(Emoticon sticker)? sendSticker;
  final Future<void> Function(GifSearchResult gif)? sendGif;
  final void Function(bool focused)? onFocusChanged;
  final Function(String currentText)? onTextUpdated;
  final void Function()? cancelReply;
  final void Function()? editLastMessage;
  final Client? Function(String input)? findOverrideClient;
  final void Function(Client overrideClient)? onTapOverrideClient;
  final void Function(PendingFileAttachment attachment)? addAttachment;
  final void Function(PendingFileAttachment attachment)? removeAttachment;
  final List<AutofillSearchResult> Function(String text)? processAutofill;
  final ValueChanged<double>? onHeightChanged;

  @override
  State<MessageInput> createState() => MessageInputState();
}

class MessageInputState extends State<MessageInput> {
  static const mobileComposerDismissDragThreshold = 36.0;

  final GlobalKey inputRootKey = GlobalKey();
  double? lastReportedHeight;

  late FocusNode textFocus;
  FocusNode emojiSearchFocus = FocusNode();
  FocusNode stickerSearchFocus = FocusNode();
  FocusNode gifSearchFocus = FocusNode();

  late TextEditingController controller;
  StreamSubscription? keyboardFocusSubscription;
  StreamSubscription? setInputTextSubscription;
  StreamSubscription? wrapComposerSelectionSubscription;
  StreamSubscription? onScopePopInvoked;
  OverlayEntry? entry;
  OverlayEntry? composerPopupEntry;
  final layerLink = LayerLink();
  final composerPopupLayerLink = LayerLink();
  bool showEmotePicker = false;
  bool emotePickerActive = false;
  bool hasEmotePickerOpened = false;
  List<AutofillSearchResult>? autoFillResults;
  Client? senderOverride;
  bool isRecordingVoiceMessage = false;
  bool voiceRecordingBusy = false;
  bool showAttachmentPickerPopup = false;
  bool showEffectsPickerPopup = false;
  bool keepComposerKeyboardSpaceForPopup = false;
  bool _restoreDesktopTextFocusAfterProcessing = false;
  double mobileComposerDismissDragDistance = 0;
  DateTime? voiceRecordingStartedAt;
  Duration voiceRecordingDuration = Duration.zero;
  Timer? voiceRecordingTicker;

  KeyboardAdaptorController keyboardAdaptorController =
      KeyboardAdaptorController();

  int? autoFillSelection;
  (int, int)? autoFillRange;
  ScrollController autofillScrollController = ScrollController();

  void unfocus() {
    textFocus.unfocus();
  }

  void onKeyboardFocusRequested() {
    textFocus.requestFocus();
  }

  bool get _shouldPreserveTextFocusAcrossProcessing => BuildConfig.DESKTOP;

  void _restoreDesktopTextFocusIfStillIdle() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.isProcessing || !widget.enabled) return;

      final primaryFocus = FocusManager.instance.primaryFocus;
      final focusMovedElsewhere =
          !textFocus.hasFocus &&
          primaryFocus != null &&
          primaryFocus is! FocusScopeNode;
      if (focusMovedElsewhere) return;

      textFocus.requestFocus();
    });
  }

  void setComposerValue(TextEditingValue value) {
    controller.value = value;
    onTextfieldUpdated(controller.text);
  }

  void onSetInputText(String newText) {
    setComposerValue(
      TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      ),
    );
  }

  void notifyHeightChanged() {
    final callback = widget.onHeightChanged;
    if (!mounted || callback == null) {
      return;
    }

    final inputHeight = inputRootKey.currentContext?.size?.height;
    if (inputHeight == null) {
      return;
    }

    final height = inputHeight + mobileCustomPickerPanelHeight;
    if (lastReportedHeight != null &&
        (lastReportedHeight! - height).abs() < 0.5) {
      return;
    }

    lastReportedHeight = height;
    callback(height);
  }

  double get mobileCustomPickerPanelHeight {
    if (!Layout.mobile ||
        (!showEmotePicker && !keepComposerKeyboardSpaceForPopup)) {
      return 0;
    }

    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery == null) {
      return 0;
    }

    final scaledQuery = mediaQuery.scale();
    final keyboardVisible = scaledQuery.viewInsets.bottom > 0;
    final retainedBottomPadding = PlatformUtils.isIOS && keyboardVisible
        ? 0.0
        : scaledQuery.padding.bottom;
    final offset = math.max(
      scaledQuery.viewInsets.bottom,
      scaledQuery.padding.bottom,
    );
    final reservedHeight =
        keyboardAdaptorController.currentReservedHeight?.call() ??
        (keyboardAdaptorController.hasOverride?.call() == true
            ? preferences.emojiPickerHeight.value
            : offset);

    return math.max(0.0, reservedHeight - retainedBottomPadding);
  }

  @override
  void dispose() {
    hideDesktopEmojiOverlay();
    hideComposerPopupOverlay();
    if (voiceRecordingBusy || isRecordingVoiceMessage) {
      unawaited(_cancelVoiceRecordingDuringDispose());
    }
    voiceRecordingTicker?.cancel();
    keyboardFocusSubscription?.cancel();
    setInputTextSubscription?.cancel();
    wrapComposerSelectionSubscription?.cancel();
    preferencesSubscription?.cancel();
    onScopePopInvoked?.cancel();
    sendDebouncer.cancel();
    removeHeightOverrideDebouncer.cancel();
    super.dispose();
  }

  Future<void> _cancelVoiceRecordingDuringDispose() async {
    await _cancelVoiceRecording("during dispose");
  }

  Future<void> _cancelVoiceRecording(String action) async {
    try {
      await VoiceRecorderBridge.cancelRecording();
    } catch (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: "Failed to cancel voice recording $action",
      );
    }
  }

  StreamSubscription? preferencesSubscription;

  @override
  void initState() {
    controller = RichTextEditingController(
      client: widget.client,
      room: widget.room,
      text: widget.initialText,
    );
    controller.addListener(controllerListener);
    keyboardFocusSubscription = widget.focusKeyboard?.listen(
      (_) => onKeyboardFocusRequested(),
    );

    setInputTextSubscription = widget.setInputText?.listen(onSetInputText);
    wrapComposerSelectionSubscription = EventBus
        .wrapComposerSelectionInBrackets
        .stream
        .listen(onWrapComposerSelectionShortcut);
    onScopePopInvoked = EventBus.onPopInvoked.stream.listen(onPopped);

    textFocus = FocusNode(onKeyEvent: onKey);
    textFocus.addListener(onTextFocusChanged);

    preferencesSubscription = preferences.onSettingChanged.listen(
      (_) => setState(() {}),
    );

    if (preferences.autoFocusMessageTextBox.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        textFocus.requestFocus();
      });
    }

    super.initState();
  }

  void onWrapComposerSelectionShortcut(_) {
    if (!mounted ||
        !widget.enabled ||
        widget.isProcessing ||
        !textFocus.hasFocus) {
      return;
    }

    final nextValue = wrapComposerSelectionInBracketsValue(controller.value);
    if (nextValue == controller.value) {
      return;
    }

    setComposerValue(nextValue);
  }

  @override
  void didUpdateWidget(covariant MessageInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isProcessing && widget.isProcessing) {
      _restoreDesktopTextFocusAfterProcessing =
          _shouldPreserveTextFocusAcrossProcessing && textFocus.hasFocus;

      if (!_restoreDesktopTextFocusAfterProcessing) {
        FocusScope.of(context).unfocus();
        unfocus();
      }
    }

    if (oldWidget.isProcessing && !widget.isProcessing) {
      final restoreFocus = _restoreDesktopTextFocusAfterProcessing;
      _restoreDesktopTextFocusAfterProcessing = false;

      if (restoreFocus && widget.enabled) {
        _restoreDesktopTextFocusIfStillIdle();
      }
    }
  }

  String? lastSearchText;
  void onTextfieldUpdated(String value) {
    widget.onTextUpdated?.call(controller.text);
    var range = getAutofillTextRange();
    var shouldClearReservedHeight = false;

    setState(() {
      senderOverride = widget.findOverrideClient?.call(controller.text);
      showAttachmentPickerPopup = false;
      showEffectsPickerPopup = false;
      shouldClearReservedHeight = keepComposerKeyboardSpaceForPopup;
      keepComposerKeyboardSpaceForPopup = false;
    });
    if (shouldClearReservedHeight && !showEmotePicker) {
      keyboardAdaptorController.clearOverride?.call();
    }

    if (range.$1 == -1 || range.$2 == -1) {
      return;
    }

    var text = value.substring(range.$1, range.$2);

    if (text == "") {
      setState(() {
        autoFillResults = null;
        autoFillSelection = null;
        autoFillRange = null;
      });
    }

    if (text == lastSearchText) {
      return;
    }

    if (text.isEmpty) {
      setState(() {
        autoFillResults = [];
        autoFillSelection = null;
        updateAutofillScroll();
      });

      return;
    }

    var result = widget.processAutofill?.call(text);
    autoFillRange = range;

    setState(() {
      autoFillResults = result;
      autoFillSelection = null;
      updateAutofillScroll();
    });
  }

  (int, int) getAutofillTextRange({int? cursorPosition}) {
    var cursor = controller.selection.base.offset;

    if (controller.text == "") {
      return (0, 0);
    }

    int start = cursorPosition ?? cursor;
    int end = controller.text.length;

    final bracketMentionRange = _getBracketMentionRange(start);
    if (bracketMentionRange != null) {
      return bracketMentionRange;
    }

    if (start > 0) {
      start -= 1;
      if (controller.text[start] == ' ') {
        return (0, 0);
      }
    }

    for (int i = start; i >= 0; i--) {
      var char = controller.text[i];
      if (char == ' ') {
        if (i == controller.text.length) {
          start = controller.text.length - 1;
        } else {
          start = i + 1;
        }

        break;
      }

      if (i <= 0) {
        start = 0;
      }
    }

    for (var i = start + 1; i < controller.text.length; i++) {
      var char = controller.text[i];
      if (char == ' ') {
        end = i;
        break;
      }
    }

    return (start, end);
  }

  (int, int)? _getBracketMentionRange(int cursorPosition) {
    if (controller.text.isEmpty) {
      return null;
    }

    final clampedCursor = cursorPosition.clamp(0, controller.text.length);
    final searchStart = clampedCursor == 0 ? 0 : clampedCursor - 1;
    final start = controller.text.lastIndexOf('@[', searchStart);
    if (start == -1) {
      return null;
    }

    final end = controller.text.indexOf(']', start + 2);
    if (end == -1 || clampedCursor > end + 1) {
      return null;
    }

    final previous = start > 0 ? controller.text[start - 1] : null;
    final next = end + 1 < controller.text.length
        ? controller.text[end + 1]
        : null;
    if (!_isMentionBoundary(previous) || !_isMentionBoundary(next)) {
      return null;
    }

    return (start, end + 1);
  }

  bool _isMentionBoundary(String? char) {
    if (char == null) {
      return true;
    }

    return !RegExp(r'[A-Za-z0-9_]').hasMatch(char);
  }

  Debouncer sendDebouncer = Debouncer(delay: Duration(milliseconds: 20));
  void sendMessage() {
    if (widget.isProcessing) {
      return;
    }

    sendDebouncer.run(() {
      if (widget.attachments == null || widget.attachments!.isEmpty) {
        if (controller.text.isEmpty) return;
        if (controller.text.trim().isEmpty) return;
      }

      var result = widget.onSendMessage?.call(
        controller.text.trim(),
        overrideClient: senderOverride,
      );

      if (result == MessageInputSendResult.success) {
        setComposerValue(TextEditingValue.empty);
      }
    });
  }

  void showMoreAttachmentOptions() {}

  // This duration is to try and hide the transition from keyboard popup animation
  Debouncer removeHeightOverrideDebouncer = Debouncer(
    delay: Duration(seconds: 1),
  );

  bool get isInEmojiPicker => showEmotePicker && !textFocus.hasFocus;

  Future<void> toggleEmojiOverlay() async {
    var keyboardOpen = await isKeyboardOpen();
    print("Keyboard open: $keyboardOpen");
    var shouldShowDesktopOverlay = false;
    var shouldHideDesktopOverlay = false;
    var shouldClearKeyboardOverrideImmediately = false;
    var shouldRequestTextFocus = false;

    setState(() {
      showAttachmentPickerPopup = false;
      showEffectsPickerPopup = false;
      autoFillResults = null;
      autoFillSelection = null;
      autoFillRange = null;
      if (Layout.mobile) {
        if (showEmotePicker && !keyboardOpen) {
          // STUPID: since we use android api to dismiss keyboard,
          // requesting focus normally doesnt work, but if we do this
          // we can get the onscreen keyboard back
          emotePickerActive = false;
          if (PlatformUtils.isIOS) {
            showEmotePicker = false;
            keepComposerKeyboardSpaceForPopup = false;
            shouldClearKeyboardOverrideImmediately = true;
            shouldRequestTextFocus = true;
          } else {
            unfocus();
            Future.delayed(Duration(milliseconds: 100)).then((_) {
              textFocus.requestFocus();
            });
            clearKeyboardOverride();
          }
        } else {
          showEmotePicker = true;
          emotePickerActive = true;
          keyboardAdaptorController.keepCurrentSize?.call();
          removeHeightOverrideDebouncer.cancel();
          if (textFocus.hasFocus || isPickerSearchFocused) {
            dismissKeyboard();
          }
        }
      }

      if (Layout.desktop) {
        showEmotePicker = !showEmotePicker;
        emotePickerActive = showEmotePicker;
        shouldShowDesktopOverlay = showEmotePicker;
        shouldHideDesktopOverlay = !showEmotePicker;
      }

      if (showEmotePicker) {
        hasEmotePickerOpened = true;
      }
    });

    if (shouldClearKeyboardOverrideImmediately) {
      removeHeightOverrideDebouncer.cancel();
      keyboardAdaptorController.clearOverride?.call();
    }
    if (shouldRequestTextFocus) {
      textFocus.requestFocus();
    }
    if (shouldShowDesktopOverlay) {
      showDesktopEmojiOverlay();
    } else if (shouldHideDesktopOverlay) {
      hideDesktopEmojiOverlay();
    }
  }

  void clearKeyboardOverride({bool debounce = true}) {
    final func = () {
      if (!mounted) {
        return;
      }
      emojiSearchFocus.unfocus();
      stickerSearchFocus.unfocus();
      gifSearchFocus.unfocus();
      hideDesktopEmojiOverlay();
      hideComposerPopupOverlay();
      showAttachmentPickerPopup = false;
      showEffectsPickerPopup = false;
      keepComposerKeyboardSpaceForPopup = false;

      if (showEmotePicker) {
        showEmotePicker = false;
        emotePickerActive = false;
      }

      if (!showEmotePicker) {
        keyboardAdaptorController.clearOverride?.call();
      }
    };

    if (!debounce) {
      removeHeightOverrideDebouncer.cancel();
      func();
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      emotePickerActive = false;
    });

    removeHeightOverrideDebouncer.run(func);
  }

  void showDesktopEmojiOverlay() {
    if (!Layout.desktop || entry != null) {
      return;
    }

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      return;
    }

    entry = OverlayEntry(
      builder: (overlayContext) {
        final mediaSize = MediaQuery.of(overlayContext).size;
        final width = math.min(430.0, math.max(320.0, mediaSize.width - 48));
        final height = math.min(390.0, math.max(280.0, mediaSize.height - 120));

        return Positioned.fill(
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    hideDesktopEmojiOverlay();
                    if (!mounted) {
                      return;
                    }
                    setState(() {
                      showEmotePicker = false;
                      emotePickerActive = false;
                    });
                  },
                ),
              ),
              CompositedTransformFollower(
                link: layerLink,
                showWhenUnlinked: false,
                targetAnchor: Alignment.topRight,
                followerAnchor: Alignment.bottomRight,
                offset: const Offset(0, -6),
                child: SizedBox(
                  width: width,
                  height: height,
                  child: desktopEmojiPickerSurface(),
                ),
              ),
            ],
          ),
        );
      },
    );

    overlay.insert(entry!);
  }

  void hideDesktopEmojiOverlay() {
    entry?.remove();
    entry = null;
  }

  bool get _showAttachmentPickerMenu =>
      showAttachmentPickerPopup &&
      widget.enabled &&
      widget.showAttachmentButton;

  bool get _showEffectsPickerMenu =>
      showEffectsPickerPopup && canShowEffectsMenu;

  bool get _showFloatingComposerPopup =>
      _showEffectsPickerMenu ||
      _showAttachmentPickerMenu ||
      _showCommandAutofill;

  Alignment get _composerPopupTargetAnchor =>
      _showEffectsPickerMenu ? Alignment.topRight : Alignment.topLeft;

  Alignment get _composerPopupFollowerAnchor =>
      _showEffectsPickerMenu ? Alignment.bottomRight : Alignment.bottomLeft;

  Offset get _composerPopupOffset {
    if (_showEffectsPickerMenu) {
      return Offset(-(Layout.desktop ? 52.0 : 8.0), -6);
    }

    if (_showCommandAutofill) {
      final inset = widget.showAttachmentButton
          ? widget.size + (Layout.desktop ? 28.0 : 16.0)
          : (Layout.desktop ? 20.0 : 12.0);
      return Offset(inset, -6);
    }

    return Offset(Layout.desktop ? 20.0 : 8.0, -6);
  }

  Widget composerPopupOverlayContent() {
    if (_showEffectsPickerMenu) {
      return effectsPickerPopup();
    }

    if (_showAttachmentPickerMenu) {
      return attachmentPickerPopup();
    }

    if (_showCommandAutofill) {
      return commandAutofillPopup();
    }

    return const SizedBox.shrink();
  }

  void syncComposerPopupOverlay() {
    if (!mounted) {
      return;
    }

    if (!_showFloatingComposerPopup) {
      hideComposerPopupOverlay();
      return;
    }

    if (composerPopupEntry == null) {
      showComposerPopupOverlay();
      return;
    }

    composerPopupEntry!.markNeedsBuild();
  }

  void showComposerPopupOverlay() {
    if (composerPopupEntry != null) {
      return;
    }

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) {
      return;
    }

    composerPopupEntry = OverlayEntry(
      builder: (overlayContext) {
        return Positioned.fill(
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: dismissFloatingComposerPopups,
                ),
              ),
              CompositedTransformFollower(
                link: composerPopupLayerLink,
                showWhenUnlinked: false,
                targetAnchor: _composerPopupTargetAnchor,
                followerAnchor: _composerPopupFollowerAnchor,
                offset: _composerPopupOffset,
                child: Material(
                  color: Colors.transparent,
                  child: composerPopupOverlayContent(),
                ),
              ),
            ],
          ),
        );
      },
    );

    overlay.insert(composerPopupEntry!);
  }

  void hideComposerPopupOverlay() {
    composerPopupEntry?.remove();
    composerPopupEntry = null;
  }

  void dismissFloatingComposerPopups() {
    if (!mounted) {
      return;
    }

    var shouldClearReservedHeight = false;
    setState(() {
      showAttachmentPickerPopup = false;
      showEffectsPickerPopup = false;
      shouldClearReservedHeight = keepComposerKeyboardSpaceForPopup;
      keepComposerKeyboardSpaceForPopup = false;
      autoFillResults = null;
      autoFillSelection = null;
      autoFillRange = null;
    });
    if (shouldClearReservedHeight && !showEmotePicker) {
      keyboardAdaptorController.clearOverride?.call();
    }
  }

  Widget desktopEmojiPickerSurface() {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(10);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: DesktopPanelEdgeHighlight(
          borderRadius: radius,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: radius,
            ),
            child: Material(
              color: Colors.transparent,
              child: buildEmojiPicker(skipIfNeverOpened: false),
            ),
          ),
        ),
      ),
    );
  }

  void dismissKeyboard({bool clearFocus = false}) {
    if (clearFocus) {
      FocusManager.instance.primaryFocus?.unfocus();
      textFocus.unfocus();
    }

    if (BuildConfig.ANDROID) {
      const platform = const MethodChannel('chat.intergalactic.app/utils');
      platform.invokeMethod("dismissKeyboard");
    } else {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  void resetMobileComposerDismissDrag() {
    mobileComposerDismissDragDistance = 0;
  }

  void onMobileComposerVerticalDragUpdate(DragUpdateDetails details) {
    if (!Layout.mobile) {
      return;
    }

    final keyboardOrPanelVisible =
        MediaQuery.of(context).viewInsets.bottom > 0 ||
        textFocus.hasFocus ||
        isPickerSearchFocused ||
        showEmotePicker ||
        showAttachmentPickerPopup ||
        showEffectsPickerPopup;
    if (!keyboardOrPanelVisible) {
      resetMobileComposerDismissDrag();
      return;
    }

    if (details.delta.dy <= 0) {
      resetMobileComposerDismissDrag();
      return;
    }

    mobileComposerDismissDragDistance += details.delta.dy;
    if (mobileComposerDismissDragDistance <
        mobileComposerDismissDragThreshold) {
      return;
    }

    dismissMobileComposerKeyboardAndPanels();
    resetMobileComposerDismissDrag();
  }

  void dismissMobileComposerKeyboardAndPanels() {
    if (showAttachmentPickerPopup ||
        showEffectsPickerPopup ||
        _showCommandAutofill) {
      setState(() {
        showAttachmentPickerPopup = false;
        showEffectsPickerPopup = false;
        keepComposerKeyboardSpaceForPopup = false;
        autoFillResults = null;
        autoFillSelection = null;
        autoFillRange = null;
      });
    }

    hideComposerPopupOverlay();

    if (showEmotePicker) {
      clearKeyboardOverride(debounce: false);
    }

    dismissKeyboard(clearFocus: true);
  }

  bool get isPickerSearchFocused =>
      emojiSearchFocus.hasFocus ||
      stickerSearchFocus.hasFocus ||
      gifSearchFocus.hasFocus;

  Future<bool> isKeyboardOpen() async {
    if (BuildConfig.ANDROID) {
      const platform = const MethodChannel('chat.intergalactic.app/utils');
      var result = await platform.invokeMethod<bool>("isKeyboardOpen");
      return result!;
    } else {
      var query = MediaQuery.of(context);
      return query.viewInsets.bottom > 0 ||
          textFocus.hasFocus ||
          isPickerSearchFocused;
    }
  }

  void onTextFocusChanged() {
    if (textFocus.hasFocus) {
      clearKeyboardOverride();
    }
  }

  void updateAutofillScroll() {
    if (!autofillScrollController.hasClients) {
      return;
    }
    if (autoFillSelection == null) {
      autofillScrollController.jumpTo(0);
      return;
    }

    int totalChars = 0;
    int selectionChars = 0;
    for (int i = 0; i < autoFillResults!.length; i++) {
      totalChars += autoFillResults![i].result.length;

      if (autoFillSelection! > i) {
        selectionChars += autoFillResults![i].result.length;
      }
    }

    var maxOffset = autofillScrollController.position.maxScrollExtent;

    var amount = selectionChars.toDouble() / totalChars.toDouble();
    var offset = (maxOffset * amount) - 50;

    if (offset < 0) {
      offset = 0;
    }

    var distance = (offset - autofillScrollController.offset).abs();
    var maxDistance =
        autofillScrollController.position.viewportDimension * 0.25;

    if (distance > maxDistance) {
      autofillScrollController.animateTo(
        offset,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOutExpo,
      );
    }
  }

  bool isKnownAutofillMatch(String text) {
    if (isRoomMentionText(text)) {
      return true;
    }

    if (text.startsWith('@[') && text.endsWith(']')) {
      return true;
    }

    if (text.startsWith("@") || text.startsWith("!")) {
      return text.isValidMatrixId;
    }

    if (text.startsWith(":") && text.endsWith(":")) {
      return true;
    } else {
      return false;
    }
  }

  TextSelection? prevSelection;

  void controllerListener() {
    if (PlatformUtils.isAndroid) {
      return;
    }

    if (preferences.disableTextCursorManagement.value) {
      return;
    }

    var startFill = getAutofillTextRange(
      cursorPosition: controller.selection.baseOffset,
    );

    var endFill = getAutofillTextRange(
      cursorPosition: controller.selection.extentOffset,
    );

    var len = controller.selection.start - controller.selection.end;

    var baseOffset = controller.selection.baseOffset;
    var extentOffset = controller.selection.extentOffset;

    if (baseOffset == -1 || extentOffset == -1) {
      return;
    }

    var text = controller.text.substring(startFill.$1, startFill.$2);
    var endText = controller.text.substring(endFill.$1, endFill.$2);
    if (isKnownAutofillMatch(text)) {
      // go forward
      if ((prevSelection != null &&
          prevSelection!.baseOffset < controller.selection.baseOffset)) {
        baseOffset = startFill.$2;
      } else {
        // go backward
        if (baseOffset > startFill.$1 && baseOffset != startFill.$2) {
          baseOffset = startFill.$1;
        }
      }
    }

    if (isKnownAutofillMatch(endText) && len != 0) {
      // go forward
      if ((prevSelection != null &&
          prevSelection!.extentOffset < controller.selection.extentOffset)) {
        extentOffset = endFill.$2;
      } else {
        // go backward
        if (extentOffset > endFill.$1) {
          extentOffset = endFill.$1;
        }
      }
    }

    if (len == 0) {
      extentOffset = baseOffset;
    }
    controller.selection = TextSelection(
      baseOffset: baseOffset,
      extentOffset: extentOffset,
    );

    prevSelection = controller.selection;
  }

  KeyEventResult onKey(FocusNode node, KeyEvent event) {
    if (BuildConfig.MOBILE || Layout.mobile) return KeyEventResult.ignored;

    if (!preferences.disableTextCursorManagement.value) {
      if (HardwareKeyboard.instance.isLogicalKeyPressed(
        LogicalKeyboardKey.backspace,
      )) {
        var selection = controller.selection.baseOffset;
        var selectionEnd = controller.selection.extentOffset;

        var range = getAutofillTextRange();

        if (range.$1 < selection) {
          selection = range.$1;
        }

        if (range.$2 > selectionEnd) {
          selectionEnd = range.$2;
        }

        var text = controller.text.substring(range.$1, range.$2);

        if (isKnownAutofillMatch(text)) {
          controller.text = controller.text.replaceRange(
            selection,
            selectionEnd,
            "",
          );
          onTextfieldUpdated(controller.text);
          return KeyEventResult.handled;
        }
      }
    }

    if (HardwareKeyboard.instance.isLogicalKeyPressed(
      LogicalKeyboardKey.keyV,
    )) {
      if (HardwareKeyboard.instance.isControlPressed) {
        readImageFromClipboard();
        return KeyEventResult.ignored;
      }
    }

    if (HardwareKeyboard.instance.isLogicalKeyPressed(LogicalKeyboardKey.tab)) {
      if (autoFillResults == null || autoFillResults!.isEmpty) {
        autoFillSelection = null;
        return KeyEventResult.ignored;
      } else {
        if (autoFillSelection == null) {
          setState(() {
            autoFillSelection = 0;
            updateAutofillScroll();
          });
        } else {
          setState(() {
            autoFillSelection = (autoFillSelection! + 1);
            if (autoFillSelection! >= autoFillResults!.length) {
              autoFillSelection = 0;
            }

            updateAutofillScroll();
          });
        }

        return KeyEventResult.handled;
      }
    }

    if (widget.disableEnterToSend != true) {
      if (HardwareKeyboard.instance.isLogicalKeyPressed(
        LogicalKeyboardKey.enter,
      )) {
        if (autoFillSelection != null && autoFillRange != null) {
          applyAutoFill(autoFillResults![autoFillSelection!]);
          return KeyEventResult.handled;
        }

        if (HardwareKeyboard.instance.isShiftPressed) {
          return KeyEventResult.ignored;
        }

        sendMessage();
        return KeyEventResult.handled;
      }
    }

    if (HardwareKeyboard.instance.isLogicalKeyPressed(
      LogicalKeyboardKey.escape,
    )) {
      doCancelInteraction();
      return KeyEventResult.handled;
    }

    if (HardwareKeyboard.instance.isLogicalKeyPressed(
          LogicalKeyboardKey.arrowUp,
        ) &&
        controller.text.isEmpty) {
      widget.editLastMessage?.call();
    }

    return KeyEventResult.ignored;
  }

  void applyAutoFill(AutofillSearchResult result) {
    var replacement = result.slug;

    var checkWhitespaceAt = autoFillRange!.$2;

    if (checkWhitespaceAt < controller.text.length) {
      if (controller.text[checkWhitespaceAt] != " ") {
        replacement = "$replacement ";
      }
    } else {
      replacement = "$replacement ";
    }

    final newText = controller.text.replaceRange(
      autoFillRange!.$1,
      autoFillRange!.$2,
      replacement,
    );
    setComposerValue(
      controller.value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(
          offset: autoFillRange!.$1 + replacement.length,
        ),
        composing: TextRange.empty,
      ),
    );
    setState(() {
      autoFillSelection = null;
      autoFillResults = null;
      autoFillRange = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMobileComposer = Layout.mobile;
    final isAndroidMobileComposer = isMobileComposer && PlatformUtils.isAndroid;
    final isIosMobileComposer = isMobileComposer && PlatformUtils.isIOS;
    final theme = Theme.of(context);
    final composerRadius = isMobileComposer
        ? (isAndroidMobileComposer ? 20.0 : (isIosMobileComposer ? 21.0 : 22.0))
        : 8.0;
    final showCommandPopup = _showCommandAutofill;
    final showInlineAutofill = autoFillResults != null && !showCommandPopup;
    final showBottomComposerRow =
        !widget.compact &&
        (!isMobileComposer ||
            senderOverride != null ||
            (showInlineAutofill && autoFillResults!.isNotEmpty));
    var padding = isMobileComposer
        ? EdgeInsets.fromLTRB(
            6,
            isAndroidMobileComposer ? 2 : (isIosMobileComposer ? 3 : 5),
            6,
            isAndroidMobileComposer ? 1 : (isIosMobileComposer ? 1 : 3),
          )
        : const EdgeInsets.fromLTRB(12, 6, 12, 0);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      notifyHeightChanged();
      syncComposerPopupOverlay();
    });

    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => notifyHeightChanged(),
        );
        return false;
      },
      child: SizeChangedLayoutNotifier(
        child: Material(
          color: Colors.transparent,
          child: TextFieldTapRegion(
            child: Opacity(
              opacity: widget.isProcessing ? 0.5 : 1,
              child: KeyboardAdaptor(
                enabled: widget.enableKeyboardAdapter,
                paddingContent: (Layout.mobile && showEmotePicker)
                    ? buildEmojiPicker()
                    : null,
                shouldPushContent: () {
                  if (emojiSearchFocus.hasFocus) {
                    return true;
                  }

                  if (stickerSearchFocus.hasFocus) {
                    return true;
                  }

                  if (gifSearchFocus.hasFocus) {
                    return true;
                  }

                  return false;
                },
                controller: keyboardAdaptorController,
                systemKeyboardGap: isMobileComposer ? 8 : 0,
                child: Column(
                  key: inputRootKey,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.typingIndicatorWidget != null)
                      widget.typingIndicatorWidget!,
                    if (widget.interactionType != null) interactionText(),
                    if (widget.attachments != null &&
                        widget.attachments!.isNotEmpty)
                      displayAttachments(),
                    CompositedTransformTarget(
                      link: composerPopupLayerLink,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        dragStartBehavior: DragStartBehavior.down,
                        onVerticalDragStart: isMobileComposer
                            ? (_) => resetMobileComposerDismissDrag()
                            : null,
                        onVerticalDragUpdate: isMobileComposer
                            ? onMobileComposerVerticalDragUpdate
                            : null,
                        onVerticalDragEnd: isMobileComposer
                            ? (_) => resetMobileComposerDismissDrag()
                            : null,
                        onVerticalDragCancel: isMobileComposer
                            ? resetMobileComposerDismissDrag
                            : null,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200),
                          child: Padding(
                            padding: padding,
                            child: isMobileComposer
                                ? composerControls(
                                    isMobileComposer: isMobileComposer,
                                    composerRadius: composerRadius,
                                    theme: theme,
                                  )
                                : desktopComposerFrame(
                                    child: composerControls(
                                      isMobileComposer: isMobileComposer,
                                      composerRadius: composerRadius,
                                      theme: theme,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    if (showBottomComposerRow)
                      SizedBox(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 2, 0, 0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const SizedBox(height: 30),
                              if (senderOverride != null) senderOverrideView(),
                              if (showInlineAutofill) autofillResultsList(),
                              if (!showInlineAutofill)
                                const Expanded(child: SizedBox()),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _useComposerBackdropBlur => Layout.mobile;

  Widget _composerBackdrop({required Widget child}) {
    if (!_useComposerBackdropBlur) {
      return child;
    }

    return BackdropFilter(
      filter: ImageFilter.blur(
        sigmaX: 22,
        sigmaY: 22,
        tileMode: TileMode.mirror,
      ),
      child: child,
    );
  }

  Widget composerControls({
    required bool isMobileComposer,
    required double composerRadius,
    required ThemeData theme,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.enabled && widget.showAttachmentButton)
          addAttachmentButton(),
        Flexible(
          child: MobileGlassEdgeHighlight(
            enabled: isMobileComposer,
            borderRadius: BorderRadius.circular(composerRadius),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(composerRadius),
                boxShadow: isMobileComposer
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(composerRadius),
                child: _composerBackdrop(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: isMobileComposer
                          ? theme.colorScheme.surface.withValues(alpha: 0.58)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(composerRadius),
                      gradient: isMobileComposer
                          ? LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                theme.colorScheme.surfaceContainerHigh
                                    .withValues(alpha: 0.3),
                                theme.colorScheme.surface.withValues(
                                  alpha: 0.56,
                                ),
                              ],
                            )
                          : null,
                      border: isMobileComposer
                          ? Border.all(
                              color: theme.colorScheme.outline.withValues(
                                alpha: 0.08,
                              ),
                            )
                          : null,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isRecordingVoiceMessage)
                          voiceRecordingIndicator(context)
                        else
                          textInput(context),
                        if (widget.enabled &&
                            canShowEffectsMenu &&
                            !isMobileComposer)
                          toggleEffectsButton(),
                        if (widget.enabled) toggleEmojiButton(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.enabled && Layout.mobile) sendMessageButton(),
      ],
    );
  }

  Widget desktopComposerFrame({required Widget child}) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(8);

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: DesktopPanelEdgeHighlight(
            borderRadius: radius,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: radius,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 3, 8, 3),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _showCommandAutofill {
    if (autoFillResults == null ||
        autoFillResults!.isEmpty ||
        autoFillRange == null) {
      return false;
    }

    final start = autoFillRange!.$1;
    return start >= 0 &&
        start < controller.text.length &&
        controller.text[start] == "/";
  }

  Widget commandAutofillPopup() {
    final results = autoFillResults;
    if (results == null || results.isEmpty) {
      return const SizedBox.shrink();
    }

    return composerPopupCard(
      preferredWidth: 288,
      maxHeight: 244,
      child: ComposerCommandMenuContent(
        results: results,
        selectedIndex: autoFillSelection,
        onSelected: applyAutoFill,
      ),
    );
  }

  Widget attachmentPickerPopup() {
    final pickers = buildAttachmentPickers();
    if (pickers.isEmpty) {
      return const SizedBox.shrink();
    }

    return composerPopupCard(
      preferredWidth: 244,
      maxHeight: 260,
      child: ComposerAttachmentMenuContent(
        pickers: pickers,
        onPickerSelected: (picker) =>
            unawaited(executeAttachmentPicker(picker)),
      ),
    );
  }

  Widget effectsPickerPopup() {
    return composerPopupCard(
      preferredWidth: 276,
      maxHeight: 244,
      child: ComposerEffectsMenuContent(onSelected: applyComposerEffect),
    );
  }

  Widget composerPopupCard({
    required double preferredWidth,
    required double maxHeight,
    required Widget child,
  }) {
    return ComposerPopupCard(
      preferredWidth: preferredWidth,
      maxHeight: maxHeight,
      safeHorizontalPadding: _composerPopupOffset.dx.abs() + 24,
      child: child,
    );
  }

  Widget senderOverrideView() {
    final profile = senderOverride?.self;
    if (profile == null) {
      return Container();
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        height: 30,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 2, 2),
          child: Material(
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.hardEdge,
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: InkWell(
              onTap: () {
                widget.onTapOverrideClient?.call(senderOverride!);
              },
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Row(
                  children: [
                    SizedBox(width: 5),
                    tiamat.Avatar(
                      radius: 10,
                      image: profile.avatar,
                      placeholderColor: profile.defaultColor,
                      placeholderText: profile.displayName,
                    ),
                    SizedBox(width: 10),
                    tiamat.Text.labelLow("Sending as: ${profile.displayName}"),
                    SizedBox(width: 5),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Expanded autofillResultsList() {
    return Expanded(
      child: ShaderMask(
        shaderCallback: (rect) {
          return const LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.center,
            colors: [Colors.purple, Colors.transparent],
            stops: [0.0, 0.1],
          ).createShader(rect);
        },
        blendMode: BlendMode.dstOut,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
          child: SizedBox(
            height: 30,
            child: Listener(
              onPointerSignal: (event) {
                if (!Layout.desktop) return;
                if (event is PointerScrollEvent) {
                  final offset = event.scrollDelta.dy;

                  autofillScrollController.jumpTo(
                    (autofillScrollController.offset + offset).clamp(
                      0,
                      autofillScrollController.position.maxScrollExtent,
                    ),
                  );
                }
              },
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(0, 0, 300, 0),
                itemCount: autoFillResults!.length,
                controller: autofillScrollController,
                shrinkWrap: true,
                itemBuilder: (context, index) {
                  bool selected = false;
                  var data = autoFillResults![index];
                  if (autoFillSelection != null) {
                    selected = data == autoFillResults![autoFillSelection!];
                  }

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Material(
                      color: selected
                          ? Theme.of(context).colorScheme.secondary
                          : Colors.transparent,
                      child: InkWell(
                        onTap: () => applyAutoFill(data),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(4, 1, 4, 1),
                          child: Row(
                            children: [
                              if (data is AutofillSearchResultEmoticon)
                                EmojiWidget(data.emoticon),
                              if (data is AutofillSearchResultAvatar)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    0,
                                    0,
                                    3,
                                    0,
                                  ),
                                  child: tiamat.Avatar(
                                    image: data.image,
                                    radius: 10,
                                    placeholderColor: data.fallbackColor,
                                    placeholderText: data.result,
                                  ),
                                ),
                              if (data is AutofillSearchResultRoomMention)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    0,
                                    0,
                                    3,
                                    0,
                                  ),
                                  child: Icon(
                                    Icons.campaign_outlined,
                                    size: 16,
                                    color: selected
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.onSecondary
                                        : Theme.of(
                                            context,
                                          ).colorScheme.secondary,
                                  ),
                                ),
                              tiamat.Text.labelLow(
                                data.result,
                                color: selected
                                    ? Theme.of(context).colorScheme.onSecondary
                                    : Theme.of(context).colorScheme.secondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get canShowEffectsMenu {
    if (widget.compact || widget.room == null) {
      return false;
    }

    return widget.onSendMessage != null;
  }

  Widget composerActionRegion({
    required String label,
    required VoidCallback? onActivate,
    required Widget child,
    String? hint,
    bool selected = false,
    BorderRadiusGeometry? borderRadius,
    String? persistentLabel,
    double persistentLabelMaxWidth = 96,
  }) {
    return AccessibleInteractiveRegion(
      semanticLabel: label,
      semanticHint: hint,
      selected: selected,
      onActivate: onActivate,
      borderRadius: borderRadius ?? BorderRadius.circular(widget.size / 2),
      minimumSize: widget.size,
      excludeChildSemantics: true,
      persistentLabel: persistentLabel,
      persistentLabelMaxWidth: persistentLabelMaxWidth,
      child: child,
    );
  }

  Widget composerActionSlot({
    required String label,
    required VoidCallback? onActivate,
    required Widget child,
    String? hint,
    bool selected = false,
    BorderRadiusGeometry? borderRadius,
    String? persistentLabel,
    double persistentLabelMaxWidth = 96,
  }) {
    final targetSize = composerActionTargetSize;
    final action = composerActionRegion(
      label: label,
      hint: hint,
      selected: selected,
      onActivate: onActivate,
      borderRadius: borderRadius,
      persistentLabel: persistentLabel,
      persistentLabelMaxWidth: persistentLabelMaxWidth,
      child: SizedBox(width: targetSize, height: targetSize, child: child),
    );

    if (AccessibilityScope.of(context).persistentActionLabels) {
      return ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: targetSize,
          minHeight: targetSize,
        ),
        child: action,
      );
    }

    return SizedBox(width: targetSize, height: targetSize, child: action);
  }

  double get composerActionTargetSize {
    final settings = AccessibilityScope.of(context);
    final tokens = AccessibilityScope.tokensOf(context);

    if (!settings.largerTouchTargets) {
      return widget.size;
    }

    return math.max(widget.size, tokens.minimumInteractiveDimension);
  }

  Widget sendMessageButton() {
    bool canSend =
        controller.text.isNotEmpty || widget.attachments?.isNotEmpty == true;
    final isAndroidMobileComposer = Layout.mobile && PlatformUtils.isAndroid;
    final isIosMobileComposer = Layout.mobile && PlatformUtils.isIOS;
    final showVoiceRecorder = canShowVoiceRecorder(canSend);

    double targetValue = (canSend || showVoiceRecorder) ? 1 : 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isAndroidMobileComposer ? 6 : (isIosMobileComposer ? 7 : 8),
        0,
        isAndroidMobileComposer ? 6 : (isIosMobileComposer ? 7 : 8),
        0,
      ),
      child: TweenAnimationBuilder(
        tween: Tween<double>(begin: 0, end: targetValue),
        duration: Durations.medium1,
        builder: (context, value, child) {
          if (!canSend && !showVoiceRecorder) {
            return SizedBox(width: widget.size, height: widget.size);
          }

          Widget button = tiamat.CircleButton(
            icon: showVoiceRecorder
                ? (isRecordingVoiceMessage
                      ? Icons.stop_rounded
                      : Icons.mic_rounded)
                : Icons.send,
            radius: widget.size * widget.iconScale,
            onPressed: () {
              if (showVoiceRecorder) {
                toggleVoiceRecording();
              } else {
                sendMessage();
              }
            },
            color: Color.lerp(
              Theme.of(context).colorScheme.primary.withAlpha(0),
              showVoiceRecorder && isRecordingVoiceMessage
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
              value,
            ),
            iconColor: Color.lerp(
              Theme.of(context).colorScheme.secondary,
              Theme.of(context).colorScheme.onPrimary,
              value,
            ),
          );

          if (canShowEffectsMenu && !isRecordingVoiceMessage) {
            button = GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: onEffectsButtonPressed,
              child: button,
            );
          }

          final actionLabel = showVoiceRecorder
              ? (isRecordingVoiceMessage
                    ? "Stop voice recording"
                    : "Record voice message")
              : "Send message";
          final actionHint = showVoiceRecorder
              ? (isRecordingVoiceMessage
                    ? "Stop recording and attach the voice message"
                    : "Start recording a voice message")
              : "Send the current message";
          final result = Focus(
            canRequestFocus: false,
            descendantsAreFocusable: false,
            child: ClipRRect(
              borderRadius: BorderRadiusGeometry.circular(widget.size),
              child: MobileGlassEdgeHighlight(
                enabled: Layout.mobile,
                highlighted: canSend,
                style: MobileGlassHighlightStyle.composer,
                borderRadius: BorderRadius.circular(widget.size),
                child: Material(
                  color: Colors.transparent,
                  child: SizedBox(
                    width: widget.size,
                    height: widget.size,
                    child: button,
                  ),
                ),
              ),
            ),
          );

          return composerActionSlot(
            label: actionLabel,
            hint: actionHint,
            selected: showVoiceRecorder && isRecordingVoiceMessage,
            onActivate: showVoiceRecorder ? toggleVoiceRecording : sendMessage,
            borderRadius: BorderRadius.circular(widget.size),
            persistentLabel: showVoiceRecorder
                ? (isRecordingVoiceMessage ? "Stop" : "Voice")
                : "Send",
            persistentLabelMaxWidth: 72,
            child: result,
          );
        },
      ),
    );
  }

  bool canShowVoiceRecorder(bool canSend) {
    if (canSend && !isRecordingVoiceMessage) {
      return false;
    }

    return Layout.mobile &&
        VoiceRecorderBridge.isSupported &&
        widget.addAttachment != null;
  }

  Future<void> toggleVoiceRecording() async {
    if (voiceRecordingBusy) {
      return;
    }

    setState(() {
      voiceRecordingBusy = true;
    });

    try {
      if (isRecordingVoiceMessage) {
        final attachment = await VoiceRecorderBridge.stopRecording();
        if (!mounted) {
          return;
        }

        setState(() {
          isRecordingVoiceMessage = false;
        });
        stopVoiceRecordingTicker();

        if (attachment != null) {
          widget.addAttachment?.call(attachment);
        } else {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text("Voice recording could not be saved."),
            ),
          );
        }
      } else {
        await VoiceRecorderBridge.startRecording();
        if (!mounted) {
          unawaited(_cancelVoiceRecordingDuringDispose());
          return;
        }

        setState(() {
          isRecordingVoiceMessage = true;
          voiceRecordingStartedAt = DateTime.now();
          voiceRecordingDuration = Duration.zero;
        });
        startVoiceRecordingTicker();
      }
    } on PlatformException catch (error, stackTrace) {
      Log.onError(error, stackTrace, content: "Voice recording failed");
      await _cancelVoiceRecording("after failure");
      if (!mounted) {
        return;
      }

      setState(() {
        isRecordingVoiceMessage = false;
      });
      stopVoiceRecordingTicker();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(voiceRecordingErrorMessage(error))),
      );
    } catch (error, stackTrace) {
      Log.onError(error, stackTrace, content: "Voice recording failed");
      await _cancelVoiceRecording("after failure");
      if (!mounted) {
        return;
      }

      setState(() {
        isRecordingVoiceMessage = false;
      });
      stopVoiceRecordingTicker();
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text("Voice recording failed.")));
    } finally {
      if (mounted) {
        setState(() {
          voiceRecordingBusy = false;
        });
      }
    }
  }

  void startVoiceRecordingTicker() {
    voiceRecordingTicker?.cancel();
    voiceRecordingTicker = Timer.periodic(const Duration(milliseconds: 250), (
      _,
    ) {
      final startedAt = voiceRecordingStartedAt;
      if (!mounted || startedAt == null) {
        return;
      }

      setState(() {
        voiceRecordingDuration = DateTime.now().difference(startedAt);
      });
    });
  }

  void stopVoiceRecordingTicker() {
    voiceRecordingTicker?.cancel();
    voiceRecordingTicker = null;
    voiceRecordingStartedAt = null;
    voiceRecordingDuration = Duration.zero;
  }

  String get voiceRecordingDurationLabel {
    final minutes = voiceRecordingDuration.inMinutes;
    final seconds = voiceRecordingDuration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String voiceRecordingErrorMessage(PlatformException error) {
    if (error.code == 'microphone_permission_denied') {
      return 'Microphone access is needed to record voice messages.';
    }

    return error.message ?? 'Voice recording failed.';
  }

  Widget toggleEmojiButton() {
    final pickerActive = emotePickerActive == true;
    Widget button = composerActionSlot(
      label: pickerActive ? "Close emoji picker" : "Open emoji picker",
      hint: "Choose emoji, stickers, or GIFs",
      selected: pickerActive,
      onActivate: toggleEmojiOverlay,
      persistentLabel: "Emoji",
      persistentLabelMaxWidth: 72,
      child: RandomEmojiButton(
        size: widget.size,
        onTap: toggleEmojiOverlay,
        toggled: pickerActive,
      ),
    );

    button = TutorialAnchor(
      id: TutorialAnchorIds.composerEmojiButton,
      padding: const EdgeInsets.all(2),
      child: CompositedTransformTarget(link: layerLink, child: button),
    );

    if (Layout.mobile) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          2,
          0,
          PlatformUtils.isAndroid ? 4 : (PlatformUtils.isIOS ? 5 : 6),
          0,
        ),
        child: button,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
      child: button,
    );
  }

  Widget toggleEffectsButton() {
    final toggled = showEffectsPickerPopup;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 2, 0),
      child: TutorialAnchor(
        id: TutorialAnchorIds.composerEffectsButton,
        padding: const EdgeInsets.all(2),
        child: Tooltip(
          message: "Effects",
          child: composerActionSlot(
            label: toggled ? "Close message effects" : "Open message effects",
            hint: "Choose a message effect",
            selected: toggled,
            onActivate: onEffectsButtonPressed,
            borderRadius: BorderRadius.circular(8),
            persistentLabel: "Effects",
            persistentLabelMaxWidth: 82,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Material(
                color: toggled
                    ? scheme.outline.withValues(alpha: 0.14)
                    : Colors.transparent,
                child: tiamat.IconButton(
                  icon: Icons.auto_awesome_rounded,
                  size: widget.size * widget.iconScale,
                  onPressed: onEffectsButtonPressed,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Expanded voiceRecordingIndicator(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tick = voiceRecordingDuration.inMilliseconds ~/ 180;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        child: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: scheme.error,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: scheme.error.withValues(alpha: 0.38),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 9),
            Text(
              voiceRecordingDurationLabel,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: scheme.error,
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 22,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (var i = 0; i < 18; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        width: 3,
                        height: (6 + (((tick + i * 3) % 5) * 3)).toDouble(),
                        decoration: BoxDecoration(
                          color: scheme.error.withValues(
                            alpha: 0.34 + ((i % 3) * 0.08),
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              "Tap stop",
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Expanded textInput(BuildContext context) {
    var height = Theme.of(context).textTheme.bodyMedium!.fontSize!;
    final isMobileComposer = Layout.mobile;
    final isAndroidMobileComposer = isMobileComposer && PlatformUtils.isAndroid;
    final isIosMobileComposer = isMobileComposer && PlatformUtils.isIOS;
    var inputStyle = Theme.of(context).textTheme.bodyMedium!;
    height = inputStyle.fontSize ?? height;
    var padding = widget.size - height;
    var hintStyle = inputStyle;
    hintStyle = hintStyle.copyWith(color: hintStyle.color?.withAlpha(156));
    return Expanded(
      child: Stack(
        children: [
          TapRegion(
            onTapInside: (event) => onTextFocusChanged(),
            child: TextField(
              focusNode: textFocus,
              onChanged: onTextfieldUpdated,
              controller: controller,
              inputFormatters: preferences.composerBracketTyping.value
                  ? const [ComposerBracketInputFormatter()]
                  : null,
              readOnly: !widget.enabled || widget.isProcessing,
              textAlignVertical: TextAlignVertical.center,
              style: inputStyle,
              minLines: 1,
              maxLines: null,
              contextMenuBuilder: contextMenuBuilder,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                contentPadding: EdgeInsets.fromLTRB(
                  isMobileComposer ? 14 : 8,
                  isMobileComposer
                      ? (isAndroidMobileComposer
                            ? 6
                            : (isIosMobileComposer ? 7 : 8))
                      : padding / 2,
                  isMobileComposer
                      ? (isAndroidMobileComposer
                            ? 6
                            : (isIosMobileComposer ? 7 : 8))
                      : 4,
                  isMobileComposer
                      ? (isAndroidMobileComposer
                            ? 6
                            : (isIosMobileComposer ? 7 : 8))
                      : padding / 2,
                ),
                hintMaxLines: isMobileComposer ? 1 : null,
                border: InputBorder.none,
                isDense: true,
                hintStyle: hintStyle,
                hintText: widget.hintText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Padding addAttachmentButton() {
    final isMobileComposer = Layout.mobile;
    final isAndroidMobileComposer = isMobileComposer && PlatformUtils.isAndroid;
    final isIosMobileComposer = isMobileComposer && PlatformUtils.isIOS;
    final theme = Theme.of(context);
    final targetSize = composerActionTargetSize;
    final radius = BorderRadius.circular(isMobileComposer ? targetSize / 2 : 8);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        isMobileComposer ? 2 : 4,
        0,
        isMobileComposer
            ? (isAndroidMobileComposer ? 4 : (isIosMobileComposer ? 5 : 6))
            : 4,
        0,
      ),
      child: TutorialAnchor(
        id: TutorialAnchorIds.composerPlusButton,
        padding: const EdgeInsets.all(2),
        child: composerActionSlot(
          label: showAttachmentPickerPopup
              ? "Close attachment menu"
              : "Add attachment",
          hint: "Choose camera, file, poll, or photo options",
          selected: showAttachmentPickerPopup,
          onActivate: onAttachmentButtonPressed,
          borderRadius: radius,
          persistentLabel: "Attach",
          persistentLabelMaxWidth: 74,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isMobileComposer
                  ? theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.7)
                  : Colors.transparent,
              borderRadius: radius,
              border: isMobileComposer
                  ? Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.12),
                    )
                  : null,
            ),
            child: MobileGlassEdgeHighlight(
              enabled: isMobileComposer,
              borderRadius: radius,
              child: ClipRRect(
                borderRadius: radius,
                child: tiamat.IconButton(
                  icon: Icons.add,
                  size: widget.size * widget.iconScale,
                  onPressed: onAttachmentButtonPressed,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double get emotePickerHeight =>
      (MediaQuery.of(context).size.height / (Layout.mobile ? 2.5 : 3)) /
      preferences.appScale.value;

  Widget buildEmojiPicker({bool skipIfNeverOpened = true}) {
    var recent = widget.client
        .getComponent<RecentEmoticonComponent>()
        ?.getRecentTypedEmoticon(widget.room);

    var availableEmoji = widget.availibleEmoticons!.toList();

    if (recent != null && recent.isNotEmpty) {
      availableEmoji.insert(
        0,
        DynamicEmoticonPack(
          identifier: "dynamic_pack_frequently_used_typing",
          displayName: "Frequently Used",
          icon: Icons.schedule,
          emoticons: recent,
          usage: EmoticonUsage.all,
        ),
      );
    }

    return (!hasEmotePickerOpened && skipIfNeverOpened)
        ? Container()
        : MobileGlassEdgeHighlight(
            enabled: Layout.mobile,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(MobileVisuals.panelRadius),
            ),
            child: Container(
              decoration: Layout.mobile
                  ? BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surface.withValues(alpha: 0.84),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(MobileVisuals.panelRadius),
                      ),
                      border: Border(
                        top: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.05),
                        ),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 14,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    )
                  : null,
              child: ClipRRect(
                borderRadius: Layout.mobile
                    ? const BorderRadius.vertical(
                        top: Radius.circular(MobileVisuals.panelRadius),
                      )
                    : BorderRadius.zero,
                child: EmoticonPicker(
                  emoji: availableEmoji,
                  emojiSearchFocus: emojiSearchFocus,
                  stickerSearchFocus: stickerSearchFocus,
                  gifSearchFocus: gifSearchFocus,
                  searchDelegate: (search) => AutofillUtils.searchEmoticon(
                    search,
                    client: widget.client,
                    room: widget.room,
                    limit: 50,
                  ).whereType<AutofillSearchResultEmoticon>().toList(),
                  stickers: widget.sendSticker == null
                      ? const []
                      : (widget.availibleStickers ?? []),
                  onEmojiPressed: insertEmoticon,
                  mobileStyle: Layout.mobile,
                  packListAxis: Layout.desktop
                      ? Axis.vertical
                      : Axis.horizontal,
                  allowGifSearch:
                      widget.sendGif != null &&
                      widget.showGifSearch &&
                      preferences.gifSearchEnabled.value &&
                      GifApiKeyStore.hasSearchProvider,
                  gifComponent: widget.gifComponent,
                  onCreatePressed: canOpenRoomEmojiSettings
                      ? openRoomEmojiSettings
                      : null,
                  onStickerPressed: (emoticon) {
                    final sendSticker = widget.sendSticker;
                    if (sendSticker == null) {
                      return;
                    }
                    try {
                      sendSticker(emoticon);
                    } catch (error, stackTrace) {
                      Log.onError(
                        error,
                        stackTrace,
                        content: "Failed to send sticker",
                      );
                      if (!mounted) {
                        return;
                      }
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(content: Text("Failed to send sticker")),
                      );
                      return;
                    }
                    if (!mounted) {
                      return;
                    }
                    clearKeyboardOverride(debounce: false);
                  },
                  onGifPressed: (gif) async {
                    final sendGif = widget.sendGif;
                    if (sendGif == null) {
                      return;
                    }
                    try {
                      await sendGif(gif);
                      if (!mounted) return;
                      clearKeyboardOverride(debounce: false);
                    } catch (error, stackTrace) {
                      Log.onError(
                        error,
                        stackTrace,
                        content: "Failed to send GIF",
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(content: Text("Failed to send GIF")),
                      );
                    }
                  },
                ),
              ),
            ),
          );
  }

  bool get canOpenRoomEmojiSettings {
    final room = widget.room;
    if (!Layout.desktop || room == null) {
      return false;
    }

    return room.permissions.canEditRoomEmoticons;
  }

  Future<void> openRoomEmojiSettings() async {
    final room = widget.room;
    if (room == null) {
      return;
    }

    hideDesktopEmojiOverlay();
    if (mounted) {
      setState(() {
        showEmotePicker = false;
        emotePickerActive = false;
      });
    }

    await SettingsNavigation.show(
      context,
      RoomSettingsPage(
        room: room,
        initialTabId: SettingsCategoryRoom.tabIdEmoticons,
      ),
    );
  }

  Future<void> handlePickedAttachment(PendingFileAttachment attachment) async {
    if (mounted) {
      var processedFile = await AdaptiveDialog.show<PendingFileAttachment>(
        scrollable: false,
        context,
        builder: (context) {
          return AttachmentProcessor(attachment: attachment);
        },
      );

      if (processedFile != null) {
        widget.addAttachment?.call(processedFile);
      }
    }
  }

  Future<void> createPoll(PollComponent pollComponent) async {
    final initialRoom = widget.room;
    if (initialRoom == null) {
      return;
    }

    final createArgs = await AdaptiveDialog.show<PollCreateArgs>(
      context,
      title: "Create Poll",
      builder: (context) => PollCreator(),
    );

    if (!mounted || createArgs == null) {
      return;
    }

    try {
      await pollComponent.createPoll(initialRoom, createArgs);
    } catch (error, stackTrace) {
      Log.onError(error, stackTrace, content: "Failed to create poll");
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text("Failed to create poll.")));
    }
  }

  void onAttachmentButtonPressed() {
    var shouldDismissKeyboard = false;
    var shouldClearReservedHeight = false;
    final keyboardVisible =
        (MediaQuery.maybeOf(context)?.viewInsets.bottom ?? 0.0) > 0;

    setState(() {
      final shouldOpen = !showAttachmentPickerPopup;
      final isMobilePlatformComposer =
          (PlatformUtils.isAndroid || PlatformUtils.isIOS) && Layout.mobile;
      final shouldKeepEmojiPickerOpen =
          isMobilePlatformComposer && shouldOpen && showEmotePicker;
      final shouldKeepSystemKeyboardOpen =
          isMobilePlatformComposer &&
          shouldOpen &&
          (keyboardVisible || textFocus.hasFocus);
      final shouldRetainMobilePickerSpace =
          shouldRetainMobilePickerSpaceForAttachmentMenu(
            isAndroid: PlatformUtils.isAndroid,
            isIOS: PlatformUtils.isIOS,
            isMobile: Layout.mobile,
            shouldOpen: shouldOpen,
            showEmotePicker: showEmotePicker,
            isPickerSearchFocused: isPickerSearchFocused,
          );
      if (shouldRetainMobilePickerSpace) {
        keyboardAdaptorController.keepCurrentSize?.call();
      }

      showAttachmentPickerPopup = shouldOpen;
      keepComposerKeyboardSpaceForPopup = shouldRetainMobilePickerSpace;
      if (showAttachmentPickerPopup) {
        hideDesktopEmojiOverlay();
        if (!shouldKeepEmojiPickerOpen) {
          showEmotePicker = false;
          emotePickerActive = false;
        }
        showEffectsPickerPopup = false;
        shouldDismissKeyboard =
            !shouldKeepEmojiPickerOpen && !shouldKeepSystemKeyboardOpen;
      } else {
        keepComposerKeyboardSpaceForPopup = false;
        shouldClearReservedHeight = !showEmotePicker;
      }
    });

    if (shouldDismissKeyboard) {
      dismissKeyboard();
    }
    if (shouldClearReservedHeight) {
      keyboardAdaptorController.clearOverride?.call();
    }
  }

  void onEffectsButtonPressed() {
    if (!canShowEffectsMenu) {
      return;
    }

    var shouldDismissKeyboard = false;
    var shouldClearReservedHeight = false;

    setState(() {
      final shouldOpen = !showEffectsPickerPopup;
      final shouldRetainMobileKeyboardSpace =
          PlatformUtils.isIOS &&
          Layout.mobile &&
          shouldOpen &&
          (showEmotePicker || textFocus.hasFocus || isPickerSearchFocused);
      if (shouldRetainMobileKeyboardSpace) {
        keyboardAdaptorController.keepCurrentSize?.call();
      }

      showEffectsPickerPopup = shouldOpen;
      keepComposerKeyboardSpaceForPopup = shouldRetainMobileKeyboardSpace;
      if (showEffectsPickerPopup) {
        hideDesktopEmojiOverlay();
        showEmotePicker = false;
        emotePickerActive = false;
        showAttachmentPickerPopup = false;
        shouldDismissKeyboard = true;
      } else {
        keepComposerKeyboardSpaceForPopup = false;
        shouldClearReservedHeight = true;
      }
    });

    if (shouldDismissKeyboard) {
      dismissKeyboard();
    }
    if (shouldClearReservedHeight) {
      keyboardAdaptorController.clearOverride?.call();
    }
  }

  void applyComposerEffect(ComposerEffectOption effect) {
    if (mounted && showEffectsPickerPopup) {
      setState(() {
        showEffectsPickerPopup = false;
      });
    }

    final sendText = composerEffectSendText(effect, controller.text);
    if (sendText != null) {
      sendEffectText(sendText);
      return;
    }

    final draft = composerEffectDraftValue(effect);
    if (draft == null) {
      return;
    }

    setComposerValue(draft);
    textFocus.requestFocus();
  }

  void sendEffectText(String message) {
    if (widget.isProcessing) {
      return;
    }

    final result = widget.onSendMessage?.call(
      message,
      overrideClient: senderOverride,
    );
    if (result == MessageInputSendResult.success) {
      setComposerValue(TextEditingValue.empty);
    }
  }

  Future<ComposerCameraCaptureKind?> _showCameraCaptureChoiceSheet() {
    return showModalBottomSheet<ComposerCameraCaptureKind>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      builder: (context) => const ComposerCameraCaptureSheet(),
    );
  }

  Future<void> _dispatchCameraAttachment(
    Future<PendingFileAttachment?> Function() pick,
  ) async {
    final attachment = await pick();
    if (!mounted || attachment == null) {
      return;
    }
    await handlePickedAttachment(attachment);
  }

  Future<void> captureCameraAttachment() async {
    if (composerShowsCameraCaptureChoiceBeforeNativePicker(
      isAndroid: PlatformUtils.isAndroid,
      isIOS: PlatformUtils.isIOS,
    )) {
      final kind = await _showCameraCaptureChoiceSheet();
      if (!mounted || kind == null) {
        return;
      }

      return _dispatchCameraAttachment(
        () => pickComposerAndroidCameraAttachment(
          kind: kind,
          includePath: !PlatformUtils.isWeb,
        ),
      );
    }

    if (composerUsesNativeCameraPicker(
      isAndroid: PlatformUtils.isAndroid,
      isIOS: PlatformUtils.isIOS,
    )) {
      return _dispatchCameraAttachment(
        () =>
            pickComposerIosCameraAttachment(includePath: !PlatformUtils.isWeb),
      );
    }

    final kind = await _showCameraCaptureChoiceSheet();
    if (!mounted || kind == null) {
      return;
    }

    return _dispatchCameraAttachment(
      () => pickComposerCameraAttachment(
        picker: ImagePicker(),
        kind: kind,
        includePath: !PlatformUtils.isWeb,
      ),
    );
  }

  List<AttachmentPicker> buildAttachmentPickers() {
    final pollComponent = widget.room?.client.getComponent<PollComponent>();
    final supportsMobileMedia = PlatformUtils.isAndroid || PlatformUtils.isIOS;

    return [
      if (supportsMobileMedia)
        AttachmentPicker(
          icon: Icons.camera_alt_rounded,
          label: composerMobileCameraAttachmentLabel,
          execute: captureCameraAttachment,
        ),
      if (supportsMobileMedia)
        AttachmentPicker(
          icon: Icons.photo_library_rounded,
          label: "Gallery",
          execute: () async {
            var picker = ImagePicker();
            var result = await picker.pickMultipleMedia();
            for (var file in result) {
              var data = await file.readAsBytes();
              await handlePickedAttachment(
                PendingFileAttachment(
                  name: file.name,
                  path: PlatformUtils.isWeb ? null : file.path,
                  mimeType: file.mimeType,
                  size: data.lengthInBytes,
                  data: data,
                ),
              );
            }
          },
        ),
      AttachmentPicker(
        icon: Icons.attach_file,
        label: "File",
        execute: () async {
          FilePickerResult? result = await FilePicker.platform.pickFiles(
            type: FileType.any,
            withData: true,
            allowMultiple: true,
          );
          if (result == null) return;

          for (var file in result.files) {
            var attachment = PendingFileAttachment(
              name: file.name,
              path: PlatformUtils.isWeb ? null : file.path,
              data: file.bytes,
              size: file.bytes?.length,
            );

            await handlePickedAttachment(attachment);
          }
        },
      ),
      if (pollComponent != null)
        AttachmentPicker(
          icon: Icons.poll,
          label: "Poll",
          execute: () async {
            await createPoll(pollComponent);
          },
        ),
    ];
  }

  Future<void> executeAttachmentPicker(AttachmentPicker picker) async {
    var shouldClearReservedHeight = false;
    if (mounted && showAttachmentPickerPopup) {
      setState(() {
        showAttachmentPickerPopup = false;
        shouldClearReservedHeight = keepComposerKeyboardSpaceForPopup;
        keepComposerKeyboardSpaceForPopup = false;
      });
      if (shouldClearReservedHeight && !showEmotePicker) {
        keyboardAdaptorController.clearOverride?.call();
      }
    }

    try {
      await Future.sync(picker.execute);
    } on PlatformException catch (error, stackTrace) {
      Log.onError(error, stackTrace, content: "Attachment picker failed");
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(error.message ?? "Attachment picker failed.")),
      );
    } on Exception catch (error, stackTrace) {
      Log.onError(error, stackTrace, content: "Attachment picker failed");
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> addAttachment() async {
    final pickers = buildAttachmentPickers();

    if (pickers.length == 1) {
      await executeAttachmentPicker(pickers.first);
    } else {
      final picker = await AdaptiveDialog.pickOne(
        context,
        items: pickers,
        itemBuilder: (context, item, onTapped) => SizedBox(
          height: 50,
          child: tiamat.TextButton(
            item.label,
            icon: item.icon,
            onTap: onTapped,
          ),
        ),
      );

      if (picker != null) {
        await executeAttachmentPicker(picker);
      }
    }
  }

  void doCancelInteraction() {
    if (widget.interactionType == EventInteractionType.edit) {
      controller.clear();
    }

    widget.cancelReply?.call();
  }

  void insertEmoticon(Emoticon emote) {
    if (widget.room != null) {
      var recents = widget.client.getComponent<RecentEmoticonComponent>();
      recents?.typedEmoticon(widget.room!, emote);
    }

    setComposerValue(insertEmoticonIntoComposerValue(controller.value, emote));
  }

  Widget interactionText() {
    final cancelLabel = widget.interactionType == EventInteractionType.reply
        ? "Cancel reply"
        : widget.interactionType == EventInteractionType.edit
        ? "Cancel edit"
        : "Cancel message action";

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 0, 4),
      child: SizedBox(
        height: 24,
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Semantics(
                label: cancelLabel,
                button: true,
                onTap: doCancelInteraction,
                excludeSemantics: true,
                child: Tooltip(
                  message: cancelLabel,
                  child: tiamat.IconButton(
                    icon: Icons.cancel_outlined,
                    size: 16,
                    onPressed: doCancelInteraction,
                  ),
                ),
              ),
            ),
            Icon(
              widget.interactionType == EventInteractionType.reply
                  ? Icons.keyboard_arrow_right_rounded
                  : widget.interactionType == EventInteractionType.edit
                  ? Icons.edit
                  : null,
            ),
            tiamat.Text.name(
              widget.relatedEventSenderName!,
              color: widget.relatedEventSenderColor,
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
                child: tiamat.Text(
                  widget.relatedEventBody ?? "Unknown",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget displayAttachments() {
    return SizedBox(
      child: Row(
        children: widget.attachments!.map((e) {
          return Padding(
            padding: const EdgeInsets.all(2.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: GestureDetector(
                onTap: () {},
                child: SizedBox(
                  height: 40,
                  width: 40,
                  child: AttachmentIcon(
                    e,
                    removeAttachment: () => widget.removeAttachment?.call(e),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget contextMenuBuilder(
    BuildContext buildContext,
    EditableTextState editableTextState,
  ) {
    final sel = editableTextState.textEditingValue.selection;
    final hasSelection = sel.start != sel.end;

    // Build the standard Cut/Copy/Paste/Select All buttons, but override
    // onPaste to preserve the existing paste-from-clipboard/image logic.
    final standardItems = editableTextState.contextMenuButtonItems.map((item) {
      if (item.type == ContextMenuButtonType.paste) {
        return item.copyWith(
          onPressed: () async {
            var clipboard = await Clipboard.getData("text/plain");
            if (clipboard != null) {
              return editableTextState.pasteText(SelectionChangedCause.toolbar);
            }
            editableTextState.hideToolbar();
            if (BuildConfig.DESKTOP) {
              await readImageFromClipboard();
            }
          },
        );
      }
      return item;
    }).toList();

    return MarkdownSelectionToolbar(
      anchors: editableTextState.contextMenuAnchors,
      formattingActions: hasSelection
          ? [
              _buildFormattingAction(
                Icons.format_bold_rounded,
                "Bold",
                () => _wrapSelection('**'),
              ),
              _buildFormattingAction(
                Icons.format_italic_rounded,
                "Italic",
                () => _wrapSelection('*'),
              ),
              _buildFormattingAction(
                Icons.format_strikethrough_rounded,
                "Strikethrough",
                () => _wrapSelection('~~'),
              ),
              _buildFormattingAction(
                Icons.format_quote_rounded,
                "Quote",
                _quoteSelection,
              ),
              _buildFormattingAction(
                Icons.code_rounded,
                "Code",
                () => _wrapSelection('`'),
              ),
              _buildFormattingAction(
                Icons.visibility_off_rounded,
                "Spoiler",
                () => _wrapSelection('||'),
              ),
            ]
          : const [],
      standardActions: standardItems
          .where((item) => item.onPressed != null)
          .map(
            (item) => MarkdownSelectionToolbarAction(
              icon: _contextMenuIcon(item.type),
              label: AdaptiveTextSelectionToolbar.getButtonLabel(
                buildContext,
                item,
              ),
              onPressed: () {
                item.onPressed?.call();
                ContextMenuController.removeAny();
              },
            ),
          )
          .toList(),
    );
  }

  MarkdownSelectionToolbarAction _buildFormattingAction(
    IconData icon,
    String label,
    VoidCallback onPressed,
  ) {
    return MarkdownSelectionToolbarAction(
      icon: icon,
      label: label,
      onPressed: () {
        onPressed();
        ContextMenuController.removeAny();
      },
    );
  }

  void _wrapSelection(String marker, {String? suffix}) {
    final selection = controller.selection;
    if (selection.start == selection.end) {
      return;
    }

    final selected = controller.text.substring(selection.start, selection.end);
    final endMarker = suffix ?? marker;
    final wrapped = '$marker$selected$endMarker';
    _replaceSelection(selection, wrapped);
  }

  void _quoteSelection() {
    final selection = controller.selection;
    if (selection.start == selection.end) {
      return;
    }

    final selected = controller.text.substring(selection.start, selection.end);
    final quoted = selected
        .split('\n')
        .map((line) => line.isEmpty ? '>' : '> $line')
        .join('\n');
    _replaceSelection(selection, quoted);
  }

  void _replaceSelection(TextSelection selection, String replacement) {
    controller.text = controller.text.replaceRange(
      selection.start,
      selection.end,
      replacement,
    );
    controller.selection = TextSelection.collapsed(
      offset: selection.start + replacement.length,
    );
  }

  IconData _contextMenuIcon(ContextMenuButtonType type) {
    return switch (type) {
      ContextMenuButtonType.cut => Icons.content_cut_rounded,
      ContextMenuButtonType.copy => Icons.copy_rounded,
      ContextMenuButtonType.paste => Icons.content_paste_rounded,
      ContextMenuButtonType.selectAll => Icons.select_all_rounded,
      ContextMenuButtonType.delete => Icons.delete_outline_rounded,
      ContextMenuButtonType.lookUp => Icons.info_outline_rounded,
      ContextMenuButtonType.searchWeb => Icons.travel_explore_rounded,
      ContextMenuButtonType.share => Icons.share_rounded,
      ContextMenuButtonType.liveTextInput => Icons.document_scanner_outlined,
      ContextMenuButtonType.custom => Icons.more_horiz_rounded,
    };
  }

  Future<void> readImageFromClipboard() async {
    var image = await Pasteboard.image;
    if (image == null) {
      return;
    }

    var processedAttachment = await AdaptiveDialog.show<PendingFileAttachment>(
      context,
      scrollable: false,
      builder: (context) => AttachmentProcessor(
        attachment: PendingFileAttachment(data: image, size: image.length),
      ),
    );

    if (processedAttachment != null) {
      setState(() {
        widget.addAttachment?.call(processedAttachment);
      });
    }
  }

  void onPopped(ScopePopped event) {
    if (event.handled) {
      return;
    }

    if (event.currentMobileSide == RevealSide.left) {
      return;
    }

    if (showEmotePicker ||
        showAttachmentPickerPopup ||
        showEffectsPickerPopup ||
        _showCommandAutofill) {
      dismissMobileComposerKeyboardAndPanels();
      event.handled = true;
    }
  }
}

class DesktopPanelEdgeHighlight extends StatelessWidget {
  const DesktopPanelEdgeHighlight({
    super.key,
    required this.borderRadius,
    required this.child,
  });

  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _DesktopPanelEdgeHighlightPainter(
                borderRadius: borderRadius,
                outline: scheme.outline.withValues(alpha: 0.42),
                highlight: scheme.outline.withValues(alpha: 0.36),
                lowlight: scheme.outline.withValues(alpha: 0.18),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DesktopPanelEdgeHighlightPainter extends CustomPainter {
  const _DesktopPanelEdgeHighlightPainter({
    required this.borderRadius,
    required this.outline,
    required this.highlight,
    required this.lowlight,
  });

  final BorderRadius borderRadius;
  final Color outline;
  final Color highlight;
  final Color lowlight;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    final rect = Offset.zero & size;
    final rrect = borderRadius.toRRect(rect.deflate(0.5));
    final radii = borderRadius.resolve(TextDirection.ltr);

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = outline,
    );

    final topStart = Offset(rrect.left + radii.topLeft.x, rrect.top);
    final topEnd = Offset(rrect.right - radii.topRight.x, rrect.top);
    final leftStart = Offset(rrect.left, rrect.top + radii.topLeft.y);
    final leftEnd = Offset(rrect.left, rrect.bottom - radii.bottomLeft.y);
    final bottomStart = Offset(rrect.left + radii.bottomLeft.x, rrect.bottom);
    final bottomEnd = Offset(rrect.right - radii.bottomRight.x, rrect.bottom);

    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75
      ..strokeCap = StrokeCap.round
      ..color = highlight;

    canvas.drawLine(topStart, topEnd, highlightPaint);
    canvas.drawLine(leftStart, leftEnd, highlightPaint);
    canvas.drawLine(
      bottomStart,
      bottomEnd,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75
        ..strokeCap = StrokeCap.round
        ..color = lowlight,
    );
  }

  @override
  bool shouldRepaint(covariant _DesktopPanelEdgeHighlightPainter oldDelegate) {
    return borderRadius != oldDelegate.borderRadius ||
        outline != oldDelegate.outline ||
        highlight != oldDelegate.highlight ||
        lowlight != oldDelegate.lowlight;
  }
}
