import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/invitation/invitation_component.dart';
import 'package:intergalactic/ui/organisms/invitation_view/single_invitation_component_view.dart';
import 'package:flutter/material.dart';

class IncomingInvitationsWidget extends StatefulWidget {
  const IncomingInvitationsWidget(this.manager, {super.key, this.filterClient});

  final ClientManager manager;
  final Client? filterClient;

  @override
  State<IncomingInvitationsWidget> createState() =>
      _IncomingInvitationsWidgetState();
}

class _IncomingInvitationsWidgetState extends State<IncomingInvitationsWidget> {
  @override
  Widget build(BuildContext context) {
    var components = widget.manager.clients
        .where((client) =>
            widget.filterClient == null || client == widget.filterClient)
        .map((element) => element.getComponent<InvitationComponent>())
        .nonNulls
        .toList(growable: false);

    if (components.isEmpty) {
      return Container();
    }

    return Column(
      children: [
        for (var comp in components)
          if (comp.invitations.isNotEmpty)
            SingleInvitationComponentIncomingView(
              comp,
              showCurrentUserId: widget.filterClient == null &&
                  widget.manager.clients.length > 1,
            )
      ],
    );
  }
}
