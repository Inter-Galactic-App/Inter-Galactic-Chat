import CryptoKit
import Intents
import MobileCoreServices
import UIKit
import UniformTypeIdentifiers

/// Share Extension entry point.
///
/// This process is not the app. It cannot reach the app's sandbox, cannot send
/// a Matrix event, and is killed as soon as `completeRequest` returns. All it
/// does is copy the shared items into the App Group staging root and write a
/// manifest the host can read.
///
/// **Host launch is best effort only.** After the manifest is staged the
/// extension tries to open `space.ourgalaxy://share/v1/<token>` by walking the
/// responder chain to `UIApplication`. REVIEW blocked that on 2026-08-02 and
/// withdrew the block on 2026-08-03 after the owner supplied Element X as a
/// production precedent; it is still not a documented Apple Share Extension
/// API, and Apple DTS describes direct containing-app launch as unsupported and
/// compatibility-sensitive.
///
/// So the launch is never load-bearing. A false result, a missing
/// `UIApplication` responder, dismissal, or process death must all leave the
/// staged session UNACKNOWLEDGED and available to the host's startup/resume
/// drain, which remains the authoritative delivery contract. The session is
/// never deleted because a launch attempt failed.
///
/// Contracts it must satisfy, all enforced on the host side too:
/// - stage under `<app group>/inbound-share/<token>/`
/// - `manifest.json`, `schemaVersion` 1, with **bare-name** file references
///   (`IosInboundShareStager` drops anything nested or absolute)
/// - the manifest is written **last and atomically**: its presence is what
///   marks a session ready for pickup, so a half-staged session is never
///   offered
final class ShareViewController: UIViewController {
  private let appGroup = "group.chat.intergalactic.app"
  private let stagingDirectory = "inbound-share"
  private let manifestName = "manifest.json"

  /// Matches the host's limits so an oversized share fails here, where the
  /// user is still in the share sheet, rather than after the app launches.
  private let maxItems = 20
  private let maxSessionBytes = 250 * 1024 * 1024

  private var sessionRoot: URL?

  // MARK: - Status UI
  //
  // The extension previously showed nothing at all: the sheet dismissed with no
  // confirmation, so a share that worked was indistinguishable from one that
  // did nothing. That is the jarring part, not the absence of an app launch -
  // most share extensions never launch their host either, they just tell you
  // what happened. This is a status card, not a compose UI.

  private let card = UIView()
  private let spinner = UIActivityIndicatorView(style: .medium)
  private let label = UILabel()

  override func viewDidLoad() {
    super.viewDidLoad()
    installStatusCard()
    stageAndHandOff()
  }

