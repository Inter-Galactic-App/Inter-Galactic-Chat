import CommonCrypto
import CryptoKit
// flock/open/close for the diagnostics counter lock. Explicit rather than
// relying on Foundation's re-export, because the calls are module-qualified.
import Darwin
import Foundation
import ImageIO
import SQLite3
import UserNotifications
import os

/// The iOS Notification Service Extension: the local-decrypt half of the
/// push privacy model (NSE Phase C).
///
/// The gateway sends routing identifiers only. This extension turns them into
/// a readable notification on the device, without the app running, by:
///
/// 1. reading the user's notification policy snapshot from the App Group and
///    deciding whether rendering is allowed at all (S&C C1-C3);
/// 2. resolving the account database at
///    `<App Group>/db/account/drift/<client_id>/data.db` (Phase B) and reading
///    the homeserver, the access token and the user id from it, read-only;
/// 3. fetching the one event by id from that homeserver (C4, C5);
/// 4. decrypting it with the Megolm session pickle from the same database
///    through vodozemac's C ABI, when it is encrypted;
/// 5. building a replacement notification and handing it over in ONE
///    assignment (C6).
///
/// Every failure, at every step, delivers the gateway's payload unmodified.
/// That is the same path `serviceExtensionTimeWillExpire` takes, so there is
/// one fallback, not two. Nothing event-derived is ever logged (C8): the log
/// lines carry a stage, an outcome class and integer codes only.
///
/// Image previews (C7): for an image or sticker event, and only when the
/// policy snapshot's media flag allows it (C2), the referenced media - the
/// sender's thumbnail when there is one - is downloaded from the same origin
/// under a byte cap, its hash checked and its AES-CTR envelope removed when
/// encrypted, decoded to a bounded thumbnail, written to THIS extension's
/// temporary directory (never the App Group), protected and read back, and
/// attached. Every failure drops the preview and keeps the text; none of
/// them changes the delivery outcome. The sender's name is the room's
/// Inter Galactic display name when one is set, then the member name.
///
/// Not in this revision, deliberately: Mentions-only mode (fails closed
/// until the payload carries a highlight signal) and the diagnostic counter
/// (D1-D6, a separate write that is pre-registered but not built here).
final class NotificationService: UNNotificationServiceExtension {
  private let logger = Logger(subsystem: "chat.intergalactic.app.nse", category: "content")
  private let work = DispatchQueue(label: "chat.intergalactic.app.nse.work", qos: .userInitiated)
  private let deliveryLock = NSLock()

  private var contentHandler: ((UNNotificationContent) -> Void)?
  /// The gateway's content, never mutated. Delivered on every failure and on
  /// expiry (C6).
  private var original: UNNotificationContent?
  private var delivered = false

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    self.contentHandler = contentHandler
    self.original = request.content
    // C4/C5: the total budget starts at receipt, not when the work queue
    // gets to it.
    let budget = NSEBudget()

    work.async { [weak self] in
      guard let self else { return }
      let pipeline = NSEPipeline(logger: self.logger, budget: budget)
      let outcome = pipeline.run(request: request)
      // `diag` is the diagnostic counter's report class (NSEDiagnostics.Report),
      // -1 when the database was never reached; on the same single line.
      switch outcome {
      case .rendered(let content, let attachment):
        // The code on a rendered outcome is the attachment class (see
        // `NSEAttachment.Code`), so the one log line still says what
        // happened to the preview without a second line.
        self.deliver(
          content, stage: "rendered", outcome: "ok", code: attachment,
          diag: pipeline.diagnostic, decryptSource: pipeline.decryptSource,
          fetchAttempts: pipeline.eventFetchAttempts
        )
      case .generic(let stage, let reason, let code):
        self.deliver(
          request.content, stage: stage, outcome: reason, code: code,
          diag: pipeline.diagnostic, decryptSource: pipeline.decryptSource,
          fetchAttempts: pipeline.eventFetchAttempts
        )
      }
    }
  }

  override func serviceExtensionTimeWillExpire() {
    if let original {
      deliver(original, stage: "expired", outcome: "generic")
    }
  }

  private func deliver(
    _ content: UNNotificationContent, stage: String, outcome: String, code: Int = 0,
    diag: Int = -1, decryptSource: String = "none", fetchAttempts: Int = 0
  ) {
    deliveryLock.lock()
    defer { deliveryLock.unlock() }
    guard !delivered, let handler = contentHandler else { return }
    delivered = true
    logger.log(
      "nse stage=\(stage, privacy: .public) outcome=\(outcome, privacy: .public) code=\(code, privacy: .public) diag=\(diag, privacy: .public) decrypt=\(decryptSource, privacy: .public) attempts=\(fetchAttempts, privacy: .public)"
    )
    handler(content)
  }
}

// MARK: - Outcome

enum NSEOutcome {
  /// `attachment` is an `NSEAttachment.Code` raw value.
  case rendered(UNNotificationContent, attachment: Int)
  /// `stage` and `reason` are compile-time literals; `code` an integer.
  case generic(stage: String, reason: String, code: Int)
}

// MARK: - Budget (C4, C5)

/// One total budget for the invocation, inside the ~30 s iOS allows, so the
/// fallback path always has time to run. Per-request timeouts are clamped to
/// what is left, and a request that could not get [minimumRequest] is not
/// started. Worst case with the clamps: 13 s event fetch, then the media
/// downloads inside the remainder, then decode - never past the deadline.
struct NSEBudget {
  static let total: TimeInterval = 24
  static let minimumRequest: TimeInterval = 2

  let deadline: Date

  init(start: Date = Date()) {
    deadline = start.addingTimeInterval(Self.total)
  }

  func remaining(now: Date = Date()) -> TimeInterval {
    max(0, deadline.timeIntervalSince(now))
  }

  func allows(_ minimum: TimeInterval, now: Date = Date()) -> Bool {
    remaining(now: now) >= minimum
  }

  func clamp(_ interval: TimeInterval, now: Date = Date()) -> TimeInterval {
    min(interval, remaining(now: now))
  }
}

// MARK: - Pipeline

final class NSEPipeline {
  let logger: Logger
  let budget: NSEBudget
  /// `NSEDiagnostics.Report` raw value for this run, -1 until the database
  /// open has been attempted.
  private(set) var diagnostic = -1
  /// Developer-only, identifier-free success provenance. It stays `none`
  /// unless an encrypted event decrypts successfully.
  private(set) var decryptSource = "none"
  /// Zero outside Developer Mode; otherwise the bounded event GET count only.
  private(set) var eventFetchAttempts = 0

  init(logger: Logger, budget: NSEBudget) {
    self.logger = logger
    self.budget = budget
  }

  private static let appGroup = "group.chat.intergalactic.app"
  private static let richMessageCategory = "chat.intergalactic.rich_message.v1"
  private static let freshnessLimit: TimeInterval = 10 * 60
  private static let maxBodyCharacters = 500
  private static let maxNameCharacters = 100

  func run(request: UNNotificationRequest) -> NSEOutcome {
    guard let payload = NSEPayload(userInfo: request.content.userInfo) else {
      return .generic(stage: "payload", reason: "invalid", code: 0)
    }
    guard let container = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: Self.appGroup
    ) else {
      return .generic(stage: "container", reason: "unavailable", code: 0)
    }

