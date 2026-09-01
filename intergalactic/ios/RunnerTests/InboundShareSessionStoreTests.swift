import XCTest

/// Regression coverage for the inbound-share reservation protocol.
///
/// `InboundShareSessionStore.swift` is compiled into this target directly
/// rather than reached through `@testable import Runner`: the store is pure
/// Foundation, and importing Runner would drag in its CocoaPods module
/// dependencies (WebRTC and friends), which a test bundle with no Pods
/// xcconfig cannot resolve.
///
/// REVIEW gated U4 on this behaviour twice: first because a permanent marker
/// was burned before Dart had the payload, then because acknowledge/reject
/// reported success even when their filesystem mutation failed. Both are
/// state-machine properties that a build cannot demonstrate, which is why this
/// target exists.
final class InboundShareSessionStoreTests: XCTestCase {
  private var root: URL!
  private let token = "a1b2c3d4e5f60718"
  private let otherToken = "b1b2c3d4e5f60719"

  override func setUpWithError() throws {
    root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent("ig-share-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: root)
  }

  // MARK: - helpers

  private func store(
    reservationTimeout: TimeInterval = 300,
    sessionMaxAge: TimeInterval = 7 * 24 * 60 * 60,
    now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }
  ) -> InboundShareSessionStore {
    InboundShareSessionStore(
      root: root,
      reservationTimeout: reservationTimeout,
      sessionMaxAge: sessionMaxAge,
      now: now
    )
  }

  @discardableResult
  private func makeSession(_ name: String, manifest: Bool = true) throws -> URL {
    let dir = root.appendingPathComponent(name, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    if manifest {
      try "{\"schemaVersion\":1}".write(
        to: dir.appendingPathComponent(InboundShareSessionStore.manifestName),
        atomically: true,
        encoding: .utf8
      )
    }
    return dir
  }

  private func exists(_ path: URL) -> Bool {
    FileManager.default.fileExists(atPath: path.path)
  }

  // MARK: - reservation

  func testReservesAReadySession() throws {
    try makeSession(token)
    XCTAssertEqual(store().reserveNext(), token)
  }

  func testAFreshReservationIsNotOfferedAgain() throws {
    try makeSession(token)
    let s = store()
    XCTAssertEqual(s.reserveNext(), token)
    XCTAssertNil(s.reserveNext(), "a session with a live reservation must not be handed out twice")
  }

  /// The finding this whole protocol exists for: anything that dies between
  /// handing out the token and acknowledging it must be retried, not stranded.
  func testAStaleReservationIsRetried() throws {
    try makeSession(token)
    var clock = 1_000_000.0
    let s = store(reservationTimeout: 300, now: { clock })
    XCTAssertEqual(s.reserveNext(), token)
    clock += 299
    XCTAssertNil(s.reserveNext(), "still within the reservation window")
    clock += 2
    XCTAssertEqual(s.reserveNext(), token, "a lapsed reservation must be retryable")
  }

  /// The claim and its timestamp have to land together. If the marker were
  /// created empty and stamped afterwards, a second drain reading it in the gap
  /// would see "no reservation", take the marker over, and be handed the same
  /// token - which is exactly the double-review this protocol exists to prevent.
  func testTheReservationMarkerCarriesAReadableTimestamp() throws {
    let dir = try makeSession(token)
    let s = store(now: { 1_000_000 })
    XCTAssertEqual(s.reserveNext(), token)
    let marker = dir.appendingPathComponent(InboundShareSessionStore.reservedMarker)
    let stamp = try String(contentsOf: marker, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    XCTAssertEqual(TimeInterval(stamp) ?? -1, 1_000_000, "the marker must be readable as a timestamp")
  }

  func testASessionWithoutAManifestIsNeverOffered() throws {
    try makeSession(token, manifest: false)
    XCTAssertNil(store().reserveNext(), "a half-staged session must not be handed out")
  }

  func testMultipleSessionsDrainToDistinctTokensAndTerminate() throws {
    try makeSession(token)
    try makeSession(otherToken)
    let s = store()
    let first = s.reserveNext()
    let second = s.reserveNext()
    XCTAssertNotNil(first)
    XCTAssertNotNil(second)
    XCTAssertNotEqual(first, second)
    XCTAssertNil(s.reserveNext())
  }

  func testNonTokenDirectoryNamesAreIgnored() throws {
    try makeSession(token)
    try makeSession("NOT-A-TOKEN-UPPERCASE")
    try makeSession("short")
    XCTAssertEqual(store().reserveNext(), token)
  }

  func testExpiredSessionsAreSwept() throws {
    let dir = try makeSession(token)
    // Age the directory past the sweep threshold.
    try FileManager.default.setAttributes(
      [.creationDate: Date(timeIntervalSince1970: 0)],
      ofItemAtPath: dir.path
    )
    XCTAssertNil(store(sessionMaxAge: 60).reserveNext())
    XCTAssertFalse(exists(dir), "an abandoned session must not accumulate forever")
  }

  // MARK: - acknowledge

  func testAcknowledgeRetiresTheSession() throws {
    let dir = try makeSession(token)
    let s = store()
    _ = s.reserveNext()
    XCTAssertTrue(s.acknowledge(token))
    XCTAssertTrue(exists(dir.appendingPathComponent(InboundShareSessionStore.acceptedMarker)))
    XCTAssertFalse(
      exists(dir.appendingPathComponent(InboundShareSessionStore.reservedMarker)),
      "acknowledge should clear the now-redundant reservation"
    )
    XCTAssertNil(s.reserveNext(), "an acknowledged session must never be offered again")
  }

  func testAcknowledgeRefusesAnUnknownOrTraversalToken() {
    let s = store()
    XCTAssertFalse(s.acknowledge("../../etc"))
    XCTAssertFalse(s.acknowledge("not-a-real-token-value"))
    XCTAssertFalse(s.acknowledge(token), "no such session on disk")
  }

  /// REVIEW's second finding: a failed mutation must not report success.
  func testAcknowledgeReturnsFalseWhenTheMarkerCannotBeWritten() throws {
    let dir = try makeSession(token)
    let s = store()
    _ = s.reserveNext()
    // Make the session directory unwritable so creating `.accepted` fails.
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
    }
    XCTAssertFalse(s.acknowledge(token), "a failed marker write must not report success")
    XCTAssertTrue(
      exists(dir.appendingPathComponent(InboundShareSessionStore.reservedMarker)),
      "the reservation must be retained so the session is retried"
    )
  }

  // MARK: - reject

  func testRejectRemovesTheStagedSession() throws {
    let dir = try makeSession(token)
    let s = store()
    _ = s.reserveNext()
    XCTAssertTrue(s.reject(token))
    XCTAssertFalse(exists(dir), "rejected staging must be deleted, not stranded")
    XCTAssertNil(s.reserveNext())
  }

  func testRejectRefusesAnUnknownOrTraversalToken() {
    let s = store()
    XCTAssertFalse(s.reject("../../etc"))
    XCTAssertFalse(s.reject(token))
  }

  /// The reject-side twin of
  /// `testAcknowledgeReturnsFalseWhenTheMarkerCannotBeWritten`: a removal that
  /// fails must report failure, or the caller retires a session whose bytes are
  /// still on disk.
  func testRejectReturnsFalseWhenTheSessionCannotBeRemoved() throws {
    let dir = try makeSession(token)
    let s = store()
    _ = s.reserveNext()
    // Unlinking the session directory needs write on its parent, so denying it
    // there is what makes the removal fail.
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
    defer {
      try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }
    XCTAssertFalse(s.reject(token), "a failed removal must not report success")
    XCTAssertTrue(exists(dir), "the staged session must be retained so a retry can clean it up")
  }

  // MARK: - token grammar

  func testTokenGrammarMatchesTheDartClaimPath() {
    XCTAssertTrue(InboundShareSessionStore.isToken(token))
    XCTAssertTrue(InboundShareSessionStore.isToken(String(repeating: "f", count: 64)))
    XCTAssertTrue(InboundShareSessionStore.isToken("aaaaaaaa-bbbbbbb"))
    XCTAssertFalse(InboundShareSessionStore.isToken(String(repeating: "a", count: 15)))
    XCTAssertFalse(InboundShareSessionStore.isToken(String(repeating: "a", count: 65)))
    XCTAssertFalse(InboundShareSessionStore.isToken(String(repeating: "A", count: 16)))
    XCTAssertFalse(InboundShareSessionStore.isToken(String(repeating: "z", count: 16)))
    XCTAssertFalse(InboundShareSessionStore.isToken(".."))
    XCTAssertFalse(InboundShareSessionStore.isToken("."))
  }
}

/// Coverage for the handoff URL the Share Extension opens.
///
/// The scheme is shared with flutter_web_auth_2's login callback, so the parser
/// must claim ONLY the exact handoff shape. Restores the coverage that was lost
/// when the Dart URL bridge was deleted during the P0 rework.
final class InboundShareHandoffURLTests: XCTestCase {
  private let token = "a1b2c3d4e5f60718"
  private func parse(_ s: String) -> String? {
    URL(string: s).flatMap { InboundShareSessionStore.token(fromHandoff: $0) }
  }

