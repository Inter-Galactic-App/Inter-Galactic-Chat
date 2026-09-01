import 'dart:async';
import 'dart:io';

const Duration _dnsLookupTimeout = Duration(seconds: 2);

Future<bool> isDirectFetchDnsSafe(Uri uri) async {
  final host = uri.host.trim();
  if (host.isEmpty) {
    return false;
  }

  try {
    final addresses = await InternetAddress.lookup(host).timeout(
      _dnsLookupTimeout,
    );
    return addresses.isNotEmpty && addresses.every(_isSafeAddress);
  } on SocketException {
    return false;
  } on TimeoutException {
    return false;
  }
}

bool _isSafeAddress(InternetAddress address) {
  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4 && bytes.length == 4) {
    return !_isBlockedIpv4(bytes);
  }

  if (address.type == InternetAddressType.IPv6 && bytes.length == 16) {
    return !_isBlockedIpv6(bytes);
  }

  return false;
}

bool _isBlockedIpv4(List<int> bytes) {
  final first = bytes[0];
  final second = bytes[1];
  final third = bytes[2];

  return first == 0 ||
      first == 10 ||
      first == 127 ||
      (first == 100 && second >= 64 && second <= 127) ||
      (first == 169 && second == 254) ||
      (first == 172 && second >= 16 && second <= 31) ||
      (first == 192 && second == 168) ||
      (first == 192 && second == 0) ||
      (first == 192 && second == 0 && third == 2) ||
      (first == 198 && (second == 18 || second == 19)) ||
      (first == 198 && second == 51 && third == 100) ||
      (first == 203 && second == 0 && third == 113) ||
      first >= 224;
}

bool _isBlockedIpv6(List<int> bytes) {
  final isUnspecified = bytes.every((byte) => byte == 0);
  final isLoopback =
      bytes.take(15).every((byte) => byte == 0) && bytes.last == 1;
  final isIpv4Mapped = bytes.take(10).every((byte) => byte == 0) &&
      bytes[10] == 0xff &&
      bytes[11] == 0xff;

  if (isIpv4Mapped) {
    return _isBlockedIpv4(bytes.sublist(12, 16));
  }

  return isUnspecified ||
      isLoopback ||
      (bytes[0] & 0xfe) == 0xfc ||
      (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) ||
      bytes[0] == 0xff ||
      (bytes[0] == 0x20 &&
          bytes[1] == 0x01 &&
          bytes[2] == 0x0d &&
          bytes[3] == 0xb8);
}