    // C1-C3: policy first. Undecidable in any way means the gateway payload.
    let policy = NSEPolicy.load(container: container)
    switch policy.decide(clientId: payload.clientId, roomId: payload.roomId, now: Date()) {
    case .generic(let reason):
      return .generic(stage: "policy", reason: reason, code: 0)
    case .render(let rendering):
      return render(payload: payload, container: container, rendering: rendering, request: request)
    }
  }

  private func render(
    payload: NSEPayload,
    container: URL,
    rendering: NSEPolicy.Rendering,
    request: UNNotificationRequest
  ) -> NSEOutcome {
    let database: NSEDatabase
    switch NSEDatabase.open(container: container, clientId: payload.clientId) {
    case .failure(let failure):
      diagnostic = NSEDiagnostics.record(
        container: container, outcome: NSEDiagnostics.outcome(forOpenFailure: failure.reason),
        extendedCode: failure.code
      ).rawValue
      return .generic(stage: "db_open", reason: failure.reason, code: failure.code)
    case .success(let db):
      diagnostic = NSEDiagnostics.record(container: container, outcome: "ok", extendedCode: 0).rawValue
      database = db
    }
    defer { database.close() }

    guard let account = database.account() else {
      return .generic(stage: "db_account", reason: "missing", code: 0)
    }

    let fetch = NSEFetch(budget: budget)
    let event: [String: Any]
    let eventResult = fetch.event(homeserver: account.homeserver, token: account.token, payload: payload)
    if rendering.developerMode { eventFetchAttempts = fetch.eventAttempts }
    switch eventResult {
    case .failure(let failure):
      return .generic(stage: "fetch", reason: failure.reason, code: failure.code)
    case .success(let json):
      event = json
    }

    // The gates the host applies in `shouldNotify`, mirrored: not our own
    // message, and not older than the freshness window.
    guard let sender = event["sender"] as? String, sender != account.userId else {
      return .generic(stage: "gate", reason: "self_sent", code: 0)
    }
    if let ts = event["origin_server_ts"] as? Double,
      Date().timeIntervalSince1970 - ts / 1000 > Self.freshnessLimit {
      return .generic(stage: "gate", reason: "stale", code: 0)
    }
    guard let type = event["type"] as? String, var content = event["content"] as? [String: Any] else {
      return .generic(stage: "event", reason: "malformed", code: 0)
    }

    var effectiveType = type
    if type == "m.room.encrypted" {
      switch NSEDecrypt.decrypt(
        content: content,
        roomId: payload.roomId,
        userId: account.userId,
        clientId: payload.clientId,
        container: container,
        account: account,
        database: database,
        fetch: fetch,
        developerMode: rendering.developerMode
      ) {
      case .failure(let failure):
        return .generic(stage: "decrypt", reason: failure.reason, code: failure.code)
      case .success(let decrypted):
        decryptSource = decrypted.source.rawValue
        let plain = decrypted.content
        guard let plainType = plain["type"] as? String,
          let plainContent = plain["content"] as? [String: Any]
        else {
          return .generic(stage: "decrypt", reason: "malformed", code: 0)
        }
        if let plainRoom = plain["room_id"] as? String, plainRoom != payload.roomId {
          return .generic(stage: "decrypt", reason: "room_mismatch", code: 0)
        }
        effectiveType = plainType
        content = plainContent
      }
    }

    guard let body = NSERender.body(type: effectiveType, content: content, senderName: nil) else {
      return .generic(
        stage: "render",
        reason: rendering.developerMode
          ? NSERender.unsupportedFamily(type: effectiveType)
          : "unsupported_type",
        code: 0
      )
    }

    // The host resolves a member's name as the room's Inter Galactic display
    // name first (a state event the app writes), then the m.room.member
    // name, then the localpart (`MatrixMember.displayName`). Same order.
    let senderName = database.roomDisplayName(roomId: payload.roomId, userId: sender)
      ?? database.memberDisplayName(roomId: payload.roomId, userId: sender)
      ?? NSERender.localpart(of: sender)
    let roomName = database.roomName(roomId: payload.roomId)

    guard let replacement = request.content.mutableCopy() as? UNMutableNotificationContent else {
      return .generic(stage: "render", reason: "copy_failed", code: 0)
    }
    // C6: this object is built completely and handed over once. `original`
    // is never touched.
    replacement.title = String(senderName.prefix(Self.maxNameCharacters))
    replacement.subtitle = roomName.map { String($0.prefix(Self.maxNameCharacters)) } ?? ""
    replacement.body = String(body.prefix(Self.maxBodyCharacters))
    replacement.threadIdentifier = "\(payload.clientId)::\(payload.roomId)"
    if rendering.richActions {
      replacement.categoryIdentifier = Self.richMessageCategory
    }

    // C7. A preview is an addition to a notification that is already
    // complete; nothing here can turn the outcome generic.
    var attachmentCode = NSEAttachment.Code.none
    let candidates = NSEAttachment.candidates(type: effectiveType, content: content)
    if !candidates.isEmpty {
      if !rendering.showMedia {
        // C2: the custom mode with media previews off lands here, not on a
        // 'private' boolean.
        attachmentCode = .mediaOff
      } else {
        // At most two downloads: the preferred file, then the fallback -
        // and none that the budget cannot cover.
        for candidate in candidates.prefix(2) {
          guard budget.allows(NSEBudget.minimumRequest) else {
            attachmentCode = .budgetExhausted
            break
          }
          switch NSEAttachment.prepare(candidate: candidate, account: account, budget: budget) {
          case .success(let attachment):
            replacement.attachments = [attachment]
            attachmentCode = .attached
          case .failure(let code):
            attachmentCode = code
          }
          if attachmentCode == .attached || attachmentCode == .downloadUnauthorized
            || attachmentCode == .budgetExhausted {
            break
          }
        }
      }
    }
    return .rendered(replacement, attachment: attachmentCode.rawValue)
  }
}

// MARK: - Payload (C4)

struct NSEPayload {
  static let maxIdentifierLength = 255
  static let maxClientIdLength = 64

  let clientId: String
  let roomId: String
  let eventId: String

  init?(userInfo: [AnyHashable: Any]) {
    guard let clientId = Self.string(userInfo, keys: ["client_id", "clientId", "clientID"]),
      let roomId = Self.string(userInfo, keys: ["room_id", "roomId", "roomID"]),
      let eventId = Self.string(userInfo, keys: ["event_id", "eventId", "eventID"])
    else {
      return nil
    }
    guard clientId.count <= Self.maxClientIdLength,
      roomId.count <= Self.maxIdentifierLength,
      eventId.count <= Self.maxIdentifierLength,
      Self.matches(clientId, "^[A-Za-z0-9._-]+$"),
      // The alphabet above admits "." and "..", and the id goes on to be a
      // path component in NSEDatabase.open. A gateway payload of ".." would
      // resolve one directory up. The sandbox bounds the damage, but the
      // component is attacker-controlled, so the primitive should not exist.
      clientId != ".", clientId != "..",
      // !opaque, with :server only in room versions before 12 - since
      // MSC4291 the id is the create event's hash and carries no server. The
      // opaque part never contains ':' or '/'. (The first alert push on the
      // device, 2026-09-04, was a v12 room and the old form rejected it.)
      Self.matches(roomId, "^![^:/\\s]+(:[A-Za-z0-9.\\-]+(:[0-9]{1,5})?)?$"),
      // $opaque, optionally :server for the older id formats. Base64 and
      // URL-safe alphabets, never '/' in the modern form.
      Self.matches(eventId, "^\\$[A-Za-z0-9+/_\\-=]+(:[A-Za-z0-9.\\-]+(:[0-9]{1,5})?)?$"),
      !eventId.dropFirst().contains("/") || eventId.contains(":")
    else {
      return nil
    }
    self.clientId = clientId
    self.roomId = roomId
    self.eventId = eventId
  }

  private static func string(_ userInfo: [AnyHashable: Any], keys: [String]) -> String? {
    for key in keys {
      if let value = userInfo[key] as? String, !value.isEmpty {
        return value
      }
    }
    return nil
  }

  private static func matches(_ value: String, _ pattern: String) -> Bool {
    value.range(of: pattern, options: .regularExpression) != nil
  }
}

// MARK: - Policy (C1-C3)

struct NSEPolicy {
  struct Rendering {
    let showMedia: Bool
    let richActions: Bool
    /// The temporary E1-E10 path is unavailable unless the host explicitly
    /// published Developer Mode into this protected App Group snapshot.
    let developerMode: Bool
  }

  enum Decision {
    case generic(String)
    case render(Rendering)
  }

  private static let directory = "notification-policy"
  private static let file = "policy.json"
  private static let maxBytes = 8 * 1024
  private static let maxSnoozes = 64

  private let document: [String: Any]?

  static func load(container: URL) -> NSEPolicy {
    let url = container.appendingPathComponent(directory).appendingPathComponent(file)
    guard let data = try? Data(contentsOf: url), data.count <= maxBytes,
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      json["version"] as? Int == 1
    else {
      return NSEPolicy(document: nil)
    }
    return NSEPolicy(document: json)
  }

  func decide(clientId: String, roomId: String, now: Date) -> Decision {
    guard let doc = document else { return .generic("policy_missing") }
    if doc["undecidable"] != nil { return .generic("policy_undecidable") }
    guard let enabled = doc["notifications_enabled"] as? Bool,
      let mode = doc["notification_mode"] as? String,
      let choice = doc["preview_choice"] as? String,
      let showMedia = doc["show_media"] as? Bool,
      let digestKeyHex = doc["digest_key"] as? String,
      let snoozes = doc["snoozes"] as? [[String: Any]],
      let digestKey = Data(hex: digestKeyHex), digestKey.count == 32,
      snoozes.count <= Self.maxSnoozes
    else {
      return .generic("policy_malformed")
    }
    // Older valid snapshots predate this field. Preserve their rendering
    // policy, but keep the developer-only backup path disabled. A present
    // non-Boolean value is still malformed rather than silently accepted.
    let developerMode: Bool
    if let rawDeveloperMode = doc["developer_mode"] {
      guard let value = rawDeveloperMode as? Bool else { return .generic("policy_malformed") }
      developerMode = value
    } else {
      developerMode = false
    }
    if !enabled { return .generic("muted") }
    // Only "all" can be evaluated here. Mentions-only needs a per-event
    // highlight signal the payload does not carry (C2), so it fails closed.
    if mode != "all" { return .generic("mode_\(mode == "mentions" ? "mentions" : "other")") }

    let key = SymmetricKey(data: digestKey)
    let digest = Self.digest(key: key, message: "\(clientId)::\(roomId)")
    for entry in snoozes {
      guard let entryDigest = entry["digest"] as? String, let untilMs = entry["until_ms"] as? Double else {
        return .generic("policy_malformed")
      }
      if entryDigest == digest, Date(timeIntervalSince1970: untilMs / 1000) > now {
        return .generic("snoozed")
      }
    }

    switch choice {
    case "rich":
      return .render(
        Rendering(showMedia: showMedia, richActions: true, developerMode: developerMode)
      )
    case "custom":
      return .render(
        Rendering(showMedia: showMedia, richActions: true, developerMode: developerMode)
      )
    default:
      // "private", or anything unrecognised: the generic payload is the
      // contentless notification the user asked for.
      return .generic("private")
    }
  }

  /// HMAC-SHA256 over the snooze key, first 16 bytes, lower-case hex -
  /// exactly what the host writes.
  static func digest(key: SymmetricKey, message: String) -> String {
    let mac = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
    return Data(mac).prefix(16).map { String(format: "%02x", $0) }.joined()
  }
}

