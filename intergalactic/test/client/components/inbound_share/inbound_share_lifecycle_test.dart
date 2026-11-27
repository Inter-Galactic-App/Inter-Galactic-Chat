import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_controller.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_lifecycle.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_payload.dart';

class _RootProvider implements InboundShareStagingRootProvider {
  _RootProvider(this.root);
  final Directory root;

  @override
  Future<Directory> resolve() async => root;
}

InboundSharePayload _payload(String token, String name) => InboundSharePayload(
  stagingToken: token,
  items: [
    InboundShareItem.file(
      InboundShareFile(displayName: name, stagingPath: 'unused', size: 1),
    ),
  ],
);

void main() {
  test(
    'claims native sessions and releases them at their terminal states',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'ig_inbound_lifecycle_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      const firstToken = '123e4567-e89b-12d3-a456-426614174000';
      const secondToken = '123e4567-e89b-12d3-a456-426614174001';
      final firstDirectory = Directory(
        '${root.path}${Platform.pathSeparator}$firstToken',
      );
      final secondDirectory = Directory(
        '${root.path}${Platform.pathSeparator}$secondToken',
      );
      await firstDirectory.create();
      await secondDirectory.create();
      final lifecycle = InboundShareLifecycle(_RootProvider(root));

      final first = await lifecycle.admit(_payload(firstToken, 'first.jpg'));
      final second = await lifecycle.admit(_payload(secondToken, 'second.jpg'));

      expect(first.admission, InboundShareAdmission.active);
      expect(second.admission, InboundShareAdmission.queued);
      final promoted = await lifecycle.finish(
        first.session!,
        InboundShareSessionState.cancelled,
      );
      expect(await firstDirectory.exists(), isFalse);
      expect(promoted, same(second.session));
      expect(promoted?.state, InboundShareSessionState.reviewing);

      await lifecycle.finish(
        second.session!,
        InboundShareSessionState.completed,
      );
      expect(await secondDirectory.exists(), isFalse);
    },
  );
}
