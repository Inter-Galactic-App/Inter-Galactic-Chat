import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_lifecycle.dart';
import 'package:intergalactic/client/components/inbound_share/ios_inbound_share_intake.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('ios-inbound-share-intake-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('reads a valid native token from its App Group session', () async {
    const token = 'a1b2c3d4e5f60718';
    final session = Directory('${root.path}${Platform.pathSeparator}$token');
    await session.create();
    await File(
      '${session.path}${Platform.pathSeparator}manifest.json',
    ).writeAsString('{"schemaVersion":1,"body":"from iOS","items":[]}');

    final intake = IosInboundShareIntake(_RootProvider(root));
    final payload = await intake.readToken(token);

    expect(payload?.stagingToken, token);
    expect(payload?.body, 'from iOS');
  });

  test(
    'rejects an invalid native token before resolving the App Group root',
    () async {
      final provider = _RootProvider(root);
      final intake = IosInboundShareIntake(provider);

      expect(await intake.readToken('../not-a-token'), isNull);
      expect(provider.resolveCalls, 0);
    },
  );

  test('rejects values outside the staging token grammar', () async {
    // The grammar is the boundary that keeps a token inside one path segment,
    // and it has to stay aligned with InboundShareSessionStore.isToken on the
    // Swift side, so the edges are pinned here as well.
    final provider = _RootProvider(root);
    final intake = IosInboundShareIntake(provider);

    expect(await intake.readToken(null), isNull);
    expect(await intake.readToken(42), isNull);
    expect(await intake.readToken('A' * 16), isNull);
    expect(await intake.readToken('a' * 15), isNull);
    expect(await intake.readToken('a' * 65), isNull);
    expect(provider.resolveCalls, 0);
  });

  test('returns null when the session was already swept', () async {
    // The normal outcome once native cleanup has removed the session: a valid
    // token with nothing behind it must not throw.
    final intake = IosInboundShareIntake(_RootProvider(root));

    expect(await intake.readToken('a' * 16), isNull);
  });
}

class _RootProvider implements InboundShareStagingRootProvider {
  _RootProvider(this.root);

  final Directory root;
  var resolveCalls = 0;

  @override
  Future<Directory> resolve() async {
    resolveCalls++;
    return root;
  }
}
