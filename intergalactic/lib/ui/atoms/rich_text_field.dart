import 'dart:convert';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/matrix/components/emoticon/matrix_emoticon.dart';
import 'package:intergalactic/client/matrix/components/emoticon/matrix_emoticon_component.dart';
import 'package:intergalactic/client/matrix/components/emoticon/matrix_room_emoticon_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/atoms/emoji_widget.dart';
import 'package:intergalactic/ui/atoms/mention.dart';
import 'package:intergalactic/utils/room_mention_utils.dart';
import 'package:intergalactic/utils/text_utils.dart';
import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:markdown/markdown.dart' as md;
import 'package:tiamat/config/config.dart';

// ignore: implementation_imports
import 'package:matrix/src/utils/markdown.dart' as mx_markdown;
import 'package:matrix/matrix.dart' as matrix;

class RichTextEditingController extends TextEditingController {
  RichTextEditingController({required this.client, this.room, super.text});
  final Room? room;
  final Client? client;

  @override
  TextSpan buildTextSpan(
      {required BuildContext context,
      TextStyle? style,
      required bool withComposing}) {
    return build(text, context, style: style);
  }

  TextSpan build(String text, BuildContext context, {TextStyle? style}) {
    final baseStyle = style ??
        Theme.of(context).textTheme.bodyMedium ??
        DefaultTextStyle.of(context).style;
    var roomEmoticons = room?.getComponent<MatrixRoomEmoticonComponent>();
    var clientEmoticons = client?.getComponent<MatrixEmoticonComponent>();
    final mentionResolver =
        room is MatrixRoom ? (room as MatrixRoom).resolveMention : null;
    var doc = md.Document(
        encodeHtml: false,
        extensionSet: md.ExtensionSet.gitHubFlavored,
        inlineSyntaxes: [
          mx_markdown.PillSyntax(),
          mx_markdown.MentionSyntax(mentionResolver),
          mx_markdown.SpoilerSyntax(),
          if (roomEmoticons != null)
            mx_markdown.EmoteSyntax(() => roomEmoticons
                .getEmotePacksFlat(matrix.ImagePackUsage.emoticon)),
          if (roomEmoticons == null && clientEmoticons != null)
            mx_markdown.EmoteSyntax(() => clientEmoticons
                .getEmotePacksFlat(matrix.ImagePackUsage.emoticon))
        ]);

    List<md.Node>? parsed;
    try {
      parsed = doc.parseLines(const LineSplitter().convert(text));
    } catch (exception) {
      return TextSpan(
        children: TextUtils.nativeEmojiTextSpans(
          text,
          style: baseStyle,
        ),
      );
    }

    var children = <InlineSpan>[];

    int currentIndex = 0;

    for (var element in parsed) {
      currentIndex =
          handleNode(context, currentIndex, text, children, baseStyle, element);
    }

    if (currentIndex <= text.length - 1) {
      children.addAll(TextUtils.nativeEmojiTextSpans(
        text.substring(currentIndex),
        style: baseStyle,
      ));
    }

    return TextSpan(children: children);
  }

