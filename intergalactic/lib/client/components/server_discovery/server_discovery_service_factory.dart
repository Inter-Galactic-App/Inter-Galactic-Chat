import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/matrix/components/server_discovery/matrix_server_discovery_service.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';

import 'server_discovery_models.dart';
import 'server_discovery_service.dart';

ServerDiscoveryService createServerDiscoveryService(Client? client) {
  if (client is MatrixClient) {
    return MatrixServerDiscoveryService(client);
  }

  return UnsupportedServerDiscoveryService(
    scope: ServerDiscoveryScope(
      accountId: client?.identifier ?? 'none',
      homeserver: 'unsupported',
    ),
  );
}
