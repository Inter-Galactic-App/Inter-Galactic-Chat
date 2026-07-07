import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/client/matrix/matrix_member.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/ui/molecules/user_panel.dart';
import 'package:intergalactic/ui/navigation/adaptive_text_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/utils/error_utils.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class RoomNicknamesSettingsPage extends StatefulWidget {
  const RoomNicknamesSettingsPage({
    required this.room,
    super.key,
  });

  final MatrixRoom room;

  @override
  State<RoomNicknamesSettingsPage> createState() =>
      _RoomNicknamesSettingsPageState();
}

class _RoomNicknamesSettingsPageState extends State<RoomNicknamesSettingsPage> {
  late Future<List<Member>> _membersFuture;
  StreamSubscription<void>? _roomSubscription;
  String? _savingUserId;

  String? get _selfId => widget.room.client.self?.identifier;

  @override
  void initState() {
    super.initState();
    _membersFuture = _loadMembers();
    _roomSubscription = widget.room.onUpdate.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _roomSubscription?.cancel();
    super.dispose();
  }

  Future<List<Member>> _loadMembers() async {
    final members = widget.room.isMembersListComplete
        ? widget.room.membersList()
        : await widget.room.fetchMembersList();

    members.sort((left, right) {
      final leftIsSelf = left.identifier == _selfId;
      final rightIsSelf = right.identifier == _selfId;
      if (leftIsSelf != rightIsSelf) {
        return leftIsSelf ? -1 : 1;
      }
      return _baseDisplayName(left)
          .toLowerCase()
          .compareTo(_baseDisplayName(right).toLowerCase());
    });

    return members;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Member>>(
      future: _membersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: tiamat.Text.error(snapshot.error.toString()));
        }

        final members = snapshot.data ?? const <Member>[];
        final selfMember =
            _selfId == null ? null : _findMember(members, _selfId!);
        final otherMembers = members
            .where((member) => member.identifier != _selfId)
            .toList(growable: false);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsSection(
              title: 'Your nickname',
              children: [
                SettingsControlRow(
                  title: 'Room display name',
                  description:
                      'Set the name people see for you in this room. Leave it blank to use your normal display name.',
                ),
                if (selfMember != null)
                  _NicknameMemberCard(
                    room: widget.room,
                    member: selfMember,
                    baseDisplayName: _baseDisplayName(selfMember),
                    currentNickname: widget.room
                        .getMemberRoomDisplayName(selfMember.identifier),
                    canEdit: widget.room.permissions.canChangeOwnNickname,
                    isSaving: _savingUserId == selfMember.identifier,
                    onEdit: () => _editNickname(selfMember, isSelf: true),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: tiamat.Text.labelLow(
                      'Your room membership is still loading.',
                    ),
                  ),
              ],
            ),
            SettingsSection(
              title: 'Other members',
              showDivider: false,
              children: [
                SettingsControlRow(
                  title: 'Member nicknames',
                  description: widget.room.permissions.canChangeOtherNicknames
                      ? 'You can set room display names for other members.'
                      : 'You can view other member nicknames, but changing them requires room display-name permission.',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                  child: Column(
                    children: [
                      for (final member in otherMembers)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _NicknameMemberCard(
                            room: widget.room,
                            member: member,
                            baseDisplayName: _baseDisplayName(member),
                            currentNickname: widget.room
                                .getMemberRoomDisplayName(member.identifier),
                            canEdit:
                                widget.room.permissions.canChangeOtherNicknames,
                            isSaving: _savingUserId == member.identifier,
                            onEdit: () => _editNickname(member, isSelf: false),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  String _baseDisplayName(Member member) {
    if (member is MatrixMember) {
      return member.matrixUser.calcDisplayname();
    }

    return member.displayName;
  }

  Member? _findMember(List<Member> members, String userId) {
    for (final member in members) {
      if (member.identifier == userId) {
        return member;
      }
    }

    return null;
  }

  Future<void> _editNickname(Member member, {required bool isSelf}) async {
    final currentNickname = widget.room.getMemberRoomDisplayName(
      member.identifier,
    );
    final baseDisplayName = _baseDisplayName(member);

    final nickname = await AdaptiveTextDialog.show(
      context,
      title: isSelf ? 'Set Your Room Nickname' : 'Set Room Nickname',
      description:
          'Leave blank to clear the room nickname and use $baseDisplayName.',
      defaultText: currentNickname ?? '',
      placeholder: 'Room nickname',
    );

    if (nickname == null) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _savingUserId = member.identifier;
    });

    await ErrorUtils.tryRun(context, () async {
      final trimmed = nickname.trim();
      await widget.room.setMemberNickname(
        member.identifier,
        trimmed.isEmpty ? null : trimmed,
      );
    });

    if (!mounted) {
      return;
    }

    setState(() {
      _savingUserId = null;
      _membersFuture = _loadMembers();
    });
  }
}

class _NicknameMemberCard extends StatelessWidget {
  const _NicknameMemberCard({
    required this.room,
    required this.member,
    required this.baseDisplayName,
    required this.currentNickname,
    required this.canEdit,
    required this.isSaving,
    required this.onEdit,
  });

  final MatrixRoom room;
  final Member member;
  final String baseDisplayName;
  final String? currentNickname;
  final bool canEdit;
  final bool isSaving;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nickname = currentNickname?.trim();
    final hasNickname = nickname != null && nickname.isNotEmpty;

    return Opacity(
      opacity: canEdit ? 1 : 0.58,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.72),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            UserPanel(
              client: room.client,
              initialMember: member,
              contextRoom: room,
              userId: member.identifier,
              detailOverride: member.identifier,
            ),
            const SizedBox(height: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _NicknameInfoPill(
                  label: 'Display name',
                  value: baseDisplayName,
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 8),
                _NicknameInfoPill(
                  label: 'Nickname',
                  value: hasNickname ? nickname : 'Not set',
                  icon: Icons.badge_outlined,
                  muted: !hasNickname,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: canEdit && !isSaving ? onEdit : null,
                icon: isSaving
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : const Icon(Icons.edit_outlined, size: 18),
                label: Text(hasNickname ? 'Edit nickname' : 'Set nickname'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NicknameInfoPill extends StatelessWidget {
  const _NicknameInfoPill({
    required this.label,
    required this.value,
    required this.icon,
    this.muted = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = muted
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.36),
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 12,
              letterSpacing: 0,
            ),
          ),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontSize: 12,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
