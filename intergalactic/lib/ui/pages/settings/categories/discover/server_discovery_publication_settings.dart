import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/server_discovery/server_discovery_models.dart';
import 'package:intergalactic/client/components/server_discovery/server_discovery_publication_controller.dart';
import 'package:intergalactic/client/components/server_discovery/server_discovery_service_factory.dart';
import 'package:intergalactic/ui/motion/inter_galactic_motion.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/ui/pages/settings/settings_status_components.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class ServerDiscoveryPublicationSettings extends StatefulWidget {
  const ServerDiscoveryPublicationSettings({
    this.room,
    this.space,
    super.key,
  }) : assert(room != null || space != null);

  final Room? room;
  final Space? space;

  @override
  State<ServerDiscoveryPublicationSettings> createState() =>
      _ServerDiscoveryPublicationSettingsState();
}

class _ServerDiscoveryPublicationSettingsState
    extends State<ServerDiscoveryPublicationSettings> {
  ServerDiscoveryPublicationController? _controller;
  Object? _targetObject;

  @override
  void initState() {
    super.initState();
    _syncController();
  }

  @override
  void didUpdateWidget(covariant ServerDiscoveryPublicationSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _syncController() {
    final targetObject = widget.room ?? widget.space;
    if (identical(_targetObject, targetObject)) {
      return;
    }

    _targetObject = targetObject;
    _controller?.dispose();

    final target = _targetFromWidget();
    final client = widget.room?.client ?? widget.space?.client;
    if (target == null || client == null) {
      _controller = null;
      return;
    }

    _controller = ServerDiscoveryPublicationController(
      service: createServerDiscoveryService(client),
      target: target,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_controller?.refresh());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const SizedBox.shrink();
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return SettingsSection(
          title: 'Discover',
          children: [
            SettingsControlRow(
              title: 'Homeserver directory',
              description: _description(controller),
              trailing: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 132),
                child: tiamat.Button.secondary(
                  text: _buttonText(controller),
                  isLoading: controller.isLoading || controller.isUpdating,
                  onTap: _buttonEnabled(controller)
                      ? () => unawaited(_toggle(controller))
                      : null,
                ),
              ),
              child: _PublicationStatusLine(controller: controller),
            ),
          ],
        );
      },
    );
  }

  ServerDiscoveryPublicationTarget? _targetFromWidget() {
    final room = widget.room;
    if (room != null) {
      return ServerDiscoveryPublicationTarget(
        identifier: room.identifier,
        type: ServerDiscoveryEntryType.room,
        canManage: room.permissions.canChangeVisibility,
      );
    }

    final space = widget.space;
    if (space != null) {
      return ServerDiscoveryPublicationTarget(
        identifier: space.identifier,
        type: ServerDiscoveryEntryType.space,
        canManage: space.permissions.canChangeVisibility,
      );
    }

    return null;
  }

  Future<void> _toggle(ServerDiscoveryPublicationController controller) {
    if (controller.isPublished) {
      return controller.unpublish();
    }
    return controller.publish();
  }

  bool _buttonEnabled(ServerDiscoveryPublicationController controller) {
    if (controller.isLoading || controller.isUpdating) {
      return false;
    }
    if (!controller.canManage) {
      return false;
    }
    final failure = controller.state?.failureKind;
    return failure != ServerDiscoveryFailureKind.unsupportedClient;
  }

  String _buttonText(ServerDiscoveryPublicationController controller) {
    if (controller.isLoading || controller.isUpdating) {
      return 'Loading...';
    }
    if (!controller.canManage) {
      return 'No permission';
    }
    return controller.isPublished ? 'Remove listing' : 'Publish';
  }

  String _description(ServerDiscoveryPublicationController controller) {
    final state = controller.state;
    final target = _targetLabel(controller);
    if (state == null || controller.isLoading) {
      return 'Checking whether this $target is listed in the selected homeserver directory.';
    }
    if (state.failureKind == ServerDiscoveryFailureKind.unsupportedClient) {
      return 'Discover is available for Matrix accounts.';
    }
    if (state.permissionDenied) {
      if (state.isPublished) {
        return 'This $target is listed in the homeserver directory, but your current role cannot change the listing.';
      }
      return 'This $target is not listed in the homeserver directory, and your current role cannot publish it.';
    }
    if (state.serverPolicyDenied) {
      return 'The homeserver refused this directory listing change.';
    }
    if (state.failureKind == ServerDiscoveryFailureKind.networkFailure) {
      return 'The homeserver directory could not be reached.';
    }
    if (state.isPublished) {
      return 'This $target appears in Discover for this homeserver. Removing the listing does not change access rules or room visibility.';
    }
    return 'Publishing lists this $target in Discover for this homeserver. It does not change join rules, room visibility, history visibility, encryption, aliases, or space membership.';
  }

  String _targetLabel(ServerDiscoveryPublicationController controller) {
    return controller.target.type == ServerDiscoveryEntryType.space
        ? 'space'
        : 'room';
  }
}