extension Data {
  init?(hex: String) {
    guard hex.count % 2 == 0 else { return nil }
    var bytes = [UInt8]()
    bytes.reserveCapacity(hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
      let next = hex.index(index, offsetBy: 2)
      guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
      bytes.append(byte)
      index = next
    }
    self.init(bytes)
  }
}

// MARK: - Host backup-version handoff (E2, E3)

enum NSEBackupVersion {
  private static let maxBytes = 4 * 1024
  private static let maxEntries = 16
  private static let pattern = "^[A-Za-z0-9._-]{1,32}$"

  static func load(container: URL, clientId: String) -> String? {
    let url = container.appendingPathComponent("nse-key-backup")
      .appendingPathComponent("versions.json")
    guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
      let fileSize = values.fileSize, fileSize >= 0, fileSize <= maxBytes,
      let data = try? Data(contentsOf: url), data.count <= maxBytes,
      let document = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      document["version"] as? Int == 1,
      document["undecidable"] == nil,
      let versions = document["versions"] as? [String: String],
      versions.count <= maxEntries,
      let version = versions[clientId],
      version.range(of: pattern, options: .regularExpression) != nil
    else {
      return nil
    }
    return version
  }
}

// MARK: - Database (Phase B layout, read-only, B2)

struct NSEFailure: Error {
  let reason: String
  let code: Int
}

final class NSEDatabase {
  struct Account {
    let homeserver: String
    let token: String
    let userId: String
  }

  private static let busyTimeoutMs: Int32 = 1500
  private var handle: OpaquePointer?

  private init(handle: OpaquePointer) {
    self.handle = handle
  }

  static func open(container: URL, clientId: String) -> Result<NSEDatabase, NSEFailure> {
    let path = container
      .appendingPathComponent("db").appendingPathComponent("account").appendingPathComponent("drift")
      .appendingPathComponent(clientId).appendingPathComponent("data.db").path
    guard FileManager.default.fileExists(atPath: path) else {
      return .failure(NSEFailure(reason: "missing", code: 0))
    }
    var handle: OpaquePointer?
    let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
    let rc = sqlite3_open_v2(path, &handle, flags, nil)
    guard rc == SQLITE_OK, let db = handle else {
      let extended = handle.map { Int(sqlite3_extended_errcode($0)) } ?? Int(rc)
      if let db = handle { sqlite3_close(db) }
      return .failure(NSEFailure(reason: Self.classify(extended), code: extended))
    }
    sqlite3_busy_timeout(db, busyTimeoutMs)
    return .success(NSEDatabase(handle: db))
  }

  func close() {
    if let handle {
      sqlite3_close(handle)
    }
    handle = nil
  }

  /// busy / hot_journal / missing / other, by extended result code - the
  /// segmentation the diagnostic counter is pre-registered to use.
  static func classify(_ extended: Int) -> String {
    let primary = extended & 0xff
    switch Int32(primary) {
    case SQLITE_BUSY, SQLITE_LOCKED: return "busy"
    case SQLITE_CANTOPEN: return "hot_journal_or_cantopen"
    case SQLITE_READONLY: return "readonly"
    case SQLITE_NOTADB, SQLITE_CORRUPT: return "corrupt"
    default: return "other"
    }
  }

  func account() -> Account? {
    // Exactly one client row per database by construction; anything else is
    // treated as missing rather than picking one (C4: no "first client").
    let rows = query(
      "SELECT homeserver_url, token, user_id FROM client_data LIMIT 2",
      bindings: []
    )
    guard rows.count == 1, let row = rows.first,
      let homeserver = row[0], let token = row[1], let userId = row[2],
      !homeserver.isEmpty, !token.isEmpty, !userId.isEmpty
    else {
      return nil
    }
    return Account(homeserver: homeserver, token: token, userId: userId)
  }

  func sessionPickle(roomId: String, sessionId: String) -> String? {
    let rows = query(
      "SELECT pickle FROM inbound_group_session WHERE room_id = ? AND session_id = ? LIMIT 1",
      bindings: [roomId, sessionId]
    )
    return rows.first?.first ?? nil
  }

  /// E5: read exactly the cached Megolm backup secret and no other SSSS
  /// record. This method is called only from the `session_missing` branch in
  /// `NSEDecrypt`; keeping the discriminator in the SQL prevents a caller from
  /// selecting either cross-signing secret by accident.
  func backupPrivateKey() -> [UInt8]? {
    guard let handle else { return nil }
    var statement: OpaquePointer?
    let sql = "SELECT content FROM s_s_s_s_cache_data WHERE type = ? LIMIT 2"
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
      let stmt = statement
    else {
      return nil
    }
    defer { sqlite3_finalize(stmt) }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    sqlite3_bind_text(stmt, 1, "m.megolm_backup.v1", -1, transient)
    guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
    let byteCount = Int(sqlite3_column_bytes(stmt, 0))
    guard byteCount > 0, byteCount <= 64, let address = sqlite3_column_blob(stmt, 0) else {
      return nil
    }
    var encoded = Data(bytes: address, count: byteCount)
    // A second row is ambiguous even though `type` is expected to be the
    // primary key. Fail closed rather than selecting one.
    guard sqlite3_step(stmt) == SQLITE_DONE else {
      encoded.resetBytes(in: 0..<encoded.count)
      return nil
    }
    let remainder = encoded.count % 4
    if remainder != 0 {
      encoded.append(contentsOf: repeatElement(UInt8(ascii: "="), count: 4 - remainder))
    }
    defer { encoded.resetBytes(in: 0..<encoded.count) }
    guard var decoded = Data(base64Encoded: encoded), decoded.count == 32 else {
      return nil
    }
    defer { decoded.resetBytes(in: 0..<decoded.count) }
    return [UInt8](decoded)
  }

  func memberDisplayName(roomId: String, userId: String) -> String? {
    let rows = query(
      "SELECT content FROM room_members WHERE room_id = ? AND user_id = ? LIMIT 1",
      bindings: [roomId, userId]
    )
    guard let row = rows.first?.first ?? nil,
      let content = Self.eventContent(row),
      let name = content["displayname"] as? String, !name.isEmpty
    else {
      return nil
    }
    return name
  }

  /// The drift store writes the WHOLE event (`event.toJson()`) into the
  /// `content` column of `room_members` and both state tables, so the
  /// fields live one level down. A bare content map is accepted too, so a
  /// storage change in that direction degrades to nothing rather than to a
  /// wrong name. (The first device run read the top level and silently fell
  /// back to the localpart.)
  private static func eventContent(_ row: String) -> [String: Any]? {
    guard let json = Self.json(row) else { return nil }
    if let content = json["content"] as? [String: Any] {
      return content
    }
    return json["type"] == nil ? json : nil
  }

  /// The room-scoped display name the app lets members set for each other:
  /// a state event of type `chat.intergalactic.app.room_display_names`
  /// (state key "", `users: {userId: name | {displayname}}`), with the older
  /// per-member `chat.intergalactic.app.member_profile` form as fallback
  /// (state key `member:<percent-encoded user id>`, or the bare id). Mirrors
  /// `MatrixRoom.getMemberRoomDisplayName` in the host, table for table.
  func roomDisplayName(roomId: String, userId: String) -> String? {
    if let content = stateContent(roomId: roomId, type: "chat.intergalactic.app.room_display_names", stateKey: ""),
      let users = content["users"] as? [String: Any] {
      let raw = users[userId]
      let name = (raw as? String) ?? ((raw as? [String: Any])?["displayname"] as? String)
      if let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
        return trimmed
      }
    }
    let encoded = userId.addingPercentEncoding(withAllowedCharacters: Self.dartComponentAllowed) ?? userId
    for stateKey in ["member:\(encoded)", userId] {
      if let content = stateContent(roomId: roomId, type: "chat.intergalactic.app.member_profile", stateKey: stateKey) {
        let name = (content["room_display_name"] as? String) ?? (content["displayname"] as? String)
        if let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
          return trimmed
        }
      }
    }
    return nil
  }

  /// What Dart's `Uri.encodeComponent` leaves unencoded.
  private static let dartComponentAllowed: CharacterSet = {
    var set = CharacterSet.alphanumerics
    set.insert(charactersIn: "-_.!~*'()")
    return set
  }()

  private func stateContent(roomId: String, type: String, stateKey: String) -> [String: Any]? {
    for table in ["preload_room_state", "non_preload_room_state"] {
      let rows = query(
        "SELECT content FROM \(table) WHERE room_id = ? AND type = ? AND state_key = ? LIMIT 1",
        bindings: [roomId, type, stateKey]
      )
      if let row = rows.first?.first ?? nil, let content = Self.eventContent(row) {
        return content
      }
    }
    return nil
  }

  func roomName(roomId: String) -> String? {
    for table in ["preload_room_state", "non_preload_room_state"] {
      let rows = query(
        "SELECT content FROM \(table) WHERE room_id = ? AND type = 'm.room.name' AND state_key = '' LIMIT 1",
        bindings: [roomId]
      )
      if let row = rows.first?.first ?? nil, let content = Self.eventContent(row),
        let name = content["name"] as? String, !name.isEmpty {
        return name
      }
    }
    return nil
  }

  private static func json(_ text: String) -> [String: Any]? {
    guard let data = text.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }

  /// Rows of optional text columns. Any error yields no rows; the caller
  /// treats that as "not found", which is the fail-closed direction.
  private func query(_ sql: String, bindings: [String]) -> [[String?]] {
    guard let handle else { return [] }
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let stmt = statement else {
      return []
    }
    defer { sqlite3_finalize(stmt) }
    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    for (index, value) in bindings.enumerated() {
      sqlite3_bind_text(stmt, Int32(index + 1), value, -1, transient)
    }
    var rows: [[String?]] = []
    while true {
      let rc = sqlite3_step(stmt)
      if rc == SQLITE_ROW {
        let count = Int(sqlite3_column_count(stmt))
        var row: [String?] = []
        for column in 0..<count {
          if let text = sqlite3_column_text(stmt, Int32(column)) {
            row.append(String(cString: text))
          } else {
            row.append(nil)
          }
        }
        rows.append(row)
      } else {
        break
      }
    }
    return rows
  }
}

