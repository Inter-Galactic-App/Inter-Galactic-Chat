import 'dart:io';

bool get isWindowsHost => Platform.isWindows;

/// True when some non-loopback interface holds a routable address.
///
/// Link-local addresses are excluded on purpose: `169.254.x.x` (IPv4) and
/// `fe80::` (IPv6) are what Windows assigns when DHCP never answered, so an
/// interface holding only those is evidence of *no* network rather than of one.
/// On the affected workstation **six** interfaces hold nothing else - a dead
/// Ethernet, the Surfshark tunnel, Wi-Fi, Bluetooth and two `Local Area
/// Connection*` stubs - so the distinction is not academic.
///
/// **Be honest about how much this actually discriminates.** Measured on that
/// same machine, Hyper-V's `vEthernet (Default Switch)` (`172.24.96.1`), the WSL
/// switch (`172.26.80.1`) and Tailscale (`100.103.121.52`) all present routable
/// addresses that exist whether or not the physical network is up. On any
/// machine with Hyper-V, WSL or a mesh VPN this probe is therefore close to
/// always-true, and the guard reduces to "never let `none` refuse a join".
///
/// That is the trade-off Route A accepted deliberately, not an oversight: a
/// genuinely offline join now fails on a real socket error, which is recoverable
/// on its own, instead of being refused by a verdict that never clears. Do not
/// "improve" this by pattern-matching virtual adapter names - that is fragile
/// and would buy back very little. If a stricter signal is ever wanted, the
/// honest one is a real reachability check, not a richer interface heuristic.
Future<bool> defaultNetworkAddressProbe() async {
  try {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      includeLinkLocal: false,
    );
    return interfaces.any((interface) => interface.addresses.any(_isRoutable));
  } on Object {
    // Enumeration failing is not evidence either way, so leave the plugin's
    // verdict alone rather than overriding on a guess.
    return false;
  }
}

bool _isRoutable(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal) {
    return false;
  }
  // `includeLinkLocal: false` covers this on most platforms, but it is
  // advisory on Windows and APIPA addresses have been observed through it.
  return !address.address.startsWith('169.254.');
}