  int handleNode(BuildContext context, int currentIndex, String text,
      List<InlineSpan> children, TextStyle style, md.Node node,
      {Widget? overrideWidget, double overrideVerticalOffset = 2.5}) {
    var originalStyle = style.copyWith();

    if (node is md.Text) {
      var substr = text.substring(currentIndex);
      var nodeText = node.text;
      var index = substr.indexOf(nodeText);

      if (index == -1) {
        return currentIndex;
      }

      if (index != 0) {
        var sub = substr.substring(0, index);

        children.addAll(TextUtils.nativeEmojiTextSpans(
          sub,
          style: style,
        ));
        currentIndex += sub.length;
      }

      if (overrideWidget != null) {
        // The total number of items that can be in the span (characters + child widgets) MUST
        // equal the amount of characters in the string it is meant to represent, so that the
        // cursor renders in the correct place.
        // This is a hacky way to acheive that
        var widgetChildren = List<InlineSpan>.generate(
            nodeText.length,
            (i) => WidgetSpan(
                child: Container(
                    child: i == 0
                        ? Transform.translate(
                            offset: Offset(0, overrideVerticalOffset),
                            child: overrideWidget)
                        : SizedBox(
                            width: 0,
                            height: 0,
                          ))));

        children.add(TextSpan(
          children: widgetChildren,
          style: originalStyle,
        ));
      } else {
        final roomMentionSpans =
            _buildRoomMentionInlineSpans(context, nodeText, originalStyle);
        if (roomMentionSpans != null) {
          children.add(TextSpan(
            children: roomMentionSpans,
            style: originalStyle,
          ));
          currentIndex += nodeText.length;
          return currentIndex;
        }

        children.addAll(TextUtils.nativeEmojiTextSpans(
          nodeText,
          style: originalStyle,
        ));
      }

      currentIndex += nodeText.length;
    }

    if (node is md.Element) {
      switch (node.tag) {
        case "em":
          style = style.copyWith(fontStyle: FontStyle.italic);
          break;
        case "strong":
          style = style.copyWith(fontWeight: FontWeight.bold);
          break;
        case "span":
          if (node.attributes.containsKey("data-mx-spoiler"))
            style =
                style.copyWith(backgroundColor: style.color?.withAlpha(200));
          break;
        case "code":
          var color =
              Theme.of(context).extension<ExtraColors>()?.codeHighlight ??
                  Theme.of(context).colorScheme.primary;
          style = style.copyWith(
              color: color,
              fontFamily: "code",
              fontFeatures: const [FontFeature.disable("calt")]);
          break;
        case "pre":
          style = style.copyWith(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              fontFamily: "code",
              fontFeatures: const [FontFeature.disable("calt")]);
          break;
        case "img":
          if (client case MatrixClient mx) {
            var content = node.attributes["alt"];
            var src = node.attributes["src"] as String;
            var uri = Uri.parse(src);
            var size = 24.0;
            currentIndex = handleNode(
                context, currentIndex, text, children, style, md.Text(content!),
                overrideVerticalOffset: 5,
                overrideWidget: SizedBox(
                    height: size,
                    width: size,
                    child: EmojiWidget(
                        height: size,
                        MatrixEmoticon(uri, mx.matrixClient,
                            shortcode: content,
                            packUsage: EmoticonUsage.all,
                            usage: EmoticonUsage.emoji))));
            return currentIndex;
          }
        case "a":
          style = style.copyWith(color: Theme.of(context).colorScheme.primary);
          var href = node.attributes["href"];
          if (href != null) {
            var result = MatrixClient.parseMatrixLink(Uri.parse(href));
            if (result != null) {
              var mxId = result.$2;

              for (var element in node.children!) {
                if (result.$1 == MatrixLinkType.user) {
                  var user = room?.getMember(mxId);
                  if (user != null) {
                    currentIndex = handleNode(
                        context, currentIndex, text, children, style, element,
                        overrideWidget: MentionWidget(
                            displayName: user.displayName,
                            avatar: user.avatar,
                            style: style,
                            placeholderColor: user.defaultColor));
                    return currentIndex;
                  }
                } else if (result.$1 == MatrixLinkType.room) {
                  var taggedRoom = client?.getRoom(mxId);

                  var vias =
                      (client as MatrixClient).parseAddressToIdAndVia(href);

                  if (taggedRoom != null) {
                    currentIndex = handleNode(
                        context, currentIndex, text, children, style, element,
                        overrideWidget: MentionWidget(
                            fallbackIcon:
                                preferences.usePlaceholderRoomAvatars.value
                                    ? null
                                    : taggedRoom.icon,
                            displayName: taggedRoom.displayName,
                            avatar: taggedRoom.avatar,
                            vias: vias?.$2,
                            style: style,
                            placeholderColor: taggedRoom.defaultColor));
                    return currentIndex;
                  }
                }
              }
            }
          }
          break;
        case "del":
          style = style.copyWith(decoration: TextDecoration.lineThrough);
          break;
        case "h1":
          style = style.copyWith(fontSize: 14 * 2, fontWeight: FontWeight.bold);
          break;
        case "h2":
          style =
              style.copyWith(fontSize: 14 * 1.5, fontWeight: FontWeight.bold);
          break;
        case "h3":
          style =
              style.copyWith(fontSize: 14 * 1.17, fontWeight: FontWeight.bold);
          break;
        case "h4":
          style = style.copyWith(fontSize: 14 * 1, fontWeight: FontWeight.bold);
          break;
        case "h5":
          style =
              style.copyWith(fontSize: 14 * 0.83, fontWeight: FontWeight.bold);
          break;
        case "h6":
          style =
              style.copyWith(fontSize: 14 * 0.67, fontWeight: FontWeight.bold);
          break;
      }

      if (node.children != null) {
        for (var element in node.children!) {
          currentIndex =
              handleNode(context, currentIndex, text, children, style, element);
        }
      }
    }
    return currentIndex;
  }
}

List<InlineSpan>? _buildRoomMentionInlineSpans(
    BuildContext context, String text, TextStyle style) {
  if (_isCodeStyle(style)) {
    return null;
  }

  final parts = splitRoomMentionParts(text);
  if (!parts.any((part) => part.isMention)) {
    return null;
  }

  return [
    for (final part in parts)
      if (!part.isMention)
        ...TextUtils.nativeEmojiTextSpans(part.text, style: style)
      else
        TextSpan(
          children: List<InlineSpan>.generate(
            part.text.length,
            (index) => WidgetSpan(
              child: index == 0
                  ? Transform.translate(
                      offset: const Offset(0, 2.5),
                      child: MentionWidget(
                        displayName: part.text,
                        fallbackIcon: Icons.campaign_outlined,
                        placeholderColor: Theme.of(context).colorScheme.primary,
                        style: style,
                      ),
                    )
                  : const SizedBox(width: 0, height: 0),
            ),
          ),
          style: style,
        ),
  ];
}

bool _isCodeStyle(TextStyle style) => style.fontFamily == 'code';
