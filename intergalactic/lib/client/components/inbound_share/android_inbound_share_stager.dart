import 'package:flutter/services.dart';
import 'package:intergalactic/client/components/inbound_share/android_inbound_share_bridge.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_payload.dart';
import 'package:intergalactic/debug/log.dart';

abstract interface class AndroidInboundShareStagingPlatform {
  Future<List<AndroidInboundShareStageEntry>> stage(List<Uri> uris);

  /// Diagnostic only, and on the interface so a fake can drive it.
  ///
  /// Returns null rather than throwing when the native side cannot answer - an
  /// older build with no handler, a channel error. Nothing downstream reads the
  /// snapshot, so a failure here must never be able to stop the share it was
  /// only meant to describe.
  Future<AndroidInboundShareGrantSnapshot?> grantSnapshot(List<Uri> uris);
}

class AndroidInboundShareGrantSnapshot {
  const AndroidInboundShareGrantSnapshot({
    required this.action,
    required this.intentReadGrant,
    required this.activityStreamCount,
    required this.clipItemCount,
    required this.requestedStreamCount,
    required this.requestedStreamHash,
    required this.requestedReadGrantCount,
  });
  factory AndroidInboundShareGrantSnapshot.fromPlatformMap(Object? value) {
    if (value is! Map)
      throw const FormatException('Invalid inbound-share grant snapshot.');
    String text(String key) =>
        value[key] is String ? value[key] as String : 'unknown';
    int count(String key) => value[key] is int ? value[key] as int : -1;
    return AndroidInboundShareGrantSnapshot(
      action: text('action'),
      intentReadGrant: value['intent_read_grant'] == true,
      activityStreamCount: count('activity_stream_count'),
      clipItemCount: count('clip_item_count'),
      requestedStreamCount: count('requested_stream_count'),
      requestedStreamHash: text('requested_stream_hash'),
      requestedReadGrantCount: count('requested_read_grant_count'),
    );
  }
  final String action;
  final bool intentReadGrant;
  final int activityStreamCount;
  final int clipItemCount;
  final int requestedStreamCount;
  final String requestedStreamHash;
  final int requestedReadGrantCount;
  String toLogFields() =>
      'action=$action intent_read_grant=$intentReadGrant activity_stream_count=$activityStreamCount clip_item_count=$clipItemCount requested_stream_count=$requestedStreamCount requested_stream_hash=$requestedStreamHash requested_read_grant_count=$requestedReadGrantCount';
}

/// Classifies a native staging failure so the user gets a message matching what
/// actually went wrong.
///
/// Reads the `reason=` token native puts in the `PlatformException` details,
/// which native derives from the exception type and the live grant check.
/// Deliberately NOT parsed from the exception message: when every item fails,
/// that message is always "No shared content could be staged." whatever the
/// cause, so the structured field is the only place the reason survives.
///
/// The distinction earns its keep - a refused grant and an oversized file are
/// both "the share did nothing" to the user, but only one is fixed by sharing a
/// link instead. Ordered so the most actionable answer wins when a multi-item
/// share failed several ways at once.
InboundShareFailure androidInboundShareFailureFromDetails(Object? details) {
  final detail = details is String ? details : '';
  if (detail.contains('reason=permission_denied')) {
    return InboundShareFailure.permissionDenied;
  }
  if (detail.contains('reason=too_large')) {
    return InboundShareFailure.tooLarge;
  }
  return InboundShareFailure.unreadable;
}

class AndroidInboundShareStageEntry {
  const AndroidInboundShareStageEntry({
    required this.displayName,
    required this.size,
    required this.sessionToken,
    this.path,
    this.mimeType,
    this.failure,
    this.diagnostic,
  });

  final String displayName;
  final String? path;
  final int size;
  final String? sessionToken;
  final String? mimeType;
  final String? failure;

  /// Structured, export-safe cause from native: `kind`, `read_grant`, `scheme`,
  /// and hashes. Separate from [failure] because that string is shown to the
  /// user. Never null in practice, but optional so an older native side - or a
  /// test fake built before this field existed - still parses.
  final String? diagnostic;

