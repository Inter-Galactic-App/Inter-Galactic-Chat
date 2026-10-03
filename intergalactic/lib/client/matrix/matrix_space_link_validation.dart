/// Matrix Space links require a non-empty list of usable server names.
bool hasValidSpaceVia(Object? via) {
  if (via is! List || via.isEmpty) return false;
  return via.every((server) {
    if (server is! String || server.isEmpty || server.trim() != server) {
      return false;
    }
    final uri = Uri.tryParse('https://$server');
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.path.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return false;
    }
    try {
      // Accessing port also rejects a malformed non-numeric port.
      uri.port;
      return server.startsWith('[')
          ? RegExp(r'^\[[0-9A-Fa-f:.]+\](?::[0-9]{1,5})?$').hasMatch(server)
          : RegExp(r'^[A-Za-z0-9.-]+(?::[0-9]{1,5})?$').hasMatch(server);
    } on FormatException {
      return false;
    }
  });
}