  private func installStatusCard() {
    view.backgroundColor = UIColor.black.withAlphaComponent(0.25)

    card.backgroundColor = .secondarySystemBackground
    card.layer.cornerRadius = 14
    card.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(card)

    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.startAnimating()
    card.addSubview(spinner)

    label.text = "Saving to Inter Galactic\u{2026}"
    label.font = .preferredFont(forTextStyle: .callout)
    label.adjustsFontForContentSizeCategory = true
    label.numberOfLines = 0
    label.textAlignment = .center
    label.textColor = .label
    label.translatesAutoresizingMaskIntoConstraints = false
    card.addSubview(label)

    NSLayoutConstraint.activate([
      card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      card.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 40),
      card.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -40),
      spinner.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
      spinner.centerXAnchor.constraint(equalTo: card.centerXAnchor),
      label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 14),
      label.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 22),
      label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -22),
      label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22),
    ])
  }

  /// Shows a final message briefly, then dismisses.
  ///
  /// The delay is short enough not to feel like a wait and long enough to read.
  /// `completeRequest` is always called, so a failure here can never strand the
  /// share sheet.
  private func finish(message: String, cancelled: Bool) {
    DispatchQueue.main.async {
      self.spinner.stopAnimating()
      self.spinner.isHidden = true
      self.label.text = message
      DispatchQueue.main.asyncAfter(deadline: .now() + (cancelled ? 1.4 : 0.9)) {
        if cancelled {
          self.cancel()
        } else {
          self.extensionContext?.completeRequest(returningItems: nil)
        }
      }
    }
  }

  // MARK: - Staging

  private func stageAndHandOff() {
    guard
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: appGroup
      )
    else {
      // Without the App Group there is nowhere the host can read from. Fail
      // closed rather than staging somewhere it will never look.
      NSLog("intergalactic_ios_share_ext event=no_app_group")
      return finish(message: "Couldn't share to Inter Galactic.", cancelled: true)
    }

    let attachments = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
      .flatMap { $0.attachments ?? [] }
    guard !attachments.isEmpty, attachments.count <= maxItems else {
      NSLog("intergalactic_ios_share_ext event=rejected reason=item_count count=%d", attachments.count)
      return finish(
        message: attachments.isEmpty
          ? "Nothing to share."
          : "Too many items - share up to \(maxItems) at once.",
        cancelled: true
      )
    }

    let token = makeToken()
    let root = container
      .appendingPathComponent(stagingDirectory, isDirectory: true)
      .appendingPathComponent(token, isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    } catch {
      NSLog("intergalactic_ios_share_ext event=staging_failed")
      return finish(message: "Couldn't share to Inter Galactic.", cancelled: true)
    }
    sessionRoot = root

    load(attachments: attachments) { [weak self] body, items in
      guard let self = self else { return }
      guard items.contains(where: { $0["failure"] == nil }) || body != nil else {
        // Nothing usable came through. Release staging rather than launching
        // the host into an empty review sheet.
        NSLog("intergalactic_ios_share_ext event=rejected reason=no_usable_items")
        return self.finish(message: "Nothing could be shared.", cancelled: true)
      }
      // Fail closed: if the manifest cannot be written there is nothing the
      // host could read, so the session is removed rather than left as staged
      // bytes with no way to pick them up.
      guard self.writeManifest(root: root, body: body, items: items) else {
        return self.finish(message: "Couldn't share to Inter Galactic.", cancelled: true)
      }
      NSLog("intergalactic_ios_share_ext event=session_staged items=%d", items.count)
      // Best effort, after the manifest is durable. Whatever happens here, the
      // session stays staged for the drain.
      // The message differs because the next user action differs, so it waits
      // for the real launch result rather than assuming one.
      self.attemptHostLaunch(token: token) { launched in
        self.finish(
          message: launched
            ? "Saved \u{2014} opening Inter Galactic\u{2026}"
            : "Saved. Open Inter Galactic to choose where to send.",
          cancelled: false
        )
      }
    }
  }

  /// Loads every provider, then reports once. Providers complete on arbitrary
  /// queues and out of order, so results are keyed by index and the order the
  /// user selected is preserved rather than the order they happened to finish.
  private func load(
    attachments: [NSItemProvider],
    completion: @escaping (String?, [[String: Any?]]) -> Void
  ) {
    var staged = [Int: [String: Any?]](minimumCapacity: attachments.count)
    var body: String?
    var totalBytes = 0
    // One image can arrive as several providers - Photos and Files commonly
    // offer the same picture in more than one representation - and each of
    // those now classifies as a file. Staging both put the same photo in the
    // review twice. Content hashing collapses them, which is representation-
    // agnostic: whatever combination a source app offers, identical bytes are
    // staged once. QA, 2026-08-03.
    var seenDigests = Set<String>()
    let group = DispatchGroup()
    let lock = NSLock()

    for (index, provider) in attachments.enumerated() {
      group.enter()
      loadItem(provider, index: index) { text, name, data, mime, failure in
        lock.lock()
        defer {
          lock.unlock()
          group.leave()
        }
        if let text = text {
          // Plain text and URLs become the message body, not attachments.
          body = body.map { "\($0)\n\(text)" } ?? text
          return
        }
        guard let data = data, failure == nil else {
          staged[index] = [
            "name": name,
            "failure": failure ?? "Could not read shared content.",
          ]
          return
        }
        if totalBytes + data.count > self.maxSessionBytes {
          staged[index] = ["name": name, "failure": "Shared content exceeds 250 MiB per share."]
          return
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard seenDigests.insert(digest).inserted else {
          // Same bytes already staged from another representation. Skipping
          // leaves no entry for this index, and the manifest is built from the
          // entries that exist.
          NSLog("intergalactic_ios_share_ext event=duplicate_representation_skipped")
          return
        }
        // Bare name only. The manifest reader rejects anything nested or
        // absolute, so the file name is the contract.
        let fileName = String(format: "item_%03d.bin", index)
        do {
          try data.write(to: self.sessionRoot!.appendingPathComponent(fileName), options: .atomic)
          totalBytes += data.count
          staged[index] = [
            "name": name,
            "file": fileName,
            "size": data.count,
            "mimeType": mime,
          ]
        } catch {
          staged[index] = ["name": name, "failure": "Could not stage shared content."]
        }
      }
    }

    group.notify(queue: .main) {
      let ordered = attachments.indices.compactMap { staged[$0] }
      completion(body, ordered)
    }
  }

  private func loadItem(
    _ provider: NSItemProvider,
    index: Int,
    completion: @escaping (String?, String, Data?, String?, String?) -> Void
  ) {
    let fallbackName = provider.suggestedName ?? "shared-file"

    switch ShareItemClassifier.kind(for: provider.registeredTypeIdentifiers) {
    case .link:
      provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
        guard let url = item as? URL else {
          completion(nil, fallbackName, nil, nil, "Could not read shared link.")
          return
        }
        // Belt and braces: a file URL is content, not a link, even if the type
        // identifiers suggested otherwise.
        guard !url.isFileURL else {
          completion(nil, url.lastPathComponent, try? Data(contentsOf: url), nil, nil)
          return
        }
        completion(url.absoluteString, fallbackName, nil, nil, nil)
      }
    case .text:
      provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
        completion(item as? String, fallbackName, nil, nil, nil)
      }
    case .file:
      // loadFileRepresentation gives a URL valid only inside the closure, which
      // is precisely why the bytes are copied rather than the path recorded.
      let type = provider.registeredTypeIdentifiers.first ?? UTType.data.identifier
      provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
        guard let url = url, error == nil else {
          completion(nil, fallbackName, nil, nil, error?.localizedDescription ?? "Could not read shared item.")
          return
        }
        let name = url.lastPathComponent.isEmpty ? fallbackName : url.lastPathComponent
        do {
          let data = try Data(contentsOf: url)
          let mime = UTType(type)?.preferredMIMEType
          completion(nil, name, data, mime, nil)
        } catch {
          completion(nil, name, nil, nil, "Could not read shared item.")
        }
      }
    }
  }

  /// The conversation the user picked in the share sheet, when there was one.
  ///
  /// iOS supplies an `INSendMessageIntent` when the share was started from a
  /// suggested conversation, and its `conversationIdentifier` is the room id the
  /// app donated. This is the Element X behaviour: share straight into that
  /// room instead of asking again.
  ///
  /// It rides in the MANIFEST, never in the handoff URL - REVIEW's contract is
  /// that only the opaque token may appear there, and a room id is exactly the
  /// destination data that must not leak into a URL other apps could observe.
  ///
  /// Note this stays nil until the app donates interactions; without donation
  /// iOS has no suggestion to offer and never populates the intent.
  private func preselectedConversationId() -> String? {
    guard let intent = extensionContext?.intent as? INSendMessageIntent else { return nil }
    guard let id = intent.conversationIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
      !id.isEmpty
    else { return nil }
    return id
  }

  private func writeManifest(root: URL, body: String?, items: [[String: Any?]]) -> Bool {
    var manifest: [String: Any] = [
      "schemaVersion": 1,
      "items": items.map { entry in
        entry.compactMapValues { $0 }
      },
    ]
    if let conversation = preselectedConversationId() {
      manifest["conversationId"] = conversation
      NSLog("intergalactic_ios_share_ext event=preselected_conversation")
    }
    if let body = body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      manifest["body"] = body
    }
    guard
      let data = try? JSONSerialization.data(withJSONObject: manifest, options: [])
    else {
      NSLog("intergalactic_ios_share_ext event=manifest_encode_failed")
      return false
    }
    do {
      try data.write(to: root.appendingPathComponent(manifestName), options: .atomic)
      return true
    } catch {
      // Previously `try?`, which discarded the failure and handed the host a
      // token for a session it could never read. REVIEW P1, 2026-08-02.
      NSLog("intergalactic_ios_share_ext event=manifest_write_failed")
      return false
    }
  }

  /// Tries to foreground the containing app. Never fails the share.
  ///
  /// `UIApplication.shared` is unavailable to extensions, so the responder
  /// chain is walked to reach it. This is the Element X pattern. It is a
  /// convenience: the staged session is already complete and the host will
  /// present it on the next open regardless of what happens here.
  /// Tries to foreground the containing app. Never fails the share.
  ///
  /// Reports through `completion` whether the app was actually asked to open,
  /// so the status card can tell the truth. An earlier revision returned true
  /// as soon as it found *any* responder answering `openURL:` and called that
  /// deprecated selector by `perform`, which reported success while nothing
  /// opened - QA, 2026-08-03.
  ///
  /// Two corrections: the walk now looks for a `UIApplication` specifically
  /// rather than anything that happens to respond to the selector, and it calls
  /// the current `open(_:options:completionHandler:)` and waits for the real
  /// result. `UIApplication.shared` is what extensions may not touch; an
  /// instance obtained from the responder chain is usable, which is the
  /// Element X pattern.
  private func attemptHostLaunch(token: String, completion: @escaping (Bool) -> Void) {
    guard let url = URL(string: "space.ourgalaxy://share/v1/\(token)") else {
      return completion(false)
    }
    var responder: UIResponder? = self
    while let current = responder {
      if let application = current as? UIApplication {
        application.open(url, options: [:]) { opened in
          NSLog(
            "intergalactic_ios_share_ext event=%@",
            opened ? "host_launch_opened" : "host_launch_refused"
          )
          completion(opened)
        }
        return
      }
      responder = current.next
    }
    // No UIApplication in the chain on this iOS version. Survivable by design:
    // the drain still delivers the share on the next manual open.
    NSLog("intergalactic_ios_share_ext event=host_launch_unavailable")
    completion(false)
  }

  private func makeToken() -> String {
    var bytes = [UInt8](repeating: 0, count: 16)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    return bytes.map { String(format: "%02x", $0) }.joined()
  }

  /// Cancels without sending, removing anything already staged.
  ///
  /// The plan requires a cancelled or failed share to leave nothing behind: the
  /// host only cleans up sessions it has claimed, and a session it never learns
  /// about would otherwise sit in the App Group forever.
  private func cancel() {
    if let root = sessionRoot {
      try? FileManager.default.removeItem(at: root)
    }
    extensionContext?.completeRequest(returningItems: nil)
  }
}
