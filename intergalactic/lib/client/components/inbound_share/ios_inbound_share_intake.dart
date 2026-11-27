import 'dart:io';

import 'inbound_share_lifecycle.dart';
import 'inbound_share_payload.dart';
import 'ios_inbound_share_stager.dart';

/// Converts an opaque iOS native handoff token into a reviewable payload.
///
/// The token is deliberately the only value accepted from the host app. The
/// manifest remains untrusted App Group data and is read only after the token
/// passes the same grammar enforced by native staging ownership.
class IosInboundShareIntake {
  const IosInboundShareIntake(
    this._rootProvider, {
    IosInboundShareStager? stager,
  }) : _stager = stager ?? const IosInboundShareStager();

  static final _token = RegExp(r'^[a-f0-9-]{16,64}$');

  final InboundShareStagingRootProvider _rootProvider;
  final IosInboundShareStager _stager;

  Future<InboundSharePayload?> readToken(Object? value) async {
    if (value is! String || !_token.hasMatch(value)) return null;
    final root = await _rootProvider.resolve();
    final sessionRoot = Directory(
      '${root.path}${Platform.pathSeparator}$value',
    );
    return _stager.read(sessionRoot.path, token: value);
  }
}
