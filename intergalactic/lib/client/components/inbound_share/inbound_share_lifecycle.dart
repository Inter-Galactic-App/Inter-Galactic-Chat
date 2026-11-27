import 'dart:io';

import 'package:flutter/services.dart';
import 'package:intergalactic/debug/log.dart';

import 'inbound_share_controller.dart';
import 'inbound_share_payload.dart';
import 'inbound_share_staging.dart';

abstract interface class InboundShareStagingRootProvider {
  Future<Directory> resolve();
}

class MethodChannelInboundShareStagingRootProvider
    implements InboundShareStagingRootProvider {
  const MethodChannelInboundShareStagingRootProvider();

  static const _channel = MethodChannel('chat.intergalactic.app/inbound_share');

  @override
  Future<Directory> resolve() async {
    final path = await _channel.invokeMethod<String>('inboundShareStagingRoot');
    if (path == null || path.isEmpty) {
      throw StateError('Inbound-share staging root is unavailable.');
    }
    return Directory(path);
  }
}

class InboundShareLifecycle {
  InboundShareLifecycle(this._rootProvider);

  final InboundShareStagingRootProvider _rootProvider;
  InboundShareController? _controller;

  InboundShareSession? get active => _controller?.active;

  Future<InboundShareAdmissionResult> admit(InboundSharePayload payload) async {
    try {
      final root = await _rootProvider.resolve();
      var controller = _controller;
      if (controller != null &&
          controller.staging.root.absolute.path != root.absolute.path) {
        if (controller.active != null) {
          return const InboundShareAdmissionResult(
            InboundShareAdmission.rejected,
            reason:
                'Inbound-share storage changed while a share was in progress.',
          );
        }
        // Nothing is in flight, so rebind to the new root. Keeping the stale
        // controller would reject every later share for the life of this
        // instance, because nothing else ever rebuilds it.
        await controller.cancelAll();
        controller = null;
      }
      controller ??= InboundShareController(InboundShareStaging(root));
      _controller = controller;
      final manifest = payload.stagingToken == null
          ? await controller.staging.createSession()
          : await controller.staging.claimExistingSession(
              payload.stagingToken!,
            );
      return controller.accept(manifest, payload);
    } catch (error, stackTrace) {
      // The caller only logs `result=rejected`, so without this a share that
      // fails to stage leaves no diagnostic anywhere.
      Log.onError(
        error,
        stackTrace,
        content: 'Failed to prepare an inbound share for review',
      );
      return const InboundShareAdmissionResult(
        InboundShareAdmission.rejected,
        reason: 'Could not prepare this share securely.',
      );
    }
  }

  Future<InboundShareSession?> finish(
    InboundShareSession session,
    InboundShareSessionState terminal,
  ) async {
    final controller = _controller;
    if (controller == null) return null;
    return controller.finish(session, terminal);
  }

  Future<void> cancelAll() async {
    await _controller?.cancelAll();
  }
}
