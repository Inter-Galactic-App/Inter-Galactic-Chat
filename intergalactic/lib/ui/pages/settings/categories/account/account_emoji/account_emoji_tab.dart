import 'dart:typed_data';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/emoticon/emoticon.dart';
import 'package:intergalactic/client/components/emoticon/emoji_pack.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_component.dart';
import 'package:intergalactic/client/components/emoticon_recent/recent_emoticon_component.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/account_emoji/account_quick_reactions_view.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/account_emoji/account_emoji_view.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/emoji_packs/room_emoji_pack_settings_view.dart';
import 'package:intergalactic/ui/pages/settings/settings_account_scope.dart';
import 'package:flutter/widgets.dart';

class AccountEmojiTab extends StatefulWidget {
  const AccountEmojiTab(
      {required this.clientManager, this.selectedClientIndex = 0, super.key});
  final ClientManager clientManager;
  final int selectedClientIndex;
  @override
  State<AccountEmojiTab> createState() => _AccountEmojiTabState();
}

class _AccountEmojiTabState extends State<AccountEmojiTab> {
  Client? selectedClient;
  EmoticonComponent? component;
  RecentEmoticonComponent? recentEmoticonComponent;

  @override
  void initState() {
    selectedClient = SettingsAccountController.resolvePreferredClient(
      widget.clientManager,
      fallback: _indexedClient,
    );
    _syncComponents();
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scopedClient = SettingsAccountScope.selectedClientOf(
      context,
      widget.clientManager,
    );
    if (!identical(scopedClient, selectedClient)) {
      selectedClient = scopedClient;
      _syncComponents();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [buildEmojiView(context)],
    );
  }

  Widget buildEmojiView(BuildContext context) {
    if (component == null) {
      return const Placeholder();
    }

    return Column(
      // I dont love using a key here, is there a better way to do this? i dont know
      key: ValueKey("account_emoji_editor_key_${selectedClient!.identifier}"),
      children: [
        if (recentEmoticonComponent != null)
          AccountQuickReactionsView(
            client: selectedClient!,
            component: component!,
            recentEmoticons: recentEmoticonComponent!,
          ),
        if (recentEmoticonComponent != null)
          const SizedBox(
            height: 5,
          ),
        RoomEmojiPackSettingsView(
          component: component!,
          editable: true,
        ),
        const SizedBox(
          height: 5,
        ),
        if (component!.globalPacks().isNotEmpty) AccountEmojiView(component!),
      ],
    );
  }

  Future<void> createPack(String name, Uint8List? avatarData) {
    return component!.createEmoticonPack(name, avatarData);
  }

  Future<void> deleteEmoticon(EmoticonPack pack, Emoticon emoticon) {
    return pack.deleteEmoticon(emoticon);
  }

  Future<void> deletePack(EmoticonPack pack) {
    return component!.deleteEmoticonPack(pack);
  }

  Client? get _indexedClient {
    final clients = widget.clientManager.clients;
    final index = widget.selectedClientIndex;
    if (clients.isEmpty) {
      return null;
    }
    if (index >= 0 && index < clients.length) {
      return clients[index];
    }
    return clients.first;
  }

  void _syncComponents() {
    component = selectedClient?.getComponent<EmoticonComponent>();
    recentEmoticonComponent =
        selectedClient?.getComponent<RecentEmoticonComponent>();
  }
}
