import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/role.dart';
import 'package:intergalactic/client/matrix/matrix_role.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/components/invitation/invitation_component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/ui/atoms/scaled_safe_area.dart';
import 'package:intergalactic/ui/molecules/profile/mini_profile_view.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/utils/debounce.dart';
import 'package:flutter/material.dart';

import 'package:tiamat/tiamat.dart' as tiamat;

class SendInvitationWidget extends StatefulWidget {
  const SendInvitationWidget(
    this.client,
    this.component, {
    super.key,
    this.roomId,
    this.displayName,
    this.onUserPicked,
    this.showSuggestions = true,
    this.existingMembers,
    this.room,
  });
  final Client client;
  final bool showSuggestions;
  final Iterable<String>? existingMembers;

  final Future<void> Function(String userId)? onUserPicked;

  final String? roomId;
  final String? displayName;
  final InvitationComponent component;

  /// When provided (and the current user can change roles), the invite sheet
  /// offers a role selector so a power level is assigned to the invitee up
  /// front - it applies as soon as they accept.
  final Room? room;

  @override
  State<SendInvitationWidget> createState() => _SendInvitationWidgetState();
}

class _SendInvitationWidgetState extends State<SendInvitationWidget> {
  late TextEditingController controller;
  late Debouncer debouncer;

  bool isSearching = false;
  List<Profile>? searchResults;

  bool loading = false;

  /// Selected role to assign the invitee. Null means "default" - no explicit
  /// power level is written and the invitee joins at the room default.
  Role? _selectedRole;

  bool get showRecommendations =>
      (!(isSearching || searchResults?.isNotEmpty == true)) &&
      widget.showSuggestions;

  bool get _canAssignRole =>
      widget.room != null &&
      widget.roomId != null &&
      widget.onUserPicked == null &&
      widget.room!.permissions.canChangeRoles;

  @override
  void initState() {
    controller = TextEditingController();
    debouncer = Debouncer(delay: const Duration(milliseconds: 500));
    super.initState();
  }

  @override
  void dispose() {
    debouncer.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var dmComponent = widget.client.getComponent<DirectMessagesComponent>();
    var recommended = List.from(dmComponent?.directMessageRooms ?? []);

    recommended.removeWhere(
      (element) =>
          widget.existingMembers?.contains(
            dmComponent?.getDirectMessagePartnerId(element),
          ) ==
          true,
    );

    return Opacity(
      opacity: loading ? 0.3 : 1.0,
      child: IgnorePointer(
        ignoring: loading,
        child: ScaledSafeArea(
          child: SizedBox(
            width: 500,
            child: Column(
              children: [
                if (!Layout.desktop)
                  _InviteSheetCloseButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                tiamat.TextInput(
                  controller: controller,
                  icon: const Icon(Icons.search),
                  maxLines: 1,
                  onChanged: onSearchTextChanged,
                ),
                if (_canAssignRole) _buildRoleSelector(context),
                if (isSearching || searchResults?.isNotEmpty == true)
                  SizedBox(
                    height: 300,
                    child: isSearching
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.builder(
                            itemCount: searchResults!.length,
                            shrinkWrap: true,
                            itemBuilder: (context, index) {
                              return MiniProfileView(
                                client: widget.component.client,
                                userId: searchResults![index].identifier,
                                initialProfile: searchResults![index],
                                onTap: () => invitePeer(
                                  searchResults![index].identifier,
                                ),
                              );
                            },
                          ),
                  ),
                if (!isSearching && searchResults?.isEmpty == true)
                  Column(
                    children: [
                      tiamat.Text("Could not find any users"),
                      tiamat.Button(
                        text: "Send invite",
                        onTap: () => invitePeer(controller.text),
                      ),
                    ],
                  ),
                if (showRecommendations && recommended.isNotEmpty)
                  Column(
                    children: [
                      const tiamat.Seperator(),
                      const tiamat.Text.labelLow("Recommended"),
                      ListView.builder(
                        shrinkWrap: true,
                        itemCount: recommended.length,
                        itemBuilder: (context, index) {
                          var room = recommended[index];
                          var userId = dmComponent!.getDirectMessagePartnerId(
                            room,
                          )!;
                          return MiniProfileView(
                            client: room.client,
                            onTap: () => invitePeer(userId),
                            userId: userId,
                          );
                        },
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void onSearchTextChanged(String value) async {
    setState(() {
      isSearching = value.isNotEmpty;
      searchResults = null;
      debouncer.cancel();
    });

    if (value.isNotEmpty) {
      debouncer.run(() => doSearch(value));
    }
  }

  void doSearch(String value) async {
    var result = await widget.component.searchUsers(value);

    if (!mounted) return;

    setState(() {
      isSearching = false;
      searchResults = result;
    });
  }

  Widget _buildRoleSelector(BuildContext context) {
    final roles = List<Role>.from(widget.room!.availableRoles)
      ..removeWhere((role) => _powerLevel(role) <= 0)
      ..sort((a, b) => _powerLevel(b).compareTo(_powerLevel(a)));

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
      child: Row(
        children: [
          const tiamat.Text.labelLow("Role on join"),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButton<Role?>(
              isExpanded: true,
              value: _selectedRole,
              onChanged: (role) => setState(() => _selectedRole = role),
              items: [
                const DropdownMenuItem<Role?>(
                  value: null,
                  child: Text("Default"),
                ),
                for (final role in roles)
                  DropdownMenuItem<Role?>(
                    value: role,
                    child: Text("${role.name} (${_powerLevel(role)})"),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _powerLevel(Role role) => role is MatrixRole ? role.powerLevel : 0;

  void invitePeer(String userId) async {
    setState(() {
      loading = true;
    });

    if (widget.onUserPicked != null) {
      try {
        await widget.onUserPicked?.call(userId);
        if (mounted) Navigator.pop(context);
      } catch (error, stack) {
        Log.onError(error, stack, content: "invitePeer: onUserPicked failed");
        if (mounted) {
          setState(() {
            loading = false;
          });
          await AdaptiveDialog.showError(context, error, stack);
        }
      }
      return;
    }

    final confirm = await AdaptiveDialog.confirmation(
      context,
      prompt:
          "Are you sure you want to Invite $userId to the room ${widget.displayName}?",
      title: "Invitation",
    );
    if (confirm != true) {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
      return;
    }

    // Invite and optional role assignment can throw (network, permission race,
    // transient sync error). Without handling, `loading` would stay true and
    // the sheet would stay blocked behind the IgnorePointer overlay with the
    // dialog never closing. Reset the spinner and surface the failure instead.
    try {
      await widget.component.inviteUserToRoom(
        userId: userId,
        roomId: widget.roomId!,
      );

      final role = _selectedRole;
      if (role != null && widget.room != null && _powerLevel(role) > 0) {
        await widget.room!.setMemberRole(userId, role);
      }

      if (mounted) Navigator.pop(context);
    } catch (error, stack) {
      Log.onError(
        error,
        stack,
        content: "invitePeer: invite or role assignment failed",
      );
      if (mounted) {
        setState(() {
          loading = false;
        });
        await AdaptiveDialog.showError(context, error, stack);
      }
    }
  }
}

class _InviteSheetCloseButton extends StatelessWidget {
  const _InviteSheetCloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: tiamat.Tooltip(
        text: "Close invite screen",
        child: Semantics(
          button: true,
          label: "Close invite screen",
          child: SizedBox.square(
            dimension: 44,
            child: tiamat.IconButton(
              icon: Icons.close,
              size: 22,
              onPressed: onPressed,
            ),
          ),
        ),
      ),
    );
  }
}
