import Foundation

/// Owns the on-disk lifecycle of iOS inbound-share staging sessions.
///
/// Extracted from `AppDelegate` so the state machine can be unit-tested. The
/// reservation protocol is the part REVIEW gated U4 on, and it is behaviour a
/// compile cannot demonstrate: a session must be recoverable if anything
/// between handing out the token and admitting the payload fails.
///
/// Three states, all expressed as marker files inside the session directory:
///
///   `.reserved` (timestamped)  handed to Dart, awaiting an outcome
///   `.accepted`                admitted; the review flow owns it and deletes
///                              the session at a terminal state
///   neither                    claimable
///
/// A reservation older than `reservationTimeout` is taken over, so a lost
/// method-channel response, a crash, or a failed manifest read all result in
/// the share being offered again rather than stranded.
struct InboundShareSessionStore {
  static let reservedMarker = ".reserved"
  static let acceptedMarker = ".accepted"
  static let manifestName = "manifest.json"

  let root: URL
  /// How long a handed-out session stays reserved before a pull may retry it.
  let reservationTimeout: TimeInterval
  /// Sessions the user never returned for are swept at this age.
  let sessionMaxAge: TimeInterval
  /// Injectable so tests can age a session without sleeping.
  let now: () -> TimeInterval

  init(
    root: URL,
    reservationTimeout: TimeInterval = 300,
    sessionMaxAge: TimeInterval = 7 * 24 * 60 * 60,
    now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 }
  ) {
    self.root = root
    self.reservationTimeout = reservationTimeout
    self.sessionMaxAge = sessionMaxAge
    self.now = now
  }

  /// Whether a staging directory name is a token this app would accept.
  ///
  /// The App Group is writable by the extension, so a name found there is
  /// untrusted input: it becomes a path component, and traversal is the failure
  /// that would matter most. Same grammar as
  /// `InboundShareStaging.claimExistingSession` in Dart.
  static func isToken(_ name: String) -> Bool {
    guard name.count >= 16, name.count <= 64 else { return false }
    guard name != ".", name != ".." else { return false }
    let allowed = CharacterSet(charactersIn: "0123456789abcdef-")
    return name.unicodeScalars.allSatisfy { allowed.contains($0) }
  }

  /// Extracts the staging token from a Share Extension handoff URL.
  ///
  /// `space.ourgalaxy://share/v1/<token>` and nothing else. Deliberately
  /// allow-list shaped: the scheme is shared with flutter_web_auth_2's login
  /// callback, so anything that is not exactly this shape must be left alone
  /// rather than claimed. Query and fragment are rejected rather than ignored,
  /// because the contract says only the opaque token may ride in this URL.
  static func token(fromHandoff url: URL) -> String? {
    guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
    guard c.scheme?.lowercased() == "space.ourgalaxy" else { return nil }
    guard c.host?.lowercased() == "share" else { return nil }
    guard c.port == nil, c.user == nil, c.password == nil else { return nil }
    guard c.query == nil, c.fragment == nil else { return nil }
    let segments = c.path.split(separator: "/", omittingEmptySubsequences: true)
    guard segments.count == 2, segments[0] == "v1" else { return nil }
    let token = String(segments[1])
    return isToken(token) ? token : nil
  }

  private func sessionURL(_ token: String) -> URL? {
    guard Self.isToken(token) else { return nil }
    let url = root.appendingPathComponent(token, isDirectory: true)
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue
    else { return nil }
    return url
  }

  /// Reserves the next ready session, or nil when there is none.
  func reserveNext() -> String? {
    let fm = FileManager.default
    guard let names = try? fm.contentsOfDirectory(atPath: root.path) else { return nil }
    let timestamp = now()

    for name in names.sorted() {
      guard Self.isToken(name) else { continue }
      let session = root.appendingPathComponent(name, isDirectory: true)
      var isDir: ObjCBool = false
      guard fm.fileExists(atPath: session.path, isDirectory: &isDir), isDir.boolValue else {
        continue
      }

      if let created = (try? fm.attributesOfItem(atPath: session.path))?[.creationDate] as? Date,
        timestamp - created.timeIntervalSince1970 > sessionMaxAge {
        try? fm.removeItem(at: session)
        continue
      }
      // Already admitted; the review flow owns it.
      if fm.fileExists(atPath: session.appendingPathComponent(Self.acceptedMarker).path) {
        continue
      }
      // No manifest means the extension is still staging or died partway.
      // Skipping is what makes the manifest the readiness signal.
      guard fm.fileExists(atPath: session.appendingPathComponent(Self.manifestName).path) else {
        continue
      }

      let reserved = session.appendingPathComponent(Self.reservedMarker)
      if let stamp = try? String(contentsOf: reserved, encoding: .utf8),
        let at = TimeInterval(stamp.trimmingCharacters(in: .whitespacesAndNewlines)),
        timestamp - at < reservationTimeout {
        continue  // a pull is still in flight
      }
      // Unreserved, or a stale reservation being retried.
      //
      // The claim has to be the exclusive create itself. `String.write(to:
      // atomically:)` replaces whatever is there, so two drains that both passed
      // the staleness check above would both "succeed" and be handed the same
      // token - `_configureIosInboundShareHandoff` runs a startup drain and an
      // onResume drain that do not await each other, so that is reachable, and
      // the user sees the same share reviewed twice. O_EXCL makes exactly one
      // caller win. A stale marker is dropped first so the retry path still has
      // a name to create.
      //
      // BUT the drop-and-create pair is NOT atomic, so O_EXCL is not the whole
      // guarantee and this comment should not imply that it is. If two callers
      // ever reach the removeItem below at the same time, B can delete A's
      // fresh marker and create its own, and both are handed the same token.
      // Exclusivity therefore also depends on reserveNext having one caller at
      // a time, which today it does: AppDelegate.configureInboundShareChannel
      // routes every store call through the serial `inboundShareQueue`, and the
      // Share Extension only stages sessions, it never reserves. Anything that
      // adds a second reserving caller must either keep that serialization or
      // replace this pair with a single atomic operation.
      try? fm.removeItem(at: reserved)
      let fd = open(reserved.path, O_CREAT | O_EXCL | O_WRONLY, 0o600)
      guard fd >= 0 else { continue }
      // The timestamp is written through the descriptor we already own. Writing
      // it separately would leave a window where the marker exists but is empty,
      // which the staleness check reads as "no reservation".
      let stampData = Data(String(timestamp).utf8)
      _ = stampData.withUnsafeBytes { buffer in
        write(fd, buffer.baseAddress, buffer.count)
      }
      close(fd)
      return name
    }
    return nil
  }

  /// Marks a session admitted. Returns false if the marker could not be
  /// written, leaving the reservation to lapse so the session is retried.
  func acknowledge(_ token: String) -> Bool {
    guard let session = sessionURL(token) else { return false }
    let accepted = session.appendingPathComponent(Self.acceptedMarker)
    let fd = open(accepted.path, O_CREAT | O_WRONLY, 0o600)
    guard fd >= 0 else { return false }
    close(fd)
    // Best-effort: `.accepted` already retires the session, and the scan checks
    // it first.
    try? FileManager.default.removeItem(at: session.appendingPathComponent(Self.reservedMarker))
    return true
  }

  /// Removes a session Dart could not use. Returns false if the removal failed,
  /// again leaving the reservation to lapse rather than silently abandoning it.
  func reject(_ token: String) -> Bool {
    guard let session = sessionURL(token) else { return false }
    do {
      try FileManager.default.removeItem(at: session)
      return true
    } catch {
      return false
    }
  }
}
