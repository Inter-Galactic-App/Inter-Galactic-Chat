import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intergalactic/client/components/invitation/invitation_component.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/client/matrix/matrix_role.dart';
import 'package:intergalactic/client/role.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/ui/atoms/role_view.dart';
import 'package:intergalactic/ui/molecules/user_panel.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/organisms/invitation_view/send_invitation.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/ui/pages/settings/settings_status_components.dart';
import 'package:intergalactic/utils/error_utils.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomMembersSettingsPage extends StatefulWidget {
  const RoomMembersSettingsPage({required this.room, super.key});

  final Room room;

  @override
  State<RoomMembersSettingsPage> createState() =>
      _RoomMembersSettingsPageState();
}

class _RoomMembersSettingsPageState extends State<RoomMembersSettingsPage> {
  late Future<void> _loadFuture;
  final List<_RoleEntry> _roles = [];
  final List<_MemberEntry> _members = [];
  final List<Member> _joinRequests = [];
  final Set<String> _processingJoinRequestIds = {};
  final List<Member> _pendingInvites = [];
  final Set<String> _processingInviteIds = {};
  List<Object> _entries = [];
  bool _isEdited = false;
  bool _isSaving = false;

  bool get _canEdit => widget.room.permissions.canChangeRoles;

  InvitationComponent? get _invitation =>
      widget.room.client.getComponent<InvitationComponent>();

  /// This page is the Members tab for both a room and a space, so the copy
  /// below deliberately avoids naming either.
  bool get _canInvite =>
      _invitation != null && widget.room.permissions.canInviteUser;

  bool get _canReviewJoinRequests =>
      widget.room.permissions.canInviteUser || widget.room.permissions.canKick;

  bool get _canReviewPendingInvites =>
      widget.room.permissions.canInviteUser || widget.room.permissions.canKick;

  RoomJoinRequestActions? get _joinRequestActions {
    final room = widget.room;
    if (room is RoomJoinRequestActions) {
      return room as RoomJoinRequestActions;
    }

    return null;
  }

  RoomPendingInviteActions? get _pendingInviteActions {
    final room = widget.room;
    if (room is RoomPendingInviteActions) {
      return room as RoomPendingInviteActions;
    }

    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadFuture = _loadMembers();
  }