// MARK: - Fetch (C4, C5)

struct NSEBackupSession {
  let ephemeral: String
  let mac: String
  let ciphertext: String
}

final class NSEFetch: NSObject, URLSessionTaskDelegate {
  private let budget: NSEBudget
  private(set) var eventAttempts = 0
  private static let requestTimeout: TimeInterval = 8
  private static let resourceTimeout: TimeInterval = 12
  /// `event` historically allowed the URLSession resource timeout plus one
  /// second for its semaphore handoff. Keep that same envelope when a request
  /// timeout leaves enough of it for one short retry.
  private static let eventFetchWindow: TimeInterval = resourceTimeout + 1
  private static let maxBodyBytes = 2 * 1024 * 1024
  private static let maxBackupBodyBytes = 64 * 1024
  private static let backupVersionPattern = "^[A-Za-z0-9._-]{1,32}$"
  private static let pathAllowed: CharacterSet = {
    var set = CharacterSet.alphanumerics
    set.insert(charactersIn: "-._~")
    return set
  }()

  init(budget: NSEBudget) {
    self.budget = budget
  }

  func event(homeserver: String, token: String, payload: NSEPayload) -> Result<[String: Any], NSEFailure> {
    // The origin comes from the database only, and must be https.
    guard var components = URLComponents(string: homeserver), components.scheme == "https",
      let host = components.host, !host.isEmpty
    else {
      return .failure(NSEFailure(reason: "origin_invalid", code: 0))
    }
    guard let room = payload.roomId.addingPercentEncoding(withAllowedCharacters: Self.pathAllowed),
      let event = payload.eventId.addingPercentEncoding(withAllowedCharacters: Self.pathAllowed)
    else {
      return .failure(NSEFailure(reason: "encode_failed", code: 0))
    }
    // Only this endpoint. Any path on the stored origin is replaced. The
    // segments are already percent-encoded, so set the encoded path directly;
    // `path` would re-encode the '%' signs.
    components.percentEncodedPath = "/_matrix/client/v3/rooms/\(room)/event/\(event)"
    components.query = nil
    components.fragment = nil
    guard let url = components.url else {
      return .failure(NSEFailure(reason: "url_invalid", code: 0))
    }

    guard budget.allows(NSEBudget.minimumRequest) else {
      return .failure(NSEFailure(reason: "budget_exhausted", code: 0))
    }
    let deadline = Date().addingTimeInterval(budget.clamp(Self.eventFetchWindow))
    let first = eventAttempt(url: url, token: token, deadline: deadline)
    guard case .failure(let failure) = first,
      failure.reason == "transport", failure.code == NSURLErrorTimedOut,
      deadline.timeIntervalSinceNow >= NSEBudget.minimumRequest + 1
    else {
      return first
    }

    // A request timeout normally fires at eight seconds. The former 13-second
    // event-fetch envelope therefore has room for one short attempt. Retrying
    // only -1001 avoids repeating HTTP, authentication, parsing, or arbitrary
    // transport failures and does not reduce the later pipeline's total budget.
    return eventAttempt(url: url, token: token, deadline: deadline)
  }

  private func eventAttempt(
    url: URL, token: String, deadline: Date
  ) -> Result<[String: Any], NSEFailure> {
    let available = min(deadline.timeIntervalSinceNow, budget.remaining())
    guard available >= NSEBudget.minimumRequest else {
      return .failure(NSEFailure(reason: "budget_exhausted", code: 0))
    }
    // Preserve one second for the synchronous semaphore handoff, matching the
    // pre-retry implementation's resourceTimeout + 1 wait.
    let resourceTimeout = min(Self.resourceTimeout, max(1, available - 1))
    let requestTimeout = min(Self.requestTimeout, resourceTimeout)

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.timeoutInterval = requestTimeout

    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = requestTimeout
    configuration.timeoutIntervalForResource = resourceTimeout
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    defer { session.invalidateAndCancel() }

    let semaphore = DispatchSemaphore(value: 0)
    var outcome: Result<[String: Any], NSEFailure> = .failure(NSEFailure(reason: "no_response", code: 0))
    let task = session.dataTask(with: request) { data, response, error in
      defer { semaphore.signal() }
      if let error = error as NSError? {
        outcome = .failure(NSEFailure(reason: "transport", code: error.code))
        return
      }
      guard let http = response as? HTTPURLResponse else {
        outcome = .failure(NSEFailure(reason: "no_http_response", code: 0))
        return
      }
      switch http.statusCode {
      case 200:
        guard let data, data.count <= Self.maxBodyBytes,
          let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
          outcome = .failure(NSEFailure(reason: "body_invalid", code: 0))
          return
        }
        outcome = .success(json)
      case 401, 403:
        // C5: stop. Never refresh, never re-authenticate, never write.
        outcome = .failure(NSEFailure(reason: "unauthorized", code: http.statusCode))
      default:
        outcome = .failure(NSEFailure(reason: "http_status", code: http.statusCode))
      }
    }
    eventAttempts += 1
    task.resume()
    if semaphore.wait(timeout: .now() + resourceTimeout + 1) == .timedOut {
      task.cancel()
      return .failure(NSEFailure(reason: "timeout", code: 0))
    }
    return outcome
  }

  /// E1-E4: fetch exactly one backed-up session. The version comes from the
  /// host handoff; this process never discovers it from `/room_keys/version`.
  func backupSession(
    homeserver: String,
    token: String,
    roomId: String,
    sessionId: String,
    version: String
  ) -> Result<NSEBackupSession, NSEFailure> {
    guard version.range(of: Self.backupVersionPattern, options: .regularExpression) != nil else {
      return .failure(NSEFailure(reason: "version_invalid", code: 0))
    }
    guard var components = URLComponents(string: homeserver), components.scheme == "https",
      let host = components.host, !host.isEmpty,
      let room = roomId.addingPercentEncoding(withAllowedCharacters: Self.pathAllowed),
      let session = sessionId.addingPercentEncoding(withAllowedCharacters: Self.pathAllowed)
    else {
      return .failure(NSEFailure(reason: "origin_or_path_invalid", code: 0))
    }
    components.percentEncodedPath = "/_matrix/client/v3/room_keys/keys/\(room)/\(session)"
    components.queryItems = [URLQueryItem(name: "version", value: version)]
    components.fragment = nil
    guard let url = components.url else {
      return .failure(NSEFailure(reason: "url_invalid", code: 0))
    }

    let available = budget.remaining()
    guard available >= NSEBudget.minimumRequest + 2 else {
      return .failure(NSEFailure(reason: "budget_exhausted", code: 0))
    }
    // Leave time to decrypt the fetched session before the extension deadline.
    let resourceTimeout = min(Self.resourceTimeout, available - 2)
    let requestTimeout = min(Self.requestTimeout, resourceTimeout)
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.timeoutInterval = requestTimeout

    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = requestTimeout
    configuration.timeoutIntervalForResource = resourceTimeout
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    let download = NSEBoundedDownload(maxBytes: Self.maxBackupBodyBytes)
    let sessionClient = URLSession(configuration: configuration, delegate: download, delegateQueue: nil)
    defer { sessionClient.invalidateAndCancel() }
    let task = sessionClient.dataTask(with: request)
    task.resume()
    if download.finished.wait(timeout: .now() + min(resourceTimeout + 1, max(0, budget.remaining() - 2))) == .timedOut {
      task.cancel()
      return .failure(NSEFailure(reason: "timeout", code: 0))
    }
    let data: Data
    switch download.outcome {
    case .failure(let failure):
      return .failure(failure)
    case .success(let value):
      data = value
    }
    guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let sessionData = json["session_data"] as? [String: Any],
      let ephemeral = sessionData["ephemeral"] as? String,
      let mac = sessionData["mac"] as? String,
      let ciphertext = sessionData["ciphertext"] as? String,
      !ephemeral.isEmpty, ephemeral.utf8.count <= 44,
      !mac.isEmpty, mac.utf8.count <= 128,
      !ciphertext.isEmpty, ciphertext.utf8.count <= Self.maxBackupBodyBytes
    else {
      return .failure(NSEFailure(reason: "body_invalid", code: 0))
    }
    return .success(NSEBackupSession(ephemeral: ephemeral, mac: mac, ciphertext: ciphertext))
  }

  /// The authenticated media download for one attachment (the second and
  /// last endpoint C5 permits), bounded by `maxBytes` while it streams so an
  /// oversized body is cancelled rather than buffered.
  func media(homeserver: String, token: String, mxc: NSEAttachment.Mxc, maxBytes: Int) -> Result<Data, NSEFailure> {
    guard var components = URLComponents(string: homeserver), components.scheme == "https",
      let host = components.host, !host.isEmpty
    else {
      return .failure(NSEFailure(reason: "origin_invalid", code: 0))
    }
    guard let server = mxc.server.addingPercentEncoding(withAllowedCharacters: Self.pathAllowed),
      let mediaId = mxc.mediaId.addingPercentEncoding(withAllowedCharacters: Self.pathAllowed)
    else {
      return .failure(NSEFailure(reason: "encode_failed", code: 0))
    }
    components.percentEncodedPath = "/_matrix/client/v1/media/download/\(server)/\(mediaId)"
    components.query = nil
    components.fragment = nil
    guard let url = components.url else {
      return .failure(NSEFailure(reason: "url_invalid", code: 0))
    }

    guard budget.allows(NSEBudget.minimumRequest) else {
      return .failure(NSEFailure(reason: "budget_exhausted", code: 0))
    }
    let resourceTimeout = budget.clamp(Self.mediaResourceTimeout)
    let requestTimeout = min(Self.mediaRequestTimeout, resourceTimeout)

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.timeoutInterval = requestTimeout

    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = requestTimeout
    configuration.timeoutIntervalForResource = resourceTimeout
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    let download = NSEBoundedDownload(maxBytes: maxBytes)
    let session = URLSession(configuration: configuration, delegate: download, delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    let task = session.dataTask(with: request)
    task.resume()
    if download.finished.wait(timeout: .now() + resourceTimeout + 1) == .timedOut {
      task.cancel()
      return .failure(NSEFailure(reason: "timeout", code: 0))
    }
    return download.outcome
  }

  private static let mediaRequestTimeout: TimeInterval = 6
  private static let mediaResourceTimeout: TimeInterval = 8

  /// No redirects of an authenticated request, cross-origin or otherwise.
  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}

