import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_controller.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_draft.dart';
import 'package:intergalactic/ui/pages/inbound_share/inbound_share_destination_model.dart';
import 'package:intergalactic/ui/pages/inbound_share/inbound_share_destination_page.dart';
import 'package:intergalactic/utils/event_bus.dart';

class InboundShareReviewLauncher {
  @visibleForTesting
  static T? uniquePreselectedDestination<T extends Object>(
    Iterable<T> destinations,
    bool Function(T destination) matches,
  ) {
    T? match;
    for (final destination in destinations) {
      if (!matches(destination)) continue;
      if (match != null) return null;
      match = destination;
    }
    return match;
  }

  static Future<void> launch(
    BuildContext context, {
    required InboundShareSession session,
    required Iterable<Client> clients,
    required String Function(Client client) accountLabel,
    required InboundShareTerminalHandler onTerminal,
  }) async {
    final clientSnapshot = clients.toList(growable: false);
    List<InboundShareDestination> destinations() =>
        InboundShareDestinations.fromClients(
          clientSnapshot,
          accountLabel: accountLabel,
        );

    final initialDestinations = destinations();

    // The share sheet may already have named the conversation (iOS supplies an
    // INSendMessageIntent when the user picked a suggestion). Going straight
    // there skips a picker the user has effectively already used.
    //
    // Only when the room still resolves AND is still sendable - a stale or
    // demoted room falls back to the picker rather than dropping the share.
    final preselected = session.payload.preselectedRoomId;
    if (preselected != null) {
      // A Matrix room id does not identify an account. If more than one
      // signed-in account is joined to the same room, selecting either one
      // here would silently violate the exact client/room routing contract.
      // Treat that as ambiguous and let the account-labelled picker resolve it.
      final match = uniquePreselectedDestination(
        initialDestinations,
        (d) =>
            d.room.identifier == preselected &&
            d.room.permissions.canSendMessage,
      );
      if (match != null) {
        EventBus.inboundShareDraft.add(
          InboundShareDraft(
            room: match.room,
            payload: session.payload,
            session: session,
            onTerminal: onTerminal,
          ),
        );
        return;
      }
    }

    if (!context.mounted) return;
    // The route result is the only signal that survives an implicit dismissal:
    // a system back pops this route without running onCancelled, which would
    // otherwise leave the session pending and its staged bytes on disk.
    final selected = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (routeContext) => InboundShareDestinationPage(
          destinations: initialDestinations,
          refreshDestinations: destinations,
          onCancelled: () {
            Navigator.of(routeContext).pop(false);
          },
          onSelected: (destination) {
            if (!destination.room.permissions.canSendMessage) {
              ScaffoldMessenger.of(routeContext).showSnackBar(
                const SnackBar(
                  content: Text('This conversation is no longer available.'),
                ),
              );
              return;
            }
            EventBus.inboundShareDraft.add(
              InboundShareDraft(
                room: destination.room,
                payload: session.payload,
                session: session,
                onTerminal: onTerminal,
              ),
            );
            Navigator.of(routeContext).pop(true);
          },
        ),
      ),
    );
    if (selected != true) {
      await onTerminal(InboundShareSessionState.cancelled);
    }
  }
}
