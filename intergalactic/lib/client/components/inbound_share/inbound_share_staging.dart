import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:mime/mime.dart' as mime;

import 'inbound_share_manifest.dart';
import 'inbound_share_payload.dart';

class InboundShareStaging {
  InboundShareStaging(this.root, {Random? random})
    : _random = random ?? Random.secure();
  final Directory root;
  final Random _random;
  final Set<String> _ownedRoots = {};

  Future<InboundShareManifest> createSession() async {
    await root.create(recursive: true);
    final token = List.generate(
      24,
      (_) => _random.nextInt(16).toRadixString(16),
    ).join();
    final sessionRoot = Directory(
      '${root.path}${Platform.pathSeparator}$token',
    );
    await sessionRoot.create();
    _ownedRoots.add(_normalized(sessionRoot.path));
    return InboundShareManifest(
      token: token,
      sessionRoot: sessionRoot.path,
      createdAt: DateTime.now(),
    );
  }

  Future<InboundShareManifest> claimExistingSession(String token) async {
    if (!RegExp(r'^[a-f0-9-]{16,64}$').hasMatch(token)) {
      throw ArgumentError.value(token, 'token', 'Invalid inbound-share token.');
    }
    await root.create(recursive: true);
    final sessionRoot = Directory(
      '${root.path}${Platform.pathSeparator}$token',
    );
    if (!await sessionRoot.exists()) {
      throw StateError('Inbound-share session does not exist.');
    }
    final normalized = _normalized(sessionRoot.path);
    if (!_ownedRoots.add(normalized)) {
      throw StateError('Inbound-share session has already been claimed.');
    }
    return InboundShareManifest(
      token: token,
      sessionRoot: sessionRoot.path,
      createdAt: DateTime.now(),
    );
  }

  Future<InboundShareFile> stageBytes(
    InboundShareManifest manifest,
    Uint8List bytes, {
    required String name,
    String? mimeType,
    String? failure,
  }) async {
    _assertOwned(manifest.sessionRoot);
    final clean = sanitizeDisplayName(name);
    final file = File(
      '${manifest.sessionRoot}${Platform.pathSeparator}${_opaqueName()}',
    );
    await file.writeAsBytes(bytes, flush: true);
    return InboundShareFile(
      displayName: clean,
      stagingPath: file.path,
      size: bytes.length,
      mimeType: mimeType ?? mime.lookupMimeType(clean, headerBytes: bytes),
      failure: failure,
    );
  }

  Future<void> release(InboundShareManifest manifest) async {
    final normalized = _normalized(manifest.sessionRoot);
    if (!_ownedRoots.contains(normalized)) return;
    final directory = Directory(manifest.sessionRoot);
    if (await directory.exists()) await directory.delete(recursive: true);
    // Ownership is dropped only once the bytes are gone. Dropping it first
    // would make a failed delete unrecoverable: the retry returns early and
    // _assertOwned then refuses every further operation on that session.
    _ownedRoots.remove(normalized);
  }

  String sanitizeDisplayName(String input) {
    var stripped = input
        .replaceAll(
          RegExp(r'[\\/:*?"<>|\x00-\x1F\x7F\u202A-\u202E\u2066-\u2069]'),
          '',
        )
        .trim();
    while (stripped.contains('..')) {
      stripped = stripped.replaceAll('..', '');
    }
    return stripped.isEmpty
        ? 'shared-file'
        : stripped.substring(0, min(stripped.length, 120));
  }

  String _opaqueName() =>
      'item_${List.generate(20, (_) => _random.nextInt(16).toRadixString(16)).join()}.bin';
  String _normalized(String value) => Directory(value).absolute.path;
  void _assertOwned(String sessionRoot) {
    if (!_ownedRoots.contains(_normalized(sessionRoot)))
      throw StateError('Staging path is not an owned inbound-share session.');
  }
}
