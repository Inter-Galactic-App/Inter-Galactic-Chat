import 'package:flutter/material.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/ui/pages/inbound_share/inbound_share_destination_model.dart';
import 'package:intergalactic/utils/common_strings.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Strings for the forward destination picker.
///
/// The confirm button reuses [CommonStrings.promptForwardMessage], which the
/// timeline menu entry that starts this flow also uses. Everything else here
/// is written for this picker, so it lives with it.
///
/// Every string is its own member. A `cond ? a : b` written as one getter
/// puts two `Intl.message` calls in one member and the extractor silently
/// drops BOTH, so the two conversation-type labels and the two row semantics
/// labels are declared separately and chosen at the call site.
class ForwardDestinationStrings {
  static String get labelForwardDestinationDirectConversation => Intl.message(
    "Direct conversation",
    name: "labelForwardDestinationDirectConversation",
    desc:
        "Subtitle under a room name in the forward picker saying the "
        "conversation is a one-to-one direct message. Also read aloud as part "
        "of the row's accessibility label",
  );

  static String get labelForwardDestinationGroupConversation => Intl.message(
    "Group conversation",
    name: "labelForwardDestinationGroupConversation",
    desc:
        "Subtitle under a room name in the forward picker saying the "
        "conversation has more than two people in it. Also read aloud as part "
        "of the row's accessibility label",
  );

  static String get titleForwardDestinationPage => Intl.message(
    "Forward to",
    name: "titleForwardDestinationPage",
    desc:
        "Title bar of the picker that chooses which conversations a message "
        "is forwarded to. Reads as the start of a sentence the chosen rooms "
        "complete",
  );

  static String get tooltipForwardDestinationCancel => Intl.message(
    "Cancel forward",
    name: "tooltipForwardDestinationCancel",
    desc:
        "Hover tooltip on the close button of the forward picker, which "
        "abandons the forward without sending anything",
  );

  static String get labelForwardDestinationSearch => Intl.message(
    "Search conversations",
    name: "labelForwardDestinationSearch",
    desc:
        "Label on the text field that filters the forward picker's list of "
        "conversations",
  );

  static String get labelForwardDestinationNoMatches => Intl.message(
    "No conversations match.",
    name: "labelForwardDestinationNoMatches",
    desc:
        "Shown in place of the forward picker's list when the search text "
        "matches no conversation",
  );

  static String semanticsForwardDestinationRow(
    String roomName,
    String conversationType,
  ) => Intl.message(
    "$roomName, $conversationType",
    name: "semanticsForwardDestinationRow",
    args: [roomName, conversationType],
    // Strings, not ints: flutter gen-l10n rejects a placeholder whose example
    // is not a non-empty STRING, and the extractor copies the literal through
    // unchanged, so a non-string here fails the build rather than this file.
    examples: const {
      'roomName': 'Team chat',
      'conversationType': 'Group conversation',
    },
    desc:
        "Accessibility label READ ALOUD by a screen reader for one selectable "
        "row of the forward picker. conversationType is one of the direct or "
        "group conversation labels",
  );

  static String semanticsForwardDestinationRowAtLimit(
    String roomName,
    String conversationType,
  ) => Intl.message(
    "$roomName, $conversationType, selection limit reached",
    name: "semanticsForwardDestinationRowAtLimit",
    args: [roomName, conversationType],
    examples: const {
      'roomName': 'Team chat',
      'conversationType': 'Group conversation',
    },
    desc:
        "Accessibility label READ ALOUD by a screen reader for a row of the "
        "forward picker that cannot be chosen because the maximum number of "
        "conversations is already selected",
  );

  static String labelForwardDestinationChooseUpTo(int maximum) => Intl.message(
    "Choose up to $maximum conversations",
    name: "labelForwardDestinationChooseUpTo",
    args: [maximum],
    examples: const {'maximum': '10'},
    desc:
        "Status line in the forward picker's footer before anything is "
        "chosen, stating how many conversations may be selected at once",
  );

  static String labelForwardDestinationSelectedCount(
    int selected,
    int maximum,
  ) => Intl.message(
    "$selected of $maximum selected",
    name: "labelForwardDestinationSelectedCount",
    args: [selected, maximum],
    examples: const {'selected': '1', 'maximum': '10'},
    desc:
        "Status line in the forward picker's footer once at least one "
        "conversation is chosen: how many are selected out of the maximum",
  );
}

/// One selectable conversation in the forward picker.
class ForwardDestination {
  const ForwardDestination({required this.room, required this.isDirect});

  final Room room;
  final bool isDirect;

  String get roomId => room.identifier;
  String get roomName => room.displayName;
  String get conversationTypeLabel => isDirect
      ? ForwardDestinationStrings.labelForwardDestinationDirectConversation
      : ForwardDestinationStrings.labelForwardDestinationGroupConversation;

  bool matches(String query) {
    final normalized = query.trim().toLowerCase();
    return normalized.isEmpty ||
        roomName.toLowerCase().contains(normalized) ||
        roomId.toLowerCase().contains(normalized);
  }

  /// Builds the pickable set for one account, newest conversation first.
  ///
  /// Ordering is deliberately the same rule the inbound-share picker uses -
  /// recent activity, then name - because both answer "which conversation did
  /// I mean" and a user who has learned one ordering should not have to learn
  /// a second. Alphabetical, which this picker used before, buries the
  /// conversation you were just in.
  static List<ForwardDestination> forRooms(Iterable<Room> rooms) {
    final destinations = <ForwardDestination>[];
    for (final room in rooms) {
      final isDirect =
          room.client
              .getComponent<DirectMessagesComponent>()
              ?.isRoomDirectMessage(room) ==
          true;
      destinations.add(ForwardDestination(room: room, isDirect: isDirect));
    }

    return InboundShareDestinations.sortByRecentActivity(
      destinations,
      lastActivity: (destination) => destination.room.lastEvent == null
          ? null
          : destination.room.lastEventTimestamp,
      roomName: (destination) => destination.roomName,
      accountLabel: (destination) => destination.roomId,
    );
  }
}

