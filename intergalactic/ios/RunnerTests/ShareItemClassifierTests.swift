import UniformTypeIdentifiers
import XCTest

/// Regression coverage for the 2026-08-03 QA report: shared images sent twice.
///
/// `public.file-url` conforms to `public.url`. Classifying by url-conformance
/// first turned an image handed over by Photos or Files into a `file://` text
/// body, and when the share also carried an image provider the result was two
/// messages for one image.
final class ShareItemClassifierTests: XCTestCase {
  func testAnImageIsAFileEvenWhenItAlsoOffersAFileURL() {
    // The exact shape that caused the duplicate.
    XCTAssertEqual(
      ShareItemClassifier.kind(for: [UTType.fileURL.identifier, UTType.jpeg.identifier]),
      .file
    )
    XCTAssertEqual(
      ShareItemClassifier.kind(for: [UTType.jpeg.identifier, UTType.fileURL.identifier]),
      .file
    )
  }

  func testABareFileURLIsAFileNotALink() {
    XCTAssertEqual(ShareItemClassifier.kind(for: [UTType.fileURL.identifier]), .file)
  }

  func testMediaTypesAreFiles() {
    for t in [UTType.image, .jpeg, .png, .movie, .mpeg4Movie, .audio, .pdf] {
      XCTAssertEqual(
        ShareItemClassifier.kind(for: [t.identifier]), .file,
        "\(t.identifier) should stage as a file"
      )
    }
  }

  func testARealWebURLIsStillALink() {
    // The case the url branch exists for - Safari sharing a page.
    XCTAssertEqual(ShareItemClassifier.kind(for: [UTType.url.identifier]), .link)
  }

  func testPlainTextIsText() {
    XCTAssertEqual(ShareItemClassifier.kind(for: [UTType.plainText.identifier]), .text)
    XCTAssertEqual(ShareItemClassifier.kind(for: [UTType.utf8PlainText.identifier]), .text)
  }

  func testAWebURLSharedAlongsideItsTitleIsStillALink() {
    XCTAssertEqual(
      ShareItemClassifier.kind(for: [UTType.url.identifier, UTType.plainText.identifier]),
      .link
    )
  }

  func testUnknownOrEmptyFallsBackToFile() {
    // Better to stage unknown content as an attachment than to drop it.
    XCTAssertEqual(ShareItemClassifier.kind(for: []), .file)
    XCTAssertEqual(ShareItemClassifier.kind(for: ["not.a.real.type"]), .file)
  }
}