  factory AndroidInboundShareStageEntry.fromPlatformMap(
    Map<dynamic, dynamic> value,
  ) {
    final name = value['name'];
    final path = value['path'];
    final size = value['size'];
    final mimeType = value['mime_type'];
    final failure = value['failure'];
    final diagnostic = value['diagnostic'];
    final sessionToken = value['session_token'];
    if (name is! String || size is! num) {
      throw const FormatException('Invalid inbound-share staging response.');
    }
    if (path != null && path is! String) {
      throw const FormatException('Invalid staged inbound-share path.');
    }
    if (mimeType != null && mimeType is! String) {
      throw const FormatException('Invalid staged inbound-share MIME type.');
    }
    if (failure != null && failure is! String) {
      throw const FormatException('Invalid inbound-share staging error.');
    }
    if (sessionToken != null && sessionToken is! String) {
      throw const FormatException('Invalid inbound-share session token.');
    }
    return AndroidInboundShareStageEntry(
      displayName: name,
      path: path as String?,
      size: size.toInt(),
      sessionToken: sessionToken as String?,
      mimeType: mimeType as String?,
      failure: failure as String?,
      diagnostic: diagnostic is String ? diagnostic : null,
    );
  }
}

class MethodChannelAndroidInboundShareStaging
    implements AndroidInboundShareStagingPlatform {
  const MethodChannelAndroidInboundShareStaging();
  static const _channel = MethodChannel('chat.intergalactic.app/inbound_share');

  @override
  Future<AndroidInboundShareGrantSnapshot?> grantSnapshot(
    List<Uri> uris,
  ) async {
    final value = await _channel.invokeMethod<Object?>(
      'inboundShareGrantSnapshot',
      {'uris': uris.map((uri) => uri.toString()).toList(growable: false)},
    );
    // Native answers null when its own probe threw; that is not a share failure.
    if (value == null) return null;
    return AndroidInboundShareGrantSnapshot.fromPlatformMap(value);
  }

  @override
  Future<List<AndroidInboundShareStageEntry>> stage(List<Uri> uris) async {
    final result = await _channel.invokeListMethod<Object?>(
      'stageContentUris',
      {'uris': uris.map((uri) => uri.toString()).toList(growable: false)},
    );
    return result
            ?.whereType<Map<dynamic, dynamic>>()
            .map(AndroidInboundShareStageEntry.fromPlatformMap)
            .toList(growable: false) ??
        const [];
  }
}

class AndroidInboundShareStager {
  AndroidInboundShareStager(this.platform, {this.onDiscard});
  final AndroidInboundShareStagingPlatform platform;

  /// Releases a native staging session this side has decided not to use.
  ///
  /// Native deletes the session only when the whole stage request throws, so a
  /// response rejected *here* would otherwise leave its staged bytes in the app
  /// cache with nothing left holding a reference that could release them.
  final Future<void> Function(String sessionToken)? onDiscard;

  Future<InboundSharePayload?> stage(AndroidInboundShareIntent intent) async {
    if (intent.streams.isEmpty) return null;
    final staged = await platform.stage(intent.streams);
    // Every rejection below used to return the same bare null, so a warm share
    // that native staged but this side refused was indistinguishable from one
    // native never staged at all - both surfaced as `result=rejected` with no
    // reason anywhere. Each exit now names itself, and the native per-item
    // cause is recorded here because nothing downstream ever sees it.
    for (final entry in staged) {
      if (entry.diagnostic == null && entry.failure == null) continue;
      Log.w(
        'inbound_share event=android_item_staged '
        'staged=${entry.path != null} '
        'size=${entry.size} '
        '${entry.diagnostic ?? 'kind=unreported'}',
      );
    }
    // Read before any rejection: every path below this point is rejecting a
    // session native has already created and filled.
    final sessionToken = staged.isEmpty ? null : staged.first.sessionToken;
    Future<InboundSharePayload?> discard(String reason) async {
      Log.w(
        'inbound_share event=android_stage_discarded reason=$reason '
        'requested=${intent.streams.length} returned=${staged.length}',
      );
      if (sessionToken != null) await onDiscard?.call(sessionToken);
      return null;
    }

    if (staged.isEmpty || staged.length != intent.streams.length) {
      return discard('entry_count_mismatch');
    }
    if (sessionToken == null ||
        staged.any((entry) => entry.sessionToken != sessionToken)) {
      return discard('session_token_mismatch');
    }
    final items = <InboundShareItem>[];
    final body = intent.text?.trim();
    if (body != null && body.isNotEmpty) items.add(InboundShareItem.text(body));
    for (final entry in staged) {
      if (entry.size < 0 || (entry.failure == null && entry.path == null)) {
        return discard('unusable_entry');
      }
      items.add(
        InboundShareItem.file(
          InboundShareFile(
            displayName: entry.displayName,
            stagingPath: entry.path ?? '',
            size: entry.size,
            mimeType: entry.mimeType ?? intent.mimeType,
            failure: entry.failure,
          ),
        ),
      );
    }
    final payload = InboundSharePayload(
      items: items,
      body: body,
      stagingToken: sessionToken,
    );
    if (!payload.hasUsableContent) return discard('no_usable_content');
    return payload;
  }
}
