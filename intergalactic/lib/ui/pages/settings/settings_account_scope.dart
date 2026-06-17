import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/main.dart';

class SettingsAccountController extends ChangeNotifier {
  SettingsAccountController({
    required this.clientManager,
    Client? initialClient,
  }) : _selectedClient = resolvePreferredClient(
          clientManager,
          fallback: initialClient,
        ) {
    _subscriptions.addAll([
      clientManager.onClientAdded.stream.listen(_handleClientListChanged),
      clientManager.onClientRemoved.stream.listen(_handleClientListChanged),
      clientManager.onClientUpdated.stream.listen((_) => notifyListeners()),
    ]);
  }

  final ClientManager clientManager;
  final List<StreamSubscription> _subscriptions = [];
  Client? _selectedClient;

  Client? get selectedClient =>
      _validClient(_selectedClient) ?? resolvePreferredClient(clientManager);

  List<Client> get clients => clientManager.clients;

  void selectClient(Client client) {
    if (!clientManager.clients.contains(client)) {
      return;
    }

    if (identical(_selectedClient, client)) {
      return;
    }

    _selectedClient = client;
    notifyListeners();
  }

  void _handleClientListChanged(dynamic _) {
    final nextClient =
        _validClient(_selectedClient) ?? resolvePreferredClient(clientManager);
    _selectedClient = nextClient;
    notifyListeners();
  }

  Client? _validClient(Client? client) {
    if (client == null || !clientManager.clients.contains(client)) {
      return null;
    }

    return client;
  }

  static Client? resolvePreferredClient(
    ClientManager? manager, {
    Client? fallback,
  }) {
    final clients = manager?.clients ?? const <Client>[];
    if (clients.isEmpty) {
      return null;
    }

    if (fallback != null && clients.contains(fallback)) {
      return fallback;
    }

    final focusedClientId = preferences.filterClient.value;
    if (focusedClientId != null) {
      for (final client in clients) {
        if (client.identifier == focusedClientId) {
          return client;
        }
      }
    }

    return clients.first;
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    super.dispose();
  }
}

class SettingsAccountScope
    extends InheritedNotifier<SettingsAccountController> {
  const SettingsAccountScope({
    required SettingsAccountController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static SettingsAccountController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<SettingsAccountScope>()
        ?.notifier;
  }

  static SettingsAccountController? maybeRead(BuildContext context) {
    final element =
        context.getElementForInheritedWidgetOfExactType<SettingsAccountScope>();
    final widget = element?.widget;
    if (widget is SettingsAccountScope) {
      return widget.notifier;
    }
    return null;
  }

  static Client? selectedClientOf(
    BuildContext context,
    ClientManager manager,
  ) {
    final controller = maybeOf(context);
    if (controller != null && identical(controller.clientManager, manager)) {
      return controller.selectedClient;
    }

    return SettingsAccountController.resolvePreferredClient(manager);
  }
}
