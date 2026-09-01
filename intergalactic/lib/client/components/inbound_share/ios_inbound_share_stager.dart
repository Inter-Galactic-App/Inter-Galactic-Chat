import 'dart:convert';
import 'dart:io';

import 'package:intergalactic/client/components/inbound_share/inbound_share_payload.dart';

/// Reads the manifest the iOS Share Extension leaves in the App Group session
/// directory and turns it into the same [InboundSharePayload] the Android
/// stager produces.
///
/// The extension runs in a different process and finishes before the host is
/// even launched, so unlike Android there is no live channel result to trust -
/// the manifest is the entire handoff. It is therefore treated as untrusted
/// input: every entry is validated, and a file reference is resolved *inside*
/// the session root or dropped.
class IosInboundShareStager {
  const IosInboundShareStager();

  static const manifestFileName = 'manifest.json';
  static const supportedSchemaVersion = 1;

  /// Reads and validates the manifest under [sessionRoot].
  ///
  /// Returns null when there is nothing usable to review. A null here means the
  /// caller should release staging and show nothing, which is the same outcome
  /// as a cancelled share.
  Future<InboundSharePayload?> read(
    String sessionRoot, {
    required String token,
  }) async {
    final manifest = File(
      '$sessionRoot${Platform.pathSeparator}$manifestFileName',
    );
    if (!await manifest.exists()) return null;

    Object? decoded;
    try {
      decoded = jsonDecode(await manifest.readAsString());
    } on FormatException {
      // A truncated manifest is the expected shape of "the extension was killed
      // mid-write", not an exceptional case worth propagating.
      return null;
    } on FileSystemException {
      // The session can be swept between the existence check and the read, so
      // the read is racy by construction. That is the same outcome as a missing
      // manifest, and it must not escape into IosInboundShareIntake.readToken.
      return null;
    }
    if (decoded is! Map) return null;

    final version = decoded['schemaVersion'];
    // Refuse a newer manifest rather than guessing at fields this build does
    // not know about.
    if (version is! int || version != supportedSchemaVersion) return null;

    final body = _trimmedOrNull(decoded['body']);
    final rawItems = decoded['items'];
    final items = <InboundShareItem>[];
    if (body != null) items.add(InboundShareItem.text(body));

    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        final file = _fileFrom(raw, sessionRoot: sessionRoot);
        if (file != null) items.add(InboundShareItem.file(file));
      }
    }

    if (items.isEmpty) return null;
    final payload = InboundSharePayload(
      items: items,
      body: body,
      stagingToken: token,
      // Optional and additive, so a manifest written before this field existed
      // still reads cleanly at the same schemaVersion.
      preselectedRoomId: _trimmedOrNull(decoded['conversationId']),
    );
    return payload.hasUsableContent ? payload : null;
  }

  InboundShareFile? _fileFrom(
    Map<dynamic, dynamic> raw, {
    required String sessionRoot,
  }) {
    final failure = _trimmedOrNull(raw['failure']);
    final displayName = _trimmedOrNull(raw['name']) ?? 'shared-file';

    // A failed entry carries no file, but is still surfaced so the review sheet
    // can tell the user something did not come through instead of silently
    // dropping it.
    if (failure != null) {
      return InboundShareFile(
        displayName: displayName,
        stagingPath: '',
        size: 0,
        mimeType: _trimmedOrNull(raw['mimeType']),
        failure: failure,
      );
    }

    final relative = _trimmedOrNull(raw['file']);
    if (relative == null) return null;
    final resolved = _resolveInside(sessionRoot, relative);
    // The manifest is written by another process. A `file` that escapes the
    // session root - absolute, or climbing out with `..` - is the one thing
    // here that could reach arbitrary app data, so it is dropped rather than
    // read.
    if (resolved == null) return null;

    final size = raw['size'];
    if (size is! int || size < 0) return null;

    return InboundShareFile(
      displayName: displayName,
      stagingPath: resolved,
      size: size,
      mimeType: _trimmedOrNull(raw['mimeType']),
    );
  }

  /// Resolves [relative] under [root], or null if it does not stay inside.
  static String? _resolveInside(String root, String relative) {
    if (relative.isEmpty) return null;
    // Only a bare file name is legitimate; the extension writes items directly
    // into the session root.
    if (relative.contains('/') || relative.contains(r'\')) return null;
    if (relative == '.' || relative == '..') return null;
    final normalizedRoot = root.endsWith(Platform.pathSeparator)
        ? root.substring(0, root.length - 1)
        : root;
    return '$normalizedRoot${Platform.pathSeparator}$relative';
  }

  static String? _trimmedOrNull(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