  func testAcceptsTheDocumentedShape() {
    XCTAssertEqual(parse("space.ourgalaxy://share/v1/\(token)"), token)
  }

  func testRejectsOtherSchemesHostsAndVersions() {
    XCTAssertNil(parse("https://share/v1/\(token)"))
    XCTAssertNil(parse("space.ourgalaxy://shared/v1/\(token)"))
    XCTAssertNil(parse("space.ourgalaxy://share/v2/\(token)"))
    XCTAssertNil(parse("space.ourgalaxy://share/\(token)"))
  }

  func testRejectsExtraOrMissingSegments() {
    XCTAssertNil(parse("space.ourgalaxy://share/v1/\(token)/extra"))
    XCTAssertNil(parse("space.ourgalaxy://share/v1/"))
    XCTAssertNil(parse("space.ourgalaxy://share/v1"))
  }

  func testRejectsQueryFragmentUserinfoAndPort() {
    // Nothing but the opaque token may ride in this URL.
    XCTAssertNil(parse("space.ourgalaxy://share/v1/\(token)?room=%21a%3Ab.org"))
    XCTAssertNil(parse("space.ourgalaxy://share/v1/\(token)#frag"))
    XCTAssertNil(parse("space.ourgalaxy://evil@share/v1/\(token)"))
    XCTAssertNil(parse("space.ourgalaxy://share:8080/v1/\(token)"))
  }

  func testRejectsTokensOutsideTheStagingGrammar() {
    XCTAssertNil(parse("space.ourgalaxy://share/v1/\(String(repeating: "A", count: 16))"))
    XCTAssertNil(parse("space.ourgalaxy://share/v1/\(String(repeating: "a", count: 15))"))
    XCTAssertNil(parse("space.ourgalaxy://share/v1/.."))
    XCTAssertNil(parse("space.ourgalaxy://share/v1/%2e%2e"))
  }

  /// The regression that would break sign-in: a login callback on the same
  /// scheme must fall through, not be claimed as a share.
  func testDoesNotClaimTheLoginCallback() {
    XCTAssertNil(parse("space.ourgalaxy://login-callback?code=abc"))
    XCTAssertNil(parse("space.ourgalaxy://auth"))
  }
}