/// Accumulates one authenticated response body under a hard streaming cap;
/// refuses redirects; 401/403 stop without retry or credential refresh.
final class NSEBoundedDownload: NSObject, URLSessionDataDelegate {
  let finished = DispatchSemaphore(value: 0)
  private(set) var outcome: Result<Data, NSEFailure> = .failure(NSEFailure(reason: "no_response", code: 0))
  private let maxBytes: Int
  private var buffer = Data()
  private var failed = false

  init(maxBytes: Int) {
    self.maxBytes = maxBytes
  }

  func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    guard let http = response as? HTTPURLResponse else {
      fail(NSEFailure(reason: "no_http_response", code: 0)); completionHandler(.cancel); return
    }
    switch http.statusCode {
    case 200:
      if http.expectedContentLength > Int64(maxBytes) {
        fail(NSEFailure(reason: "too_large", code: 0)); completionHandler(.cancel); return
      }
      completionHandler(.allow)
    case 401, 403:
      fail(NSEFailure(reason: "unauthorized", code: http.statusCode)); completionHandler(.cancel)
    default:
      fail(NSEFailure(reason: "http_status", code: http.statusCode)); completionHandler(.cancel)
    }
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    guard !failed else { return }
    buffer.append(data)
    if buffer.count > maxBytes {
      fail(NSEFailure(reason: "too_large", code: 0))
      dataTask.cancel()
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    defer { finished.signal() }
    if failed { return }
    if let error = error as NSError? {
      outcome = .failure(NSEFailure(reason: "transport", code: error.code))
      return
    }
    outcome = buffer.isEmpty ? .failure(NSEFailure(reason: "body_invalid", code: 0)) : .success(buffer)
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }

  private func fail(_ failure: NSEFailure) {
    if !failed {
      failed = true
      outcome = .failure(failure)
      buffer = Data()
    }
  }
}

// MARK: - Attachment (C7)

enum NSEAttachment {
  /// The class of what happened to the preview, carried as the integer code
  /// on the rendered outcome's log line. Integers only (C8).
  enum Code: Int, Error {
    case none = 0
    case attached = 1
    case mediaOff = 2
    case candidateUnsupported = 3
    case downloadFailed = 4
    case downloadUnauthorized = 5
    case integrityFailed = 6
    case decodeFailed = 7
    case fileFailed = 8
    case attachFailed = 9
    /// The invocation's total budget could not cover a download (C4/C5).
    case budgetExhausted = 10
  }

  struct Mxc {
    let server: String
    let mediaId: String
  }

  struct Envelope {
    let key: Data
    let iv: Data
    let sha256: Data
  }

  struct Candidate {
    let mxc: Mxc
    let envelope: Envelope?
  }

  /// A thumbnail smaller than this on either side is the app's 64 px
  /// placeholder, which renders as a blur; the full file is preferred then,
  /// with the thumbnail kept as the fallback when the full file is over the
  /// cap.
  private static let usefulThumbnailSide = 256

  private static let allowedMimeTypes: Set<String> = ["image/jpeg", "image/png", "image/gif", "image/webp"]
  private static let allowedUTIs: Set<String> = ["public.jpeg", "public.png", "com.compuserve.gif", "org.webmproject.webp", "public.webp"]
  private static let maxDownloadBytes = 6 * 1024 * 1024
  private static let maxSourceSide = 16_384
  private static let maxSourcePixels = 40_000_000
  private static let thumbnailMaxSide = 1024
  private static let directoryName = "intergalactic-nse-previews"
  private static let maximumAge: TimeInterval = 24 * 60 * 60
  private static let outputUTI = "public.png"

  /// The media an image or sticker event refers to, in the order to try:
  /// a usefully sized thumbnail first, otherwise the full file with the
  /// small thumbnail as fallback. Empty for every other event and for
  /// anything outside the allowlists.
  static func candidates(type: String, content: [String: Any]) -> [Candidate] {
    let isImage: Bool
    switch type {
    case "m.room.message": isImage = (content["msgtype"] as? String) == "m.image"
    case "m.sticker": isImage = true
    default: isImage = false
    }
    guard isImage else { return [] }
    let info = content["info"] as? [String: Any] ?? [:]
    let thumbnailInfo = info["thumbnail_info"] as? [String: Any] ?? [:]
    let thumbnail = parse(
      file: info["thumbnail_file"], url: info["thumbnail_url"], mimetype: thumbnailInfo["mimetype"]
    )
    let full = parse(file: content["file"], url: content["url"], mimetype: info["mimetype"])
    let width = thumbnailInfo["w"] as? Int ?? 0
    let height = thumbnailInfo["h"] as? Int ?? 0
    let thumbnailUseful = width >= usefulThumbnailSide && height >= usefulThumbnailSide
    let ordered = thumbnailUseful ? [thumbnail, full] : [full, thumbnail]
    return ordered.compactMap { $0 }
  }

  private static func parse(file: Any?, url: Any?, mimetype: Any?) -> Candidate? {
    guard let declared = (mimetype as? String)?.split(separator: ";").first?
      .trimmingCharacters(in: .whitespaces).lowercased(),
      allowedMimeTypes.contains(declared)
    else {
      return nil
    }
    if let file = file as? [String: Any] {
      guard let mxc = Self.mxc(file["url"]),
        let key = file["key"] as? [String: Any],
        (key["alg"] as? String) == "A256CTR", (key["kty"] as? String) == "oct",
        let keyData = base64(key["k"]), keyData.count == 32,
        let iv = base64(file["iv"]), iv.count == 16,
        let hashes = file["hashes"] as? [String: Any],
        let sha = base64(hashes["sha256"]), sha.count == 32
      else {
        return nil
      }
      return Candidate(mxc: mxc, envelope: Envelope(key: keyData, iv: iv, sha256: sha))
    }
    guard let mxc = Self.mxc(url) else { return nil }
    return Candidate(mxc: mxc, envelope: nil)
  }

  private static func mxc(_ value: Any?) -> Mxc? {
    guard let text = value as? String, text.count <= 512,
      text.range(of: "^mxc://[A-Za-z0-9.\\-]+(:[0-9]{1,5})?/[A-Za-z0-9_\\-]+$", options: .regularExpression) != nil
    else {
      return nil
    }
    let rest = text.dropFirst("mxc://".count)
    let parts = rest.split(separator: "/", maxSplits: 1)
    guard parts.count == 2 else { return nil }
    return Mxc(server: String(parts[0]), mediaId: String(parts[1]))
  }

  /// Standard or URL-safe alphabet, padded or not (the spec's `k` is
  /// unpadded URL-safe; `iv` and the hash are unpadded standard).
  private static func base64(_ value: Any?) -> Data? {
    guard var text = value as? String, !text.isEmpty, text.count <= 128 else { return nil }
    text = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    while text.count % 4 != 0 { text.append("=") }
    return Data(base64Encoded: text)
  }

  /// Download, verify, decrypt, decode, write, protect, attach. Any failure
  /// removes what was written and reports its class; the caller keeps the
  /// text-only notification.
  static func prepare(
    candidate: Candidate, account: NSEDatabase.Account, budget: NSEBudget
  ) -> Result<UNNotificationAttachment, Code> {
    let fetch = NSEFetch(budget: budget)
    var bytes: Data
    switch fetch.media(
      homeserver: account.homeserver, token: account.token, mxc: candidate.mxc, maxBytes: maxDownloadBytes
    ) {
    case .failure(let failure):
      switch failure.reason {
      case "unauthorized": return .failure(.downloadUnauthorized)
      case "budget_exhausted": return .failure(.budgetExhausted)
      default: return .failure(.downloadFailed)
      }
    case .success(let data):
      bytes = data
    }

    if let envelope = candidate.envelope {
      // Hash over the ciphertext first, as the spec orders it, then AES-CTR.
      guard Data(SHA256.hash(data: bytes)) == envelope.sha256,
        let plain = aesCtr(bytes, key: envelope.key, iv: envelope.iv)
      else {
        return .failure(.integrityFailed)
      }
      bytes = plain
    }

    guard let image = decode(bytes) else {
      return .failure(.decodeFailed)
    }
    bytes = Data()

    guard let url = write(image) else {
      return .failure(.fileFailed)
    }
    guard protect(url) else {
      try? FileManager.default.removeItem(at: url)
      return .failure(.fileFailed)
    }
    do {
      let attachment = try UNNotificationAttachment(
        identifier: "chat.intergalactic.preview", url: url,
        options: [UNNotificationAttachmentOptionsTypeHintKey: outputUTI]
      )
      return .success(attachment)
    } catch {
      try? FileManager.default.removeItem(at: url)
      return .failure(.attachFailed)
    }
  }

