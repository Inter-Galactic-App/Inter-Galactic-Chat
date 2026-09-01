import 'dart:async';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_component.dart';
import 'package:intergalactic/client/components/emoticon_recent/recent_emoticon_component.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/ui/atoms/emoji_widget.dart';
import 'package:intergalactic/ui/molecules/emoji_picker.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/utils/autofill_utils.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class AccountQuickReactionsView extends StatefulWidget {
  const AccountQuickReactionsView(
      {required this.client,
      required this.component,
      required this.recentEmoticons,
      super.key});

  final Client client;
  final EmoticonComponent component;
  final RecentEmoticonComponent recentEmoticons;

  @override
  State<AccountQuickReactionsView> createState() =>
      _AccountQuickReactionsViewState();
}

class _AccountQuickReactionsViewState extends State<AccountQuickReactionsView> {
  StreamSubscription? componentSub;
  List<Emoticon> quickReactions = List.empty();

  String get labelCustomizeReactions => Intl.message(
        "Customize Reactions",
        desc: "Header for the quick reaction customization section",
        name: "labelCustomizeReactions",
      );

  String get labelCustomizeReactionsDescription => Intl.message(
        "Tap a reaction, then choose an emoji to replace it.",
        desc: "Help text for the quick reaction customization section",
        name: "labelCustomizeReactionsDescription",
      );

  String get labelChooseReaction => Intl.message(
        "Choose Reaction",
        desc: "Title for the quick reaction picker dialog",
        name: "labelChooseReaction",
      );

  @override
  void initState() {
    super.initState();
    quickReactions = widget.recentEmoticons.getQuickReactionEmoticon(null);
    componentSub = widget.component.onStateChanged.listen((_) => updateState());
  }

  @override
  void didUpdateWidget(covariant AccountQuickReactionsView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.component != widget.component) {
      componentSub?.cancel();
      componentSub =
          widget.component.onStateChanged.listen((_) => updateState());
    }

    updateState();
  }

  @override
  void dispose() {
    componentSub?.cancel();
    super.dispose();
  }

  void updateState() {
    if (mounted == false) return;

    setState(() {
      quickReactions = widget.recentEmoticons.getQuickReactionEmoticon(null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SettingsSection(
      title: labelCustomizeReactions,
      children: [
        SettingsControlRow(
          title: 'Quick reaction slots',
          description: labelCustomizeReactionsDescription,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.72),
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Wrap(
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < quickReactions.length; i++)
                  buildReactionButton(context, i, quickReactions[i]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget buildReactionButton(
      BuildContext context, int index, Emoticon reaction) {
    return tiamat.Tooltip(
      text: reaction.shortcode ?? reaction.slug,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => openReactionPicker(index),
          child: Ink(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.56),
              ),
            ),
            child: Center(
              child: EmojiWidget(
                reaction,
                height: 30,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openReactionPicker(int index) async {
    await AdaptiveDialog.show(
      context,
      title: labelChooseReaction,
      scrollable: false,
      builder: (dialogContext) {
        return SizedBox(
          width: Layout.desktop ? 720 : null,
          height: 460,
          child: EmojiPicker(
            widget.component.availablePacks,
            onlyEmoji: true,
            preferredTooltipDirection: AxisDirection.down,
            searchDelegate: (search) => AutofillUtils.searchEmoticon(search,
                    client: widget.client, limit: 50)
                .whereType<AutofillSearchResultEmoticon>()
                .toList(),
            onEmoticonPressed: (emoticon) async {
              await widget.recentEmoticons
                  .setQuickReactionEmoticon(index, emoticon);

              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
              }

              updateState();
            },
          ),
        );
      },
    );
  }
}
