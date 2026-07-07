import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as material;
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/atoms/mention.dart';
import 'package:intergalactic/ui/atoms/rich_text/spans/link.dart';
import 'package:intergalactic/utils/room_mention_utils.dart';
import 'package:intl/intl.dart' as intl;

import 'emoji/emoji_matcher.dart';

final _urlRegex = RegExp(
  r'(?:(?:https?):\/\/|www\.)(?:\([-A-Z0-9+&@#/%=~_|$?!:,.]*\)|[-A-Z0-9+&@#/%=~_|$?!:,.])*(?:\([-A-Z0-9+&@#/%=~_|$?!:,.]*\)|[A-Z0-9+&@#/%=~_|$])',
  caseSensitive: false,
  dotAll: true,
);

enum NewPasswordResult { valid, tooShort, noNumbers, noSymbols, noMixedCase }

class TextUtils {
  static const String _appleColorEmoji = 'Apple Color Emoji';
  static const String _segoeUiEmoji = 'Segoe UI Emoji';
  static const String _notoColorEmoji = 'Noto Color Emoji';
  static const String _emojiFont = 'EmojiFont';

  static const List<String> nativeEmojiFontFallback = [
    _appleColorEmoji,
    _segoeUiEmoji,
    _notoColorEmoji,
    _emojiFont,
  ];

  static TextStyle withNativeEmojiFallback(TextStyle? style) {
    final baseStyle = style ?? const TextStyle();
    final existingFallback = baseStyle.fontFamilyFallback ?? const <String>[];
    final fallback = [
      ...nativeEmojiFontFallback,
      ...existingFallback.where(
        (font) => !nativeEmojiFontFallback.contains(font),
      ),
    ];

    return baseStyle.copyWith(
      fontFamily: _nativeEmojiFontFamilyForPlatform() ?? baseStyle.fontFamily,
      fontFamilyFallback: fallback,
    );
  }

  static List<InlineSpan> nativeEmojiTextSpans(
    String text, {
    TextStyle? style,
  }) {
    if (text.isEmpty) {
      return const [];
    }

    final spans = <InlineSpan>[];
    final textBuffer = StringBuffer();

    void flushText() {
      if (textBuffer.isEmpty) {
        return;
      }

      spans.add(TextSpan(text: textBuffer.toString(), style: style));
      textBuffer.clear();
    }

    for (final char in text.characters) {
      if (isEmoji(char)) {
        flushText();
        spans.add(TextSpan(text: char, style: withNativeEmojiFallback(style)));
      } else {
        textBuffer.write(char);
      }
    }

    flushText();
    return spans;
  }

  static bool isEmoji(String text) {
    if (text.isEmpty || text.trim().isEmpty) {
      return false;
    }

    var matches = EmojiMatcher.find(text);
    if (matches.length == 1 &&
        matches.single.start == 0 &&
        matches.single.end == text.length) {
      return true;
    }

    return _looksLikeEmojiGrapheme(text);
  }

  static bool isEmojiOnly(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    var emojiCount = 0;
    for (final char in trimmed.characters) {
      if (char.trim().isEmpty) {
        continue;
      }

      if (!isEmoji(char)) {
        return false;
      }

      emojiCount++;
    }

    return emojiCount > 0;
  }

  static bool containsEmoji(String text) {
    return text.characters.any(isEmoji);
  }