  static func aesCtr(_ data: Data, key: Data, iv: Data) -> Data? {
    var cryptor: CCCryptorRef?
    let created = key.withUnsafeBytes { keyBytes in
      iv.withUnsafeBytes { ivBytes in
        CCCryptorCreateWithMode(
          CCOperation(kCCDecrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES), CCPadding(ccNoPadding),
          ivBytes.baseAddress, keyBytes.baseAddress, key.count, nil, 0, 0,
          CCModeOptions(kCCModeOptionCTR_BE), &cryptor
        )
      }
    }
    guard created == kCCSuccess, let cryptor else { return nil }
    defer { CCCryptorRelease(cryptor) }
    var output = Data(count: CCCryptorGetOutputLength(cryptor, data.count, true))
    var moved = 0
    let updated = data.withUnsafeBytes { input in
      output.withUnsafeMutableBytes { out in
        CCCryptorUpdate(cryptor, input.baseAddress, data.count, out.baseAddress, out.count, &moved)
      }
    }
    guard updated == kCCSuccess else { return nil }
    output.count = moved
    return output
  }

  /// A bounded thumbnail, never the full-resolution frame: the source's
  /// declared dimensions are checked before any pixel is decoded, and the
  /// container type must be one the allowlist names.
  private static func decode(_ data: Data) -> CGImage? {
    let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary),
      let uti = CGImageSourceGetType(source) as String?, allowedUTIs.contains(uti),
      CGImageSourceGetCount(source) >= 1,
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0, width <= maxSourceSide, height <= maxSourceSide,
      width * height <= maxSourcePixels
    else {
      return nil
    }
    let thumbnailOptions: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxSide,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
  }

  private static func write(_ image: CGImage) -> URL? {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent(directoryName, isDirectory: true)
    let manager = FileManager.default
    do {
      try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      return nil
    }
    sweep(directory)
    let url = directory.appendingPathComponent(UUID().uuidString + ".png")
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, outputUTI as CFString, 1, nil) else {
      return nil
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      try? manager.removeItem(at: url)
      return nil
    }
    return url
  }

  /// Set the class and read it back, as the host does for its own previews.
  private static func protect(_ url: URL) -> Bool {
    let manager = FileManager.default
    let wanted = FileProtectionType.completeUntilFirstUserAuthentication
    do {
      try manager.setAttributes([.protectionKey: wanted], ofItemAtPath: url.path)
      let read = try manager.attributesOfItem(atPath: url.path)[.protectionKey] as? FileProtectionType
      return read == wanted
    } catch {
      return false
    }
  }

  /// Orphans older than a day, left by an invocation that died between the
  /// write and the hand-over. The notification centre moves attached files
  /// out, and every failure path removes its own.
  private static func sweep(_ directory: URL) {
    let manager = FileManager.default
    guard let entries = try? manager.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: []
    ) else { return }
    let cutoff = Date().addingTimeInterval(-maximumAge)
    for entry in entries {
      let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
      if let modified, modified < cutoff {
        try? manager.removeItem(at: entry)
      }
    }
  }
}

// MARK: - Diagnostic counter (S&C D1-D6)

/// The extension's one write outside the database: an AGGREGATE of database
/// open outcomes, kept so the rollback-journal-versus-WAL question can be
/// decided on measurement rather than guessed (S&C ruling of 2026-08-14,
/// conditions D1-D6; pre-registrations 12-15 of the Phase B record).
///
/// Counters, not events (D1): one saturating counter per outcome, a bounded
/// map of extended SQLite result codes, the CURRENT failure streak (class,
/// run count, start minute - one value, overwritten in place) and closed
/// streaks as a fixed duration histogram. No identifiers, no paths, no error
/// strings, no per-push record. Fixed key set and a 4 KB ceiling that
/// disables the write rather than truncating (D2). Protection class set on
/// the directory and the file and READ BACK, backup excluded, fail closed
/// with no file left behind (D3). One file at one fixed path in a directory
/// used for nothing else, never the database (D4). The host reads it only as
/// this aggregate (D5). The extension stops writing 90 days after the window
/// opened and the host deletes it then, on logout and on data reset (D6).
///
/// Two honest gaps, recorded for S&C: the second D1 axis ("background
/// execution active") is not observable from an extension, so the single
/// axis value is `unknown`; and `timeout` has no producer at this stage -
/// `sqlite3_busy_timeout` is set AFTER `sqlite3_open_v2` returns, so a busy
/// OPEN never waited and the timeout governs later statements only. Moving
/// the timeout ahead of the open would change the open's blocking inside
/// the extension's budget; do not. `timeout` stays 0 by construction.
/// `other` outcomes (readonly, corrupt, unclassified) count in the
/// extended-code map only and neither open nor close a streak.
enum NSEDiagnostics {
  enum Report: Int {
    case written = 0
    case writeFailed = 1
    case disabled = 2
    case expired = 3
  }

  static let directoryName = "nse-diagnostics"
  static let fileName = "db-read-counter.json"
  static let lockFileName = "db-read-counter.lock"
  /// How long an invocation waits for the counter lock before giving up. The
  /// extension's budget is short and a push delivery must not queue behind
  /// another invocation's write, so contention fails closed to `.writeFailed`
  /// rather than blocking. A lost sample is a smaller error than a late push.
  static let lockTimeout: TimeInterval = 0.25
  static let version = 1
  static let maxBytes = 4 * 1024
  static let saturation = 1_000_000
  static let maxExtendedCodes = 16
  static let windowDays = 90
  static let outcomes = ["ok", "busy", "hot_journal", "missing", "timeout"]
  static let axis = "unknown"
  static let durationBuckets: [(String, TimeInterval)] = [
    ("lt1m", 60), ("lt5m", 300), ("lt30m", 1800), ("lt2h", 7200), ("lt12h", 43200), ("lt24h", 86400),
  ]
  static let lastBucket = "ge24h"

  static func outcome(forOpenFailure reason: String) -> String {
    switch reason {
    case "missing": return "missing"
    case "busy": return "busy"
    case "hot_journal_or_cantopen": return "hot_journal"
    default: return "other"
    }
  }

  /// Records one database open outcome and writes the file. `other` outcomes
  /// (readonly, corrupt, unclassified) count in the extended-code map only.
  static func record(container: URL, outcome: String, extendedCode: Int, now: Date = Date()) -> Report {
    let directory = container.appendingPathComponent(directoryName, isDirectory: true)
    return withLock(directory: directory) {
      recordLocked(container: container, outcome: outcome, extendedCode: extendedCode, now: now)
    }
  }

  /// Serialises `recordLocked`'s read-modify-write across concurrent
  /// invocations. iOS runs one Notification Service Extension process per
  /// push and several pushes can be delivered at once. Without this, two
  /// invocations load the same document, each applies its own increment, and
  /// the second write discards the first. `replaceItemAt` keeps the file
  /// itself intact, so the loss is silent: the aggregate undercounts and the
  /// streak record interleaves into a value describing neither invocation -
  /// biasing exactly the burst case the counter exists to measure.
  private static func withLock(directory: URL, _ body: () -> Report) -> Report {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let lockPath = directory.appendingPathComponent(lockFileName).path
    // `Darwin.` qualified throughout: this enum declares its own `close`.
    let descriptor = Darwin.open(lockPath, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { return .writeFailed }
    defer { Darwin.close(descriptor) }
    _ = protect(lockPath)
    let deadline = Date().addingTimeInterval(lockTimeout)
    while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
      guard errno == EWOULDBLOCK, Date() < deadline else { return .writeFailed }
      usleep(5_000)
    }
    defer { _ = flock(descriptor, LOCK_UN) }
    return body()
  }

  private static func recordLocked(
    container: URL, outcome: String, extendedCode: Int, now: Date
  ) -> Report {
    let directory = container.appendingPathComponent(directoryName, isDirectory: true)
    let url = directory.appendingPathComponent(fileName)
    var doc = load(url) ?? fresh(now: now)
    guard let opened = doc["window_opened_day"] as? String, let openedDate = day(from: opened) else {
      doc = fresh(now: now)
      return apply(&doc, directory: directory, url: url, outcome: outcome, extendedCode: extendedCode, now: now)
    }
    if now.timeIntervalSince(openedDate) > TimeInterval(windowDays) * 86400 {
      return .expired
    }
    return apply(&doc, directory: directory, url: url, outcome: outcome, extendedCode: extendedCode, now: now)
  }

