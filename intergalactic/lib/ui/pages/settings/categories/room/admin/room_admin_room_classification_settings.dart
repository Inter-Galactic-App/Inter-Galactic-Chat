import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/client/components/direct_messages/direct_message_component.dart';
import 'package:intergalactic/client/matrix/components/direct_messages/matrix_direct_messages_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/matrix_room_migration.dart';
import 'package:intergalactic/main.dart' show preferences;
import 'package:intergalactic/utils/event_bus.dart';
import 'package:intergalactic/ui/navigation/adaptive_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/ui/pages/settings/settings_status_components.dart';
import 'package:tiamat/tiamat.dart' as tiamat;
import 'package:matrix/matrix_api_lite/generated/model.dart' as matrix_api;

class RoomAdminRoomClassificationSettings extends StatefulWidget {
  const RoomAdminRoomClassificationSettings({required this.room, super.key});

  final MatrixRoom room;

  @override
  State<RoomAdminRoomClassificationSettings> createState() =>
      _RoomAdminRoomClassificationSettingsState();
}

class _RoomAdminRoomClassificationSettingsState
    extends State<RoomAdminRoomClassificationSettings> {
  bool _savingClassification = false;
  List<String> _stableVersions = const [];
  String? _selectedVersion;
  String? _versionLoadError;
  bool _loadingVersions = false;
  bool _migrating = false;
  int _versionLoadGeneration = 0;
  StreamSubscription<bool>? _developerModeSubscription;

  MatrixDirectMessagesComponent? get _directMessages =>
      widget.room.client.getComponent<MatrixDirectMessagesComponent>();

  DirectMessagesComponent? get _directMessageClassifier =>
      widget.room.client.getComponent<DirectMessagesComponent>();

  bool get _isDirectMessage =>
      _directMessageClassifier?.isRoomDirectMessage(widget.room) == true;

  String get _currentVersion => widget.room.matrixRoom.roomVersion ?? '1';

  bool get _canMigrate =>
      widget.room.matrixRoom.canChangeStateEvent('m.room.tombstone');

  String? get _successorRoomId => matrixRoomMigrationSuccessorId(widget.room);

  String? get _predecessorRoomId =>
      matrixRoomMigrationPredecessorId(widget.room);

  @override
  void initState() {
    super.initState();
    _developerModeSubscription = preferences.developerMode.onChanged.listen((
      enabled,
    ) {
      if (!mounted) return;
      setState(_clearRoomVersions);
      if (enabled) _loadRoomVersions();
    });
    if (preferences.developerMode.value) _loadRoomVersions();
  }

  @override
  void didUpdateWidget(RoomAdminRoomClassificationSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room == widget.room) return;
    _clearRoomVersions();
    if (preferences.developerMode.value) {
      final room = widget.room;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            identical(widget.room, room) &&
            preferences.developerMode.value) {
          _loadRoomVersions();
        }
      });
    }
  }

  @override
  void dispose() {
    unawaited(_developerModeSubscription?.cancel());
    super.dispose();
  }

  void _clearRoomVersions() {
    _versionLoadGeneration++;
    _stableVersions = const [];
    _selectedVersion = null;
    _versionLoadError = null;
    _loadingVersions = false;
  }

  Future<void> _loadRoomVersions() async {
    if (!preferences.developerMode.value) return;
    final generation = ++_versionLoadGeneration;
    final room = widget.room;
    setState(() => _loadingVersions = true);
    try {
      final capabilities = await room.matrixRoom.client.getCapabilities();
      final versions =
          capabilities.mRoomVersions?.available.entries
              .where(
                (entry) =>
                    entry.value == matrix_api.RoomVersionAvailable.stable,
              )
              .map((entry) => entry.key)
              .toList() ??
          <String>[];
      versions.sort(_compareRoomVersions);
      if (!mounted ||
          generation != _versionLoadGeneration ||
          !preferences.developerMode.value) {
        return;
      }
      setState(() {
        _stableVersions = versions;
        final defaultVersion = capabilities.mRoomVersions?.default$;
        _selectedVersion = versions.contains(defaultVersion)
            ? defaultVersion
            : versions.firstOrNull;
        _loadingVersions = false;
      });
    } catch (_) {
      if (!mounted ||
          generation != _versionLoadGeneration ||
          !preferences.developerMode.value) {
        return;
      }
      setState(() {
        _versionLoadError = 'The homeserver could not provide room versions.';
        _loadingVersions = false;
      });
    }
  }

  String? get _directMessagePartnerId {
    final selfId = widget.room.client.self?.identifier;
    if (selfId == null) {
      return null;
    }

    return MatrixDirectMessagesComponent.joinedOneToOnePartnerIdFromSnapshot(
      selfId: selfId,
      joinedMemberIds: widget.room.memberIds,
      isMembersListComplete: widget.room.isMembersListComplete,
      joinedMemberCount: widget.room.matrixRoom.summary.mJoinedMemberCount,
      isRoomInSpace: widget.room.isSpecialRoomType,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_buildConversationTypeSection(), _buildRoomVersionSection()],
    );
  }

  Widget _buildConversationTypeSection() {
    final isDirect = _isDirectMessage;
    final canConvertToDirect =
        _directMessagePartnerId != null &&
        _directMessages != null &&
        !_savingClassification;

    return SettingsSection(
      title: 'Conversation type',
      children: [
        SettingsControlRow(
          title: 'Current type',
          description: isDirect
              ? 'Direct message is a personal room-list classification. It does not change members, history, permissions, or the room on other accounts.'
              : 'Group room keeps this conversation in the regular room list for this account. It does not change members, history, permissions, or the room on other accounts.',
          semanticValue: isDirect ? 'Direct message' : 'Group room',
          trailing: SettingsStatusChip(
            icon: isDirect
                ? Icons.alternate_email_rounded
                : Icons.group_outlined,
            label: isDirect ? 'Direct message' : 'Group room',
            compactLabel: isDirect ? 'DM' : 'Group',
            semanticLabel: isDirect
                ? 'Current conversation type: direct message'
                : 'Current conversation type: group room',
            tone: isDirect
                ? SettingsStatusTone.accent
                : SettingsStatusTone.neutral,
          ),
        ),
        SettingsControlRow(
          title: isDirect
              ? 'Convert to group room'
              : 'Convert to direct message',
          description: isDirect
              ? 'Remove the direct-message classification for this account. A complete one-to-one room will stay a group room here.'
              : _directMessagePartnerId == null
              ? 'Direct messages require exactly one other known member in this room.'
              : 'Mark this one-to-one room as a direct message for this account.',
          trailing: tiamat.Button.secondary(
            text: isDirect ? 'Make group room' : 'Make direct message',
            isLoading: _savingClassification,
            onTap: isDirect
                ? _savingClassification || _directMessages == null
                      ? null
                      : () => unawaited(_convertToGroupRoom())
                : canConvertToDirect
                ? () => unawaited(_convertToDirectMessage())
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildRoomVersionSection() {
    if (!preferences.developerMode.value) {
      return _buildRoomVersionStatusSection();
    }

    final successorRoomId = _successorRoomId;
    if (successorRoomId != null) {
      return _buildRecoverySection(successorRoomId);
    }
    final selectedVersion = _selectedVersion;
    final predecessorRoomId = _predecessorRoomId;
    final dropdownVersion =
        selectedVersion ??
        (_stableVersions.isEmpty ? null : _stableVersions.first);
    final canStartMigration =
        _canMigrate &&
        !_loadingVersions &&
        !_migrating &&
        selectedVersion != null &&
        selectedVersion != _currentVersion;
    return SettingsSection(
      title: 'Matrix room version',
      children: [
        SettingsControlRow(
          title: 'Current Matrix room version',
          description:
              'This room currently uses Matrix room version $_currentVersion.',
          semanticValue: 'Room version $_currentVersion',
          trailing: SettingsStatusChip(
            icon: Icons.commit,
            label: 'Room v$_currentVersion',
            compactLabel: 'v$_currentVersion',
            semanticLabel: 'Current Matrix room version $_currentVersion',
            tone: SettingsStatusTone.neutral,
          ),
        ),
        if (predecessorRoomId != null)
          SettingsControlRow(
            title: 'Previous room history',
            description:
                'This room is the newer version of an earlier Matrix room. Open it to read messages that remain in that timeline.',
            semanticValue: 'Previous room history is available',
            trailing: tiamat.Button.secondary(
              text: 'Open history',
              onTap: () => EventBus.openRoom.add((
                predecessorRoomId,
                widget.room.client.identifier,
              )),
            ),
          ),
        SettingsControlRow(
          title: 'Migrate to a new room version',
          description: _migrationDescription(selectedVersion),
          trailing: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260, minWidth: 196),
            child: _loadingVersions
                ? const SizedBox(
                    height: 32,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : dropdownVersion == null
                ? const tiamat.Text.label('No stable version available')
                : tiamat.DropdownSelector<String>(
                    color: Theme.of(context).colorScheme.surfaceContainer,
                    value: dropdownVersion,
                    items: _stableVersions,
                    itemBuilder: (version) =>
                        tiamat.Text.label('Room v$version'),
                    onItemSelected: _canMigrate && !_migrating
                        ? (version) {
                            if (version != null)
                              setState(() => _selectedVersion = version);
                          }
                        : null,
                  ),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: tiamat.Button.secondary(
              text: 'Start migration',
              isLoading: _migrating,
              onTap: canStartMigration
                  ? () => _startMigration(selectedVersion)
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRoomVersionStatusSection() {
    return SettingsSection(
      title: 'Matrix room version',
      children: [
        SettingsControlRow(
          title: 'Current Matrix room version',
          description:
              'This room currently uses Matrix room version $_currentVersion.',
          semanticValue: 'Room version $_currentVersion',
          trailing: SettingsStatusChip(
            icon: Icons.commit,
            label: 'Room v$_currentVersion',
            compactLabel: 'v$_currentVersion',
            semanticLabel: 'Current Matrix room version $_currentVersion',
            tone: SettingsStatusTone.neutral,
          ),
        ),
      ],
    );
  }

  Widget _buildRecoverySection(String successorRoomId) {
    final canRecover = widget.room.permissions.canInviteUser && !_migrating;
    return SettingsSection(
      title: 'Room migration recovery',
      children: [
        SettingsControlRow(
          title: 'This room was replaced',
          description:
              'Matrix moved future activity to a successor room. Messages remain here; membership is not copied by the protocol.',
          semanticValue: 'Room migration recovery available',
          trailing: const SettingsStatusChip(
            icon: Icons.warning_amber_rounded,
            label: 'Recovery available',
            compactLabel: 'Recover',
            semanticLabel: 'Room migration recovery available',
            tone: SettingsStatusTone.warning,
          ),
        ),
        SettingsControlRow(
          title: 'Open successor room',
          description: 'Open the replacement room created by this upgrade.',
          trailing: tiamat.Button.secondary(
            text: 'Open successor',
            onTap: () => EventBus.openRoom.add((
              successorRoomId,
              widget.room.client.identifier,
            )),
          ),
        ),
        SettingsControlRow(
          title: 'Recover missing members',
          description: _migrating
              ? 'Recovery is checking the successor and will report success or a network timeout.'
              : (canRecover
                    ? 'Check the old and new rooms, then invite only members still missing. You can retry this safely after a failure.'
                    : 'Only a room admin who can invite members can finish this recovery.'),
          trailing: tiamat.Button.secondary(
            text: 'Recover members',
            isLoading: _migrating,
            onTap: canRecover ? _recoverMigration : null,
          ),
        ),
      ],
    );
  }

  String _migrationDescription(String? version) {
    if (!_canMigrate) return 'Only room admins can migrate this Matrix room.';
    if (_loadingVersions)
      return 'Checking stable room versions supported by this homeserver.';
    if (_versionLoadError != null) return _versionLoadError!;
    if (version == null)
      return 'This homeserver did not report a stable room version for migration.';
    if (version == _currentVersion)
      return 'This room already uses the selected stable version.';
    return 'Creates a successor room on version $version, then invites the current members. History remains in this room.';
  }

  Future<void> _startMigration(String version) async {
    final confirmed = await AdaptiveDialog.confirmation(
      context,
      title: 'Start room migration',
      prompt:
          'Matrix will create a successor room on version $version and tombstone this room. Existing messages stay here. Inter Galactic will invite the current members after the successor arrives; any failed invites can be retried from this room.',
      confirmationText: 'Create successor and migrate',
      dangerous: true,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _migrating = true);
    try {
      final result = await MatrixRoomMigration(
        widget.room.client as MatrixClient,
      ).upgrade(source: widget.room, targetVersion: version);
      if (!mounted) return;
      await _showMigrationResult(result);
      if (mounted && result.isComplete) {
        EventBus.openRoom.add((
          result.successorRoomId,
          widget.room.client.identifier,
        ));
      }
    } catch (error, stackTrace) {
      if (mounted) await AdaptiveDialog.showError(context, error, stackTrace);
    } finally {
      if (mounted) setState(() => _migrating = false);
    }
  }

  Future<void> _recoverMigration() async {
    setState(() => _migrating = true);
    try {
      final result = await MatrixRoomMigration(
        widget.room.client as MatrixClient,
      ).recover(source: widget.room);
      if (mounted) await _showMigrationResult(result);
    } catch (error, stackTrace) {
      if (mounted) await AdaptiveDialog.showError(context, error, stackTrace);
    } finally {
      if (mounted) setState(() => _migrating = false);
    }
  }

  Future<void> _showMigrationResult(MatrixRoomMigrationResult result) {
    final failed = result.failedMemberIds.length;
    final failedSpaces = result.failedSpaceIds.length;
    final permissionsFailed = !result.permissionsRestored;
    final remaining = [
      if (failed > 0) '$failed invite(s)',
      if (failedSpaces > 0)
        '$failedSpaces space membership change(s)${_migrationFailureDetail(result.spaceFailure)}',
      if (permissionsFailed)
        'the permission restore${_migrationFailureDetail(result.permissionFailure)}',
    ];
    return AdaptiveDialog.show(
      context,
      title: result.isComplete
          ? 'Migration ready'
          : 'Migration needs attention',
      builder: (context) => tiamat.Text.body(
        result.isComplete
            ? 'The successor room is ready. ${result.invitedMemberIds.length} member(s) were invited. Old messages remain in this room.${result.successorPermissionsPreserved ? ' Existing successor permissions were kept; review them if the initial restore failed.' : ''}'
            : '${result.invitedMemberIds.length} member(s) were invited. ${remaining.join(', ')} need another attempt. Return to this room and use Recover missing members to retry safely.',
      ),
    );
  }

  String _migrationFailureDetail(String? label) {
    return label == null ? '' : ' [$label]';
  }

  Future<void> _convertToDirectMessage() async {
    final partnerId = _directMessagePartnerId;
    final directMessages = _directMessages;
    if (partnerId == null || directMessages == null) {
      return;
    }

    final confirmed = await AdaptiveDialog.confirmation(
      context,
      title: 'Convert to direct message',
      prompt:
          'Mark this one-to-one room as a direct message for this account? This does not change membership, history, permissions, or how the room appears to other members.',
      confirmationText: 'Make direct message',
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _savingClassification = true);
    try {
      await directMessages.markRoomAsDirectMessage(
        widget.room,
        partnerId: partnerId,
      );
      if (mounted) {
        setState(() {});
      }
    } catch (error, stackTrace) {
      if (mounted) {
        await AdaptiveDialog.showError(context, error, stackTrace);
      }
    } finally {
      if (mounted) {
        setState(() => _savingClassification = false);
      }
    }
  }

  Future<void> _convertToGroupRoom() async {
    final directMessages = _directMessages;
    if (directMessages == null) {
      return;
    }

    final confirmed = await AdaptiveDialog.confirmation(
      context,
      title: 'Convert to group room',
      prompt:
          'Remove the direct-message classification for this account? This does not change membership, history, permissions, or how the room appears to other members.',
      confirmationText: 'Make group room',
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _savingClassification = true);
    try {
      await directMessages.markRoomAsGroup(widget.room);
      if (mounted) {
        setState(() {});
      }
    } catch (error, stackTrace) {
      if (mounted) {
        await AdaptiveDialog.showError(context, error, stackTrace);
      }
    } finally {
      if (mounted) {
        setState(() => _savingClassification = false);
      }
    }
  }
}

int _compareRoomVersions(String left, String right) {
  final leftNumber = int.tryParse(left);
  final rightNumber = int.tryParse(right);
  if (leftNumber != null && rightNumber != null) {
    return rightNumber.compareTo(leftNumber);
  }
  return left.compareTo(right);
}
