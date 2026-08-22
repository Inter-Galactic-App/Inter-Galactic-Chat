import 'package:intergalactic/client/attachment.dart';

enum InboundShareItemKind { text, url, file }

enum InboundShareItemStatus { ready, failed }

/// Why an inbound share produced nothing to review.
///
/// A share that fails every item never reaches the destination picker, so
/// without this the user sees the share sheet close and then nothing at all -
/// indistinguishable from the app ignoring them. Device QA on 2026-08-05 hit
/// exactly that: `com.android.chrome.fileprovider` refuses a read grant, so
/// sharing an image from Google Images silently vanished while the same image
/// from the gallery worked.
enum InboundShareFailure {
  /// The sending app did not grant read access to the content it shared.
  ///
  /// Nothing on this side can recover it - the grant is the sender's to issue -
  /// so the message points at the one thing that does work: share a link.
  permissionDenied,

  /// The content was over the per-item or per-share size limit.
  tooLarge,

  /// Staging failed for some other reason, or the response was unusable.
  unreadable,
}

class InboundShareItem {
  const InboundShareItem._({
    required this.kind,
    this.text,
    this.url,
    this.file,
    this.failure,
  });
  const InboundShareItem.text(String value)
    : this._(kind: InboundShareItemKind.text, text: value);
  const InboundShareItem.url(Uri value)
    : this._(kind: InboundShareItemKind.url, url: value);
  const InboundShareItem.file(InboundShareFile value)
    : this._(kind: InboundShareItemKind.file, file: value);
  final InboundShareItemKind kind;
  final String? text;
  final Uri? url;
  final InboundShareFile? file;
  final String? failure;
  InboundShareItemStatus get status => failure == null && file?.failure == null
      ? InboundShareItemStatus.ready
      : InboundShareItemStatus.failed;
}

class InboundShareFile {
  const InboundShareFile({
    required this.displayName,
    required this.stagingPath,
    required this.size,
    this.mimeType,
    this.failure,
  });
  final String displayName;
  final String stagingPath;
  final int size;
  final String? mimeType;
  final String? failure;
  bool get isUsable => failure == null;
  PendingFileAttachment? toPendingAttachment() => isUsable
      ? PendingFileAttachment(
          name: displayName,
          path: stagingPath,
          mimeType: mimeType,
          size: size,
        )
      : null;
}

class InboundSharePayload {
  const InboundSharePayload({
    required this.items,
    this.body,
    this.stagingToken,
    this.preselectedRoomId,
  });
  final List<InboundShareItem> items;
  final String? body;

  /// Opaque native staging-directory identifier; never a filesystem path.
  final String? stagingToken;

  /// Room the user already chose in the share sheet, when the platform
  /// supplied one. Null means "ask" - the ordinary destination picker.
  final String? preselectedRoomId;
  bool get hasUsableContent => items.any((item) {
    if (item.status != InboundShareItemStatus.ready) return false;
    return switch (item.kind) {
      InboundShareItemKind.text => item.text?.trim().isNotEmpty ?? false,
      InboundShareItemKind.url => item.url != null,
      InboundShareItemKind.file => item.file!.isUsable,
    };
  });
  int get itemCount => items.length;
  int get stagedBytes => items
      .where((item) => item.file?.isUsable ?? false)
      .fold(0, (sum, item) => sum + item.file!.size);
  List<PendingFileAttachment> get pendingAttachments => items
      .map((item) => item.file?.toPendingAttachment())
      .whereType<PendingFileAttachment>()
      .toList(growable: false);
}