  private static func apply(
    _ doc: inout [String: Any], directory: URL, url: URL, outcome: String, extendedCode: Int, now: Date
  ) -> Report {
    var counters = doc["counters"] as? [String: Int] ?? [:]
    if outcomes.contains(outcome) {
      let key = "\(outcome).\(axis)"
      counters[key] = saturate((counters[key] ?? 0) + 1)
    }
    doc["counters"] = counters

    if outcome != "ok" {
      var codes = doc["extended_codes"] as? [String: Int] ?? [:]
      let key = String(extendedCode)
      if codes[key] != nil || codes.count < maxExtendedCodes {
        codes[key] = saturate((codes[key] ?? 0) + 1)
      } else {
        codes["other"] = saturate((codes["other"] ?? 0) + 1)
      }
      doc["extended_codes"] = codes
    }

    // Streaks: only the D1 outcome classes form runs.
    let minute = Int(now.timeIntervalSince1970 / 60)
    let streak = doc["streak"] as? [String: Any]
    if outcome == "ok" {
      if let streak { close(streak, now: now, into: &doc) }
      doc["streak"] = nil
    } else if outcomes.contains(outcome) {
      if let streak, (streak["outcome"] as? String) == outcome {
        var updated = streak
        updated["runs"] = saturate((streak["runs"] as? Int ?? 0) + 1)
        doc["streak"] = updated
      } else {
        if let streak { close(streak, now: now, into: &doc) }
        doc["streak"] = ["outcome": outcome, "runs": 1, "started_minute": minute]
      }
    }

    guard let data = try? JSONSerialization.data(withJSONObject: doc, options: [.sortedKeys]),
      data.count <= maxBytes
    else {
      return .disabled
    }
    return write(data, directory: directory, url: url) ? .written : .writeFailed
  }

  private static func close(_ streak: [String: Any], now: Date, into doc: inout [String: Any]) {
    guard let outcome = streak["outcome"] as? String, let started = streak["started_minute"] as? Int else { return }
    let duration = now.timeIntervalSince(Date(timeIntervalSince1970: TimeInterval(started) * 60))
    var bucket = lastBucket
    for (name, limit) in durationBuckets where duration < limit {
      bucket = name
      break
    }
    var closed = doc["closed_streaks"] as? [String: [String: Int]] ?? [:]
    var perOutcome = closed[outcome] ?? [:]
    perOutcome[bucket] = saturate((perOutcome[bucket] ?? 0) + 1)
    closed[outcome] = perOutcome
    doc["closed_streaks"] = closed
  }

  private static func saturate(_ value: Int) -> Int { min(value, saturation) }

  private static func fresh(now: Date) -> [String: Any] {
    ["version": version, "window_opened_day": dayString(now), "counters": [String: Int](),
     "extended_codes": [String: Int](), "closed_streaks": [String: [String: Int]]()]
  }

  /// D2 (S&C C2): the document is REBUILT from the fixed key set on load.
  /// Anything on disk outside that set - a key another target in the group
  /// wrote, or a value of the wrong type - is dropped rather than carried
  /// forward, so the extension never re-writes a key it did not author and
  /// the 4 KB ceiling is unreachable from outside.
  private static func load(_ url: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: url), data.count <= maxBytes,
      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      (json["version"] as? Int) == version,
      let opened = json["window_opened_day"] as? String, day(from: opened) != nil
    else { return nil }
    var doc: [String: Any] = ["version": version, "window_opened_day": opened]
    var counters: [String: Int] = [:]
    for outcome in outcomes {
      let key = "\(outcome).\(axis)"
      if let value = (json["counters"] as? [String: Any])?[key] as? Int, value >= 0 { counters[key] = saturate(value) }
    }
    doc["counters"] = counters
    var codes: [String: Int] = [:]
    for (key, value) in (json["extended_codes"] as? [String: Any]) ?? [:] {
      guard let count = value as? Int, count >= 0, key == "other" || Int(key) != nil else { continue }
      if codes.count < maxExtendedCodes + 1 { codes[key] = saturate(count) }
    }
    doc["extended_codes"] = codes
    var closed: [String: [String: Int]] = [:]
    let bucketNames = durationBuckets.map { $0.0 } + [lastBucket]
    for outcome in outcomes {
      guard let histogram = (json["closed_streaks"] as? [String: Any])?[outcome] as? [String: Any] else { continue }
      var kept: [String: Int] = [:]
      for bucket in bucketNames {
        if let count = histogram[bucket] as? Int, count >= 0 { kept[bucket] = saturate(count) }
      }
      if !kept.isEmpty { closed[outcome] = kept }
    }
    doc["closed_streaks"] = closed
    if let streak = json["streak"] as? [String: Any],
      let outcome = streak["outcome"] as? String, outcomes.contains(outcome), outcome != "ok",
      let runs = streak["runs"] as? Int, runs > 0,
      let started = streak["started_minute"] as? Int, started > 0 {
      doc["streak"] = ["outcome": outcome, "runs": saturate(runs), "started_minute": started]
    }
    return doc
  }

  private static let dayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()

  static func dayString(_ date: Date) -> String { dayFormatter.string(from: date) }
  static func day(from text: String) -> Date? { dayFormatter.date(from: text) }

  /// D3, with S&C C1: the DIRECTORY is backup-excluded so every name inside
  /// it is covered, the directory and the file are protected and read back,
  /// the staging file is protected before it holds data and is removed on
  /// every failure path, and the replacement is `replaceItemAt`, which is
  /// atomic and leaves no window with neither file present.
  private static func write(_ data: Data, directory: URL, url: URL) -> Bool {
    let manager = FileManager.default
    let staging = directory.appendingPathComponent(fileName + ".tmp")
    defer { try? manager.removeItem(at: staging) }
    do {
      try manager.createDirectory(at: directory, withIntermediateDirectories: true)
      guard protect(directory.path), excludeFromBackup(directory) else { return false }
      try manager.removeItem(at: staging)
    } catch {
      // A missing staging file is the normal case; anything else falls
      // through to the write and surfaces there.
    }
    do {
      // The staging file exists and is protected BEFORE any data lands in
      // it: create it empty, set and read back the class, then write in
      // place (not `.atomic`, which would write a third file and rename it
      // over this one, losing the attribute just set).
      guard manager.createFile(atPath: staging.path, contents: nil), protect(staging.path) else { return false }
      try data.write(to: staging, options: [])
      if manager.fileExists(atPath: url.path) {
        _ = try manager.replaceItemAt(url, withItemAt: staging, backupItemName: nil, options: [])
      } else {
        try manager.moveItem(at: staging, to: url)
      }
      guard protect(url.path), excludeFromBackup(url) else {
        try? manager.removeItem(at: url)
        return false
      }
      return true
    } catch {
      try? manager.removeItem(at: url)
      return false
    }
  }

  private static func excludeFromBackup(_ url: URL) -> Bool {
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var target = url
    do {
      try target.setResourceValues(values)
      return true
    } catch {
      return false
    }
  }

  private static func protect(_ path: String) -> Bool {
    #if os(iOS)
      let manager = FileManager.default
      let wanted = FileProtectionType.completeUntilFirstUserAuthentication
      do {
        try manager.setAttributes([.protectionKey: wanted], ofItemAtPath: path)
        return (try manager.attributesOfItem(atPath: path)[.protectionKey] as? FileProtectionType) == wanted
      } catch {
        return false
      }
    #else
      return true
    #endif
  }
}

// MARK: - Decrypt (Megolm only)

enum NSEDecrypt {
  enum Source: String {
    case local
    case backup
  }

  struct Success {
    let content: [String: Any]
    let source: Source
  }

  private static let algorithm = "m.megolm.v1.aes-sha2"
  private static let backupType = "m.megolm_backup.v1"
  private static let maxEventCiphertextBytes = 64 * 1024
  private static let maxEventPlaintextBytes = 64 * 1024

  static func decrypt(
    content: [String: Any],
    roomId: String,
    userId: String,
    clientId: String,
    container: URL,
    account: NSEDatabase.Account,
    database: NSEDatabase,
    fetch: NSEFetch,
    developerMode: Bool
  ) -> Result<Success, NSEFailure> {
    guard content["algorithm"] as? String == algorithm else {
      return .failure(NSEFailure(reason: "algorithm_unsupported", code: 0))
    }
    guard let sessionId = content["session_id"] as? String, !sessionId.isEmpty,
      let ciphertext = content["ciphertext"] as? String, !ciphertext.isEmpty
    else {
      return .failure(NSEFailure(reason: "content_malformed", code: 0))
    }
    if let pickle = database.sessionPickle(roomId: roomId, sessionId: sessionId) {
      switch decryptLocal(pickle: pickle, ciphertext: ciphertext, userId: userId) {
      case .failure(let failure):
        return .failure(failure)
      case .success(let content):
        return .success(Success(content: content, source: .local))
      }
    }

    // E5: nothing below this line is reachable until the existing read-only
    // local-session lookup has returned exactly `session_missing`. Developer
    // Mode is a protected host snapshot value and is false when absent.
    guard developerMode else {
      return .failure(NSEFailure(reason: "session_missing", code: 0))
    }
    guard ciphertext.utf8.count <= maxEventCiphertextBytes else {
      return .failure(NSEFailure(reason: "backup_event_oversize", code: 0))
    }
    guard let version = NSEBackupVersion.load(container: container, clientId: clientId) else {
      return .failure(NSEFailure(reason: "backup_version_unavailable", code: 0))
    }
    guard var privateKey = database.backupPrivateKey() else {
      return .failure(NSEFailure(reason: "backup_key_unavailable", code: 0))
    }
    defer { wipe(&privateKey) }

    let backup: NSEBackupSession
    switch fetch.backupSession(
      homeserver: account.homeserver,
      token: account.token,
      roomId: roomId,
      sessionId: sessionId,
      version: version
    ) {
    case .failure(let failure):
      // Internal developer evidence distinguishes coarse layers of the
      // bounded fetch without exposing route identifiers, HTTP status,
      // transport codes, or response payloads.
      return .failure(NSEFailure(reason: backupFetchFailureClass(failure), code: 0))
    case .success(let value):
      backup = value
    }
    switch decryptBackupEvent(
      privateKey: &privateKey,
      backup: backup,
      eventCiphertext: ciphertext
    ) {
    case .failure(let failure):
      return .failure(failure)
    case .success(let content):
      return .success(Success(content: content, source: .backup))
    }
  }