  static String? _nativeEmojiFontFamilyForPlatform() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return _appleColorEmoji;
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
        return _notoColorEmoji;
      case TargetPlatform.windows:
        return _segoeUiEmoji;
    }
  }

  static bool _looksLikeEmojiGrapheme(String text) {
    if (text.characters.length != 1) {
      return false;
    }

    final codePoints = text.runes.toList();
    if (codePoints.isEmpty) {
      return false;
    }

    if (codePoints.any(_isEmojiPresentationCodePoint)) {
      return true;
    }

    final hasEmojiJoiner = codePoints.contains(0x200D);
    final hasEmojiVariation = codePoints.contains(0xFE0F);
    final hasKeycap = codePoints.contains(0x20E3);

    if (!hasEmojiJoiner && !hasEmojiVariation && !hasKeycap) {
      return false;
    }

    return codePoints.any(_isEmojiBaseCodePoint);
  }

  static bool _isEmojiBaseCodePoint(int codePoint) {
    return _isEmojiPresentationCodePoint(codePoint) ||
        codePoint == 0x0023 ||
        codePoint == 0x002A ||
        (codePoint >= 0x0030 && codePoint <= 0x0039) ||
        (codePoint >= 0x203C && codePoint <= 0x3299);
  }

  static bool _isEmojiPresentationCodePoint(int codePoint) {
    return (codePoint >= 0x1F000 && codePoint <= 0x1FAFF) ||
        (codePoint >= 0x1FC00 && codePoint <= 0x1FFFF) ||
        (codePoint >= 0xE0020 && codePoint <= 0xE007F);
  }

  static String linkifyStringHtml(String text) {
    var matches = _urlRegex.allMatches(text);
    List<String> urlsToReplace = List.empty(growable: true);

    for (int i = 0; i < matches.length; i++) {
      var match = matches.elementAt(i);
      var link = text.substring(match.start, match.end);

      if (!urlsToReplace.contains(link)) {
        urlsToReplace.add(link);
      }
    }

    for (var link in urlsToReplace) {
      text = text.replaceAll(link, '<a href="$link">$link</a>');
    }

    return text;
  }

  static bool containsUrl(String text) {
    return _urlRegex.hasMatch(text);
  }

  static List<InlineSpan> linkifyString(
    String text, {
    TextStyle? style,
    required BuildContext context,
    required String clientId,
  }) {
    final parts = splitRoomMentionParts(text);
    if (parts.any((part) => part.isMention)) {
      return [
        for (final part in parts)
          if (!part.isMention)
            ..._linkifySegment(
              part.text,
              style: style,
              context: context,
              clientId: clientId,
            )
          else
            WidgetSpan(
              child: Transform.translate(
                offset: const Offset(0, 2),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(2, 0, 2, 0),
                  child: MentionWidget(
                    displayName: part.text,
                    fallbackIcon: Icons.campaign_outlined,
                    placeholderColor: Theme.of(context).colorScheme.primary,
                    style: style,
                  ),
                ),
              ),
            ),
      ];
    }

    return _linkifySegment(
      text,
      style: style,
      context: context,
      clientId: clientId,
    );
  }

  static List<Uri>? findUrls(String text) {
    var matches = _urlRegex.allMatches(text);
    if (matches.isEmpty) return null;

    return matches
        .map((e) => Uri.parse(text.substring(e.start, e.end)))
        .toList();
  }

  static List<InlineSpan> formatMatches(
    Iterable<RegExpMatch> matches,
    String text, {
    required InlineSpan Function(String matchedText, TextStyle? theme) builder,
    TextStyle? style,
  }) {
    if (matches.isEmpty) return nativeEmojiTextSpans(text, style: style);

    List<InlineSpan> span = List.empty(growable: true);
    for (int i = 0; i < matches.length; i++) {
      var match = matches.elementAt(i);

      String? pre;

      if (i == 0 && match.start > 0) {
        pre = text.substring(0, match.start);
      } else if (i > 0) {
        var start = match.start;
        var end = matches.elementAt(i - 1).end;

        if (start != end) {
          var previous = matches.elementAt(i - 1);
          pre = text.substring(previous.end, match.start);
        }
      }

      if (pre != null) {
        span.addAll(nativeEmojiTextSpans(pre, style: style));
      }

      span.add(builder(text.substring(match.start, match.end), style));
    }

    if (matches.last.end != text.length) {
      span.addAll(
        nativeEmojiTextSpans(text.substring(matches.last.end), style: style),
      );
    }

    return span;
  }

  static List<InlineSpan> _linkifySegment(
    String text, {
    TextStyle? style,
    required BuildContext context,
    required String clientId,
  }) {
    final matches = _urlRegex.allMatches(text);
    return formatMatches(
      matches,
      text,
      style: style,
      builder: (matchedText, theme) {
        return LinkSpan.create(
          matchedText,
          clientId: clientId,
          context: context,
          destination: Uri.parse(matchedText),
          style: style,
        );
      },
    );
  }

  static NewPasswordResult isValidPassword(
    String password, {
    bool forceDigits = false,
    int? forceLength,
    bool forceSpecialCharacter = false,
  }) {
    if (forceLength != null) {
      if (password.length < forceLength) return NewPasswordResult.tooShort;
    }

    if (forceDigits) {
      if (!password.characters.any((char) => int.tryParse(char) != null)) {
        return NewPasswordResult.noNumbers;
      }
    }

    if (forceSpecialCharacter) {
      if (!password.characters.any(
        (char) => ("!@#\$%^&*()_+`{}|:\"<>?/.,';][=-\\").contains(char),
      )) {
        return NewPasswordResult.noSymbols;
      }
    }

    return NewPasswordResult.valid;
  }

  static String timestampToLocalizedTime(DateTime time, BuildContext context) {
    var difference = DateTime.now().difference(time);

    if (difference.inDays == 0) {
      return MaterialLocalizations.of(
        context,
      ).formatTimeOfDay(TimeOfDay.fromDateTime(time));
    }

    if (difference.inDays < 365) {
      return intl.DateFormat(
        intl.DateFormat.MONTH_WEEKDAY_DAY,
      ).format(time.toLocal());
    }

    return intl.DateFormat(
      intl.DateFormat.YEAR_MONTH_WEEKDAY_DAY,
    ).format(time.toLocal());
  }

  static String timestampToLocalizedTimeSpecific(DateTime time, context) {
    return intl.DateFormat().format(time.toLocal());
  }

  static String formatDuration(Duration duration) {
    if (duration.inSeconds < 60) {
      return "${duration.inSeconds}s";
    }

    if (duration.inMinutes < 60) {
      return "${duration.inMinutes.remainder(60)}:${(duration.inSeconds.remainder(60))}";
    }
    return "${duration.inHours}:${duration.inMinutes.remainder(60)}:${(duration.inSeconds.remainder(60))}";
  }

  static String readableFileSize(num number, {bool base1024 = true}) {
    const List<String> affixes = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    const useBase1024 = true;
    const int round = 2;

    // ignore: dead_code
    num divider = useBase1024 ? 1024 : 1000;

    num size = number;
    num runningDivider = divider;
    num runningPreviousDivider = 0;
    int affix = 0;

    while (size >= runningDivider && affix < affixes.length - 1) {
      runningPreviousDivider = runningDivider;
      runningDivider *= divider;
      affix++;
    }

    String result =
        (runningPreviousDivider == 0 ? size : size / runningPreviousDivider)
            .toStringAsFixed(round);

    //Check if the result ends with .00000 (depending on how many decimals) and remove it if found.
    if (result.endsWith("0" * round))
      result = result.substring(0, result.length - round - 1);

    return "$result ${affixes[affix]}";
  }

  static String redactSensitiveInfo(String text) {
    if (clientManager != null) {
      for (final client in clientManager!.clients) {
        if (client is MatrixClient) {
          var token = client.getMatrixClient().accessToken;

          if (token != null) {
            text = text.replaceAll(token, "[REDACTED ACCESS TOKEN]");
          }
        }
      }
    }

    return text;
  }

  static String toHexString(Uint8List bytes) {
    return bytes.fold<String>(
      '',
      (str, byte) => str + byte.toRadixString(16).padLeft(2, '0'),
    );
  }

  static Uint8List parseHexString(String hexString) => Uint8List.fromList(
        (RegExp(r'.{1,2}').allMatches(hexString).toList()).map<int>((byte) {
          return int.parse(byte.group(0)!, radix: 16);
        }).toList(),
      );
}
