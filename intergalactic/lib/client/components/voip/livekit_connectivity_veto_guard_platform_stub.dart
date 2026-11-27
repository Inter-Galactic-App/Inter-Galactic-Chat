/// Web has no Windows host and no `NetworkInterface` to enumerate.
///
/// Both answers are the "do nothing" answer: the guard is not installed, and if
/// something installed it anyway the probe never overrides a `none` verdict.
bool get isWindowsHost => false;

Future<bool> defaultNetworkAddressProbe() async => false;