  private static func backupFetchFailureClass(_ failure: NSEFailure) -> String {
    switch failure.reason {
    case "unauthorized", "http_status":
      return "backup_fetch_http"
    case "body_invalid", "too_large":
      return "backup_fetch_body"
    case "timeout", "transport", "no_response", "no_http_response":
      return "backup_fetch_transport"
    case "budget_exhausted":
      return "backup_fetch_budget"
    default:
      return "backup_fetch_failed"
    }
  }

  private static func decryptLocal(
    pickle: String, ciphertext: String, userId: String
  ) -> Result<[String: Any], NSEFailure> {
    // The SDK pickles with the Matrix user id's UTF-16 code units, low byte
    // of each, zero-padded or truncated to 32 (pickle_key.dart). ASCII ids
    // make that the ASCII bytes.
    var key = Array(userId.utf16).map { UInt8(truncatingIfNeeded: $0) }
    if key.count < 32 {
      key.append(contentsOf: [UInt8](repeating: 0, count: 32 - key.count))
    } else if key.count > 32 {
      key = Array(key.prefix(32))
    }

    let result = key.withUnsafeBufferPointer { keyBuffer -> IOSDecryptResult in
      pickle.withCString { pickleC in
        ciphertext.withCString { cipherC in
          ios_decrypt_event(pickleC, keyBuffer.baseAddress, cipherC)
        }
      }
    }
    defer { ios_free_result(result) }

    if result.error != nil {
      // The library's message is not logged (C8); the class is enough.
      return .failure(NSEFailure(reason: "decrypt_failed", code: 1))
    }
    guard let plaintext = result.plaintext,
      let data = String(cString: plaintext).data(using: .utf8),
      let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    else {
      return .failure(NSEFailure(reason: "plaintext_malformed", code: 0))
    }
    return .success(json)
  }

  private static func decryptBackupEvent(
    privateKey: inout [UInt8], backup: NSEBackupSession, eventCiphertext: String
  ) -> Result<[String: Any], NSEFailure> {
    let type = [UInt8](backupType.utf8)
    let ephemeral = [UInt8](backup.ephemeral.utf8)
    let mac = [UInt8](backup.mac.utf8)
    let backupCiphertext = [UInt8](backup.ciphertext.utf8)
    let eventCiphertext = [UInt8](eventCiphertext.utf8)

    let result = type.withUnsafeBufferPointer { typeBuffer in
      privateKey.withUnsafeBufferPointer { keyBuffer in
        ephemeral.withUnsafeBufferPointer { ephemeralBuffer in
          mac.withUnsafeBufferPointer { macBuffer in
            backupCiphertext.withUnsafeBufferPointer { backupBuffer in
              eventCiphertext.withUnsafeBufferPointer { eventBuffer in
                ios_decrypt_backup_event_v1(
                  typeBuffer.baseAddress,
                  typeBuffer.count,
                  keyBuffer.baseAddress,
                  keyBuffer.count,
                  ephemeralBuffer.baseAddress,
                  ephemeralBuffer.count,
                  macBuffer.baseAddress,
                  macBuffer.count,
                  backupBuffer.baseAddress,
                  backupBuffer.count,
                  eventBuffer.baseAddress,
                  eventBuffer.count
                )
              }
            }
          }
        }
      }
    }
    defer { ios_backup_event_decrypt_result_free(result) }
    guard result.success == 1, let plaintext = result.plaintext,
      result.plaintext_len > 0, result.plaintext_len <= maxEventPlaintextBytes
    else {
      return .failure(NSEFailure(reason: "backup_failed", code: 0))
    }
    let data = Data(bytes: plaintext, count: result.plaintext_len)
    guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
      return .failure(NSEFailure(reason: "plaintext_malformed", code: 0))
    }
    return .success(json)
  }

  private static func wipe(_ bytes: inout [UInt8]) {
    bytes.withUnsafeMutableBytes { raw in
      guard let address = raw.baseAddress, raw.count > 0 else { return }
      // Unlike final Swift stores or memset, C11 memset_s must not be
      // optimized away. This clears the caller-owned Array storage; it does
      // not claim to erase transient Data, SQLite, register, or Rust copies.
      precondition(Darwin.memset_s(address, raw.count, 0, raw.count) == 0)
    }
    withExtendedLifetime(bytes) {}
  }
}

// MARK: - Rendering

enum NSERender {
  /// Developer-only, closed-set event family. Never log the raw event type,
  /// message body, route, or a derived identifier.
  static func unsupportedFamily(type: String) -> String {
    switch type {
    case "m.room.message": return "unrenderable_message"
    case "chat.intergalactic.story.photo", "chat.intergalactic.story.video":
      return "story_post"
    case "chat.intergalactic.story.reaction": return "story_reaction"
    case "m.reaction": return "reaction"
    case "m.poll.start", "m.poll.response", "m.poll.end": return "poll"
    default: return type.hasPrefix("m.call.") ? "call" : "other"
    }
  }

  /// The text presentation of a message, mirroring the host's
  /// attachment presentations for media. Nil for types the host would not
  /// notify about from a push.
  static func body(type: String, content: [String: Any], senderName: String?) -> String? {
    switch type {
    case "m.room.message":
      let msgtype = content["msgtype"] as? String ?? "m.text"
      let text = plainText(content)
      switch msgtype {
      case "m.text", "m.notice":
        return text.isEmpty ? nil : text
      case "m.emote":
        return text.isEmpty ? nil : "* \(text)"
      case "m.image": return localizedBody("nse.body.image", english: "Sent an image")
      case "m.video": return localizedBody("nse.body.video", english: "Sent a video")
      case "m.audio": return localizedBody("nse.body.audio", english: "Sent an audio message")
      case "m.file": return localizedBody("nse.body.file", english: "Sent a file")
      case "m.location": return localizedBody("nse.body.location", english: "Shared a location")
      default:
        return text.isEmpty ? nil : text
      }
    case "m.sticker":
      return localizedBody("nse.body.sticker", english: "Sent a sticker")
    default:
      return nil
    }
  }

  private static func localizedBody(_ key: String, english: String) -> String {
    Bundle.main.localizedString(forKey: key, value: english, table: "Localizable")
  }

  /// What the host shows: the SDK's `plaintextBody`, which is the HTML
  /// `formatted_body` flattened to text when the format is
  /// `org.matrix.custom.html`, else `body`. Mentions are links whose text is
  /// the name the sender chose, so flattening keeps the name where the raw
  /// body carries the pill's source form. Reply fallbacks are dropped as
  /// the host drops them.
  static func plainText(_ content: [String: Any]) -> String {
    let body = (content["body"] as? String) ?? ""
    guard (content["format"] as? String) == "org.matrix.custom.html",
      let html = content["formatted_body"] as? String, !html.isEmpty
    else {
      return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return htmlToText(html)
  }

  static func htmlToText(_ html: String) -> String {
    var text = html
    // (?s) so '.' spans newlines: String.CompareOptions has no dot-all member,
    // and a reply fallback is normally multi-line. Without it the block
    // survives, the tag strip below leaves the quoted original as plain text,
    // and the 500-character truncation drops the actual reply.
    text = text.replacingOccurrences(
      of: "(?s)<mx-reply>.*?</mx-reply>", with: "",
      options: [.regularExpression, .caseInsensitive]
    )
    text = text.replacingOccurrences(
      of: "<br\\s*/?>|</p>|</div>|</li>|</blockquote>|</pre>|</h[1-6]>",
      with: "\n", options: [.regularExpression, .caseInsensitive]
    )
    text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    text = decodeEntities(text)
    let lines = text.components(separatedBy: "\n").map {
      $0.trimmingCharacters(in: .whitespaces)
    }
    return lines.joined(separator: "\n")
      .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func decodeEntities(_ text: String) -> String {
    var out = text
    let named: [(String, String)] = [
      ("&nbsp;", "\u{00A0}"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
      ("&#39;", "'"), ("&apos;", "'"), ("&amp;", "&"),
    ]
    // Numeric first so an encoded ampersand cannot form a new entity.
    if let regex = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]{1,6}|[0-9]{1,7});") {
      let matches = regex.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed()
      for match in matches {
        guard let whole = Range(match.range, in: out), let group = Range(match.range(at: 1), in: out) else { continue }
        let code = out[group]
        let value = code.hasPrefix("x") ? UInt32(code.dropFirst(), radix: 16) : UInt32(code)
        if let value, let scalar = Unicode.Scalar(value) {
          out.replaceSubrange(whole, with: String(Character(scalar)))
        }
      }
    }
    for (entity, replacement) in named {
      out = out.replacingOccurrences(of: entity, with: replacement)
    }
    return out
  }

  static func localpart(of userId: String) -> String {
    let trimmed = userId.hasPrefix("@") ? String(userId.dropFirst()) : userId
    return trimmed.split(separator: ":", maxSplits: 1).first.map(String.init) ?? trimmed
  }
}