  Future<void> _loadMembers() async {
    final loadedMembers = widget.room.isMembersListComplete
        ? widget.room.membersList()
        : await widget.room.fetchMembersList();
    final joinRequestActions = _joinRequestActions;
    final loadedJoinRequests =
        joinRequestActions != null && _canReviewJoinRequests
        ? await joinRequestActions.fetchJoinRequests()
        : <Member>[];
    final pendingInviteActions = _pendingInviteActions;
    final loadedPendingInvites =
        pendingInviteActions != null && _canReviewPendingInvites
        ? await pendingInviteActions.fetchPendingInvites()
        : <Member>[];
    final availableRoles =
        widget.room.availableRoles
            .map(
              (role) => _RoleEntry(role: role, powerLevel: _powerLevel(role)),
            )
            .toList(growable: false)
          ..sort((left, right) => right.powerLevel.compareTo(left.powerLevel));

    _roles
      ..clear()
      ..addAll(availableRoles);
    _members
      ..clear()
      ..addAll(
        loadedMembers.map((member) {
          final role = _matchingAvailableRole(
            widget.room.getMemberRole(member.identifier),
          );
          return _MemberEntry(member: member, originalRole: role, role: role);
        }),
      );
    _joinRequests
      ..clear()
      ..addAll(loadedJoinRequests);
    _processingJoinRequestIds.removeWhere(
      (id) => !_joinRequests.any((member) => member.identifier == id),
    );
    _pendingInvites
      ..clear()
      ..addAll(loadedPendingInvites);
    _processingInviteIds.removeWhere(
      (id) => !_pendingInvites.any((member) => member.identifier == id),
    );

    _sortEntries();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: tiamat.Text.error(snapshot.error.toString()));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // First, because it is the one thing on this page you come here to
            // DO. Join requests below still announce themselves with an accent
            // panel, so leading with the action does not bury them.
            if (_canInvite) _buildInviteSection(context),
            if (_joinRequests.isNotEmpty) _buildJoinRequestsSection(context),
            if (_pendingInvites.isNotEmpty)
              _buildPendingInvitesSection(context),
            ReorderableList(
              itemBuilder: (context, index) {
                final entry = _entries[index];
                final enabled = _canEdit && !_isSaving && entry is _MemberEntry;
                final key = entry is _RoleEntry
                    ? ValueKey('room-member-role-${entry.powerLevel}')
                    : ValueKey(
                        'room-member-${(entry as _MemberEntry).member.identifier}',
                      );

                if (BuildConfig.MOBILE) {
                  return ReorderableDelayedDragStartListener(
                    key: key,
                    enabled: enabled,
                    index: index,
                    child: _buildEntry(context, index),
                  );
                }

                return ReorderableDragStartListener(
                  key: key,
                  enabled: enabled,
                  index: index,
                  child: _buildEntry(context, index),
                );
              },
              onReorderStart: (_) => HapticFeedback.mediumImpact(),
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) {
                    final value = Curves.easeOut.transform(animation.value);
                    return Transform.scale(
                      scale: lerpDouble(1, 1.03, value)!,
                      child: child,
                    );
                  },
                  child: child,
                );
              },
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: _entries.length,
              onReorder: _onReorder,
            ),
            if (_isEdited)
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: tiamat.Button(
                    text: 'Save role changes',
                    isLoading: _isSaving,
                    onTap: _isSaving ? null : _applySettings,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildInviteSection(BuildContext context) {
    return SettingsSection(
      title: 'Invite',
      showDivider: false,
      children: [
        SettingsControlRow(
          title: 'Invite people',
          description:
              'Search for someone and send them an invite. They appear under '
              'Pending invites until they accept.',
          trailing: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 124,
              child: tiamat.Button(
                text: 'Invite',
                onTap: _isSaving ? null : () => _showInviteDialog(context),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showInviteDialog(BuildContext context) async {
    final invitation = _invitation;
    if (invitation == null) {
      return;
    }

    await AdaptiveDialog.show<void>(
      context,
      title: 'Invite',
      builder: (context) => SendInvitationWidget(
        widget.room.client,
        invitation,
        roomId: widget.room.identifier,
        displayName: widget.room.displayName,
        existingMembers: widget.room.memberIds,
        room: widget.room,
      ),
    );

    if (!mounted) {
      return;
    }

    // The pending-invite list is loaded once, in initState. Without this the
    // person you just invited is missing from the very section that exists to
    // show them, which reads as the invite having failed.
    await ErrorUtils.tryRun(context, _loadMembers);
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildJoinRequestsSection(BuildContext context) {
    return SettingsSection(
      title: 'Join requests',
      showDivider: false,
      children: [
        SettingsStatePanel(
          icon: Icons.how_to_reg,
          title: _joinRequestsTitle,
          description:
              'Review people who requested access by knocking. Approve lets them join this room; decline removes the pending request.',
          tone: SettingsStatusTone.accent,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        ),
        for (final request in _joinRequests)
          _buildJoinRequestEntry(context, request),
      ],
    );
  }

  Widget _buildJoinRequestEntry(BuildContext context, Member request) {
    final isProcessing =
        _processingJoinRequestIds.contains(request.identifier) || _isSaving;
    final canApprove = widget.room.permissions.canInviteUser && !isProcessing;
    final canDecline = widget.room.permissions.canKick && !isProcessing;

    return SettingsControlRow(
      title: _memberDisplayName(request),
      description:
          'Requested access as ${request.identifier}. Approve lets them join; decline removes this request.',
      trailing: _JoinRequestActions(
        memberLabel: _memberLabel(request),
        isProcessing: isProcessing,
        onDecline: canDecline
            ? () => _handleJoinRequest(request, approve: false)
            : null,
        onApprove: canApprove
            ? () => _handleJoinRequest(request, approve: true)
            : null,
      ),
    );
  }

  String get _joinRequestsTitle {
    final count = _joinRequests.length;
    return count == 1 ? '1 pending request' : '$count pending requests';
  }

  Widget _buildPendingInvitesSection(BuildContext context) {
    return SettingsSection(
      title: 'Pending invites',
      showDivider: false,
      children: [
        SettingsStatePanel(
          icon: Icons.mail_outline,
          title: _pendingInvitesTitle,
          description:
              'People who have been invited but have not accepted yet. Revoke removes the invite.',
          tone: SettingsStatusTone.accent,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        ),
        for (final invite in _pendingInvites)
          _buildPendingInviteEntry(context, invite),
      ],
    );
  }

  Widget _buildPendingInviteEntry(BuildContext context, Member invite) {
    final isProcessing =
        _processingInviteIds.contains(invite.identifier) || _isSaving;
    final canRevoke = widget.room.permissions.canKick && !isProcessing;

    return SettingsControlRow(
      title: _memberDisplayName(invite),
      description:
          'Invited as ${invite.identifier}. Waiting for them to accept.',
      trailing: _PendingInviteActions(
        memberLabel: _memberLabel(invite),
        isProcessing: isProcessing,
        onRevoke: canRevoke ? () => _handleRevokeInvite(invite) : null,
      ),
    );
  }

  String get _pendingInvitesTitle {
    final count = _pendingInvites.length;
    return count == 1 ? '1 pending invite' : '$count pending invites';
  }

  Future<void> _handleRevokeInvite(Member invite) async {
    final pendingInviteActions = _pendingInviteActions;
    if (pendingInviteActions == null) {
      return;
    }

    setState(() {
      _processingInviteIds.add(invite.identifier);
    });

    await ErrorUtils.tryRun(context, () async {
      await pendingInviteActions.revokePendingInvite(invite.identifier);
      await _loadMembers();
    });

    if (!mounted) {
      return;
    }

    setState(() {
      _processingInviteIds.remove(invite.identifier);
    });
  }

  Widget _buildEntry(BuildContext context, int index) {
    final entry = _entries[index];
    if (entry is _RoleEntry) {
      return Align(
        alignment: Alignment.center,
        child: RoleView(
          name: entry.role.name,
          icon: entry.role.icon,
          powerLevel: entry.powerLevel,
        ),
      );
    }

    if (entry is _MemberEntry) {
      return _buildMember(entry, context);
    }

    return const SizedBox.shrink();
  }

  Widget _buildMember(_MemberEntry entry, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 6),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.72),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: MouseRegion(
          cursor: _canEdit
              ? WidgetStateMouseCursor.clickable
              : MouseCursor.defer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
            child: Row(
              children: [
                Icon(
                  Icons.drag_indicator,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: UserPanel(
                    key: ValueKey(
                      'room-member-settings-${entry.member.identifier}',
                    ),
                    client: widget.room.client,
                    initialMember: entry.member,
                    contextRoom: widget.room,
                    userId: entry.member.identifier,
                    detailOverride: entry.member.identifier,
                  ),
                ),
                if (entry.isChanged)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 4, 0),
                    child: Icon(
                      Icons.edit,
                      color: Theme.of(context).colorScheme.primary,
                      size: 15,
                    ),
                  ),
                tiamat.Text.tiny(_powerLevel(entry.role).toString()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (!_canEdit || _isSaving) {
      return;
    }

    setState(() {
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }

      final item = _entries[oldIndex];
      if (item is! _MemberEntry) {
        return;
      }

      final items = List<Object>.from(_entries)
        ..removeAt(oldIndex)
        ..insert(newIndex, item);

      if (!_isListValid(items)) {
        return;
      }

      _entries = items;
      _determineMemberRoles();
    });
  }

  bool _isListValid(List<Object> items) {
    if (items.isEmpty || items.first is! _RoleEntry) {
      return false;
    }

    _RoleEntry? previousRole;
    for (final item in items) {
      if (item is! _RoleEntry) {
        continue;
      }

      if (previousRole != null && previousRole.powerLevel < item.powerLevel) {
        return false;
      }

      previousRole = item;
    }

    return true;
  }

  void _determineMemberRoles() {
    _RoleEntry? currentRole;
    for (final entry in _entries) {
      if (entry is _RoleEntry) {
        currentRole = entry;
        continue;
      }

      if (entry is _MemberEntry && currentRole != null) {
        entry.role = currentRole.role;
      }
    }

    _isEdited = _members.any((entry) => entry.isChanged);
  }

  Future<void> _applySettings() async {
    setState(() {
      _isSaving = true;
    });

    var saved = false;
    var shouldSort = false;
    await ErrorUtils.tryRun(context, () async {
      final failures = <String>[];
      final changedMembers =
          _members.where((entry) => entry.isChanged).toList(growable: false)
            ..sort(_compareMemberSaveOrder);

      for (final member in changedMembers) {
        final targetRole = member.role;
        try {
          await widget.room.setMemberRole(member.member.identifier, targetRole);
          member.originalRole = targetRole;
          shouldSort = true;
        } catch (error, stackTrace) {
          Log.onError(error, stackTrace);
          failures.add('${_memberLabel(member.member)}: $error');
        }
      }

      if (failures.isNotEmpty) {
        final plural = failures.length == 1 ? '' : 's';
        throw Exception(
          'Failed to update ${failures.length} member role$plural:\n'
          '${failures.join('\n')}',
        );
      }

      await _loadMembers();
      saved = true;
    });

    if (!mounted) {
      return;
    }

    setState(() {
      _isSaving = false;
      _isEdited = _members.any((entry) => entry.isChanged);
      if (!saved && shouldSort) {
        _sortEntries();
      }
    });
  }

  Future<void> _handleJoinRequest(
    Member request, {
    required bool approve,
  }) async {
    final joinRequestActions = _joinRequestActions;
    if (joinRequestActions == null) {
      return;
    }

    setState(() {
      _processingJoinRequestIds.add(request.identifier);
    });

    await ErrorUtils.tryRun(context, () async {
      if (approve) {
        await joinRequestActions.approveJoinRequest(request.identifier);
      } else {
        await joinRequestActions.declineJoinRequest(request.identifier);
      }
      await _loadMembers();
    });

    if (!mounted) {
      return;
    }

    setState(() {
      _processingJoinRequestIds.remove(request.identifier);
    });
  }

  int _compareMemberSaveOrder(_MemberEntry left, _MemberEntry right) {
    final selfId = widget.room.client.self?.identifier;
    final leftSelfDemotion = _isSelfDemotion(left, selfId);
    final rightSelfDemotion = _isSelfDemotion(right, selfId);
    if (leftSelfDemotion != rightSelfDemotion) {
      return leftSelfDemotion ? 1 : -1;
    }

    final leftDemotion = _roleDelta(left) < 0;
    final rightDemotion = _roleDelta(right) < 0;
    if (leftDemotion != rightDemotion) {
      return leftDemotion ? 1 : -1;
    }

    return _powerLevel(right.role).compareTo(_powerLevel(left.role));
  }

  bool _isSelfDemotion(_MemberEntry member, String? selfId) {
    return selfId != null &&
        member.member.identifier == selfId &&
        _roleDelta(member) < 0;
  }

  int _roleDelta(_MemberEntry member) {
    return _powerLevel(member.role) - _powerLevel(member.originalRole);
  }

  Role _matchingAvailableRole(Role role) {
    final powerLevel = _powerLevel(role);
    for (final entry in _roles) {
      if (entry.powerLevel == powerLevel) {
        return entry.role;
      }
    }

    if (_roles.isNotEmpty && powerLevel > _roles.first.powerLevel) {
      return _roles.first.role;
    }

    return role;
  }

  void _sortEntries() {
    final entries = <Object>[..._roles, ..._members];

    entries.sort((left, right) {
      if (left is _RoleEntry && right is _RoleEntry) {
        return right.powerLevel.compareTo(left.powerLevel);
      }

      if (left is _RoleEntry && right is _MemberEntry) {
        final compare = right.currentPowerLevel.compareTo(left.powerLevel);
        return compare == 0 ? -1 : compare;
      }

      if (left is _MemberEntry && right is _RoleEntry) {
        final compare = right.powerLevel.compareTo(left.currentPowerLevel);
        return compare == 0 ? 1 : compare;
      }

      if (left is _MemberEntry && right is _MemberEntry) {
        final compare = right.currentPowerLevel.compareTo(
          left.currentPowerLevel,
        );
        if (compare != 0) {
          return compare;
        }

        return _memberSortName(
          left.member,
        ).compareTo(_memberSortName(right.member));
      }

      return 0;
    });

    _entries = entries;
    _isEdited = _members.any((entry) => entry.isChanged);
  }
}

String _memberLabel(Member member) {
  final displayName = member.displayName.trim();
  if (displayName.isEmpty || displayName == member.identifier) {
    return member.identifier;
  }

  return '$displayName (${member.identifier})';
}

String _memberDisplayName(Member member) {
  final displayName = member.displayName.trim();
  if (displayName.isEmpty || displayName == member.identifier) {
    return member.identifier;
  }

  return displayName;
}

String _memberSortName(Member member) {
  final displayName = member.displayName.trim();
  return (displayName.isEmpty ? member.identifier : displayName).toLowerCase();
}

class _JoinRequestActions extends StatelessWidget {
  const _JoinRequestActions({
    required this.memberLabel,
    required this.isProcessing,
    required this.onDecline,
    required this.onApprove,
  });

  final String memberLabel;
  final bool isProcessing;
  final VoidCallback? onDecline;
  final VoidCallback? onApprove;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackActions =
            constraints.hasBoundedWidth && constraints.maxWidth < 272;
        final decline = _JoinRequestActionButton(
          label: 'Decline',
          semanticLabel: 'Decline join request from $memberLabel',
          isLoading: isProcessing,
          onTap: onDecline,
          expand: stackActions,
        );
        final approve = _JoinRequestActionButton(
          label: 'Approve',
          semanticLabel: 'Approve join request from $memberLabel',
          isLoading: isProcessing,
          onTap: onApprove,
          primary: true,
          expand: stackActions,
        );

        if (stackActions) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [decline, const SizedBox(height: 8), approve],
          );
        }

        return Wrap(
          alignment: WrapAlignment.end,
          spacing: 8,
          runSpacing: 8,
          children: [decline, approve],
        );
      },
    );
  }
}

