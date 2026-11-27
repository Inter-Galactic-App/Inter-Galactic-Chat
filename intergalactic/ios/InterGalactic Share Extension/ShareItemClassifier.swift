import Foundation
import UniformTypeIdentifiers

/// How a shared item should be staged.
enum ShareItemKind {
  case link  // a real web URL - becomes the message body
  case text  // plain text - becomes the message body
  case file  // image, movie, document - becomes an attachment
}

/// Classifies a shared item from an `NSItemProvider`'s registered type
/// identifiers.
///
/// Pure and free of UIKit so it can be unit-tested: an `NSItemProvider` carrying
/// real share-sheet payloads cannot be constructed in a test bundle, but the
/// identifiers it reports can.
///
/// **The media check must come first.** `public.file-url` conforms to
/// `public.url`, so testing url-conformance first classified an image handed
/// over by Photos or Files as a link and staged it as a `file://` text body.
/// When the same share also carried an image provider, that produced TWO
/// messages for one image - the QA report on 2026-08-03.
enum ShareItemClassifier {
  static func kind(for identifiers: [String]) -> ShareItemKind {
    let media: [UTType] = [.image, .movie, .audio, .audiovisualContent, .pdf, .fileURL]
    let types = identifiers.compactMap { UTType($0) }
    if types.contains(where: { t in media.contains { t.conforms(to: $0) } }) {
      return .file
    }
    if types.contains(where: { $0.conforms(to: .url) }) { return .link }
    if types.contains(where: { $0.conforms(to: .text) }) { return .text }
    return .file
  }
}