/// Destination picker for a forward, shaped like the inbound-share picker.
///
/// Three things the generic multi-select dialog it replaces could not do, all
/// of which the owner hit on a real account: it showed a bare name per row so
/// every conversation looked alike; it had no search, so finding a room meant
/// scrolling; and it laid the list and the submit button out in one scrolling
/// column, so with more than a screenful of rooms the button was somewhere
/// below the fold with nothing to say it existed.
///
/// Here the list scrolls inside its own [Expanded] and the action bar is a
/// sibling, so the button and the running count are always on screen.
class ForwardDestinationPage extends StatefulWidget {
  const ForwardDestinationPage({
    required this.destinations,
    required this.maximumSelections,
    super.key,
  });

  final List<ForwardDestination> destinations;
  final int maximumSelections;

  /// Presents the picker and returns the chosen rooms, or null if cancelled.
  ///
  /// Full screen on mobile, matching the share flow the owner compared this
  /// to; a fixed-size dialog on desktop, because the pinned action bar needs a
  /// bounded height to be pinned to.
  static Future<List<Room>?> show(
    BuildContext context, {
    required List<ForwardDestination> destinations,
    required int maximumSelections,
  }) {
    final page = ForwardDestinationPage(
      destinations: destinations,
      maximumSelections: maximumSelections,
    );

    if (Layout.desktop) {
      return showDialog<List<Room>>(
        context: context,
        builder: (context) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 460,
              maxHeight: 620,
              minHeight: 420,
            ),
            child: page,
          ),
        ),
      );
    }

    return Navigator.of(context).push<List<Room>>(
      MaterialPageRoute(fullscreenDialog: true, builder: (context) => page),
    );
  }

  @override
  State<ForwardDestinationPage> createState() => _ForwardDestinationPageState();
}

class _ForwardDestinationPageState extends State<ForwardDestinationPage> {
  final Set<String> _selectedRoomIds = <String>{};
  String _query = '';

  bool get _atLimit => _selectedRoomIds.length >= widget.maximumSelections;

  List<Room> get _selectedRooms => [
    for (final destination in widget.destinations)
      if (_selectedRoomIds.contains(destination.roomId)) destination.room,
  ];

  void _toggle(ForwardDestination destination) {
    setState(() {
      if (!_selectedRoomIds.remove(destination.roomId) && !_atLimit) {
        _selectedRoomIds.add(destination.roomId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = InboundShareDestinations.search(
      widget.destinations,
      _query,
      (destination, query) => destination.matches(query),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(ForwardDestinationStrings.titleForwardDestinationPage),
        leading: IconButton(
          tooltip: ForwardDestinationStrings.tooltipForwardDestinationCancel,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              autofocus: Layout.desktop,
              decoration: InputDecoration(
                labelText:
                    ForwardDestinationStrings.labelForwardDestinationSearch,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      ForwardDestinationStrings
                          .labelForwardDestinationNoMatches,
                    ),
                  )
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) =>
                        _destinationTile(visible[index]),
                  ),
          ),
          _ActionBar(
            selected: _selectedRoomIds.length,
            maximum: widget.maximumSelections,
            onSubmit: _selectedRoomIds.isEmpty
                ? null
                : () => Navigator.of(context).pop(_selectedRooms),
          ),
        ],
      ),
    );
  }

  Widget _destinationTile(ForwardDestination destination) {
    final selected = _selectedRoomIds.contains(destination.roomId);
    // A row that cannot be selected any more is disabled rather than allowed
    // to fail at submit time. The limit is a rule of the feature, so it should
    // stop the eleventh tap, not the Forward button.
    final selectable = selected || !_atLimit;

    // The tile publishes its own title and subtitle, which the label above
    // repeats, so the child is excluded and this node carries the checkbox
    // state and action itself - the same shape as _JoinRequestActionButton.
    return Semantics(
      label: selectable
          ? ForwardDestinationStrings.semanticsForwardDestinationRow(
              destination.roomName,
              destination.conversationTypeLabel,
            )
          : ForwardDestinationStrings.semanticsForwardDestinationRowAtLimit(
              destination.roomName,
              destination.conversationTypeLabel,
            ),
      checked: selected,
      enabled: selectable,
      onTap: selectable ? () => _toggle(destination) : null,
      child: ExcludeSemantics(
        child: CheckboxListTile(
          value: selected,
          enabled: selectable,
          controlAffinity: ListTileControlAffinity.trailing,
          onChanged: (_) => _toggle(destination),
          secondary: tiamat.Avatar(
            radius: 20,
            image: destination.room.avatar,
            placeholderText: destination.roomName,
            placeholderColor: destination.room.defaultColor,
          ),
          title: Text(
            destination.roomName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(destination.conversationTypeLabel),
        ),
      ),
    );
  }
}

/// The pinned footer: how many are chosen, the limit, and the action.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.selected,
    required this.maximum,
    required this.onSubmit,
  });

  final int selected;
  final int maximum;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    selected == 0
                        ? ForwardDestinationStrings.labelForwardDestinationChooseUpTo(
                            maximum,
                          )
                        : ForwardDestinationStrings.labelForwardDestinationSelectedCount(
                            selected,
                            maximum,
                          ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: onSubmit,
                icon: const Icon(Icons.forward),
                label: Text(CommonStrings.promptForwardMessage),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