class _PendingInviteActions extends StatelessWidget {
  const _PendingInviteActions({
    required this.memberLabel,
    required this.isProcessing,
    required this.onRevoke,
  });

  final String memberLabel;
  final bool isProcessing;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final expand =
            constraints.hasBoundedWidth && constraints.maxWidth < 272;
        return Align(
          alignment: Alignment.centerRight,
          child: _JoinRequestActionButton(
            label: 'Revoke',
            semanticLabel: 'Revoke invite for $memberLabel',
            isLoading: isProcessing,
            onTap: onRevoke,
            expand: expand,
          ),
        );
      },
    );
  }
}

class _JoinRequestActionButton extends StatelessWidget {
  const _JoinRequestActionButton({
    required this.label,
    required this.semanticLabel,
    required this.isLoading,
    required this.onTap,
    required this.expand,
    this.primary = false,
  });

  final String label;
  final String semanticLabel;
  final bool isLoading;
  final VoidCallback? onTap;
  final bool expand;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: expand ? double.infinity : 124,
      child: primary
          ? tiamat.Button(text: label, isLoading: isLoading, onTap: onTap)
          : tiamat.Button.secondary(
              text: label,
              isLoading: isLoading,
              onTap: onTap,
            ),
    );

    return Semantics(
      label: semanticLabel,
      button: true,
      enabled: onTap != null,
      child: ExcludeSemantics(child: button),
    );
  }
}

class _RoleEntry {
  const _RoleEntry({required this.role, required this.powerLevel});

  final Role role;
  final int powerLevel;
}

class _MemberEntry {
  _MemberEntry({
    required this.member,
    required this.originalRole,
    required this.role,
  });

  final Member member;
  Role originalRole;
  Role role;

  bool get isChanged => _powerLevel(originalRole) != _powerLevel(role);

  int get currentPowerLevel => _powerLevel(role);
}

int _powerLevel(Role role) {
  if (role is MatrixRole) {
    return role.powerLevel;
  }

  return 0;
}