class _PublicationStatusLine extends StatelessWidget {
  const _PublicationStatusLine({required this.controller});

  final ServerDiscoveryPublicationController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    final tone = _tone(state);

    return AnimatedSwitcher(
      duration: InterGalacticMotion.duration(
        context,
        InterGalacticMotion.standard,
      ),
      switchInCurve: InterGalacticMotion.standardOut,
      switchOutCurve: InterGalacticMotion.standardIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SizeTransition(
            sizeFactor: animation,
            axisAlignment: -1,
            child: child,
          ),
        );
      },
      child: Wrap(
        key: ValueKey(_statusKey(state)),
        spacing: 8,
        runSpacing: 8,
        children: [
          SettingsStatusChip(
            icon: _icon(state),
            label: _label(state),
            compactLabel: _compactLabel(state),
            tone: tone,
          ),
          if (controller.isUpdating)
            const SettingsStatusChip(
              icon: Icons.sync,
              label: 'Updating',
              tone: SettingsStatusTone.accent,
            ),
        ],
      ),
    );
  }

  String _statusKey(ServerDiscoveryPublicationState? state) {
    return [
      controller.isLoading,
      controller.isUpdating,
      state?.isPublished,
      state?.permissionDenied,
      state?.serverPolicyDenied,
      state?.failureKind,
    ].join(':');
  }

  IconData _icon(ServerDiscoveryPublicationState? state) {
    if (controller.isLoading) {
      return Icons.sync;
    }
    if (state == null) {
      return Icons.help_outline;
    }
    if (state.permissionDenied) {
      return Icons.lock_outline;
    }
    if (state.failureKind != null) {
      return Icons.error_outline;
    }
    return state.isPublished ? Icons.public_rounded : Icons.public_off_outlined;
  }

  String _label(ServerDiscoveryPublicationState? state) {
    if (controller.isLoading) {
      return 'Checking';
    }
    if (state == null) {
      return 'Unknown';
    }
    if (state.permissionDenied) {
      return 'Permission required';
    }
    if (state.serverPolicyDenied) {
      return 'Server denied';
    }
    if (state.failureKind == ServerDiscoveryFailureKind.networkFailure) {
      return 'Network unavailable';
    }
    if (state.failureKind != null) {
      return 'Unavailable';
    }
    return state.isPublished ? 'Listed in Discover' : 'Not listed';
  }

  String? _compactLabel(ServerDiscoveryPublicationState? state) {
    if (controller.isLoading) {
      return 'Checking';
    }
    if (state == null) {
      return 'Unknown';
    }
    if (state.permissionDenied) {
      return 'No permission';
    }
    if (state.serverPolicyDenied) {
      return 'Server denied';
    }
    if (state.failureKind == ServerDiscoveryFailureKind.networkFailure) {
      return 'Network';
    }
    if (state.failureKind != null) {
      return 'Unavailable';
    }
    return state.isPublished ? 'Listed' : 'Not listed';
  }

  SettingsStatusTone _tone(ServerDiscoveryPublicationState? state) {
    if (controller.isLoading || state == null) {
      return SettingsStatusTone.neutral;
    }
    if (state.permissionDenied || state.failureKind != null) {
      return SettingsStatusTone.danger;
    }
    return state.isPublished
        ? SettingsStatusTone.accent
        : SettingsStatusTone.neutral;
  }
}
